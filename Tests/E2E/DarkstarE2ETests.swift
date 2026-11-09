import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DarkstarCore

// End-to-end tests: the real ProcessCommandRunner against real processes,
// real files, and a real local HTTP server. These are the tests that would
// have caught the 2026-10-24 demo failures before Abel did.

final class ProcessRunnerE2ETests: XCTestCase {
    private let runner = ProcessCommandRunner()

    func testRunsARealProcessAndCapturesOutput() throws {
        let output = try runner.run(executable: "/bin/echo", arguments: ["darkstar"], timeout: 5)
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(output.stdout.contains("darkstar"))
    }

    func testRealFailingProcessBecomesTypedCommandFailure() {
        XCTAssertThrowsError(try runner.runChecked(executable: "/usr/bin/false", arguments: [], timeout: 5)) { error in
            guard let darkstarError = error as? DarkstarError else { return XCTFail("Expected DarkstarError, got \(error)") }
            XCTAssertEqual(darkstarError.code, "command_failed")
        }
    }

    func testMissingExecutableBecomesCommandNotFound() {
        XCTAssertThrowsError(try runner.run(executable: "/definitely/missing/utmctl", arguments: ["list"], timeout: 5)) { error in
            XCTAssertEqual(error as? DarkstarError, .commandNotFound(executable: "/definitely/missing/utmctl"))
        }
    }

    func testSlowProcessIsTerminatedAtTimeout() {
        XCTAssertThrowsError(try runner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 1)) { error in
            guard let darkstarError = error as? DarkstarError else { return XCTFail("Expected DarkstarError, got \(error)") }
            XCTAssertEqual(darkstarError.code, "command_timed_out")
        }
    }
}

final class FakeUTMEndToEndTests: XCTestCase {
    private func makeExecutable(named name: String, body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("darkstar-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    func testProbeAgainstFakeUTMBinaryReportsRunning() throws {
        let utmctl = try makeExecutable(named: "utmctl", body: """
        #!/bin/sh
        echo "UUID STATUS NAME"
        echo "abc-123 started Omega-Ubuntu"
        """)
        let probe = RuntimeProbe(runner: ProcessCommandRunner())

        let status = probe.vmStatus(utmctlPath: utmctl.path, vmName: "Omega-Ubuntu")

        XCTAssertEqual(status, .running)
    }

    func testProbeAgainstFailingUTMBinarySurfacesItsOutput() throws {
        let utmctl = try makeExecutable(named: "utmctl", body: """
        #!/bin/sh
        echo "utmctl: internal error" >&2
        exit 3
        """)
        let probe = RuntimeProbe(runner: ProcessCommandRunner())

        let status = probe.vmStatus(utmctlPath: utmctl.path, vmName: "Omega-Ubuntu")

        guard case .probeFailed(let error) = status else { return XCTFail("Expected probeFailed, got \(status)") }
        XCTAssertTrue(error.diagnosticMessage.contains("internal error"))
    }

    func testProbeAgainstAbsentUTMBinaryReportsToolMissing() {
        let probe = RuntimeProbe(runner: ProcessCommandRunner())
        let status = probe.vmStatus(utmctlPath: "/tmp/darkstar-e2e-no-such-utmctl", vmName: "Omega-Ubuntu")
        XCTAssertEqual(status, .toolMissing(path: "/tmp/darkstar-e2e-no-such-utmctl"))
    }
}

final class LocalReplayServerE2ETests: XCTestCase {
    // Serves a stand-in replay page with a real HTTP server on localhost,
    // then walks the whole path the Viewer takes: policy validation, then
    // an actual HTTP fetch of the page.
    func testLocalReplayServerServesPageThatViewerPolicyAccepts() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("darkstar-replay-\(UUID().uuidString)")
        let demoDir = root.appendingPathComponent("demo")
        try fm.createDirectory(at: demoDir, withIntermediateDirectories: true)
        try "<html><title>Swarm Recovery — Golden Demo</title></html>"
            .write(to: demoDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: root) }

        let port = Int.random(in: 20000...29000)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", String(port), "--directory", root.path]
        server.standardOutput = Pipe()
        server.standardError = Pipe()
        do {
            try server.run()
        } catch {
            throw XCTSkip("python3 is not available to host the replay fixture: \(error.localizedDescription)")
        }
        defer { server.terminate() }

        let urlString = "http://127.0.0.1:\(port)/demo/"
        let validated = try ViewerURLPolicy.validate(urlString).get()
        XCTAssertEqual(validated.absoluteString, urlString)

        // Poll until the server answers, like a user retrying Load.
        let deadline = Date().addingTimeInterval(10)
        var body: String?
        while Date() < deadline {
            let fetched = expectation(description: "fetch attempt")
            var result: String?
            URLSession.shared.dataTask(with: validated) { data, response, _ in
                if let http = response as? HTTPURLResponse, http.statusCode == 200, let data {
                    result = String(data: data, encoding: .utf8)
                }
                fetched.fulfill()
            }.resume()
            wait(for: [fetched], timeout: 5)
            if let result {
                body = result
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        XCTAssertNotNil(body, "The local replay server never returned the demo page")
        XCTAssertTrue(body?.contains("Golden Demo") ?? false)
    }
}

final class RuntimeRecoveryE2ETests: XCTestCase {
    private func makeExecutable(named name: String, in dir: URL, body: String) throws -> URL {
        let file = dir.appendingPathComponent(name)
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("darkstar-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let destination = try! SSHDestination.validate(user: "ryuk", host: "100.67.141.81").get()

    func testRealProcessSSHAnswersAndAuthFailureBothCountAsUp() throws {
        let dir = try makeDir()
        let up = try makeExecutable(named: "ssh-up", in: dir, body: "#!/bin/sh\nexit 0\n")
        let noKey = try makeExecutable(named: "ssh-nokey", in: dir, body: "#!/bin/sh\necho 'ryuk@100.67.141.81: Permission denied (publickey,password).' >&2\nexit 255\n")
        let probe = RuntimeProbe(runner: ProcessCommandRunner())
        XCTAssertEqual(probe.sshReachability(destination: destination, sshPath: up.path), .answering)
        XCTAssertEqual(probe.sshReachability(destination: destination, sshPath: noKey.path), .answering)
    }

    func testRealProcessHungSSHIsKilledAndReportedNotAnswering() throws {
        let dir = try makeDir()
        let hung = try makeExecutable(named: "ssh-hung", in: dir, body: "#!/bin/sh\nsleep 30\n")
        let probe = RuntimeProbe(runner: ProcessCommandRunner())
        let started = Date()
        let reach = probe.sshReachability(destination: destination, sshPath: hung.path, connectTimeoutSeconds: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "the poll must not block on a hung ssh")
        guard case .notAnswering(let error) = reach else { return XCTFail("Expected notAnswering, got \(reach)") }
        XCTAssertEqual(error.code, "command_timed_out")
    }

    func testForceRestartAgainstStatefulFakeUTM() throws {
        let dir = try makeDir()
        let state = dir.appendingPathComponent("state")
        try "started".write(to: state, atomically: true, encoding: .utf8)
        let log = dir.appendingPathComponent("log")
        let utmctl = try makeExecutable(named: "utmctl", in: dir, body: """
        #!/bin/sh
        echo "$*" >> "\(log.path)"
        case "$1" in
          list) echo "UUID Status Name"; echo "abc $(cat "\(state.path)") Omega-Ubuntu" ;;
          stop) echo stopped > "\(state.path)" ;;
          start) echo started > "\(state.path)" ;;
        esac
        """)
        let probe = RuntimeProbe(runner: ProcessCommandRunner())

        let result = probe.forceRestartVM(utmctlPath: utmctl.path, vmName: "Omega-Ubuntu", sleep: { _ in })

        guard case .success = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(probe.vmStatus(utmctlPath: utmctl.path, vmName: "Omega-Ubuntu"), .running)
        let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(calls.prefix(3)), ["stop Omega-Ubuntu --force", "list", "start Omega-Ubuntu"])
    }
}
