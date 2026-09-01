# Multi-Window Multi-Burn-Rate Alerting

This document explains the Burn-Rate alerting methodology implemented on the AWS SRE Platform, based on Google SRE best practices.

---

## 1. Why Burn-Rate Alerting?

Traditional threshold alerts suffer from two major flaws:
1. **Short time windows (e.g., 5 minutes):** Cause alert fatigue from transient, self-healing spikes that consume almost zero error budget.
2. **Long time windows (e.g., 24 hours):** Cause unacceptable notification delays for severe outages that burn the entire error budget in minutes.

**Burn-rate alerting solves this by measuring the rate of error budget consumption relative to time.**

A burn rate of $1.0\times$ means the service will consume exactly $100\%$ of its error budget over the 30-day period. A burn rate of $14.4\times$ means $2\%$ of the entire 30-day error budget is consumed in just **1 hour**.

---

## 2. Mathematical Definition

$$\text{Burn Rate} = \frac{\text{Observed Error Rate}}{\text{Allowed Error Budget Ratio}}$$

For Node Availability ($99.9\%$ SLO, budget $= 0.001$):

$$\text{Burn Rate}_{5\text{m}} = \frac{1 - \text{avg\_over\_time}(\text{sre:node\_availability:ratio}[5\text{m}])}{0.001}$$

$$\text{Burn Rate}_{1\text{h}} = \frac{1 - \text{avg\_over\_time}(\text{sre:node\_availability:ratio}[1\text{h}])}{0.001}$$

---

## 3. PromQL Recording Rules

Prometheus computes short-window ($5\text{m}$) and long-window ($1\text{h}$) burn rates continuously:

```promql
# Short-Window (5m) Burn Rates
record: sre:node_availability:burn_rate_5m
expr: (1 - avg_over_time(sre:node_availability:ratio[5m])) / 0.001

record: sre:cpu_health:burn_rate_5m
expr: (1 - avg_over_time(sre:cpu_health:ratio[5m])) / 0.01

record: sre:memory_health:burn_rate_5m
expr: (1 - avg_over_time(sre:memory_health:ratio[5m])) / 0.01

record: sre:filesystem_health:burn_rate_5m
expr: (1 - avg_over_time(sre:filesystem_health:ratio[5m])) / 0.01

# Long-Window (1h) Burn Rates
record: sre:node_availability:burn_rate_1h
expr: (1 - avg_over_time(sre:node_availability:ratio[1h])) / 0.001

record: sre:cpu_health:burn_rate_1h
expr: (1 - avg_over_time(sre:cpu_health:ratio[1h])) / 0.01

record: sre:memory_health:burn_rate_1h
expr: (1 - avg_over_time(sre:memory_health:ratio[1h])) / 0.01

record: sre:filesystem_health:burn_rate_1h
expr: (1 - avg_over_time(sre:filesystem_health:ratio[1h])) / 0.01
```

---

## 4. Multi-Window Alert Rules

To ensure alerts trigger rapidly upon severe failure while instantly resetting when recovery occurs, Prometheus alerts require **both short and long windows to exceed the burn rate threshold simultaneously**:

```promql
- alert: NodeAvailabilityBurnRateHigh
  expr: |
    (sre:node_availability:burn_rate_5m > 14.4)
    and
    (sre:node_availability:burn_rate_1h > 14.4)
  for: 2m
  labels:
    severity: critical
    team: sre
  annotations:
    summary: "Node availability SLO burn rate is high"
    description: "Node {{ $labels.instance }} is consuming the 99.9% availability error budget at more than 14.4x the sustainable rate."

- alert: CPUHealthBurnRateHigh
  expr: |
    (sre:cpu_health:burn_rate_5m > 14.4)
    and
    (sre:cpu_health:burn_rate_1h > 14.4)
  for: 2m
  labels:
    severity: critical
    team: sre
  annotations:
    summary: "CPU health SLO burn rate is high"
    description: "CPU health on {{ $labels.instance }} is consuming the 99% error budget at more than 14.4x the sustainable rate."
```

### Operational Advantages:
1. **Low False Alarms:** Transient glitches trigger the $5\text{m}$ window but fail to elevate the $1\text{h}$ window, preventing false pages.
2. **Rapid Reset:** Once the node is remediated and healthy scrapes resume, the $5\text{m}$ burn rate immediately drops below $14.4$, clearing the alert without waiting for the full 1-hour window to cycle out.
