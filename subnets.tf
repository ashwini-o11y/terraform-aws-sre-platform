resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.sre_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name        = "sre-${var.environment}-public-subnet"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}