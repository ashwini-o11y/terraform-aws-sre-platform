# Incident Intelligence & Deterministic RCA Engine

An engineering deep dive into the architecture, mathematical reasoning, safety constraints, and implementation of the `incident_intelligence` subsystem.

---

## 1. Architectural Purpose

The `incident_intelligence` package is a standalone, read-only Python subsystem designed to eliminate alert fatigue and human error during multi-system operational incidents.

It operates under an uncompromised safety mandate:

$$\text{Signals} \longrightarrow \text{Correlation} \longrightarrow \text{Deterministic RCA} \longrightarrow \text{Human Approval Gate} \longrightarrow \text{SSM Execution} \longrightarrow \text{Verification}$$

> **Core Philosophy:** Diagnosis must never have side effects. An engine may recommend an action with mathematical determinism, but execution strictly requires out-of-band authorization and target validation.

---

## 2. Core Modules & Subsystem Structure

```text
incident_intelligence/
├── collectors.py          # Read-only REST and AWS API signal collectors
├── engine.py              # Pure-functional, deterministic correlation & RCA rules
├── execution.py           # SSM live execution adapter (allowlist-enforced)
├── model.py               # Strongly typed data models (SignalSnapshot, Incident)
├── remediation.py         # Human approval gate, allowlist validation, and closure logic
└── report.py              # Structured human-readable incident rendering
```

---

## 3. Data Model & Evidence Schema

### `SignalSnapshot`
Captures multi-source state at an exact point in time:
- `prometheus_targets`: Scrape status (`health`, `lastError`, scrape duration)
- `prometheus_alerts`: Active firing alerts with labels and annotations
- `alertmanager_alerts`: Ingested Alertmanager alerts
- `alb_targets`: AWS Target Group health descriptions (`State: healthy|unhealthy`)
- `application`: Real-time probe results (HTTP status code, latency)
- `known_events`: Historical maintenance and injection markers

### `Incident`
Represents an evidence-backed operational anomaly:
- `incident_id`: Deterministic hash (`INC-<SHA256>`)
- `root_cause`: `category`, `confidence`, and evidence list
- `impact`: Dimensional mapping across `monitoring`, `application`, `infrastructure`, and `customer`
- `recommended_action`: Structured action payload (`action`, `reason`, `risk`)
- `approval_required`: Always `True` for executable actions
- `status`: Lifecycle state (`AWAITING_TRIAGE`, `AWAITING_REMEDIATION_APPROVAL`, `RESOLVED`)

---

## 4. Deterministic RCA Rules

The engine replaces opaque heuristics with transparent, deterministic signal correlation:

```python
# Rule: Monitoring Agent Failure vs. Real Outage
if name == "InstanceDown" and down_target:
    if connection_refused and alb_healthy and app_healthy:
        category = "monitoring_agent_failure"
        confidence = "high"
        action = "restart node_exporter"
        impact = {"monitoring": True, "application": False, "infrastructure": False, "customer": False}
        status = "AWAITING_REMEDIATION_APPROVAL"
```

### Correlation Rule Matrix

| Observed Signals | Root Cause Category | Customer Impact | Recommended Action |
|---|---|:---:|---|
| Target `:9100` DOWN + Connection Refused + ALB Target HEALTHY + HTTP 200 | `monitoring_agent_failure` | **None** | `restart node_exporter` |
| Target `:9100` DOWN + ALB Target UNHEALTHY + HTTP 5xx | `application_availability_failure` | **High** | Investigate ALB / Application |
| `HighCPUUsage` / `CPUHealthBurnRateHigh` firing | `resource_saturation` | **None** | Investigate CPU Saturation |
| Unrecognized or conflicting signal combinations | `unclassified` | **Unknown** | Hold at `AWAITING_TRIAGE` |

---

## 5. Security & Safety Boundaries

### Why Arbitrary Shell Commands Are Forbidden
To prevent command injection, privilege escalation, and unintentional infrastructure damage, the live execution adapter does not expose any generic shell runner.

- **Allowlisted Action Set:** `ALLOWED_ACTIONS = {"restart_node_exporter"}`
- **Fixed Execution Payload:** Hardcoded internally to:
  ```bash
  systemctl restart node_exporter
  systemctl is-active --quiet node_exporter
  ```
- **Target Instance Validation:** The adapter strictly checks that the target instance ID starts with `i-` and matches the incident's affected resource candidate set.
- **Fail-Closed Execution:** Any missing approval, ambiguous target, or unrecognized action aborts execution immediately (`status: blocked`, `executed: False`).
