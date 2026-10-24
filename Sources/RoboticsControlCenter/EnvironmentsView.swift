import SwiftUI

struct EnvironmentsView: View {
    @EnvironmentObject private var runtime: RuntimeController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Environments")
                        .font(.largeTitle.bold())
                    Text("One click gives you a complete, known-good robotics stack. No install guides, no version roulette.")
                        .foregroundStyle(.secondary)
                }

                ForEach(RobotEnvironment.samples) { env in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text(env.name).font(.title3.bold())
                                Text(env.status.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(env.status == .ready ? Color.green.opacity(0.25) : Color.secondary.opacity(0.2)))
                            }
                            Text(env.blurb).foregroundStyle(.secondary)
                            HStack(spacing: 14) {
                                Label(env.ubuntu, systemImage: "desktopcomputer")
                                Label(env.ros, systemImage: "point.3.connected.trianglepath.dotted")
                                Label(env.simulator, systemImage: "cube.transparent")
                                Label(env.runtimeName, systemImage: "server.rack")
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if env.status == .ready {
                            Button(runtime.vmState == "Running" ? "Running" : "Launch") { runtime.startVM() }
                                .buttonStyle(.borderedProminent)
                                .disabled(runtime.vmState == "Running")
                        } else {
                            Button("Set up") {}.disabled(true)
                            Text("Provisioning engine\narrives with packaging")
                                .font(.caption).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.55)))
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Environments")
    }
}
