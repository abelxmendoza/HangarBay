"""Read-only probes that build a MachineProfile (raw evidence only).

Design rules (phase1-spec.md §4):
- Presence -> version -> config probes only. NO simulator smoke tests in
  this implementation, and nothing here installs, writes, or changes any
  system state. The only commands executed are read-only queries
  (version strings, `docker info`, and -- inside a throwaway subshell --
  sourcing a ROS setup file and running `ros2 doctor --report`, the
  operational probe the spec names for ROS 2).
- Every probe records what it tried and what it observed. A probe that
  cannot decide records an error string instead of guessing; evaluation
  turns that into UNKNOWN.
- All subprocess calls are time-boxed and use shell=False (except the
  single documented `bash -c` ROS sourcing probe, whose arguments are
  built only from distro names found on disk, never from user input).
"""

from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess

PROBE_TIMEOUT_S = 10
ROS_PROBE_TIMEOUT_S = 25


def _run(argv, timeout=PROBE_TIMEOUT_S):
    """Run a read-only command; return (exit_code|None, stdout, stderr, error)."""
    try:
        proc = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, shell=False
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip(), None
    except FileNotFoundError:
        return None, "", "", "not found: %s" % argv[0]
    except subprocess.TimeoutExpired:
        return None, "", "", "timeout after %ss: %s" % (timeout, " ".join(argv))
    except OSError as exc:  # e.g. permission errors executing the binary
        return None, "", "", "os error running %s: %s" % (argv[0], exc)


def parse_os_release(text):
    """Parse /etc/os-release content into a dict (values unquoted)."""
    data = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def probe_os(path="/etc/os-release"):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            data = parse_os_release(fh.read())
        return {
            "id": data.get("ID"),
            "version_id": data.get("VERSION_ID"),
            "pretty_name": data.get("PRETTY_NAME"),
            "source": path,
            "error": None,
        }
    except OSError as exc:
        return {
            "id": None,
            "version_id": None,
            "pretty_name": None,
            "source": path,
            "error": "cannot read %s: %s" % (path, exc),
        }


def probe_architecture():
    return {"machine": platform.machine(), "source": "platform.machine()", "error": None}


def probe_disk(path="/"):
    try:
        usage = shutil.disk_usage(path)
        return {
            "path": path,
            "total_gb": round(usage.total / 1e9, 2),
            "free_gb": round(usage.free / 1e9, 2),
            "source": "shutil.disk_usage(%r)" % path,
            "error": None,
        }
    except OSError as exc:
        return {"path": path, "total_gb": None, "free_gb": None,
                "source": "shutil.disk_usage(%r)" % path,
                "error": "disk_usage failed: %s" % exc}


# Distro directory names under /opt/ros are the primary ROS evidence.
_SAFE_DISTRO = re.compile(r"^[a-z0-9_]+$")


def _ros_sourced_probe(distro):
    """Config + functional evidence for one installed ROS distro.

    Sources the distro's setup.bash inside a throwaway bash subshell (the
    audit process and the system are untouched), then reports the
    resulting ROS_DISTRO / AMENT_PREFIX_PATH and whether the spec's
    operational probe, `ros2 doctor --report`, ran successfully there.
    """
    setup = "/opt/ros/%s/setup.bash" % distro
    script = (
        "source %s >/dev/null 2>&1; "
        "printf 'ROS_DISTRO=%%s\\nAMENT=%%s\\n' \"$ROS_DISTRO\" \"$AMENT_PREFIX_PATH\"; "
        "ros2 doctor --report >/dev/null 2>&1; printf 'DOCTOR_EXIT=%%s\\n' \"$?\""
    ) % setup
    code, out, _err, error = _run(["bash", "-c", script], timeout=ROS_PROBE_TIMEOUT_S)
    result = {"ros_distro_after_source": None, "ament_prefix_path": None,
              "functional_probe": {"command": "ros2 doctor --report (after sourcing %s)" % setup,
                                   "ran": False, "ok": None, "detail": None}}
    if error is not None:
        result["functional_probe"]["detail"] = error
        return result
    for line in out.splitlines():
        if line.startswith("ROS_DISTRO="):
            result["ros_distro_after_source"] = line.partition("=")[2] or None
        elif line.startswith("AMENT="):
            result["ament_prefix_path"] = line.partition("=")[2] or None
        elif line.startswith("DOCTOR_EXIT="):
            result["functional_probe"]["ran"] = True
            result["functional_probe"]["ok"] = line.partition("=")[2] == "0"
            result["functional_probe"]["detail"] = "exit code %s" % line.partition("=")[2]
    if code is None:
        result["functional_probe"]["detail"] = "sourcing probe did not complete"
    return result


def probe_ros(ros_root="/opt/ros", environ=None):
    environ = os.environ if environ is None else environ
    evidence = {
        "root": ros_root,
        "installed": [],  # [{distro, setup_bash, sourced:{...}}]
        "env_ros_distro": environ.get("ROS_DISTRO"),
        "env_ament_prefix_path": environ.get("AMENT_PREFIX_PATH"),
        "methods_tried": ["list %s/<distro> directories" % ros_root,
                          "check <distro>/setup.bash exists",
                          "source setup.bash in a subshell; check ROS_DISTRO/AMENT_PREFIX_PATH",
                          "run 'ros2 doctor --report' in that subshell"],
        "error": None,
    }
    try:
        entries = sorted(os.listdir(ros_root))
    except FileNotFoundError:
        return evidence  # no /opt/ros at all: nothing installed, not an error
    except OSError as exc:
        evidence["error"] = "cannot list %s: %s" % (ros_root, exc)
        return evidence
    for name in entries:
        full = os.path.join(ros_root, name)
        if not os.path.isdir(full) or not _SAFE_DISTRO.match(name):
            continue
        setup = os.path.join(full, "setup.bash")
        item = {"distro": name, "path": full, "setup_bash": os.path.isfile(setup)}
        if item["setup_bash"]:
            item["sourced"] = _ros_sourced_probe(name)
        evidence["installed"].append(item)
    return evidence


_GZ_SIM_VERSION = re.compile(r"version[:\s]+(\d+)\.(\d+)(?:\.(\d+))?", re.IGNORECASE)


def parse_version(text):
    """Extract an (major, minor, patch) tuple from version output, or None."""
    if not text:
        return None
    m = _GZ_SIM_VERSION.search(text)
    if not m:
        m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text)
    if not m:
        return None
    return tuple(int(g) if g is not None else 0 for g in m.groups())


def probe_gazebo():
    evidence = {"gz_path": shutil.which("gz"), "legacy_path": shutil.which("gazebo"),
                "version_raw": None, "version": None,
                "methods_tried": [], "error": None}
    argv = None
    if evidence["gz_path"]:
        argv = ["gz", "sim", "--version"]
    elif evidence["legacy_path"]:
        argv = ["gazebo", "--version"]
    if argv is None:
        evidence["methods_tried"] = ["PATH lookup for 'gz'", "PATH lookup for 'gazebo'"]
        return evidence
    evidence["methods_tried"] = ["PATH lookup for 'gz'/'gazebo'", "%s" % " ".join(argv)]
    code, out, err, error = _run(argv)
    if error is not None:
        evidence["error"] = error
        return evidence
    evidence["version_raw"] = out or err
    parsed = parse_version(evidence["version_raw"])
    if parsed is not None:
        evidence["version"] = list(parsed)
    return evidence


def probe_docker():
    evidence = {"cli_path": shutil.which("docker"), "cli_version_raw": None,
                "cli_version": None, "daemon_reachable": None,
                "daemon_server_version": None, "daemon_error": None,
                "methods_tried": ["PATH lookup for 'docker'", "docker --version",
                                  "docker info --format {{.ServerVersion}}"],
                "error": None}
    if evidence["cli_path"] is None:
        return evidence
    code, out, err, error = _run(["docker", "--version"])
    if error is not None:
        evidence["error"] = error
        return evidence
    evidence["cli_version_raw"] = out or err
    parsed = parse_version(evidence["cli_version_raw"])
    if parsed is not None:
        evidence["cli_version"] = list(parsed)
    # Daemon reachability is a separate fact from CLI presence (spec §3:
    # "CLI alone is the classic false READY").
    code, out, err, error = _run(["docker", "info", "--format", "{{.ServerVersion}}"])
    if error is not None:
        evidence["daemon_error"] = error  # e.g. timeout: cannot decide
        return evidence
    if code == 0 and out:
        evidence["daemon_reachable"] = True
        evidence["daemon_server_version"] = out
    else:
        evidence["daemon_reachable"] = False
        evidence["daemon_error"] = (err or out or "docker info exited %s" % code)[:300]
    return evidence


def collect_profile(disk_path="/"):
    """Run every probe and return the raw MachineProfile dict."""
    return {
        "os": probe_os(),
        "architecture": probe_architecture(),
        "disk": probe_disk(disk_path),
        "ros2": probe_ros(),
        "gazebo": probe_gazebo(),
        "docker": probe_docker(),
    }
