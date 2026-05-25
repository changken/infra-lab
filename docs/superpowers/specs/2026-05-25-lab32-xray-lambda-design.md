# Lab 32: X-Ray + Lambda + API Gateway 分散式追蹤 — 設計文件

**日期**: 2026-05-25
**路徑**: `terraform/labs/32-xray-lambda/`
**費用**: $0（X-Ray 免費額度 100,000 traces/月、1M subsegments/月）
**認證覆蓋**: DVA

---

## 目標

建立 API Gateway + Lambda 鏈路，開啟 X-Ray Active Tracing，讓使用者透過 CLI 查看分散式追蹤的 Trace 結構、Service Map 與延遲分布。

---

## 架構

```
Client（curl）
   │
   ▼
API Gateway REST API（xray_tracing_enabled = true）
   │  自動注入 Trace ID Header（X-Amzn-Trace-Id）
   ▼
Lambda（tracing_config.mode = "Active"）
   │  Lambda runtime 自動送 trace 至 X-Ray daemon
   └── X-Ray Service Map: [Client] → [API Gateway] → [Lambda]
```

---

## 資源（TODOs）

| # | 資源 | 關鍵設定 |
|---|------|---------|
| 1 | `aws_iam_role` + 2× `aws_iam_role_policy_attachment` | BasicExecutionRole + `AWSXRayDaemonWriteAccess` |
| 2 | `aws_lambda_function` | `tracing_config { mode = "Active" }`、`runtime = "python3.12"` |
| 3 | `aws_api_gateway_rest_api` + `aws_api_gateway_resource` + `aws_api_gateway_method` + `aws_api_gateway_integration` | Lambda proxy 整合，`http_method = "POST"` |
| 4 | `aws_api_gateway_deployment` + `aws_api_gateway_stage` | `xray_tracing_enabled = true`、`stage_name = "dev"` |
| 5 | `aws_lambda_permission` | `principal = "apigateway.amazonaws.com"` |

---

## 檔案結構

```
32-xray-lambda/
├── terraform.tf            # provider aws ~> 5.0
├── variables.tf            # region, project, environment
├── locals.tf               # common_tags
├── main.tf                 # 5 個 TODO 資源骨架
├── outputs.tf              # api_endpoint, lambda_function_name, xray_group_arn
├── src/
│   └── handler.py          # Lambda 程式碼（已完成，無需 TODO）
├── terraform.tfvars.example
├── .gitignore              # 含 src/*.zip
└── README.md
```

---

## Lambda 程式碼（`src/handler.py`，已預填，非 TODO）

```python
import json
import time

def handler(event, context):
    time.sleep(0.1)  # 模擬業務延遲，讓 X-Ray trace 有意義的數字
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from X-Ray lab!",
            "path": event.get("path", "/"),
        }),
    }
```

不引入 `aws_xray_sdk`，Lambda 的 Active Tracing 模式由 runtime 自動送 trace segment，無需外部 SDK。

---

## 驗證流程（純 CLI）

1. `terraform apply`
2. `curl` API endpoint 3-5 次製造追蹤資料
3. 等待約 10 秒（X-Ray 資料有輕微延遲）
4. `aws xray get-trace-summaries` — 列出最近 traces，確認 Http Status = 200
5. `aws xray batch-get-traces` — 查詢特定 trace 的完整細節（duration、segments）
6. `aws xray get-service-graph` — 取得服務圖 JSON，確認 API GW → Lambda 節點存在
7. `terraform destroy`

---

## 核心概念（README 必須涵蓋）

- X-Ray **Trace** vs **Segment** vs **Subsegment** 的層次關係
- `tracing_config { mode = "Active" }` vs `PassThrough` 差異
- API Gateway 的 `xray_tracing_enabled` 開關位置（Stage 層，非 Resource/Method）
- `AWSXRayDaemonWriteAccess` 為何必要（Lambda 送 trace 至 X-Ray daemon 需要此權限）
- X-Ray 免費額度與 Sampling Rule 概念（預設 5% + 1 req/sec）

---

## main.tf TODO 格式規範

遵循現有 lab 慣例：
- 大 comment block 在頂部說明 X-Ray 概念
- 每個 TODO 上方有詳細 comment（資源說明、文件連結、關鍵欄位）
- resource body 保持空白（`# TODO`）

---

## 面試重點

| 情境 | 選擇 | 原因 |
|------|------|------|
| 追蹤跨服務延遲 | X-Ray | 自動傳遞 Trace ID，有 Service Map |
| 只需記錄錯誤 | CloudWatch Logs | 更簡單，X-Ray 是 latency/dependency 分析工具 |
| Lambda 需要自訂 subsegment | aws_xray_sdk | 手動標記業務邏輯區塊 |
| 生產環境節省費用 | Sampling Rule | 只追蹤部分請求，降低 X-Ray 費用 |
