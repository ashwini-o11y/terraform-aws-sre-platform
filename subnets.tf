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

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.sre_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "sre-${var.environment}-public-subnet-b"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.sre_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "sre-${var.environment}-private-subnet-a"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.sre_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "sre-${var.environment}-private-subnet-b"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "private"
  }
}