# OCI Labs - AI 協作規範

OCI 學習 labs，對標 AWS（`../labs/`）與 Azure（`../azure-labs/`）。
共通規範請見上層 [`../agents.md`](../agents.md)；本文件只記錄 **OCI 專屬** 的差異與護欄。

## 帳號背景

- **方案**：Pay As You Go（PAYG），**不是**純 Free Tier
- **Credit**：400 SGD，**2026-11-22 到期**；到期後超出 Always Free 的資源直接扣信用卡
- **Home region**：`ap-singapore-1`（只有 **1 個 AD**）
- **認證**：`~/.oci/config` 的 `[DEFAULT]`（API key），Provider 不寫入任何金鑰

## 目錄

```
oci-labs/
├── AGENTS.md
├── O-01-base-database/   # Base Database（對比 RDS Oracle）
├── O-02-autonomous-database/ # Autonomous Database（對比 Aurora）
├── O-03-adb-vector-genai/ # ADB AI Vector Search + Generative AI（對比 Aurora + pgvector + Bedrock）
├── O-04-mysql-heatwave/  # MySQL HeatWave（對比 RDS MySQL）
├── O-05-postgresql/      # OCI Database with PostgreSQL（對比 RDS／Aurora PostgreSQL）
├── O-06-oke-cluster/     # OKE（對比 EKS）
├── O-07-edge-security/   # LB + WAF + Network Firewall + Bastion（對比 ALB + WAF + Network Firewall + SSM）
└── O-08-cpu-llm/         # CPU 自架 LLM（E5 Flex，import 自 Console 手動建立的實例）
```

## 學習路線（2026-11-16 重新規劃）

方向：backend + AI agent 整合會用到、且平常捨不得開的服務為主（AI、資安、效能三條線），不走純 DBA 題材。

| 順序 | 編號 | Lab | 對標 AWS | 捨不得開的部分 | 額度（11/16 查） | 狀態 |
|---|---|---|---|---|---|---|
| — | O-01 | Base Database | RDS Oracle | Base DB + 授權 | `vm-basedb-x86-ecpu-count` 8 | ✅ 完成（已 destroy） |
| — | O-02 | Autonomous Database（付費 ECPU、Data Guard、private endpoint） | Aurora | 付費 ADB | `atp-ecpu-count` 32 | ✅ 完成（已 destroy） |
| 1 | O-03 | ADB Vector Search + Generative AI（自帶 ADB，23ai 以上；embedding／chat、Select AI） | Aurora + pgvector + Bedrock | 付費 ADB、GenAI 推論 | ✅（Singapore GenAI 只有 Gemini chat，無 embedding 模型 → embedding 用資料庫內 ONNX） | 🚧 骨架已建（TODO 待填） |
| 2 | O-04 | MySQL HeatWave（HA + HeatWave cluster + 內建向量／LLM） | RDS MySQL | HeatWave 節點 | ✅ `mysql-N-count` 100、`mysql-heatwave-*` 100（用 ECPU 制 `MySQL.N` shape） | ✅ TODO 1～5 與 SQL-1～3 已實測（Bastion 連線、HeatWave offload、VECTOR 搜尋、GenAI RAG 皆成功；DB system 不可掛 NSG，改用 security list；HeatWave 節點用 `HeatWave.32GB`）；HA failover 秒數與 InnoDB／HeatWave 耗時未記錄 |
| 4 | O-05 | PostgreSQL（HA + reader endpoint） | RDS／Aurora PostgreSQL | 多節點 DB system | ✅ `dbsystem-e5-count` 20（`dbsystem-count` 為 0，但用 E5 shape 不會被擋，已 apply 驗證） | ✅ 已 destroy（單節點連線成功、HA 3 instance 建立成功；failover、reader endpoint、p95 未量測） |
| — | O-06 | OKE | EKS | — | — | ✅ 完成（已 destroy） |
| 3 | O-07 | LB + WAF + Network Firewall + Bastion（`MANAGED_SSH`） | ALB + WAF + Network Firewall + SSM | Network Firewall | ✅ LB、WAF、Bastion；Network Firewall 未查 | 🚧 TODO 已填、validate 通過、尚未 apply（Network Firewall 的 FQDN／SNAT／路由導向、單價與額度未驗證） |
| 5 | O-08 | CPU 自架 LLM（1 台 `VM.Standard.E5.Flex` 8 OCPU / 64 GB，llama.cpp 或 Ollama + 7B–8B Q4 量化模型；與 O-03 託管 GenAI 比延遲與每百萬 token 成本） | EC2（CPU 推論） | 大規格 compute | ✅ `standard-e5-core-count` 83、`standard-e5-memory-count` 1250（GPU 版因 `gpu-a10-count` 調額被拒而放棄） | 🚧 實例已在 Console 開好並 import（實際 23 OCPU / 276 GB / boot 1024 GB，比規劃大），LLM 尚未部署 |
| 6 | O-09 | Kafka 事件骨幹（integration event／outbox） | MSK | 託管 Kafka 叢集 | 未查 | 規劃（選做） |

- **已移除**：GoldenGate + Base DB（原 O-05，Oracle 對 Oracle 複寫離主軸太遠）、Exadata Exascale（原 O-09，純 DBA 題材，且 `exadbxs-*` 額度為 0）。
- 效能線不另開 lab：O-04、O-05 的驗證章節加負載測試，記錄 p95 延遲與 failover 中斷時間。
- 11/21 全部 `terraform destroy`，再用 `oci` CLI 檢查殘留資源（cluster / LB / DB system / GPU instance）。
- 新 lab 都沒有 Always Free 可用，全部耗 credit；單價與 Singapore 供應需開 lab 前用 Cost Estimator 確認。
- Always Free 內的服務（Functions、API Gateway、NoSQL、Vault、Queue、Streaming、DevOps 等）不急，credit 到期後再補。

長駐、已存在的資源在 `../envs/oci-*`（governance / vcn / linux），**lab 不要修改它們**。

## 護欄（務必遵守）

1. **絕不 destroy／replace `envs/oci-linux` 的 A1 實例**。Singapore 的 A1 常缺貨，刪了可能開不回來。
2. **A1 Always Free 額度是全帳號共用，且已用滿**：總額 4 OCPU / 24 GB，`oci-linux` 的兩台 A1（各 2 OCPU / 12 GB）已全部佔用（2026-11-16 以 CLI 確認）。
   **lab 可用的 A1 額度為 0**：新 lab 的 compute 一律用付費 shape（如 `VM.Standard.E4.Flex`）並加數量 validation；Block volume 合計 200 GB（已用 2 × 47 GB）。
   帳號的 Service Limit 顯示 A1 還有 250 OCPU 可開 → **沒有硬性上限，開了就計費**。
3. **付費資源註明到期日**：README 的成本章節要標示是否在 Always Free 內，以及「11/22 前必須 destroy」。
4. **K8s 建立的資源 Terraform 管不到**：`Service type=LoadBalancer` 會建 OCI LB。README 的「結束」章節必須先寫 `kubectl delete svc`，再 `terraform destroy`。
5. **IAM／Budget 屬 tenancy 層級**，由 `../envs/oci-governance` 管理；lab 內不要建 policy／group。
6. **對外 IP 變動**要同步更新：`envs/oci-vcn` 的 `ssh_allowed_cidr`、`envs/oci-governance` 的 `home_ip_cidr`，以及各 lab 的 `allowed_cidr`。

## OCI 慣例

- **每個資源都要 `compartment_id`**，lab 一律放 `homelab`（取自 `envs/oci-governance` output）。
- Tags 用 `freeform_tags = local.common_tags`（`Project / Environment / ManagedBy / Lab`）。OCI 會自動加 `Oracle-Tags.*` defined tags，import 的資源需 `ignore_changes = [defined_tags]`。
- 查 Availability Domain 用 **tenancy** OCID，不是 compartment。
- Security List 與 NSG 規則是**疊加**的，兩邊都要限制才有效。
- Identity Domains 的 group 用 `oci_identity_domains_group`，不是 `oci_identity_group`。
- `terraform.tfvars`、`*.tfstate`、`kubeconfig` 不進 Git。

## 驗證用 CLI

```bash
oci iam region list                                     # 認證是否正常
oci limits resource-availability get --service-name compute \
  --limit-name standard-a1-core-count -c <tenancy> \
  --availability-domain <AD>                            # A1 額度
oci ce cluster list -c <compartment> --lifecycle-state ACTIVE   # 是否有殘留叢集
oci lb load-balancer list -c <compartment>              # 是否有殘留 LB
```

> Windows Git Bash 下 OCI CLI 會印出 `Get-Acl` 錯誤，是檢查設定檔權限失敗，**不影響結果**，可忽略。

## 更新記錄

- 2026-11-20: O-05 改 HA（`instance_count = 3`，`is_regionally_durable = false`；Singapore 只有 1 個 AD，true 會被 400-InvalidParameter 拒絕）；單節點改 HA 是 replace，舊 DB 與資料會消失；CLI 列表指令更正為 `oci psql db-system-collection list-db-systems`，failover 為 `oci psql db-system failover`

- 2026-11-20: O-05 單節點 apply 成功、Bastion tunnel + DataGrip 連線驗證通過；`psql_shape` 名稱更正為 `PostgreSQL.VM.Standard.E5.Flex`（原寫的 `.2.32GB` 後綴會造成 plan 想 in-place 改 shape）；`instances` output 取代 `instance_private_ips`（provider 的 `instances` 屬性沒有 private IP）

- 2026-11-19: O-07-edge-security 填完 TODO 1～5（LB、WAF OWASP SQLi/XSS + rate limit、Network Firewall FQDN allow + drop-all + SNAT、MANAGED_SSH Bastion）；validate 通過，未 plan／apply
- 2026-11-19: 新增 O-07-edge-security 骨架（LB public subnet、backend ×2 private + Bastion plugin、TODO：LB／WAF／Network Firewall／MANAGED_SSH Bastion；`terraform validate` 通過，未 apply）
- 2026-11-19: O-05 apply 被 `dbsystem-count`（額度 0）擋下：Singapore 的 PostgreSQL 只提供 E5／E6／Standard3 shape（`oci psql shape-summary list-shapes --all`），沒有 E4，E4 會落到通用額度；預設 shape 改為 `PostgreSQL.VM.Standard.E5.Flex`（shape 名稱不含 `.2.32GB`，OCPU／記憶體由 `instance_ocpu_count`／`instance_memory_gbs` 另外指定；用 `dbsystem-e5-count` 20），2026-11-20 apply 成功

- 2026-11-19: O-05-postgresql 填完 TODO 1～5 與 SQL；`terraform validate` 通過（未 plan／apply；單節點用單 AD 儲存、instance_count > 1 時改 regional 儲存，備份關閉）

- 2026-11-19: 新增 O-05-postgresql 骨架（private subnet + Bastion、`oci_psql_db_system`、HA / reader endpoint TODO、`sql/` failover 探測腳本；shape、單價、額度未驗證，尚未 init／validate）

- 2026-11-20: O-04 實測：HeatWave GenAI 在 Singapore 可用；`heatwave_shape` 的有效值為 `HeatWave.32GB`／`512GB`／`Free`（`256GB` 被拒）；聚合查詢 EXPLAIN 確認走 secondary engine RAPID
- 2026-11-20: O-04-mysql-heatwave 填完 TODO 1～5 並 apply：MySQL.2 單節點經 Bastion 連線成功；DB system 掛 `nsg_ids` 會 `FAILED`（`AuthorizationFailed`，拿掉後 ~9 分鐘 ACTIVE），改用 subnet security list 放行 3306／33060；HA（TODO 2）、HeatWave（TODO 3）、SQL 尚未實測
- 2026-11-19: 新增 O-04-mysql-heatwave 骨架（private subnet + Bastion、HA、HeatWave cluster、`sql/` 填空腳本；單價、HeatWave shape、Singapore HeatWave GenAI 支援待確認）
- 2026-11-19: 新增 O-08-cpu-llm：Console 手動建立的 E5 Flex 實例以 `terraform import` 納管（名稱 / IP / 規格放 variables，無 replace）；實際規格 23 OCPU / 276 GB / boot 1024 GB ultra high，遠大於規劃
- 2026-11-16: `gpu-a10-count` 調額申請被 Oracle 拒絕，O-08 由 GPU 版改為 E5 CPU 版（`VM.Standard.E5.Flex`，額度以 CLI 確認）
- 2026-11-16: 新增 O-03-adb-vector-genai 骨架（public endpoint + ACL + TLS、Object Storage + PAR、`sql/` 填空腳本；單價待 Cost Estimator 確認，Select AI + Gemini 未實測）
- 2026-11-16: 重新規劃學習路線（偏 backend + AI agent、平常捨不得開的服務）：移除 GoldenGate 與 Exascale；O-03 加 Generative AI、O-07 加 Network Firewall；新增 O-05 PostgreSQL、O-09 Kafka；O-08 改為 GPU 自架 LLM（已送 `gpu-a10-count` 調額）；A1 護欄更正為 lab 可用 0
- 2026-11-12: O-01 改為 private subnet + OCI Bastion（新增 TODO 4/5，移除 IGW / 公網 IP）
- 2026-11-12: 重新編號（O-02→O-01、O-04→O-06）並加入學習路線 O-02~O-09
- 2026-11-12: 新增 O-02-autonomous-database 骨架（TODO 填空式，單價待 Cost Estimator 確認）
- 2026-11-09: 新增 O-01-base-database（原 O-02）（無 Always Free，全部耗 credit，11/22 前 destroy）
- 2026-11-06: 建立 oci-labs 與 O-06-oke-cluster（原 O-04）
