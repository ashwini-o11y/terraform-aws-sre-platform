"""Approved live execution adapter for the Phase 8B SSM workflow.

This module intentionally implements only a single allowlisted action:
restart_node_exporter. It never accepts arbitrary user input, never exposes a
broad shell runner, and never executes automation unless a human-approved target
and action have already been validated.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from .model import Incident
from .remediation import ALLOWED_ACTIONS, RemediationApproval

FIXED_COMMANDS = [
    "systemctl restart node_exporter",
    "systemctl is-active --quiet node_exporter",
]
FIXED_TIMEOUT_SECONDS = 60
POLL_INTERVAL_SECONDS = 2
WAIT_TIMEOUT_SECONDS = 120


@dataclass
class SSMExecutionResult:
    incident_id: str
    action: str
    target_instance_id: str | None
    target_private_ip: str | None = None
    approver: str | None = None
    approval_timestamp: str | None = None
    approval_reason: str | None = None
    ssm_command_id: str | None = None
    submission_timestamp: str | None = None
    completion_timestamp: str | None = None
    status: str = "blocked"
    exit_code: int | None = None
    stdout_excerpt: str | None = None
    stderr_excerpt: str | None = None
    error_info: str | None = None
    executed: bool = False
    evidence: list[str] = field(default_factory=list)

    @staticmethod
    def _excerpt(value: str | None, *, limit: int = 4000) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        if len(text) <= limit:
            return text
        return text[:limit] + "..."


class SSMExecutionAdapter:
    """Narrow Systems Manager adapter for the approved restart node_exporter workflow."""

    def __init__(self, *, client: Any | None = None, wait_timeout_seconds: int = WAIT_TIMEOUT_SECONDS, timeout_seconds: int = FIXED_TIMEOUT_SECONDS):
        self.client = client
        self.wait_timeout_seconds = wait_timeout_seconds
        self.timeout_seconds = timeout_seconds

    @staticmethod
    def _fixed_command_payload() -> list[str]:
        return list(FIXED_COMMANDS)

    @staticmethod
    def _safe_target_instance_id(target_instance_id: str | None) -> str | None:
        if not target_instance_id:
            return None
        value = str(target_instance_id).strip()
        return value if value.startswith("i-") else None

    @staticmethod
    def _target_private_ip(incident: Incident, target_instance_id: str | None) -> str | None:
        if not target_instance_id:
            return None
        for target in incident.observed_signals.get("alb", []):
            if target.get("instance_id") == target_instance_id:
                return target.get("private_ip")
        if incident.affected_resource and "." in incident.affected_resource:
            return incident.affected_resource.split(":", 1)[0]
        return None

    @staticmethod
    def _is_target_match(incident: Incident, target_instance_id: str | None) -> bool:
        if not target_instance_id:
            return False
        if not str(target_instance_id).startswith("i-"):
            return False
        candidates = {
            incident.affected_instance,
            incident.affected_resource,
            incident.affected_resource.split(":", 1)[0] if incident.affected_resource else None,
            *[
                str(target.get("instance_id"))
                for target in incident.observed_signals.get("alb", [])
                if isinstance(target, dict) and target.get("instance_id")
            ],
        }
        return target_instance_id in {candidate for candidate in candidates if candidate}

    def execute(
        self,
        *,
        action_id: str,
        incident: Incident,
        approval: RemediationApproval,
        target_instance_id: str | None,
        command: str | None = None,
    ) -> SSMExecutionResult:
        """Execute the approved restart_node_exporter action through SSM.

        The adapter accepts no user-controlled command. If a command is supplied it
        must match the approved fixed payload exactly; any other payload is rejected.
        """
        if command is not None:
            if command != "\n".join(self._fixed_command_payload()):
                raise ValueError("Arbitrary command injection is not allowed for the approved adapter.")

        if not isinstance(incident, Incident):
            return SSMExecutionResult(
                incident_id=getattr(incident, "incident_id", "unknown"),
                action=action_id,
                target_instance_id=target_instance_id,
                approver=getattr(approval, "approver", None),
                approval_timestamp=getattr(approval, "approved_at", None),
                approval_reason=getattr(approval, "approval_reason", None),
                status="blocked",
                executed=False,
                evidence=["Incident context is invalid."],
                error_info="Incident context is invalid.",
            )

        if action_id not in ALLOWED_ACTIONS:
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=target_instance_id,
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                status="blocked",
                executed=False,
                evidence=[f"Action '{action_id}' is not allowlisted."],
                error_info=f"Action '{action_id}' is not allowlisted.",
            )

        if not approval.approved:
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=target_instance_id,
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                status="blocked",
                executed=False,
                evidence=["Human approval is required before execution."],
                error_info="Human approval is required before execution.",
            )

        if incident.root_cause.get("category") != "monitoring_agent_failure":
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=target_instance_id,
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                status="blocked",
                executed=False,
                evidence=["Only monitoring_agent_failure incidents may use the restart_node_exporter action."],
                error_info="Only monitoring_agent_failure incidents may use the restart_node_exporter action.",
            )

        recommended = (incident.recommended_action or {}).get("action", "")
        if action_id == "restart_node_exporter" and recommended not in {"restart node_exporter", "restart_node_exporter"}:
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=target_instance_id,
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                status="blocked",
                executed=False,
                evidence=["Recommended action does not match the allowlisted remediation choice."],
                error_info="Recommended action does not match the allowlisted remediation choice.",
            )

        safe_target = self._safe_target_instance_id(target_instance_id)
        if not safe_target:
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=target_instance_id,
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                status="blocked",
                executed=False,
                evidence=["Target instance must be an explicit EC2 instance ID."],
                error_info="Target instance must be an explicit EC2 instance ID.",
            )

        if not self._is_target_match(incident, safe_target):
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=safe_target,
                target_private_ip=self._target_private_ip(incident, safe_target),
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                status="blocked",
                executed=False,
                evidence=["Target identity does not match the incident's affected resource."],
                error_info="Target identity does not match the incident's affected resource.",
            )

        if self.client is None:
            try:
                import boto3

                self.client = boto3.client("ssm")
            except ImportError:
                import awscli.botocore.session

                session = awscli.botocore.session.get_session()
                self.client = session.create_client("ssm")

        submission_at = datetime.now(UTC).isoformat()
        try:
            response = self.client.send_command(
                DocumentName="AWS-RunShellScript",
                InstanceIds=[safe_target],
                Parameters={"commands": FIXED_COMMANDS},
                TimeoutSeconds=self.timeout_seconds,
                MaxConcurrency="1",
                MaxErrors="0",
            )
        except Exception as exc:  # pragma: no cover - exercised through mocked tests.
            return SSMExecutionResult(
                incident_id=incident.incident_id,
                action=action_id,
                target_instance_id=safe_target,
                target_private_ip=self._target_private_ip(incident, safe_target),
                approver=approval.approver,
                approval_timestamp=approval.approved_at,
                approval_reason=approval.approval_reason,
                ssm_command_id=None,
                submission_timestamp=submission_at,
                completion_timestamp=datetime.now(UTC).isoformat(),
                status="failed",
                executed=False,
                exit_code=None,
                stdout_excerpt=None,
                stderr_excerpt=None,
                error_info=str(exc),
                evidence=["SSM submission failed."],
            )

        command_id = response.get("Command", {}).get("CommandId")
        invocation_status: dict[str, Any] | None = None
        deadline = time.monotonic() + self.wait_timeout_seconds

        while time.monotonic() < deadline:
            time.sleep(POLL_INTERVAL_SECONDS)
            try:
                invocation_status = self.client.get_command_invocation(
                    CommandId=command_id,
                    InstanceId=safe_target,
                )
            except Exception:
                invocation_status = None
                continue

            status = invocation_status.get("Status")
            if status in {"Success", "Failed", "Cancelled", "TimedOut"}:
                break

        if invocation_status is None:
            if command_id:
                status = "timed_out"
                error_info = "SSM command exceeded the wait timeout window or did not return a final status."
            else:
                status = "failed"
                error_info = "SSM invocation status could not be retrieved."
            exit_code = None
            stdout_excerpt = None
            stderr_excerpt = None
        elif invocation_status.get("Status") == "Success":
            status = "success"
            exit_code = invocation_status.get("ExitCode")
            stdout_excerpt = invocation_status.get("StandardOutputContent")
            stderr_excerpt = invocation_status.get("StandardErrorContent")
            error_info = None
        elif invocation_status.get("Status") == "TimedOut":
            status = "timed_out"
            exit_code = invocation_status.get("ExitCode")
            stdout_excerpt = invocation_status.get("StandardOutputContent")
            stderr_excerpt = invocation_status.get("StandardErrorContent")
            error_info = "SSM command timed out before completion."
        elif time.monotonic() >= deadline:
            status = "timed_out"
            exit_code = invocation_status.get("ExitCode")
            stdout_excerpt = invocation_status.get("StandardOutputContent")
            stderr_excerpt = invocation_status.get("StandardErrorContent")
            error_info = "SSM command exceeded the wait timeout window."
        else:
            status = "failed"
            exit_code = invocation_status.get("ExitCode")
            stdout_excerpt = invocation_status.get("StandardOutputContent")
            stderr_excerpt = invocation_status.get("StandardErrorContent")
            error_info = invocation_status.get("StatusDetails") or "SSM invocation returned a non-zero result."

        completion_at = datetime.now(UTC).isoformat()
        executed = status == "success"

        if status == "success" and exit_code not in {0, None}:
            status = "failed"
            executed = False
            error_info = error_info or "SSM command exited with a non-zero status."

        if status == "success":
            evidence = [
                "Approved remediation was executed via AWS Systems Manager SendCommand.",
                f"Target: {safe_target}",
                "Fixed command payload was used for restart_node_exporter.",
            ]
        else:
            evidence = [
                "Execution did not complete successfully via AWS Systems Manager.",
                f"Target: {safe_target}",
                f"Status: {status}",
            ]

        return SSMExecutionResult(
            incident_id=incident.incident_id,
            action=action_id,
            target_instance_id=safe_target,
            target_private_ip=self._target_private_ip(incident, safe_target),
            approver=approval.approver,
            approval_timestamp=approval.approved_at,
            approval_reason=approval.approval_reason,
            ssm_command_id=command_id,
            submission_timestamp=submission_at,
            completion_timestamp=completion_at,
            status=status,
            exit_code=exit_code,
            stdout_excerpt=SSMExecutionResult._excerpt(stdout_excerpt),
            stderr_excerpt=SSMExecutionResult._excerpt(stderr_excerpt),
            error_info=error_info,
            executed=executed,
            evidence=evidence,
        )


__all__ = ["SSMExecutionAdapter", "SSMExecutionResult", "FIXED_COMMANDS", "FIXED_TIMEOUT_SECONDS", "WAIT_TIMEOUT_SECONDS"]
