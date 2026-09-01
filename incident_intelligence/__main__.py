"""CLI for read-only collection and incident analysis."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .collectors import collect
from .engine import analyze
from .model import SignalSnapshot
from .report import render


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only SRE incident intelligence analysis")
    parser.add_argument("--fixture", type=Path, help="JSON signal snapshot for deterministic analysis")
    parser.add_argument("--environment", default="dev")
    parser.add_argument("--prometheus-url", default="http://localhost:39090")
    parser.add_argument("--alertmanager-url", default="http://localhost:39093")
    parser.add_argument("--alb-dns-name")
    parser.add_argument("--target-group-arn")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of a human-readable report")
    args = parser.parse_args()
    if args.fixture:
        snapshot = SignalSnapshot(**json.loads(args.fixture.read_text()))
    elif args.alb_dns_name and args.target_group_arn:
        snapshot = collect(args.environment, args.prometheus_url, args.alertmanager_url, args.alb_dns_name, args.target_group_arn)
    else:
        parser.error("provide --fixture or both --alb-dns-name and --target-group-arn")
    incidents = analyze(snapshot)
    if args.json:
        print(json.dumps([incident.to_dict() for incident in incidents], indent=2))
    else:
        print("\n\n".join(render(incident) for incident in incidents) or "No active incidents detected.")


if __name__ == "__main__":
    main()