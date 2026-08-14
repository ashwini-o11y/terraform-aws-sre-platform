resource "aws_security_group" "web" {
  name        = "sre-${var.environment}-web-sg"
  description = "Security group for SRE platform web server"
  vpc_id      = aws_vpc.sre_vpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sre-${var.environment}-web-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
  }
}
resource "aws_security_group" "alb" {
  name        = "sre-${var.environment}-alb-sg"
  description = "Security group for SRE platform ALB"
  vpc_id      = aws_vpc.sre_vpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sre-${var.environment}-alb-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "alb"
  }
}

resource "aws_security_group" "app" {
  name        = "sre-${var.environment}-app-sg"
  description = "Security group for SRE platform application servers"
  vpc_id      = aws_vpc.sre_vpc.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sre-${var.environment}-app-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}