# Terraform AWS SRE Platform

A production-style AWS SRE platform built with **Terraform**, designed to demonstrate Infrastructure as Code, cloud networking, secure application architecture, observability, monitoring, operational troubleshooting, and reliability engineering practices.

The project is being built incrementally, with each phase representing a real SRE capability rather than simply provisioning infrastructure.

---

## 🎯 Project Objectives

This project demonstrates how to design, provision, monitor, troubleshoot, and operate a highly available AWS application platform using Infrastructure as Code and SRE principles.

Key objectives:

- Build AWS infrastructure using Terraform
- Implement a multi-AZ AWS architecture
- Separate public and private infrastructure tiers
- Implement secure application access using Security Groups
- Deploy applications behind an Application Load Balancer
- Implement NAT-based outbound connectivity for private workloads
- Implement infrastructure and application monitoring
- Deploy Prometheus for metrics collection
- Deploy Prometheus Node Exporter on application servers
- Implement secure monitoring access using Security Group references
- Implement AWS Systems Manager for operational access
- Implement IAM roles and instance profiles
- Demonstrate incident detection and troubleshooting
- Build SRE-focused dashboards and alerting
- Define SLI/SLO concepts
- Introduce OpenTelemetry and distributed observability
- Automate infrastructure validation and deployment
- Evolve the platform toward production-style SRE practices

---

# 🏗️ Architecture

The current platform follows a multi-tier, multi-AZ architecture.

```text
                              Internet
                                  │
                                  ▼
                         Internet Gateway
                                  │
                                  ▼
                     ┌─────────────────────┐
                     │    Public Subnets   │
                     │                     │
                     │  AZ-a       AZ-b    │
                     └────┬────────┬────────┘
                          │        │
                          ▼        ▼
                    ┌───────────────────┐
                    │ Application Load  │
                    │     Balancer       │
                    │       :80          │
                    └─────────┬─────────┘
                              │
                    HTTP / TCP 80
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
       ┌───────────────┐               ┌───────────────┐
       │ Application A │               │ Application B │
       │ Private AZ-a  │               │ Private AZ-b  │
       │ 10.0.11.x     │               │ 10.0.12.x     │
       │               │               │               │
       │    NGINX      │               │    NGINX      │
       │ Node Exporter │               │ Node Exporter │
       │    :9100      │               │    :9100      │
       └───────┬───────┘               └───────┬───────┘
               │                               │
               │         TCP 9100              │
               │                               │
               └──────────────┬────────────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │     Prometheus    │
                    │                   │
                    │   Private AZ-a    │
                    │    10.0.11.x      │
                    │       :9090       │
                    └───────────────────┘
                              │
                              ▼
                         Metrics Store

Infrastructure as Code

All AWS infrastructure is managed using Terraform.

Core Terraform components include:

providers.tf
versions.tf
variables.tf
data.tf
network.tf
subnets.tf
security.tf
compute.tf
iam.tf
outputs.tf

Terraform is used to manage:

VPC
Subnets
Route tables
Internet Gateway
NAT Gateway
Security Groups
Application Load Balancer
Target Groups
EC2 instances
IAM roles
IAM instance profiles
Security Group rules

