# CloudWatch Dashboard

## 對比 EKS lab（Grafana + Prometheus）

| 項目 | EKS | ECS Fargate |
|------|-----|-------------|
| Metrics 收集 | Prometheus（自部署 Helm chart）| Container Insights（Cluster 層級開關）|
| 視覺化 | Grafana Dashboard（自定義）| CloudWatch Dashboard（Terraform 管理）|
| 安裝成本 | 需要 Helm + PVC + RBAC | 零設定（`containerInsights = "enabled"`）|
| 自定義彈性 | 高（PromQL）| 中（CloudWatch Metric Math）|
| 費用 | 含在 Node 費用內 | Container Insights 約 $0.50/GB ingested |

## Dashboard 位置

```
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=infra-lab-dev
```

或：
```bash
terraform output dashboard_url
```

## Widget 說明

### Row 1 — ECS Task Metrics（Container Insights）

| Widget | Metric | 說明 |
|--------|--------|------|
| CPU Utilization (%) | `CpuUtilized / CpuReserved × 100` | Metric Math 計算百分比；橘線 = 70% scale-out 閾值 |
| Memory Utilization (%) | `MemoryUtilized / MemoryReserved × 100` | 同上；橘線 = 80% scale-out 閾值 |
| Task Count | `RunningTaskCount` vs `DesiredTaskCount` | 兩線分離代表 Auto Scaling 正在調整 |

**Metric Math 語法（CPU 為例）：**
```
e1 = m1 / m2 * 100
m1 = ECS/ContainerInsights CpuUtilized   (hidden)
m2 = ECS/ContainerInsights CpuReserved   (hidden)
```
CloudWatch 原生支援，不需要 PromQL。

### Row 2 — ALB Metrics

| Widget | Metric | 說明 |
|--------|--------|------|
| Request Count | `RequestCount` (Sum) | 每分鐘總請求數 |
| 5xx Errors | `HTTPCode_Target_5XX_Count` + `HTTPCode_ELB_5XX_Count` | Target 5xx = app 回傳錯誤；ELB 5xx = ALB 本身錯誤（連不到 target）|
| Response Time | `TargetResponseTime` P50 / P99 | P99 飆高但 P50 正常 → 長尾問題 |

### Row 3 — Blue/Green Target Group Health

| Widget | 說明 |
|--------|------|
| Blue TG Healthy Hosts | 平時應為 2（`service_desired_count`），部署期間舊 tasks drain 時下降 |
| Green TG Healthy Hosts | 平時為 0，CodeDeploy 部署期間爬升到 2，流量切換完成後 Blue 歸零 |

**觀察 Blue/Green 部署時的 dashboard 變化：**
```
部署開始 → Green TG Healthy: 0 → 2
流量切換 → Blue TG Request Count 下降，Green TG 上升
Blue drain → Blue TG Healthy: 2 → 0（5 分鐘後）
```

## 手動觸發壓力（觀察 Auto Scaling）

```bash
# 安裝 hey（HTTP 壓測工具）
go install github.com/rakyll/hey@latest

ALB="http://infra-lab-dev-alb-17053701.us-east-1.elb.amazonaws.com"

# 打 300 秒，200 concurrent，觀察 CPU widget 是否超過 70%
hey -z 300s -c 200 $ALB/

# 同時看 Task Count widget，應該會從 2 爬升
```

Auto Scaling 反應時間約 1-3 分鐘（CloudWatch alarm → scaling policy → ECS task 啟動）。

## Terraform 實作重點

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name_prefix
  dashboard_body = jsonencode({ widgets = [...] })
}
```

- `dashboard_body` 是 JSON 字串，用 `jsonencode()` 生成
- 每個 widget 必須指定 `region`（metric widget 規定）
- `arn_suffix` attribute（`aws_lb.main.arn_suffix`）直接取得 CloudWatch dimension 所需的格式

## Container Insights 可用 Metrics

namespace: `ECS/ContainerInsights`，dimensions: `ClusterName` + `ServiceName`

| Metric | 說明 |
|--------|------|
| `CpuUtilized` / `CpuReserved` | 實際用量 / 配額（CPU units）|
| `MemoryUtilized` / `MemoryReserved` | 實際用量 / 配額（MiB）|
| `RunningTaskCount` / `DesiredTaskCount` | 現有 / 目標 task 數 |
| `NetworkRxBytes` / `NetworkTxBytes` | 網路流量 |
| `StorageReadBytes` / `StorageWriteBytes` | 儲存 I/O |
