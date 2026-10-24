import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var runtime: RuntimeController

    private var runtimeRunning: Bool { runtime.vmState == "Running" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
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
        .background(HB.obsidian)
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("COMMAND DECK / 01")
            Text("Fleet Overview")
                .font(.largeTitle.bold())
                .foregroundStyle(HB.frost)
            Text("Every robot you own, ready to fly. · \(runtime.hostSummary)")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if runtimeRunning {
                    EvidenceChip(.live, label: "RUNTIME · LIVE")
                } else {
                    EvidenceChip(.unknown, label: "RUNTIME · \(runtime.vmState.uppercased())")
                }
                EvidenceChip(.recorded, label: "GOLDEN DEMO · PASS")
                EvidenceChip(.demo, label: "FLEET · SAMPLE")
            }
            .padding(.top, 2)
        }
    }

    private var runtimeCard: some View {
        Card(title: "Linux Runtime", icon: "server.rack",
             chip: runtimeRunning ? EvidenceChip(.live) : EvidenceChip(.unknown, label: runtime.vmState.uppercased())) {
            LabeledContent("Virtual machine", value: runtime.vmName)
            LabeledContent("State", value: runtime.vmState)
            HStack {
                if runtimeRunning {
                    Button("Stop") { runtime.stopVM() }
                } else {
                    Button("Start") { runtime.startVM() }
                        .buttonStyle(.borderedProminent)
                        .tint(HB.signal)
                }
                Button("Console") { runtime.openConsole() }
                Button("SSH") { runtime.openSSHTerminal() }
            }
            .padding(.top, 4)
        }
    }

    private var pairingCard: some View {
        Card(title: "Active Pairing", icon: "square.stack.3d.up", chip: EvidenceChip(.recorded, label: "VALIDATED")) {
            LabeledContent("Ubuntu", value: "24.04 LTS")
            LabeledContent("ROS 2", value: "Jazzy")
            LabeledContent("Simulator", value: "Gazebo Harmonic 8.15")
            Text("A validated pairing — you never have to guess which versions belong together.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var px4Card: some View {
        Card(title: "PX4 SITL", icon: "airplane", chip: EvidenceChip(.recorded, label: "VERIFIED 2026-10-23")) {
            LabeledContent("Autopilot", value: "PX4-Autopilot")
            LabeledContent("Bridge", value: "Micro XRCE-DDS · UDP 8888")
            LabeledContent("Messages", value: "px4_msgs @ 392e831")
            Text("Golden-demo environment: the same pinned revisions that produced the verified 2026-09-12 swarm flight.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var linkCard: some View {
        Card(title: "Tailscale Link", icon: "network",
             chip: runtime.tailscaleState.contains("Connected") ? EvidenceChip(.live) : EvidenceChip(.unknown)) {
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
    var chip: EvidenceChip? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(HB.frost)
                Spacer()
                if let chip { chip }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HB.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HB.hairline, lineWidth: 1))
    }
}
