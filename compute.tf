
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
# Prometheus + Alertmanager Monitoring Server
# ---------------------------------------------------------

resource "aws_instance" "prometheus" {
  lifecycle {
    create_before_destroy = true
  }
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  user_data_replace_on_change = true

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.monitoring.id
  ]

  iam_instance_profile = aws_iam_instance_profile.prometheus.name

  associate_public_ip_address = false
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }
  user_data = <<-EOF
              #!/bin/bash

              set -e

              dnf update -y


              dnf install -y amazon-ssm-agent

              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent


              id prometheus >/dev/null 2>&1 || \
                useradd --no-create-home --shell /bin/false prometheus

              mkdir -p /etc/prometheus
              mkdir -p /var/lib/prometheus


              cd /tmp

              curl -fLO https://github.com/prometheus/prometheus/releases/download/v3.5.0/prometheus-3.5.0.linux-amd64.tar.gz

              tar -xzf prometheus-3.5.0.linux-amd64.tar.gz

              cp prometheus-3.5.0.linux-amd64/prometheus /usr/local/bin/prometheus
              cp prometheus-3.5.0.linux-amd64/promtool /usr/local/bin/promtool

              rm -rf /tmp/prometheus-3.5.0.linux-amd64
              rm -f /tmp/prometheus-3.5.0.linux-amd64.tar.gz


              cat > /etc/prometheus/prometheus.yml <<'PROM'
              global:
                scrape_interval: 15s

              alerting:
                alertmanagers:
                  - static_configs:
                      - targets:
                          - "localhost:9093"

              rule_files:
                - "/etc/prometheus/rules/*.yml"

              scrape_configs:

                - job_name: "node-exporter"

                  static_configs:
                    - targets:
                        - "${aws_instance.app_a.private_ip}:9100"
                        - "${aws_instance.app_b.private_ip}:9100"
              PROM


              mkdir -p /etc/prometheus/rules

              cat > /etc/prometheus/rules/sre-platform-alerts.yml <<'RULES'
              groups:
                - name: sre-platform-rules
                  rules:


                    - record: sre:node_availability:ratio
                      expr: |
                        up{job="node-exporter"}

                    - record: sre:cpu_health:ratio
                      expr: |
                        (
                          100 -
                          (
                            rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100
                          )
                        ) <= bool 80

                    - record: sre:memory_health:ratio
                      expr: |
                        (
                          100 *
                          (
                            1 -
                            (
                              node_memory_MemAvailable_bytes /
                              node_memory_MemTotal_bytes
                            )
                          )
                        ) <= bool 85

                    - record: sre:filesystem_health:ratio
                      expr: |
                        (
                          100 *
                          (
                            1 -
                            (
                              node_filesystem_avail_bytes{
                                mountpoint="/",
                                fstype!="tmpfs"
                              }
                              /
                              node_filesystem_size_bytes{
                                mountpoint="/",
                                fstype!="tmpfs"
                              }
                            )
                          )
                        ) <= bool 85


                    - record: sre:node_availability:samples_30d
                      expr: |
                        count_over_time(
                          sre:node_availability:ratio[30d]
                        )

                    - record: sre:cpu_health:samples_30d
                      expr: |
                        count_over_time(
                          sre:cpu_health:ratio[30d]
                        )

                    - record: sre:memory_health:samples_30d
                      expr: |
                        count_over_time(
                          sre:memory_health:ratio[30d]
                        )

                    - record: sre:filesystem_health:samples_30d
                      expr: |
                        count_over_time(
                          sre:filesystem_health:ratio[30d]
                        )


                    - record: sre:node_availability:slo_30d
                      expr: |
                        (
                          avg_over_time(
                            sre:node_availability:ratio[30d]
                          )
                          and
                          (
                            sre:node_availability:samples_30d >= 164160
                          )
                        )

                    - record: sre:cpu_health:slo_30d
                      expr: |
                        (
                          avg_over_time(
                            sre:cpu_health:ratio[30d]
                          )
                          and
                          (
                            sre:cpu_health:samples_30d >= 164160
                          )
                        )

                    - record: sre:memory_health:slo_30d
                      expr: |
                        (
                          avg_over_time(
                            sre:memory_health:ratio[30d]
                          )
                          and
                          (
                            sre:memory_health:samples_30d >= 164160
                          )
                        )

                    - record: sre:filesystem_health:slo_30d
                      expr: |
                        (
                          avg_over_time(
                            sre:filesystem_health:ratio[30d]
                          )
                          and
                          (
                            sre:filesystem_health:samples_30d >= 164160
                          )
                        )


                    - record: sre:node_availability:observed_1h
                      expr: |
                        avg_over_time(
                          sre:node_availability:ratio[1h]
                        )

                    - record: sre:cpu_health:observed_1h
                      expr: |
                        avg_over_time(
                          sre:cpu_health:ratio[1h]
                        )

                    - record: sre:memory_health:observed_1h
                      expr: |
                        avg_over_time(
                          sre:memory_health:ratio[1h]
                        )

                    - record: sre:filesystem_health:observed_1h
                      expr: |
                        avg_over_time(
                          sre:filesystem_health:ratio[1h]
                        )


                    - record: sre:node_availability:error_budget_remaining_30d
                      expr: |
                        clamp_min(
                          1 -
                          (
                            (
                              1 -
                              sre:node_availability:slo_30d
                            )
                            /
                            0.001
                          ),
                          0
                        )

                    - record: sre:cpu_health:error_budget_remaining_30d
                      expr: |
                        clamp_min(
                          1 -
                          (
                            (
                              1 -
                              sre:cpu_health:slo_30d
                            )
                            /
                            0.01
                          ),
                          0
                        )

                    - record: sre:memory_health:error_budget_remaining_30d
                      expr: |
                        clamp_min(
                          1 -
                          (
                            (
                              1 -
                              sre:memory_health:slo_30d
                            )
                            /
                            0.01
                          ),
                          0
                        )

                    - record: sre:filesystem_health:error_budget_remaining_30d
                      expr: |
                        clamp_min(
                          1 -
                          (
                            (
                              1 -
                              sre:filesystem_health:slo_30d
                            )
                            /
                            0.01
                          ),
                          0
                        )


                    - record: sre:node_availability:burn_rate_5m
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:node_availability:ratio[5m]
                          )
                        ) / 0.001

                    - record: sre:cpu_health:burn_rate_5m
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:cpu_health:ratio[5m]
                          )
                        ) / 0.01

                    - record: sre:memory_health:burn_rate_5m
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:memory_health:ratio[5m]
                          )
                        ) / 0.01

                    - record: sre:filesystem_health:burn_rate_5m
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:filesystem_health:ratio[5m]
                          )
                        ) / 0.01


                    - record: sre:node_availability:burn_rate_1h
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:node_availability:ratio[1h]
                          )
                        ) / 0.001

                    - record: sre:cpu_health:burn_rate_1h
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:cpu_health:ratio[1h]
                          )
                        ) / 0.01

                    - record: sre:memory_health:burn_rate_1h
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:memory_health:ratio[1h]
                          )
                        ) / 0.01

                    - record: sre:filesystem_health:burn_rate_1h
                      expr: |
                        (
                          1 -
                          avg_over_time(
                            sre:filesystem_health:ratio[1h]
                          )
                        ) / 0.01


                    - alert: NodeAvailabilityBurnRateHigh
                      expr: |
                        (
                          sre:node_availability:burn_rate_5m > 14.4
                        )
                        and
                        (
                          sre:node_availability:burn_rate_1h > 14.4
                        )
                      for: 2m
                      labels:
                        severity: critical
                        team: sre
                      annotations:
                        summary: "Node availability SLO burn rate is high"
                        description: "Node {{ $labels.instance }} is consuming the 99.9% availability error budget at more than 14.4x the sustainable rate."

                    - alert: CPUHealthBurnRateHigh
                      expr: |
                        (
                          sre:cpu_health:burn_rate_5m > 14.4
                        )
                        and
                        (
                          sre:cpu_health:burn_rate_1h > 14.4
                        )
                      for: 2m
                      labels:
                        severity: critical
                        team: sre
                      annotations:
                        summary: "CPU health SLO burn rate is high"
                        description: "CPU health on {{ $labels.instance }} is consuming the 99% error budget at more than 14.4x the sustainable rate."

                    - alert: MemoryHealthBurnRateHigh
                      expr: |
                        (
                          sre:memory_health:burn_rate_5m > 14.4
                        )
                        and
                        (
                          sre:memory_health:burn_rate_1h > 14.4
                        )
                      for: 2m
                      labels:
                        severity: critical
                        team: sre
                      annotations:
                        summary: "Memory health SLO burn rate is high"
                        description: "Memory health on {{ $labels.instance }} is consuming the 99% error budget at more than 14.4x the sustainable rate."

                    - alert: FilesystemHealthBurnRateHigh
                      expr: |
                        (
                          sre:filesystem_health:burn_rate_5m > 14.4
                        )
                        and
                        (
                          sre:filesystem_health:burn_rate_1h > 14.4
                        )
                      for: 2m
                      labels:
                        severity: critical
                        team: sre
                      annotations:
                        summary: "Filesystem health SLO burn rate is high"
                        description: "Filesystem health on {{ $labels.instance }} is consuming the 99% error budget at more than 14.4x the sustainable rate."


                    - alert: InstanceDown
                      expr: |
                        up{job="node-exporter"} == 0
                      for: 2m
                      labels:
                        severity: critical
                        team: sre
                      annotations:
                        summary: "Node exporter is down"
                        description: "Node exporter on {{ $labels.instance }} has been unavailable for more than 2 minutes."

                    - alert: HighCPUUsage
                      expr: |
                        (
                          100 -
                          (
                            avg by(instance) (
                              rate(node_cpu_seconds_total{mode="idle"}[5m])
                            ) * 100
                          )
                        ) > 80
                      for: 5m
                      labels:
                        severity: warning
                        team: sre
                      annotations:
                        summary: "High CPU usage detected"
                        description: "CPU utilization on {{ $labels.instance }} has been above 80% for more than 5 minutes."

                    - alert: HighMemoryUsage
                      expr: |
                        (
                          100 *
                          (
                            1 -
                            (
                              node_memory_MemAvailable_bytes /
                              node_memory_MemTotal_bytes
                            )
                          )
                        ) > 85
                      for: 5m
                      labels:
                        severity: warning
                        team: sre
                      annotations:
                        summary: "High memory usage detected"
                        description: "Memory utilization on {{ $labels.instance }} has been above 85% for more than 5 minutes."

                    - alert: FilesystemAlmostFull
                      expr: |
                        (
                          100 *
                          (
                            1 -
                            (
                              node_filesystem_avail_bytes{
                                mountpoint="/",
                                fstype!="tmpfs"
                              }
                              /
                              node_filesystem_size_bytes{
                                mountpoint="/",
                                fstype!="tmpfs"
                              }
                            )
                          )
                        ) > 85
                      for: 5m
                      labels:
                        severity: warning
                        team: sre
                      annotations:
                        summary: "Filesystem usage is high"
                        description: "Root filesystem on {{ $labels.instance }} has been above 85% utilization for more than 5 minutes."
              RULES

              chown -R prometheus:prometheus /etc/prometheus
              chown -R prometheus:prometheus /var/lib/prometheus


              /usr/local/bin/promtool check config \
                /etc/prometheus/prometheus.yml

              /usr/local/bin/promtool check rules \
                /etc/prometheus/rules/sre-platform-alerts.yml


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
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE


              id alertmanager >/dev/null 2>&1 || \
                useradd --no-create-home --shell /bin/false alertmanager

              mkdir -p /etc/alertmanager
              mkdir -p /var/lib/alertmanager

              cd /tmp

              curl -fLO https://github.com/prometheus/alertmanager/releases/download/v0.33.1/alertmanager-0.33.1.linux-amd64.tar.gz

              tar -xzf alertmanager-0.33.1.linux-amd64.tar.gz

              cp alertmanager-0.33.1.linux-amd64/alertmanager /usr/local/bin/alertmanager
              cp alertmanager-0.33.1.linux-amd64/amtool /usr/local/bin/amtool

              rm -rf /tmp/alertmanager-0.33.1.linux-amd64
              rm -f /tmp/alertmanager-0.33.1.linux-amd64.tar.gz


              cat > /etc/alertmanager/alertmanager.yml <<'ALERTMANAGER'
              global:
                resolve_timeout: 5m

              route:
                group_by:
                  - alertname
                  - instance
                group_wait: 30s
                group_interval: 5m
                repeat_interval: 4h
                receiver: "warning"

                routes:
                  - matchers:
                      - severity="critical"
                    receiver: "critical"

                  - matchers:
                      - severity="warning"
                    receiver: "warning"

              receivers:
                - name: "critical"

                - name: "warning"
              ALERTMANAGER

              chown -R alertmanager:alertmanager /etc/alertmanager
              chown -R alertmanager:alertmanager /var/lib/alertmanager


              /usr/local/bin/amtool check-config \
                /etc/alertmanager/alertmanager.yml


              cat > /etc/systemd/system/alertmanager.service <<'SERVICE'
              [Unit]
              Description=Alertmanager
              Wants=network-online.target
              After=network-online.target

              [Service]
              User=alertmanager
              Group=alertmanager
              Type=simple

              ExecStart=/usr/local/bin/alertmanager \
                --config.file=/etc/alertmanager/alertmanager.yml \
                --storage.path=/var/lib/alertmanager \
                --web.listen-address=127.0.0.1:9093

              Restart=always
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE


              systemctl daemon-reload

              systemctl enable prometheus
              systemctl enable alertmanager

              systemctl restart alertmanager
              systemctl restart prometheus


              systemctl is-active --quiet alertmanager
              systemctl is-active --quiet prometheus
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
  lifecycle {
    create_before_destroy = true
  }
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

              echo '${base64gzip(file("${path.module}/grafana/dashboards/sre-platform-overview.json"))}' \
                | base64 -d \
                | gunzip > /var/lib/grafana/dashboards/sre-platform-overview.json

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
