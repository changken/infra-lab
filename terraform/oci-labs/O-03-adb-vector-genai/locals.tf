locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-03-adb-vector-genai"
  }

  # 要上傳到 bucket 的檔案：物件名稱 => 本機路徑
  #   data/*.csv     範例資料（已提供）
  #   models/*.onnx  embedding 模型（你自己下載，見 README「準備 ONNX 模型」）
  upload_files = merge(
    { for f in fileset("${path.module}/data", "*.csv") : "data/${f}" => "${path.module}/data/${f}" },
    { for f in fileset("${path.module}/models", "*.onnx") : "models/${f}" => "${path.module}/models/${f}" },
  )
}
