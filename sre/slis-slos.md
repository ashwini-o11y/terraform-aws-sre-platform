SRE Service Level Indicators and Objectives

Purpose

This document defines the Service Level Indicators (SLIs), Service Level Objectives (SLOs), and Error Budget approach for the Terraform AWS SRE Platform.

The objective is to establish measurable reliability targets for the application and infrastructure platform.

The platform currently uses Prometheus and Node Exporter for infrastructure-level reliability measurements.

Application-level availability measurement is defined but is planned for future implementation using Application Load Balancer and application request metrics.

1. Service Level Indicators

1.1 Application Availability

Definition

Application availability measures the percentage of application requests that successfully reach a healthy application instance.

Measurement Source

The Application Load Balancer is used as the primary source for application availability measurements.

The intended measurement compares successful application requests against total application requests.

SLI Calculation

Successful application requests
-------------------------------- × 100
Total application requests

SLO

Target: 99.9% monthly availability.

Error Budget

Error Budget = 100% - 99.9%
             = 0.1%

For a 30-day month:

30 × 24 × 60 = 43,200 minutes
43,200 × 0.001 = 43.2 minutes

Monthly error budget is approximately 43 minutes.

Implementation Status

Planned.

The Application Load Balancer is currently deployed, but application-level request success metrics have not yet been implemented as a Prometheus SLI.

1.2 Node Availability

Definition

Node availability measures the percentage of time that application instances are reachable by Prometheus through Node Exporter.

Measurement Source

Prometheus uses the up metric for the node-exporter job.

up = 1 → Prometheus successfully scraped the target
up = 0 → Prometheus could not scrape the target

Prometheus Metric

up{job="node-exporter"}

SLI Calculation

Time Node Exporter is UP
------------------------ × 100
Total observation time

Equivalent conceptual calculation:

Successful scrape intervals
--------------------------- × 100
Total scrape intervals

Scrape Configuration

Prometheus scrapes the application Node Exporter endpoints every 15 seconds.

Current targets:

App A: 10.0.11.132:9100
App B: 10.0.12.233:9100

Failure Condition

up{job="node-exporter"} == 0

Alert Evaluation

The InstanceDown alert fires when the target remains unavailable for more than 2 minutes.

SLO

Target: 99.5% monthly node availability.

Error Budget

Error Budget = 100% - 99.5%
             = 0.5%

For a 30-day month:

43,200 × 0.005 = 216 minutes

Monthly error budget is 216 minutes.

Implementation Status

Implemented.

Prometheus currently monitors both application instances through Node Exporter.

1.3 CPU Health

Definition

CPU health measures the percentage of observation time during which application instances remain below the defined CPU utilization threshold.

Measurement Source

CPU metrics are collected by Node Exporter and stored in Prometheus.

Metric:

node_cpu_seconds_total

Prometheus Expression

100 - (
  avg by(instance) (
    rate(node_cpu_seconds_total{mode="idle"}[5m])
  ) * 100
)

Calculation

The 5-minute rate of idle CPU time is calculated first.

Idle CPU percentage
=
Average rate of idle CPU time × 100

CPU utilization is then:

CPU utilization
=
100 - Idle CPU percentage

Threshold

CPU utilization above 80% is considered a warning condition.

Evaluation Window

The condition must remain above 80% for 5 minutes.

Alert

HighCPUUsage

Alert Expression

100 - (
  avg by(instance) (
    rate(node_cpu_seconds_total{mode="idle"}[5m])
  ) * 100
) > 80

SLI Interpretation

Time CPU utilization is at or below 80%
--------------------------------------- × 100
Total observation time

SLO

Target: 99% of observation time with CPU utilization at or below 80%.

Error Budget

Error Budget = 100% - 99%
             = 1%

For a 30-day month:

43,200 × 0.01 = 432 minutes

Monthly error budget is 432 minutes.

Implementation Status

Implemented as an operational monitoring indicator through the HighCPUUsage Prometheus alert.

1.4 Memory Health

Definition

Memory health measures the percentage of observation time during which application instances remain below the defined memory utilization threshold.

Measurement Source

Memory metrics are collected by Node Exporter and stored in Prometheus.

Metrics:

node_memory_MemAvailable_bytes
node_memory_MemTotal_bytes

Prometheus Expression

100 * (
  1 -
  (
    node_memory_MemAvailable_bytes /
    node_memory_MemTotal_bytes
  )
)

Calculation

Available memory ratio
=
MemAvailable / MemTotal

Memory utilization
=
100 × (1 - MemAvailable / MemTotal)

Threshold

Memory utilization above 85% is considered a warning condition.

Evaluation Window

The condition must remain above 85% for 5 minutes.

Alert

HighMemoryUsage

Alert Expression

100 * (
  1 -
  (
    node_memory_MemAvailable_bytes /
    node_memory_MemTotal_bytes
  )
) > 85

SLI Interpretation

Time memory utilization is at or below 85%
------------------------------------------ × 100
Total observation time

SLO

Target: 99% of observation time with memory utilization at or below 85%.

Error Budget

Error Budget = 100% - 99%
             = 1%

For a 30-day month:

43,200 × 0.01 = 432 minutes

Monthly error budget is 432 minutes.

Implementation Status

Implemented as an operational monitoring indicator through the HighMemoryUsage Prometheus alert.

1.5 Filesystem Health

Definition

Filesystem health measures the percentage of observation time during which the root filesystem remains below the defined utilization threshold.

Measurement Source

Filesystem metrics are collected by Node Exporter and stored in Prometheus.

Metrics:

node_filesystem_avail_bytes
node_filesystem_size_bytes

Prometheus Expression

100 * (
  1 - (
    node_filesystem_avail_bytes{
      mountpoint="/",
      fstype!="tmpfs"
    }
    /
    node_filesystem_size_bytes{
      mountpoint="/",
      fstype!="tmpfs"
    }
  )
)

Calculation

Available capacity ratio
=
Available bytes / Total filesystem size

Filesystem utilization
=
100 × (1 - Available bytes / Total filesystem size)

The calculation is restricted to the root filesystem:

mountpoint="/"

and excludes:

fstype="tmpfs"

Threshold

Root filesystem utilization above 85% is considered a warning condition.

Evaluation Window

The condition must remain above 85% for 5 minutes.

Alert

FilesystemAlmostFull

Alert Expression

100 * (
  1 - (
    node_filesystem_avail_bytes{
      mountpoint="/",
      fstype!="tmpfs"
    }
    /
    node_filesystem_size_bytes{
      mountpoint="/",
      fstype!="tmpfs"
    }
  )
) > 85

SLI Interpretation

Time root filesystem utilization is at or below 85%
---------------------------------------------------- × 100
Total observation time

SLO

Target: 99% of observation time with root filesystem utilization at or below 85%.

Current Baseline

The application instances currently have approximately:

Root filesystem size: 30 GB
Used space:           4.3 GB
Utilization:          15%

The current filesystem utilization is well below the 85% warning threshold.

Error Budget

Error Budget = 100% - 99%
             = 1%

For a 30-day month:

43,200 × 0.01 = 432 minutes

Monthly error budget is 432 minutes.

Implementation Status

Implemented as an operational monitoring indicator through the FilesystemAlmostFull Prometheus alert.

2. Service Level Objectives Summary

SLI

SLO Target

Threshold

Evaluation Window

Status

Application Availability

99.9%

Request success

Monthly

Planned

Node Availability

99.5%

up == 0

2 minutes

Implemented

CPU Health

99%

>80% utilization

5 minutes

Implemented

Memory Health

99%

>85% utilization

5 minutes

Implemented

Filesystem Health

99%

>85% utilization

5 minutes

Implemented

3. Error Budget

3.1 Definition

An error budget represents the amount of unreliability permitted by an SLO.

Error Budget = 100% - SLO Target

The error budget provides a measurable tolerance for service degradation or unavailability.

3.2 Examples

99.9% SLO

Error Budget = 0.1%
30-day budget = 43.2 minutes

99.5% SLO

Error Budget = 0.5%
30-day budget = 216 minutes

99% SLO

Error Budget = 1%
30-day budget = 432 minutes

4. Error Budget Policy

4.1 Healthy Error Budget

When sufficient error budget remains:

Normal infrastructure changes may proceed.

Reliability improvements should continue.

Routine maintenance can proceed through the normal change process.

Operational work should be prioritized based on service impact.

4.2 Reduced Error Budget

When a significant portion of the error budget has been consumed:

Investigate reliability incidents.

Prioritize reliability improvements.

Review recurring alerts.

Review recent infrastructure or application changes.

Reduce unnecessary operational risk.

Prioritize remediation of recurring reliability issues.

4.3 Exhausted Error Budget

When the error budget is exhausted:

Reliability work takes priority over non-critical changes.

Changes should be reviewed for additional operational risk.

Recurring incidents should be addressed before increasing change velocity.

Reliability-impacting changes should require additional review.

Engineering effort should focus on restoring the service to the required reliability level.

5. Alert Relationship

Alerts are operational signals and are not themselves the SLO.

Metric
  ↓
SLI
  ↓
SLO
  ↓
Error Budget
  ↓
Operational Alert
  ↓
Incident Response

5.1 Instance Down

Node Exporter unavailable
        ↓
up{job="node-exporter"} == 0
        ↓
Node Availability SLI decreases
        ↓
Potential SLO impact
        ↓
InstanceDown alert
        ↓
Instance Down Runbook
        ↓
Investigation and remediation
        ↓
Prometheus target returns to UP

The InstanceDown alert fires after the target has remained unavailable for more than 2 minutes.

5.2 Prometheus Target Down

Prometheus cannot scrape Node Exporter
        ↓
up{job="node-exporter"} == 0
        ↓
PrometheusTargetDown
        ↓
Investigation
        ↓
Remediation
        ↓
Target returns to UP

PrometheusTargetDown provides an additional operational signal for monitoring-target availability.

5.3 High CPU

CPU utilization > 80%
        ↓
Condition persists for 5 minutes
        ↓
HighCPUUsage alert
        ↓
CPU Health SLI affected
        ↓
Potential SLO impact
        ↓
High CPU Runbook
        ↓
Investigation and remediation

5.4 High Memory

Memory utilization > 85%
        ↓
Condition persists for 5 minutes
        ↓
HighMemoryUsage alert
        ↓
Memory Health SLI affected
        ↓
Potential SLO impact
        ↓
High Memory Runbook
        ↓
Investigation and remediation

5.5 Filesystem Almost Full

Root filesystem utilization > 85%
        ↓
Condition persists for 5 minutes
        ↓
FilesystemAlmostFull alert
        ↓
Filesystem Health SLI affected
        ↓
Potential SLO impact
        ↓
Filesystem Runbook
        ↓
Investigation and remediation

6. Incident Response Relationship

The SRE monitoring workflow is:

Monitoring
    ↓
Metric Collection
    ↓
SLI Evaluation
    ↓
SLO Evaluation
    ↓
Alert Detection
    ↓
Alertmanager
    ↓
Incident Identification
    ↓
Runbook Selection
    ↓
Investigation
    ↓
Remediation
    ↓
Validation
    ↓
Alert Recovery
    ↓
Incident Closure

Current operational access is provided through AWS Systems Manager Session Manager.

Application instances can be accessed without exposing SSH directly to the internet.

## 6.1 Alertmanager Routing Validation

Alert routing has been validated using a controlled Node Exporter failure on App A.

Test scenario:

Node Exporter on App A was intentionally stopped.

The Prometheus target changed from:

up = 1

to:

up = 0

After the configured 2-minute evaluation period:

InstanceDown → FIRING
PrometheusTargetDown → FIRING

Prometheus successfully delivered both alerts to Alertmanager.

Both alerts were classified as:

severity="critical"

Alertmanager successfully routed both alerts to the:

critical

receiver.

Recovery was then validated by restarting Node Exporter.

After recovery:

App A → up = 1
App B → up = 1
Prometheus active alerts → []

This validated the complete incident lifecycle:

Failure
  ↓
Metric degradation
  ↓
Prometheus alert evaluation
  ↓
Alert firing
  ↓
Alertmanager routing
  ↓
Incident remediation
  ↓
Metric recovery
  ↓
Alert resolution

Implementation Status

Validated.

7. Current Reliability Signals

Signal

Source

Calculation / Threshold

Alert

Node availability

Prometheus up

up == 0 for 2 minutes

InstanceDown

Prometheus target availability

Prometheus up

up == 0 for 2 minutes

PrometheusTargetDown

CPU utilization

Node Exporter

>80% for 5 minutes

HighCPUUsage

Memory utilization

Node Exporter

>85% for 5 minutes

HighMemoryUsage

Root filesystem utilization

Node Exporter

>85% for 5 minutes

FilesystemAlmostFull

8. Current Platform Scope

The current platform provides the infrastructure and monitoring capabilities required to establish the initial SRE reliability model.

Current components include:

AWS infrastructure managed by Terraform

Multi-AZ application instances

Application Load Balancer

Private application tier

NGINX

Prometheus

Node Exporter

Alertmanager

Grafana

SRE infrastructure dashboard

Prometheus alert rules

Operational runbooks

AWS Systems Manager

IAM instance profiles

Security Group based monitoring access

9. Current Implementation Status

Capability

Status

SLI definitions

Implemented

Application Availability SLI

Planned

Node Availability SLI

Implemented

CPU Health SLI

Implemented

Memory Health SLI

Implemented

Filesystem Health SLI

Implemented

Application Availability SLO

Defined

Node Availability SLO

Defined

CPU Health SLO

Defined

Memory Health SLO

Defined

Filesystem Health SLO

Defined

Error Budget model

Defined

Error Budget policy

Defined

Prometheus alerting

Implemented

Alertmanager

Implemented

Incident detection

Validated

Incident recovery

Validated

Runbooks

Implemented

SLO measurement recording rules

Planned

SLO dashboard

Planned

Error-budget dashboard

Planned

Burn-rate alerting

Planned

10. Future Improvements

The following improvements are planned:

Application-level request metrics

ALB request-based availability measurement

Application error-rate SLIs

Application latency SLIs

Prometheus recording rules for SLI calculations

SLO dashboards in Grafana

Error-budget dashboards

Burn-rate alerting

OpenTelemetry application metrics

Distributed tracing

Centralized logging

Trace-to-metric correlation

Service dependency mapping

11. SRE Principle

The platform follows the principle that monitoring should support reliability decisions rather than simply collect metrics.

The intended progression is:

Observe
  ↓
Measure
  ↓
Define SLI
  ↓
Set SLO
  ↓
Calculate Error Budget
  ↓
Detect Reliability Risk
  ↓
Respond
  ↓
Improve

The current implementation establishes the foundation for this reliability engineering lifecycle.