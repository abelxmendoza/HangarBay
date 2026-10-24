import SwiftUI

/// Darkstar Robotics (formerly Hangar Bay) — a native macOS robotics
/// workstation. The user lives here; a managed Linux runtime (UTM today)
/// does the ROS 2 / Gazebo / PX4 work underneath.
@main
struct RoboticsControlCenterApp: App {
    @StateObject private var runtime = RuntimeController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runtime)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(runtime)
        }
    }
}
