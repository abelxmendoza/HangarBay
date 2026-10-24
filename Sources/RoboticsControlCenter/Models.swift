import Foundation

/// A validated Ubuntu + ROS 2 + simulator pairing. Pairings are the core
/// idea of the Control Center: the user picks what they want to build,
/// never which distro "goes with" which ROS release.
enum EnvStatus: String {
    case ready = "Ready"
    case planned = "Planned"
    case settingUp = "Setting up"
}

struct RobotEnvironment: Identifiable {
    let id = UUID()
    let name: String
    let ubuntu: String
    let ros: String
    let simulator: String
    let runtimeName: String
    let status: EnvStatus
    let blurb: String

    static let samples: [RobotEnvironment] = [
        RobotEnvironment(
            name: "PX4 Swarm Lab",
            ubuntu: "Ubuntu 24.04",
            ros: "ROS 2 Jazzy",
            simulator: "Gazebo Harmonic",
            runtimeName: "Omega-Ubuntu",
            status: .ready,
            blurb: "PX4 SITL multi-vehicle simulation with ROS 2 offboard control and requirement verification."
        ),
        RobotEnvironment(
            name: "ROS 2 Desktop Lab",
            ubuntu: "Ubuntu 22.04",
            ros: "ROS 2 Humble",
            simulator: "Gazebo Fortress",
            runtimeName: "Not created yet",
            status: .planned,
            blurb: "The long-term-support pairing most university courses and TurtleBot stacks still target."
        ),
        RobotEnvironment(
            name: "Field Robotics Lab",
            ubuntu: "Ubuntu 24.04",
            ros: "ROS 2 Jazzy",
            simulator: "Gazebo Harmonic",
            runtimeName: "Omega-Ubuntu",
            status: .planned,
            blurb: "Same runtime as the Swarm Lab, tuned for a physical robot over Tailscale: teleop, bags, replay."
        )
    ]
}

struct RobotDevice: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let connection: String
    let status: String

    static let samples: [RobotDevice] = [
        RobotDevice(name: "SITL Vehicle 1", kind: "PX4 quadcopter (simulated)", connection: "Runtime · XRCE-DDS", status: "Flown in golden demo"),
        RobotDevice(name: "SITL Vehicle 2", kind: "PX4 quadcopter (simulated)", connection: "Runtime · XRCE-DDS", status: "Flown in golden demo")
    ]
}
