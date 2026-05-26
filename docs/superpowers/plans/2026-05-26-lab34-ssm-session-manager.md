# Lab 34: SSM Session Manager + Patch Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `terraform/labs/34-ssm-session-manager/` — 一個填空式 lab，讓使用者學習 SSM Session Manager（零 SSH 連線）與 Patch Manager（自動掃描修補）。

**Architecture:** EC2（Amazon Linux 2023）放在 Public Subnet + IGW（零 NAT、零 VPC Endpoint，免費出站路徑），Security Group 完全無 inbound 規則（包含無 SSH 22 port），只透過 SSM Session Manager 建立互動式 shell。SSM Patch Manager 建立 Patch Baseline + Maintenance Window（rate 7 days）+ Target（EC2 tag）+ Task（AWS-RunPatchBaseline, Scan 模式），不做真實安裝，只掃描。

**Tech Stack:** Terraform >= 1.0, AWS Provider ~> 5.0, Amazon Linux 2023 (SSM Agent 預裝), AmazonSSMManagedInstanceCore

---

## File Map

```
terraform/labs/34-ssm-session-manager/
├── terraform.tf              # Provider 版本鎖定
├── variables.tf              # region, project, environment
├── locals.tf                 # common_tags
├── main.tf                   # 6 個 TODO（核心學習內容）
├── outputs.tf                # instance_id, patch_baseline_id, ssm 連線指令
├── terraform.tfvars.example  # 範例變數值
├── .gitignore                # *.tfvars, *.tfstate
└── README.md                 # 學習目標、架構、驗證腳本
```

---

## Task 1: 建立目錄與 boilerplate 檔案

**Files:**
- Create: `terraform/labs/34-ssm-session-manager/terraform.tf`
- Create: `terraform/labs/34-ssm-session-manager/variables.tf`
- Create: `terraform/labs/34-ssm-session-manager/locals.tf`
- Create: `terraform/labs/34-ssm-session-manager/terraform.tfvars.example`
- Create: `terraform/labs/34-ssm-session-manager/.gitignore`

- [ ] **Step 1: 建立目錄**

```bash
mkdir -p terraform/labs/34-ssm-session-manager
```

- [ ] **Step 2: 建立 terraform.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 3: 建立 variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "ssm-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

- [ ] **Step 4: 建立 locals.tf**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "34-ssm-session-manager"
    ManagedBy   = "terraform"
  }
}
```

- [ ] **Step 5: 建立 terraform.tfvars.example**

```hcl
region      = "us-east-1"
project     = "ssm-lab"
environment = "dev"
```

- [ ] **Step 6: 建立 .gitignore**

```gitignore
*.tfvars
*.tfstate
*.tfstate.backup
.terraform/
```

- [ ] **Step 7: Commit boilerplate**

```bash
git add terraform/labs/34-ssm-session-manager/
git commit -m "chore(labs): add lab 34 boilerplate files"
```

---

## Task 2: 建立 main.tf（6 個 TODO 填空骨架）

**Files:**
- Create: `terraform/labs/34-ssm-session-manager/main.tf`

- [ ] **Step 1: 建立 main.tf**

```hcl
#==============================================================
# 學習目標：SSM Session Manager + Patch Manager
#
# 核心問題：如何在完全沒有 SSH port 的情況下安全連進 EC2？
#
# Session Manager 原理（面試必考）：
#   EC2 上的 SSM Agent 主動建立出站 HTTPS 連線到 SSM 服務
#   → 不需任何 inbound port，不需 Bastion Host，不需 VPN
#   → 連線紀錄自動寫入 CloudTrail / CloudWatch（合規友善）
#
# Patch Manager 架構（4 個資源）：
#   aws_ssm_patch_baseline        → 定義哪些 CVE 等級要修補
#   aws_ssm_maintenance_window    → 定義維護排程（rate / cron）
#   aws_ssm_maintenance_window_target → 定義目標 EC2（tag 篩選）
#   aws_ssm_maintenance_window_task   → 定義執行的 SSM Document
#
# Public Subnet + IGW vs VPC Endpoint：
#   VPC Endpoint 需要 3 個（ssm、ec2messages、ssmmessages）
#   每個 $0.01/hr → lab 環境不必要
#   Public Subnet 提供免費出站路徑，EC2 需要 Public IP
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：動態取得 Amazon Linux 2023 最新 AMI
# Amazon Linux 2023 預裝 SSM Agent，不需額外安裝
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}


#--------------------------------------------------------------
# TODO 1: VPC + Public Subnet + IGW + Route Table
#--------------------------------------------------------------
# 文件 (vpc):                   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
# 文件 (subnet):                https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
# 文件 (internet_gateway):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
# 文件 (route_table):           https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
# 文件 (route_table_association): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
#
# [VPC]
#   cidr_block = "10.0.0.0/16"
#   tags       = local.common_tags
#
# [Subnet]
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.1.0/24"
#   map_public_ip_on_launch = true   # ← EC2 自動取得 Public IP，才能出站連 SSM
#   tags                    = local.common_tags
#
# [Internet Gateway]
#   vpc_id = aws_vpc.main.id
#   tags   = local.common_tags
#
# [Route Table]（Public 路由：0.0.0.0/0 → IGW）
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }
#   tags = local.common_tags
#
# [Route Table Association]
#   subnet_id      = aws_subnet.public.id
#   route_table_id = aws_route_table.public.id

resource "aws_vpc" "main" {
  # TODO
}

resource "aws_subnet" "public" {
  # TODO
}

resource "aws_internet_gateway" "main" {
  # TODO
}

resource "aws_route_table" "public" {
  # TODO
}

resource "aws_route_table_association" "public" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Security Group（無任何 inbound 規則，outbound HTTPS 443）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
#   name        = "${var.project}-ec2-sg"
#   description = "No inbound - SSM Session Manager only"
#   vpc_id      = aws_vpc.main.id
#   tags        = local.common_tags
#
# ⚠️ 注意：inbound 區塊完全不加（或留空 ingress = []）
#         這是本 lab 的核心重點：Security Group 零 inbound，SSH 22 完全關閉
#
# [Egress：HTTPS 443 到 SSM Endpoint]
#   egress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#     description = "HTTPS to SSM endpoints"
#   }

resource "aws_security_group" "ec2" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: IAM Role + Instance Profile（AmazonSSMManagedInstanceCore）
#--------------------------------------------------------------
# 文件 (role):             https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (policy_attachment): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
# 文件 (instance_profile): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
#
# [IAM Role]（EC2 使用）
#   name = "${var.project}-ec2-role"
#   tags = local.common_tags
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
# [Policy Attachment：SSM Core]
#   role       = aws_iam_role.ec2_ssm.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#   # ← 此受管政策包含 Session Manager + Patch Manager 所需全部 SSM 權限
#
# [Instance Profile]（將 Role 綁定給 EC2）
#   name = "${var.project}-ec2-profile"
#   role = aws_iam_role.ec2_ssm.name
#   tags = local.common_tags
#
# ⚠️ 注意：EC2 需要透過 Instance Profile 取得 Role，直接指定 Role ARN 不夠

resource "aws_iam_role" "ec2_ssm" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  # TODO
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  # TODO
}


#--------------------------------------------------------------
# TODO 4: EC2 Instance（Amazon Linux 2023, t3.micro）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
#
#   ami                    = data.aws_ami.amazon_linux_2023.id
#   instance_type          = "t3.micro"
#   subnet_id              = aws_subnet.public.id
#   vpc_security_group_ids = [aws_security_group.ec2.id]
#   iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
#   tags                   = merge(local.common_tags, {
#     Name       = "${var.project}-ssm-target"
#     PatchGroup = var.project   # ← Patch Manager Target 會用此 tag 篩選
#   })
#
# ⚠️ 注意：不要加 key_name（沒有 SSH key）、不要加 associate_public_ip_address
#         Public IP 由 Subnet 的 map_public_ip_on_launch = true 自動指派

resource "aws_instance" "ssm_target" {
  # TODO
}


#--------------------------------------------------------------
# TODO 5: SSM Patch Baseline（Amazon Linux 2023）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_patch_baseline
#
#   name             = "${var.project}-baseline"
#   description      = "Patch baseline for Amazon Linux 2023"
#   operating_system = "AMAZON_LINUX_2023"
#   tags             = local.common_tags
#
#   approval_rule {
#     approve_after_days = 7   # ← 修補釋出 7 天後自動核准
#     compliance_level   = "HIGH"
#
#     patch_filter {
#       key    = "PRODUCT"
#       values = ["AmazonLinux2023"]
#     }
#
#     patch_filter {
#       key    = "CLASSIFICATION"
#       values = ["Security", "Bugfix"]
#     }
#
#     patch_filter {
#       key    = "SEVERITY"
#       values = ["Critical", "Important"]
#     }
#   }

resource "aws_ssm_patch_baseline" "amazon_linux_2023" {
  # TODO
}


#--------------------------------------------------------------
# TODO 6: Maintenance Window + Target + Task（每 7 天掃描）
#--------------------------------------------------------------
# 文件 (window):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window
# 文件 (target):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_target
# 文件 (task):    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_task
#
# [Maintenance Window]
#   name              = "${var.project}-window"
#   schedule          = "rate(7 days)"   # ← lab 使用 rate 語法；生產環境常用 cron
#   duration          = 2                # ← 維護視窗持續 2 小時
#   cutoff            = 1                # ← 截止前 1 小時停止啟動新任務
#   allow_unassociated_targets = false
#   tags              = local.common_tags
#
# [Window Target]（指定要修補的 EC2）
#   window_id     = aws_ssm_maintenance_window.weekly.id
#   name          = "${var.project}-target"
#   resource_type = "INSTANCE"
#
#   targets {
#     key    = "tag:PatchGroup"       # ← 比對 EC2 tag PatchGroup
#     values = [var.project]          # ← 只有 PatchGroup = "ssm-lab" 的 EC2
#   }
#
# [Window Task]（執行 Patch Scan）
#   window_id        = aws_ssm_maintenance_window.weekly.id
#   name             = "${var.project}-patch-scan"
#   task_arn         = "arn:aws:ssm:${var.region}::document/AWS-RunPatchBaseline"
#   task_type        = "RUN_COMMAND"
#   service_role_arn = aws_iam_role.ec2_ssm.arn
#   priority         = 1
#   max_concurrency  = "1"
#   max_errors       = "1"
#
#   targets {
#     key    = "WindowTargetIds"
#     values = [aws_ssm_maintenance_window_target.ec2.id]
#   }
#
#   task_invocation_parameters {
#     run_command_parameters {
#       document_version = "$DEFAULT"
#
#       parameter {
#         name   = "Operation"
#         values = ["Scan"]   # ← Scan 只檢查不安裝；生產環境改 "Install"
#       }
#     }
#   }
#
# ⚠️ 注意：task_arn 的 document ARN 格式為
#          arn:aws:ssm:{region}::document/AWS-RunPatchBaseline（雙冒號 ::，無帳號 ID）

resource "aws_ssm_maintenance_window" "weekly" {
  # TODO
}

resource "aws_ssm_maintenance_window_target" "ec2" {
  # TODO
}

resource "aws_ssm_maintenance_window_task" "patch_scan" {
  # TODO
}
```

- [ ] **Step 2: Commit main.tf scaffold**

```bash
git add terraform/labs/34-ssm-session-manager/main.tf
git commit -m "feat(labs): add lab 34 main.tf with TODO scaffolding"
```

---

## Task 3: 建立 outputs.tf

**Files:**
- Create: `terraform/labs/34-ssm-session-manager/outputs.tf`

- [ ] **Step 1: 建立 outputs.tf**

```hcl
output "instance_id" {
  description = "EC2 Instance ID（用於 SSM Session Manager 連線）"
  value       = aws_instance.ssm_target.id
}

output "instance_public_ip" {
  description = "EC2 Public IP（用於確認 Public Subnet 路由正確；不用於 SSH）"
  value       = aws_instance.ssm_target.public_ip
}

output "patch_baseline_id" {
  description = "SSM Patch Baseline ID"
  value       = aws_ssm_patch_baseline.amazon_linux_2023.id
}

output "maintenance_window_id" {
  description = "SSM Maintenance Window ID"
  value       = aws_ssm_maintenance_window.weekly.id
}

output "ssm_start_session_command" {
  description = "啟動 Session Manager 互動式 Shell 的指令（需安裝 AWS CLI + session-manager-plugin）"
  value       = "aws ssm start-session --target ${aws_instance.ssm_target.id} --region ${var.region}"
}

output "ssm_console_url" {
  description = "SSM Session Manager Console 連結"
  value       = "https://${var.region}.console.aws.amazon.com/systems-manager/session-manager/${aws_instance.ssm_target.id}"
}
```

- [ ] **Step 2: Commit outputs.tf**

```bash
git add terraform/labs/34-ssm-session-manager/outputs.tf
git commit -m "feat(labs): add lab 34 outputs.tf"
```

---

## Task 4: 建立 README.md

**Files:**
- Create: `terraform/labs/34-ssm-session-manager/README.md`

- [ ] **Step 1: 建立 README.md**

````markdown
# Lab 34: SSM Session Manager + Patch Manager

> 在完全沒有 SSH port（Security Group 零 inbound）的情況下，透過 SSM Session Manager 連進 EC2，並用 Patch Manager 定期掃描修補狀態。

**費用等級**：🟢 安全（< $0.10，EC2 t3.micro 跑 2 小時 ≈ $0.02，Free Tier 內 $0）

---

## 學習目標

- 理解 **SSM Session Manager** 原理：SSM Agent 出站 HTTPS → 不需 inbound port、不需 Bastion
- 建立 **Security Group 零 inbound**（含無 SSH 22 port）的 EC2 架構
- 設定 **AmazonSSMManagedInstanceCore** IAM Instance Profile
- 理解 **Patch Manager 4 個資源**：Baseline → Window → Target → Task
- 用 AWS CLI 啟動互動式 Shell、觸發 Patch Scan、查看 Patch Compliance

---

## 架構

```
VPC (10.0.0.0/16)
  └── Public Subnet (10.0.1.0/24) + IGW
        └── EC2 (Amazon Linux 2023, t3.micro)
              ├── IAM Instance Profile
              │     └── AmazonSSMManagedInstanceCore
              └── Security Group
                    ├── Inbound:  無任何規則（無 SSH！）
                    └── Outbound: HTTPS 443 → SSM Endpoint

EC2 SSM Agent → SSM Service (出站 HTTPS)
  ├── Session Manager（互動式 Shell，零 SSH）
  └── Patch Manager
        ├── Patch Baseline（Amazon Linux 2023, Critical+Important）
        ├── Maintenance Window（rate(7 days)）
        ├── Window Target（tag: PatchGroup = ssm-lab）
        └── Window Task（AWS-RunPatchBaseline, Operation=Scan）
```

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | `aws_vpc` + `aws_subnet` + `aws_internet_gateway` + `aws_route_table` + `aws_route_table_association` | `map_public_ip_on_launch = true`、route `0.0.0.0/0 → IGW` |
| 2 | `aws_security_group` | inbound = 完全空白、egress HTTPS 443 only |
| 3 | `aws_iam_role` + `aws_iam_role_policy_attachment` + `aws_iam_instance_profile` | `AmazonSSMManagedInstanceCore`、`ec2.amazonaws.com` |
| 4 | `aws_instance` | `iam_instance_profile`、Amazon Linux 2023 AMI、tag `PatchGroup = ssm-lab` |
| 5 | `aws_ssm_patch_baseline` | `operating_system = "AMAZON_LINUX_2023"`、approval rule |
| 6 | `aws_ssm_maintenance_window` + `aws_ssm_maintenance_window_target` + `aws_ssm_maintenance_window_task` | `rate(7 days)`、`AWS-RunPatchBaseline`、`Operation=Scan` |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate   # 填完所有 TODO 後再執行
terraform plan
terraform apply
```

> **注意**：resource body 空白時 `terraform validate` 會失敗，這是正常的。

---

## 驗證

### 1. 確認 SSM Agent 已註冊

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
echo "Instance: $INSTANCE_ID"

# 等待 SSM Agent 啟動（約 60-90 秒）
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].{Status:PingStatus,Agent:AgentVersion}' \
  --output table
```

**期望輸出**：`PingStatus = Online`。若顯示空白，等待 60 秒後重試。

### 2. 確認 Security Group 無 inbound 規則

```bash
SG_ID=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

aws ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json
```

**期望輸出**：`[]`（空陣列，完全無 inbound 規則）。

### 3. 啟動 Session Manager 互動式 Shell

> **前提**：需安裝 [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

```bash
# 取得連線指令
terraform output -raw ssm_start_session_command

# 直接執行連線（互動式，按 exit 離開）
aws ssm start-session --target "$INSTANCE_ID"
```

成功連線後可執行：
```bash
whoami        # → ssm-user
hostname      # → EC2 hostname
curl -s http://169.254.169.254/latest/meta-data/instance-id
```

### 4. 觸發 Patch Scan（Run Command 手動觸發）

```bash
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunPatchBaseline" \
  --parameters '{"Operation":["Scan"]}' \
  --query 'Command.CommandId' \
  --output text)

echo "Command ID: $COMMAND_ID"
echo "等待掃描完成（約 30 秒）..."
sleep 30
```

### 5. 查看 Patch Compliance 結果

```bash
aws ssm list-compliance-items \
  --resource-ids "$INSTANCE_ID" \
  --resource-types ManagedInstance \
  --filters "Key=ComplianceType,Values=Patch" \
  --query 'ComplianceItems[0].{Status:Status,Details:Details}' \
  --output table
```

**期望輸出**：`Status = COMPLIANT` 或顯示待修補清單。

### 6. 查看 Maintenance Window 狀態

```bash
WINDOW_ID=$(terraform output -raw maintenance_window_id)

aws ssm describe-maintenance-windows \
  --filters "Key=Name,Values=ssm-lab-window" \
  --query 'WindowIdentities[0].{Id:WindowId,Schedule:Schedule,Enabled:Enabled}' \
  --output table
```

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| EC2 t3.micro（2 小時）| ~$0.02（Free Tier 內 $0）|
| VPC / IGW | $0 |
| SSM Session Manager | $0 |
| SSM Patch Manager | $0 |
| **合計** | **< $0.10**（🟢 安全）|

---

## 核心概念釐清

### SSM Session Manager vs SSH 比較

| | SSH | SSM Session Manager |
|--|-----|---------------------|
| 需要開 inbound port | 是（22）| **否** |
| 需要 SSH Key | 是 | **否** |
| 連線紀錄 | 無 | **CloudTrail + CloudWatch** |
| IAM 控管 | 否 | **是（IAM Policy）** |
| Bastion Host | 常見需求 | **不需要** |
| **適合場景** | 傳統環境 | **零信任、合規、現代架構** |

### Patch Manager 資源關係

```
aws_ssm_patch_baseline         → 定義「哪些修補要安裝」
         ↓ （由 Window Task 參考）
aws_ssm_maintenance_window     → 定義「何時執行」（排程）
         ↓
aws_ssm_maintenance_window_target → 定義「哪些 EC2」（tag 篩選）
         ↓
aws_ssm_maintenance_window_task   → 定義「執行什麼」（Scan or Install）
```

### Operation=Scan vs Install 差異

| | Scan | Install |
|--|------|---------|
| 行為 | 只檢查，不修改 | 下載並安裝修補 |
| 重啟 EC2 | 否 | 可能（視修補而定）|
| **適合場景** | Lab / 合規審計 | 生產環境維護視窗 |

---

## 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 遠端管理 EC2 | Session Manager | 零 port 開放，完整稽核，無需 Bastion |
| 合規需求（誰做了什麼） | Session Manager + CloudTrail | 每次連線有完整紀錄 |
| 定期修補生產 EC2 | Patch Manager + Maintenance Window | 排程自動化，不需人工干預 |
| 快速確認 patch 狀態 | Run Command（手動觸發）| 不用等 Maintenance Window 排程 |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SSM Agent 狀態一直是空白 / Connection Lost | EC2 沒有 Public IP（Subnet 缺少 `map_public_ip_on_launch = true`）或 IGW/Route Table 未設定 |
| `start-session` 失敗：`TargetNotConnected` | 等待 60-90 秒讓 SSM Agent 初始化，或確認 `AmazonSSMManagedInstanceCore` 已綁定 |
| `start-session` 失敗：`An error occurred (AccessDeniedException)` | 本機 IAM 身份缺少 `ssm:StartSession` 權限 |
| `start-session` 失敗：plugin 未安裝 | 需先安裝 session-manager-plugin，參考 AWS 文件連結 |
| Patch Scan 失敗：`AccessDenied` | EC2 IAM Role 缺少 `AmazonSSMManagedInstanceCore` 綁定 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
| Maintenance Window Task ARN 格式錯誤 | Document ARN 格式為 `arn:aws:ssm:{region}::document/...`（雙冒號，無帳號 ID）|
````

- [ ] **Step 2: Commit README.md**

```bash
git add terraform/labs/34-ssm-session-manager/README.md
git commit -m "docs(labs): add lab 34 README with verification guide"
```

---

## Task 5: 初始化並鎖定 Provider 版本

**Files:**
- Create: `terraform/labs/34-ssm-session-manager/.terraform.lock.hcl` (generated)

- [ ] **Step 1: 切換到 lab 目錄並執行 terraform init**

```bash
cd terraform/labs/34-ssm-session-manager
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

- [ ] **Step 2: 確認 lock file 已生成**

```bash
ls .terraform.lock.hcl
```

Expected: 檔案存在，內容包含 `hashicorp/aws` 的版本雜湊。

- [ ] **Step 3: Commit lock file**

```bash
git add .terraform.lock.hcl
git commit -m "chore(labs): add lab 34 terraform lock file"
```

---

## Task 6: 更新 Roadmap 標記 Lab 34

**Files:**
- Modify: `terraform/docs/roadmap-v2.md`

- [ ] **Step 1: 更新 roadmap-v2.md**

在 `terraform/docs/roadmap-v2.md` 中，找到 Lab 34 那一行（包含 `ssm-session-manager`），在編號後加上 🚧：

找：
```
| 34 | `34-ssm-session-manager` |
```

改為：
```
| 34 🚧 | `34-ssm-session-manager` |
```

- [ ] **Step 2: Commit roadmap update**

```bash
git add terraform/docs/roadmap-v2.md
git commit -m "docs(roadmap): mark lab 34 as scaffolded"
```

---

## Self-Review

**Spec coverage check:**
- ✅ VPC + Public Subnet + IGW + Route Table → Task 2, TODO 1
- ✅ Security Group 零 inbound → Task 2, TODO 2
- ✅ IAM Role + AmazonSSMManagedInstanceCore + Instance Profile → Task 2, TODO 3
- ✅ EC2 Amazon Linux 2023 t3.micro + PatchGroup tag → Task 2, TODO 4
- ✅ SSM Patch Baseline (AMAZON_LINUX_2023) → Task 2, TODO 5
- ✅ Maintenance Window (rate 7 days) + Target (tag) + Task (Scan) → Task 2, TODO 6
- ✅ 動態 AMI data source → main.tf pre-filled section
- ✅ 驗證腳本（describe-instance-information, start-session, send-command）→ Task 4 README
- ✅ 費用估算 < $0.10 → Task 4 README
- ✅ SSM vs SSH 比較表 → Task 4 README
- ✅ Scan vs Install 差異說明 → Task 4 README
- ✅ .terraform.lock.hcl → Task 5
- ✅ Roadmap 更新 → Task 6

**Placeholder scan:** 無 TBD/TODO 殘留於計劃本身（main.tf 的 TODO 是教學用途，屬正常）。

**Type consistency:**
- `aws_iam_instance_profile.ec2_ssm.name` 用於 `aws_instance.ssm_target` 的 `iam_instance_profile` ✅
- `aws_ssm_maintenance_window.weekly.id` 用於 Target 和 Task ✅
- `aws_ssm_maintenance_window_target.ec2.id` 用於 Task 的 targets ✅
- tag key `PatchGroup` 在 EC2（TODO 4）和 Window Target（TODO 6）一致 ✅
- `var.project` 作為 PatchGroup 值在 EC2 tags 和 Window Target values 一致 ✅
