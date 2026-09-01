"""Human-approved remediation workflow for Phase 8B.

This module intentionally does not perform autonomous remediation. It models the
approved workflow of recommendation -> approval -> explicit execution ->
verification -> closure, while keeping the actual system action outside of the
RCA engine and preventively forbidding arbitrary command execution.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import Enum
from typing import Any

from .model import Incident

ALLOWED_ACTIONS = {"restart_node_exporter"}


class RemediationAction(str, Enum):
    """Typed and allowlisted actions for Phase 8B."""

    RESTART_NODE_EXPORTER = "restart_node_exporter"


class ExecutionAdapter:
    """Execution abstraction for a disabled Phase 8B runtime."""

    def execute(self, *, action_id: str, incident: Incident, approval: "RemediationApproval") -> "RemediationExecutionResult":
        raise NotImplementedError("Live execution adapter is disabled in Phase 8B.")


class DisabledExecutionAdapter(ExecutionAdapter):
    """No-op adapter that blocks live execution while preserving the interface."""

    def execute(self, *, action_id: str, incident: Incident, approval: "RemediationApproval") -> "RemediationExecutionResult":
        return RemediationExecutionResult(
            action_id=action_id,
            status="not_implemented",
            executed=False,
            evidence=[
                "Live execution is disabled for Phase 8B.",
                "This adapter does not invoke shell commands, SSM, or AWS APIs.",
            ],
            executed_by=approval.approver,
            notes="Execution adapter intentionally disabled until a human-approved live adapter is implemented.",
        )


@dataclass
class RemediationApproval:
    """Required explicit human approval before an allowlisted action may proceed."""

    action_id: str
    approved: bool
    approver: str
    approval_reason: str
    approved_at: str | None = None

    def validate(self) -> str | None:
        if not self.action_id:
            return "Action is required."
        if self.action_id not in ALLOWED_ACTIONS:
            return f"Action '{self.action_id}' is not allowlisted."
        if not self.approved:
            return "Human approval is required before execution."
        if not self.approver or not self.approver.strip():
            return "Approver identity is required."
        if not self.approval_reason or not self.approval_reason.strip():
            return "Approval reason is required."
        return None


@dataclass
class RemediationExecutionResult:
    action_id: str
    status: str
    executed: bool
    evidence: list[str] = field(default_factory=list)
    executed_by: str | None = None
    timestamp: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    notes: str = ""


@dataclass
class VerificationResult:
    action_id: str
    status: str
    exporter_health: bool = False
    prometheus_target_up: bool = False
    alert_cleared: bool = False
    alb_healthy: bool = False
    app_healthy: bool = False
    evidence: list[str] = field(default_factory=list)
    timestamp: str = field(default_factory=lambda: datetime.now(UTC).isoformat())


def _incident_action_matches(incident: Incident, action_id: str) -> bool:
    recommended = (incident.recommended_action or {}).get("action", "")
    return action_id == "restart_node_exporter" and (
        recommended == "restart node_exporter" or recommended == "restart_node_exporter"
    )


def validate_action_for_incident(incident: Incident, action_id: str) -> str | None:
    """Reject non-allowlisted or mismatched actions before execution."""
    if action_id not in ALLOWED_ACTIONS:
        return f"Action '{action_id}' is not allowlisted."
    if incident.root_cause.get("category") != "monitoring_agent_failure":
        return "Only monitoring_agent_failure incidents may use the restart_node_exporter action."
    if not _incident_action_matches(incident, action_id):
        return "Recommended action does not match the allowlisted remediation choice."
    return None


def execute_human_approved_remediation(
    incident: Incident,
    approval: RemediationApproval,
    *,
    dry_run: bool = True,
    execution_adapter: ExecutionAdapter | None = None,
) -> RemediationExecutionResult:
    """Phase 8B execution gate: explicit human approval required, no autonomous action.

    The code intentionally does not execute arbitrary shell commands or call AWS APIs.
    In this Phase 8B safety model, execution is represented as a structured, explicit
    action record and remains inert unless the caller opts in to a live adapter.
    """
    if not isinstance(incident, Incident):
        return RemediationExecutionResult(
            action_id=getattr(approval, "action_id", "unknown"),
            status="blocked",
            executed=False,
            evidence=["Incident context is invalid."],
            notes="Execution is blocked because the incident object is invalid.",
        )

    validation_error = approval.validate()
    if validation_error:
        return RemediationExecutionResult(
            action_id=approval.action_id,
            status="blocked",
            executed=False,
            evidence=[validation_error],
            executed_by=approval.approver,
            notes="Execution blocked before any service activity was attempted.",
        )

    action_error = validate_action_for_incident(incident, approval.action_id)
    if action_error:
        return RemediationExecutionResult(
            action_id=approval.action_id,
            status="blocked",
            executed=False,
            evidence=[action_error],
            executed_by=approval.approver,
            notes="Allowlist validation failed.",
        )

    if dry_run:
        return RemediationExecutionResult(
            action_id=approval.action_id,
            status="dry_run",
            executed=False,
            evidence=[
                "Allowlisted remediation prepared for human-approved execution.",
                f"Affected resource: {incident.affected_resource}",
                f"Approver: {approval.approver}",
            ],
            executed_by=approval.approver,
            notes="No system action was performed; this is a safe planning-only result.",
        )

    adapter = execution_adapter or DisabledExecutionAdapter()
    return adapter.execute(action_id=approval.action_id, incident=incident, approval=approval)


def verify_node_exporter_recovery(
    *,
    exporter_health: bool,
    prometheus_target_up: bool,
    alert_cleared: bool,
    alb_healthy: bool,
    app_healthy: bool,
    action_id: str = "restart_node_exporter",
) -> VerificationResult:
    """Verify recovery criteria before closing the incident."""
    evidence: list[str] = []
    if exporter_health:
        evidence.append("node_exporter health endpoint is healthy")
    else:
        evidence.append("node_exporter health endpoint is not healthy")
    if prometheus_target_up:
        evidence.append("Prometheus target is UP")
    else:
        evidence.append("Prometheus target is not UP")
    if alert_cleared:
        evidence.append("related alert has cleared")
    else:
        evidence.append("related alert has not cleared")
    if alb_healthy:
        evidence.append("ALB target remains healthy")
    else:
        evidence.append("ALB target is not healthy")
    if app_healthy:
        evidence.append("application remains healthy")
    else:
        evidence.append("application is not healthy")

    status = "verified" if all([exporter_health, prometheus_target_up, alert_cleared, alb_healthy, app_healthy]) else "failed"
    return VerificationResult(
        action_id=action_id,
        status=status,
        exporter_health=exporter_health,
        prometheus_target_up=prometheus_target_up,
        alert_cleared=alert_cleared,
        alb_healthy=alb_healthy,
        app_healthy=app_healthy,
        evidence=evidence,
    )


def close_incident_if_verified(verification: VerificationResult) -> bool:
    """Only close the incident when all verification checks pass."""
    return verification.status == "verified"


__all__ = [
    "ALLOWED_ACTIONS",
    "RemediationAction",
    "ExecutionAdapter",
    "DisabledExecutionAdapter",
    "RemediationApproval",
    "RemediationExecutionResult",
    "VerificationResult",
    "execute_human_approved_remediation",
    "validate_action_for_incident",
    "verify_node_exporter_recovery",
    "close_incident_if_verified",
]
