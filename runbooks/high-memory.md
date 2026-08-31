# Runbook: High Memory Usage

## Alert

`HighMemoryUsage`

## Severity

Warning

## Threshold

Memory utilization above 85% for more than 5 minutes.

## Investigation

Connect to the affected instance:

```bash
aws ssm start-session --target INSTANCE_ID
