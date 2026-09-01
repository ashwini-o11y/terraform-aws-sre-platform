"""Read-only collectors for Prometheus, Alertmanager, ALB, and application health."""

from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen

from .model import SignalSnapshot


def _json(url: str) -> Any:
    with urlopen(url, timeout=10) as response:  # nosec B310: endpoints are operator supplied
        return json.load(response)


def _aws(*args: str) -> Any:
    completed = subprocess.run(["aws", *args, "--output", "json"], check=True, capture_output=True, text=True)
    return json.loads(completed.stdout)


def collect(environment: str, prometheus_url: str, alertmanager_url: str, alb_dns_name: str, target_group_arn: str) -> SignalSnapshot:
    """Collect a point-in-time, read-only snapshot from existing platform APIs."""
    errors: list[str] = []
    targets: list[dict[str, Any]] = []
    prometheus_alerts: list[dict[str, Any]] = []
    alertmanager_alerts: list[dict[str, Any]] = []
    alb_targets: list[dict[str, Any]] = []
    application: dict[str, Any] = {"url": f"http://{alb_dns_name}"}
    try:
        targets = _json(f"{prometheus_url}/api/v1/targets")["data"]["activeTargets"]
        prometheus_alerts = _json(f"{prometheus_url}/api/v1/alerts")["data"]["alerts"]
    except (URLError, KeyError, ValueError) as error:
        errors.append(f"Prometheus collection failed: {error}")
    try:
        alertmanager_alerts = _json(f"{alertmanager_url}/api/v2/alerts")
    except (URLError, ValueError) as error:
        errors.append(f"Alertmanager collection failed: {error}")
    try:
        descriptions = _aws("elbv2", "describe-target-health", "--target-group-arn", target_group_arn)["TargetHealthDescriptions"]
        instance_ids = [item["Target"]["Id"] for item in descriptions]
        instances = _aws("ec2", "describe-instances", "--instance-ids", *instance_ids)["Reservations"]
        ip_by_id = {instance["InstanceId"]: instance["PrivateIpAddress"] for reservation in instances for instance in reservation["Instances"]}
        alb_targets = [{"instance_id": item["Target"]["Id"], "private_ip": ip_by_id.get(item["Target"]["Id"]), "health": item["TargetHealth"]["State"], "reason": item["TargetHealth"].get("Reason")} for item in descriptions]
    except (KeyError, subprocess.CalledProcessError, ValueError) as error:
        errors.append(f"ALB collection failed: {error}")
    try:
        with urlopen(application["url"], timeout=10) as response:  # nosec B310: endpoint is the deployed ALB DNS name
            application["status_code"] = response.status
    except URLError as error:
        application["error"] = str(error)
    return SignalSnapshot(datetime.now(UTC).isoformat(), environment, targets, prometheus_alerts, alertmanager_alerts, alb_targets, application, errors)