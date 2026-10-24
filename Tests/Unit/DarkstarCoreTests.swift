import XCTest
@testable import DarkstarCore

final class DarkstarErrorTests: XCTestCase {
    func testMissingUTMToolExplainsRecovery() {
        let error = DarkstarError.commandNotFound(executable: "/Applications/UTM.app/Contents/MacOS/utmctl")

        XCTAssertEqual(error.code, "command_not_found")
        XCTAssertTrue(error.userMessage.contains("utmctl"))
        XCTAssertTrue(error.displayMessage.contains("Update UTM"))
        XCTAssertFalse(error.isRetryable)
    }

    func testCommandFailureKeepsExitCodeAndOutput() {
        let error = DarkstarError.commandFailed(
            executable: "/tmp/fake-tool",
            exitCode: 42,
            output: "  the VM is locked  "
        )

        XCTAssertEqual(error.code, "command_failed")
        XCTAssertTrue(error.userMessage.contains("42"))
        XCTAssertTrue(error.diagnosticMessage.contains("the VM is locked"))
        XCTAssertTrue(error.isRetryable)
    }

    func testRetryabilityForHTTPStatuses() {
        XCTAssertTrue(DarkstarError.httpStatus(statusCode: 429, body: nil).isRetryable)
        XCTAssertTrue(DarkstarError.httpStatus(statusCode: 503, body: nil).isRetryable)
        XCTAssertFalse(DarkstarError.httpStatus(statusCode: 404, body: nil).isRetryable)
        XCTAssertFalse(DarkstarError.invalidURL("::::").isRetryable)
    }

    func testCommandOutputCombinesStreamsWithoutEmptyLines() {
        let output = CommandOutput(exitCode: 0, stdout: "hello\n", stderr: " warning \n")
        XCTAssertEqual(output.combinedOutput, "hello\nwarning")
        XCTAssertTrue(output.isSuccess)
    }
}

final class SemanticVersionTests: XCTestCase {
    func testParsesVPrefixedVersions() {
        XCTAssertEqual(SemanticVersion("v1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(SemanticVersion(" 0.3.0 ")?.components, [0, 3, 0])
    }

    func testComparisonPadsMissingComponentsWithZero() {
        XCTAssertTrue(SemanticVersion.isNewer("1.2.1", than: "1.2"))
        XCTAssertTrue(SemanticVersion.isNewer("1.3", than: "1.2.9"))
        XCTAssertFalse(SemanticVersion.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(SemanticVersion.isNewer("0.9.9", than: "1.0.0"))
    }

    func testInvalidVersionsAreRejected() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("1..2"))
        XCTAssertNil(SemanticVersion("1.two.3"))
        XCTAssertNil(SemanticVersion("version-1"))
        XCTAssertFalse(SemanticVersion.isNewer("latest", than: "1.0.0"))
    }

    func testBuildMetadataDoesNotChangeTheVersionCore() {
        XCTAssertEqual(SemanticVersion("1.2.3+build.7")?.components, [1, 2, 3])
    }
}

final class StatusParserTests: XCTestCase {
    private let header = "UUID                                 STATUS   NAME"

    func testUTMParserFindsRunningVM() {
        let output = "\(header)\n1234-uuid                            started  Omega-Ubuntu"
        XCTAssertEqual(UTMListParser.parse(output: output, vmName: "Omega-Ubuntu"), .running)
    }

    func testUTMParserFindsStoppedAndPausedVMs() {
        XCTAssertEqual(
            UTMListParser.parse(output: "abc stopped Omega-Ubuntu", vmName: "Omega-Ubuntu"),
            .stopped
        )
        XCTAssertEqual(
            UTMListParser.parse(output: "abc suspended Omega-Ubuntu", vmName: "Omega-Ubuntu"),
            .paused
        )
    }

    func testUTMParserDistinguishesMissingAndMalformedOutput() {
        XCTAssertEqual(
            UTMListParser.parse(output: "\(header)\nabc started Somebody-Elses-VM", vmName: "Omega-Ubuntu"),
            .notFound
        )
        XCTAssertEqual(UTMListParser.parse(output: "   \n", vmName: "Omega-Ubuntu"), .malformed(output: "   \n"))
    }

    func testUTMParserReturnsPresentForUnrecognizedState() {
        XCTAssertEqual(
            UTMListParser.parse(output: "abc teleporting Omega-Ubuntu", vmName: "Omega-Ubuntu"),
            .present
        )
    }

    func testTailscaleParserReadsBackendState() {
        XCTAssertEqual(TailscaleStatusParser.parse(output: #"{"BackendState":"Running"}"#), .connected)
        XCTAssertEqual(
            TailscaleStatusParser.parse(output: #"{"BackendState":"NeedsLogin"}"#),
            .stopped(backendState: "NeedsLogin")
        )
    }

    func testTailscaleParserRejectsMalformedJSON() {
        XCTAssertEqual(TailscaleStatusParser.parse(output: "not-json"), .malformed)
        XCTAssertEqual(TailscaleStatusParser.parse(output: #"{"Other":true}"#), .stopped(backendState: ""))
    }
}

final class UpdateEvaluatorTests: XCTestCase {
    private func releaseData(tag: String, url: String = "https://github.com/abelxmendoza/HangarBay/releases/tag/v1.0.0") -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)","name":"Release"}"#.utf8)
    }

    func testNetworkErrorWinsAndIsTyped() {
        let result = UpdateEvaluator.evaluate(
            statusCode: nil,
            data: nil,
            networkErrorDescription: "The Internet connection appears to be offline.",
            currentVersion: "0.3.0"
        )
        guard case .failed(let error) = result else { return XCTFail("Expected failed evaluation, got \(result)") }
        XCTAssertEqual(error.code, "network")
    }

    func testMissingResponseIsANetworkFailure() {
        let result = UpdateEvaluator.evaluate(statusCode: nil, data: nil, networkErrorDescription: nil, currentVersion: "0.3.0")
        guard case .failed(let error) = result else { return XCTFail("Expected failure") }
        XCTAssertEqual(error.code, "network")
    }

    func test404MeansNoPublishedReleases() {
        XCTAssertEqual(
            UpdateEvaluator.evaluate(statusCode: 404, data: nil, networkErrorDescription: nil, currentVersion: "0.3.0"),
            .noReleases
        )
    }

    func testServerErrorIsRetryableHTTPFailure() {
        let result = UpdateEvaluator.evaluate(statusCode: 503, data: Data("busy".utf8), networkErrorDescription: nil, currentVersion: "0.3.0")
        guard case .failed(let error) = result else { return XCTFail("Expected failure") }
        XCTAssertEqual(error, .httpStatus(statusCode: 503, body: "busy"))
        XCTAssertTrue(error.isRetryable)
    }

    func testInvalidJSONIsADecodingFailure() {
        let result = UpdateEvaluator.evaluate(statusCode: 200, data: Data("[]".utf8), networkErrorDescription: nil, currentVersion: "0.3.0")
        guard case .failed(let error) = result else { return XCTFail("Expected failure") }
        XCTAssertEqual(error.code, "decoding")
    }

    func testUpToDateAndUpdateAvailable() {
        XCTAssertEqual(
            UpdateEvaluator.evaluate(statusCode: 200, data: releaseData(tag: "v0.3.0"), networkErrorDescription: nil, currentVersion: "0.3.0"),
            .upToDate(latest: "0.3.0")
        )

        let newer = UpdateEvaluator.evaluate(
            statusCode: 200,
            data: releaseData(tag: "v0.4.0", url: "https://github.com/abelxmendoza/HangarBay/releases/tag/v0.4.0"),
            networkErrorDescription: nil,
            currentVersion: "0.3.0"
        )
        XCTAssertEqual(
            newer,
            .updateAvailable(version: "0.4.0", url: URL(string: "https://github.com/abelxmendoza/HangarBay/releases/tag/v0.4.0")!)
        )
    }

    func testReleaseWithNonHTTPSURLIsRejected() {
        let result = UpdateEvaluator.evaluate(
            statusCode: 200,
            data: releaseData(tag: "v9.9.9", url: "http://example.invalid/release"),
            networkErrorDescription: nil,
            currentVersion: "0.3.0"
        )
        guard case .failed(let error) = result else { return XCTFail("Expected failure") }
        XCTAssertEqual(error.code, "decoding")
    }
}

final class ViewerURLPolicyTests: XCTestCase {
    func testDefaultReplayURLIsValidLocalHTTP() {
        let result = ViewerURLPolicy.validate(ViewerURLPolicy.defaultReplayURLString)
        XCTAssertEqual(try? result.get(), ViewerURLPolicy.defaultReplayURL)
    }

    func testLocalHostsMayUseHTTP() {
        for raw in [
            "http://localhost:8000/demo/",
            "http://127.0.0.1:8000/demo/",
            "http://[::1]:8000/demo/",
            "http://omega.local:8000/demo/"
        ] {
            XCTAssertNoThrow(try ViewerURLPolicy.validate(raw).get(), raw)
        }
    }

    func testRemoteHTTPIsBlockedWithRecovery() {
        let result = ViewerURLPolicy.validate("http://100.67.141.81:8000/demo/")
        guard case .failure(let error) = result else { return XCTFail("Expected cleartext refusal") }
        XCTAssertEqual(error, .cleartextRemoteURL(host: "100.67.141.81"))
        XCTAssertTrue(error.displayMessage.contains("SSH tunnel"))
    }

    func testRemoteHTTPSIsAllowed() {
        XCTAssertNoThrow(try ViewerURLPolicy.validate("https://example.com/replay").get())
    }

    func testUnsupportedSchemesAndBadInputAreRejected() {
        guard case .failure(let emptyError) = ViewerURLPolicy.validate("   ") else { return XCTFail("Expected empty failure") }
        XCTAssertEqual(emptyError.code, "invalid_input")

        guard case .failure(let schemeError) = ViewerURLPolicy.validate("file:///tmp/replay.html") else {
            return XCTFail("Expected scheme failure")
        }
        XCTAssertEqual(schemeError, .unsupportedURLScheme("file"))

        guard case .failure(let invalidError) = ViewerURLPolicy.validate("not a url") else {
            return XCTFail("Expected invalid URL failure")
        }
        XCTAssertEqual(invalidError.code, "invalid_url")
    }
}

final class SSHDestinationTests: XCTestCase {
    func testValidDestination() {
        let result = SSHDestination.validate(user: " ryuk ", host: " 100.67.141.81 ")
        XCTAssertEqual(try? result.get(), SSHDestination(user: "ryuk", host: "100.67.141.81"))
        XCTAssertEqual((try? result.get())?.terminalCommand, "ssh ryuk@100.67.141.81")
    }

    func testEmptyAndInjectedDestinationsAreRejected() {
        for (user, host) in [("", "host"), ("ryuk", ""), ("ryuk; rm -rf /", "host"), ("ryuk", "host/name"), ("ry uk", "host")] {
            guard case .failure(let error) = SSHDestination.validate(user: user, host: host) else {
                return XCTFail("Expected rejection for \(user)/\(host)")
            }
            XCTAssertEqual(error.code, "invalid_input")
        }
    }
}

final class PreflightRulesTests: XCTestCase {
    func testMemoryThresholds() {
        XCTAssertEqual(PreflightRules.memoryStatus(installedGB: 0), .unknown)
        XCTAssertEqual(PreflightRules.memoryStatus(installedGB: 15.9), .warn)
        XCTAssertEqual(PreflightRules.memoryStatus(installedGB: 16), .pass)
    }

    func testDiskThresholdBoundaries() {
        XCTAssertEqual(PreflightRules.diskStatus(freeGB: nil), .unknown)
        XCTAssertEqual(PreflightRules.diskStatus(freeGB: -1), .unknown)
        XCTAssertEqual(PreflightRules.diskStatus(freeGB: 100), .pass)
        XCTAssertEqual(PreflightRules.diskStatus(freeGB: 99.9), .warn)
        XCTAssertEqual(PreflightRules.diskStatus(freeGB: 40), .warn)
        XCTAssertEqual(PreflightRules.diskStatus(freeGB: 39.9), .fail)
    }

    func testVMAndTailscaleMappings() {
        XCTAssertEqual(PreflightRules.vmStatus(.running), .pass)
        XCTAssertEqual(PreflightRules.vmStatus(.stopped), .warn)
        XCTAssertEqual(PreflightRules.vmStatus(.toolMissing(path: "/nope")), .fail)
        XCTAssertEqual(PreflightRules.tailscaleStatus(.connected), .pass)
        XCTAssertEqual(PreflightRules.tailscaleStatus(.stopped(backendState: "NeedsLogin")), .fail)
    }
}
