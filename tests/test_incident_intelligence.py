import unittest

from incident_intelligence.engine import analyze
from incident_intelligence.model import SignalSnapshot


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


if __name__ == "__main__":
    unittest.main()