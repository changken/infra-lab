# Observability Lab — kube-prometheus-stack

## 概念

kube-prometheus-stack 是 Kubernetes 可觀測性的標準套件，一次裝好：

| 元件 | 負責 |
|------|------|
| **Prometheus** | 時序資料庫，定期抓取 (scrape) 各 Pod 的 `/metrics` |
| **Grafana** | 視覺化儀表板，前端給人看 |
| **node-exporter** | 每個 Node 上的 DaemonSet，回報 CPU/Memory/Disk |
| **kube-state-metrics** | 把 K8s 物件狀態（Pod READY、HPA 副本數…）轉成 metrics |
| **ServiceMonitor** | CRD，告訴 Prometheus「去哪裡抓哪個 Service 的 metrics」 |

抓取鏈：
```
custom-app Pod
  └── GET /metrics (Prometheus exposition format)
        ← ServiceMonitor (CRD) 描述抓取規則
              ← Prometheus 定期 scrape
                    └── Grafana 查詢顯示
```

---

## 架構

```
Internet
  └── ALB (eks-monitoring group)
        └── Grafana Service (monitoring namespace)

Prometheus (monitoring ns)
  ├── scrape: custom-app/metrics (custom_app_http_requests_total, bedrock_requests_total)
  ├── scrape: podinfo/metrics     (http_requests_total, go_*)
  ├── scrape: node-exporter       (node_cpu_seconds_total, node_memory_*)
  └── scrape: kube-state-metrics  (kube_pod_*, kube_deployment_*, kube_hpa_*)
```

---

## 環境

| 項目 | 值 |
|------|-----|
| Helm Chart | prometheus-community/kube-prometheus-stack |
| Namespace | `monitoring` |
| 部署方式 | ArgoCD (Helm source) |
| 自訂 metrics | `custom_app_http_requests_total`, `custom_app_bedrock_requests_total`, `custom_app_aws_requests_total` |

---

## 步驟

### Step 1 — Build & Push custom-app v6（加了 /metrics）

```bash
# 切到 app 目錄
cd terraform/envs/aws-eks/app

# Build
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  661515655645.dkr.ecr.us-east-1.amazonaws.com

docker build -t infra-lab-dev-app:v6 .
docker tag infra-lab-dev-app:v6 \
  661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v6
docker push 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v6
```

v6 新增了三個 Prometheus Counter：
- `custom_app_http_requests_total{path, status}` — 每個 endpoint 的請求數
- `custom_app_bedrock_requests_total{model, status}` — Bedrock 呼叫次數
- `custom_app_aws_requests_total{service, status}` — AWS API 呼叫次數

### Step 2 — 確認 Helm Chart 版本

```bash
# 查詢最新版本
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community/kube-prometheus-stack --versions | head -5
```

若最新版本與 `monitoring-app.yaml` 中的 `targetRevision` 不同，更新 YAML。

### Step 3 — 設定 Grafana 密碼

`k8s/argocd/monitoring-app.yaml` 中找到：
```yaml
adminPassword: "admin-change-me"
```
改成你自己的密碼。

> ⚠️ 進階做法：改用 K8s Secret 儲存密碼，避免明文進 Git
> ```bash
> kubectl create secret generic grafana-admin \
>   --from-literal=admin-password=你的密碼 \
>   -n monitoring
> ```
> 然後 values 改成：
> ```yaml
> grafana:
>   admin:
>     existingSecret: grafana-admin
>     passwordKey: admin-password
> ```

### Step 4 — Push 到 Git，ArgoCD 自動部署

```bash
git add terraform/envs/aws-eks/
git commit -m "feat(aws-eks): 新增 kube-prometheus-stack 可觀測性"
git push
```

ArgoCD 同步後依序建立：
1. `monitoring` namespace
2. CRDs（ServiceMonitor、PrometheusRule 等）
3. Prometheus、Grafana、node-exporter、kube-state-metrics

等待 5-10 分鐘讓 Stack 完全啟動：
```bash
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring
kubectl get pods -n monitoring
```

### Step 5 — 套用 ServiceMonitor

ServiceMonitor 在 `k8s/monitoring/` 目錄，ArgoCD 不管理（不在 ArgoCD App scope），手動 apply：

```bash
kubectl apply -f terraform/envs/aws-eks/k8s/monitoring/
```

確認 Prometheus 有抓到：
```bash
# Port-forward 到 Prometheus UI
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring

# 另開一個 terminal
# 瀏覽器開 http://localhost:9090/targets
# 應看到 custom-app / podinfo 出現在 serviceMonitor 區塊
```

### Step 6 — 取得 Grafana ALB URL

```bash
kubectl get ingress -n monitoring
# NAME      CLASS   HOSTS   ADDRESS                                    PORTS
# grafana   alb     *       k8s-monitoring-xxx.us-east-1.elb.amazonaws.com   80
```

瀏覽器開 `http://<ALB_URL>`，用 `admin` / 你設定的密碼登入。

---

## 驗證

### 確認 custom-app /metrics 正常

```bash
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# 看到 Prometheus exposition format 輸出
curl http://$ALB/metrics | grep custom_app
```

預期輸出：
```
# HELP custom_app_http_requests_total Total HTTP requests by path and status
# TYPE custom_app_http_requests_total counter
custom_app_http_requests_total{path="/health",status="200"} 12
custom_app_http_requests_total{path="/",status="200"} 3
```

### 在 Prometheus 查詢

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

PromQL 範例：
```promql
# custom-app 的請求速率（per second）
rate(custom_app_http_requests_total[5m])

# Bedrock 呼叫次數（依 model 分組）
sum by (model) (custom_app_bedrock_requests_total)

# 節點 CPU 使用率
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

# Pod 記憶體使用量
container_memory_working_set_bytes{namespace="custom-app"}
```

### Grafana 推薦 Dashboard

登入 Grafana 後，左側 Dashboards → Browse，搜尋以下內建 Dashboard：

| Dashboard | ID | 看什麼 |
|-----------|----|--------|
| Kubernetes / Compute Resources / Cluster | — | 整體 CPU/Memory |
| Kubernetes / Compute Resources / Namespace | — | custom-app / podinfo 分開看 |
| Node Exporter Full | 1860 | 節點硬體指標 |
| Kubernetes / HPA | — | HPA 目前副本數 vs 目標 |

### 產生流量觀察圖表變化

```bash
# 用 watch 連打 /health（每 2 秒）
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

watch -n 2 "curl -s http://$ALB/health"

# 打 Bedrock（需要 API Key）
API_KEY=$(kubectl get secret custom-app-secrets -n custom-app \
  -o jsonpath='{.data.chat-api-key}' | base64 -d)

curl "http://$ALB/chat?q=hello&model=nova" \
  -H "X-API-Key: $API_KEY"
```

Grafana 應該在 1-2 分鐘後（下一個 scrape interval）更新圖表。

---

## TODO 進階挑戰

### TODO A — 加一個 Histogram metric（量測 response time）

在 `app/main.go` 加入：
```go
// 提示：用 prometheus.NewHistogramVec，buckets 設定回應時間分佈
// 文件：https://pkg.go.dev/github.com/prometheus/client_golang/prometheus#NewHistogramVec
var httpDuration = promauto.NewHistogramVec(...)
```

完成後可以用 `histogram_quantile(0.99, ...)` 查 P99 latency。

### TODO B — 寫一條 PrometheusRule（Alerting Rule）

建立 `k8s/monitoring/custom-app-rule.yaml`：
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-app-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: custom-app
      rules:
        - alert: CustomAppHighErrorRate
          # TODO: 當 /chat 的 4xx/5xx 比例超過 10% 時發出 alert
          # 提示：用 rate() 計算 status != "200" 的比例
          expr: # TODO
          for: 2m
          labels:
            severity: warning
```

### TODO C — 加 Loki（集中 log）

kube-prometheus-stack 不含 Loki，需另外部署：
```yaml
# k8s/argocd/loki-app.yaml
# 提示：chart = grafana/loki-stack，包含 Loki + Promtail
# Promtail 自動收集所有 Pod 的 stdout log
```

---

## 遇到的問題

| 症狀 | 原因 | 解法 |
|------|------|------|
| ServiceMonitor 建立後 Prometheus 沒有抓到 | `serviceMonitorSelectorNilUsesHelmValues: false` 沒設 | 確認 monitoring-app.yaml 有設定 |
| Prometheus target 顯示 connection refused | custom-app Service 沒有 named port | 確認 service.yaml 有 `name: http` |
| ArgoCD sync 失敗：CRD not found | kube-prometheus-stack 還在建立 CRD | 等 CRD 就緒再 sync ServiceMonitor |
| Grafana 頁面打不開 | ALB 還在 provisioning | 等 2-3 分鐘，`kubectl describe ingress -n monitoring` |
| Helm chart version not found | targetRevision 填了不存在的版本 | `helm search repo` 確認版本 |

---

## 成本

| 新增資源 | 費用 |
|---------|------|
| Grafana ALB (eks-monitoring group) | ~$0.016/hr ≈ $0.38/day |
| Pod 資源（Prometheus 512Mi、Grafana 128Mi…） | 使用現有 Node，若 Node 不夠會 scale out |
| EBS PVC（本 lab 關閉，用 emptyDir） | $0 |
| **合計** | ~$0.38/day 增量 |

> ⚠️ Prometheus 會讓 t3.medium (4GB) Node 記憶體吃緊，
> 若 Pod Evicted，考慮把 Node Group desiredSize 從 2 加到 3：
> ```bash
> aws eks update-nodegroup-config \
>   --cluster-name infra-lab-dev-eks \
>   --nodegroup-name infra-lab-dev-node-group \
>   --scaling-config minSize=1,maxSize=3,desiredSize=3
> ```

---

## 清理

```bash
# 只移除 monitoring stack（保留 EKS 其他服務）
kubectl delete application kube-prometheus-stack -n argocd
kubectl delete -f terraform/envs/aws-eks/k8s/monitoring/
kubectl delete namespace monitoring
```

---

*紀錄日期：2026-06-22*
*環境：AWS EKS 1.36 / kube-prometheus-stack 70.x / Prometheus 3.x / Grafana 11.x*
