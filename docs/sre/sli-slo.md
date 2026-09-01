# Service Level Indicators (SLIs) & Service Level Objectives (SLOs)

This document details the Service Level Indicators (SLIs) and Service Level Objectives (SLOs) implemented on the AWS SRE Platform.

---

## 1. Domain Separation: Infrastructure Health vs. Customer Availability

A fundamental principle of modern reliability engineering is distinguishing between internal component health and external customer-facing availability:

- **Customer-Facing Application Availability:** Whether user requests to the Application Load Balancer are successfully served HTTP `200 OK`.
- **Infrastructure & Monitoring Health:** Whether supporting components (such as `node_exporter`, CPU headroom, or memory capacity) are operating within normal parameters.

> **Key Takeaway:** An exporter failure degrades *observability* without degrading *customer availability*. Conversely, resource saturation degrades *infrastructure margin* before impacting customer requests.

---

## 2. Defined Platform Objectives (30-Day Rolling Window)

The platform implements five primary SLOs evaluated via Prometheus recording rules over a rolling 30-day window ($164,160$ expected 15-second scrape samples):

| Reliability Dimension | Indicator Type | Target SLO | Total 30d Error Budget | Recording Rule Target |
|---|---|:---:|:---:|---|
| **Node Availability** | Ratio (`up{job="node-exporter"}`) | **99.9%** | $0.1\%$ ($43.2\text{ min}$) | `sre:node_availability:slo_30d` |
| **CPU Health** | Utilization ($\le 80\%$) | **99.0%** | $1.0\%$ ($7.2\text{ hours}$) | `sre:cpu_health:slo_30d` |
| **Memory Health** | Utilization ($\le 85\%$) | **99.0%** | $1.0\%$ ($7.2\text{ hours}$) | `sre:memory_health:slo_30d` |
| **Filesystem Health** | Disk Usage ($\le 85\%$) | **99.0%** | $1.0\%$ ($7.2\text{ hours}$) | `sre:filesystem_health:slo_30d` |
| **Application Availability** | ALB Health (`200 OK`) | **99.9%** | $0.1\%$ ($43.2\text{ min}$) | ALB Metric Stream |

---

## 3. Mathematical Definitions & PromQL Implementations

### A. Node Availability SLI
Measures the ratio of successful scrape cycles where `node_exporter` is actively responding:

$$\text{SLI}_{\text{node}} = \frac{\sum \text{successful scrapes}}{\sum \text{total scrape attempts}} = \text{avg\_over\_time}(\text{up}\{\text{job}=\text{"node-exporter"}\}[30\text{d}])$$

```promql
# Instantaneous ratio per scrape
record: sre:node_availability:ratio
expr: up{job="node-exporter"}

# 30-day compliance evaluation with sample gating (>= 164,160 samples)
record: sre:node_availability:slo_30d
expr: (avg_over_time(sre:node_availability:ratio[30d]) and (sre:node_availability:samples_30d >= 164160))
```

---

### B. CPU Health SLI
Measures the proportion of time where aggregate CPU utilization is $\le 80\%$ (at least $20\%$ idle time):

$$\text{SLI}_{\text{cpu}} = \left( 100 - \left(\text{rate}(\text{node\_cpu\_seconds\_total}\{\text{mode}=\text{"idle"}\}[5\text{m}]) \times 100\right) \right) \le 80$$

```promql
record: sre:cpu_health:ratio
expr: (100 - (rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100)) <= bool 80

record: sre:cpu_health:slo_30d
expr: (avg_over_time(sre:cpu_health:ratio[30d]) and (sre:cpu_health:samples_30d >= 164160))
```

---

### C. Memory Health SLI
Measures the proportion of time where available memory is $\ge 15\%$ (utilization $\le 85\%$):

$$\text{SLI}_{\text{mem}} = \left( 100 \times \left( 1 - \frac{\text{node\_memory\_MemAvailable\_bytes}}{\text{node\_memory\_MemTotal\_bytes}} \right) \right) \le 85$$

```promql
record: sre:memory_health:ratio
expr: (100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))) <= bool 85

record: sre:memory_health:slo_30d
expr: (avg_over_time(sre:memory_health:ratio[30d]) and (sre:memory_health:samples_30d >= 164160))
```

---

### D. Filesystem Health SLI
Measures the proportion of time where root filesystem utilization is $\le 85\%$:

$$\text{SLI}_{\text{fs}} = \left( 100 \times \left( 1 - \frac{\text{node\_filesystem\_avail\_bytes}}{\text{node\_filesystem\_size\_bytes}} \right) \right) \le 85$$

```promql
record: sre:filesystem_health:ratio
expr: (100 * (1 - (node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/", fstype!="tmpfs"}))) <= bool 85

record: sre:filesystem_health:slo_30d
expr: (avg_over_time(sre:filesystem_health:ratio[30d]) and (sre:filesystem_health:samples_30d >= 164160))
```

---

## 4. Sample Gating & Measurement Integrity

To prevent misleading 100% compliance figures during initial bootstrap, the 30-day recording rules enforce a sample count gate:

$$\text{sre:node\_availability:samples\_30d} = \text{count\_over\_time}(\text{sre:node\_availability:ratio}[30\text{d}])$$

Compliance is recorded only when the sample count meets or exceeds $164,160$ samples ($30\text{ days} \times 24\text{ hours} \times 60\text{ minutes} \times 4\text{ scrapes/min}$).
