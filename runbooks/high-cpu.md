# Runbook: High CPU Usage

## Alert

`HighCPUUsage`

## Severity

Warning

## Threshold

CPU utilization above 80% for more than 5 minutes.

## Investigation

Connect to the affected instance:

```bash
aws ssm start-session --target INSTANCE_ID
