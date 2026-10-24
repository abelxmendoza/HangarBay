import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var runtime: RuntimeController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hangar Bay")
                        .font(.largeTitle.bold())
                    Text("Every robot you own, ready to fly. · \(runtime.hostSummary)")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    runtimeCard
                    pairingCard
                    px4Card
                    linkCard
                }

                Text("The runtime does the heavy lifting underneath — ROS 2, Gazebo and PX4 live there, so this Mac stays a clean place to think, design and review.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle("Dashboard")
    }

    private var runtimeCard: some View {
        Card(title: "Linux Runtime", icon: "server.rack") {
            LabeledContent("Virtual machine", value: runtime.vmName)
            LabeledContent("State", value: runtime.vmState)
            HStack {
                if runtime.vmState == "Running" {
                    Button("Stop") { runtime.stopVM() }
                } else {
                    Button("Start") { runtime.startVM() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Console") { runtime.openConsole() }
                Button("SSH") { runtime.openSSHTerminal() }
            }
            .padding(.top, 4)
        }
    }

    private var pairingCard: some View {
        Card(title: "Active Pairing", icon: "square.stack.3d.up") {
            LabeledContent("Ubuntu", value: "24.04 LTS")
            LabeledContent("ROS 2", value: "Jazzy")
            LabeledContent("Simulator", value: "Gazebo Harmonic 8.15")
            Text("A validated pairing — you never have to guess which versions belong together.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var px4Card: some View {
        Card(title: "PX4 SITL", icon: "airplane") {
            LabeledContent("Autopilot", value: "PX4-Autopilot")
            LabeledContent("Bridge", value: "Micro XRCE-DDS · UDP 8888")
            LabeledContent("Messages", value: "px4_msgs @ 392e831")
            Text("Golden-demo environment: the same pinned revisions that produced the verified 2026-09-12 swarm flight.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var linkCard: some View {
        Card(title: "Tailscale Link", icon: "network") {
            LabeledContent("State", value: runtime.tailscaleState)
            LabeledContent("Runtime address", value: runtime.sshHost)
            Text("Your Mac and the runtime find each other anywhere — no port forwarding, no router spelunking.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.55)))
    }
}
