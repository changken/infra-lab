# AI Agent 協作指南 — aws-k3s 模組

本文件為 AI 助手（Claude、Gemini 等）提供此模組的背景與協作規範。
Claude Code 透過 `CLAUDE.md`（hard link）自動載入，Gemini CLI 透過 `GEMINI.md`（hard link）自動載入。

## 模組概覽

**模組名稱**: aws-k3s (AWS K3s Lab)
**用途**: 個人學習與實驗用的 AWS K3s 叢集（1 CP + 2 Workers）
**特性**: Tailscale VPN 管理、EIP 穩定 IP、SSM SecureString 管理 secrets、Local Terraform state
**注意**: 這不是填空式 Lab，而是可長期使用的個人參考模組

## 目錄結構

```
aws-k3s/
├── agents.md                    # AI 協作指南（CLAUDE.md / GEMINI.md 為 hard link）
├── CLAUDE.md                    # → agents.md（Claude Code 自動載入）
├── GEMINI.md                    # → agents.md（Gemini CLI 自動載入）
├── main.tf                      # Terraform backend + AWS provider
├── aws.tf                       # AWS 全部資源（VPC / SG / IAM / EIP / EC2）
├── variables.tf                 # AWS 變數
├── outputs.tf                   # 輸出值（含 next_steps 操作指引）
├── user-data-cp.sh              # Control plane cloud-init（K3s server + SSM write + Tailscale）
├── user-data-worker.sh          # Worker node cloud-init（SSM poll + k3s agent + Tailscale）
├── terraform.tfvars.example     # 變數範例（可公開）
├── .terraform.lock.hcl          # Provider 版本鎖定（已提交）
└── docs/
    └── SETUP_GUIDE.md           # 詳細建置記錄
```

## 架構

```
AWS us-east-1 VPC (10.1.0.0/16)
  │
  ├─ my-cp       (t3.medium, 2vCPU/4GB) ← Control Plane
  │    EIP: <stable public IP>
  │    K3s server
  │    cloud-init: K3s → SSM write → Tailscale
  │
  ├─ my-worker-1 (t3.small, 1vCPU/2GB)  ← Worker
  │    K3s agent (joins via CP private IP)
  │    cloud-init: SSM poll → k3s agent → Tailscale
  │
  └─ my-worker-2 (t3.small, 1vCPU/2GB)  ← Worker
       K3s agent
       cloud-init: SSM poll → k3s agent → Tailscale

SSM Parameter Store (SecureString)
  ├─ /k3s-lab/tailscale-auth-key  ← 手動 apply 前建立
  └─ /k3s-lab/node-token          ← CP cloud-init 自動寫入

本機 ←→ Tailscale VPN ←→ 所有節點
```

**cloud-init 啟動順序：**
```
terraform apply
  │
  ├─ 1. 分配 EIP → 建立 CP → 關聯 EIP
  └─ 2. 建立 2 台 workers（depends_on CP）

CP cloud-init:
  apt update → K3s server → 等 token → SSM write → Tailscale (best-effort)

Worker cloud-init（concurrent）:
  apt update → SSM poll（最多 10 分鐘）→ k3s agent join → Tailscale (best-effort)
```

## 核心設計原則

| 原則 | 說明 |
|------|------|
| **Tailscale First** | 無公開 SSH；所有管理存取均透過 Tailscale VPN |
| **IMDSv2 強制** | `http_tokens = "required"`，防止 SSRF 攻擊 |
| **加密 Volume** | 所有 EC2 root volume 強制加密 |
| **SSM SecureString** | Tailscale key 與 K3s token 均以 SecureString 儲存，不進 Terraform state |
| **Local State** | Terraform state 存於本機（`.terraform/terraform.tfstate`），不使用 Terraform Cloud |
| **最小權限 IAM** | IAM policy 鎖定至 `parameter/k3s-lab/*`，不使用 `"*"` |

## 費用估算

| 資源 | 費用 |
|------|------|
| CP (t3.medium) | ~$0.0416/hr |
| Worker × 2 (t3.small) | ~$0.0416/hr（合計） |
| EIP（開機中） | 免費 |
| EIP（停機閒置） | $0.005/hr ⚠️ |
| SSM SecureString | < $0.01/月 |
| **合計（開機中）** | **~$0.083/hr (~$60/月)** |

> 不使用時執行 `aws ec2 stop-instances` 停止全部 3 台，或 `terraform destroy` 完全清除。

## 關機 / 開機

```bash
# 停止全部 3 台
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

## 關鍵變數

| 變數 | 必填 | 說明 |
|------|------|------|
| `aws_ssh_public_key_path` | ❌ | AWS 緊急 SSH 公鑰路徑（預設 `./.ssh/aws_emergency_ed25519.pub`） |
| `aws_region` | ❌ | 預設 `us-east-1` |
| `cp_instance_type` | ❌ | CP instance type，預設 `t3.medium` |
| `worker_instance_type` | ❌ | Worker instance type，預設 `t3.small` |
| `worker_count` | ❌ | Worker 數量，預設 `2` |
| `cp_hostname` | ❌ | CP hostname，預設 `my-cp` |
| `worker_hostname_prefix` | ❌ | Worker hostname 前綴，預設 `my-worker`（產生 my-worker-1, my-worker-2）|
| `ssh_allowed_cidr` | ❌ | 緊急 SSH 來源 IP（預設 `0.0.0.0/0`，建議改 `/32`）|
| `aws_availability_zone` | ❌ | 預設空（AWS 自動選）|

**SSM 參數（apply 前手動建立）：**

| 參數名稱 | 類型 | 說明 |
|---------|------|------|
| `/k3s-lab/tailscale-auth-key` | SecureString | Tailscale auth key |
| `/k3s-lab/node-token` | SecureString | K3s node token（CP 自動寫入，勿手動建立）|

## AI 協作規範

### 修改此模組時的注意事項

1. **安全不降級**：不要移除 IMDSv2、volume 加密、IAM 最小權限等安全設定
2. **Tailscale 優先**：Tailscale 失敗時叢集仍運作；不要預設開放 SSH ingress
3. **SSM 優先**：secrets 不應進入 templatefile() 或 Terraform state
4. **Provider 版本**：修改前確認 `.terraform.lock.hcl`，維持一致性
5. **費用提醒**：新增資源應評估費用並更新本文件

### 常見操作流程

```bash
# apply 前：建立 SSM Tailscale key
aws ssm put-parameter \
  --name "/k3s-lab/tailscale-auth-key" \
  --value "tskey-auth-REPLACE_ME" \
  --type SecureString --region us-east-1

# 部署
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt && terraform validate
terraform plan
terraform apply

# 查看後續步驟
terraform output next_steps

# 取得 kubeconfig
EIP=$(terraform output -raw aws_eip_public_ip)
tailscale ssh ubuntu@my-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
  > kubeconfig/k3s-aws.yaml

# 完全銷毀
terraform destroy
aws ssm delete-parameter --name "/k3s-lab/node-token" --region us-east-1
aws ssm delete-parameter --name "/k3s-lab/tailscale-auth-key" --region us-east-1
```

### 疑難排解

| 症狀 | 原因與解法 |
|------|-----------|
| Workers 無法加入叢集 | CP 尚未完成 cloud-init（等 3-5 分鐘）；查 CP console output |
| Tailscale 連不上 | SSM `/k3s-lab/tailscale-auth-key` 不存在或過期；Tailscale 失敗不影響叢集 |
| kubeconfig 連不上 | 確認使用 EIP（`terraform output aws_eip_public_ip`）；stop/start 後 EIP 不變 |
| SSM GetParameter 失敗 | 確認 IAM instance profile 已掛載；policy 允許 `k3s-lab/*` |
| K3s 未自動安裝 | `aws ec2 get-console-output --instance-id <id> --region us-east-1` |
| `terraform plan` 顯示差異 | 檢查 AMI 是否有更新版本（data.aws_ami 會自動選最新）|

---

*最後更新: 2026-06-01*
