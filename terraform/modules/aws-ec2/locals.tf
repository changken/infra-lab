#--------------------------------------------------------------
# Local Values
#--------------------------------------------------------------

locals {
  # Common tags applied to all resources
  common_tags = {
    Environment = var.environment
    Project     = var.project
    CreatedBy   = "terraform"
  }
}
