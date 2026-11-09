import Foundation
import DarkstarCore

// MARK: - CLI configuration

public enum CLICommand: Equatable, Sendable {
    case status
    case vm
    case version
    case help
}

/// Configuration for the Darkstar Linux CLI: who to link to, and how.
/// Resolution order for each value: explicit flag, environment variable,
/// built-in default.
public struct CLIConfig: Equatable, Sendable {
    public var user: String
    public var host: String
    public var identityFile: String?
    public var extraSSHArguments: [String]
    public var connectTimeoutSeconds: Int

    public init(user: String, host: String, identityFile: String? = nil,
                extraSSHArguments: [String] = [], connectTimeoutSeconds: Int = CLIConfig.defaultTimeoutSeconds) {
        self.user = user
        self.host = host
        self.identityFile = identityFile
        self.extraSSHArguments = extraSSHArguments
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }

    public static let defaultUser = "ryuk"
    public static let defaultHost = "100.67.141.81"
    public static let defaultTimeoutSeconds = 10

    public static let usage = """
        darkstar — Darkstar Robotics for Linux (links this machine to the runtime VM)

        USAGE
          darkstar <command> [options]

        COMMANDS
          status    Tailscale state on this machine + SSH link check to the VM (default)
          vm        Deep probe of the VM over SSH: OS, disk, ROS 2, Gazebo, Docker, PX4
          version   Print the CLI version
          help      Show this text

        OPTIONS
          --user <name>       SSH user on the VM (env DARKSTAR_SSH_USER, default ryuk)
          --host <address>    VM address (env DARKSTAR_SSH_HOST, default 100.67.141.81)
          --identity <path>   SSH identity file (env DARKSTAR_SSH_IDENTITY)
          --ssh-arg <arg>     Extra argument passed to ssh (repeatable;
                              env DARKSTAR_SSH_ARGS is a space-separated list)
          --timeout <seconds> SSH connect timeout (default 10)

        The CLI is read-only: it probes and reports, it never changes the VM.
        """

    public static func parse(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Result<(command: CLICommand, config: CLIConfig), DarkstarError> {
        var config = CLIConfig(
            user: environment["DARKSTAR_SSH_USER"] ?? defaultUser,
            host: environment["DARKSTAR_SSH_HOST"] ?? defaultHost,
            identityFile: environment["DARKSTAR_SSH_IDENTITY"],
            extraSSHArguments: (environment["DARKSTAR_SSH_ARGS"] ?? "")
                .split(separator: " ").map(String.init),
            connectTimeoutSeconds: defaultTimeoutSeconds
        )
        var command: CLICommand = .status
        var sawCommand = false

        var index = 0
        func nextValue(for flag: String) -> Result<String, DarkstarError> {
            guard index + 1 < arguments.count else {
                return .failure(.invalidInput(field: flag, reason: "The flag needs a value."))
            }
            index += 1
            return .success(arguments[index])
        }

        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "status", "vm", "version", "help":
                guard !sawCommand else {
                    return .failure(.invalidInput(field: "command", reason: "Give exactly one command."))
                }
                sawCommand = true
                command = CLICommand(word: arg)
            case "--user":
                switch nextValue(for: arg) {
                case .success(let value): config.user = value
                case .failure(let error): return .failure(error)
                }
            case "--host":
                switch nextValue(for: arg) {
                case .success(let value): config.host = value
                case .failure(let error): return .failure(error)
                }
            case "--identity", "-i":
                switch nextValue(for: arg) {
                case .success(let value): config.identityFile = value
                case .failure(let error): return .failure(error)
                }
            case "--ssh-arg":
                switch nextValue(for: arg) {
                case .success(let value): config.extraSSHArguments.append(value)
                case .failure(let error): return .failure(error)
                }
            case "--timeout":
                switch nextValue(for: arg) {
                case .success(let value):
                    guard let seconds = Int(value), seconds > 0 else {
                        return .failure(.invalidInput(field: "--timeout", reason: "Timeout must be a positive whole number of seconds."))
                    }
                    config.connectTimeoutSeconds = seconds
                case .failure(let error): return .failure(error)
                }
            case "--help", "-h":
                command = .help
                sawCommand = true
            case "--version":
                command = .version
                sawCommand = true
            default:
                return .failure(.invalidInput(field: arg, reason: "Unknown argument. Run `darkstar help` for usage."))
            }
            index += 1
        }

        // Validate the destination now so a bad target fails before any
        // process is launched, with DarkstarCore's safety rules.
        switch SSHDestination.validate(user: config.user, host: config.host) {
        case .success:
            return .success((command: command, config: config))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// The validated SSH destination for this configuration.
    public func validatedDestination() -> Result<SSHDestination, DarkstarError> {
        SSHDestination.validate(user: user, host: host)
    }
}

private extension CLICommand {
    init(word: String) {
        switch word {
        case "vm": self = .vm
        case "version": self = .version
        case "help": self = .help
        default: self = .status
        }
    }
}

// MARK: - Remote probe report

/// The parsed result of the one-shot probe the CLI runs inside the VM
/// over SSH. The remote side prints KEY=VALUE lines; everything the
/// remote shell could not determine is simply absent, and absence is
/// reported as UNKNOWN — never guessed.
public struct RemoteReport: Equatable, Sendable {
    public var values: [String: String]

    public static func parse(_ output: String) -> RemoteReport {
        var values: [String: String] = [:]
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equals])
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { values[key] = value }
        }
        return RemoteReport(values: values)
    }

    public var hostname: String? { values["HOSTNAME"] }
    public var osName: String? { values["OS"] }
    public var architecture: String? { values["ARCH"] }
    public var kernel: String? { values["KERNEL"] }
    public var uptime: String? { values["UPTIME"] }
    public var gazeboVersion: String? {
        guard let raw = values["GZ"], !raw.isEmpty else { return nil }
        return raw
    }

    /// The DF line is the raw `df -P /` data row:
    /// Filesystem, 1K-blocks, Used, Available, Capacity, Mounted-on.
    public var diskTotalKB: Int? { diskField(index: 1) }
    public var diskFreeKB: Int? { diskField(index: 3) }
    public var diskFreeGB: Double? { diskFreeKB.map { Double($0) / 1_048_576.0 } }

    private func diskField(index: Int) -> Int? {
        guard let df = values["DF"] else { return nil }
        let fields = df.split(separator: " ").map(String.init)
        guard fields.count > index else { return nil }
        return Int(fields[index])
    }

    public var rosDistros: [String] {
        guard let raw = values["ROS"], !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    public var ros2CLIPresent: Bool {
        guard let raw = values["ROS2CLI"] else { return false }
        return raw != "absent" && !raw.isEmpty
    }

    public var dockerPath: String? {
        guard let raw = values["DOCKER"], raw != "absent", !raw.isEmpty else { return nil }
        return raw
    }

    public var px4Paths: [String] {
        guard let raw = values["PX4"], !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// ros2 executables found under /opt/ros/*/bin (independent of PATH,
    /// which a non-interactive SSH shell does not get from .bashrc).
    public var ros2Binaries: [String] {
        guard let raw = values["ROS2BIN"], !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// nil when the probe predates this field (older remote script).
    public var px4SITLBuilt: Bool? {
        guard let raw = values["PX4SITL"] else { return nil }
        return raw == "built"
    }

    public var xrceAgentPath: String? {
        guard let raw = values["XRCE"], raw != "absent", !raw.isEmpty else { return nil }
        return raw
    }

    public static func gibString(kb: Int) -> String {
        let gib = Double(kb) / 1_048_576.0
        return String(format: "%.1f", gib)
    }
}

// MARK: - Link probe

/// Runs the two link probes — local Tailscale state and the SSH session
/// into the VM — through an injected command runner, so the whole flow
/// is testable with a fake runner and no network.
public struct LinkProbe {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning) {
        self.runner = runner
    }

    public static let tailscaleCandidatePaths = [
        "/usr/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    public func tailscaleStatus() -> TailscaleStatus {
        RuntimeProbe(runner: runner).tailscaleStatus(candidatePaths: Self.tailscaleCandidatePaths)
    }

    /// The one-line remote script. The remote side stays dumb on
    /// purpose: it prints raw facts, and all interpretation (including
    /// the df column math) happens here, where it is unit-tested.
    public static let remoteProbeCommand = "echo \"HOSTNAME=$(hostname)\"; echo \"OS=$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})\"; echo \"ARCH=$(uname -m)\"; echo \"KERNEL=$(uname -r)\"; echo \"UPTIME=$(uptime -p 2>/dev/null)\"; echo \"DF=$(df -P / | tail -n 1)\"; echo \"ROS=$(ls /opt/ros 2>/dev/null | paste -sd, -)\"; echo \"GZ=$(gz sim --version 2>/dev/null | head -n 1)\"; echo \"DOCKER=$(command -v docker || echo absent)\"; echo \"ROS2CLI=$(command -v ros2 || echo absent)\"; echo \"PX4=$(ls -d ~/PX4-Autopilot ~/PX4-Autonomous-Missions 2>/dev/null | paste -sd, -)\"; echo \"ROS2BIN=$(ls /opt/ros/*/bin/ros2 2>/dev/null | paste -sd, -)\"; echo \"PX4SITL=$(test -x ~/PX4-Autopilot/build/px4_sitl_default/bin/px4 && echo built || echo absent)\"; echo \"XRCE=$(ls /usr/local/bin/MicroXRCEAgent 2>/dev/null || command -v MicroXRCEAgent || echo absent)\""

    public static func sshArguments(config: CLIConfig, destination: SSHDestination, remoteCommand: String) -> [String] {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(config.connectTimeoutSeconds)",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
        if let identity = config.identityFile {
            arguments += ["-i", identity, "-o", "IdentitiesOnly=yes"]
        }
        arguments += config.extraSSHArguments
        arguments.append(destination.target)
        arguments.append(remoteCommand)
        return arguments
    }

    /// Opens one SSH session to the VM, runs the probe, and parses the
    /// report. Throws the DarkstarError the runner surfaces (command
    /// not found, non-zero exit with ssh's stderr, timeout), or the
    /// validation error if the configured destination is unsafe.
    public func probeVM(config: CLIConfig, timeout: TimeInterval = 30) throws -> RemoteReport {
        let destination: SSHDestination
        switch config.validatedDestination() {
        case .success(let validated): destination = validated
        case .failure(let error): throw error
        }
        let output = try runner.runChecked(
            executable: "/usr/bin/ssh",
            arguments: Self.sshArguments(config: config, destination: destination, remoteCommand: Self.remoteProbeCommand),
            timeout: timeout
        )
        return RemoteReport.parse(output.stdout)
    }
}

// MARK: - Runtime stack preflight (used by the app)

/// One Preflight row about the software inside the runtime VM.
public struct RuntimeStackCheck: Equatable, Sendable {
    public enum Item: String, CaseIterable, Sendable {
        case ssh, disk, ros2, gazebo, px4, xrce
    }

    public let item: Item
    public let detail: String
    public let status: PreflightRuleStatus

    public var title: String {
        switch item {
        case .ssh: return "Runtime SSH"
        case .disk: return "Runtime disk"
        case .ros2: return "ROS 2 Jazzy (in runtime)"
        case .gazebo: return "Gazebo Harmonic (in runtime)"
        case .px4: return "PX4 SITL (in runtime)"
        case .xrce: return "Micro XRCE-DDS Agent (in runtime)"
        }
    }
}

/// The outcome of the last deep probe of the runtime.
public enum RuntimeStackProbeResult: Equatable, Sendable {
    case report(RemoteReport, at: Date)
    case failed(DarkstarError, at: Date)
}

/// Turns the runtime's health and the last deep probe into Preflight rows.
/// Honesty rules (docs/TESTING.md): a report is only trusted while the
/// runtime is answering; anything not probed is UNKNOWN with the reason,
/// never a pass from memory and never a guess.
public enum RuntimeStackAssessment {
    public static let fixHint = "run bash dev.sh runtime"

    public static func checks(health: RuntimeHealth, result: RuntimeStackProbeResult?) -> [RuntimeStackCheck] {
        switch health {
        case .notRunning:
            return unknownAll("The runtime is stopped — start it to check.")
        case .booting:
            return unknownAll("Waiting for the runtime to finish booting.")
        case .unverified:
            return unknownAll("Can't check until Tailscale is connected on this Mac.")
        case .unresponsive:
            var rows = unknownAll("The runtime isn't answering, so this can't be checked.")
            rows[0] = RuntimeStackCheck(item: .ssh,
                                        detail: health.userMessage ?? "The runtime isn't answering.",
                                        status: .fail)
            return rows
        case .responsive:
            switch result {
            case nil:
                return unknownAll("Checking the runtime…")
            case .failed(let error, _):
                var rows = unknownAll("Could not read the runtime — see Runtime SSH.")
                rows[0] = RuntimeStackCheck(item: .ssh, detail: error.displayMessage, status: .fail)
                return rows
            case .report(let report, _):
                return assess(report)
            }
        }
    }

    public static func assess(_ report: RemoteReport) -> [RuntimeStackCheck] {
        [ssh(report), disk(report), ros2(report), gazebo(report), px4(report), xrce(report)]
    }

    private static func unknownAll(_ detail: String) -> [RuntimeStackCheck] {
        RuntimeStackCheck.Item.allCases.map { RuntimeStackCheck(item: $0, detail: detail, status: .unknown) }
    }

    static func ssh(_ r: RemoteReport) -> RuntimeStackCheck {
        let parts = [r.hostname, r.osName, r.kernel.map { "kernel \($0)" }, r.uptime].compactMap { $0 }
        return RuntimeStackCheck(item: .ssh,
                                 detail: parts.isEmpty ? "Answered" : "Answered · " + parts.joined(separator: " · "),
                                 status: .pass)
    }

    static func disk(_ r: RemoteReport) -> RuntimeStackCheck {
        guard let free = r.diskFreeKB, let total = r.diskTotalKB else {
            return RuntimeStackCheck(item: .disk, detail: "The runtime did not report its disk.", status: .unknown)
        }
        let line = "\(RemoteReport.gibString(kb: free)) GB free of \(RemoteReport.gibString(kb: total)) GB"
        let status = PreflightRules.runtimeVMDiskStatus(freeGB: r.diskFreeGB)
        let suffix: String
        switch status {
        case .pass, .unknown: suffix = ""
        case .warn: suffix = " — tight for rebuilds and ros2 bags (want \(Int(PreflightRules.runtimeVMDiskPassGB)) GB+)"
        case .fail: suffix = " — too low; provisioning needs ~\(Int(PreflightRules.runtimeVMDiskPassGB)) GB (bash dev.sh doctor shows the fix)"
        }
        return RuntimeStackCheck(item: .disk, detail: line + suffix, status: status)
    }

    static func ros2(_ r: RemoteReport) -> RuntimeStackCheck {
        let hasJazzy = r.rosDistros.contains("jazzy")
        let jazzyBinary = r.ros2Binaries.contains { $0.hasPrefix("/opt/ros/jazzy/") }
        if hasJazzy && jazzyBinary {
            return RuntimeStackCheck(item: .ros2, detail: "Installed · /opt/ros/jazzy", status: .pass)
        }
        if hasJazzy {
            return RuntimeStackCheck(item: .ros2, detail: "/opt/ros/jazzy exists but has no ros2 command — incomplete install; \(fixHint)", status: .warn)
        }
        if !r.rosDistros.isEmpty {
            return RuntimeStackCheck(item: .ros2, detail: "Found \(r.rosDistros.joined(separator: ", ")); Darkstar's validated pairing is Jazzy — \(fixHint)", status: .warn)
        }
        return RuntimeStackCheck(item: .ros2, detail: "Not installed — \(fixHint)", status: .fail)
    }

    static func gazebo(_ r: RemoteReport) -> RuntimeStackCheck {
        guard let version = r.gazeboVersion else {
            return RuntimeStackCheck(item: .gazebo, detail: "Not installed — \(fixHint)", status: .fail)
        }
        // Gazebo Harmonic is gz-sim 8.x.
        if version.range(of: #"version 8\."#, options: .regularExpression) != nil {
            return RuntimeStackCheck(item: .gazebo, detail: version, status: .pass)
        }
        return RuntimeStackCheck(item: .gazebo, detail: "\(version) — the validated pairing is Harmonic (gz-sim 8)", status: .warn)
    }

    static func px4(_ r: RemoteReport) -> RuntimeStackCheck {
        switch r.px4SITLBuilt {
        case true?:
            return RuntimeStackCheck(item: .px4, detail: "Built · ~/PX4-Autopilot/build/px4_sitl_default", status: .pass)
        case false?:
            if r.px4Paths.contains(where: { $0.hasSuffix("/PX4-Autopilot") }) {
                return RuntimeStackCheck(item: .px4, detail: "Source is there but SITL isn't built — \(fixHint)", status: .warn)
            }
            return RuntimeStackCheck(item: .px4, detail: "Not installed — \(fixHint)", status: .fail)
        case nil:
            return RuntimeStackCheck(item: .px4, detail: "The runtime did not report PX4's build state.", status: .unknown)
        }
    }

    static func xrce(_ r: RemoteReport) -> RuntimeStackCheck {
        guard r.values["XRCE"] != nil else {
            return RuntimeStackCheck(item: .xrce, detail: "The runtime did not report the agent.", status: .unknown)
        }
        if let path = r.xrceAgentPath {
            return RuntimeStackCheck(item: .xrce, detail: "Installed · \(path) (PX4 ↔ ROS 2 bridge, UDP 8888)", status: .pass)
        }
        return RuntimeStackCheck(item: .xrce, detail: "Not installed — \(fixHint)", status: .fail)
    }
}

/// When to run the (heavier) deep probe. The cheap SSH reachability
/// check runs every poll; the stack probe runs once a minute, on demand,
/// and immediately once a freshly booted runtime starts answering.
public enum RuntimeStackProbeSchedule {
    public static let intervalSeconds: TimeInterval = 60

    public static func shouldProbe(health: RuntimeHealth, lastProbeAt: Date?, now: Date,
                                   force: Bool, inFlight: Bool,
                                   interval: TimeInterval = intervalSeconds) -> Bool {
        guard health == .responsive, !inFlight else { return false }
        guard !force, let last = lastProbeAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
