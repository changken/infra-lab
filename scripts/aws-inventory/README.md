# AWS Account Inventory Scanner

跨帳號、多 Region 的 AWS 唯讀資源盤點工具。

掃描引擎由 [aws-auto-inventory](https://github.com/aws-samples/aws-auto-inventory)（AWS 官方 sample）提供，本工具負責互動式選單、多帳號編排與結果整理。

## 架構

```
run-inventory.sh          ← 互動式編排（你維護這裡）
scans/
  billing.json            ← EC2/EBS/EIP/NAT/ELB/RDS/EKS（預設全勾，會產生費用）
  storage.json            ← S3/Snapshot
  compute.json            ← Lambda/CloudFormation
  security.json           ← IAM Roles/MFA
  iam-global.json         ← IAM Users/Access Keys（由專用收集器執行）
vendor/
  aws-auto-inventory/     ← git submodule，掃描引擎（不用自己維護）
inventory-output/         ← 掃描結果（已加入 .gitignore）
```

## 前置條件

| 工具 | 版本 |
|------|------|
| AWS CLI | v2.x |
| Python | 3.8+ |
| Bash | 4.x+（WSL 或 Linux） |

## 初次設定

```bash
# 1. clone repo 後初始化 submodule
git submodule update --init

# 2. 建立 Python venv（只需做一次）
cd vendor/aws-auto-inventory
python3 -m venv .venv
.venv/bin/pip install boto3 requests jq XlsxWriter
cd ../..
```

## 執行

```bash
cd /mnt/d/repo/infra-lab/scripts/aws-inventory
chmod +x run-inventory.sh
./run-inventory.sh
```

啟動後會依序設定：

1. **Profiles** — 從 `~/.aws/config` 動態列出，全部不預選
2. **Regions** — 預設勾 `us-east-1`、`us-west-2`、`ap-northeast-1`、`ap-east-1`
3. **資源類別** — 預設全勾（`billing`、`storage`、`compute`、`security`）
4. **Cost Explorer（選擇性）** — 預設略過，不會呼叫 Cost Explorer。只有明確輸入 `y` 才會選擇 management account 的 SSO Profile 和查詢月份。

確認後開始掃描。資源 JSON 存在 `inventory-output/<timestamp>/<account_id>/<category>/`，Excel 報表則直接放在該次 `<timestamp>/` 目錄下。
費用 API 依 request 計費；目前帳單顯示 USD 0.01/request，逐 Region 查詢與分頁會增加請求數。因此費用查詢預設關閉，啟用前會再次提示。

## Excel 報表

每次執行完成後自動產生 `aws-report-YYYY-MM-DD-HH-mm-ss.xlsx`，包含：

- **總覽** — 掃描範圍、帳號與類別資源數、費用摘要及掃描警告。
- **資源清單** — 每個資源一列，具 Excel Table 篩選功能；依類別套用淡色底。Global 資源去重並標示為 `Global`。
- **費用明細** — 明確啟用 Cost Explorer 後，依月份、帳號、服務和 Region 列出 `UnblendedCost`、幣別及估算狀態；略過時工作表會是空表，總覽會註明「未查詢」。

JSON 原始結果仍獨立保存；「資源清單」的「原始 JSON」欄提供相對路徑連結。即使掃描沒有資源或部分查詢失敗，也會產生報表並在總覽列出警告。
IAM 為 Global 服務，僅掃描一次；會明確輸出 IAM Users（即使結果為空），再逐一查詢各使用者的 Access Key 中繼資料，並顯示使用者與金鑰數量。

### Cost Explorer 權限（選擇性）

只有明確啟用費用查詢時，才需要 management account 的 SSO Profile；若 AWS Organization 尚未啟用 Cost Explorer，需由 management account 管理者一次啟用。將 AWS 受管政策 `AWSBillingReadOnlyAccess` 指派給 management account 使用的 IAM Identity Center Permission Set。程式不使用 root 憑證，也不需要為 API 查詢開啟 Billing Console 的 `Activate IAM Access`。

成本以 Cost Explorer 回傳的 `UnblendedCost` 呈現；當月資料若尚未結算，報表會標示為估算值。費用是依帳號、服務、Region 彙總，並非逐資源成本。

## 測試

在 `scripts/aws-inventory` 目錄執行；測試使用固定資料和 AWS API stub，不會呼叫真實 AWS：

```bash
vendor/aws-auto-inventory/.venv/bin/python3 -m unittest discover -s tests -v
```

## 輸出結構

```
inventory-output/
└── 20260101T120000/
    ├── aws-report-2026-01-01-12-00-00.xlsx
    └── 123456789012/          ← Account ID
        ├── billing/
        │   └── <timestamp>/
        │       ├── us-east-1/
        │       │   ├── ec2-describe_instances.json
        │       │   ├── ec2-describe_volumes.json
        │       │   └── ...
        │       └── ap-northeast-1/
        │           └── ...
        ├── storage/
        ├── compute/
        └── security/
```

## 新增掃描項目

在對應的 `scans/*.json` 加一個 entry 即可，格式參考 [aws-auto-inventory scan file 說明](https://github.com/aws-samples/aws-auto-inventory#configuration)：

```json
{ "service": "dynamodb", "function": "list_tables", "result_key": "TableNames" }
```

service 名稱對應 boto3 client 名稱，可在 `vendor/aws-auto-inventory/scan/sample/services/` 找到所有可用的 service scan file 參考。

## 更新掃描引擎

```bash
cd vendor/aws-auto-inventory
git pull
cd ../..
git add vendor/aws-auto-inventory
git commit -m "chore: bump aws-auto-inventory submodule"
```
