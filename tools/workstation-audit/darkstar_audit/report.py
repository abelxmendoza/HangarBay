"""Render audit.json and audit.md from the same findings object.

Both outputs are generated from the single dict produced by
evaluate.evaluate() (+ probe/profile metadata added by the CLI), so the
machine-readable evidence and the human-readable report can never drift
apart (phase1-spec.md §6, Decision 2).
"""

from __future__ import annotations

import json

_STATE_GLYPH = {True: "yes", False: "no", None: "not assessed"}


def to_json(report):
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def _fmt_evidence_value(value):
    if value is None:
        return "—"
    if isinstance(value, (list, tuple)):
        return ", ".join(str(v) for v in value) if value else "—"
    if isinstance(value, dict):
        return "; ".join("%s: %s" % (k, _fmt_evidence_value(v)) for k, v in value.items())
    return str(value)


def to_markdown(report):
    stack = report["target_stack"]
    summary = report["summary"]
    lines = []
    lines.append("# Darkstar Robotics — Phase 1 Workstation Audit")
    lines.append("")
    lines.append("Generated: %s" % report.get("generated_at", "unknown"))
    lines.append("")
    lines.append("Target stack: **%s** (Ubuntu %s · ROS 2 %s · Gazebo %s · "
                 "disk floor %s GB free)"
                 % (stack["name"], stack["os_release"], stack["ros_distro"],
                    stack["gazebo_flavor"], stack["disk_free_gb_min"]))
    lines.append("")
    lines.append("This report was produced by read-only probes. Nothing was "
                 "installed, modified, or started by the audit. Statuses carry "
                 "their evidence: a claim is only as strong as the probe behind it.")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    counts = summary["findings_by_status"]
    lines.append("Findings by status: " +
                 ", ".join("%s × %d" % (k, counts[k]) for k in sorted(counts)))
    lines.append("")
    lines.append("- **Workstation readiness** (is the audit itself functioning): "
                 "%s — %s" % (summary["workstation_readiness"]["status"],
                              summary["workstation_readiness"]["detail"]))
    lines.append("- **Stack readiness** (this machine vs. the *selected* stack): "
                 "%s — %s" % (summary["stack_readiness"]["status"],
                              summary["stack_readiness"]["detail"]))
    lines.append("")
    lines.append("An absent *optional* item never degrades readiness; it appears "
                 "above only as information.")
    lines.append("")
    lines.append("## Findings")
    lines.append("")
    lines.append("| Check | Role | Status |")
    lines.append("|---|---|---|")
    for f in report["findings"]:
        lines.append("| %s | %s | **%s** |" % (f["name"], f["role"], f["status"]))
    lines.append("")
    for f in report["findings"]:
        lines.append("### %s — %s" % (f["name"], f["status"]))
        lines.append("")
        st = f["states"]
        lines.append("States: installed=%s · configured=%s · compatible=%s · operational=%s"
                     % (_STATE_GLYPH[st["installed"]], _STATE_GLYPH[st["configured"]],
                        _STATE_GLYPH[st["compatible"]], _STATE_GLYPH[st["operational"]]))
        if f.get("assessment") and f["assessment"] != "complete":
            lines.append("")
            lines.append("Assessment: %s" % f["assessment"].replace("_", " "))
        lines.append("")
        lines.append("Why:")
        for reason in f["reasons"]:
            lines.append("- %s" % reason)
        if f.get("recommendation"):
            lines.append("")
            lines.append("Recommended action: %s" % f["recommendation"])
        lines.append("")
        lines.append("Evidence:")
        for key in sorted(f["evidence"]):
            lines.append("- %s: %s" % (key, _fmt_evidence_value(f["evidence"][key])))
        lines.append("")
    lines.append("## Status meanings")
    lines.append("")
    lines.append("- **READY** — installed + configured + compatible + operational, "
                 "each backed by probe evidence. Never granted for a binary alone.")
    lines.append("- **MISCONFIGURED** — installed and version-compatible, but a "
                 "configuration check failed (or a system requirement, e.g. the "
                 "disk floor, is not met).")
    lines.append("- **INCOMPATIBLE** — installed, but its version conflicts with "
                 "the stack or another member (e.g. ROS 2 Humble on Ubuntu 24.04).")
    lines.append("- **NOT INSTALLED** — detection found nothing; the methods tried "
                 "are listed in the evidence.")
    lines.append("- **UNKNOWN** — the inspection could not determine the state "
                 "(includes *not assessed*: e.g. a simulator's operational state, "
                 "which Phase 1 v1 deliberately does not probe).")
    lines.append("")
    return "\n".join(lines)
