import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DarkstarCore

// Integration tests: real DarkstarCore components composed together, with
// only the outermost boundary (process execution / HTTP transport) faked.
// No network, no UTM, and no Tailscale are touched.

private final class FakeCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var calls: [Call] = []
    var responses: [String: Result<CommandOutput, DarkstarError>] = [:]

    private func key(_ executable: String, _ arguments: [String]) -> String {
        executable + "|" + arguments.joined(separator: " ")
    }

    func stub(executable: String, arguments: [String], result: Result<CommandOutput, DarkstarError>) {
        responses[key(executable, arguments)] = result
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        calls.append(Call(executable: executable, arguments: arguments))
        if let result = responses[key(executable, arguments)] {
            return try result.get()
        }
        return CommandOutput(exitCode: 0, stdout: "", stderr: "")
    }
}

final class RuntimeProbeIntegrationTests: XCTestCase {
    private let utmctl = "/fake/UTM.app/Contents/MacOS/utmctl"
    private let tailscale = "/fake/Tailscale"

    func testProbeReportsRunningVMFromFakeUTM() {
        let runner = FakeCommandRunner()
        runner.stub(
            executable: utmctl,
            arguments: ["list"],
            result: .success(CommandOutput(
                exitCode: 0,
                stdout: "UUID STATUS NAME\nabc-123 started Omega-Ubuntu",
                stderr: ""
            ))
        )
        let probe = RuntimeProbe(runner: runner, fileExists: { _ in true })

        let status = probe.vmStatus(utmctlPath: utmctl, vmName: "Omega-Ubuntu")

        XCTAssertEqual(status, .running)
        XCTAssertEqual(PreflightRules.vmStatus(status), .pass)
        XCTAssertEqual(runner.calls, [FakeCommandRunner.Call(executable: utmctl, arguments: ["list"])])
    }

    func testProbeReportsToolMissingInsteadOfVagueUnavailable() {
        let runner = FakeCommandRunner()
        runner.stub(
            executable: utmctl,
            arguments: ["list"],
            result: .failure(.commandNotFound(executable: utmctl))
        )
        let probe = RuntimeProbe(runner: runner, fileExists: { _ in true })

        let status = probe.vmStatus(utmctlPath: utmctl, vmName: "Omega-Ubuntu")

        XCTAssertEqual(status, .toolMissing(path: utmctl))
        XCTAssertEqual(status.legacyState, "UTM control unavailable")
        XCTAssertTrue(status.detail.contains("Update UTM"))
    }

    func testProbeSurfacesUTMFailureOutput() {
        let runner = FakeCommandRunner()
        runner.stub(
            executable: utmctl,
            arguments: ["list"],
            result: .success(CommandOutput(exitCode: 9, stdout: "", stderr: "utmctl: VM registry locked"))
        )
        let probe = RuntimeProbe(runner: runner, fileExists: { _ in true })

        let status = probe.vmStatus(utmctlPath: utmctl, vmName: "Omega-Ubuntu")

        guard case .probeFailed(let error) = status else { return XCTFail("Expected probeFailed, got \(status)") }
        XCTAssertEqual(error.code, "command_failed")
        XCTAssertTrue(error.diagnosticMessage.contains("VM registry locked"))
        XCTAssertEqual(PreflightRules.vmStatus(status), .fail)
    }

    func testProbeReportsStoppedVMAsWarningNotFailure() {
        let runner = FakeCommandRunner()
        runner.stub(
            executable: utmctl,
            arguments: ["list"],
            result: .success(CommandOutput(exitCode: 0, stdout: "abc stopped Omega-Ubuntu", stderr: ""))
        )
        let probe = RuntimeProbe(runner: runner, fileExists: { _ in true })

        let status = probe.vmStatus(utmctlPath: utmctl, vmName: "Omega-Ubuntu")

        XCTAssertEqual(status, .stopped)
        XCTAssertEqual(PreflightRules.vmStatus(status), .warn)
    }

    func testTailscaleProbeUsesFirstInstalledCandidate() {
        let runner = FakeCommandRunner()
        runner.stub(
            executable: tailscale,
            arguments: ["status", "--json"],
            result: .success(CommandOutput(exitCode: 0, stdout: #"{"BackendState":"NeedsLogin"}"#, stderr: ""))
        )
        let probe = RuntimeProbe(runner: runner, fileExists: { $0 == "/fake/Tailscale" })

        let status = probe.tailscaleStatus(candidatePaths: ["/missing/tailscale", tailscale])

        XCTAssertEqual(status, .stopped(backendState: "NeedsLogin"))
        XCTAssertEqual(runner.calls.map(\.executable), [tailscale])
    }

    func testTailscaleProbeReportsNotInstalledWhenNoCandidateExists() {
        let runner = FakeCommandRunner()
        let probe = RuntimeProbe(runner: runner, fileExists: { _ in false })

        XCTAssertEqual(probe.tailscaleStatus(candidatePaths: ["/a", "/b"]), .notInstalled)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testTailscaleProbeSurfacesCommandFailure() {
        let runner = FakeCommandRunner()
        runner.stub(
            executable: tailscale,
            arguments: ["status", "--json"],
            result: .success(CommandOutput(exitCode: 1, stdout: "", stderr: "daemon not running"))
        )
        let probe = RuntimeProbe(runner: runner, fileExists: { _ in true })

        let status = probe.tailscaleStatus(candidatePaths: [tailscale])

        guard case .probeFailed(let error) = status else { return XCTFail("Expected probeFailed, got \(status)") }
        XCTAssertTrue(error.diagnosticMessage.contains("daemon not running"))
    }
}

// MARK: - HTTP transport integration (stubbed at URLProtocol)

private final class StubURLProtocol: URLProtocol {
    static var statusCode = 200
    static var body = Data()
    static var error: NSError? = nil

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UpdateFlowIntegrationTests: XCTestCase {
    private func fetchAndEvaluate(
        statusCode: Int,
        body: Data,
        error: NSError? = nil
    ) -> UpdateEvaluation {
        StubURLProtocol.statusCode = statusCode
        StubURLProtocol.body = body
        StubURLProtocol.error = error

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)

        let finished = expectation(description: "stubbed request finishes")
        var evaluation: UpdateEvaluation?
        let task = session.dataTask(with: URL(string: "https://api.github.com/repos/abelxmendoza/HangarBay/releases/latest")!) { data, response, taskError in
            evaluation = UpdateEvaluator.evaluate(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                data: data,
                networkErrorDescription: taskError?.localizedDescription,
                currentVersion: "0.3.0"
            )
            finished.fulfill()
        }
        task.resume()
        wait(for: [finished], timeout: 5)
        return evaluation!
    }

    func testStubbedGitHubResponseFlowsToUpdateAvailable() {
        let body = Data(#"{"tag_name":"v0.4.0","html_url":"https://github.com/abelxmendoza/HangarBay/releases/tag/v0.4.0","name":"v0.4.0"}"#.utf8)
        let evaluation = fetchAndEvaluate(statusCode: 200, body: body)
        XCTAssertEqual(
            evaluation,
            .updateAvailable(version: "0.4.0", url: URL(string: "https://github.com/abelxmendoza/HangarBay/releases/tag/v0.4.0")!)
        )
    }

    func testStubbed404FlowsToNoReleases() {
        XCTAssertEqual(fetchAndEvaluate(statusCode: 404, body: Data()), .noReleases)
    }

    func testTransportErrorFlowsToNetworkFailure() {
        let evaluation = fetchAndEvaluate(
            statusCode: 200,
            body: Data(),
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        )
        guard case .failed(let error) = evaluation else { return XCTFail("Expected failure, got \(evaluation)") }
        XCTAssertEqual(error.code, "network")
    }

    func testMalformedReleasePayloadFlowsToDecodingFailure() {
        let evaluation = fetchAndEvaluate(statusCode: 200, body: Data(#"{"unexpected":true}"#.utf8))
        guard case .failed(let error) = evaluation else { return XCTFail("Expected failure, got \(evaluation)") }
        XCTAssertEqual(error.code, "decoding")
    }
}

final class ViewerPolicyIntegrationTests: XCTestCase {
    // The exact failure from the 2026-10-24 demo session: the replay was
    // served from the runtime's Tailscale address and the viewer stayed
    // blank. The policy must refuse that address up front, with the fix.
    func testDemoFailureScenarioIsRefusedWithRecovery() {
        let result = ViewerURLPolicy.validate("http://100.67.141.81:8000/demo/")
        guard case .failure(let error) = result else { return XCTFail("Expected refusal") }
        XCTAssertEqual(error.code, "cleartext_remote_url")
        XCTAssertTrue(error.displayMessage.contains("localhost"))
    }

    func testReplayServedOnThisMacIsAccepted() {
        XCTAssertNoThrow(try ViewerURLPolicy.validate("http://localhost:8000/demo/").get())
    }
}
