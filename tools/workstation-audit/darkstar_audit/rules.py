"""Compatibility rules for the Phase 1 audit, kept as data.

These encode the pairing knowledge from phase1-spec.md §3:
ROS distro <-> Ubuntu release, Gazebo flavour <-> ROS distro, and the
40 GB free-disk floor for the PX4 Drone Development stack (the
Omega-Ubuntu lesson: ~17 GB free cannot hold that stack).
"""

# ROS 2 distro -> the Ubuntu release it is built/targeted for.
ROS_UBUNTU_PAIRING = {
    "jazzy": "24.04",
    "humble": "22.04",
    "iron": "22.04",
    "foxy": "20.04",
    "galactic": "20.04",
}

# Gazebo flavour -> the ROS 2 distro it pairs with (per spec §3 sketch).
GAZEBO_ROS_PAIRING = {
    "harmonic": "jazzy",
    "garden": "iron",
    "fortress": "humble",
}

# Gazebo Sim major version -> flavour name. (11 is legacy Gazebo Classic,
# which has no supported pairing with current ROS 2 distros here.)
GAZEBO_MAJOR_TO_FLAVOR = {
    8: "harmonic",
    7: "garden",
    6: "fortress",
    11: "classic",
}

# Architectures the PX4 Drone Development stack targets (spec §3 sketch).
SUPPORTED_ARCHES = {"x86_64", "arm64", "aarch64"}

# System-requirement floor from the stack profile: minimum free disk (GB).
DISK_FREE_GB_MIN = 40

# The Phase 1 target stack. Stacks are presets, not bundles: every tool
# carries a role, and an absent *optional* tool never degrades readiness.
TARGET_STACK = {
    "id": "px4-drone-development",
    "name": "PX4 Drone Development",
    "os_id": "ubuntu",
    "os_release": "24.04",
    "ros_distro": "jazzy",
    "gazebo_flavor": "harmonic",
    "disk_free_gb_min": DISK_FREE_GB_MIN,
}

# Role of each audited item within the target stack.
ROLES = {
    "os": "required",
    "architecture": "required",
    "disk_space": "required",
    "ros2": "required",
    "gazebo": "required",
    "docker": "optional",  # useful container runtime; the stack does not require it
}
