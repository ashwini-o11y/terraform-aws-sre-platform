# Error Budget Management

This document defines how Error Budgets are calculated, monitored, and used for operational decision-making on the AWS SRE Platform.

---

## 1. What is an Error Budget?

An Error Budget is the allowable margin of unreliability permitted for a service over a defined rolling window. It represents the mathematical inverse of the Service Level Objective (SLO):

$$\text{Error Budget} = 100\% - \text{SLO Target}$$

For a 30-day rolling period ($43,200\text{ minutes}$):

| SLO Target | Error Budget Ratio | Total Allowed Unreliability (30 Days) |
|:---:|:---:|:---:|
| **99.9%** | $0.1\%$ ($0.001$) | **43.2 minutes** |
| **99.0%** | $1.0\%$ ($0.01$) | **432.0 minutes (7.2 hours)** |

---

## 2. Real-Time Error Budget Calculation in PromQL

The platform continuously evaluates remaining error budgets using dedicated recording rules with a minimum floor clamp:

$$\text{Error Budget Remaining} = \max\left(0, \, 1 - \frac{1 - \text{Observed SLO}_{30\text{d}}}{\text{Allowed Error Budget}}\right)$$

### PromQL Recording Rules:

```promql
# Node Availability (99.9% SLO -> Allowed Budget = 0.001)
record: sre:node_availability:error_budget_remaining_30d
expr: clamp_min(1 - ((1 - sre:node_availability:slo_30d) / 0.001), 0)

# CPU Health (99.0% SLO -> Allowed Budget = 0.01)
record: sre:cpu_health:error_budget_remaining_30d
expr: clamp_min(1 - ((1 - sre:cpu_health:slo_30d) / 0.01), 0)

# Memory Health (99.0% SLO -> Allowed Budget = 0.01)
record: sre:memory_health:error_budget_remaining_30d
expr: clamp_min(1 - ((1 - sre:memory_health:slo_30d) / 0.01), 0)

# Filesystem Health (99.0% SLO -> Allowed Budget = 0.01)
record: sre:filesystem_health:error_budget_remaining_30d
expr: clamp_min(1 - ((1 - sre:filesystem_health:slo_30d) / 0.01), 0)
```

---

## 3. Operational Policy & Error Budget Governance

Error budget depletion acts as an engineering control gate governing platform changes and risk tolerance:

```text
Error Budget Remaining:
┌───────────────────────────────────────────────────────────┐
│ 100% - 50%  🟢 HEALTHY: Normal deployments, feature velocity│
├───────────────────────────────────────────────────────────┤
│  50% - 20%  🟡 DEGRADED: Increased review, freeze high-risk│
├───────────────────────────────────────────────────────────┤
│  20% -  0%  🔴 EXHAUSTED: Change freeze, focus on reliability│
└───────────────────────────────────────────────────────────┘
```

1. **Healthy State ($> 50\%$ Remaining):** Standard continuous deployment and feature development proceed unimpeded.
2. **Degraded State ($20\% - 50\%$ Remaining):** Architectural modifications and non-critical infrastructure changes require peer SRE approval.
3. **Exhausted State ($< 20\%$ Remaining):** Non-emergency changes are frozen. Engineering velocity is redirected entirely toward reliability hardening, root cause remediation, and observability improvements.
