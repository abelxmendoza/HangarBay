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
    public static let remoteProbeCommand = "echo \"HOSTNAME=$(hostname)\"; echo \"OS=$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})\"; echo \"ARCH=$(uname -m)\"; echo \"KERNEL=$(uname -r)\"; echo \"UPTIME=$(uptime -p 2>/dev/null)\"; echo \"DF=$(df -P / | tail -n 1)\"; echo \"ROS=$(ls /opt/ros 2>/dev/null | paste -sd, -)\"; echo \"GZ=$(gz sim --version 2>/dev/null | head -n 1)\"; echo \"DOCKER=$(command -v docker || echo absent)\"; echo \"ROS2CLI=$(command -v ros2 || echo absent)\"; echo \"PX4=$(ls -d ~/PX4-Autopilot ~/PX4-Autonomous-Missions 2>/dev/null | paste -sd, -)\""

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
