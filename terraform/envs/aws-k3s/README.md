# AWS K3s Lab

AWS 上的 K3s 叢集：1 台 Control Plane + 2 台 Worker Node，透過 Tailscale VPN 管理，Elastic IP 確保 kubeconfig 穩定。

## ⚠️ 免責聲明

> **本專案僅供個人學習與實驗用途，不建議直接用於生產環境。**

## 架構

```
AWS us-east-1 VPC (10.1.0.0/16)
  │
  ├─ my-cp         (t3.medium, 2vCPU/4GB) ← Control Plane + EIP
  ├─ my-worker-1   (t3.small,  1vCPU/2GB) ← Worker
  └─ my-worker-2   (t3.small,  1vCPU/2GB) ← Worker

SSM Parameter Store
  ├─ /k3s-lab/tailscale-auth-key  (SecureString, 手動建立)
  └─ /k3s-lab/node-token          (SecureString, CP 自動寫入)

所有節點 ←→ Tailscale VPN ←→ 本機
```

## 費用估算

| 資源 | 費用/hr |
|------|---------|
| CP (t3.medium) | $0.0416 |
| Worker × 2 (t3.small) | $0.0416（合計） |
| EIP（開機中） | 免費 |
| **合計（開機中）** | **~$0.083/hr (~$60/月)** |

> 不使用時執行 `aws ec2 stop-instances` 停機，EIP 閒置收 $0.005/hr。

## 前置需求

- [Terraform](https://www.terraform.io/downloads) >= 1.6.0
- [AWS CLI](https://aws.amazon.com/cli/) 已配置（`aws configure`）
- [Tailscale](https://tailscale.com/) 帳號
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## 快速開始

### 1. 產生緊急 SSH 金鑰

```bash
mkdir -p ./.ssh
ssh-keygen -t ed25519 -f ./.ssh/aws_emergency_ed25519 -N ""
```

### 2. 建立 SSM 參數（apply 前必做）

```bash
aws ssm put-parameter \
  --name "/k3s-lab/tailscale-auth-key" \
  --value "tskey-auth-REPLACE_ME" \
  --type SecureString \
  --region us-east-1
```

### 3. 設定變數

```bash
cp terraform.tfvars.example terraform.tfvars
# 依需求調整 cp_hostname、worker_hostname_prefix 等
```

### 4. 部署

```bash
terraform init
terraform fmt && terraform validate
terraform plan
terraform apply
```

### 5. 等待 cloud-init 完成（約 3-5 分鐘）

```bash
terraform output next_steps
```

### 6. 取得 kubeconfig

```bash
EIP=$(terraform output -raw aws_eip_public_ip)
tailscale ssh ubuntu@my-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
  > kubeconfig/k3s-aws.yaml
```

### 7. 驗證叢集

```bash
KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

# 預期輸出
# NAME         STATUS   ROLES                  AGE
# my-cp        Ready    control-plane,master   Xm
# my-worker-1  Ready    <none>                 Xm
# my-worker-2  Ready    <none>                 Xm
```

## 日常操作

### 關機 / 開機

```bash
# 停止全部 3 台（省費）
aws ec2 stop-instances \
  --instance-ids \
    $(terraform output -raw aws_instance_id) \
    $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ') \
  --region us-east-1

# 啟動
aws ec2 start-instances \
  --instance-ids \
    $(terraform output -raw aws_instance_id) \
    $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ') \
  --region us-east-1
```

### 使用 kubectl

```bash
export KUBECONFIG=$(pwd)/kubeconfig/k3s-aws.yaml
kubectl get nodes
kubectl get pods -A
```

### 銷毀資源

```bash
terraform destroy

# destroy 後清理 SSM
aws ssm delete-parameter --name "/k3s-lab/node-token" --region us-east-1
aws ssm delete-parameter --name "/k3s-lab/tailscale-auth-key" --region us-east-1
```

## 疑難排解

| 症狀 | 解法 |
|------|------|
| Worker 無法加入叢集 | CP 可能尚未完成啟動，等 3-5 分鐘；或查 CP console output |
| Tailscale 連不上 | 確認 SSM `/k3s-lab/tailscale-auth-key` 存在且未過期 |
| kubeconfig 連不上 | 確認使用 EIP（`terraform output aws_eip_public_ip`），非動態 public IP |
| K3s 未安裝 | `aws ec2 get-console-output --instance-id <id> --region us-east-1` |
| SSM 拒絕存取 | 確認 IAM instance profile 已掛載 |
| EIP 費用持續產生 | 停機後 EIP 閒置仍計費；長期不用請 `terraform destroy` |

---

**詳細建置記錄**：[docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md)
