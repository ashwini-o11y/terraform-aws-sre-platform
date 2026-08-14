resource "aws_internet_gateway" "sre_igw" {
  vpc_id = aws_vpc.sre_vpc.id

  tags = {
    Name        = "sre-${var.environment}-igw"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sre_vpc.id

  tags = {
    Name        = "sre-${var.environment}-public-rt"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}

# Internet access for public subnets
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sre_igw.id
}

# Associate first public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sre_vpc.id

  tags = {
    Name        = "sre-${var.environment}-private-rt"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "private"
  }
}

# Associate private subnet A
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}
# Associate private subnet B
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "sre-${var.environment}-nat-eip"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "network"
  }
}

# NAT Gateway in the public subnet
resource "aws_nat_gateway" "sre_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [
    aws_internet_gateway.sre_igw
  ]

  tags = {
    Name        = "sre-${var.environment}-nat"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "network"
  }
}

# Allow private subnets to reach the internet through NAT
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.sre_nat.id
}