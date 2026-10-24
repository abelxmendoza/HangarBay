import Foundation
import AppKit
import DarkstarCore

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
///
/// Error-handling rule: a boundary failure is data, not a dead end. Probes
/// return typed statuses from DarkstarCore and actions publish the exact
/// `DarkstarError` that occurred, so the UI can explain *why* something is
/// unavailable instead of collapsing every failure into "not available".
final class RuntimeController: ObservableObject {
    @Published var vmState: String = "Unknown"
    @Published var tailscaleState: String = "Unknown"
    @Published var checks: [PreflightCheck] = []
    @Published var lastChecked: Date? = nil
    @Published private(set) var lastActionError: DarkstarError? = nil

    private var timer: Timer?

    static let utmAppPath = "/Applications/UTM.app"
    static let utmctlPath = "/Applications/UTM.app/Contents/MacOS/utmctl"
    private static let runner = ProcessCommandRunner()

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
            let tailscale = Self.tailscaleStatus()
            let built = Self.buildChecks(vmName: name, vmStatus: vm, tailscaleStatus: tailscale)
            DispatchQueue.main.async {
                self.vmState = vm.legacyState
                self.tailscaleState = tailscale.legacyState
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

    func startVM() { runVMCommand("start") }
    func stopVM() { runVMCommand("stop") }

    private func runVMCommand(_ verb: String) {
        let name = vmName
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                _ = try Self.runner.runChecked(executable: Self.utmctlPath, arguments: [verb, name], timeout: 15)
                DispatchQueue.main.async {
                    self.lastActionError = nil
                    self.refresh()
                }
            } catch let error as DarkstarError {
                DispatchQueue.main.async {
                    self.lastActionError = error
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastActionError = .unknown(error.localizedDescription)
                    self.refresh()
                }
            }
        }
    }

    func openConsole() {
        guard FileManager.default.fileExists(atPath: Self.utmAppPath) else {
            lastActionError = .fileNotFound(path: Self.utmAppPath)
            return
        }
        if NSWorkspace.shared.open(URL(fileURLWithPath: Self.utmAppPath)) {
            lastActionError = nil
        } else {
            lastActionError = .unknown("macOS could not open UTM.")
        }
    }

    func openSSHTerminal() {
        switch SSHDestination.validate(user: sshUser, host: sshHost) {
        case .failure(let error):
            lastActionError = error
        case .success(let destination):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    _ = try Self.runner.runChecked(executable: "/usr/bin/osascript", arguments: [
                        "-e", "tell application \"Terminal\" to activate",
                        "-e", "tell application \"Terminal\" to do script \"\(destination.terminalCommand)\""
                    ], timeout: 10)
                    DispatchQueue.main.async { self.lastActionError = nil }
                } catch let error as DarkstarError {
                    DispatchQueue.main.async { self.lastActionError = error }
                } catch {
                    DispatchQueue.main.async { self.lastActionError = .unknown(error.localizedDescription) }
                }
            }
        }
    }

    func clearActionError() {
        lastActionError = nil
    }

    // MARK: - Probes

    private static let probe = RuntimeProbe(runner: ProcessCommandRunner())

    private static func vmStatus(named name: String) -> VMStatus {
        probe.vmStatus(utmctlPath: utmctlPath, vmName: name)
    }

    private static func tailscaleStatus() -> TailscaleStatus {
        probe.tailscaleStatus(candidatePaths: [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale"
        ])
    }

    // MARK: - Preflight checklist

    private static func map(_ status: PreflightRuleStatus) -> CheckStatus {
        switch status {
        case .pass: return .pass
        case .warn: return .warn
        case .fail: return .fail
        case .unknown: return .unknown
        }
    }

    private static func buildChecks(vmName: String, vmStatus: VMStatus, tailscaleStatus: TailscaleStatus) -> [PreflightCheck] {
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
            status: map(PreflightRules.memoryStatus(installedGB: ramGB))))

        var freeGB: Double? = nil
        if let vals = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let cap = vals.volumeAvailableCapacityForImportantUsage {
            freeGB = Double(cap) / 1_073_741_824
        }
        result.append(PreflightCheck(
            title: "Free disk on this Mac",
            detail: freeGB != nil ? String(format: "%.0f GB free · the golden runtime image wants ~100 GB of headroom", freeGB!) : "Could not measure",
            status: map(PreflightRules.diskStatus(freeGB: freeGB))))

        let xcodeInstalled = fm.fileExists(atPath: "/Applications/Xcode.app")
        result.append(PreflightCheck(
            title: "Xcode",
            detail: xcodeInstalled ? "Installed" : "Missing — install from the App Store",
            status: xcodeInstalled ? .pass : .fail))

        let utmInstalled = fm.fileExists(atPath: utmAppPath)
        let utmctlInstalled = fm.fileExists(atPath: utmctlPath)
        result.append(PreflightCheck(
            title: "UTM runtime host",
            detail: !utmInstalled
                ? "Missing — the runtime lives in a UTM virtual machine"
                : (utmctlInstalled
                    ? "Installed"
                    : "Installed, but Darkstar cannot control it: this UTM build is missing utmctl. Update UTM or manage the VM inside UTM."),
            status: !utmInstalled ? .fail : (utmctlInstalled ? .pass : .warn),
            actionTitle: utmInstalled ? nil : "Open UTM",
            actionID: utmInstalled ? nil : "openUTM"))

        result.append(PreflightCheck(
            title: "Runtime VM (\(vmName))",
            detail: vmStatus.detail,
            status: map(PreflightRules.vmStatus(vmStatus)),
            actionTitle: (vmStatus == .stopped || vmStatus == .paused) ? "Start VM" : nil,
            actionID: (vmStatus == .stopped || vmStatus == .paused) ? "startVM" : nil))

        result.append(PreflightCheck(
            title: "Tailscale link",
            detail: tailscaleStatus.detail,
            status: map(PreflightRules.tailscaleStatus(tailscaleStatus))))

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
