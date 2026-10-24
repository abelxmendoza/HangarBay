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
    }

    func testMissingFactsStayAbsent() {
        let report = RemoteReport.parse("HOSTNAME=only\nGARBAGE LINE\n")
        XCTAssertEqual(report.hostname, "only")
        XCTAssertNil(report.osName)
        XCTAssertNil(report.diskFreeKB)
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
