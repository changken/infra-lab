# K3s on Hetzner Cloud — 從零到 GitOps 的完整建置日記

> 一個人從裸機到 full GitOps CI/CD pipeline 的完整旅程。
> 包含所有踩過的坑、做過的決策、以及為什麼選 A 不選 B。

**技術棧：** K3s · ARM64 (Hetzner CAX) · ArgoCD · Traefik · cert-manager · Tailscale · Sealed Secrets · kube-prometheus-stack

**本 Repo** 即為 ArgoCD 所管理的 GitOps source of truth。

---

## 目錄

- [架構總覽](#架構總覽)
- [Phase 1 — Cluster 初始建置](#phase-1--cluster-初始建置-day-1)
- [Phase 2 — 監控與安全存取](#phase-2--監控與安全存取-day-2)
- [Phase 3 — ArgoCD GitOps 納管](#phase-3--argocd-gitops-納管-day-3)
- [Phase 4 — 第一個 App 的 CI/CD Pipeline](#phase-4--第一個-app-的-cicd-pipeline-drawcardapp)
- [Repo 結構](#repo-結構)
- [費用明細](#費用明細)
- [全階段踩坑總結](#全階段踩坑總結)
- [Roadmap](#roadmap)

---

## 架構總覽

```
                         Internet
                            │
                     ┌──────┴──────┐
                     │  Hetzner FW │
                     └──────┬──────┘
                            │
               ┌────────────┼────────────┐
               │            │            │
          k3s-master   k3s-worker-1  k3s-worker-2
          (CAX21)      (CAX11)       (CAX11)
          Public IP    Public IP     Public IP
               │            │            │
               └────────────┼────────────┘
                            │
                     Hetzner VPC
                     10.0.0.0/16
                            │
                       Tailscale
                     (overlay mesh)
                            │
                        本機 / 手機


git push (app repo)
  │
  ▼
GitHub Actions
  ├── build multi-arch image (amd64 + arm64)
  ├── push → ghcr.io
  └── yq 更新 k3s-gitops image tag → commit + push
                │
                ▼
           ArgoCD (in-cluster，僅 Tailscale 可存取)
             └── 偵測 GitOps repo diff → rolling update
                        │
                        ▼
              App Pod (ARM64) — TLS via cert-manager
```

### 節點規格

| 角色 | 機型 | vCPU | RAM | 備註 |
|------|------|------|-----|------|
| Control Plane | CAX21 (ARM64) | 4 | 8 GB | 同時跑監控元件 |
| Worker × 2 | CAX11 (ARM64) | 2 | 4 GB | 工作負載節點 |

### 為什麼選 ARM64？

- 同規格比 x86 (CX) 便宜
- K3s、.NET、Node.js 都有完善的 ARM64 支援
- 偶爾踩到沒有 ARM64 build 的 Helm chart，本身就是一種學習

### 為什麼 Control Plane 用 CAX21 不用 CAX11？

- K3s control plane 大約吃 ~1.5 GB
- kube-prometheus-stack 大約吃 ~2 GB
- CAX11 (4 GB) 會在 OOM 邊緣掙扎，CAX21 vs CAX11 價差極小，買穩定值得

---

## Phase 1 — Cluster 初始建置 (Day 1)

### 1.1 Hetzner 網路配置

**Private Network (VPC)**
- CIDR: `10.0.0.0/16`
- 機房: Helsinki (`hel1`)
- 所有 K3s 節點都加入此 VPC

**Firewall 規則**

Master firewall：

| 方向 | 來源 | 協定/Port | 用途 |
|------|------|-----------|------|
| Inbound | `10.0.0.0/16` | ALL | VPC 內部全開 |
| Inbound | `0.0.0.0/0` | TCP/22 | SSH |
| Inbound | `0.0.0.0/0` | TCP/6443 | kubectl 遠端管理 |

Worker firewall：

| 方向 | 來源 | 協定/Port | 用途 |
|------|------|-----------|------|
| Inbound | `10.0.0.0/16` | ALL | VPC 內部全開 |
| Inbound | `0.0.0.0/0` | TCP/22 | SSH |

> Worker 不需要對外開 6443，cluster 內部通訊走 VPC。

Worker 有 public IP 是為了 SSH 方便 debug。安全性靠 firewall 擋，不是靠藏 IP。

### 1.2 Master Node 安裝

```bash
hostnamectl set-hostname <YOUR_MASTER_HOSTNAME>

apt update && apt upgrade -y
apt install -y curl git

curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644 \
  --tls-san <YOUR_MASTER_PUBLIC_IP> \
  --tls-san <YOUR_MASTER_VPC_IP>
```

| 參數 | 用途 |
|------|------|
| `--disable traefik` | 之後自己選 ingress 方案 |
| `--disable servicelb` | 之後自己選 LB 方案 |
| `--write-kubeconfig-mode 644` | 讓非 root user 也能讀 kubeconfig |
| `--tls-san` | 把 public IP + VPC IP 加進 TLS 憑證 SAN |

> **Phase 2 更新：** 後來 MetalLB 在 Hetzner VPC 踩坑失敗，最終回頭啟用 K3s 內建的 Traefik + ServiceLB。詳見 [Phase 2 決策](#21-ingress-策略metallb-的坑)。

```bash
# 驗證
systemctl status k3s
kubectl get nodes

# 記下 join token，worker 加入要用
cat /var/lib/rancher/k3s/server/node-token
```

### 1.3 Worker Node（cloud-init 自動化）

```yaml
#cloud-config
hostname: <YOUR_WORKER_HOSTNAME>

runcmd:
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --auth-key=<YOUR_TAILSCALE_AUTHKEY> --hostname=<YOUR_TS_HOSTNAME>
  - curl -sfL https://get.k3s.io | K3S_URL=https://<MASTER_VPC_IP>:6443 K3S_TOKEN=<NODE_TOKEN> sh -
```

> Worker join 走 VPC IP — 同機房內部流量免費、延遲最低。不走 public IP，也不走 Tailscale IP。

| 變數 | 來源 |
|------|------|
| `<YOUR_TAILSCALE_AUTHKEY>` | Tailscale Console → Settings → Auth Keys（建議 reusable + ephemeral） |
| `<NODE_TOKEN>` | Master 上 `cat /var/lib/rancher/k3s/server/node-token` |

### 1.4 安裝後設定

```bash
# 加上 worker role label（K3s 不會自動加）
kubectl label node <WORKER_1> node-role.kubernetes.io/worker=worker
kubectl label node <WORKER_2> node-role.kubernetes.io/worker=worker

# 驗證
kubectl get nodes
# NAME          STATUS   ROLES           VERSION
# master        Ready    control-plane   v1.x.x+k3s1
# worker-1      Ready    worker          v1.x.x+k3s1
# worker-2      Ready    worker          v1.x.x+k3s1
```

從本機遠端操作 kubectl：
```bash
scp root@<MASTER_PUBLIC_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/<MASTER_PUBLIC_IP>/g' ~/.kube/config
```

### 1.5 踩坑紀錄 — Phase 1

| 問題 | 原因 | 解法 |
|------|------|------|
| 非 root user 無法讀 kubeconfig | K3s 預設 kubeconfig 權限是 `600`（僅 root） | 安裝時加 `--write-kubeconfig-mode 644` |
| Worker role 顯示 `<none>` | K3s 不會自動標記 worker role | `kubectl label node <n> node-role.kubernetes.io/worker=worker` |
| 改完 hostname 後舊名稱還在 | K3s node 名稱在第一次註冊時就鎖定了 | `kubectl delete node <舊名>` → `systemctl restart k3s` → 用新名稱重新註冊 |

**心得：** 一定要先改好 hostname **再**裝 K3s。

---

## Phase 2 — 監控與安全存取 (Day 2)

### 2.1 Ingress 策略：MetalLB 的坑

這是整個建置過程中最大的繞路。

| 方案 | 結果 | 原因 |
|------|------|------|
| MetalLB L2 + ingress-nginx | ❌ 失敗 | Hetzner VPC **不允許 ARP 廣播** — L2Advertisement 直接沒用 |
| MetalLB BGP | ❌ 跳過 | 需要 Floating IP + BGP peer 設定，單一用途不值得 |
| hcloud-cloud-controller-manager | ⚠️ 可行但跳過 | 每月多 ~€5 的 Hetzner LB 費用，學習環境不划算 |
| **ServiceLB + Traefik（K3s 內建）** | ✅ 採用 | 零配置、免費、夠用 |

**教訓：** MetalLB 是給**裸機 LAN** 環境用的。雲端 VPC 要用雲廠商原生 LB 或其他方案。

所以 K3s 安裝參數改了 — Traefik 和 ServiceLB 重新啟用：
```bash
curl -sfL https://get.k3s.io | sh -s - server \
  # Traefik + ServiceLB：不 disable
  --write-kubeconfig-mode 644 \
  --tls-san <YOUR_MASTER_PUBLIC_IP> \
  --tls-san <YOUR_MASTER_VPC_IP>
```

### 2.2 cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io && helm repo update

helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true --wait
```

ClusterIssuer（搭配 Traefik）：
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <YOUR_EMAIL>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik   # 不是 nginx — 我們用 K3s 內建的
```

### 2.3 kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.adminPassword=<YOUR_GRAFANA_PASSWORD> \
  --wait
```

服務暴露策略：

| 服務 | Type | 對外暴露 | 存取方式 |
|------|------|----------|----------|
| Grafana | LoadBalancer (Tailscale) | 僅 Tailnet | `http://<TAILSCALE_HOSTNAME>` |
| Prometheus | ClusterIP | ❌ | `kubectl port-forward :9090` |
| Alertmanager | ClusterIP | ❌ | `kubectl port-forward :9093` |

### 2.4 Tailscale Operator — 安全暴露 Grafana

目標：讓 Grafana Web Dashboard 可以存取，但不開放在公網上。

| 方案 | 評估 |
|------|------|
| 換 port | ❌ Security through obscurity，port scan 就找到 |
| Traefik BasicAuth | ⚠️ 可用但不夠強 |
| Traefik IP Whitelist (CGNAT range) | ⚠️ 可用 |
| **Tailscale Operator** | ✅ 公網零暴露 |
| kubectl port-forward | ⚠️ 備案，最簡單但不持久 |

**安裝步驟 — 順序很重要！**

**Step 1：在 Tailscale Admin Console 設定 ACL tags**
```jsonc
{
  "tagOwners": {
    "tag:k8s-operator": ["autogroup:admin"],
    "tag:k8s":          ["tag:k8s-operator"],
    "tag:ken-core":     ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:ken-core"],
      "dst": ["tag:k8s:*", "tag:k8s-operator:*"]
    }
  ]
}
```

**Step 2：建立 OAuth Client（必須綁定上面建好的 tag）**
- Scopes：`auth_keys:write`、`devices:write`、`routes:write`
- Tags：`tag:k8s-operator`

**Step 3：安裝 Operator**
```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts && helm repo update

helm install tailscale-operator tailscale/tailscale-operator \
  -n tailscale --create-namespace \
  --set oauth.clientId=<YOUR_CLIENT_ID> \
  --set oauth.clientSecret=<YOUR_CLIENT_SECRET> \
  --wait
```

**Step 4：暴露 Grafana**
```bash
kubectl annotate svc monitoring-grafana -n monitoring \
  tailscale.com/expose="true" \
  tailscale.com/hostname="<YOUR_GRAFANA_TS_HOSTNAME>"

kubectl patch svc monitoring-grafana -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

### 2.5 踩坑紀錄 — Phase 2

| 問題 | 原因 | 解法 |
|------|------|------|
| Tailscale OAuth 403 | scope 不夠 | 必須勾選 `auth_keys:write`、`devices:write`、`routes:write` |
| Tailscale OAuth 400 | ACL tag 還不存在 | 建立 tag 要在建立 OAuth Client **之前** |
| Tailscale 流量被 drop | ACL 沒有放行 `ken-core → k8s` | 加上明確的 ACL 規則 |
| Grafana `EXTERNAL-IP: <pending>` | K3s ServiceLB 和 Tailscale Operator 同時搶同一個 LB Service | 功能正常（走 Tailnet hostname），`kubectl get svc` 顯示不完美 |
| Helm `connection refused` | `KUBECONFIG` 環境變數沒設 | `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` |

**心得：** Tailscale Operator 設定順序：ACL tags → OAuth Client 綁 tags → 安裝 Operator。任何一步反過來就是 403/400。

---

## Phase 3 — ArgoCD GitOps 納管 (Day 3)

### 3.1 安裝 ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

關閉內建 TLS（交給 Tailscale 處理）：
```bash
kubectl patch deployment argocd-server -n argocd \
  --type json \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args", "value": ["/usr/local/bin/argocd-server", "--insecure"]}]'
```

### 3.2 透過 Tailscale 暴露（跟 Grafana 同樣模式）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server-ts
  namespace: argocd
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "<YOUR_ARGOCD_TS_HOSTNAME>"
spec:
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
    - name: http
      port: 80
      targetPort: 8080
  type: ClusterIP
```

```bash
# 取得初始密碼
PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d)

# 透過 Tailscale 登入
argocd login <ARGOCD_TAILSCALE_FQDN> \
  --username admin --password "$PASS" \
  --plaintext --grpc-web

# 立刻改密碼，然後刪除初始 secret
argocd account update-password \
  --current-password "$PASS" \
  --new-password '<YOUR_NEW_PASSWORD>'

kubectl delete secret argocd-initial-admin-secret -n argocd
```

### 3.3 連接 Git Repo

```bash
argocd repo add https://github.com/<YOUR_USER>/<YOUR_GITOPS_REPO>.git \
  --username <YOUR_USER> \
  --password <GITHUB_PAT>   # 需要 repo scope
```

### 3.4 納管順序（依風險由低到高）

```
1. Sealed Secrets        ← 無外部依賴，最安全的起點
2. cert-manager          ← 只有 CRD，爆炸半徑低
3. kube-prometheus-stack  ← Grafana 密碼透過 SealedSecret 管理
4. tailscale-operator    ← OAuth 憑證透過 SealedSecret 管理
5. traefik               ← 特殊處理：K3s 內建，用 HelmChartConfig（不是 Helm source）
```

**為什麼這個順序？** Sealed Secrets 必須先起來，因為後面的元件都需要它來管理 secret。cert-manager 是無狀態的 CRD。監控和網路元件如果設定錯誤會影響整個 cluster，所以放最後。

### 3.5 Secret 管理 — Sealed Secrets

所有 secret 進 Git 之前都經過 `kubeseal` 加密：

```bash
kubectl create secret generic <SECRET_NAME> \
  --namespace <NS> \
  --from-literal=key='value' \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format yaml > infra/<component>/sealed-secret.yaml
```

目前透過此方式管理的 secret：
- Grafana admin 帳密
- Tailscale OAuth client ID + secret

### 3.6 Traefik — 特殊處理

K3s 內建的 Traefik 無法用一般的 Helm source 在 ArgoCD 中管理，因為 chart 存在 K3s API server 內部。解法：用 `HelmChartConfig` CRD。

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    deployment:
      podAnnotations:
        prometheus.io/port: "8082"
        prometheus.io/scrape: "true"
    # ...（完整 values 見 infra/traefik/helmchartconfig.yaml）
```

ArgoCD Application 指向 Git path 而不是 Helm repo：
```yaml
spec:
  source:
    repoURL: https://github.com/<YOUR_USER>/<YOUR_GITOPS_REPO>.git
    path: infra/traefik
    targetRevision: HEAD
```

### 3.7 App of Apps

所有 Application manifest 放在 `apps/` 目錄下。root-app 監控這個目錄：

```yaml
# root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_USER>/<YOUR_GITOPS_REPO>.git
    path: apps
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

新增 app = 在 `apps/` 加一個 YAML 檔 + `git push`。ArgoCD 自動接手。

### 3.8 踩坑紀錄 — Phase 3

| 問題 | 原因 | 解法 |
|------|------|------|
| ArgoCD gRPC 登入失敗 | `--insecure` 沒套用到 deployment | 直接 patch deployment args |
| port-forward `connection reset` | TLS 還在，port 衝突 | 暫時改用 NodePort 繞過 |
| kube-prometheus-stack `OutOfSync` | 孤立 secret 需要 prune | `argocd app sync --prune` |
| Traefik 無法用 Helm source 納管 | chart 在 K3s API server 內部 | 改用 `HelmChartConfig` CRD + Git path source |
| Grafana pod `couldn't find key` | SealedSecret 缺少必要的 key | 確保 `admin-user` 和 `admin-password` 兩個 key 都有 |

---

## Phase 4 — 第一個 App 的 CI/CD Pipeline (drawcardapp)

### 4.1 Pipeline 流程

```
git push (app repo, main branch)
  │
  ▼
GitHub Actions
  ├── QEMU + Buildx 設定
  ├── Build multi-arch image (linux/amd64 + linux/arm64)
  ├── Push → ghcr.io/<user>/drawcardapp:<git-sha>
  └── Clone k3s-gitops → yq 更新 image tag → commit + push
                │
                ▼
           ArgoCD 偵測到 diff → rolling update
```

### 4.2 Dockerfile（Multi-stage、Non-root、Multi-arch）

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["drawcardapp.csproj", "./"]
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
RUN useradd -m appuser
USER appuser
COPY --from=build /app/publish .
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "drawcardapp.dll"]
```

關鍵決策：
- **`useradd`** 不是 `adduser` — ASP.NET slim image 沒有 `adduser`
- **`dotnet publish` 不指定 `-r linux-arm64`** — 讓 Buildx 透過 QEMU 處理架構
- **Port 8080** — non-root 無法 bind 80

### 4.3 GitHub Actions Workflow

`.github/workflows/build.yml` 的關鍵步驟：

1. **QEMU + Buildx** — 啟用 ARM64 交叉編譯
2. **Login to GHCR** — 使用 `GITHUB_TOKEN`（自動提供）
3. **Build & push** — multi-arch manifest `linux/amd64,linux/arm64`
4. **更新 GitOps repo** — clone `k3s-gitops`，`yq` 更新 image tag，commit + push

| Secret | 用途 |
|--------|------|
| `GITHUB_TOKEN` | 自動提供，push 到 GHCR |
| `GITOPS_TOKEN` | 手動建立的 PAT，需要 GitOps repo 的 `contents:write` 權限 |

### 4.4 K8s Manifests

位置：`apps/drawcardapp/`

- **Deployment** — 1 replica，resource limits (128Mi–256Mi / 100m–500m CPU)，liveness + readiness probe 打 `/health`
- **Service** — ClusterIP，port 80 → 8080
- **Ingress** — Traefik `ingressClassName`，cert-manager TLS annotation，Let's Encrypt 自動簽發

### 4.5 ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: drawcardapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_USER>/<YOUR_GITOPS_REPO>
    targetRevision: main
    path: apps/drawcardapp
  destination:
    server: https://kubernetes.default.svc
    namespace: drawcardapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 4.6 踩坑紀錄 — Phase 4

| 問題 | 原因 | 解法 |
|------|------|------|
| `adduser: not found` | ASP.NET slim image 沒有這個指令 | 改用 `useradd -m appuser` |
| ArgoCD sync status 顯示 `Unknown` | GitOps repo token 被 rotate 了 | 把 repo 改為 public（infra manifest 公開可接受） |
| Cluster 拉不到 GHCR image | GHCR package 預設是 private | GitHub Packages → Change visibility → Public |

---

## Repo 結構

```
k3s-gitops/
├── apps/                              # ArgoCD Application manifests
│   ├── sealed-secrets.yaml
│   ├── cert-manager.yaml
│   ├── kube-prometheus-stack.yaml
│   ├── tailscale-operator.yaml
│   ├── traefik-config.yaml
│   └── drawcardapp/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
├── argocd/
│   └── apps/
│       └── drawcardapp.yaml
├── infra/                             # 實際 manifest / Helm values
│   ├── traefik/
│   │   └── helmchartconfig.yaml
│   ├── tailscale/
│   │   └── sealed-oauth.yaml         # SealedSecret（可安全進 Git）
│   ├── monitoring/
│   │   └── grafana-admin-sealed.yaml
│   └── argocd/
│       └── tailscale-svc.yaml
└── root-app.yaml                      # App of Apps 入口
```

---

## 費用明細

| 元件 | 月費 |
|------|------|
| 1× Control Plane (CAX21) | ~€5–8 |
| 2× Worker (CAX11 + public IP) | 每台 ~€4 |
| Tailscale | Free tier |
| cert-manager / Prometheus / Grafana / ArgoCD | 免費 (OSS) |
| **合計** | **~€13–17/月** |

> 跟 minikube/kind 單機模擬相比，這是**真實的多節點 production-like 環境**，對 CKA 備考和作品集的價值高很多。

---

## 全階段踩坑總結

### 基礎設施
1. **MetalLB ≠ 萬能** — 它是裸機 LAN 方案。雲端 VPC 不支援 L2 ARP 廣播。選 LB 之前先搞清楚你的網路環境。
2. **K3s 內建元件就夠用了** — Traefik + ServiceLB 省了好幾個小時的 debug 和每月 €5 的 LB 費用。沒有真正的理由就不要急著換掉預設值。
3. **Tailscale Operator 設定順序很關鍵** — ACL tags → OAuth Client 綁 tags → 安裝 Operator。任何一步反過來就是莫名其妙的 403/400。
4. **K3s ≠ kubeadm** — 預設行為不同（kubeconfig 權限、role label、內建元件）。不要假設一個的行為跟另一個一樣。

### GitOps
5. **納管順序：低風險 → 高風險** — Sealed Secrets 先（無依賴），網路/監控最後（爆炸半徑大）。
6. **K3s 內建 Traefik 要用 HelmChartConfig** — 無法用標準 Helm source 在 ArgoCD 中管理，因為 chart 在 K3s API server 內部。
7. **SealedSecrets 要比所有需要 secret 的元件更早裝** — 事後回想很明顯，但做的時候很容易忘。

### CI/CD
8. **ARM64 cluster 必須 multi-arch build** — Buildx 加一個 `platforms: linux/amd64,linux/arm64` flag 就好，但 Dockerfile 要避免寫死架構的指令。
9. **GHCR 預設 private** — cluster 拉不到 image 直到你手動改 visibility。GitOps repo token 同理。

### 方法論
10. **LLM 是加速工具，不是替代品** — 沒有基礎來判斷 LLM 輸出對不對，就只是加速踩雷而已。
11. **永遠不要把 credential 貼進聊天** — 包括 API token、OAuth secret、密碼。對 AI 助手也一樣。
12. **先改 hostname 再裝 K3s** — node 名稱在第一次註冊時就鎖定了。事後改名要 delete + 重新註冊。

---

## Roadmap

| 優先度 | 項目 | 狀態 |
|--------|------|------|
| ✅ | K3s cluster 初始建置（1 CP + 2 Workers） | 完成 |
| ✅ | 監控（Prometheus + Grafana） | 完成 |
| ✅ | Tailscale Operator（zero-trust 存取） | 完成 |
| ✅ | ArgoCD GitOps + App of Apps | 完成 |
| ✅ | Sealed Secrets | 完成 |
| ✅ | 第一個 app CI/CD (drawcardapp) | 完成 |
| 🔲 | ArgoCD 自管（ArgoCD 管理自己） | 計劃中 |
| 🔲 | cert-manager ClusterIssuer 納入 GitOps | 計劃中 |
| 🔲 | Gateway API 遷移（取代 Ingress） | 計劃中 |
| 🔲 | Network Policy + Kyverno（CKS 準備） | 計劃中 |
| 🔲 | Terraform import 現有 VM → IaC | 計劃中 |

---

## License

MIT
