"""Deterministic, side-effect-free signal correlation and RCA rules."""

from __future__ import annotations

import hashlib
from typing import Any

from .model import Incident, SignalSnapshot


RESOURCE_ALERTS = {"HighCPUUsage", "CPUHealthBurnRateHigh", "HighMemoryUsage", "MemoryHealthBurnRateHigh", "FilesystemHealthBurnRateHigh"}


def _label(alert: dict[str, Any], name: str) -> str | None:
    return alert.get("labels", {}).get(name)


def _instance_from_target(target: dict[str, Any]) -> str | None:
    return target.get("labels", {}).get("instance") or target.get("instance")


def _matching_alb_targets(snapshot: SignalSnapshot, instance: str | None) -> list[dict[str, Any]]:
    if not instance:
        return []
    host = instance.split(":", 1)[0]
    return [target for target in snapshot.alb_targets if target.get("private_ip") == host or target.get("instance_id") == instance]


def _severity(alerts: list[dict[str, Any]]) -> str:
    levels = {_label(alert, "severity") for alert in alerts}
    return "CRITICAL" if "critical" in levels else "WARNING" if "warning" in levels else "INFO"


def _timeline(snapshot: SignalSnapshot, alerts: list[dict[str, Any]]) -> list[dict[str, str]]:
    events = list(snapshot.known_events)
    for alert in alerts:
        active_at = alert.get("activeAt") or alert.get("startsAt")
        if active_at:
            events.append({"timestamp": active_at, "event": f"{_label(alert, 'alertname')} active in Prometheus"})
    for alert in snapshot.alertmanager_alerts:
        starts_at = alert.get("startsAt")
        if starts_at:
            events.append({"timestamp": starts_at, "event": f"{_label(alert, 'alertname')} received by Alertmanager"})
    return sorted(events, key=lambda event: event["timestamp"])


def _approval(action: str, reason: str, resource: str, risk: str) -> dict[str, str]:
    return {
        "workflow": "ANALYZE -> RECOMMEND -> REQUEST_APPROVAL -> EXECUTE -> VERIFY",
        "what_will_change": action,
        "why": reason,
        "resource": resource,
        "expected_outcome": "Restore the affected signal or service while preserving application availability.",
        "risk": risk,
        "rollback": "No action has been executed. Future executable remediation must define its own rollback.",
    }


def analyze(snapshot: SignalSnapshot) -> list[Incident]:
    """Correlate active alerts into deterministic, evidence-backed incidents.

    This function reads only the supplied snapshot. It never calls a service,
    changes infrastructure, or executes recommended actions.
    """
    active_alerts = [alert for alert in snapshot.prometheus_alerts if alert.get("state", "firing") in {"firing", "pending"}]
    incidents: list[Incident] = []
    handled: set[int] = set()

    for index, alert in enumerate(active_alerts):
        name = _label(alert, "alertname") or "UnknownAlert"
        instance = _label(alert, "instance")
        matching_targets = [target for target in snapshot.prometheus_targets if _instance_from_target(target) == instance]
        down_target = any(target.get("health") == "down" for target in matching_targets)
        connection_refused = any("connection refused" in target.get("lastError", "").lower() for target in matching_targets)
        related_alerts = [candidate for candidate in active_alerts if _label(candidate, "instance") == instance]

        if name == "InstanceDown" and down_target:
            handled.update(index for index, candidate in enumerate(active_alerts) if _label(candidate, "instance") == instance and _label(candidate, "alertname") in {"InstanceDown", "NodeAvailabilityBurnRateHigh"})
            alb_targets = _matching_alb_targets(snapshot, instance)
            alb_healthy = bool(alb_targets) and all(target.get("health") == "healthy" for target in alb_targets)
            app_healthy = snapshot.application.get("status_code") == 200
            category = "monitoring_agent_failure" if connection_refused else "monitoring_target_unavailable"
            confidence = "high" if connection_refused and alb_healthy and app_healthy else "medium"
            action = "restart node_exporter"
            reason = "Prometheus cannot connect to the node exporter while the application and ALB target remain healthy."
            impact = {"monitoring": True, "application": not app_healthy, "infrastructure": False, "customer": not app_healthy}
            status = "AWAITING_REMEDIATION_APPROVAL"
        elif any(target.get("health") == "unhealthy" for target in _matching_alb_targets(snapshot, instance)) and snapshot.application.get("status_code", 0) >= 500:
            handled.add(index)
            alb_targets = _matching_alb_targets(snapshot, instance)
            action = "investigate unhealthy ALB target and application service"
            reason = "An ALB target is unhealthy and the ALB endpoint is returning a server error."
            category = "application_availability_failure"
            confidence = "high"
            impact = {"monitoring": False, "application": True, "infrastructure": True, "customer": True}
            status = "AWAITING_REMEDIATION_APPROVAL"
        elif name in RESOURCE_ALERTS:
            handled.add(index)
            alb_targets = _matching_alb_targets(snapshot, instance)
            action = "investigate resource utilization"
            reason = "A resource saturation alert is active; no automated action is permitted."
            category = "resource_saturation"
            confidence = "high"
            impact = {"monitoring": False, "application": False, "infrastructure": True, "customer": False}
            status = "AWAITING_REMEDIATION_APPROVAL"
        else:
            if index in handled:
                continue
            handled.add(index)
            alb_targets = _matching_alb_targets(snapshot, instance)
            action = "investigate affected service"
            reason = "The observed signals do not match a deterministic RCA rule."
            category = "unclassified"
            confidence = "low"
            impact = {"monitoring": False, "application": "unknown", "infrastructure": "unknown", "customer": "unknown"}
            status = "AWAITING_TRIAGE"

        resource = instance or "platform"
        alert_names = sorted({_label(candidate, "alertname") or "UnknownAlert" for candidate in related_alerts})
        incident_key = f"{snapshot.timestamp}|{resource}|{category}".encode()
        incident_id = f"INC-{hashlib.sha256(incident_key).hexdigest()[:8].upper()}"
        incidents.append(
            Incident(
                incident_id=incident_id,
                timestamp=snapshot.timestamp,
                severity=_severity(related_alerts),
                alert_name=", ".join(alert_names),
                affected_resource=resource,
                affected_instance=instance,
                service="node_exporter" if category.startswith("monitoring_") else "application-platform",
                environment=snapshot.environment,
                observed_signals={
                    "prometheus": matching_targets + related_alerts,
                    "alertmanager": [candidate for candidate in snapshot.alertmanager_alerts if _label(candidate, "instance") == instance],
                    "alb": alb_targets,
                    "application": [snapshot.application],
                    "node_exporter": matching_targets,
                },
                impact=impact,
                root_cause={"category": category, "confidence": confidence, "evidence": [target.get("lastError", target.get("health", "unknown")) for target in matching_targets] + [f"ALB target={target.get('health')}" for target in alb_targets] + [f"ALB HTTP={snapshot.application.get('status_code', 'unavailable')}"]},
                correlation={"related_alerts": alert_names, "related_targets": [resource], "related_services": ["Prometheus", "Alertmanager", "ALB", "nginx", "node_exporter"]},
                recommended_action={"action": action, "reason": reason, "risk": "low"},
                approval_required=True,
                status=status,
                timeline=_timeline(snapshot, related_alerts),
                approval_request=_approval(action, reason, resource, "low"),
            )
        )
    return incidents