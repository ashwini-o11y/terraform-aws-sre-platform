# Phase 8B Incident Drill Report: Human-Approved Node Exporter Recovery

## 1. Objective

Demonstrate and validate the controlled Phase 8B human-approved remediation workflow for an observability agent failure on the AWS SRE Platform. The drill exercises the complete end-to-end operational lifecycle:

$$\text{DETECT} \longrightarrow \text{CORRELATE} \longrightarrow \text{ANALYZE (RCA)} \longrightarrow \text{RECOMMEND} \longrightarrow \text{HUMAN APPROVAL} \longrightarrow \text{SAFETY GATES} \longrightarrow \text{SSM REMEDIATION} \longrightarrow \text{VERIFY} \longrightarrow \text{CLOSE}$$

---

## 2. Architecture & Roles

```text
┌────────────────────────────────────────────────────────────────────────┐
│                          Observability Plane                           │
│  Prometheus (10.0.11.28) ─── Scrape :9100 ───▶ App-A / App-B           │
│  Alertmanager (10.0.11.28) ◀── Alerts ─────── Prometheus               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Telemetry Snapshot
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Incident Intelligence Engine                       │
│  - Correlates firing alerts + scrape targets + ALB health + HTTP code  │
│  - Deterministic RCA: monitoring_agent_failure                         │
│  - Recommends: restart_node_exporter (Approval Required = True)        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Recommendation & Authorization Request
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Human Operator (Ashwini)                        │
│  - Explicit Approval: action_id="restart_node_exporter", approved=True │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Dispatches via Live SSM Adapter
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 AWS Systems Manager (Role B Executor)                  │
│  - SendCommand: AWS-RunShellScript                                     │
│  - Target: i-06b9096543449916d (App-A)                                 │
│  - Fixed Payload: systemctl restart node_exporter                      │
│                   systemctl is-active --quiet node_exporter            │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Execution
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       EC2 Target Plane (Role A)                        │
│  App-A (i-06b9096543449916d, 10.0.11.132)                             │
│  - AmazonSSMManagedInstanceCore Profile                                │
│  - node_exporter.service restarted & verified active                   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Post-Remediation Probing
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     8-Point Recovery Verification                      │
│  - Target UP, Alerts Cleared, ALB Healthy, HTTP 200                    │
│  - close_incident_if_verified() ──▶ INCIDENT RESOLVED / CLOSED         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Failure Scenario

- **Target Instance:** App-A (`sre-dev-app-a`, Instance ID: `i-06b9096543449916d`, Private IP: `10.0.11.132`)
- **Injected Fault:** Controlled failure injection stopping `node_exporter.service` via SSM.
- **Service Isolation:** Nginx web service and SSM Agent remained fully operational. Only the monitoring agent was stopped.

---

## 4. Detection Signals & Telemetry

Prometheus scrape target `10.0.11.132:9100` failed with connection refused, triggering alerting:

- **Prometheus Scrape Health:** `down` (`lastError: dial tcp 10.0.11.132:9100: connect: connection refused`)
- **Active Prometheus Alerts:**
  - `InstanceDown` (`severity: critical`, `instance: 10.0.11.132:9100`)
  - `NodeAvailabilityBurnRateHigh` (`severity: critical`, `burn_rate: >14.4x`, `instance: 10.0.11.132:9100`)
- **ALB Target Health:** `healthy` (`i-06b9096543449916d:80`)
- **ALB Endpoint Response:** HTTP `200 OK`
- **Customer / Application Impact:** None observed (application serving traffic normally).

---

## 5. Incident Intelligence RCA

The deterministic correlation engine analyzed the snapshot and classified the incident:

- **Incident ID:** `INC-255A868F`
- **Severity:** `CRITICAL`
- **Root Cause Category:** `monitoring_agent_failure`
- **Confidence:** `HIGH` (Evidence: target down on :9100 + connection refused + ALB target healthy + ALB HTTP 200)
- **Impact Assessment:**
  - Monitoring: `True`
  - Application: `False`
  - Infrastructure: `False`
  - Customer: `False`
- **Recommended Action:** `restart node_exporter`
- **Approval Required:** `True`
- **Incident Status:** `AWAITING_REMEDIATION_APPROVAL`

---

## 6. Human Approval

Remediation was strictly blocked until explicit human approval was provided:

```python
RemediationApproval(
    action_id="restart_node_exporter",
    approved=True,
    approver="Ashwini",
    approval_reason="Controlled Phase 8B remediation drill to restore the App-A monitoring agent after confirmed node_exporter failure.",
    approved_at="2026-09-01T18:58:52Z"
)
```

---

## 7. Safety Gates

Before any command dispatch, the `SSMExecutionAdapter` evaluated the following safety gates (failing closed on any discrepancy):

1. **Allowlist Validation:** Action `restart_node_exporter` is in `ALLOWED_ACTIONS`.
2. **Category Validation:** Incident root cause category is `monitoring_agent_failure`.
3. **Recommendation Alignment:** Recommended action matches `restart_node_exporter`.
4. **Target Identity Validation:** Target ID `i-06b9096543449916d` is explicit and matches the incident's affected resource.
5. **Human Gate:** `approved=True` with valid approver and reason.
6. **Command Hardening:** No arbitrary commands or parameters accepted; internal payload is fixed.

---

## 8. AWS Systems Manager Remediation

The remediation adapter dispatched the fixed execution payload:

- **SSM Document:** `AWS-RunShellScript`
- **Target Instance:** `i-06b9096543449916d`
- **Fixed Commands:**
  ```bash
  systemctl restart node_exporter
  systemctl is-active --quiet node_exporter
  ```
- **SSM Command ID:** `0989fecf-2969-4784-8d6f-51a12c6b8692`
- **Execution Submission:** `2026-09-01T18:58:52Z`
- **Execution Completion:** `2026-09-01T18:58:55Z`
- **SSM Invocation Status:** `Success`
- **Exit Code:** `0`

---

## 9. Recovery Verification

Rather than assuming success upon SSM exit code 0, a comprehensive eight-point read-only verification was conducted:

| Check # | Verification Item | Result | Telemetry Evidence |
|:---:|---|:---:|---|
| **1** | node_exporter service on App-A | **PASS** | `systemctl is-active` returned `active` (PID 133185 running) |
| **2** | Prometheus target `10.0.11.132:9100` | **PASS** | Scrape health returned `up`, `lastError: ""` |
| **3** | `InstanceDown` alert | **PASS** | Alert transitioned to inactive / cleared |
| **4** | `NodeAvailabilityBurnRateHigh` alert | **PASS** | Target recovery restored `up == 1` metrics |
| **5** | App-A ALB target health | **PASS** | `i-06b9096543449916d` remains `healthy` |
| **6** | App-B ALB target health | **PASS** | `i-078cdb8c637466f5e` remains `healthy` |
| **7** | ALB HTTP response | **PASS** | HTTP `200 OK` across multiple probes |
| **8** | Application health | **PASS** | Nginx web server maintained 100% uptime |

---

## 10. Incident Closure Decision

- **Verification Evaluation:** `verify_node_exporter_recovery(...) -> status: verified`
- **Closure Rule:** `close_incident_if_verified(verification) -> True`
- **Final Incident Status:** `RESOLVED / CLOSED`

---

## 11. Timeline of Events

| Timestamp (UTC) | Component | Event / Action |
|---|---|---|
| `2026-09-01T18:47:33Z` | Pre-Flight | Read-only pre-flight inspection confirmed App-A SSM `Online` and ALB healthy. |
| `2026-09-01T18:54:00Z` | App-A | Controlled failure injection: `systemctl stop node_exporter` executed via SSM. |
| `2026-09-01T18:54:33Z` | Prometheus | Prometheus detected target `10.0.11.132:9100` down (`connect: connection refused`). |
| `2026-09-01T18:54:33Z` | Alertmanager | Alerts `InstanceDown` and `NodeAvailabilityBurnRateHigh` fired. |
| `2026-09-01T18:54:33Z` | Engine | Incident `INC-255A868F` generated (`monitoring_agent_failure`, `AWAITING_REMEDIATION_APPROVAL`). |
| `2026-09-01T18:58:52Z` | Human Gate | Ashwini provided explicit approval for `restart_node_exporter`. |
| `2026-09-01T18:58:52Z` | SSM Adapter | Safety checks passed; SSM SendCommand `0989fecf-2969-4784-8d6f-51a12c6b8692` dispatched. |
| `2026-09-01T18:58:55Z` | AWS SSM | Command completed with status `Success`, exit code `0`. |
| `2026-09-01T18:59:48Z` | Prometheus | Next scrape cycle confirmed `10.0.11.132:9100` is `up`. |
| `2026-09-01T19:00:00Z` | Verification | 8-point telemetry verification confirmed 100% health across all layers. |
| `2026-09-01T19:00:05Z` | Engine | `close_incident_if_verified()` evaluated to `True`; incident closed. |

---

## 12. Safety Boundaries & Guarantees

1. **Separation of Concerns:** RCA and remediation are completely decoupled. The RCA engine is purely functional and read-only.
2. **Fail-Closed Design:** Any missing approval, ambiguous target, unallowlisted action, or mismatched category immediately aborts execution (`status: blocked`).
3. **No Autonomous Loop:** Execution is strictly gated by human approval.
4. **Bounded Scope:** The only permitted executable action is `restart_node_exporter`.
5. **No Blind Trust:** SSM command success does not equate to incident resolution; resolution requires external telemetry re-verification.

---

## 14. IAM Hardening Note

- The Phase 8B live drill was conducted using the existing development identity (`AdministratorAccess`).
- A dedicated least-privilege policy (`aws_iam_policy.remediation_executor`) has been implemented and validated in Terraform in [iam.tf](iam.tf), but was intentionally NOT applied to avoid live infrastructure mutations during the drill.
- For production environments, hardening should deploy and bind this dedicated identity restricting `ssm:SendCommand` strictly to `AWS-RunShellScript` on instances tagged `Project = SRE Platform`.
