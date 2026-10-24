import SwiftUI

/// Preflight: the prerequisite check every user runs before setup, before
/// a build, before a flight. Each row is a real probe of this Mac or the
/// runtime; failed rows carry their remedy as a button, and anything the
/// app cannot fix by itself appears in Dependency Downloads with its size
/// and source, ready for the download engine.
struct PreflightView: View {
    @EnvironmentObject private var runtime: RuntimeController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                checklist
                downloads
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Preflight")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pre-flight checks")
                .font(.largeTitle.bold())
            Text("Everything a budding roboticist needs — verified before anything runs. Checks re-run automatically every few seconds.")
                .foregroundStyle(.secondary)
            if let when = runtime.lastChecked {
                Text("Last checked \(when.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(runtime.checks) { check in
                HStack(spacing: 12) {
                    Image(systemName: symbol(for: check.status))
                        .foregroundStyle(color(for: check.status))
                        .font(.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title).font(.headline)
                        Text(check.detail).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let title = check.actionTitle, let id = check.actionID {
                        Button(title) { runtime.performAction(id) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private var downloads: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dependency downloads")
                .font(.title2.bold())
            Text("The heavy pieces a fresh install pulls down automatically. The download engine ships with the packaging step; tonight these were provisioned by script on Omega-Ubuntu.")
                .foregroundStyle(.secondary)
            ForEach(Dependency.samples) { dep in
                HStack(spacing: 12) {
                    Image(systemName: dep.icon)
                        .font(.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dep.name).font(.headline)
                        Text("\(dep.source) · \(dep.size)")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(dep.state)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func symbol(for status: CheckStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(for status: CheckStatus) -> Color {
        switch status {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .unknown: return .secondary
        }
    }
}

struct Dependency: Identifiable {
    let id = UUID()
    let name: String
    let source: String
    let size: String
    let icon: String
    let state: String

    static let samples: [Dependency] = [
        Dependency(name: "Golden runtime image (Omega-Ubuntu)", source: "Control Center library", size: "~12 GB", icon: "externaldrive", state: "After PX4 build"),
        Dependency(name: "PX4-Autopilot source", source: "github.com/PX4", size: "~5 GB with submodules", icon: "airplane", state: "Downloading in runtime"),
        Dependency(name: "Micro XRCE-DDS Agent", source: "github.com/eProsima", size: "~60 MB", icon: "arrow.left.arrow.right", state: "Build pending"),
        Dependency(name: "px4_msgs (pinned 392e831)", source: "github.com/PX4", size: "~15 MB", icon: "envelope", state: "Installed in runtime"),
        Dependency(name: "ROS 2 Jazzy + Gazebo Harmonic", source: "packages.ros.org · OSRF", size: "~3 GB", icon: "shippingbox", state: "Installed in runtime")
    ]
}
