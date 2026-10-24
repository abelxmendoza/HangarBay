import SwiftUI
import DarkstarCore

struct MissionsView: View {
    @State private var replayError: String? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Missions")
                        .font(.largeTitle.bold())
                    Text("Fly it in simulation, verify it against requirements, then take it to real hardware.")
                        .foregroundStyle(.secondary)
                }

                goldenCard

                HStack(alignment: .top, spacing: 16) {
                    miniCard(
                        title: "Reproduce the evidence",
                        icon: "checkmark.shield",
                        bodyText: "The verifier recomputes the verdict from the raw recorded telemetry — no trust in the flight code required. Runs today from the runtime; an in-app button lands with the runtime bridge."
                    )
                    miniCard(
                        title: "Fly it again (SITL)",
                        icon: "play.circle",
                        bodyText: "A fresh dropout-recovery flight on this Mac's own runtime, checked against the golden numbers. Enabled when the PX4 SITL build completes."
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .background(HB.obsidian)
        .navigationTitle("Missions")
    }

    private var goldenCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                Text("Swarm Recovery — Golden Demo")
                    .font(.title2.bold())
                Spacer()
                EvidenceChip(.recorded, label: "RECORDED · 2026-09-12")
                Text("PASS")
                    .font(.headline)
                    .foregroundStyle(HB.telemetry)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(HB.telemetry.opacity(0.22)))
            }
            Text("Two PX4 quadcopters divide a cooperative mission. One is commanded to retire mid-flight; the survivor confirms it landed, inherits its tasks, and finishes — while an independent verifier checks every claim from the raw telemetry.")
                .foregroundStyle(.secondary)
            HStack(spacing: 28) {
                Stat(label: "Min separation", value: "8.095 m", note: "required 2.5 m")
                Stat(label: "Samples", value: "641", note: "synchronized")
                Stat(label: "Reassignments", value: "2", note: "after dropout")
                Stat(label: "Recorded", value: "2026-09-12", note: "PX4 SITL · Gazebo")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Watch the replay") { openReplay() }
                    .buttonStyle(.borderedProminent)
                    Text("Serve the replay from the missions project (web/replay) — or open the Viewer tab.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if let replayError {
                    Text(replayError)
                        .font(.callout)
                        .foregroundStyle(HB.alert)
                }
            }
        }
        .padding(20)
        .background(HB.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HB.hairline, lineWidth: 1))
    }

    private func openReplay() {
        switch ViewerURLPolicy.validate(ViewerURLPolicy.defaultReplayURLString) {
        case .success(let url):
            if NSWorkspace.shared.open(url) {
                replayError = nil
            } else {
                replayError = "macOS could not open the replay in a browser. Start the replay server on this Mac, or use the Viewer tab."
            }
        case .failure(let error):
            replayError = error.displayMessage
        }
    }

    private func miniCard(title: String, icon: String, bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            Text(bodyText).foregroundStyle(.secondary).font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HB.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HB.hairline, lineWidth: 1))
    }
}

private struct Stat: View {
    let label: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption.weight(.medium))
            Text(note).font(.caption).foregroundStyle(.tertiary)
        }
    }
}
