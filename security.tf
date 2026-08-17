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
resource "aws_security_group" "monitoring" {
  name        = "sre-${var.environment}-monitoring-sg"
  description = "Security group for SRE monitoring infrastructure"
  vpc_id      = aws_vpc.sre_vpc.id

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sre-${var.environment}-monitoring-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_node_exporter" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.monitoring.id

  from_port   = 9100
  to_port     = 9100
  ip_protocol = "tcp"

  description = "Prometheus monitoring server to Node Exporter"
}

# ---------------------------------------------------------
# Grafana Security Group
# ---------------------------------------------------------

resource "aws_security_group" "grafana" {
  name        = "sre-${var.environment}-grafana-sg"
  description = "Security group for SRE Grafana monitoring server"
  vpc_id      = aws_vpc.sre_vpc.id

  ingress {
    description = "Grafana UI from VPC"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sre-${var.environment}-grafana-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}

# ---------------------------------------------------------
# Allow Grafana to query Prometheus
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "prometheus_from_grafana" {
  security_group_id            = aws_security_group.monitoring.id
  referenced_security_group_id = aws_security_group.grafana.id

  from_port   = 9090
  to_port     = 9090
  ip_protocol = "tcp"

  description = "Grafana to Prometheus"
}