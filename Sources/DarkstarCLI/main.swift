import Foundation
import DarkstarCore
import DarkstarLink

// darkstar — Darkstar Robotics for Linux.
// Links this machine to the runtime VM over Tailscale/SSH and reports
// what it finds, honestly: LIVE only for a probe that actually ran,
// UNKNOWN for anything the probe could not determine. Read-only.

let cliVersion = "0.1.0"

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func padded(_ label: String, _ width: Int = 14) -> String {
    label.padding(toLength: width, withPad: " ", startingAt: 0)
}

func printStatus(report: RemoteReport, config: CLIConfig) {
    let host = report.hostname ?? "VM"
    let os = report.osName ?? "unknown OS"
    let uptime = report.uptime ?? "unknown uptime"
    print("\(padded("SSH link"))LIVE — \(host) (\(os)), \(uptime)")
}

func printVM(report: RemoteReport) {
    print("\(padded("Hostname"))\(report.hostname ?? "UNKNOWN")")
    print("\(padded("OS"))\(report.osName ?? "UNKNOWN")")
    print("\(padded("Architecture"))\(report.architecture ?? "UNKNOWN")")
    print("\(padded("Kernel"))\(report.kernel ?? "UNKNOWN")")
    print("\(padded("Uptime"))\(report.uptime ?? "UNKNOWN")")
    if let free = report.diskFreeKB, let total = report.diskTotalKB {
        print("\(padded("Disk (root)"))\(RemoteReport.gibString(kb: free)) GB free of \(RemoteReport.gibString(kb: total)) GB")
    } else {
        print("\(padded("Disk (root)"))UNKNOWN")
    }
    if report.rosDistros.isEmpty {
        print("\(padded("ROS 2"))NOT INSTALLED (no /opt/ros)")
    } else {
        let cli = report.ros2CLIPresent ? "ros2 CLI present" : "ros2 CLI not on PATH"
        print("\(padded("ROS 2"))\(report.rosDistros.joined(separator: ", ")) — \(cli)")
    }
    print("\(padded("Gazebo"))\(report.gazeboVersion ?? "NOT INSTALLED")")
    print("\(padded("Docker"))\(report.dockerPath ?? "NOT INSTALLED")")
    if report.px4Paths.isEmpty {
        print("\(padded("PX4"))not found in the home directory")
    } else {
        print("\(padded("PX4"))\(report.px4Paths.joined(separator: ", "))")
    }
}

func run(command: CLICommand, config: CLIConfig) {
    let probe = LinkProbe(runner: ProcessCommandRunner())
    let label = "\(config.user)@\(config.host)"
    switch command {
    case .status:
        print("DARKSTAR LINK — \(label)")
        print("\(padded("Tailscale"))\(probe.tailscaleStatus().detail) (this machine)")
    case .vm:
        print("DARKSTAR VM PROBE — \(label)")
    case .version, .help:
        return
    }
    do {
        let report = try probe.probeVM(config: config)
        switch command {
        case .status: printStatus(report: report, config: config)
        case .vm: printVM(report: report)
        case .version, .help: break
        }
    } catch let error as DarkstarError {
        printError("\(padded("SSH link"))FAILED — \(error.displayMessage)")
        let diagnostic = error.diagnosticMessage
        if diagnostic != error.userMessage && !diagnostic.isEmpty {
            printError("\(padded(""))Detail: \(diagnostic)")
        }
        if let recovery = error.recoverySuggestion {
            printError("\(padded(""))\(recovery)")
        }
        exit(1)
    } catch {
        printError("\(padded("SSH link"))FAILED — \(error.localizedDescription)")
        exit(1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch CLIConfig.parse(arguments: arguments) {
case .failure(let error):
    printError(error.displayMessage)
    printError("Run `darkstar help` for usage.")
    exit(2)
case .success(let (command, config)):
    switch command {
    case .help:
        print(CLIConfig.usage)
    case .version:
        print("darkstar \(cliVersion) — Darkstar Robotics for Linux")
    case .status, .vm:
        run(command: command, config: config)
    }
}
