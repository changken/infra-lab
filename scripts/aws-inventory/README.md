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
  security.json           ← IAM Users/Roles/Access Keys
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
.venv/bin/pip install boto3 requests jq
cd ../..
```

## 執行

```bash
cd /mnt/d/repo/infra-lab/scripts/aws-inventory
chmod +x run-inventory.sh
./run-inventory.sh
```

啟動後依序出現三個互動式選單：

1. **Profiles** — 從 `~/.aws/config` 動態列出，全部不預選
2. **Regions** — 預設勾 `us-east-1`、`us-west-2`、`ap-northeast-1`、`ap-east-1`
3. **資源類別** — 預設全勾（`billing`、`storage`、`compute`、`security`）

確認後開始掃描，結果存在 `inventory-output/<timestamp>/<account_id>/<category>/`。

## 輸出結構

```
inventory-output/
└── 20260101T120000/
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
