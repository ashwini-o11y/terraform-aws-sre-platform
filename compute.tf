
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
  ami           = var.ami_id
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
# ---------------------------------------------------------
# Private Application Server A
# ---------------------------------------------------------

resource "aws_instance" "app_a" {
  ami           = var.ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  associate_public_ip_address = false

  iam_instance_profile        = aws_iam_instance_profile.app_ssm.name
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash

              # -------------------------------------------------
              # System update
              # -------------------------------------------------

              dnf update -y

              # -------------------------------------------------
              # Install AWS Systems Manager Agent
              # -------------------------------------------------

              dnf install -y amazon-ssm-agent

              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              # -------------------------------------------------
              # Install Nginx
              # -------------------------------------------------

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

  tags = {
    Name        = "sre-${var.environment}-app-a"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}

resource "aws_iam_role" "app_ssm" {
  name = "sre-${var.environment}-app-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "sre-${var.environment}-app-ssm-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_ssm" {
  name = "sre-${var.environment}-app-ssm-profile"
  role = aws_iam_role.app_ssm.name

  tags = {
    Name        = "sre-${var.environment}-app-ssm-profile"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "application"
  }
}

# ---------------------------------------------------------
# Private Application Server B
# ---------------------------------------------------------

# ---------------------------------------------------------
# Private Application Server B
# ---------------------------------------------------------

resource "aws_instance" "app_b" {
  ami           = var.ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_b.id

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  associate_public_ip_address = false

  iam_instance_profile        = aws_iam_instance_profile.app_ssm.name
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash

              # -------------------------------------------------
              # System update
              # -------------------------------------------------

              dnf update -y

              # -------------------------------------------------
              # Install AWS Systems Manager Agent
              # -------------------------------------------------

              dnf install -y amazon-ssm-agent

              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              # -------------------------------------------------
              # Install Nginx
              # -------------------------------------------------

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
# ---------------------------------------------------------
# Prometheus Monitoring Server
# ---------------------------------------------------------

resource "aws_instance" "prometheus" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  user_data_replace_on_change = true

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.monitoring.id
  ]
  iam_instance_profile = aws_iam_instance_profile.prometheus.name

  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash

              dnf update -y

              # Install Prometheus
              useradd --no-create-home --shell /bin/false prometheus

              mkdir -p /etc/prometheus
              mkdir -p /var/lib/prometheus
              dnf update -y

              # Install and start AWS SSM Agent
              dnf install -y amazon-ssm-agent
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              cd /tmp

              curl -LO https://github.com/prometheus/prometheus/releases/download/v3.5.0/prometheus-3.5.0.linux-amd64.tar.gz

              tar -xzf prometheus-3.5.0.linux-amd64.tar.gz

              cp prometheus-3.5.0.linux-amd64/prometheus /usr/local/bin/
              cp prometheus-3.5.0.linux-amd64/promtool /usr/local/bin/

              cp -r prometheus-3.5.0.linux-amd64/consoles /etc/prometheus/
              cp -r prometheus-3.5.0.linux-amd64/console_libraries /etc/prometheus/

              chown -R prometheus:prometheus /etc/prometheus
              chown -R prometheus:prometheus /var/lib/prometheus

              cat > /etc/prometheus/prometheus.yml <<'PROM'
              global:
                scrape_interval: 15s

              scrape_configs:

                - job_name: "node-exporter"

                  static_configs:
                    - targets:
                        - "10.0.11.132:9100"
                        - "10.0.12.46:9100"
              PROM

              chown prometheus:prometheus /etc/prometheus/prometheus.yml

              cat > /etc/systemd/system/prometheus.service <<'SERVICE'
              [Unit]
              Description=Prometheus Monitoring
              Wants=network-online.target
              After=network-online.target

              [Service]
              User=prometheus
              Group=prometheus
              Type=simple

              ExecStart=/usr/local/bin/prometheus \
                --config.file=/etc/prometheus/prometheus.yml \
                --storage.tsdb.path=/var/lib/prometheus \
                --web.listen-address=0.0.0.0:9090

              Restart=always

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable prometheus
              systemctl start prometheus
              EOF

  tags = {
    Name        = "sre-${var.environment}-prometheus"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}

# ---------------------------------------------------------
# Grafana Monitoring Server
# ---------------------------------------------------------

resource "aws_instance" "grafana" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  user_data_replace_on_change = true

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.grafana.id
  ]

  iam_instance_profile = aws_iam_instance_profile.grafana.name

  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash

              # -------------------------------------------------
              # System update
              # -------------------------------------------------

              dnf update -y

              # -------------------------------------------------
              # Install AWS Systems Manager Agent
              # -------------------------------------------------

              dnf install -y amazon-ssm-agent

              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              # -------------------------------------------------
              # Configure Grafana Repository
              # -------------------------------------------------

              cat > /etc/yum.repos.d/grafana.repo <<'REPO'
              [grafana]
              name=grafana
              baseurl=https://rpm.grafana.com
              repo_gpgcheck=1
              enabled=1
              gpgcheck=1
              gpgkey=https://rpm.grafana.com/gpg.key
              sslverify=1
              sslcacert=/etc/pki/tls/certs/ca-bundle.crt
              REPO

              # -------------------------------------------------
              # Import Grafana GPG key
              # -------------------------------------------------

              curl -fsSL https://rpm.grafana.com/gpg.key \
                -o /tmp/grafana.gpg.key

              rpm --import /tmp/grafana.gpg.key

              # -------------------------------------------------
              # Install Grafana OSS
              # -------------------------------------------------

              dnf install -y grafana

              # -------------------------------------------------
              # Configure Prometheus Datasource
              # -------------------------------------------------

              mkdir -p /etc/grafana/provisioning/datasources

              cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'DATASOURCE'
              apiVersion: 1

              datasources:
                - name: Prometheus
                  uid: prometheus
                  type: prometheus
                  access: proxy
                  url: http://${aws_instance.prometheus.private_ip}:9090
                  isDefault: true
                  editable: true
              DATASOURCE

              # -------------------------------------------------
              # Configure Dashboard Provisioning
              # -------------------------------------------------

              mkdir -p /etc/grafana/provisioning/dashboards
              mkdir -p /var/lib/grafana/dashboards

              cat > /etc/grafana/provisioning/dashboards/dashboards.yml <<'DASHBOARD_PROVIDER'
              apiVersion: 1

              providers:
                - name: 'SRE Platform'
                  orgId: 1
                  folder: 'SRE Platform'
                  type: file
                  disableDeletion: true
                  updateIntervalSeconds: 30
                  allowUiUpdates: false
                  options:
                    path: /var/lib/grafana/dashboards
              DASHBOARD_PROVIDER

              # -------------------------------------------------
              # Deploy SRE Platform Dashboard
              # -------------------------------------------------

              echo '${base64encode(file("${path.module}/grafana/dashboards/sre-platform-overview.json"))}' \
                | base64 -d > /var/lib/grafana/dashboards/sre-platform-overview.json

              chown -R grafana:grafana /var/lib/grafana/dashboards
              chmod 644 /var/lib/grafana/dashboards/sre-platform-overview.json

              # -------------------------------------------------
              # Configure Grafana
              # -------------------------------------------------

              sed -i 's/^;http_addr =.*$/http_addr = 0.0.0.0/' /etc/grafana/grafana.ini
              sed -i 's/^;http_port =.*$/http_port = 3000/' /etc/grafana/grafana.ini

              # -------------------------------------------------
              # Start Grafana
              # -------------------------------------------------

              systemctl daemon-reload
              systemctl enable grafana-server
              systemctl start grafana-server

              # -------------------------------------------------
              # Ensure Grafana reloads provisioning
              # -------------------------------------------------

              systemctl restart grafana-server
              EOF

  tags = {
    Name        = "sre-${var.environment}-grafana"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}