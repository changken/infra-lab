# ArgoCD GitOps + ALB Ingress 實戰紀錄

## 概念

ArgoCD 是 Kubernetes 的 GitOps controller。核心思路：

```
Git Repository（唯一事實來源）
  └── ArgoCD 持續監控 repo HEAD
        └── 偵測到 manifest 變更 → 自動 sync 到 cluster
              └── Kubernetes 實際狀態 = Git 狀態
```

和傳統 CI/CD 的差異：

| | 傳統 CI/CD（Push） | GitOps（Pull） |
|--|--|--|
| 觸發方式 | CI pipeline 推送到 cluster | ArgoCD 從 cluster 內拉 Git |
| cluster 存取 | CI runner 需要 kubeconfig | 只有 ArgoCD 需要權限 |
| 狀態追蹤 | pipeline log | ArgoCD UI / Git history |
| 回滾 | 重跑舊 pipeline | `git revert` |

---

## 架構

```
GitHub (infra-lab repo)
  └── terraform/envs/aws-eks/k8s/
        ├── custom-app/     ← ArgoCD Application: custom-app
        ├── podinfo/        ← ArgoCD Application: podinfo
        └── argocd/         ← ArgoCD 自身設定（含本文的 Ingress）

ArgoCD（argocd namespace）
  ├── argocd-server  ← UI + API
  ├── argocd-repo-server
  ├── argocd-application-controller
  └── argocd-dex-server（OIDC）

Internet
  └── ALB (eks-argocd group)
        └── argocd-server:80（--insecure 模式，ALB 終止 HTTP）
```

---

## 環境

| 項目 | 值 |
|------|-----|
| ArgoCD 版本 | v2.x（透過 Helm 安裝） |
| Namespace | `argocd` |
| ALB URL | `k8s-eksargocd-c3539cccb2-1655315358.us-east-1.elb.amazonaws.com` |
| ALB group | `eks-argocd`（獨立 ALB，不與其他服務共用） |
| 帳號 | `admin` |
| 初始密碼 | 見下方指令 |

---

## ArgoCD Applications

| Application | Source | 目標 Namespace | 說明 |
|-------------|--------|---------------|------|
| `custom-app` | `k8s/custom-app/` | `custom-app` | Go HTTP service（v7，含 IRSA + Bedrock + RAG） |
| `podinfo` | Helm chart `stefanprodan/podinfo` | `podinfo` | 參考微服務 |
| `kube-prometheus-stack` | Helm chart `prometheus-community` | `monitoring` | Prometheus + Grafana |

---

## 步驟

### 1. ArgoCD 安裝（已完成）

ArgoCD 透過 Helm 安裝於 `argocd` namespace：

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace
```

### 2. 開啟 --insecure 模式

ArgoCD server 預設強制 HTTPS redirect，ALB 走 HTTP 時會造成 redirect loop。
用 ConfigMap 關掉內部 TLS，讓 ALB 直接終止 HTTP：

```yaml
# k8s/argocd/argocd-insecure-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  server.insecure: "true"
```

```bash
kubectl apply -f k8s/argocd/argocd-insecure-cm.yaml
kubectl rollout restart deployment/argocd-server -n argocd
```

### 3. 建立 ALB Ingress

```yaml
# k8s/argocd/argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: eks-argocd
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
```

```bash
kubectl apply -f k8s/argocd/argocd-ingress.yaml

# 取得 ALB URL（約 1-2 分鐘後出現）
kubectl get ingress argocd-server -n argocd
```

### 4. 取得初始密碼

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

> ⚠️ 登入後請至 **User Info → Update Password** 更換密碼，
> 並刪除 `argocd-initial-admin-secret`（Secret 存在代表從未更換過）：
> ```bash
> kubectl delete secret argocd-initial-admin-secret -n argocd
> ```

---

## 驗證

### 登入 ArgoCD UI

```
http://k8s-eksargocd-c3539cccb2-1655315358.us-east-1.elb.amazonaws.com

帳號：admin
密碼：（上方指令取得）
```

### 確認 Applications 狀態

```bash
kubectl get applications -n argocd
# NAME                    SYNC STATUS   HEALTH STATUS
# custom-app              Synced        Healthy
# kube-prometheus-stack   Synced        Healthy
# podinfo                 Synced        Healthy
```

### 手動強制 Sync

```bash
# 用 kubectl annotation 觸發 ArgoCD refresh（不需要 argocd CLI）
kubectl annotate app custom-app -n argocd \
  argocd.argoproj.io/refresh=normal --overwrite

# 觀察 sync 狀態
kubectl get app custom-app -n argocd -w
```

### GitOps 驗證流程

```bash
# 1. 改一個 manifest（例如 replicas）
# 2. git commit + push
# 3. ArgoCD 在 3 分鐘內自動偵測並 sync

# 確認目前的 image 版本
kubectl get pods -n custom-app -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
```

---

## ArgoCD Application 結構

```yaml
# k8s/argocd/custom-app-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: custom-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/changken/infra-lab
    targetRevision: HEAD          # 追蹤 main branch HEAD
    path: terraform/envs/aws-eks/k8s/custom-app
  destination:
    server: https://kubernetes.default.svc
    namespace: custom-app
  syncPolicy:
    automated:
      prune: true      # Git 刪掉的資源，cluster 也刪
      selfHeal: true   # 有人手動改 cluster，自動還原成 Git 狀態
    syncOptions:
      - CreateNamespace=true
```

---

## 注意事項

### HTTP --insecure 的安全考量

本 lab 使用 HTTP（無 TLS），已知風險：
- 帳號密碼在網路上明文傳輸
- ArgoCD token 可能被中間人截取

**可接受的原因：** lab 環境，無敏感資料，短期使用後 `terraform destroy`。

**正式環境升級路徑：**
1. 購買 domain（Route53，~$12/年）
2. 申請 ACM 憑證（免費）
3. ALB Ingress 加上：
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
     alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
     alb.ingress.kubernetes.io/ssl-redirect: "443"
   ```

### 本機 DNS 解不到 ALB hostname

家用路由器 DNS 有時無法解析 `*.elb.amazonaws.com`。
直接用瀏覽器開 URL 通常沒問題（瀏覽器走 OS DNS，OS DNS 通常指向 8.8.8.8 或 ISP DNS）。

驗證方式：
```bash
nslookup k8s-eksargocd-c3539cccb2-1655315358.us-east-1.elb.amazonaws.com 8.8.8.8
```

---

## 費用

| 資源 | 費用 |
|------|------|
| ArgoCD Pods（controller + server + repo-server + dex + redis） | 使用現有節點，無額外費用 |
| ALB (eks-argocd group) | ~$0.016/hr ≈ $0.38/day |

---

## 延伸閱讀

| 文件 | 說明 |
|------|------|
| [irsa-demo.md](./irsa-demo.md) | custom-app IRSA + Bedrock，ArgoCD 管理的主要 workload |
| [monitoring-demo.md](./monitoring-demo.md) | kube-prometheus-stack，同樣透過 ArgoCD 部署 |
| [rag-demo.md](./rag-demo.md) | Poor Man's RAG，custom-app v7 |

---

*紀錄日期：2026-06-22*
*環境：AWS EKS 1.36 / ArgoCD / AWS Load Balancer Controller*
