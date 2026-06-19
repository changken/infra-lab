# K3s Multi-Node Cluster Design

**日期**: 2026-05-31
**狀態**: 待實作
**範圍**: `terraform/modules/aws-k3s` — AWS 部分改為 1 control plane + 2 worker nodes

## 背景

現有模組在 AWS 部署單節點 K3s（`aws_instance.k3s`，t3.medium）。本設計將 AWS 部分擴充為三節點叢集，Azure 部分維持不變。

## 目標

- 1 台 control plane + 2 台 worker nodes，全在同一 AWS VPC/Subnet
- 純 Terraform IaC，`terraform apply` 一次完成所有節點的建立與加入
- Control plane 使用 Elastic IP，kubeconfig 在 stop/start 後仍有效
- 所有節點裝 Tailscale，可從外部 SSH 個別進入 debug
- Workers 透過 SSM Parameter Store 取得 K3s token，自動加入叢集

## 架構

```
AWS us-east-1 VPC (10.1.0.0/16)
  │
  ├─ Subnet 10.1.1.0/24
  │    ├─ EC2: k3s-cp       (aws_instance.k3s_cp)        ← control plane
  │    ├─ EC2: k3s-worker-0 (aws_instance.k3s_worker[0]) ← worker
  │    └─ EC2: k3s-worker-1 (aws_instance.k3s_worker[1]) ← worker
  │
  ├─ Elastic IP → k3s-cp (固定 public IP，kubectl 用)
  │
  └─ SSM Parameter Store
       └─ /k3s-lab/node-token (SecureString)
            ├─ CP 啟動後寫入
            └─ Workers 輪詢讀取，加入叢集

所有節點 ←→ Tailscale VPN ←→ 本機
```

**啟動順序：**
1. Terraform 分配 EIP → 建 CP instance（EIP 注入 user_data）→ 關聯 EIP
2. Terraform 建 2 台 worker（depends_on CP instance）
3. CP cloud-init：安裝 Tailscale → 安裝 K3s server → 寫 token 至 SSM
4. Worker cloud-init：安裝 Tailscale → 輪詢 SSM（最多 10 分鐘）→ 讀 token → `k3s agent` 加入叢集

## 變更清單

### `variables.tf` — 新增

```hcl
variable "cp_instance_type" {
  description = "K3s control plane EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "K3s worker node EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
  default     = 2
}
```

現有 `aws_instance_type` 變數移除（由上兩個取代）。

### `aws.tf` — 異動摘要

| 資源 | 異動 |
|------|------|
| `aws_instance.k3s` | 改名為 `aws_instance.k3s_cp`；掛 IAM instance profile；user_data 改用 `user-data-cp.sh`；傳入 `public_ip = aws_eip.k3s_cp.public_ip`<br>⚠️ 改名會讓 Terraform 視為刪除舊 instance 並建新 instance（destroy + recreate），請確認現有 instance 無需保留資料 |
| `aws_security_group.k3s` | 新增三條 self-referencing ingress（6443/tcp、8472/udp、10250/tcp）；新增 6443/tcp 對外開放（kubectl）|
| `aws_key_pair.emergency` | 沿用，workers 共用同一 key pair |
| `aws_eip.k3s_cp` | 新增，分配 Elastic IP |
| `aws_eip_association.k3s_cp` | 新增，關聯 EIP 與 CP instance |
| `aws_iam_role.k3s_node` | 新增，EC2 assume role |
| `aws_iam_role_policy.k3s_ssm` | 新增，SSM 最小權限 policy |
| `aws_iam_instance_profile.k3s_node` | 新增，掛到 CP 和 workers |
| `aws_instance.k3s_worker` | 新增，count = var.worker_count；depends_on CP；user_data 使用 `user-data-worker.sh` |
| `data.aws_caller_identity` | 新增，取得 account ID 組 SSM ARN |

### IAM Policy（最小權限）

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:PutParameter",
    "ssm:GetParameter",
    "ssm:DeleteParameter"
  ],
  "Resource": "arn:aws:ssm:<region>:<account_id>:parameter/k3s-lab/node-token"
}
```

> Terraform 實作時 `<region>` 用 `var.aws_region`，`<account_id>` 用 `data.aws_caller_identity.current.account_id` 動態取得。

### Security Group 新增 Ingress

```hcl
# 節點間通訊（self-referencing）
ingress { port = 6443, protocol = tcp, self = true }  # K3s API
ingress { port = 8472, protocol = udp, self = true }  # Flannel VXLAN
ingress { port = 10250, protocol = tcp, self = true } # Kubelet

# 本機 kubectl 連線
ingress { port = 6443, protocol = tcp, cidr = "0.0.0.0/0" }
```

### `user-data-aws.sh` → `user-data-cp.sh`

新增邏輯：
- 接收 `${public_ip}` templatefile 變數（來自 EIP）
- 改用 `${public_ip}` 取代舊的 `tailscale ip -4`
- K3s 啟動後等待 token 檔案產生，寫入 SSM

```bash
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

hostnamectl set-hostname "${hostname}"

apt-get update && apt-get upgrade -y

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up --authkey="${tailscale_auth_key}" --ssh \
  --hostname="${hostname}" --accept-routes

# K3s server（使用 EIP）
PUBLIC_IP="${public_ip}"
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san "$PUBLIC_IP" \
  --node-external-ip "$PUBLIC_IP" \
  --node-name "${hostname}"

# 等待 token，寫入 SSM
until [ -f /var/lib/rancher/k3s/server/node-token ]; do sleep 2; done
aws ssm put-parameter \
  --name "/k3s-lab/node-token" \
  --value "$(cat /var/lib/rancher/k3s/server/node-token)" \
  --type SecureString \
  --region "${aws_region}" \
  --overwrite

echo "Setup complete at $(date)"
```

### `user-data-worker.sh`（新增）

```bash
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

hostnamectl set-hostname "${hostname}"

apt-get update && apt-get upgrade -y

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up --authkey="${tailscale_auth_key}" --ssh \
  --hostname="${hostname}" --accept-routes

# 輪詢 SSM token（最多 10 分鐘）
TOKEN=""
for i in $(seq 1 60); do
  TOKEN=$(aws ssm get-parameter \
    --name "/k3s-lab/node-token" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "${aws_region}" 2>/dev/null || true)
  [ -n "$TOKEN" ] && break
  echo "Waiting for K3s token... ($i/60)"
  sleep 10
done

[ -z "$TOKEN" ] && { echo "ERROR: timed out waiting for K3s token"; exit 1; }

# 加入叢集（透過 VPC 私有 IP）
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${cp_private_ip}:6443" \
  K3S_TOKEN="$TOKEN" \
  sh -s - agent --node-name "${hostname}"

echo "Setup complete at $(date)"
```

Terraform templatefile 注入：

```hcl
user_data = templatefile("${path.module}/user-data-worker.sh", {
  tailscale_auth_key = var.tailscale_auth_key
  hostname           = "k3s-worker-${count.index}"
  aws_region         = var.aws_region
  cp_private_ip      = aws_instance.k3s_cp.private_ip
})
```

### `outputs.tf` — 新增/修改

```hcl
output "aws_instance_id"         # 改為 k3s_cp
output "aws_eip_public_ip"       # 新增：EIP（穩定 IP）
output "worker_instance_ids"     # 新增：k3s_worker[*].id
output "worker_private_ips"      # 新增：k3s_worker[*].private_ip
```

> 現有 `next_steps` output 內引用 `aws_instance.k3s.id` 需一併更新為 `aws_instance.k3s_cp.id`。

## AMI

CP 和 workers 共用現有 `data.aws_ami.ubuntu`（Ubuntu 24.04 LTS，Canonical）。

## 費用估算

| 資源 | 規格 | 費用/hr |
|------|------|---------|
| CP (t3.medium) | 2 vCPU / 4 GB | $0.0416 |
| Worker × 2 (t3.small) | 1 vCPU / 2 GB | $0.0208 × 2 |
| EIP（instance 運行中）| — | 免費 |
| SSM Parameter Store | SecureString | < $0.01/月 |
| **合計（開機中）** | | **~$0.083/hr (~$60/月)** |

> 不使用時執行 `aws ec2 stop-instances` 停止全部 3 台以節省費用。

## 驗證方式

```bash
# 取得 kubeconfig
EIP=$(terraform output -raw aws_eip_public_ip)
tailscale ssh ubuntu@k3s-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
  > kubeconfig/k3s-aws.yaml

# 確認 3 個節點都 Ready
KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

# 預期輸出
# NAME           STATUS   ROLES                  AGE
# k3s-cp         Ready    control-plane,master   Xm
# k3s-worker-0   Ready    <none>                 Xm
# k3s-worker-1   Ready    <none>                 Xm
```

## 已知限制與風險

| 風險 | 說明 | 緩解 |
|------|------|------|
| Workers 啟動競態 | Worker cloud-init 在 CP 寫入 SSM 前就開始輪詢 | 輪詢最多 60 次 × 10s = 10 分鐘，足夠 CP 完成 |
| EIP 費用 | Instance 停止後 EIP 閒置收費 $0.005/hr | 長期停用時執行 `terraform destroy` 或手動釋放 EIP |
| 6443 對外開放 | kubectl port 對全網際網路開放 | 可將 cidr 改為自己的 IP `/32` |
| SSM token 殘留 | `terraform destroy` 不會自動刪除 SSM parameter | 需手動執行 `aws ssm delete-parameter --name /k3s-lab/node-token` 或加 `aws_ssm_parameter` lifecycle |
