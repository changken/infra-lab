# Lab 34 設計文件：SSM Session Manager + Patch Manager

**日期**: 2026-05-26
**狀態**: 已確認，準備實作

---

## 範圍

建立 `terraform/labs/34-ssm-session-manager/`，涵蓋：
- EC2 + IAM Instance Profile（AmazonSSMManagedInstanceCore）
- Security Group：無任何 inbound（含無 SSH 22 port）
- SSM Session Manager 零 SSH 連線
- SSM Patch Manager（Patch Baseline + Maintenance Window + Target + Task）

---

## 架構

```
VPC (Public Subnet + IGW)
  EC2 (Amazon Linux 2023, t3.micro)
  ├── IAM Instance Profile
  │     └── AmazonSSMManagedInstanceCore
  └── Security Group
        ├── Inbound:  無任何規則（無 SSH！）
        └── Outbound: HTTPS 443（SSM endpoint）

EC2 → SSM Endpoint（出站 HTTPS）
  ├── Session Manager（互動式 shell，零 SSH）
  └── Patch Manager
        ├── Patch Baseline（Amazon Linux 2023）
        ├── Maintenance Window（rate(7 days)）
        ├── Window Target（EC2 instance tag）
        └── Window Task（AWS-RunPatchBaseline, Operation=Scan）
```

---

## TODO 結構

| TODO | Terraform 資源 | 關鍵設定 |
|------|---------------|---------|
| 1 | VPC + Subnet + IGW + Route Table | `map_public_ip_on_launch = true` |
| 2 | Security Group | inbound = 空、outbound = HTTPS 443 |
| 3 | `aws_iam_role` + `aws_iam_instance_profile` | `AmazonSSMManagedInstanceCore` |
| 4 | `aws_instance` | `iam_instance_profile`、Amazon Linux 2023 AMI |
| 5 | `aws_ssm_patch_baseline` | `operating_system = "AMAZON_LINUX_2023"` |
| 6 | `aws_ssm_maintenance_window` + `aws_ssm_maintenance_window_target` + `aws_ssm_maintenance_window_task` | `rate(7 days)`、`AWS-RunPatchBaseline` |

---

## 檔案清單

```
34-ssm-session-manager/
├── terraform.tf
├── variables.tf
├── locals.tf
├── main.tf              ← 6 個 TODO
├── outputs.tf
├── terraform.tfvars.example
├── .gitignore
└── README.md
```

---

## 費用估算

| 資源 | 費用 |
|------|------|
| EC2 t3.micro（2 小時）| ~$0.02（Free Tier 內 $0）|
| VPC / IGW | $0 |
| SSM / Patch Manager | $0 |
| **合計** | **< $0.10**（🟢 安全）|

---

## 決策記錄

- **Public Subnet + IGW 而非 VPC Endpoint**：VPC Endpoint 需要 3 個（ssm、ec2messages、ssmmessages），每個 $0.01/hr = $0.03/hr，對 lab 過貴；Public Subnet 提供免費出站路徑
- **Patch Task Operation = Scan**：Scan 只檢查而不安裝，避免 lab 環境意外更新套件；真實生產環境用 Install
- **Amazon Linux 2023**：SSM Agent 預裝，不需額外安裝步驟
- **Maintenance Window rate(7 days)**：lab 用途，學習排程語法；不會真正等待觸發
