# ---------------------------------------------------------
# IAM Role for EC2 Systems Manager
# ---------------------------------------------------------

resource "aws_iam_role" "prometheus_ssm" {
  name = "sre-${var.environment}-prometheus-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "sre-${var.environment}-prometheus-ssm-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}

# ---------------------------------------------------------
# Attach AWS managed SSM policy
# ---------------------------------------------------------

resource "aws_iam_role_policy_attachment" "prometheus_ssm" {
  role       = aws_iam_role.prometheus_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------
# Instance Profile
# ---------------------------------------------------------

resource "aws_iam_instance_profile" "prometheus" {
  name = "sre-${var.environment}-prometheus-profile"
  role = aws_iam_role.prometheus_ssm.name

  tags = {
    Name        = "sre-${var.environment}-prometheus-profile"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}
# ---------------------------------------------------------
# Grafana IAM Role for AWS Systems Manager
# ---------------------------------------------------------

resource "aws_iam_role" "grafana_ssm" {
  name = "sre-${var.environment}-grafana-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "sre-${var.environment}-grafana-ssm-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}

# ---------------------------------------------------------
# Attach AWS Managed SSM Policy
# ---------------------------------------------------------

resource "aws_iam_role_policy_attachment" "grafana_ssm" {
  role       = aws_iam_role.grafana_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------
# Grafana Instance Profile
# ---------------------------------------------------------

resource "aws_iam_instance_profile" "grafana" {
  name = "sre-${var.environment}-grafana-profile"
  role = aws_iam_role.grafana_ssm.name

  tags = {
    Name        = "sre-${var.environment}-grafana-profile"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "monitoring"
  }
}

# ---------------------------------------------------------
# Least-Privilege IAM Policy for Remediation Executor (Role B)
# ---------------------------------------------------------

resource "aws_iam_policy" "remediation_executor" {
  name        = "sre-${var.environment}-remediation-executor-policy"
  description = "Least-privilege policy for human-approved SRE remediation via AWS Systems Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSendCommandRestricted"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:document/AWS-RunShellScript",
          "arn:aws:ec2:${var.aws_region}:*:instance/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = "SRE Platform"
          }
        }
      },
      {
        Sid    = "SSMCommandInvocationRead"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2TargetDiscoveryRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "sre-${var.environment}-remediation-executor-policy"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "SRE Platform"
    Tier        = "operations"
  }
}
