output "repository_url" {
  description = "ECR repository URL (用於 docker tag 和 docker push)"
  value       = aws_ecr_repository.main.repository_url
}

output "registry_id" {
  description = "AWS Account ID（ECR registry ID）"
  value       = aws_ecr_repository.main.registry_id
}

# TODO: push_commands
#   提示：用 format() 組出完整的 docker push 流程指令（多行字串）：
#
#   Step 1 - 認證：
#   "aws ecr get-login-password --region %s | docker login --username AWS --password-stdin %s"
#   引數：region, registry_url（registry_id + ".dkr.ecr." + region + ".amazonaws.com"）
#
#   Step 2 - Build + Tag + Push：
#   "docker build -t %s ./app"
#   "docker tag %s:latest %s:latest"
#   "docker push %s:latest"
#   引數依序：repository_name, repository_name, repository_url, repository_url
#
#   提示：用 "\n" 連接多行，或直接用 <<-EOF 風格的 format

output "push_commands" {
  description = "Docker push commands"
  value = <<-EOF
aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.main.registry_id}.dkr.ecr.${var.region}.amazonaws.com
docker build -t ${var.repository_name} ./app
docker tag ${var.repository_name}:latest ${aws_ecr_repository.main.repository_url}:latest
docker push ${aws_ecr_repository.main.repository_url}:latest
  EOF
}