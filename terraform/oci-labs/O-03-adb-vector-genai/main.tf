#==============================================================
# 本 lab 沒有網路層：ADB 用 public endpoint + ACL + TLS，
# 讓你本機的後端程式可以直接連（對比 O-02 的 private endpoint + Bastion）。
#
#   你的電腦 ──TLS 1521（只有 allowed_cidr 能連）──> ADB
#   ADB ──HTTPS──> Object Storage（PAR：讀範例資料與 ONNX 模型）
#   ADB ──HTTPS──> OCI Generative AI（Gemini chat，在 sql/ 內設定）
#==============================================================

#--------------------------------------------------------------
# TODO 1: Autonomous Database（23ai 以上，public endpoint + ACL）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/database_autonomous_database
#
# 基本欄位和 O-02 的 TODO 1 相同（compartment_id、db_name、display_name、
# admin_password、db_workload、compute_model、compute_count、
# data_storage_size_in_gb、is_free_tier、license_model、freeform_tags），
# 請自己寫，不要直接複製 O-02。
#
# 本 lab 新增／不同的欄位：
#   db_version                  = ???    # var.db_version；想一想為什麼不能用 19c
#   whitelisted_ips             = [???]  # ACL：只放你的 IP
#   is_mtls_connection_required = ???    # 想讓後端不帶 wallet 連線，這裡該是什麼？
#
# ⚠️ 注意：
#   - 不要設 subnet_id／nsg_ids（那是 private endpoint，和 whitelisted_ips 互斥）
#   - 關閉 mTLS 的前提是有 ACL 或 private endpoint，否則 API 會拒絕
#   - 本 lab 不開 auto scaling、不開 Data Guard（O-02 練過了，這裡只會多花錢）
#   - admin_password 考慮 lifecycle ignore_changes
#   - 建立約 5–15 分鐘

resource "oci_database_autonomous_database" "this" {
  # TODO 1
  compartment_id              = var.compartment_id
  db_name                     = var.db_name
  display_name                = "${var.name_prefix}-adb"
  admin_password              = var.admin_password
  db_workload                 = var.db_workload
  compute_model               = "ECPU"
  compute_count               = var.compute_count
  data_storage_size_in_gb     = var.data_storage_gbs
  is_free_tier                = false
  license_model               = "LICENSE_INCLUDED"
  freeform_tags               = local.common_tags
  db_version                  = var.db_version
  whitelisted_ips             = [var.allowed_cidr]
  is_mtls_connection_required = false

  lifecycle {
    ignore_changes = [admin_password]
  }
}

#--------------------------------------------------------------
# TODO 2: Object Storage bucket
#--------------------------------------------------------------
# 文件:
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/objectstorage_namespace
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_bucket
#
# (a) data "oci_objectstorage_namespace"：
#   compartment_id = ???    # namespace 是整個 tenancy 一個，每個 bucket 操作都要帶
#
# (b) oci_objectstorage_bucket 需要設定：
#   compartment_id = var.compartment_id
#   namespace      = ???                    # (a) 的結果
#   name           = "${var.name_prefix}-bucket"
#   access_type    = ???                    # ⚠️ 不要公開；公開與否和 PAR 是兩回事
#   freeform_tags  = local.common_tags
#
# 對比 AWS：S3 bucket 名稱全球唯一；OCI bucket 名稱只需在 namespace 內唯一。

data "oci_objectstorage_namespace" "this" {
  # TODO 2 (a)
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "this" {
  # TODO 2 (b)
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${var.name_prefix}-bucket"
  access_type    = "NoPublicAccess"
  freeform_tags  = local.common_tags
}

#--------------------------------------------------------------
# TODO 3: 上傳範例資料與 ONNX 模型
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_object
#
# locals.tf 已提供 local.upload_files（物件名稱 => 本機路徑），用 for_each 逐一上傳：
#   for_each  = ???
#   namespace = ???
#   bucket    = ???    # bucket 的 name，不是 OCID
#   object    = ???    # 物件名稱（each 的哪一邊？）
#   source    = ???    # 本機路徑
#
# 想一想：本機檔案內容改了，Terraform 怎麼知道要重新上傳？（看文件的 content_md5）
#
# ⚠️ 注意：
#   - models/ 是空的時候只會上傳 CSV；ONNX 模型要先依 README 下載
#   - 模型檔約一百多 MB，上傳要一點時間

resource "oci_objectstorage_object" "files" {
  # TODO 3
  for_each  = local.upload_files
  namespace = data.oci_objectstorage_namespace.this.namespace
  bucket    = oci_objectstorage_bucket.this.name
  object    = each.key
  source    = each.value
  # content_md5 需為「base64 編碼的二進位 MD5」；filemd5() 是 hex，會被服務端以 digest 不符拒絕，故不設。
  # 代價：本機檔案內容變更不會自動重傳（要改用 terraform apply -replace='oci_objectstorage_object.files["..."]'）。
}

#--------------------------------------------------------------
# TODO 4: Pre-authenticated request（PAR）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_preauthrequest
#
# 讓 ADB 不需要任何憑證就能讀 bucket 內的物件（對比 S3 presigned URL）。
#
# 需要設定：
#   namespace             = ???
#   bucket                = ???
#   name                  = "${var.name_prefix}-par"
#   access_type           = ???    # 整個 bucket 唯讀；查文件有哪些值，不要給寫入權限
#   bucket_listing_action = ???    # 要不要允許列出物件？
#   time_expires          = var.par_expires_at
#
# ⚠️ 注意：
#   - PAR URL 等同密碼：任何拿到的人都能讀，output 要 sensitive，不要貼到公開的地方
#   - PAR URL 只在建立當下回傳一次，之後只存在 tfstate（再次提醒 tfstate 不進 Git）
#   - 不指定 object 就是 bucket 層級的 PAR，物件網址 = PAR 網址 + 物件名稱

resource "oci_objectstorage_preauthrequest" "this" {
  # TODO 4
  namespace             = data.oci_objectstorage_namespace.this.namespace
  bucket                = oci_objectstorage_bucket.this.name
  name                  = "${var.name_prefix}-par"
  access_type           = "AnyObjectRead" # bucket 層級（不指定 object）只能用 Any* 系列；ObjectRead 需搭配 object
  bucket_listing_action = "Deny"
  time_expires          = var.par_expires_at
}
