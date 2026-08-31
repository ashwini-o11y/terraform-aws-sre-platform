# Runbook: Filesystem Almost Full

## Alert

`FilesystemAlmostFull`

## Severity

Warning

## Threshold

Root filesystem utilization above 85% for more than 5 minutes.

## Prometheus Expression

```promql
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