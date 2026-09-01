"""Structured, serializable incident and evidence models."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class SignalSnapshot:
    """Evidence collected from existing observability systems."""

    timestamp: str
    environment: str
    prometheus_targets: list[dict[str, Any]] = field(default_factory=list)
    prometheus_alerts: list[dict[str, Any]] = field(default_factory=list)
    alertmanager_alerts: list[dict[str, Any]] = field(default_factory=list)
    alb_targets: list[dict[str, Any]] = field(default_factory=list)
    application: dict[str, Any] = field(default_factory=dict)
    collection_errors: list[str] = field(default_factory=list)
    known_events: list[dict[str, str]] = field(default_factory=list)


@dataclass
class Incident:
    incident_id: str
    timestamp: str
    severity: str
    alert_name: str
    affected_resource: str
    affected_instance: str | None
    service: str
    environment: str
    observed_signals: dict[str, list[dict[str, Any]]]
    impact: dict[str, bool | str]
    root_cause: dict[str, Any]
    correlation: dict[str, list[str]]
    recommended_action: dict[str, str]
    approval_required: bool
    status: str
    timeline: list[dict[str, str]]
    approval_request: dict[str, str]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)