import SwiftUI
import DarkstarCore

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
                resourcesCard
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
            BrandLogo(height: 200, cornerRadius: 18)
                .padding(.bottom, 4)
            Eyebrow("COMMAND DECK / 01")
            Text("Fleet Overview")
                .font(.largeTitle.bold())
                .foregroundStyle(HB.frost)
            Text("BUILD • EXPLORE • DEPLOY · \(runtime.hostSummary)")
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
            if let message = runtime.runtimeHealth.userMessage {
                Text(message)
                    .font(.callout.weight(runtime.runtimeHealth.isUnresponsive ? .semibold : .regular))
                    .foregroundStyle(runtime.runtimeHealth.isUnresponsive ? HB.alert : .secondary)
                if let recovery = runtime.runtimeHealth.recoverySuggestion {
                    Text(recovery).font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                if runtime.runtimeHealth.isUnresponsive || runtime.isForceRestarting {
                    Button(runtime.isForceRestarting ? "Restarting…" : "Force restart") { runtime.forceRestartVM() }
                        .buttonStyle(.borderedProminent)
                        .tint(HB.signal)
                        .disabled(runtime.isForceRestarting)
                } else if runtimeRunning || runtime.vmState == "Starting up" {
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
            if let error = runtime.lastActionError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.userMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(HB.alert)
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("Dismiss") { runtime.clearActionError() }
                        .controlSize(.small)
                }
                .padding(.top, 6)
            }
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

    // MARK: - Resources (split-architecture design §9: know / show / manage)

    private var headroomVerdict: HeadroomVerdict {
        guard let memory = runtime.memory else { return .unknown }
        return ResourceRules.runtimeHeadroom(
            pressure: memory.pressure,
            availableBytes: memory.availableBytes,
            reservationBytes: runtime.vmReservationBytes,
            vmRunning: runtimeRunning)
    }

    private var verdictColor: Color {
        switch headroomVerdict {
        case .fits: return HB.telemetry
        case .tight: return HB.warning
        case .wontFit: return HB.alert
        case .unknown: return HB.steel
        }
    }

    private var verdictSentence: String {
        let top = runtime.topProcesses.first
        switch headroomVerdict {
        case .fits:
            return runtimeRunning
                ? "Fits — the runtime is resident and this Mac still has headroom."
                : "Fits — there is room to start the Linux runtime."
        case .tight:
            if let top {
                return "Tight — \(top.name) is using \(Self.fmt(top.bytes)). Quitting heavy apps frees real headroom."
            }
            return "Tight — memory pressure is elevated."
        case .wontFit:
            if let top {
                return "Won't fit yet — the runtime needs more free memory than this Mac has right now. Biggest consumer: \(top.name) at \(Self.fmt(top.bytes))."
            }
            return "Won't fit yet — the runtime needs more free memory than this Mac has right now."
        case .unknown:
            return "Not measured yet — the first probe lands a few seconds after launch."
        }
    }

    private var resourcesCard: some View {
        Card(title: "Workstation Resources", icon: "memorychip",
             chip: runtime.memory != nil ? EvidenceChip(.live) : EvidenceChip(.unknown)) {
            if let memory = runtime.memory {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(HB.gunmetal)
                        RoundedRectangle(cornerRadius: 4).fill(HB.cyan)
                            .frame(width: max(2, geo.size.width * memory.usedFraction))
                    }
                }
                .frame(height: 10)
                .accessibilityLabel("Memory used \(Self.fmt(memory.usedBytes)) of \(Self.fmt(memory.totalBytes))")

                LabeledContent("Memory used", value: "\(Self.fmt(memory.usedBytes)) of \(Self.fmt(memory.totalBytes))")
                LabeledContent("Available", value: Self.fmt(memory.availableBytes))
                LabeledContent("Pressure", value: memory.compressedBytes > 0
                    ? "\(memory.pressure.label) · \(Self.fmt(memory.compressedBytes)) compressed"
                    : memory.pressure.label)
                if let reservation = runtime.vmReservationBytes {
                    LabeledContent("Linux runtime", value: runtimeRunning
                        ? "Running · reserving \(Self.fmt(reservation))"
                        : "Stopped · needs \(Self.fmt(reservation)) to start")
                }
                Text(verdictSentence)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(verdictColor)
                    .padding(.top, 2)

                if !runtime.topProcesses.isEmpty {
                    Divider().overlay(HB.hairline)
                    Text("TOP MEMORY USERS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(HB.steel)
                    ForEach(runtime.topProcesses) { process in
                        HStack {
                            Text(process.name)
                            Spacer()
                            Text(Self.fmt(process.bytes))
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                            if runtime.quittableAppNames.contains(process.name),
                               process.name != "Darkstar Robotics",
                               process.name != "RoboticsControlCenter" {
                                Button("Quit") { runtime.quitApp(named: process.name) }
                                    .controlSize(.small)
                            }
                        }
                        .font(.callout)
                    }
                    Text("Darkstar never quits your apps on its own — it names the heavy ones and lets you decide.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Measuring this Mac's memory…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private static func fmt(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
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
