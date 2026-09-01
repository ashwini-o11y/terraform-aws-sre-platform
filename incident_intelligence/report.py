"""Human-readable rendering for an incident analysis; no execution support."""

from __future__ import annotations

from .model import Incident


def render(incident: Incident) -> str:
    evidence = incident["root_cause"]["evidence"] if isinstance(incident, dict) else incident.root_cause["evidence"]
    data = incident if isinstance(incident, dict) else incident.to_dict()
    return "\n".join([
        "--------------------------------------------------",
        f"INCIDENT #{data['incident_id']}",
        "--------------------------------------------------",
        f"Severity: {data['severity']}",
        f"Affected Resource: {data['affected_resource']}",
        f"Incident Type: {data['root_cause']['category']}",
        "Detection: Prometheus",
        f"Alerts: {data['alert_name']}",
        "Evidence:",
        *[f"- {item}" for item in evidence],
        f"Customer Impact: {data['impact']['customer']}",
        f"Application Impact: {data['impact']['application']}",
        f"Monitoring Impact: {data['impact']['monitoring']}",
        f"Likely Root Cause: {data['root_cause']['category']}",
        f"Confidence: {data['root_cause']['confidence'].upper()}",
        f"Recommended Remediation: {data['recommended_action']['action']}",
        f"Risk: {data['recommended_action']['risk'].upper()}",
        f"Approval Required: {data['approval_required']}",
        f"Status: {data['status']}",
        "--------------------------------------------------",
    ])