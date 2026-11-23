locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-09-kafka-event-backbone"
  }
}
