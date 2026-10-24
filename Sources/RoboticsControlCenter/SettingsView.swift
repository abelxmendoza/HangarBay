import SwiftUI

struct SettingsView: View {
    @AppStorage("vmName") private var vmName: String = "Omega-Ubuntu"
    @AppStorage("sshUser") private var sshUser: String = "ryuk"
    @AppStorage("sshHost") private var sshHost: String = "100.67.141.81"
    @EnvironmentObject private var runtime: RuntimeController
    @StateObject private var updater = UpdateChecker()

    var body: some View {
        Form {
            Section("Linux runtime") {
                TextField("UTM virtual machine", text: $vmName)
                TextField("SSH user", text: $sshUser)
                TextField("SSH host (Tailscale address)", text: $sshHost)
                Button("Re-check everything") { runtime.refresh() }
            }
            Section("Updates") {
                LabeledContent("Installed version", value: UpdateChecker.currentVersion)
                switch updater.state {
                case .notChecked:
                    Text("Not checked yet. Darkstar Robotics checks GitHub Releases only when you ask.")
                        .font(.callout).foregroundStyle(.secondary)
                case .checking:
                    Text("Checking GitHub Releases…")
                        .font(.callout).foregroundStyle(.secondary)
                case .upToDate(let latest):
                    Text("Up to date — latest release is \(latest).")
                        .font(.callout).foregroundStyle(.secondary)
                case .updateAvailable(let version, let url):
                    Link("Update available: version \(version) — view on GitHub", destination: url)
                case .failed(let message):
                    Text(message)
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Check for updates") { updater.check() }
            }
            Section("About") {
                LabeledContent("App", value: "Darkstar Robotics")
                LabeledContent("Version", value: "0.3.0")
                Text("One friendly place on your Mac for robotics development: pick a validated environment, pass preflight, fly in simulation, verify the evidence, then go to real hardware. The Linux runtime underneath is managed for you.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .preferredColorScheme(.dark)
    }
}
