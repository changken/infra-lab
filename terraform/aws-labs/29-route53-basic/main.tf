#==============================================================
# 學習目標：Route 53 Private Hosted Zone + DNS 記錄 + Health Check + Routing Policy
#
# 核心問題：VPC 內部的服務怎麼用域名互相找到對方？Public 服務又如何做 DNS Failover？
#
# Route 53 的三個角色：
#   1. DNS Resolver（解析域名）
#   2. DNS Registrar（域名申請/管理）← 本 lab 不涉及
#   3. Health Checker（監控端點，配合 Failover Routing）
#
# Hosted Zone 的兩種類型：
#   Public Hosted Zone：
#     → 對全網際網路提供 DNS 解析（需要擁有一個真實域名）
#     → 費用：$0.50/月/zone
#
#   Private Hosted Zone（本 lab 使用）：
#     → 只在關聯的 VPC 內部生效（不需要購買域名）
#     → 適合微服務內部通訊：app.myproject.internal
#     → 費用：$0.50/月/zone
#
# DNS Record 類型（面試常考）：
#   A     → 域名 → IPv4 位址
#   AAAA  → 域名 → IPv6 位址
#   CNAME → 域名 → 另一個域名（不能用於 Zone Apex，即 example.com 本身）
#   ALIAS → AWS 特有，域名 → AWS 資源（可用於 Zone Apex，等同 A record 但不收 DNS 查詢費）
#   MX    → 郵件伺服器
#   TXT   → 文字記錄（常用於驗證域名所有權）
#
# Routing Policy（本 lab 實作 Weighted，面試常問 Failover）：
#   Simple    → 直接回傳 IP（無法搭配 Health Check）
#   Weighted  → 按比例分流（A/B 測試、藍綠部署）
#   Failover  → 主站掛了自動切到備站（需要 Health Check）
#   Latency   → 回傳延遲最低的 Region
#   Geolocation → 依使用者地理位置路由
#   Geoproximity → 回傳離使用者最近的 Region (需啟用 AWS Global Accelerator)
#   
# ⚠️ Health Check 限制：
#   Health Check 只能監控公開可連線的端點（Public IP 或 FQDN）。
#   Private Hosted Zone 的 Failover Routing 需要搭配 CloudWatch Alarm 而非直接 Health Check。
#
# 完成順序：1 → 2 → 3 → 4
#==============================================================


# 已完成：取得預設 VPC（Private Hosted Zone 需要關聯 VPC）
data "aws_vpc" "default" {
  default = true
}


#--------------------------------------------------------------
# TODO 1: Private Hosted Zone
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone
#
# Private Hosted Zone 需要在建立時關聯至少一個 VPC。
# 關聯後，該 VPC 內的 EC2 / Lambda / ECS 等都能用這個 Zone 的域名。
#
#   name    = local.zone_name        # "r53-lab.internal"
#   comment = "Lab 29 private zone"
#   tags    = local.common_tags
#
#   vpc {
#     vpc_id = data.aws_vpc.default.id
#     # ← 關聯 VPC，讓 VPC 內的資源可以解析這個 Zone 的域名
#     # 一個 Zone 可以關聯多個 VPC（跨帳號也可以）
#   }
#
# ⚠️ Private vs Public 的差異在 Terraform 中：
#   private_zone 不是一個 argument，而是 data source 的 filter。
#   建立時只要有 vpc block 就自動是 Private Zone。

resource "aws_route53_zone" "private" {
  # TODO
  name    = local.zone_name
  comment = "Lab 29 private zone"
  tags    = local.common_tags

  vpc {
    vpc_id = data.aws_vpc.default.id
  }
}


#--------------------------------------------------------------
# TODO 2: DNS Records（Simple Routing）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
#
# 建立兩筆記錄：
#
# [A Record] app.r53-lab.internal → 10.0.1.100（模擬應用伺服器 IP）
#   zone_id = aws_route53_zone.private.zone_id
#   name    = "app.${local.zone_name}"
#   type    = "A"
#   ttl     = 300
#   records = ["10.0.1.100"]
#
# [CNAME Record] api.r53-lab.internal → app.r53-lab.internal
#   zone_id = aws_route53_zone.private.zone_id
#   name    = "api.${local.zone_name}"
#   type    = "CNAME"
#   ttl     = 300
#   records = ["app.${local.zone_name}"]
#
# ⚠️ CNAME 不能用於 Zone Apex（即 r53-lab.internal 本身）
#    如果需要在 apex 指向 AWS 資源（如 ALB），要用 ALIAS record（alias block 取代 ttl+records）

resource "aws_route53_record" "app" {
  # TODO
  zone_id = aws_route53_zone.private.zone_id
  name    = "app.${local.zone_name}"
  type    = "A"
  ttl     = 300
  records = ["10.0.1.100"]
}

resource "aws_route53_record" "api" {
  # TODO
  zone_id = aws_route53_zone.private.zone_id
  name    = "api.${local.zone_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["app.${local.zone_name}"]
}


#--------------------------------------------------------------
# TODO 3: Health Check（HTTP）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_health_check
#
# Route 53 Health Checker 全球 15 個節點定期探測目標，
# 超過 failure_threshold 次失敗才標為 Unhealthy（避免短暫網路抖動觸發 Failover）。
#
#   fqdn              = var.health_check_fqdn  # "example.com"
#   port              = 443
#   type              = "HTTPS"
#   resource_path     = "/"
#   # ← 探測的路徑，回傳 2xx/3xx 視為健康
#
#   failure_threshold = 3
#   # ← 連續 3 次失敗才標為 Unhealthy
#
#   request_interval  = 30
#   # ← 每 30 秒探測一次（10 秒的話每月多 $0.50，生產環境才用）
#
#   tags = merge(local.common_tags, {
#     Name = "${var.project}-health-check"
#   })

resource "aws_route53_health_check" "main" {
  # TODO
  fqdn              = var.health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30
  tags = merge(local.common_tags, {
    Name = "${var.project}-health-check"
  })

}


#--------------------------------------------------------------
# TODO 4: Weighted Routing Records
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
#       （同一個 resource，但加上 set_identifier + weighted_routing_policy）
#
# Weighted Routing 讓同一個域名有多筆記錄，依 weight 比例分流。
# 常見用途：藍綠部署（80/20 流量切換）、A/B 測試。
#
# ⚠️ Weighted Routing 必要欄位：
#   set_identifier = 唯一字串，用來區分同名的多筆記錄
#   weighted_routing_policy { weight = N }  # N 是相對權重，所有記錄 weight 加總即為 100%
#
# [Primary，80% 流量]
#   zone_id        = aws_route53_zone.private.zone_id
#   name           = "blue-green.${local.zone_name}"
#   type           = "A"
#   set_identifier = "primary"
#   weighted_routing_policy { weight = 80 }
#   ttl     = 60
#   records = ["10.0.1.100"]
#
# [Secondary，20% 流量]
#   zone_id        = aws_route53_zone.private.zone_id
#   name           = "blue-green.${local.zone_name}"
#   type           = "A"
#   set_identifier = "secondary"
#   weighted_routing_policy { weight = 20 }
#   ttl     = 60
#   records = ["10.0.2.100"]
#
# 思考題：如果 weight 都設為 0，Route 53 會怎麼做？
# 答案：隨機選一筆（相當於 Simple Routing）

resource "aws_route53_record" "weighted_primary" {
  # TODO
  zone_id        = aws_route53_zone.private.zone_id
  name           = "blue-green.${local.zone_name}"
  type           = "A"
  set_identifier = "primary"
  weighted_routing_policy { weight = 80 }
  ttl     = 60
  records = ["10.0.1.100"]


}

resource "aws_route53_record" "weighted_secondary" {
  # TODO
  zone_id        = aws_route53_zone.private.zone_id
  name           = "blue-green.${local.zone_name}"
  type           = "A"
  set_identifier = "secondary"
  weighted_routing_policy { weight = 20 }
  ttl     = 60
  records = ["10.0.2.100"]

}
