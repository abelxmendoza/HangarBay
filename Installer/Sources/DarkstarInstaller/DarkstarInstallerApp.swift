import SwiftUI
import AppKit

@main
struct DarkstarInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            InstallerView()
                .frame(width: 540, height: 620)
        }
        .windowResizability(.contentSize)
    }
}

private let brandStarfire = Color(red: 1.0, green: 0x4A / 255.0, blue: 0x2F / 255.0)
private let voidBlack = Color(red: 0x0A / 255.0, green: 0x0F / 255.0, blue: 0x14 / 255.0)
private let deepSlate = Color(red: 0x11 / 255.0, green: 0x18 / 255.0, blue: 0x21 / 255.0)
private let iceWhite = Color(red: 0xE8 / 255.0, green: 0xEA / 255.0, blue: 0xF0 / 255.0)
private let steelGray = Color(red: 0x8A / 255.0, green: 0x97 / 255.0, blue: 0xA8 / 255.0)
private let systemGreen = Color(red: 0x28 / 255.0, green: 0xD9 / 255.0, blue: 0x7A / 255.0)
private let alertRed = Color(red: 0xF6 / 255.0, green: 0x4D / 255.0, blue: 0x4D / 255.0)

final class InstallerModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case working(String)
        case installed
        case failed(String)
    }

    @Published var phase: Phase = .ready
    @Published var existingVersion: String? = nil
    @Published var alsoInUserApplications = false

    let newVersion = "0.3.0"
    private let appName = "Darkstar Robotics.app"
    private var systemDest: URL { URL(fileURLWithPath: "/Applications").appendingPathComponent(appName) }
    private var userDest: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").appendingPathComponent(appName) }

    init() { refreshExisting() }

    func refreshExisting() {
        existingVersion = version(at: systemDest) ?? version(at: userDest)
        alsoInUserApplications = FileManager.default.fileExists(atPath: userDest.path)
            && !FileManager.default.fileExists(atPath: systemDest.path)
    }

    private func version(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Bundle(path: url.path)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var isInstalled: Bool { existingVersion != nil }

    func install() {
        phase = .working("Preparing payload\u{2026}")
        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            do {
                guard let payload = Bundle.module.url(forResource: "Payload", withExtension: nil)?
                    .appendingPathComponent(self.appName),
                      fm.fileExists(atPath: payload.path) else {
                    await MainActor.run { self.phase = .failed("Installer payload is missing from this installer build. Nothing was installed.") }
                    return
                }
                await MainActor.run { self.phase = .working("Copying Darkstar Robotics to /Applications\u{2026}") }
                if fm.fileExists(atPath: self.systemDest.path) {
                    try fm.removeItem(at: self.systemDest)
                }
                try fm.copyItem(at: payload, to: self.systemDest)
                await MainActor.run {
                    self.refreshExisting()
                    self.phase = .installed
                }
            } catch {
                await MainActor.run { self.phase = .failed("Install failed: \(error.localizedDescription)") }
            }
        }
    }

    func openApp() {
        let target = FileManager.default.fileExists(atPath: systemDest.path) ? systemDest : userDest
        NSWorkspace.shared.open(target)
    }
}

struct InstallerView: View {
    @StateObject private var model = InstallerModel()

    private var logo: NSImage? {
        guard let url = Bundle.module.url(forResource: "installer-logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        ZStack {
            voidBlack.ignoresSafeArea()
            VStack(spacing: 14) {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 170)
                        .padding(.top, 22)
                }
                Text("DARKSTAR ROBOTICS")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(iceWhite)
                    .tracking(2)
                Text("BUILD \u{2022} EXPLORE \u{2022} DEPLOY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(brandStarfire)
                    .tracking(3)
                Text("Installer \u{2014} version \(model.newVersion) \u{00B7} macOS 14+ \u{00B7} Apple Silicon")
                    .font(.system(size: 12))
                    .foregroundColor(steelGray)

                statusPanel
                    .padding(.horizontal, 28)
                    .padding(.top, 4)

                actionButtons

                VStack(alignment: .leading, spacing: 5) {
                    Text("\u{2022} Installs Darkstar Robotics into /Applications. Nothing else on your Mac is changed.")
                    Text("\u{2022} This is an unsigned community build. On first launch, right-click the app and choose Open (or approve it under System Settings \u{2192} Privacy & Security).")
                    Text("\u{2022} Re-running this installer updates the app in place.")
                }
                .font(.system(size: 11))
                .foregroundColor(steelGray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 18)
            }
        }
    }

    @ViewBuilder private var statusPanel: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.system(size: 12.5))
                .foregroundColor(iceWhite)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(deepSlate)
        .cornerRadius(10)
    }

    private var statusColor: Color {
        switch model.phase {
        case .installed: return systemGreen
        case .failed: return alertRed
        case .working: return brandStarfire
        case .ready: return model.isInstalled ? systemGreen : steelGray
        }
    }

    private var statusText: String {
        switch model.phase {
        case .working(let step): return step
        case .installed: return "Installed \u{2014} Darkstar Robotics \(model.newVersion) is in /Applications."
        case .failed(let message): return message
        case .ready:
            if let v = model.existingVersion {
                var s = "Found existing install (version \(v))\(model.alsoInUserApplications ? " in your user Applications folder" : "")."
                if v != model.newVersion { s += " This installer will update it to \(model.newVersion)." }
                return s
            }
            return "Not installed yet. This installer will add Darkstar Robotics \(model.newVersion) to /Applications."
        }
    }

    @ViewBuilder private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(model.isInstalled ? "Reinstall / Update" : "Install Darkstar Robotics") { model.install() }
                .buttonStyle(.borderedProminent)
                .tint(brandStarfire)
                .disabled(isWorking)
            if model.isInstalled || model.phase == .installed {
                Button("Open Darkstar Robotics") { model.openApp() }
                    .buttonStyle(.bordered)
            }
            if isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var isWorking: Bool {
        if case .working = model.phase { return true }
        return false
    }
}
