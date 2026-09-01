# Incident Intelligence / RCA

This Phase 8A component is a standalone, read-only Python package. It does not alter Terraform, Prometheus, Alertmanager, Grafana, AWS resources, or application services.

## Architecture

```text
Prometheus targets, alerts, and rules -----+
Alertmanager active alerts ----------------+--> read-only collectors --> deterministic correlation/RCA --> incident report + approval request
AWS ALB target health ---------------------+
ALB HTTP response -------------------------+
```

The collector queries Prometheus and Alertmanager HTTP APIs, AWS `describe-target-health`/`describe-instances`, and the existing ALB HTTP endpoint. The engine operates only on the resulting `SignalSnapshot`; it has no execution or write path.

## Model and reasoning

Each `Incident` carries the incident identity and scope, source evidence grouped by system, impact across monitoring/application/infrastructure/customer domains, RCA category and confidence, correlated alerts/targets/services, a timestamped timeline, recommended action, and an approval request.

The current deterministic rule is intentionally narrow:

```text
Prometheus target down + connection refused on :9100 + healthy matching ALB target + ALB HTTP 200
  => monitoring_agent_failure, high confidence, no application/customer impact
  => recommend restart node_exporter; approval required
```

Related `InstanceDown` and `NodeAvailabilityBurnRateHigh` signals for the same exporter form one incident. An unhealthy matching ALB target together with an ALB HTTP 5xx response is an `application_availability_failure` with customer impact. CPU/memory/filesystem alerts are classified as `resource_saturation`. Unknown combinations are deliberately held at `AWAITING_TRIAGE`, not guessed.

## Run

Replay the documented App-A incident without contacting AWS:

```bash
python3 -m incident_intelligence --fixture incident_intelligence/fixtures/app_a_node_exporter_down.json
```

Collect from live, locally forwarded Prometheus and Alertmanager endpoints:

```bash
python3 -m incident_intelligence \
  --environment dev \
  --alb-dns-name sre-dev-alb-1147481649.eu-west-1.elb.amazonaws.com \
  --target-group-arn "$(terraform output -raw web_target_group_arn)"
```

## Approval gate and future remediation

Phase 8A implements `ANALYZE -> RECOMMEND -> REQUEST_APPROVAL`. Every recommendation includes the proposed change, reason, resource, expected outcome, risk, and rollback statement. `EXECUTE` and `VERIFY` are reserved for a later phase. Future execution adapters may support exporter/nginx restarts, target draining, instance isolation/replacement, rollback, and post-action verification, but no such adapters exist here.

## Limits

The engine does not invent timestamps: the timeline contains only source timestamps and explicitly supplied known events. Current infrastructure-level root cause classification is conservative until additional CloudWatch, application metrics, logging, and tracing evidence is available.