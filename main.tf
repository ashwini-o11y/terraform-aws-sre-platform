resource "aws_vpc" "sre_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "sre-${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}