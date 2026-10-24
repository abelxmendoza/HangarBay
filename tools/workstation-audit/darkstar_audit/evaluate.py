"""Pure evaluation: MachineProfile -> findings.

Implements the spec's four-state model (installed / configured /
compatible / operational, tracked separately) and five statuses
(READY / MISCONFIGURED / INCOMPATIBLE / NOT INSTALLED / UNKNOWN).

Hard rules enforced here:
- READY is never granted from an executable's presence alone; it needs
  configured + compatible + operational evidence.
- No simulator smoke tests exist in this implementation, so a
  simulator's operational state is *not assessed* (None) and it can
  never be READY here — that is stated in its reasons, not hidden.
- An absent optional tool never appears in the stack's blockers.
- A probe that could not decide yields UNKNOWN, never a guess.
"""

from __future__ import annotations

from . import rules

READY = "READY"
MISCONFIGURED = "MISCONFIGURED"
INCOMPATIBLE = "INCOMPATIBLE"
NOT_INSTALLED = "NOT INSTALLED"
UNKNOWN = "UNKNOWN"


def _finding(check_id, name, status, states, evidence, reasons, recommendation=None):
    return {
        "id": check_id,
        "name": name,
        "role": rules.ROLES[check_id],
        "status": status,
        "states": states,  # installed/configured/compatible/operational: True|False|None
        "evidence": evidence,
        "reasons": reasons,
        "recommendation": recommendation,
    }


def _states(installed=None, configured=None, compatible=None, operational=None):
    return {"installed": installed, "configured": configured,
            "compatible": compatible, "operational": operational}


def evaluate_os(profile, stack):
    p = profile.get("os") or {}
    ev = {"source": p.get("source"), "observed_id": p.get("id"),
          "observed_version_id": p.get("version_id"),
          "observed_pretty_name": p.get("pretty_name"),
          "expected": "%s %s" % (stack["os_id"], stack["os_release"])}
    if p.get("error") or not p.get("id") or not p.get("version_id"):
        return _finding("os", "Operating system", UNKNOWN, _states(),
                        {**ev, "probe_error": p.get("error")},
                        ["OS could not be determined: %s" % (p.get("error") or "os-release fields missing")])
    if p["id"] == stack["os_id"] and p["version_id"] == stack["os_release"]:
        return _finding("os", "Operating system", READY,
                        _states(True, True, True, True), ev,
                        ["%s matches the %s stack target; observed directly from %s."
                         % (p.get("pretty_name") or p["version_id"], stack["name"], p.get("source"))])
    paired = rules.ROS_UBUNTU_PAIRING.get(stack["ros_distro"])
    return _finding("os", "Operating system", INCOMPATIBLE,
                    _states(True, True, False, True), ev,
                    ["Stack targets Ubuntu %s (ROS 2 %s pairs with Ubuntu %s), but this machine runs %s %s."
                     % (stack["os_release"], stack["ros_distro"], paired,
                        p["id"], p["version_id"])],
                    "Use a %s %s workstation for this stack, or select a stack built for %s %s."
                    % (stack["os_id"], stack["os_release"], p["id"], p["version_id"]))


def evaluate_architecture(profile, stack):
    p = profile.get("architecture") or {}
    machine = p.get("machine")
    ev = {"source": p.get("source"), "observed": machine,
          "supported": sorted(rules.SUPPORTED_ARCHES)}
    if p.get("error") or not machine:
        return _finding("architecture", "CPU architecture", UNKNOWN, _states(),
                        {**ev, "probe_error": p.get("error")},
                        ["Architecture could not be determined."])
    if machine in rules.SUPPORTED_ARCHES:
        return _finding("architecture", "CPU architecture", READY,
                        _states(True, True, True, True), ev,
                        ["Architecture %s is a supported target for the stack." % machine])
    return _finding("architecture", "CPU architecture", INCOMPATIBLE,
                    _states(True, True, False, True), ev,
                    ["Architecture %s is not among the stack's targets (%s)."
                     % (machine, ", ".join(sorted(rules.SUPPORTED_ARCHES)))])


def evaluate_disk(profile, stack):
    p = profile.get("disk") or {}
    floor = stack["disk_free_gb_min"]
    ev = {"source": p.get("source"), "path": p.get("path"),
          "free_gb": p.get("free_gb"), "total_gb": p.get("total_gb"),
          "floor_gb": floor}
    if p.get("error") or p.get("free_gb") is None:
        return _finding("disk_space", "Disk space", UNKNOWN, _states(),
                        {**ev, "probe_error": p.get("error")},
                        ["Free disk space could not be determined: %s" % p.get("error")])
    if p["free_gb"] >= floor:
        return _finding("disk_space", "Disk space", READY,
                        _states(True, True, True, True), ev,
                        ["%.1f GB free, above the %d GB stack-policy floor."
                         % (p["free_gb"], floor)])
    return _finding("disk_space", "Disk space", MISCONFIGURED,
                    _states(True, True, False, None), ev,
                    ["Only %.1f GB free on %s, below the %d GB stack-policy floor for %s. "
                     "The stack's tools and build artifacts will not fit reliably."
                     % (p["free_gb"], p.get("path"), floor, stack["name"])],
                    "Free or expand disk space to at least %d GB free before setting up this stack." % floor)


def evaluate_ros2(profile, stack):
    p = profile.get("ros2") or {}
    installed = p.get("installed") or []
    ev = {"root": p.get("root"), "methods_tried": p.get("methods_tried"),
          "installed_distros": [i.get("distro") for i in installed],
          "env_ros_distro": p.get("env_ros_distro")}
    if p.get("error"):
        return _finding("ros2", "ROS 2", UNKNOWN, _states(),
                        {**ev, "probe_error": p["error"]},
                        ["ROS 2 detection could not complete: %s" % p["error"]])
    if not installed:
        return _finding("ros2", "ROS 2", NOT_INSTALLED, _states(False, False, None, False),
                        ev,
                        ["No ROS 2 installation found. Tried: %s."
                         % "; ".join(p.get("methods_tried") or [])],
                        "Install ROS 2 %s for this stack (see README for the official instructions link)."
                        % stack["ros_distro"])
    # Primary distro: the one the environment names, else the stack's
    # target if present, else the first installed (deterministic).
    by_distro = {i["distro"]: i for i in installed}
    primary_name = None
    for candidate in (p.get("env_ros_distro"), stack["ros_distro"]):
        if candidate in by_distro:
            primary_name = candidate
            break
    if primary_name is None:
        primary_name = sorted(by_distro)[0]
    item = by_distro[primary_name]
    ev.update({"primary_distro": primary_name, "install_path": item.get("path"),
               "setup_bash": item.get("setup_bash"),
               "other_distros_present": sorted(d for d in by_distro if d != primary_name)})
    expected_ubuntu = rules.ROS_UBUNTU_PAIRING.get(primary_name)
    os_version = (profile.get("os") or {}).get("version_id")
    if expected_ubuntu is None:
        return _finding("ros2", "ROS 2", UNKNOWN, _states(True, None, None, None), ev,
                        ["ROS 2 %s is installed, but this audit has no pairing rule for that distro, "
                         "so compatibility cannot be determined." % primary_name])
    if os_version is not None and expected_ubuntu != os_version:
        return _finding("ros2", "ROS 2", INCOMPATIBLE,
                        _states(True, None, False, None), ev,
                        ["ROS 2 %s pairs with Ubuntu %s, but this machine runs Ubuntu %s. "
                         "This is a version-pairing conflict, not a missing install."
                         % (primary_name, expected_ubuntu, os_version)],
                        "Use ROS 2 %s on Ubuntu %s, or move this stack to an Ubuntu %s machine."
                        % (stack["ros_distro"], os_version, expected_ubuntu))
    if primary_name != stack["ros_distro"]:
        return _finding("ros2", "ROS 2", INCOMPATIBLE,
                        _states(True, None, False, None), ev,
                        ["The stack requires ROS 2 %s; the detected primary distro is %s."
                         % (stack["ros_distro"], primary_name)])
    # Compatible pairing. Configured = sourcing setup.bash yields the
    # right environment (the spec's config probe, §3).
    sourced = item.get("sourced") or {}
    ev["ros_distro_after_source"] = sourced.get("ros_distro_after_source")
    ev["ament_prefix_path_after_source"] = sourced.get("ament_prefix_path")
    configured = bool(item.get("setup_bash")) and sourced.get("ros_distro_after_source") == primary_name \
        and bool(sourced.get("ament_prefix_path")) and ("/opt/ros/%s" % primary_name) in (sourced.get("ament_prefix_path") or "")
    if not item.get("setup_bash"):
        return _finding("ros2", "ROS 2", MISCONFIGURED,
                        _states(True, False, True, None), ev,
                        ["ROS 2 %s directory exists at %s but setup.bash is missing — "
                         "the installation looks incomplete." % (primary_name, item.get("path"))])
    if not configured:
        return _finding("ros2", "ROS 2", MISCONFIGURED,
                        _states(True, False, True, None), ev,
                        ["ROS 2 %s is installed and pairs correctly, but sourcing setup.bash did not "
                         "produce a matching ROS_DISTRO/AMENT_PREFIX_PATH (observed ROS_DISTRO=%r). "
                         "Installed is not the same as configured."
                         % (primary_name, sourced.get("ros_distro_after_source"))])
    # Operational = the spec's ROS preflight probe actually ran clean.
    fp = sourced.get("functional_probe") or {}
    ev["functional_probe"] = fp
    if not fp.get("ran"):
        return _finding("ros2", "ROS 2", UNKNOWN,
                        _states(True, True, True, None), ev,
                        ["ROS 2 %s is installed, compatible, and configured, but the operational probe "
                         "(%s) could not be completed: %s. READY is not claimed without it."
                         % (primary_name, fp.get("command"), fp.get("detail"))])
    if not fp.get("ok"):
        return _finding("ros2", "ROS 2", MISCONFIGURED,
                        _states(True, True, True, False), ev,
                        ["ROS 2 %s is installed and configured, but its operational probe failed (%s: %s)."
                         % (primary_name, fp.get("command"), fp.get("detail"))])
    return _finding("ros2", "ROS 2", READY,
                    _states(True, True, True, True), ev,
                    ["ROS 2 %s installed at %s, pairs with Ubuntu %s, sources to a correct environment, "
                     "and `ros2 doctor --report` ran successfully in that environment."
                     % (primary_name, item.get("path"), os_version)])


def evaluate_gazebo(profile, stack):
    p = profile.get("gazebo") or {}
    ros = profile.get("ros2") or {}
    installed_ros = [i.get("distro") for i in (ros.get("installed") or [])]
    ev = {"methods_tried": p.get("methods_tried"), "gz_path": p.get("gz_path"),
          "legacy_path": p.get("legacy_path"), "version_raw": p.get("version_raw"),
          "version": p.get("version")}
    if p.get("error"):
        return _finding("gazebo", "Gazebo", UNKNOWN, _states(),
                        {**ev, "probe_error": p["error"]},
                        ["Gazebo detection could not complete: %s" % p["error"]])
    if not p.get("gz_path") and not p.get("legacy_path"):
        return _finding("gazebo", "Gazebo", NOT_INSTALLED, _states(False, False, None, False),
                        ev,
                        ["No Gazebo installation found. Tried: %s."
                         % "; ".join(p.get("methods_tried") or [])],
                        "Install Gazebo %s for this stack (see README for the official instructions link)."
                        % stack["gazebo_flavor"])
    if not p.get("version"):
        return _finding("gazebo", "Gazebo", UNKNOWN, _states(True, None, None, None), ev,
                        ["A Gazebo binary is present but its version could not be parsed from %r, "
                         "so its flavour and pairing cannot be determined." % p.get("version_raw")])
    major = p["version"][0]
    flavor = rules.GAZEBO_MAJOR_TO_FLAVOR.get(major, "unknown")
    ev["flavor"] = flavor
    ev["version_string"] = ".".join(str(v) for v in p["version"])
    paired_ros = rules.GAZEBO_ROS_PAIRING.get(flavor)
    if flavor == "classic" or paired_ros is None:
        return _finding("gazebo", "Gazebo", INCOMPATIBLE,
                        _states(True, None, False, None), ev,
                        ["Gazebo %s (%s) has no supported pairing with ROS 2 %s in this stack; "
                         "the stack requires Gazebo %s."
                         % (ev["version_string"], flavor, stack["ros_distro"], stack["gazebo_flavor"])])
    if paired_ros != stack["ros_distro"] or flavor != stack["gazebo_flavor"]:
        return _finding("gazebo", "Gazebo", INCOMPATIBLE,
                        _states(True, None, False, None), ev,
                        ["Gazebo %s pairs with ROS 2 %s, but this stack requires Gazebo %s with ROS 2 %s. "
                         "Both can 'work' individually and still be a wrong pairing."
                         % (flavor, paired_ros, stack["gazebo_flavor"], stack["ros_distro"])])
    if installed_ros and stack["ros_distro"] not in installed_ros:
        return _finding("gazebo", "Gazebo", INCOMPATIBLE,
                        _states(True, None, False, None), ev,
                        ["Gazebo %s is the right flavour for ROS 2 %s, but the ROS 2 found on this "
                         "machine is %s, so the pair as installed does not match the stack."
                         % (flavor, stack["ros_distro"], ", ".join(installed_ros))])
    # Installed + right flavour + right pairing. Operational state is
    # NOT assessed in Phase 1 v1: the only honest operational evidence
    # for a simulator is a headless smoke run, which this implementation
    # deliberately does not execute. So READY cannot be claimed.
    return _finding("gazebo", "Gazebo", UNKNOWN,
                    _states(True, True, True, None), ev,
                    ["Gazebo %s (%s) is installed and pairs correctly with ROS 2 %s. "
                     "Its operational state is not assessed in Phase 1 v1 — simulator smoke tests "
                     "are out of scope, and READY is never claimed from a binary's presence alone, "
                     "so this check stays UNKNOWN (not-assessed), not READY."
                     % (ev["version_string"], flavor, stack["ros_distro"])])


def evaluate_docker(profile, stack):
    p = profile.get("docker") or {}
    ev = {"methods_tried": p.get("methods_tried"), "cli_path": p.get("cli_path"),
          "cli_version_raw": p.get("cli_version_raw"),
          "daemon_server_version": p.get("daemon_server_version")}
    if p.get("error"):
        return _finding("docker", "Docker", UNKNOWN, _states(),
                        {**ev, "probe_error": p["error"]},
                        ["Docker detection could not complete: %s" % p["error"]])
    if not p.get("cli_path"):
        return _finding("docker", "Docker", NOT_INSTALLED, _states(False, False, None, False),
                        ev,
                        ["Docker CLI not found on PATH. Docker is optional for this stack, "
                         "so this is information, not a problem."])
    if p.get("daemon_reachable") is None:
        return _finding("docker", "Docker", UNKNOWN,
                        _states(True, None, True, None),
                        {**ev, "daemon_error": p.get("daemon_error")},
                        ["Docker CLI is present (%s) but daemon reachability could not be determined: %s"
                         % (p.get("cli_version_raw"), p.get("daemon_error"))])
    if p.get("daemon_reachable") is False:
        return _finding("docker", "Docker", MISCONFIGURED,
                        _states(True, False, True, False),
                        {**ev, "daemon_error": p.get("daemon_error")},
                        ["Docker CLI is present (%s) but the daemon is not reachable (%s). "
                         "A CLI alone is not a working Docker — this is the classic false READY."
                         % (p.get("cli_version_raw"), p.get("daemon_error"))],
                        "Start the Docker daemon (or check group/socket permissions), then re-run the audit.")
    return _finding("docker", "Docker", READY,
                    _states(True, True, True, True), ev,
                    ["Docker CLI present (%s) and the daemon answered `docker info` "
                     "(server %s). Daemon reachability is Docker's operational evidence; "
                     "the Phase 1 stack sets no Docker version constraint."
                     % (p.get("cli_version_raw"), p.get("daemon_server_version"))])


def evaluate(profile, stack=None):
    """Return the full findings object (shared by JSON + Markdown reports)."""
    stack = dict(rules.TARGET_STACK if stack is None else stack)
    findings = [
        evaluate_os(profile, stack),
        evaluate_architecture(profile, stack),
        evaluate_disk(profile, stack),
        evaluate_ros2(profile, stack),
        evaluate_gazebo(profile, stack),
        evaluate_docker(profile, stack),
    ]
    # Assessment bookkeeping, kept explicit so the summary never conflates
    # two different UNKNOWNs: "inconclusive" (a probe could not decide —
    # that reflects on the audit/Core) vs "not_assessed" (a state this
    # implementation deliberately does not probe, e.g. a simulator's
    # operational state — that reflects on the tool's evidence, not on
    # Core). Currently the only not_assessed path is a compatible Gazebo
    # whose operational check is out of scope by design.
    for f in findings:
        if f["status"] != UNKNOWN:
            f["assessment"] = "complete"
        elif f["id"] == "gazebo" and f["states"]["installed"] and f["states"]["compatible"]:
            f["assessment"] = "not_assessed"
        else:
            f["assessment"] = "inconclusive"
    by_status = {}
    for f in findings:
        by_status[f["status"]] = by_status.get(f["status"], 0) + 1
    blockers = [f["id"] for f in findings
                if f["role"] == "required" and f["status"] != READY]
    optional_notes = [f["id"] for f in findings
                      if f["role"] == "optional" and f["status"] != READY]
    inconclusive = [f["id"] for f in findings if f.get("assessment") == "inconclusive"]
    not_assessed = [f["id"] for f in findings if f.get("assessment") == "not_assessed"]
    return {
        "target_stack": stack,
        "findings": findings,
        "summary": {
            "findings_by_status": by_status,
            # Workstation readiness is about Darkstar Core itself: the
            # inspector ran and every probe executed (spec §1). Tool
            # absence does not degrade it.
            "workstation_readiness": {
                "status": READY if not inconclusive else UNKNOWN,
                "detail": ("The audit itself ran and all probes produced a determination."
                           + (" Not assessed by design in this version: %s."
                              % ", ".join(not_assessed) if not_assessed else "")
                           if not inconclusive else
                           "The audit ran, but these probes were inconclusive: %s."
                           % ", ".join(inconclusive)),
            },
            "stack_readiness": {
                "status": READY if not blockers else "NOT READY",
                "blockers": blockers,
                "optional_not_ready": optional_notes,
                "detail": ("All required checks for %s are READY." % stack["name"]
                           if not blockers else
                           "Required checks not READY: %s. Optional items never block: %s."
                           % (", ".join(blockers), ", ".join(optional_notes) or "none")),
            },
        },
    }
