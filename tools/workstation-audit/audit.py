#!/usr/bin/env python3
"""Darkstar Robotics — Phase 1 read-only workstation audit (entry point).

Usage:
    python3 audit.py --out-dir ./audit-output [--disk-path /]

Writes audit.json and audit.md into --out-dir. Read-only: the audit
never installs, modifies, or configures anything, needs no sudo, and
works offline. Exit code is 0 whenever the audit itself ran — findings
are a report, not a pass/fail gate.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from darkstar_audit import __version__  # noqa: E402
from darkstar_audit import evaluate as evaluate_mod  # noqa: E402
from darkstar_audit import probes, report as report_mod  # noqa: E402


def build_report(disk_path="/"):
    profile = probes.collect_profile(disk_path=disk_path)
    result = evaluate_mod.evaluate(profile)
    return {
        "schema_version": 1,
        "tool": {"name": "Darkstar Robotics Phase 1 Workstation Audit",
                 "version": __version__},
        "generated_at": datetime.datetime.now(datetime.timezone.utc)
                        .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "machine_profile": {
            "os": profile["os"],
            "architecture": profile["architecture"],
            "disk": profile["disk"],
        },
        "target_stack": result["target_stack"],
        "findings": result["findings"],
        "summary": result["summary"],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Darkstar Robotics Phase 1 read-only workstation audit")
    parser.add_argument("--out-dir", required=True,
                        help="directory to write audit.json and audit.md into")
    parser.add_argument("--disk-path", default="/",
                        help="filesystem to measure free disk space on (default: /)")
    args = parser.parse_args(argv)

    report = build_report(disk_path=args.disk_path)

    os.makedirs(args.out_dir, exist_ok=True)
    json_path = os.path.join(args.out_dir, "audit.json")
    md_path = os.path.join(args.out_dir, "audit.md")
    with open(json_path, "w", encoding="utf-8") as fh:
        fh.write(report_mod.to_json(report))
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(report_mod.to_markdown(report))

    print("Darkstar Robotics workstation audit — target stack: %s"
          % report["target_stack"]["name"])
    for f in report["findings"]:
        print("  %-16s %-14s (%s)" % (f["name"], f["status"], f["role"]))
    print("Stack readiness: %s" % report["summary"]["stack_readiness"]["status"])
    print("Wrote %s and %s" % (json_path, md_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
