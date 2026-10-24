import SwiftUI

struct SettingsView: View {
    @AppStorage("vmName") private var vmName: String = "Omega-Ubuntu"
    @AppStorage("sshUser") private var sshUser: String = "ryuk"
    @AppStorage("sshHost") private var sshHost: String = "100.67.141.81"
    @EnvironmentObject private var runtime: RuntimeController

    var body: some View {
        Form {
            Section("Linux runtime") {
                TextField("UTM virtual machine", text: $vmName)
                TextField("SSH user", text: $sshUser)
                TextField("SSH host (Tailscale address)", text: $sshHost)
                Button("Re-check everything") { runtime.refresh() }
            }
            Section("About") {
                LabeledContent("App", value: "Hangar Bay")
                LabeledContent("Version", value: "0.2 — DARKSTAR foundation")
                Text("One friendly place on your Mac for robotics development: pick a validated environment, pass preflight, fly in simulation, verify the evidence, then go to real hardware. The Linux runtime underneath is managed for you.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .preferredColorScheme(.dark)
    }
}
