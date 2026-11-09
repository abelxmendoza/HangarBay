import XCTest
@testable import DarkstarLink
import DarkstarCore

final class DarkstarLinkTests: XCTestCase {

    // MARK: - RemoteReport parsing

    private let sampleOutput = """
        HOSTNAME=omegaubuntu
        OS=Ubuntu 24.04.3 LTS
        ARCH=aarch64
        KERNEL=6.8.0-87-generic
        UPTIME=up 3 hours, 12 minutes
        DF=/dev/mapper/ubuntu--vg-ubuntu--lv 30859776 20583424 8710272 71% /
        ROS=jazzy
        GZ=Gazebo Sim, version 8.15.0
        DOCKER=absent
        ROS2CLI=/opt/ros/jazzy/bin/ros2
        PX4=/home/ryuk/PX4-Autonomous-Missions
        """

    func testParsesFullProbeOutput() {
        let report = RemoteReport.parse(sampleOutput)
        XCTAssertEqual(report.hostname, "omegaubuntu")
        XCTAssertEqual(report.osName, "Ubuntu 24.04.3 LTS")
        XCTAssertEqual(report.architecture, "aarch64")
        XCTAssertEqual(report.kernel, "6.8.0-87-generic")
        XCTAssertEqual(report.uptime, "up 3 hours, 12 minutes")
        XCTAssertEqual(report.rosDistros, ["jazzy"])
        XCTAssertEqual(report.gazeboVersion, "Gazebo Sim, version 8.15.0")
        XCTAssertNil(report.dockerPath)
        XCTAssertTrue(report.ros2CLIPresent)
        XCTAssertEqual(report.px4Paths, ["/home/ryuk/PX4-Autonomous-Missions"])
    }

    func testDiskFieldsComeFromTheDfColumns() {
        let report = RemoteReport.parse(sampleOutput)
        XCTAssertEqual(report.diskTotalKB, 30_859_776)
        XCTAssertEqual(report.diskFreeKB, 8_710_272)
        XCTAssertEqual(RemoteReport.gibString(kb: 8_710_272), "8.3")
        XCTAssertEqual(report.diskFreeGB!, 8.307, accuracy: 0.01)
        // 8.3 GB free is below what a full runtime install needs.
        XCTAssertEqual(PreflightRules.runtimeVMDiskStatus(freeGB: report.diskFreeGB), .fail)
    }

    func testMissingFactsStayAbsent() {
        let report = RemoteReport.parse("HOSTNAME=only\nGARBAGE LINE\n")
        XCTAssertEqual(report.hostname, "only")
        XCTAssertNil(report.osName)
        XCTAssertNil(report.diskFreeKB)
        XCTAssertNil(report.diskFreeGB)
        XCTAssertEqual(PreflightRules.runtimeVMDiskStatus(freeGB: report.diskFreeGB), .unknown)
        XCTAssertEqual(report.rosDistros, [])
        XCTAssertEqual(report.px4Paths, [])
        XCTAssertFalse(report.ros2CLIPresent)
    }

    func testMultipleROSDistrosSplitOnCommas() {
        let report = RemoteReport.parse("ROS=humble,jazzy\n")
        XCTAssertEqual(report.rosDistros, ["humble", "jazzy"])
    }

    // MARK: - CLIConfig parsing

    func testDefaultsComeFromTheEnvironment() {
        let result = CLIConfig.parse(arguments: [], environment: [:])
        guard case .success(let (command, config)) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(command, .status)
        XCTAssertEqual(config.user, "ryuk")
        XCTAssertEqual(config.host, "100.67.141.81")
        XCTAssertNil(config.identityFile)
    }

    func testEnvironmentOverridesDefaultsAndFlagsOverrideEnvironment() {
        let env = ["DARKSTAR_SSH_HOST": "10.0.0.9", "DARKSTAR_SSH_USER": "envuser"]
        let result = CLIConfig.parse(arguments: ["vm", "--host", "192.168.1.5"], environment: env)
        guard case .success(let (command, config)) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(command, .vm)
        XCTAssertEqual(config.host, "192.168.1.5")
        XCTAssertEqual(config.user, "envuser")
    }

    func testSSHArgsEnvironmentSplitsOnSpacesAndFlagAppends() {
        let env = ["DARKSTAR_SSH_ARGS": "-o ProxyJump=bastion -p 2222"]
        let result = CLIConfig.parse(arguments: ["status", "--ssh-arg", "-v"], environment: env)
        guard case .success(let (_, config)) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(config.extraSSHArguments, ["-o", "ProxyJump=bastion", "-p", "2222", "-v"])
    }

    func testUnknownFlagFailsWithInvalidInput() {
        let result = CLIConfig.parse(arguments: ["--bogus"], environment: [:])
        guard case .failure(let error) = result, case .invalidInput = error else {
            return XCTFail("expected invalidInput failure, got \(result)")
        }
    }

    func testFlagWithoutValueFails() {
        let result = CLIConfig.parse(arguments: ["--host"], environment: [:])
        guard case .failure(let error) = result, case .invalidInput = error else {
            return XCTFail("expected invalidInput failure, got \(result)")
        }
    }

    func testUnsafeHostIsRejectedByValidation() {
        let result = CLIConfig.parse(arguments: ["--host", "evil;rm"], environment: [:])
        guard case .failure(let error) = result, case .invalidInput = error else {
            return XCTFail("expected invalidInput failure, got \(result)")
        }
    }

    func testBadTimeoutFails() {
        let result = CLIConfig.parse(arguments: ["--timeout", "zero"], environment: [:])
        guard case .failure(let error) = result, case .invalidInput = error else {
            return XCTFail("expected invalidInput failure, got \(result)")
        }
    }

    // MARK: - SSH argument construction

    func testSSHArgumentsIncludeSafetyOptionsIdentityAndTarget() throws {
        let parsed = CLIConfig.parse(
            arguments: ["vm", "--identity", "/home/x/.ssh/id_ed25519", "--ssh-arg", "-v"],
            environment: [:]
        )
        guard case .success(let (_, config)) = parsed else {
            return XCTFail("expected success, got \(parsed)")
        }
        let destination = try XCTUnwrap(config.validatedDestination().successValue)
        let args = LinkProbe.sshArguments(config: config, destination: destination, remoteCommand: "echo hi")
        XCTAssertTrue(args.contains("BatchMode=yes"))
        XCTAssertTrue(args.contains("ConnectTimeout=10"))
        XCTAssertTrue(args.contains("/home/x/.ssh/id_ed25519"))
        XCTAssertEqual(Array(args.suffix(3)), ["-v", "ryuk@100.67.141.81", "echo hi"])
    }

    // MARK: - LinkProbe flow with a fake runner

    private final class FakeRunner: CommandRunning {
        var invocations: [(executable: String, arguments: [String])] = []
        var handler: (String, [String]) throws -> CommandOutput

        init(handler: @escaping (String, [String]) throws -> CommandOutput) {
            self.handler = handler
        }

        func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
            invocations.append((executable, arguments))
            return try handler(executable, arguments)
        }
    }

    func testProbeRunsSSHAndParsesTheReport() throws {
        let runner = FakeRunner { executable, _ in
            XCTAssertEqual(executable, "/usr/bin/ssh")
            return CommandOutput(exitCode: 0, stdout: "HOSTNAME=omegaubuntu\nOS=Ubuntu 24.04.3 LTS\n", stderr: "")
        }
        let probe = LinkProbe(runner: runner)
        let config = CLIConfig(user: "ryuk", host: "100.67.141.81", identityFile: nil, extraSSHArguments: [], connectTimeoutSeconds: 10)
        let report = try probe.probeVM(config: config)
        XCTAssertEqual(report.hostname, "omegaubuntu")
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(runner.invocations.first?.arguments.last, LinkProbe.remoteProbeCommand)
    }

    func testProbeSurfacesSSHFailureAsDarkstarError() {
        let runner = FakeRunner { _, _ in
            throw DarkstarError.commandFailed(executable: "/usr/bin/ssh", exitCode: 255, output: "ssh: connect to host port 22: Connection refused")
        }
        let probe = LinkProbe(runner: runner)
        let config = CLIConfig(user: "ryuk", host: "100.67.141.81", identityFile: nil, extraSSHArguments: [], connectTimeoutSeconds: 10)
        XCTAssertThrowsError(try probe.probeVM(config: config)) { error in
            guard let darkstarError = error as? DarkstarError, case .commandFailed = darkstarError else {
                return XCTFail("expected DarkstarError.commandFailed, got \(error)")
            }
        }
    }

    func testProbeRejectsUnsafeDestinationBeforeRunning() {
        let runner = FakeRunner { _, _ in
            XCTFail("runner must not be invoked for an unsafe destination")
            return CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }
        let probe = LinkProbe(runner: runner)
        let config = CLIConfig(user: "ryuk", host: "bad host", identityFile: nil, extraSSHArguments: [], connectTimeoutSeconds: 10)
        XCTAssertThrowsError(try probe.probeVM(config: config))
        XCTAssertTrue(runner.invocations.isEmpty)
    }
}

private extension Result {
    var successValue: Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}

// MARK: - Live runtime Preflight (RuntimeStackAssessment + schedule)

final class RuntimeStackAssessmentTests: XCTestCase {
    /// Captured from the real Omega-Ubuntu runtime on 2026-11-08.
    static let healthyOutput = """
        HOSTNAME=omegaubuntu
        OS=Ubuntu 24.04.5 LTS
        ARCH=aarch64
        KERNEL=6.8.0-149-generic
        UPTIME=up 30 minutes
        DF=/dev/mapper/ubuntu--vg-ubuntu--lv    62717884 24537664  35289256      42% /
        ROS=jazzy
        GZ=Gazebo Sim, version 8.15.0
        DOCKER=absent
        ROS2CLI=absent
        PX4=/home/ryuk/PX4-Autonomous-Missions,/home/ryuk/PX4-Autopilot
        ROS2BIN=/opt/ros/jazzy/bin/ros2
        PX4SITL=built
        XRCE=/usr/local/bin/MicroXRCEAgent
        """

    private func statuses(_ rows: [RuntimeStackCheck]) -> [RuntimeStackCheck.Item: PreflightRuleStatus] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.item, $0.status) })
    }

    func testNewProbeFieldsParse() {
        let r = RemoteReport.parse(Self.healthyOutput)
        XCTAssertEqual(r.ros2Binaries, ["/opt/ros/jazzy/bin/ros2"])
        XCTAssertEqual(r.px4SITLBuilt, true)
        XCTAssertEqual(r.xrceAgentPath, "/usr/local/bin/MicroXRCEAgent")
        XCTAssertEqual(r.diskFreeKB, 35_289_256, "df columns are split on runs of spaces")
    }

    func testHealthyRuntimePassesEveryRowInOrder() {
        let rows = RuntimeStackAssessment.assess(RemoteReport.parse(Self.healthyOutput))
        XCTAssertEqual(rows.map(\.item), RuntimeStackCheck.Item.allCases)
        XCTAssertTrue(rows.allSatisfy { $0.status == .pass }, "\(rows)")
        XCTAssertTrue(rows[0].detail.contains("omegaubuntu"))
        XCTAssertTrue(rows[1].detail.hasPrefix("33.7 GB free of 59.8 GB"))
        XCTAssertEqual(rows[3].detail, "Gazebo Sim, version 8.15.0")
    }

    func testFreshUbuntuFailsWithTheFix() {
        let fresh = RemoteReport.parse("""
            HOSTNAME=newvm
            DF=/dev/mapper/ubuntu--vg-ubuntu--lv 30859776 10000000 20859776 33% /
            ROS=
            GZ=
            PX4=
            ROS2BIN=
            PX4SITL=absent
            XRCE=absent
            """)
        let s = statuses(RuntimeStackAssessment.assess(fresh))
        XCTAssertEqual(s[.ssh], .pass)
        XCTAssertEqual(s[.disk], .warn)          // 19.9 GB: below 25, above 15
        XCTAssertEqual(s[.ros2], .fail)
        XCTAssertEqual(s[.gazebo], .fail)
        XCTAssertEqual(s[.px4], .fail)
        XCTAssertEqual(s[.xrce], .fail)
        XCTAssertTrue(RuntimeStackAssessment.assess(fresh).filter { $0.status == .fail }
            .allSatisfy { $0.detail.contains("bash dev.sh runtime") })
    }

    func testPartialInstallsWarnInsteadOfPassing() {
        let partial = RemoteReport.parse("""
            ROS=humble,jazzy
            ROS2BIN=/opt/ros/humble/bin/ros2
            GZ=Gazebo Sim, version 9.0.0
            PX4=/home/ryuk/PX4-Autopilot
            PX4SITL=absent
            XRCE=absent
            """)
        let s = statuses(RuntimeStackAssessment.assess(partial))
        XCTAssertEqual(s[.ros2], .warn, "jazzy dir without its ros2 binary is incomplete")
        XCTAssertEqual(s[.gazebo], .warn, "gz-sim 9 is not the validated Harmonic pairing")
        XCTAssertEqual(s[.px4], .warn, "source present, SITL not built")
        XCTAssertEqual(s[.disk], .unknown, "no DF line means unknown, not fail")

        let otherDistro = RemoteReport.parse("ROS=humble\nROS2BIN=/opt/ros/humble/bin/ros2")
        XCTAssertEqual(statuses(RuntimeStackAssessment.assess(otherDistro))[.ros2], .warn)
    }

    func testOlderProbeWithoutNewFieldsIsUnknownNotFail() {
        // Same output an older darkstar CLI produced: no PX4SITL / XRCE keys.
        let old = RemoteReport.parse("ROS=jazzy\nGZ=Gazebo Sim, version 8.15.0\nPX4=/home/ryuk/PX4-Autopilot")
        let s = statuses(RuntimeStackAssessment.assess(old))
        XCTAssertEqual(s[.px4], .unknown)
        XCTAssertEqual(s[.xrce], .unknown)
    }

    func testNothingIsTrustedUnlessTheRuntimeIsAnswering() {
        let stale = RuntimeStackProbeResult.report(RemoteReport.parse(Self.healthyOutput), at: Date())
        for health in [RuntimeHealth.notRunning, .booting(elapsedSeconds: 10), .unverified] {
            let rows = RuntimeStackAssessment.checks(health: health, result: stale)
            XCTAssertEqual(rows.count, RuntimeStackCheck.Item.allCases.count)
            XCTAssertTrue(rows.allSatisfy { $0.status == .unknown }, "\(health): \(rows)")
        }
        XCTAssertTrue(RuntimeStackAssessment.checks(health: .unverified, result: stale)[0].detail.contains("Tailscale"))
        XCTAssertTrue(RuntimeStackAssessment.checks(health: .notRunning, result: nil)[0].detail.contains("start it"))

        let hung = RuntimeStackAssessment.checks(health: .unresponsive(elapsedSeconds: 200, lastError: nil), result: stale)
        XCTAssertEqual(hung[0].status, .fail)
        XCTAssertTrue(hung.dropFirst().allSatisfy { $0.status == .unknown })
    }

    func testResponsiveWithoutAResultYetSaysChecking() {
        let rows = RuntimeStackAssessment.checks(health: .responsive, result: nil)
        XCTAssertTrue(rows.allSatisfy { $0.status == .unknown && $0.detail.contains("Checking") })
    }

    func testProbeFailureIsShownOnTheSSHRowWithItsMessage() {
        let error = DarkstarError.commandTimedOut(executable: "/usr/bin/ssh", timeoutSeconds: 20)
        let rows = RuntimeStackAssessment.checks(health: .responsive, result: .failed(error, at: Date()))
        XCTAssertEqual(rows[0].status, .fail)
        XCTAssertEqual(rows[0].detail, error.displayMessage)
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.status == .unknown })
    }

    func testScheduleProbesOncePerMinuteOnDemandAndRightAfterBoot() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(RuntimeStackProbeSchedule.shouldProbe(health: .responsive, lastProbeAt: nil, now: t0, force: false, inFlight: false))
        XCTAssertFalse(RuntimeStackProbeSchedule.shouldProbe(health: .responsive, lastProbeAt: t0, now: t0.addingTimeInterval(59), force: false, inFlight: false))
        XCTAssertTrue(RuntimeStackProbeSchedule.shouldProbe(health: .responsive, lastProbeAt: t0, now: t0.addingTimeInterval(60), force: false, inFlight: false))
        XCTAssertTrue(RuntimeStackProbeSchedule.shouldProbe(health: .responsive, lastProbeAt: t0, now: t0.addingTimeInterval(1), force: true, inFlight: false))
        XCTAssertFalse(RuntimeStackProbeSchedule.shouldProbe(health: .responsive, lastProbeAt: nil, now: t0, force: true, inFlight: true), "never two probes at once")
        for health in [RuntimeHealth.notRunning, .booting(elapsedSeconds: 5), .unverified, .unresponsive(elapsedSeconds: 200, lastError: nil)] {
            XCTAssertFalse(RuntimeStackProbeSchedule.shouldProbe(health: health, lastProbeAt: nil, now: t0, force: true, inFlight: false), "\(health)")
        }
    }

    func testProbeThroughFakeSSHFeedsTheAssessment() throws {
        final class Runner: CommandRunning {
            var arguments: [String] = []
            func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
                self.arguments = arguments
                return CommandOutput(exitCode: 0, stdout: RuntimeStackAssessmentTests.healthyOutput, stderr: "")
            }
        }
        let runner = Runner()
        let config = CLIConfig(user: "ryuk", host: "100.67.141.81", connectTimeoutSeconds: 5)
        let report = try LinkProbe(runner: runner).probeVM(config: config, timeout: 20)
        let rows = RuntimeStackAssessment.checks(health: .responsive, result: .report(report, at: Date()))
        XCTAssertTrue(rows.allSatisfy { $0.status == .pass })
        XCTAssertTrue(runner.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(runner.arguments.contains("ConnectTimeout=5"))
        XCTAssertTrue(runner.arguments.last?.contains("PX4SITL=") ?? false)
    }
}
