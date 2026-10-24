"""Unit tests for the Darkstar Robotics Phase 1 workstation audit.

Evaluation is a pure function of a MachineProfile dict, so fixtures are
plain dicts — no real machine, root, or network needed.

Run from tools/workstation-audit/:
    python3 -m unittest discover -s tests -v
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from darkstar_audit import evaluate as ev  # noqa: E402
from darkstar_audit import probes, report as report_mod  # noqa: E402


def base_profile():
    """A healthy Ubuntu 24.04 machine with Jazzy + Harmonic + Docker up."""
    return {
        "os": {"id": "ubuntu", "version_id": "24.04",
               "pretty_name": "Ubuntu 24.04.3 LTS", "source": "/etc/os-release",
               "error": None},
        "architecture": {"machine": "aarch64", "source": "platform.machine()",
                         "error": None},
        "disk": {"path": "/", "total_gb": 100.0, "free_gb": 60.0,
                 "source": "shutil.disk_usage('/')", "error": None},
        "ros2": {"root": "/opt/ros",
                 "installed": [{"distro": "jazzy", "path": "/opt/ros/jazzy",
                                "setup_bash": True,
                                "sourced": {
                                    "ros_distro_after_source": "jazzy",
                                    "ament_prefix_path": "/opt/ros/jazzy",
                                    "functional_probe": {
                                        "command": "ros2 doctor --report",
                                        "ran": True, "ok": True,
                                        "detail": "exit code 0"}}}],
                 "env_ros_distro": "jazzy",
                 "env_ament_prefix_path": "/opt/ros/jazzy",
                 "methods_tried": ["list /opt/ros/<distro>"], "error": None},
        "gazebo": {"gz_path": "/usr/bin/gz", "legacy_path": None,
                   "version_raw": "Gazebo Sim, version: 8.15.0",
                   "version": [8, 15, 0],
                   "methods_tried": ["gz sim --version"], "error": None},
        "docker": {"cli_path": "/usr/bin/docker",
                   "cli_version_raw": "Docker version 27.3.1, build ce12230",
                   "cli_version": [27, 3, 1], "daemon_reachable": True,
                   "daemon_server_version": "27.3.1", "daemon_error": None,
                   "methods_tried": ["docker info"], "error": None},
    }


def finding(result, check_id):
    return next(f for f in result["findings"] if f["id"] == check_id)


class TestHealthyMachine(unittest.TestCase):
    def test_ros_and_docker_ready(self):
        result = ev.evaluate(base_profile())
        self.assertEqual(finding(result, "ros2")["status"], ev.READY)
        self.assertEqual(finding(result, "docker")["status"], ev.READY)
        self.assertEqual(finding(result, "os")["status"], ev.READY)
        self.assertEqual(finding(result, "disk_space")["status"], ev.READY)

    def test_gazebo_never_ready_without_smoke_test(self):
        # Honesty rule: Harmonic is installed + compatible, but no
        # simulator smoke test exists in v1, so operational is not
        # assessed and READY must not be claimed.
        result = ev.evaluate(base_profile())
        gz = finding(result, "gazebo")
        self.assertEqual(gz["status"], ev.UNKNOWN)
        self.assertIsNone(gz["states"]["operational"])
        self.assertTrue(gz["states"]["installed"])
        self.assertTrue(gz["states"]["compatible"])
        self.assertIn("gazebo", result["summary"]["stack_readiness"]["blockers"])
        self.assertEqual(result["summary"]["stack_readiness"]["status"], "NOT READY")


class TestMissingRos(unittest.TestCase):
    def test_missing_ros_is_not_installed_and_blocks_stack(self):
        profile = base_profile()
        profile["ros2"]["installed"] = []
        profile["ros2"]["env_ros_distro"] = None
        result = ev.evaluate(profile)
        ros = finding(result, "ros2")
        self.assertEqual(ros["status"], ev.NOT_INSTALLED)
        self.assertFalse(ros["states"]["installed"])
        self.assertIn("ros2", result["summary"]["stack_readiness"]["blockers"])

    def test_missing_optional_docker_does_not_block(self):
        profile = base_profile()
        profile["docker"]["cli_path"] = None
        result = ev.evaluate(profile)
        docker = finding(result, "docker")
        self.assertEqual(docker["status"], ev.NOT_INSTALLED)
        # Optional absence: noted, never a stack blocker, and it never
        # degrades workstation readiness.
        self.assertIn("docker", result["summary"]["stack_readiness"]["optional_not_ready"])
        self.assertNotIn("docker", result["summary"]["stack_readiness"]["blockers"])
        self.assertEqual(result["summary"]["workstation_readiness"]["status"], ev.READY)


class TestLowDisk(unittest.TestCase):
    def test_low_disk_is_misconfigured_with_reason(self):
        profile = base_profile()
        profile["disk"]["free_gb"] = 17.0  # the Omega-Ubuntu pre-install state
        result = ev.evaluate(profile)
        disk = finding(result, "disk_space")
        self.assertEqual(disk["status"], ev.MISCONFIGURED)
        self.assertIn("40", " ".join(disk["reasons"]))
        self.assertIsNotNone(disk["recommendation"])
        self.assertIn("disk_space", result["summary"]["stack_readiness"]["blockers"])


class TestIncompatibleVersions(unittest.TestCase):
    def test_humble_on_ubuntu_2404_is_incompatible(self):
        profile = base_profile()
        profile["ros2"]["installed"] = [{
            "distro": "humble", "path": "/opt/ros/humble", "setup_bash": True,
            "sourced": {"ros_distro_after_source": "humble",
                        "ament_prefix_path": "/opt/ros/humble",
                        "functional_probe": {"command": "ros2 doctor --report",
                                             "ran": True, "ok": True,
                                             "detail": "exit code 0"}}}]
        profile["ros2"]["env_ros_distro"] = "humble"
        result = ev.evaluate(profile)
        ros = finding(result, "ros2")
        self.assertEqual(ros["status"], ev.INCOMPATIBLE)
        self.assertIn("22.04", " ".join(ros["reasons"]))

    def test_fortress_with_jazzy_is_incompatible(self):
        profile = base_profile()
        profile["gazebo"]["version"] = [6, 16, 0]
        profile["gazebo"]["version_raw"] = "Gazebo Sim, version: 6.16.0"
        result = ev.evaluate(profile)
        gz = finding(result, "gazebo")
        self.assertEqual(gz["status"], ev.INCOMPATIBLE)
        self.assertIn("fortress", " ".join(gz["reasons"]).lower())

    def test_wrong_os_for_stack_is_incompatible(self):
        profile = base_profile()
        profile["os"]["version_id"] = "22.04"
        result = ev.evaluate(profile)
        self.assertEqual(finding(result, "os")["status"], ev.INCOMPATIBLE)


class TestDockerDaemonDown(unittest.TestCase):
    def test_cli_present_daemon_down_is_misconfigured_not_ready(self):
        profile = base_profile()
        profile["docker"]["daemon_reachable"] = False
        profile["docker"]["daemon_error"] = "Cannot connect to the Docker daemon"
        result = ev.evaluate(profile)
        docker = finding(result, "docker")
        self.assertEqual(docker["status"], ev.MISCONFIGURED)
        self.assertTrue(docker["states"]["installed"])
        self.assertFalse(docker["states"]["operational"])


class TestUnknownProbes(unittest.TestCase):
    def test_unreadable_os_release_is_unknown(self):
        profile = base_profile()
        profile["os"] = {"id": None, "version_id": None, "pretty_name": None,
                         "source": "/etc/os-release",
                         "error": "cannot read /etc/os-release: Permission denied"}
        result = ev.evaluate(profile)
        self.assertEqual(finding(result, "os")["status"], ev.UNKNOWN)
        self.assertEqual(result["summary"]["workstation_readiness"]["status"], ev.UNKNOWN)

    def test_unparseable_gazebo_version_is_unknown(self):
        profile = base_profile()
        profile["gazebo"]["version"] = None
        profile["gazebo"]["version_raw"] = "some unexpected banner"
        result = ev.evaluate(profile)
        self.assertEqual(finding(result, "gazebo")["status"], ev.UNKNOWN)

    def test_ros_functional_probe_incomplete_is_unknown_not_ready(self):
        profile = base_profile()
        profile["ros2"]["installed"][0]["sourced"]["functional_probe"] = {
            "command": "ros2 doctor --report", "ran": False, "ok": None,
            "detail": "timeout after 25s"}
        result = ev.evaluate(profile)
        ros = finding(result, "ros2")
        self.assertEqual(ros["status"], ev.UNKNOWN)
        self.assertIsNone(ros["states"]["operational"])


class TestRosMisconfigured(unittest.TestCase):
    def test_installed_but_not_sourcing_is_misconfigured(self):
        profile = base_profile()
        profile["ros2"]["installed"][0]["sourced"]["ros_distro_after_source"] = None
        profile["ros2"]["installed"][0]["sourced"]["ament_prefix_path"] = None
        result = ev.evaluate(profile)
        ros = finding(result, "ros2")
        self.assertEqual(ros["status"], ev.MISCONFIGURED)
        self.assertTrue(ros["states"]["installed"])
        self.assertFalse(ros["states"]["configured"])


class TestParsers(unittest.TestCase):
    def test_parse_os_release(self):
        data = probes.parse_os_release('NAME="Ubuntu"\nVERSION_ID="24.04"\nID=ubuntu\n')
        self.assertEqual(data["ID"], "ubuntu")
        self.assertEqual(data["VERSION_ID"], "24.04")

    def test_parse_gazebo_version(self):
        self.assertEqual(probes.parse_version("Gazebo Sim, version: 8.15.0"), (8, 15, 0))
        self.assertEqual(probes.parse_version("Docker version 27.3.1, build ce12230"),
                         (27, 3, 1))
        self.assertIsNone(probes.parse_version("no numbers here at all"))


class TestReportsAgree(unittest.TestCase):
    def test_json_and_markdown_come_from_same_findings(self):
        result = ev.evaluate(base_profile())
        report = {"schema_version": 1, "generated_at": "2026-10-24T00:00:00Z",
                  "target_stack": result["target_stack"],
                  "findings": result["findings"], "summary": result["summary"]}
        parsed = json.loads(report_mod.to_json(report))
        md = report_mod.to_markdown(report)
        for f in parsed["findings"]:
            self.assertIn(f["status"], md)
            self.assertIn(f["name"], md)
        self.assertEqual([f["id"] for f in parsed["findings"]],
                         [f["id"] for f in report["findings"]])
        self.assertEqual(parsed["summary"]["stack_readiness"]["status"],
                         report["summary"]["stack_readiness"]["status"])


if __name__ == "__main__":
    unittest.main()
