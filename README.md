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

📈 Current Implementation Status
Capability	Status
Terraform Infrastructure	✅ Complete
AWS VPC	✅ Complete
Multi-AZ Networking	✅ Complete
Public/Private Subnets	✅ Complete
Internet Gateway	✅ Complete
NAT Gateway	✅ Complete
Application Load Balancer	✅ Complete
Private Application Tier	✅ Complete
NGINX	✅ Complete
Node Exporter	✅ Complete
Prometheus	✅ Complete
Prometheus Target Monitoring	✅ Complete
Monitoring Security Groups	✅ Complete
IAM Instance Profiles	✅ Complete
AWS Systems Manager	✅ Complete
Monitoring Connectivity Validation	✅ Complete
Incident Troubleshooting Exercise	✅ Complete
Grafana	🔜 Next
SRE Dashboards	🔜 Next
Alerting	🔜 Planned
SLI/SLO Implementation	🔜 Planned
AWS Service Discovery	🔜 Planned
OpenTelemetry	🔜 Planned
Distributed Tracing	🔜 Planned
Centralized Logging	🔜 Planned
CI/CD	🔜 Planned
Terraform Security Scanning	🔜 Planned
🗺️ Roadmap
Phase 1 — Infrastructure Foundation
 Terraform project
 AWS VPC
 Multi-AZ networking
 Public/private subnet architecture
 Internet Gateway
 NAT Gateway
 Security Groups
Phase 2 — Application Platform
 Application Load Balancer
 Target Group
 Private application servers
 NGINX
 Multi-AZ application deployment
 ALB health checks
Phase 3 — Metrics Observability
 Prometheus
 Node Exporter
 Prometheus target configuration
 Monitoring Security Group
 Secure TCP/9100 access
 Metrics connectivity validation
Phase 4 — Visualization
 Grafana
 Infrastructure dashboard
 Application dashboard
 Prometheus dashboard
 CPU/memory/disk/network panels
Phase 5 — SRE Practices
 SLIs
 SLOs
 Error budgets
 Alerting
 Alert routing
 Incident response workflow
 Runbooks
Phase 6 — Advanced Observability
 OpenTelemetry
 Distributed tracing
 Application metrics
 Centralized logging
 Trace-to-metric correlation
 Service dependency mapping
Phase 7 — Automation and Platform Engineering
 AWS service discovery
 GitHub Actions CI/CD
 Terraform automated validation
 Terraform security scanning
 Automated infrastructure testing
 Automated observability validation
