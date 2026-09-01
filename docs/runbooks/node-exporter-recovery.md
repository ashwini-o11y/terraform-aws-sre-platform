# Standard Operating Procedure: Node Exporter Recovery

**Document ID:** `SOP-SRE-001`
**Target Action:** `restart_node_exporter`
**Classification:** Operational Runbook
**Execution Mode:** Human-Approved SSM Remediation (Phase 8B)

---

## 1. Purpose & Scope
This runbook defines the operational procedure for diagnosing, validating, approving, and verifying the remediation of an unresponsive Prometheus Node Exporter agent on private EC2 instances within the AWS SRE Platform.

- **Applies to:** `sre-dev-app-a`, `sre-dev-app-b`, `sre-dev-prometheus`, `sre-dev-grafana`
- **Scope Limit:** Single service action (`restart_node_exporter`). Does not cover EC2 reboots, OS patching, or application code deployment.

---

## 2. Detection & Triggering Conditions

The runbook is initiated upon one or more of the following alerts in Prometheus/Alertmanager:

1. `InstanceDown` (`severity: critical`): Exporter unreachable on `TCP:9100` for $> 2\text{ minutes}$.
2. `NodeAvailabilityBurnRateHigh` (`severity: critical`): Burn rate exceeds $14.4\times$ over $5\text{m}$ and $1\text{h}$ windows.
3. Incident Intelligence classification: `monitoring_agent_failure` (`confidence: high`).

---

## 3. Pre-Checks & Customer Impact Triage

Before taking any remediation action, verify customer impact and application availability:

```text
[Alert Fired: InstanceDown on 10.0.11.132:9100]
               │
               ▼
   [Is ALB Target Group Healthy for App-A?] ─── No ───▶ [ESCALATE to Application Outage Runbook]
               │ Yes
               ▼
   [Is ALB HTTP Status 200 OK?] ─── No ───▶ [ESCALATE to Application Outage Runbook]
               │ Yes
               ▼
   [Customer Impact = NONE] ──▶ Proceed with Agent Remediation
```

---

## 4. Remediation Procedure (Phase 8B Human-Approved Workflow)

### Step 1: Incident Intelligence Analysis
Run the deterministic CLI to analyze the active signals:

```bash
python3 -m incident_intelligence \
  --alb-dns-name "<alb_dns_name>" \
  --target-group-arn "<web_target_group_arn>"
```

Confirm that the output reports:
- Root cause: `monitoring_agent_failure`
- Recommended action: `restart node_exporter`
- Impact: `monitoring: true`, `application: false`, `customer: false`

### Step 2: Human Operator Approval
Provide explicit authorization via CLI or API:

```bash
python3 -m incident_intelligence \
  --fixture <incident_fixture.json> \
  --approve-action restart_node_exporter \
  --approver "<your_name>" \
  --approval-reason "Restoring unresponsive node_exporter after confirming zero customer impact"
```

### Step 3: Execution Dispatch
The live execution adapter dispatches the fixed SSM payload:

```bash
systemctl restart node_exporter
systemctl is-active --quiet node_exporter
```

---

## 5. Recovery Verification Checklist

Do **NOT** close the incident based solely on SSM exit code `0`. Verify all five recovery signals:

- [ ] **1. Exporter Active:** `systemctl is-active node_exporter` returns `active`.
- [ ] **2. Prometheus Target UP:** Prometheus target health transitions from `down` to `up`.
- [ ] **3. InstanceDown Alert Cleared:** Alert deactivates in Prometheus.
- [ ] **4. ALB Target Healthy:** AWS Target Group describes instance target as `healthy`.
- [ ] **5. Application Serving Traffic:** ALB endpoint returns HTTP `200 OK`.

---

## 6. Incident Closure & Escalation Criteria

- **Closure Criteria:** All 5 checklist items evaluate to `True`. `close_incident_if_verified()` returns `True`. Incident status transitions to `RESOLVED / CLOSED`.
- **Escalation Trigger:** If SSM SendCommand fails, times out ($> 120\text{s}$), or if post-restart verification fails, **DO NOT RETRY AUTOMATICALLY**. Escalate immediately to the SRE Lead for interactive system inspection via AWS Systems Manager Session Manager.
