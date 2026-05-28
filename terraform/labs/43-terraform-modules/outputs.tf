#--------------------------------------------------------------
# TODO 6: 聚合並輸出 Module 的值
#--------------------------------------------------------------
# 根配置的 output 透過 module.<name>.<output> 引用模組輸出
# 語法：module.api.api_endpoint
#
# 需要輸出的值（依照下方 output block 的 description 填寫）：

output "api_endpoint" {
  description = "API Gateway 呼叫 URL（來自 module.api）"
  # TODO: value = module.api.???
}

output "function_name" {
  description = "Lambda Function 名稱（來自 module.api）"
  # TODO
}

output "vpc_id" {
  description = "VPC ID（來自 module.network）"
  # TODO
}

output "public_subnet_ids" {
  description = "Public Subnet IDs（來自 module.network）"
  # TODO
}

output "sns_topic_arn" {
  description = "Alarm SNS Topic ARN（來自 module.monitoring）"
  # TODO
}

output "curl_command" {
  description = "測試 API 的 curl 指令"
  # TODO: value = "curl -s ${module.api.api_endpoint}/"
}
