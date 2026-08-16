data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ---------------------------------------------------------
# Application Load Balancer Target Group
# ---------------------------------------------------------

resource "aws_lb_target_group" "web" {
  name     = "sre-${var.environment}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.sre_vpc.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name        = "sre-${var.environment}-web-tg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}

# ---------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------

resource "aws_lb" "web" {
  name               = "sre-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name        = "sre-${var.environment}-alb"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "alb"
  }
}

# ---------------------------------------------------------
# ALB Listener
# ---------------------------------------------------------

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------------------------------------------------------
# Existing Public EC2
# Keep this temporarily during migration
# ---------------------------------------------------------

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash

              dnf update -y
              dnf install -y nginx

              systemctl enable nginx
              systemctl start nginx

              cat > /usr/share/nginx/html/index.html <<'HTML'
              <html>
                <head>
                  <title>SRE Platform</title>
                </head>
                <body>
                  <h1>Terraform SRE Platform</h1>
                  <p>Infrastructure managed by Terraform.</p>
                  <p>Environment: ${var.environment}</p>
                  <p>Server: Public Web Server</p>
                </body>
              </html>
              HTML
              EOF

  lifecycle {
    ignore_changes = [
      user_data
    ]
  }

  tags = {
    Name        = "sre-${var.environment}-web"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "legacy-public"
  }
}

# ---------------------------------------------------------
# Private Application Server A
# ---------------------------------------------------------

resource "aws_instance" "app_a" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash

              dnf update -y
              dnf install -y nginx

              systemctl enable nginx
              systemctl start nginx

              # -------------------------------------------------
              # Install Prometheus Node Exporter
              # -------------------------------------------------

              useradd --no-create-home --shell /bin/false node_exporter

              cd /tmp

              curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz

              tar -xzf node_exporter-1.9.1.linux-amd64.tar.gz

              cp node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/node_exporter

              chown node_exporter:node_exporter /usr/local/bin/node_exporter

              cat > /etc/systemd/system/node_exporter.service <<'SERVICE'
              [Unit]
              Description=Prometheus Node Exporter
              Wants=network-online.target
              After=network-online.target

              [Service]
              User=node_exporter
              Group=node_exporter
              Type=simple
              ExecStart=/usr/local/bin/node_exporter

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable node_exporter
              systemctl start node_exporter

              # -------------------------------------------------
              # Application page
              # -------------------------------------------------

              cat > /usr/share/nginx/html/index.html <<'HTML'
              <html>
                <head>
                  <title>SRE Platform</title>
                </head>
                <body>
                  <h1>Terraform SRE Platform</h1>
                  <p>Infrastructure managed by Terraform.</p>
                  <p>Environment: ${var.environment}</p>
                  <p>Server: Private Application A</p>
                  <p>Availability Zone: eu-west-1a</p>
                </body>
              </html>
              HTML
              EOF

  lifecycle {
    ignore_changes = [
      user_data
    ]
  }

  tags = {
    Name        = "sre-${var.environment}-app-a"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}

# ---------------------------------------------------------
# Private Application Server B
# ---------------------------------------------------------

resource "aws_instance" "app_b" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_b.id

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash

              dnf update -y
              dnf install -y nginx

              systemctl enable nginx
              systemctl start nginx

              # -------------------------------------------------
              # Install Prometheus Node Exporter
              # -------------------------------------------------

              useradd --no-create-home --shell /bin/false node_exporter

              cd /tmp

              curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz

              tar -xzf node_exporter-1.9.1.linux-amd64.tar.gz

              cp node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin/node_exporter

              chown node_exporter:node_exporter /usr/local/bin/node_exporter

              cat > /etc/systemd/system/node_exporter.service <<'SERVICE'
              [Unit]
              Description=Prometheus Node Exporter
              Wants=network-online.target
              After=network-online.target

              [Service]
              User=node_exporter
              Group=node_exporter
              Type=simple
              ExecStart=/usr/local/bin/node_exporter

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable node_exporter
              systemctl start node_exporter

              # -------------------------------------------------
              # Application page
              # -------------------------------------------------

              cat > /usr/share/nginx/html/index.html <<'HTML'
              <html>
                <head>
                  <title>SRE Platform</title>
                </head>
                <body>
                  <h1>Terraform SRE Platform</h1>
                  <p>Infrastructure managed by Terraform.</p>
                  <p>Environment: ${var.environment}</p>
                  <p>Server: Private Application B</p>
                  <p>Availability Zone: eu-west-1b</p>
                </body>
              </html>
              HTML
              EOF

  lifecycle {
    ignore_changes = [
      user_data
    ]
  }

  tags = {
    Name        = "sre-${var.environment}-app-b"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}

# ---------------------------------------------------------
# Register Private Application A with Target Group
# ---------------------------------------------------------

resource "aws_lb_target_group_attachment" "app_a" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.app_a.id
  port             = 80
}

# ---------------------------------------------------------
# Register Private Application B with Target Group
# ---------------------------------------------------------

resource "aws_lb_target_group_attachment" "app_b" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.app_b.id
  port             = 80
}