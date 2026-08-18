variable "aws_region" {
  description = "AWS region for the SRE platform"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "ami_id" {
  description = "Pinned Amazon Linux 2023 AMI ID"
  type        = string
  default     = "ami-06b92572563223046"
}