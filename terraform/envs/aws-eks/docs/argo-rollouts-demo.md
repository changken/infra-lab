# Argo Rollouts Demo — Canary 部署 + Prometheus 自動分析

## 架構概覽

```
git push (v9)
   │
   ▼
GitHub Actions → ECR push → rollout.yaml image tag 更新
   │
   ▼
ArgoCD sync
   │
   ▼
Argo Rollouts controller
   │
   ├─ Step 1: setWeight 20%
   │    └─ ALB: 20% → canary pods, 80% → stable pods
   ├─ Step 2: analysis (success-rate, 5×30s)
   │    └─ Prometheus: success rate >= 95%? ✅
   ├─ Step 3: pause 2m
   ├─ Step 4: setWeight 50%
   │    └─ ALB: 50% → canary, 50% → stable
   ├─ Step 5: analysis (success-rate, 5×30s)
   │    └─ Prometheus: success rate >= 95%? ✅
   ├─ Step 6: pause 2m
   └─ promote → 100% canary（stable 舊 pods 退場）
```

**核心優勢**：流量切換精確（ALB 加權），失敗自動 rollback（Prometheus 指標驅動）。

---

## 元件清單

| 元件 | 位置 | 說明 |
|------|------|------|
| Argo Rollouts controller | `argo-rollouts` namespace | Helm 安裝 |
| `k8s/rollout.yaml` | eks-app | 取代 Deployment，含 canary strategy |
| `k8s/service-canary.yaml` | eks-app | canary 專用 Service |
| `k8s/analysis-template.yaml` | eks-app | Prometheus success rate 分析 |
| `k8s/ingress.yaml` | eks-app | 改為 `use-annotation` backend，Rollouts 管理流量 |

---

## Helm 安裝

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argo-rollouts argo/argo-rollouts \
  -n argo-rollouts --create-namespace \
  --set dashboard.enabled=true
```

---

## Rollout 設定（rollout.yaml）

```yaml
strategy:
  canary:
    stableService: custom-app         # 100% stable 流量
    canaryService: custom-app-canary  # canary 流量
    trafficRouting:
      alb:
        ingress: custom-app
        servicePort: 80
    steps:
      - setWeight: 20        # Step 1: 20% → canary
      - analysis:            # Step 2: Prometheus 分析
          templates:
            - templateName: success-rate
      - pause: {duration: 2m}
      - setWeight: 50        # Step 4: 50% → canary
      - analysis:            # Step 5: 再次分析
          templates:
            - templateName: success-rate
      - pause: {duration: 2m}
      # Step 6 完成後自動 promote → 100%
```

---

## ALB 流量切換原理

Argo Rollouts 透過修改 Ingress annotation 來控制 ALB 加權路由：

```yaml
# Argo Rollouts 自動管理此 annotation
alb.ingress.kubernetes.io/actions.custom-app: |
  {"type":"forward","forwardConfig":{"targetGroups":[
    {"serviceName":"custom-app",        "servicePort":"80","weight":80},
    {"serviceName":"custom-app-canary", "servicePort":"80","weight":20}
  ]}}
```

Ingress backend 改為 `use-annotation` 模式，讓 ALB Controller 讀取 action 而非直連 service：

```yaml
backend:
  service:
    name: custom-app
    port:
      name: use-annotation  # ← 關鍵：指向 action annotation
```

---

## AnalysisTemplate（analysis-template.yaml）

```yaml
spec:
  metrics:
    - name: success-rate
      count: 5          # 執行 5 次（5 × 30s = 2.5 分鐘）
      interval: 30s
      successCondition: result[0] >= 0.95   # 95% 成功率門檻
      failureLimit: 3
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring:9090
          query: |
            (sum(rate(custom_app_http_requests_total{status="200"}[2m])) or vector(1))
            /
            (sum(rate(custom_app_http_requests_total[2m])) or vector(1))
```

`or vector(1)` 防止 canary 剛起來無流量時 query 返回空值導致 Error。

---

## 驗證結果

### Canary 推進記錄（v9 部署）
```
11:13:44  Healthy step=6
AnalysisRun: custom-app-597d59ffb9-3-1: Successful
             custom-app-597d59ffb9-3-4: Successful
```

### 最終狀態
```bash
kubectl get rollout custom-app -n custom-app
# NAME         DESIRED   CURRENT   UP-TO-DATE   AVAILABLE
# custom-app   2         2         2            2

curl http://<ALB>/
# {"version":"v9","uptime":"15m8s",...}
```

---

## Rollback 情境

若 AnalysisRun 失敗（error rate > 5%），Rollouts 自動執行：

```
AnalysisRun: Degraded（failureLimit 超過）
   └── Rollout: abort
         └── setWeight 0%（canary 流量歸零）
               └── canary pods 縮容
                     └── stable 繼續服務
```

手動中止 canary：
```bash
kubectl patch rollout custom-app -n custom-app \
  -p '{"status":{"abort":true}}' --type merge
```

手動 promote（跳過剩餘步驟）：
```bash
kubectl patch rollout custom-app -n custom-app \
  -p '{"status":{"pauseConditions":null}}' --type merge
```

---

## 延伸閱讀

- [gitops-cicd-demo.md](./gitops-cicd-demo.md) — GitHub Actions pipeline（trigger 本 Lab 的 canary）
- [monitoring-demo.md](./monitoring-demo.md) — Prometheus 安裝（AnalysisTemplate 的資料來源）
- [karpenter-demo.md](./karpenter-demo.md) — Karpenter node 自動擴縮（canary 需要額外 node 時自動補上）
