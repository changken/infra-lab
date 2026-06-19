# K3s Multi-Node Cluster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 aws-k3s 模組的 AWS 部分從單節點改為 1 control plane + 2 worker nodes，透過 SSM Parameter Store 自動傳遞 K3s token，Elastic IP 固定 CP public IP。

**Architecture:** CP 啟動後安裝 K3s server，將 node-token 寫入 SSM SecureString。Workers 以 IAM instance profile 輪詢 SSM 取得 token，透過 VPC 私有 IP 加入叢集。所有節點裝 Tailscale，EIP 確保 kubeconfig 在 stop/start 後仍有效。

**Tech Stack:** Terraform ~> 5.x (AWS provider)、K3s、Tailscale、AWS SSM Parameter Store、AWS EIP、Ubuntu 24.04 LTS

---

## File Map

| 檔案 | 動作 | 說明 |
|------|------|------|
| `variables.tf` | 修改 | 移除 `aws_instance_type`，新增 `cp_instance_type` / `worker_instance_type` / `worker_count` |
| `aws.tf` | 修改 | 新增 IAM / EIP / SG ingress；改名 CP instance；新增 worker instances |
| `user-data-aws.sh` | 刪除 | 由 `user-data-cp.sh` 取代 |
| `user-data-cp.sh` | 新增 | CP cloud-init：Tailscale + K3s server + 寫入 SSM |
| `user-data-worker.sh` | 新增 | Worker cloud-init：Tailscale + 輪詢 SSM + k3s agent |
| `outputs.tf` | 修改 | 更新 CP outputs；新增 EIP / worker outputs；修正 `next_steps` 內的資源引用 |
| `terraform.tfvars.example` | 修改 | 移除 `aws_instance_type`，新增 `cp_instance_type` / `worker_instance_type` |

---

## Task 1: 更新 variables.tf

**Files:**
- Modify: `variables.tf`

- [ ] **Step 1: 移除舊變數、新增三個新變數**

將 `variables.tf` 中的 `variable "aws_instance_type"` 區塊整段替換為：

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

- [ ] **Step 2: 格式化並驗證語法**

```bash
terraform fmt variables.tf
terraform validate
```

Expected: `Success! The configuration is valid.`
（此時 aws.tf 仍引用舊變數 `var.aws_instance_type`，validate 會報錯 — 正常，Task 4 修正）

- [ ] **Step 3: Commit**

```bash
git add variables.tf
git commit -m "feat(aws-k3s): replace aws_instance_type with cp/worker instance type variables"
```

---

## Task 2: 建立 user-data-cp.sh

**Files:**
- Create: `user-data-cp.sh`
- Delete: `user-data-aws.sh`

- [ ] **Step 1: 建立 user-data-cp.sh**

新增檔案 `user-data-cp.sh`，內容如下：

```bash
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Starting K3s control plane setup at $(date)"
echo "========================================="

# Set hostname
hostnamectl set-hostname "${hostname}"

# Update system
echo "[1/4] Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Tailscale
echo "[2/4] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up \
  --authkey="${tailscale_auth_key}" \
  --ssh \
  --hostname="${hostname}" \
  --accept-routes

# Install K3s server (use EIP for TLS SAN)
echo "[3/4] Installing K3s server..."
PUBLIC_IP="${public_ip}"
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san "$PUBLIC_IP" \
  --node-external-ip "$PUBLIC_IP" \
  --node-name "${hostname}"

# Wait for K3s to generate node token, then write to SSM
echo "[4/4] Writing node token to SSM..."
until [ -f /var/lib/rancher/k3s/server/node-token ]; do
  echo "Waiting for K3s token file..."
  sleep 2
done

aws ssm put-parameter \
  --name "/k3s-lab/node-token" \
  --value "$(cat /var/lib/rancher/k3s/server/node-token)" \
  --type SecureString \
  --region "${aws_region}" \
  --overwrite

echo "========================================="
echo "Setup complete at $(date)"
echo "EIP: ${public_ip}"
echo "To get kubeconfig:"
echo "  tailscale ssh ubuntu@${hostname} 'sudo cat /etc/rancher/k3s/k3s.yaml'"
echo "========================================="
```

- [ ] **Step 2: Commit**

```bash
git add user-data-cp.sh
git commit -m "feat(aws-k3s): add control plane cloud-init script with EIP and SSM token write"
```

> `user-data-aws.sh` 暫時保留，在 Task 7 更新 `aws.tf` 引用後再一起刪除，避免中間狀態驗證失敗。

---

## Task 3: 建立 user-data-worker.sh

**Files:**
- Create: `user-data-worker.sh`

- [ ] **Step 1: 建立 user-data-worker.sh**

新增檔案 `user-data-worker.sh`，內容如下：

```bash
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Starting K3s worker setup at $(date)"
echo "========================================="

# Set hostname
hostnamectl set-hostname "${hostname}"

# Update system
echo "[1/4] Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Tailscale
echo "[2/4] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up \
  --authkey="${tailscale_auth_key}" \
  --ssh \
  --hostname="${hostname}" \
  --accept-routes

# Poll SSM for K3s token (max 10 minutes: 60 retries x 10s)
echo "[3/4] Waiting for K3s token from SSM..."
TOKEN=""
for i in $(seq 1 60); do
  TOKEN=$(aws ssm get-parameter \
    --name "/k3s-lab/node-token" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "${aws_region}" 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then
    echo "Token received on attempt $i"
    break
  fi
  echo "Waiting for K3s token... ($i/60)"
  sleep 10
done

if [ -z "$TOKEN" ]; then
  echo "ERROR: timed out waiting for K3s token after 10 minutes"
  exit 1
fi

# Join K3s cluster via CP private IP
echo "[4/4] Joining K3s cluster..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${cp_private_ip}:6443" \
  K3S_TOKEN="$TOKEN" \
  sh -s - agent \
  --node-name "${hostname}"

echo "========================================="
echo "Setup complete at $(date)"
echo "Node ${hostname} joined cluster at ${cp_private_ip}"
echo "========================================="
```

- [ ] **Step 2: Commit**

```bash
git add user-data-worker.sh
git commit -m "feat(aws-k3s): add worker node cloud-init script with SSM token polling"
```

---

## Task 4: 更新 aws.tf — Security Group + Data Sources

**Files:**
- Modify: `aws.tf`

- [ ] **Step 1: 在 aws.tf 頂部新增 data source**

在 `aws.tf` 第一行（`# ===...` 注解前）插入：

```hcl
data "aws_caller_identity" "current" {}
```

- [ ] **Step 2: 更新 Security Group，新增四條 ingress 規則**

在 `aws_security_group.k3s` 的 `egress` 區塊之後，新增以下四個 `ingress` 區塊：

```hcl
  # K3s API server — inter-node (self) and kubectl from outside
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
    description = "K3s API server (inter-node)"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "K3s API server (kubectl access)"
  }

  # Flannel VXLAN — pod network overlay
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
    description = "Flannel VXLAN (pod network)"
  }

  # Kubelet — health checks between nodes
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet metrics"
  }
```

- [ ] **Step 3: 格式化並驗證**

```bash
terraform fmt aws.tf
terraform validate
```

Expected: 仍有 `var.aws_instance_type` 錯誤，正常，Task 5 修正。

- [ ] **Step 4: Commit**

```bash
git add aws.tf
git commit -m "feat(aws-k3s): add inter-node and kubectl ingress rules to security group"
```

---

## Task 5: 更新 aws.tf — IAM Role + Instance Profile

**Files:**
- Modify: `aws.tf`

- [ ] **Step 1: 在 Security Group 資源之後新增 IAM 資源**

```hcl
# ============================================================================
# IAM Role for K3s nodes (SSM Parameter Store access)
# ============================================================================

resource "aws_iam_role" "k3s_node" {
  name = "my-k3s-lab-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "my-k3s-lab-node-role"
    Project = "k3s-lab"
  }
}

resource "aws_iam_role_policy" "k3s_ssm" {
  name = "my-k3s-lab-ssm-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:DeleteParameter"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/k3s-lab/node-token"
    }]
  })
}

resource "aws_iam_instance_profile" "k3s_node" {
  name = "my-k3s-lab-node-profile"
  role = aws_iam_role.k3s_node.name

  tags = {
    Name    = "my-k3s-lab-node-profile"
    Project = "k3s-lab"
  }
}
```

- [ ] **Step 2: 格式化並驗證**

```bash
terraform fmt aws.tf
terraform validate
```

Expected: 仍有 `var.aws_instance_type` 錯誤，正常。

- [ ] **Step 3: Commit**

```bash
git add aws.tf
git commit -m "feat(aws-k3s): add IAM role and instance profile for SSM Parameter Store access"
```

---

## Task 6: 更新 aws.tf — Elastic IP

**Files:**
- Modify: `aws.tf`

- [ ] **Step 1: 在 IAM 資源之後新增 EIP 資源**

```hcl
# ============================================================================
# Elastic IP for K3s control plane (stable public IP for kubeconfig)
# ============================================================================

resource "aws_eip" "k3s_cp" {
  domain = "vpc"

  tags = {
    Name    = "my-k3s-lab-cp-eip"
    Project = "k3s-lab"
  }
}
```

> `aws_eip_association` 會在 Task 7 中與 CP instance 一起新增。

- [ ] **Step 2: 格式化並驗證**

```bash
terraform fmt aws.tf
terraform validate
```

- [ ] **Step 3: Commit**

```bash
git add aws.tf
git commit -m "feat(aws-k3s): add Elastic IP for control plane stable public IP"
```

---

## Task 7: 更新 aws.tf — 改名 CP Instance

**Files:**
- Modify: `aws.tf`

> ⚠️ 此 task 將 `aws_instance.k3s` 改名為 `aws_instance.k3s_cp`。若 state 中已有資源，`terraform apply` 會 destroy 舊 instance 並建新 instance。請確認現有 EC2 無需保留資料。

- [ ] **Step 1: 將 `aws_instance.k3s` 整段替換為 `aws_instance.k3s_cp`**

找到 `resource "aws_instance" "k3s"` 區塊，整段替換為：

```hcl
resource "aws_instance" "k3s_cp" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.cp_instance_type
  key_name      = aws_key_pair.emergency.key_name

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.k3s_node.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 64
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name    = "my-k3s-cp-root"
      Project = "k3s-lab"
    }
  }

  user_data = templatefile("${path.module}/user-data-cp.sh", {
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = "k3s-cp"
    aws_region         = var.aws_region
    public_ip          = aws_eip.k3s_cp.public_ip
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name    = "my-k3s-cp"
    Project = "k3s-lab"
  }
}

resource "aws_eip_association" "k3s_cp" {
  instance_id   = aws_instance.k3s_cp.id
  allocation_id = aws_eip.k3s_cp.id
}
```

- [ ] **Step 2: 格式化並驗證**

```bash
terraform fmt aws.tf
terraform validate
```

Expected: `Success! The configuration is valid.`（`var.aws_instance_type` 錯誤應已消失）

- [ ] **Step 3: 刪除舊 user-data-aws.sh（現在 aws.tf 已不再引用它）**

```bash
git rm user-data-aws.sh
```

- [ ] **Step 4: Commit**

```bash
git add aws.tf
git commit -m "feat(aws-k3s): rename k3s instance to k3s_cp, attach IAM profile and EIP, use user-data-cp.sh"
```

---

## Task 8: 更新 aws.tf — 新增 Worker Instances

**Files:**
- Modify: `aws.tf`

- [ ] **Step 1: 在 `aws_eip_association.k3s_cp` 之後新增 worker instances**

```hcl
# ============================================================================
# K3s Worker Nodes
# ============================================================================

resource "aws_instance" "k3s_worker" {
  count = var.worker_count

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  key_name      = aws_key_pair.emergency.key_name

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.k3s_node.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 32
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name    = "my-k3s-worker-${count.index}-root"
      Project = "k3s-lab"
    }
  }

  user_data = templatefile("${path.module}/user-data-worker.sh", {
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = "k3s-worker-${count.index}"
    aws_region         = var.aws_region
    cp_private_ip      = aws_instance.k3s_cp.private_ip
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  depends_on = [aws_instance.k3s_cp]

  tags = {
    Name    = "my-k3s-worker-${count.index}"
    Project = "k3s-lab"
  }
}
```

- [ ] **Step 2: 格式化並驗證**

```bash
terraform fmt aws.tf
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add aws.tf
git commit -m "feat(aws-k3s): add worker node instances with SSM token polling and cluster join"
```

---

## Task 9: 更新 outputs.tf

**Files:**
- Modify: `outputs.tf`

- [ ] **Step 1: 更新所有 AWS outputs**

將 `outputs.tf` 中 `# AWS Outputs` 區塊之後的所有內容替換為：

```hcl
# AWS Outputs
output "aws_instance_id" {
  description = "AWS EC2 control plane instance ID"
  value       = aws_instance.k3s_cp.id
}

output "aws_instance_private_ip" {
  description = "AWS EC2 control plane private IP address"
  value       = aws_instance.k3s_cp.private_ip
}

output "aws_eip_public_ip" {
  description = "AWS EC2 control plane Elastic IP (stable public IP for kubeconfig)"
  value       = aws_eip.k3s_cp.public_ip
}

output "aws_instance_public_dns" {
  description = "AWS EC2 control plane public DNS name"
  value       = aws_instance.k3s_cp.public_dns
}

output "worker_instance_ids" {
  description = "AWS EC2 worker node instance IDs"
  value       = aws_instance.k3s_worker[*].id
}

output "worker_private_ips" {
  description = "AWS EC2 worker node private IP addresses"
  value       = aws_instance.k3s_worker[*].private_ip
}

output "worker_public_ips" {
  description = "AWS EC2 worker node public IP addresses"
  value       = aws_instance.k3s_worker[*].public_ip
}

# Instructions
output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ========================================
    Multi-Cloud K3s Lab Deployed!
    ========================================

    Azure VM:       ${azurerm_linux_virtual_machine.vm.name}
    AWS CP:         ${aws_instance.k3s_cp.id}
    AWS Workers:    ${join(", ", aws_instance.k3s_worker[*].id)}
    AWS EIP:        ${aws_eip.k3s_cp.public_ip}

    Next Steps:

    1. Wait for cloud-init to complete (~3-5 minutes):

       # Check CP (Azure Run Command not needed for AWS — use console output)
       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s_cp.id} \
         --region ${var.aws_region} | grep "Setup complete"

       # Check workers
       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s_worker[0].id} \
         --region ${var.aws_region} | grep "Setup complete"

    2. Check Tailscale devices:
       https://login.tailscale.com/admin/machines

       You should see:
       - k3s-cp (AWS control plane) ✓
       - k3s-worker-0 (AWS worker) ✓
       - k3s-worker-1 (AWS worker) ✓

    3. Get kubeconfig:
       EIP="${aws_eip.k3s_cp.public_ip}"
       tailscale ssh ubuntu@k3s-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
         | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
         > kubeconfig/k3s-aws.yaml

    4. Verify all nodes are Ready:
       KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

       Expected:
       NAME           STATUS   ROLES                  AGE
       k3s-cp         Ready    control-plane,master   Xm
       k3s-worker-0   Ready    <none>                 Xm
       k3s-worker-1   Ready    <none>                 Xm

    5. Stop instances to save cost when not in use:
       aws ec2 stop-instances \
         --instance-ids ${aws_instance.k3s_cp.id} ${join(" ", aws_instance.k3s_worker[*].id)} \
         --region ${var.aws_region}

    ========================================
    Troubleshooting:

    CP cloud-init log:
      aws ec2 get-console-output --instance-id ${aws_instance.k3s_cp.id} --region ${var.aws_region}

    Worker cloud-init log (Tailscale SSH):
      tailscale ssh ubuntu@k3s-worker-0 "tail -50 /var/log/user-data.log"

    SSM token check:
      aws ssm get-parameter --name /k3s-lab/node-token --with-decryption --region ${var.aws_region}

    Clean up SSM after destroy:
      aws ssm delete-parameter --name /k3s-lab/node-token --region ${var.aws_region}
    ========================================
  EOT
}
```

- [ ] **Step 2: 格式化並驗證**

```bash
terraform fmt outputs.tf
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add outputs.tf
git commit -m "feat(aws-k3s): update outputs for multi-node cluster with EIP and worker IPs"
```

---

## Task 10: 更新 terraform.tfvars.example

**Files:**
- Modify: `terraform.tfvars.example`

- [ ] **Step 1: 替換 AWS instance type 變數**

找到：
```hcl
# AWS EC2 instance type (t3.medium = 2 vCPU, 4 GB RAM)
aws_instance_type = "t3.medium"
```

替換為：
```hcl
# AWS EC2 instance type for control plane (t3.medium = 2 vCPU, 4 GB RAM)
cp_instance_type = "t3.medium"

# AWS EC2 instance type for worker nodes (t3.small = 1 vCPU, 2 GB RAM, cheaper)
worker_instance_type = "t3.small"

# Number of worker nodes (default: 2)
# worker_count = 2
```

- [ ] **Step 2: Commit**

```bash
git add terraform.tfvars.example
git commit -m "docs(aws-k3s): update tfvars example for multi-node variables"
```

---

## Task 11: 最終驗證

**Files:** 全部

- [ ] **Step 1: 完整格式化**

```bash
terraform fmt
```

Expected: 無輸出（代表所有檔案已符合格式）

- [ ] **Step 2: 完整驗證**

```bash
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: 執行 terraform plan 確認變更符合預期**

```bash
terraform plan
```

Expected plan 應顯示：
```
Plan: 10 to add, 2 to change, 1 to destroy.

# Resources to add (10):
+ aws_eip.k3s_cp
+ aws_eip_association.k3s_cp
+ aws_iam_instance_profile.k3s_node
+ aws_iam_role.k3s_node
+ aws_iam_role_policy.k3s_ssm
+ aws_instance.k3s_cp     (new name — recreate)
+ aws_instance.k3s_worker[0]
+ aws_instance.k3s_worker[1]

# Resources to change (2):
~ aws_security_group.k3s   (new ingress rules)
~ data.aws_ami.ubuntu       (refresh only)

# Resources to destroy (1):
- aws_instance.k3s          (old name, replaced by k3s_cp)
```

> 若 state 中沒有現有資源（從未 apply 過），plan 會顯示全部 add，無 destroy。

- [ ] **Step 4: 更新 agents.md 費用估算**

在 `agents.md` 的費用表格中，將舊的單節點費用更新為：

```markdown
| 資源 | 費用 |
|------|------|
| AWS CP (t3.medium) | ~$0.0416/hr |
| AWS Worker × 2 (t3.small) | ~$0.0416/hr (合計) |
| AWS EIP（開機中） | 免費 |
| Azure Standard_B2s | ~$0.042/hr (~$30/月) |
| **AWS 合計（開機中）** | **~$0.083/hr (~$60/月)** |
```

- [ ] **Step 5: 最終 Commit**

```bash
git add agents.md CLAUDE.md GEMINI.md
git commit -m "docs(aws-k3s): update cost estimates for multi-node cluster"
```
