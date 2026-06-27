#--------------------------------------------------------------
# TODO 1: Resource Group（供 Service Connection 的權限範圍使用）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group
#
# 需要設定：
#   name     = "${local.name_prefix}-rg"
#   location = var.location
#   tags     = local.common_tags

resource "azurerm_resource_group" "rg" {
  # TODO
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

#--------------------------------------------------------------
# TODO 2: Azure DevOps Project
#--------------------------------------------------------------
# 對比 AWS：CodePipeline 不需要獨立「專案」概念，直接在帳號下建
# Azure DevOps：所有資源（Repo、Pipeline、Board）都在 Project 內
#
# 文件: https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/resources/project
#
# 需要設定：
#   name               = var.devops_project_name
#   visibility         = "private"
#   version_control    = "Git"
#   work_item_template = "Agile"

resource "azuredevops_project" "project" {
  # TODO
  name               = var.devops_project_name
  visibility         = "private"
  version_control    = "Git"
  work_item_template = "Agile"
}

#--------------------------------------------------------------
# TODO 3: Service Connection（Azure DevOps → Azure 訂閱）
#--------------------------------------------------------------
# 對比 AWS：CodePipeline 用 IAM Role；Azure DevOps 用 Service Connection
# Service Connection 讓 pipeline 有權限操作 Azure 資源（push ACR、deploy ACA）
#
# 文件: https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/resources/service_endpoint_azurerm
#
# 需要設定：
#   project_id            = azuredevops_project.project.id
#   service_endpoint_name = "azure-subscription"
#   credentials {
#     serviceprincipalid  = （留空，Terraform 自動建立 Service Principal）
#     serviceprincipalkey = （留空）
#   }
#   settings {
#     subscription_id   = var.subscription_id
#     subscription_name = data.azurerm_subscription.current.display_name
#   }
#
# ⚠️ 注意：Terraform 會自動建立一個 Service Principal 並設定 Azure AD 授權

resource "azuredevops_service_endpoint_azurerm" "azure_connection" {
  # TODO
  project_id            = azuredevops_project.project.id
  service_endpoint_name = "azure-subscription"
  credentials {
    serviceprincipalid  = ""
    serviceprincipalkey = ""
  }
  settings {
    subscription_id   = var.subscription_id
    subscription_name = data.azurerm_subscription.current.display_name
  }
}

#--------------------------------------------------------------
# TODO 4: Role Assignment — Service Connection 可操作 Azure 資源
#--------------------------------------------------------------
# 給 Service Connection 的 Service Principal 足夠的權限
# 對比 AWS：CodePipeline execution role 的 IAM Policy
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
#
# 需要設定：
#   scope                = azurerm_resource_group.rg.id   # 限縮在此 RG
#   role_definition_name = "Contributor"
#   principal_id         = azuredevops_service_endpoint_azurerm.azure_connection.service_principal_id
#
# ⚠️ 注意：生產環境應改用自訂 role，Contributor 權限太大

resource "azurerm_role_assignment" "devops_contributor" {
  # TODO
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuredevops_service_endpoint_azurerm.azure_connection.service_principal_id
}

#--------------------------------------------------------------
# TODO 5: Build Definition（Pipeline）
#--------------------------------------------------------------
# 指向 repo 中的 azure-pipelines.yml，定義 CI/CD 流程
# 對比 AWS：CodePipeline + CodeBuild buildspec.yml
#
# 文件: https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/resources/build_definition
#
# 需要設定：
#   project_id = azuredevops_project.project.id
#   name       = "azure-labs-ci-cd"
#
#   ci_trigger { use_yaml = true }   # 讀取 azure-pipelines.yml 中的 trigger 設定
#
#   repository {
#     repo_type   = "TfsGit"         # Azure DevOps 內建 Git
#     repo_id     = azuredevops_project.project.id
#     branch_name = "refs/heads/main"
#     yml_path    = "azure-pipelines.yml"
#   }
#
# ⚠️ 注意：pipeline YAML 路徑是相對於 repo 根目錄

resource "azuredevops_build_definition" "pipeline" {
  # TODO
  project_id = azuredevops_project.project.id
  name       = "azure-labs-ci-cd"

  ci_trigger { use_yaml = true }

  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_project.project.id
    branch_name = "refs/heads/main"
    yml_path    = "azure-pipelines.yml"
  }
}
