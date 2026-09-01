import unittest
from unittest.mock import Mock, patch

from incident_intelligence.engine import analyze
from incident_intelligence.execution import SSMExecutionAdapter
from incident_intelligence.model import SignalSnapshot

# NOTE: Testing the live adapter is intentionally isolated from AWS. The tests
# mock boto3 and validate the safety gates, not any real Systems Manager call.


def snapshot(alerts, targets, alb="healthy", http=200):
    instance = "10.0.11.132:9100"
    return SignalSnapshot(
        timestamp="2026-08-31T22:15:00Z",
        environment="dev",
        prometheus_alerts=alerts,
        prometheus_targets=targets,
        alertmanager_alerts=alerts,
        alb_targets=[{"instance_id": "i-app-a", "private_ip": "10.0.11.132", "health": alb}],
        application={"status_code": http},
        known_events=[{"timestamp": "2026-08-31T21:56:43Z", "event": "node_exporter failure injected"}],
    )


def alert(name, instance="10.0.11.132:9100", severity="critical"):
    return {"labels": {"alertname": name, "instance": instance, "severity": severity}, "state": "firing", "activeAt": "2026-08-31T22:14:54Z"}


class IncidentIntelligenceTests(unittest.TestCase):
    def test_node_exporter_down_with_healthy_alb_is_monitoring_incident(self):
        data = snapshot([alert("InstanceDown"), alert("NodeAvailabilityBurnRateHigh")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}])
        incidents = analyze(data)
        self.assertEqual(len(incidents), 1)
        self.assertEqual(incidents[0].root_cause["category"], "monitoring_agent_failure")
        self.assertTrue(incidents[0].impact["monitoring"])
        self.assertFalse(incidents[0].impact["application"])
        self.assertFalse(incidents[0].impact["customer"])
        self.assertEqual(incidents[0].recommended_action["action"], "restart node_exporter")
        self.assertTrue(incidents[0].approval_required)

    def test_unhealthy_alb_target_is_not_misclassified_as_monitoring_failure(self):
        incident = analyze(snapshot([alert("ApplicationUnavailable")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "up"}], alb="unhealthy", http=503))[0]
        self.assertEqual(incident.root_cause["category"], "application_availability_failure")
        self.assertNotEqual(incident.root_cause["category"], "monitoring_agent_failure")
        self.assertTrue(incident.impact["customer"])

    def test_high_cpu_is_resource_saturation(self):
        incident = analyze(snapshot([alert("HighCPUUsage", severity="warning")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "up"}]))[0]
        self.assertEqual(incident.root_cause["category"], "resource_saturation")
        self.assertTrue(incident.impact["infrastructure"])

    def test_high_memory_is_resource_saturation(self):
        incident = analyze(snapshot([alert("HighMemoryUsage", severity="warning")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "up"}]))[0]
        self.assertEqual(incident.root_cause["category"], "resource_saturation")

    def test_alb_and_http_failure_remains_customer_impacting_triage(self):
        incident = analyze(snapshot([alert("ApplicationUnavailable")], [], alb="unhealthy", http=503))[0]
        self.assertEqual(incident.status, "AWAITING_REMEDIATION_APPROVAL")
        self.assertEqual(incident.root_cause["confidence"], "high")
        self.assertTrue(incident.impact["application"])

    def test_related_node_alerts_correlate_to_one_incident(self):
        incidents = analyze(snapshot([alert("InstanceDown"), alert("NodeAvailabilityBurnRateHigh")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connection refused"}]))
        self.assertEqual(len(incidents), 1)
        self.assertEqual(incidents[0].correlation["related_alerts"], ["InstanceDown", "NodeAvailabilityBurnRateHigh"])


    def test_phase_8b_approval_requires_allowlisted_action(self):
        from incident_intelligence.remediation import ALLOWED_ACTIONS
        self.assertEqual(ALLOWED_ACTIONS, {"restart_node_exporter"})

    def test_phase_8b_human_approval_is_required_before_execution(self):
        from incident_intelligence.remediation import RemediationApproval, execute_human_approved_remediation

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=False, approver="ops-lead", approval_reason="Human approval required before restart")

        result = execute_human_approved_remediation(incident, approval, dry_run=True)
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_phase_8b_invalid_action_is_blocked(self):
        from incident_intelligence.remediation import RemediationApproval, execute_human_approved_remediation

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="arbitrary_shell_command", approved=True, approver="ops-lead", approval_reason="Not allowed")

        result = execute_human_approved_remediation(incident, approval, dry_run=True)
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_phase_8b_recommendation_action_mismatch_is_blocked(self):
        from incident_intelligence.remediation import RemediationApproval, execute_human_approved_remediation

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Valid")
        incident.recommended_action = {"action": "restart nginx", "reason": "wrong", "risk": "low"}

        result = execute_human_approved_remediation(incident, approval, dry_run=True)
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_phase_8b_wrong_incident_category_is_blocked(self):
        from incident_intelligence.remediation import RemediationApproval, execute_human_approved_remediation

        incident = analyze(snapshot([alert("HighCPUUsage", severity="warning")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "up"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Should be blocked")

        result = execute_human_approved_remediation(incident, approval, dry_run=True)
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_phase_8b_approved_restart_node_exporter_prepare_is_safe(self):
        from incident_intelligence.remediation import RemediationApproval, execute_human_approved_remediation

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Validated: app healthy, ALB healthy, monitoring degraded")

        result = execute_human_approved_remediation(incident, approval, dry_run=True)
        self.assertEqual(result.status, "dry_run")
        self.assertEqual(result.action_id, "restart_node_exporter")
        self.assertFalse(result.executed)

    def test_phase_8b_cli_requires_approval_to_run_dry_run(self):
        import subprocess
        import sys

        completed = subprocess.run(
            [sys.executable, "-m", "incident_intelligence", "--fixture", "incident_intelligence/fixtures/app_a_node_exporter_down.json"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0)
        self.assertIn("Human approval is required before execution.", completed.stdout)

    def test_phase_8b_cli_approved_dry_run_only(self):
        import subprocess
        import sys

        completed = subprocess.run(
            [
                sys.executable,
                "-m",
                "incident_intelligence",
                "--fixture",
                "incident_intelligence/fixtures/app_a_node_exporter_down.json",
                "--approve-action",
                "restart_node_exporter",
                "--approver",
                "ops-lead",
                "--approval-reason",
                "Approved by human for dry-run preparation only",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0)
        self.assertIn("Execution status: dry_run", completed.stdout)

    def test_phase_8b_no_arbitrary_command_execution_capability(self):
        from incident_intelligence.remediation import RemediationApproval, execute_human_approved_remediation

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Used to validate safe path")
        result = execute_human_approved_remediation(incident, approval, dry_run=True)
        self.assertNotIn("systemctl", str(result.evidence))
        self.assertNotIn("ssm", str(result.evidence).lower())
        self.assertNotIn("aws", str(result.evidence).lower())
        self.assertFalse(result.executed)

    def test_phase_8b_verification_marks_incident_closed_when_recovery_is_observed(self):
        from incident_intelligence.remediation import verify_node_exporter_recovery, close_incident_if_verified

        verification = verify_node_exporter_recovery(
            exporter_health=True,
            prometheus_target_up=True,
            alert_cleared=True,
            alb_healthy=True,
            app_healthy=True,
        )
        self.assertEqual(verification.status, "verified")
        self.assertTrue(close_incident_if_verified(verification))

    def test_live_ssm_adapter_requires_approval_before_execution(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=False, approver="ops-lead", approval_reason="Need approval")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_rejects_invalid_action(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="reboot_instance", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_rejects_recommendation_mismatch(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        incident.recommended_action = {"action": "restart nginx", "reason": "wrong", "risk": "low"}
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_rejects_wrong_incident_category(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("HighCPUUsage", severity="warning")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "up"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_requires_target_instance(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id=None)
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_rejects_ambiguous_target(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="ambiguous")
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_rejects_target_identity_mismatch(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-other-instance")
        self.assertEqual(result.status, "blocked")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_calls_ssm_for_approved_action(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        incident.affected_instance = "i-1234567890abcdef0"
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        client = Mock()
        client.send_command.return_value = {"Command": {"CommandId": "cmd-123"}}
        client.get_command_invocation.return_value = {
            "Status": "Success",
            "StandardOutputContent": "restart ok",
            "StandardErrorContent": "",
            "ExitCode": 0,
        }

        adapter = SSMExecutionAdapter(client=client)
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "success")
        self.assertTrue(result.executed)
        self.assertEqual(result.target_instance_id, "i-1234567890abcdef0")
        self.assertEqual(result.ssm_command_id, "cmd-123")

    def test_live_ssm_adapter_rejects_arbitrary_command_supply(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        adapter = SSMExecutionAdapter(client=Mock())
        with self.assertRaises(ValueError):
            adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0", command="rm -rf /")

    def test_live_ssm_adapter_marks_ssm_submission_failure(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        incident.affected_instance = "i-1234567890abcdef0"
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        client = Mock()
        client.send_command.side_effect = Exception("SSM submit failed")
        adapter = SSMExecutionAdapter(client=client)

        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "failed")
        self.assertFalse(result.executed)
        self.assertIn("SSM submit failed", result.error_info)

    def test_live_ssm_adapter_marks_timeout_as_timed_out(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        incident.affected_instance = "i-1234567890abcdef0"
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        client = Mock()
        client.send_command.return_value = {"Command": {"CommandId": "cmd-123"}}
        client.get_command_invocation.return_value = {"Status": "InProgress"}
        adapter = SSMExecutionAdapter(client=client, wait_timeout_seconds=0)

        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "timed_out")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_handles_non_zero_exit_result(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        incident.affected_instance = "i-1234567890abcdef0"
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        client = Mock()
        client.send_command.return_value = {"Command": {"CommandId": "cmd-123"}}
        client.get_command_invocation.return_value = {
            "Status": "Failed",
            "StandardOutputContent": "",
            "StandardErrorContent": "Job failed",
            "ExitCode": 1,
        }

        adapter = SSMExecutionAdapter(client=client)
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.status, "failed")
        self.assertFalse(result.executed)

    def test_live_ssm_adapter_returns_structured_execution_result(self):
        from incident_intelligence.execution import SSMExecutionAdapter
        from incident_intelligence.remediation import RemediationApproval

        incident = analyze(snapshot([alert("InstanceDown")], [{"labels": {"instance": "10.0.11.132:9100"}, "health": "down", "lastError": "connect: connection refused"}]))[0]
        incident.affected_instance = "i-1234567890abcdef0"
        approval = RemediationApproval(action_id="restart_node_exporter", approved=True, approver="ops-lead", approval_reason="Approved")

        client = Mock()
        client.send_command.return_value = {"Command": {"CommandId": "cmd-123"}}
        client.get_command_invocation.return_value = {
            "Status": "Success",
            "StandardOutputContent": "active",
            "StandardErrorContent": "",
            "ExitCode": 0,
        }

        adapter = SSMExecutionAdapter(client=client)
        result = adapter.execute(action_id="restart_node_exporter", incident=incident, approval=approval, target_instance_id="i-1234567890abcdef0")
        self.assertEqual(result.incident_id, incident.incident_id)
        self.assertEqual(result.action, "restart_node_exporter")
        self.assertEqual(result.target_instance_id, "i-1234567890abcdef0")
        self.assertEqual(result.approver, "ops-lead")
        self.assertEqual(result.status, "success")
        self.assertTrue(result.executed)

    def test_verification_failure_prevents_closure(self):
        from incident_intelligence.remediation import verify_node_exporter_recovery, close_incident_if_verified

        verification = verify_node_exporter_recovery(
            exporter_health=False,
            prometheus_target_up=True,
            alert_cleared=True,
            alb_healthy=True,
            app_healthy=True,
        )
        self.assertEqual(verification.status, "failed")
        self.assertFalse(close_incident_if_verified(verification))

    def test_five_point_verification_allows_closure(self):
        from incident_intelligence.remediation import verify_node_exporter_recovery, close_incident_if_verified

        verification = verify_node_exporter_recovery(
            exporter_health=True,
            prometheus_target_up=True,
            alert_cleared=True,
            alb_healthy=True,
            app_healthy=True,
        )
        self.assertEqual(verification.status, "verified")
        self.assertTrue(close_incident_if_verified(verification))


if __name__ == "__main__":
    unittest.main()