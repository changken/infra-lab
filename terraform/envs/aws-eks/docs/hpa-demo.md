# HPA (Horizontal Pod Autoscaler) 實戰紀錄

## 環境

| 項目 | 值 |
|------|-----|
| Cluster | `infra-lab-dev-eks` (EKS 1.36) |
| 節點 | 2x t3.medium SPOT |
| 應用 | `custom-app` (Go, ECR image v2) |
| HPA 目標 | CPU 使用率 30% |
| Pod 範圍 | min=2 / max=6 |

---

## 架構

```
Internet
  └── ALB (internet-facing)
        └── custom-app Service
              ├── Pod 1 (平時)
              └── Pod 2 (平時)
                    ↕ HPA 根據 CPU 動態調整至最多 6 pods
```

---

## 步驟

### 1. 安裝 Metrics Server

HPA 需要 Metrics Server 提供 CPU / Memory 即時數據。

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 驗證
kubectl top nodes
```

### 2. 建立 HPA

```bash
kubectl autoscale deployment custom-app \
  -n custom-app \
  --cpu-percent=30 \
  --min=2 \
  --max=6

# 查看狀態（等 metrics 收進來）
kubectl get hpa -n custom-app
```

### 3. 壓力測試（Scale Out）

同時起 5 個 busybox pod 持續打 ALB：

```bash
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

for i in 1 2 3 4 5; do
  kubectl run load-test-$i --image=busybox --restart=Never -n custom-app \
    --command -- sh -c "while true; do wget -q -O- http://$ALB/ > /dev/null; done"
done
```

### 4. 清除壓測（Scale In）

```bash
kubectl delete pod load-test-1 load-test-2 load-test-3 load-test-4 load-test-5 \
  -n custom-app
```

---

## 觀察結果

| 時間 | CPU | Replicas | 事件 |
|------|-----|----------|------|
| 壓測前 | 2% | 2 | 閒置，維持 min |
| 壓測 T+0s | 122% | 2 | 超標，HPA 決策中 |
| 壓測 T+15s | 81% | 2 | 仍在決策 |
| 壓測 T+30s | 29% | 4 | **Scale Out 開始** |
| 壓測 T+45s | 45% | 6 | **擴到 max=6** |
| 壓測結束 | 2% | 6 | Cooldown 等待中 |
| 壓測後 +5分 | 2% | 2 | **Scale In 完成** |

---

## HPA 行為說明

### Scale Out（快）
- 觸發條件：平均 CPU > 目標值
- 反應時間：~30 秒（metrics 抓取間隔 15s × 2）
- 計算公式：`desiredReplicas = ceil(currentReplicas × currentCPU / targetCPU)`
  - 例：`ceil(2 × 122% / 30%) = ceil(8.1) = 6`（上限 max=6）

### Scale In（慢）
- 預設 stabilization window：**5 分鐘**
- 目的：避免流量抖動造成 pod 反覆開關（flapping）
- 5 分鐘內 CPU 持續低於目標才會縮減

### 為什麼 scale out 要等 2 個 metrics 週期？
HPA 需要連續確認 CPU 超標才會觸發，避免偶發性 CPU spike 造成不必要的擴容。

---

## 常用指令

```bash
# 查看 HPA 狀態
kubectl get hpa -n custom-app

# 查看 HPA 詳細事件
kubectl describe hpa custom-app -n custom-app

# 查看 pod 數量變化
kubectl get pods -n custom-app -w

# 即時 CPU 使用率
kubectl top pods -n custom-app

# 刪除 HPA
kubectl delete hpa custom-app -n custom-app
```

---

## 費用影響

| 狀態 | Pods | EC2 費用 |
|------|------|---------|
| 平時 | 2 | ~$0.028/hr (SPOT) |
| 尖峰 | 6 | ~$0.084/hr (SPOT) |

SPOT 節點在 t3.medium 上最多跑 6 pods（受節點資源限制），超過需要 Cluster Autoscaler 或 Karpenter 新增節點。

---

*紀錄日期：2026-06-21*
*環境：AWS EKS 1.36 / Kubernetes HPA v2*
