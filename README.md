# Terraform SRE Platform

Production-style AWS infrastructure and SRE platform built using
Terraform, with a focus on Infrastructure as Code, cloud networking,
security, observability, automation, and reliability engineering.

## 🎯 Project Objectives

This project demonstrates how to design, provision, secure, and
operate a cloud-based application platform using Infrastructure as
Code and SRE principles.

Key objectives:

- Build AWS infrastructure using Terraform
- Apply Infrastructure as Code best practices
- Implement secure cloud networking
- Automate infrastructure provisioning
- Introduce observability using OpenTelemetry
- Implement metrics, logs, and traces
- Define SLI/SLO concepts
- Build CI/CD pipelines using GitHub Actions
- Implement Terraform validation and security scanning
- Demonstrate incident detection and troubleshooting

---

## 🏗️ Current Architecture

The current environment contains:

```text
                         Internet
                            │
                            ▼
                   Internet Gateway
                            │
                            ▼
                     Public Route
                        Table
                            │
                     0.0.0.0/0
                            │
                            ▼
                    Public Subnet
                     10.0.1.0/24
                            │
                   ┌────────┴────────┐
                   │                 │
             Security Group         EC2
              TCP/80              t3.micro
                                     │
                                   NGINX
                                     │
                                     ▼
                               Web Application