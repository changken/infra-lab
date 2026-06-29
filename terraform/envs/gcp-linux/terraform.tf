terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.38"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # 認證方式（擇一）：
  # 1. 設定環境變數：export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
  # 2. 執行：gcloud auth application-default login
  # 3. 填入下方 credentials（JSON key 檔路徑或內容）
  # credentials = file("~/.config/gcloud/key.json")
}
