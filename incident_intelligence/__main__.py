"""CLI for read-only collection and incident analysis."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .collectors import collect
from .engine import analyze
from .model import SignalSnapshot
from .remediation import RemediationApproval, execute_human_approved_remediation
from .report import render


def _print_incident_summary(incident):
    print(f"Incident: {incident.incident_id}")
    print(f"Category: {incident.root_cause.get('category')}")
    print(f"Affected component: {incident.affected_resource}")
    print(f"Recommended remediation: {incident.recommended_action.get('action')}")
    print(f"Risk: {incident.recommended_action.get('risk')}")
    print("Human approval is required before execution.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only SRE incident intelligence analysis")
    parser.add_argument("--fixture", type=Path, help="JSON signal snapshot for deterministic analysis")
    parser.add_argument("--environment", default="dev")
    parser.add_argument("--prometheus-url", default="http://localhost:39090")
    parser.add_argument("--alertmanager-url", default="http://localhost:39093")
    parser.add_argument("--alb-dns-name")
    parser.add_argument("--target-group-arn")
    parser.add_argument("--approve-action", choices=["restart_node_exporter"], help="Explicit human approval for the allowlisted remediation action")
    parser.add_argument("--approver", help="Human approver identity required when --approve-action is supplied")
    parser.add_argument("--approval-reason", help="Human approval rationale required when --approve-action is supplied")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of a human-readable report")
    args = parser.parse_args()
    if args.fixture:
        snapshot = SignalSnapshot(**json.loads(args.fixture.read_text()))
    elif args.alb_dns_name and args.target_group_arn:
        snapshot = collect(args.environment, args.prometheus_url, args.alertmanager_url, args.alb_dns_name, args.target_group_arn)
    else:
        parser.error("provide --fixture or both --alb-dns-name and --target-group-arn")
    incidents = analyze(snapshot)
    if not incidents:
        print("No active incidents detected.")
        return

    if args.json:
        payload = []
        for incident in incidents:
            payload.append(incident.to_dict())
        print(json.dumps(payload, indent=2))
        if args.approve_action:
            if not args.approver or not args.approval_reason:
                parser.error("--approver and --approval-reason are required when using --approve-action")
            approval = RemediationApproval(action_id=args.approve_action, approved=True, approver=args.approver, approval_reason=args.approval_reason)
            result = execute_human_approved_remediation(incidents[0], approval, dry_run=True)
            print(json.dumps({"approval": approval.__dict__, "execution": result.__dict__}, indent=2))
        return

    for incident in incidents:
        print("\n\n".join(render(incident) for incident in incidents) or "No active incidents detected.")
        _print_incident_summary(incident)
        if args.approve_action:
            if not args.approver or not args.approval_reason:
                parser.error("--approver and --approval-reason are required when using --approve-action")
            approval = RemediationApproval(action_id=args.approve_action, approved=True, approver=args.approver, approval_reason=args.approval_reason)
            result = execute_human_approved_remediation(incident, approval, dry_run=True)
            print(f"Approval validation: {approval.validate() or 'valid'}")
            print(f"Execution status: {result.status}")
            print(f"Executed: {result.executed}")
            if result.notes:
                print(f"Notes: {result.notes}")
            break


if __name__ == "__main__":
    main()

if __name__ == "__main__":
    main()