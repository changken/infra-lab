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

> **補充**：雖然 EC2 有 Public IP（`terraform output instance_public_ip`），但 Security Group 完全封鎖 inbound，所以無法 SSH 進去——這正是本 lab 的核心架構。

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
