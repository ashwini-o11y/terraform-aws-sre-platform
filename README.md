# Terraform AWS SRE Platform

A production-grade AWS Site Reliability Engineering (SRE) platform provisioned with **Terraform**, designed to demonstrate modern Infrastructure as Code, resilient cloud networking, multi-AZ workload architecture, metrics-driven observability, multi-window SLO burn-rate alerting, automated root cause analysis (RCA), and safe, human-approved remediation workflows via AWS Systems Manager.

---

## 🎯 Platform Workflow & Lifecycle

The platform operational lifecycle follows an explicit, fail-closed reliability pipeline:

$$\text{DETECT} \longrightarrow \text{CORRELATE} \longrightarrow \text{ANALYZE (RCA)} \longrightarrow \text{RECOMMEND} \longrightarrow \text{HUMAN APPROVAL} \longrightarrow \text{REMEDIATE} \longrightarrow \text{VERIFY} \longrightarrow \text{CLOSE}$$

> **Core Safety Principle:**
> *RCA and remediation are deliberately separated. Incident Intelligence can analyze signals and recommend an action, but remediation strictly requires explicit human approval and strict allowlist validation before execution.*

---

## 🏗️ Architecture

The platform spans a resilient multi-tier, multi-AZ virtual private cloud (VPC) in AWS `eu-west-1`.

```text
                                  Internet
                                      │
                                      ▼
                             Internet Gateway
                                      │
                                      ▼
                         ┌─────────────────────────┐
                         │      Public Subnets     │
                         │                         │
                         │    AZ-a         AZ-b    │
                         └──────┬────────────┬─────┘
                                │            │
                                ▼            ▼
                        ┌───────────────────────────┐
                        │ Application Load Balancer │
                        │           :80             │
                        └─────────────┬─────────────┘
                                      │
                                HTTP / TCP 80
                                      │
                  ┌───────────────────┴───────────────────┐
                  │                                       │
                  ▼                                       ▼
       ┌─────────────────────┐                 ┌─────────────────────┐
       │    Application A    │                 │    Application B    │
       │    Private AZ-a     │                 │    Private AZ-b     │
       │     10.0.11.132     │                 │     10.0.12.233     │
       │                     │                 │                     │
       │        NGINX        │                 │        NGINX        │
       │    Node Exporter    │                 │    Node Exporter    │
       │        :9100        │                 │        :9100        │
       └──────────┬──────────┘                 └──────────┬──────────┘
                  │                                       │
                  │              TCP 9100                 │
                  │                                       │
                  └───────────────────┬───────────────────┘
                                      │
                                      ▼
                        ┌───────────────────────────┐
                        │     Prometheus Server     │
                        │        Private AZ-a       │
                        │         10.0.11.28        │
                        │           :9090           │
                        └─────────────┬─────────────┘
                                      │
                       Alerts / Metrics Evaluation
                                      ▼
                        ┌───────────────────────────┐
                        │    Grafana Dashboard &    │
                        │    Alertmanager Alerts    │
                        │        Private AZ-a       │
                        │         10.0.11.190       │
                        └───────────────────────────┘
```

---

## 📊 Observability & Reliability Stack

### 1. Prometheus & Target Monitoring
- Dedicated Prometheus server scraping Node Exporters on all private workloads (`:9100`) and itself (`:9090`).
- Scrape interval: 15s with 10s scrape timeout.

### 2. SRE Metrics, SLIs, and SLOs
The platform defines precision Service Level Objectives based on the Google SRE Multi-Window Multi-Burn-Rate alerting framework:

- **Application Availability SLO:** `99.9%` success rate over 30 days.
- **Node Availability SLO:** `99.9%` exporter uptime over 30 days.
- **CPU Saturation SLO:** `99.0%` of intervals with CPU utilization $< 80\%$.
- **Memory Saturation SLO:** `99.0%` of intervals with memory utilization $< 85\%$.
- **Filesystem Saturation SLO:** `99.0%` of intervals with disk utilization $< 85\%$.

### 3. Multi-Window Burn-Rate Alerting
Prometheus rule evaluations compute consumption velocity against error budgets:
- **Critical (Page):** $14.4\times$ burn rate (consuming 2% error budget in 1 hour) with short-window (5m) and long-window (1h) correlation.
- **Warning (Ticket):** $6\times$ burn rate (consuming 5% error budget in 6 hours).

---

## 🧠 Incident Intelligence & RCA (Phase 8A)

The `incident_intelligence` engine is a standalone, read-only Python subsystem that deterministically correlates multi-source signals into structured incidents without side effects:

- **Signal Ingestion:** Prometheus targets & alert status, Alertmanager active alerts, AWS Target Group health descriptions, and ALB HTTP endpoint probes.
- **Deterministic RCA Rules:**
  - `monitoring_agent_failure`: Prometheus target DOWN with connection refused, but ALB target HEALTHY and ALB HTTP 200.
  - `application_availability_failure`: ALB target UNHEALTHY with ALB HTTP 5xx.
  - `resource_saturation`: CPU, memory, or disk burn-rate alerts active without immediate target unavailability.
  - `unclassified`: Complex or conflicting signals held at `AWAITING_TRIAGE`.
- **Domain Impact Classification:** Separates monitoring degradation from actual customer/application impact.

---

## 🛡️ Human-Approved Remediation & Safety Model (Phase 8B)

Remediation execution is decoupled from diagnosis and governed by a strict safety framework:

```text
[Incident Intelligence]
        │
        ▼ (recommends: restart_node_exporter)
[Human Operator Approval] ──▶ Action: restart_node_exporter, Approver: Ashwini, Approved: True
        │
        ▼
[Safety & Allowlist Gates] ──▶ Category Check, Target Identity Check, Allowlist Check
        │
        ▼ (pass)
[SSM Live Execution Adapter] ──▶ AWS Systems Manager SendCommand (AWS-RunShellScript)
        │
        ▼
[8-Point Telemetry Verification] ──▶ Exporter UP, Target UP, Alerts Cleared, ALB Healthy, HTTP 200
        │
        ▼
[Incident Closure Decision] ──▶ INCIDENT RESOLVED / CLOSED
```

### Safety Guarantees & Constraints:
1. **Allowlisted Actions Only:** Currently scoped strictly to `restart_node_exporter`.
2. **Explicit Target Resolution:** Requires exact instance ID (`i-...`) matching affected incident signals.
3. **No Arbitrary Commands:** The execution adapter uses fixed internal command payloads (`systemctl restart node_exporter && systemctl is-active --quiet node_exporter`). No user-supplied shell input is accepted.
4. **Bounded Polling:** 60s execution timeout, 120s wait window, no blind retry loops.
5. **Fail-Closed Verification:** Incident closure requires all verification checks to pass; any failure escalates to a human operator.

---

## 📁 Repository Structure

```text
├── compute.tf                 # EC2 instances, Nginx & Node Exporter bootstrap
├── data.tf                    # AWS data sources (AZs, AMIs)
├── iam.tf                     # EC2 instance profiles and least-privilege executor policies
├── main.tf                    # Core VPC and infrastructure orchestration
├── network.tf                 # Internet Gateway, NAT Gateway, Route tables
├── security.tf                # Security groups for ALB, App, Prometheus, Grafana
├── subnets.tf                 # Public and Private multi-AZ subnet layout
├── variables.tf               # Configurable deployment inputs
├── outputs.tf                 # Exported VPC, ALB, and instance identifiers
├── versions.tf                # Terraform & AWS provider version constraints
├── docs/
│   └── incidents/
│       └── phase-8b-node-exporter-recovery.md  # Detailed live drill report & evidence
├── grafana/                   # Dashboard provisioning and JSON definitions
├── incident_intelligence/     # RCA, safety gates, and remediation engine
│   ├── collectors.py          # Read-only telemetry collectors
│   ├── engine.py              # Deterministic correlation and RCA rules
│   ├── execution.py           # SSM live execution adapter (allowlist-enforced)
│   ├── model.py               # Incident and Signal data classes
│   ├── remediation.py         # Approval gates, verification, and closure logic
│   └── report.py              # Human-readable incident rendering
├── runbooks/                  # Operational playbooks for alert response
├── sre/                       # SLI/SLO and burn-rate definitions
└── tests/
    └── test_incident_intelligence.py  # 31 automated unit tests
```

---

## 🗺️ Project Roadmap & Status

| Phase | Milestone | Status | Description |
|:---:|---|:---:|---|
| **Phase 1** | AWS Foundation | ✅ **Complete** | VPC, Multi-AZ Subnets, IGW, NAT Gateway, Routing |
| **Phase 2** | Application Infrastructure | ✅ **Complete** | ALB, Target Groups, Private EC2, Nginx Web Tier |
| **Phase 3** | Prometheus Observability | ✅ **Complete** | Prometheus Server, Node Exporter, Security Group rules |
| **Phase 4** | Alertmanager Integration | ✅ **Complete** | Alert routing, notification channels, alert grouping |
| **Phase 5** | Grafana Visualization | ✅ **Complete** | SRE Overview dashboard, multi-tier metric visualization |
| **Phase 6** | SLO & Burn-Rate Monitoring | ✅ **Complete** | Multi-window burn rates, error budget consumption alerts |
| **Phase 7** | Failure & Recovery Validation | ✅ **Complete** | Controlled failure testing and alert firing verification |
| **Phase 8A** | Incident Intelligence & RCA | ✅ **Complete** | Deterministic incident correlation & recommendation engine |
| **Phase 8B** | Human-Approved Remediation | ✅ **Complete** | SSM live execution adapter, safety gates, live drill verified |
| **Phase 9** | Policy-Controlled Autonomous SRE | 🔜 **Next** | Automated policy evaluations, rate limits, canary remediation |
| **Phase 10** | Portfolio Hardening & Demo | 📋 **Planned** | End-to-end interactive CLI, automated demonstration suite |

---

## 🧪 Testing & Validation

Run the complete test suite locally:

```bash
# Run 31 unit tests covering RCA, safety gates, SSM adapter, and verification
python3 -m unittest discover -v

# Validate Terraform syntax and configuration
terraform fmt -check
terraform validate
```
