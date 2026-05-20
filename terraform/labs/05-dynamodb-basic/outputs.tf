output "table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.orders.name
}

output "table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.orders.arn
}

# TODO: gsi_name
#   提示：aws_dynamodb_table.orders.global_secondary_index 是 set，
#         用 tolist(...)[0].name 取第一個（這個 lab 只有一個 GSI）

# TODO: item_count
#   提示：length(aws_dynamodb_table_item.sample) — 印出你塞了幾筆資料

output "gsi_name"{
  description = "Name of the GSI"
  value       = tolist(aws_dynamodb_table.orders.global_secondary_index)[0].name
}

output "item_count"{
  description = "Number of items in the table"
  value       = length(aws_dynamodb_table_item.sample)
}