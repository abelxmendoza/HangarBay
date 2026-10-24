import Foundation
import AppKit

enum CheckStatus {
    case pass, warn, fail, unknown
}

struct PreflightCheck: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let status: CheckStatus
    var actionTitle: String? = nil
    var actionID: String? = nil
}

/// Owns everything the app knows about the world outside its own window:
/// the host Mac, the UTM runtime, and the Tailscale link. Polls on a timer
/// so the dashboard and the preflight checklist are always live.
final class RuntimeController: ObservableObject {
    @Published var vmState: String = "Unknown"
    @Published var tailscaleState: String = "Unknown"
    @Published var checks: [PreflightCheck] = []
    @Published var lastChecked: Date? = nil

    private var timer: Timer?

    var vmName: String { UserDefaults.standard.string(forKey: "vmName") ?? "Omega-Ubuntu" }
    var sshUser: String { UserDefaults.standard.string(forKey: "sshUser") ?? "ryuk" }
    var sshHost: String { UserDefaults.standard.string(forKey: "sshHost") ?? "100.67.141.81" }

    var hostSummary: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let ram = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
        return "Apple silicon Mac · \(ram) RAM · \(os)"
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Polling

    func refresh() {
        let name = vmName
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let vm = Self.vmStatus(named: name)
            let ts = Self.tailscaleStatus()
            let built = Self.buildChecks(vmName: name, vm: vm, tailscale: ts)
            DispatchQueue.main.async {
                self.vmState = vm
                self.tailscaleState = ts
                self.checks = built
                self.lastChecked = Date()
            }
        }
    }

    // MARK: - Actions (also used as preflight remedies)

    func performAction(_ id: String) {
        switch id {
        case "startVM": startVM()
        case "openUTM": openConsole()
        default: break
        }
    }

    func startVM() {
        _ = Self.run("/Applications/UTM.app/Contents/MacOS/utmctl", ["start", vmName])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    func stopVM() {
        _ = Self.run("/Applications/UTM.app/Contents/MacOS/utmctl", ["stop", vmName])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    func openConsole() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/UTM.app"))
    }

    func openSSHTerminal() {
        let cmd = "ssh \(sshUser)@\(sshHost)"
        _ = Self.run("/usr/bin/osascript", [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(cmd)\""
        ])
    }

    // MARK: - Probes

    private static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func vmStatus(named name: String) -> String {
        let (code, out) = run("/Applications/UTM.app/Contents/MacOS/utmctl", ["list"])
        guard code == 0 else { return "UTM not available" }
        for line in out.split(separator: "\n") {
            if line.contains(name) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    return parts[1] == "started" ? "Running" : "Stopped"
                }
                return "Present"
            }
        }
        return "Not found"
    }

    private static func tailscaleStatus() -> String {
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let (code, out) = run(path, ["status", "--json"])
            if code == 0 {
                return out.contains("\"BackendState\":\"Running\"") || out.contains("\"BackendState\": \"Running\"") ? "Connected" : "Stopped"
            }
        }
        return "Not installed"
    }

    // MARK: - Preflight checklist

    private static func buildChecks(vmName: String, vm: String, tailscale: String) -> [PreflightCheck] {
        var result: [PreflightCheck] = []
        let fm = FileManager.default

        result.append(PreflightCheck(
            title: "macOS",
            detail: ProcessInfo.processInfo.operatingSystemVersionString + " · Apple silicon",
            status: .pass))

        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        result.append(PreflightCheck(
            title: "Memory",
            detail: String(format: "%.0f GB installed · runtime reserves 8 GB while running", ramGB),
            status: ramGB >= 16 ? .pass : .warn))

        var freeGB = -1.0
        if let vals = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let cap = vals.volumeAvailableCapacityForImportantUsage {
            freeGB = Double(cap) / 1_073_741_824
        }
        result.append(PreflightCheck(
            title: "Free disk on this Mac",
            detail: freeGB >= 0 ? String(format: "%.0f GB free · the golden runtime image wants ~100 GB of headroom", freeGB) : "Could not measure",
            status: freeGB >= 100 ? .pass : (freeGB >= 40 ? .warn : .fail)))

        result.append(PreflightCheck(
            title: "Xcode",
            detail: fm.fileExists(atPath: "/Applications/Xcode.app") ? "Installed" : "Missing — install from the App Store",
            status: fm.fileExists(atPath: "/Applications/Xcode.app") ? .pass : .fail))

        let utm = fm.fileExists(atPath: "/Applications/UTM.app")
        result.append(PreflightCheck(
            title: "UTM runtime host",
            detail: utm ? "Installed" : "Missing — the runtime lives in a UTM virtual machine",
            status: utm ? .pass : .fail,
            actionTitle: utm ? nil : "Open UTM",
            actionID: utm ? nil : "openUTM"))

        result.append(PreflightCheck(
            title: "Runtime VM (\(vmName))",
            detail: vm,
            status: vm == "Running" ? .pass : (vm == "Stopped" ? .warn : .fail),
            actionTitle: vm == "Stopped" ? "Start VM" : nil,
            actionID: vm == "Stopped" ? "startVM" : nil))

        result.append(PreflightCheck(
            title: "Tailscale link",
            detail: tailscale,
            status: tailscale == "Connected" ? .pass : .fail))

        result.append(PreflightCheck(
            title: "Runtime SSH",
            detail: "Verified out-of-band 2026-10-23 · in-app probe arrives with the runtime bridge",
            status: .unknown))

        result.append(PreflightCheck(
            title: "ROS 2 Jazzy (in runtime)",
            detail: "Installed and verified 2026-10-23 · 194 packages",
            status: .unknown))

        result.append(PreflightCheck(
            title: "Gazebo Harmonic (in runtime)",
            detail: "Gazebo Sim 8.15.0 · headless smoke test passed 2026-10-23",
            status: .unknown))

        result.append(PreflightCheck(
            title: "PX4 SITL",
            detail: "Source clone and build in progress on the runtime",
            status: .warn))

        return result
    }
}
