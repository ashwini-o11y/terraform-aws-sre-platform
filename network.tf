resource "aws_internet_gateway" "sre_igw" {
  vpc_id = aws_vpc.sre_vpc.id

  tags = {
    Name        = "sre-${var.environment}-igw"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sre_vpc.id

  tags = {
    Name        = "sre-${var.environment}-public-rt"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sre_igw.id
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
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
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}