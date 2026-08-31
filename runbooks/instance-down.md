# Runbook: Instance Down

## Alert

`InstanceDown`

## Severity

Critical

## Description

Node Exporter has been unavailable for more than 2 minutes.

Prometheus expression:

```promql
up{job="node-exporter"} == 0