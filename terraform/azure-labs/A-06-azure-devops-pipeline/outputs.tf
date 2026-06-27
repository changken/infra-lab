output "devops_project_url" {
  description = "Azure DevOps 專案 URL（瀏覽器開啟）"
  # TODO: "${var.azuredevops_org_url}/${azuredevops_project.project.name}"
  value = null
}

output "pipeline_url" {
  description = "Pipeline 頁面 URL"
  # TODO: "${var.azuredevops_org_url}/${azuredevops_project.project.name}/_build?definitionId=${azuredevops_build_definition.pipeline.id}"
  value = null
}

output "service_connection_name" {
  description = "Service Connection 名稱（pipeline YAML 中 azureSubscription 用）"
  # TODO: azuredevops_service_endpoint_azurerm.azure_connection.service_endpoint_name
  value = null
}
