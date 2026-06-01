#==============================================================
# Lab 43：Terraform 模組化重構
#
# 根配置（Root Configuration）呼叫三個本地 module：
#   module "network"    → ./modules/networking
#   module "api"        → ./modules/serverless-api
#   module "monitoring" → ./modules/observability
#
# 模組資料流：
#   root 傳 project/environment/tags → 各 module
#   module.api.function_name ──────── → module.monitoring
#   （observability 模組需要 Lambda 名稱，透過 output → variable 傳遞）
#
# 完成順序：1（networking）→ 2（serverless-api）→ 3（observability）
#           → 4（此檔案的 module 呼叫）→ 5（terraform.tf backend）→ 6（outputs.tf）
#==============================================================


# 已完成：打包 Lambda 原始碼（在 root 建立 zip，路徑傳給 serverless-api module）
data "archive_file" "hello" {
  type        = "zip"
  source_file = "${path.module}/src/hello.py"
  output_path = "${path.module}/src/hello.zip"
}


#--------------------------------------------------------------
# TODO 4: 呼叫三個 Module
#--------------------------------------------------------------
# Module 呼叫語法：
#   module "<name>" {
#     source = "<path>"   ← 本地 module 用相對路徑
#     <variable> = <value>
#   }
#
# Module 輸出引用語法：
#   module.<name>.<output_name>
#
# [module "network"]
#   source              = "./modules/networking"
#   project             = var.project
#   environment         = var.environment
#   tags                = local.common_tags
#   # 選填（有預設值，可覆蓋）：
#   # vpc_cidr            = "10.0.0.0/16"
#   # public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
#   # availability_zones  = ["us-east-1a", "us-east-1b"]
#
# [module "api"]
#   source           = "./modules/serverless-api"
#   project          = var.project
#   environment      = var.environment
#   source_zip_path  = data.archive_file.hello.output_path
#   source_code_hash = data.archive_file.hello.output_base64sha256
#   tags             = local.common_tags
#   # 選填：handler, runtime, timeout, memory_size, environment_variables
#
# [module "monitoring"]
#   source               = "./modules/observability"
#   project              = var.project
#   environment          = var.environment
#   lambda_function_name = module.api.function_name   ← 跨 module 資料傳遞！
#   notification_email   = var.notification_email
#   tags                 = local.common_tags
#
# ⚠️ 注意：
#   - 每次新增 module 或修改 source，需要重新執行 terraform init
#   - module.api 必須在 module.monitoring 之前定義（Terraform 能自動解析依賴，
#     但明確的依賴順序讓程式碼更易讀）
#   - networking 模組建立 VPC 但 serverless-api 不需要 VPC（Lambda 預設是公有）
#     兩個模組獨立，根配置決定是否把 networking 的輸出傳給其他模組

module "network" {
  # TODO
  source      = "./modules/networking"
  project     = var.project
  environment = var.environment
  tags        = local.common_tags
}

module "api" {
  # TODO
  source           = "./modules/serverless-api"
  project          = var.project
  environment      = var.environment
  source_zip_path  = data.archive_file.hello.output_path
  source_code_hash = data.archive_file.hello.output_base64sha256
  tags             = local.common_tags
  # 選填：handler, runtime, timeout, memory_size, environment_variables
  handler     = "hello.lambda_handler"
  runtime     = "python3.13"
  timeout     = 10
  memory_size = 128
  environment_variables = {
    ENVIRONMENT = var.environment
    LOG_LEVEL   = "INFO"
  }
}

module "monitoring" {
  # TODO
  source               = "./modules/observability"
  project              = var.project
  environment          = var.environment
  lambda_function_name = module.api.function_name
  notification_email   = var.notification_email
  tags                 = local.common_tags
}
