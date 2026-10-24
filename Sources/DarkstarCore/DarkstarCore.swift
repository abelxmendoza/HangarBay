import Foundation

// MARK: - Typed application errors

/// A single error vocabulary for every external boundary Darkstar crosses:
/// local processes, files, HTTP, JSON, and user-entered destinations.
///
/// The important product rule is that an external failure must never be
/// collapsed into a vague state such as "not available" when the app knows
/// more. `userMessage` is safe to show in the UI, `diagnosticMessage` keeps
/// the details needed for debugging, and `recoverySuggestion` tells the user
/// what can be done next.
public enum DarkstarError: Error, Equatable, Sendable {
    case commandNotFound(executable: String)
    case commandLaunchFailed(executable: String, reason: String)
    case commandFailed(executable: String, exitCode: Int32, output: String)
    case commandTimedOut(executable: String, timeoutSeconds: Double)
    case fileNotFound(path: String)
    case permissionDenied(path: String, reason: String)
    case invalidURL(String)
    case unsupportedURLScheme(String?)
    case cleartextRemoteURL(host: String)
    case httpStatus(statusCode: Int, body: String?)
    case network(String)
    case decoding(String)
    case invalidInput(field: String, reason: String)
    case unknown(String)

    /// Stable machine-readable code for logs and tests.
    public var code: String {
        switch self {
        case .commandNotFound: return "command_not_found"
        case .commandLaunchFailed: return "command_launch_failed"
        case .commandFailed: return "command_failed"
        case .commandTimedOut: return "command_timed_out"
        case .fileNotFound: return "file_not_found"
        case .permissionDenied: return "permission_denied"
        case .invalidURL: return "invalid_url"
        case .unsupportedURLScheme: return "unsupported_url_scheme"
        case .cleartextRemoteURL: return "cleartext_remote_url"
        case .httpStatus: return "http_status"
        case .network: return "network"
        case .decoding: return "decoding"
        case .invalidInput: return "invalid_input"
        case .unknown: return "unknown"
        }
    }

    /// Concise copy that can be displayed directly to the user.
    public var userMessage: String {
        switch self {
        case .commandNotFound(let executable):
            return "A required command-line tool is missing: \((executable as NSString).lastPathComponent)."
        case .commandLaunchFailed(let executable, _):
            return "Darkstar could not launch \((executable as NSString).lastPathComponent)."
        case .commandFailed(let executable, let exitCode, _):
            return "\((executable as NSString).lastPathComponent) failed with exit code \(exitCode)."
        case .commandTimedOut(let executable, let seconds):
            return "\((executable as NSString).lastPathComponent) did not answer within \(Int(seconds)) seconds."
        case .fileNotFound(let path):
            return "A required file is missing: \(path)."
        case .permissionDenied(let path, _):
            return "Darkstar does not have permission to use \(path)."
        case .invalidURL(let value):
            return value.isEmpty ? "The URL is empty." : "The URL is not valid: \(value)."
        case .unsupportedURLScheme(let scheme):
            return "Darkstar cannot open the URL scheme \(scheme ?? "(missing)")."
        case .cleartextRemoteURL(let host):
            return "macOS blocks a plain-HTTP replay from the non-local address \(host) in this viewer."
        case .httpStatus(let statusCode, _):
            return "The server returned HTTP \(statusCode)."
        case .network(let reason):
            return reason
        case .decoding:
            return "The response from the server was not in the expected format."
        case .invalidInput(let field, let reason):
            return "\(field): \(reason)"
        case .unknown(let reason):
            return reason
        }
    }

    /// Longer detail retained for support, logs, and tests.
    public var diagnosticMessage: String {
        switch self {
        case .commandNotFound(let executable):
            return "Expected executable at \(executable), but no file exists there."
        case .commandLaunchFailed(let executable, let reason):
            return "Launching \(executable) failed: \(reason)"
        case .commandFailed(let executable, let exitCode, let output):
            let trimmed = Self.truncated(output, maxCharacters: 800)
            return trimmed.isEmpty
                ? "\(executable) exited with code \(exitCode) and produced no output."
                : "\(executable) exited with code \(exitCode). Output: \(trimmed)"
        case .commandTimedOut(let executable, let seconds):
            return "\(executable) exceeded the \(seconds)-second timeout and was terminated."
        case .fileNotFound(let path):
            return "No file exists at \(path)."
        case .permissionDenied(let path, let reason):
            return "Permission problem at \(path): \(reason)"
        case .invalidURL(let value):
            return "URL parsing failed for \(value.debugDescription)."
        case .unsupportedURLScheme(let scheme):
            return "Unsupported URL scheme: \(scheme ?? "nil")."
        case .cleartextRemoteURL(let host):
            return "Refused cleartext HTTP for remote host \(host); use localhost, an SSH tunnel, or HTTPS."
        case .httpStatus(let statusCode, let body):
            if let body, !body.isEmpty {
                return "HTTP \(statusCode). Body: \(Self.truncated(body, maxCharacters: 400))"
            }
            return "HTTP \(statusCode) with no response body."
        case .network(let reason):
            return "Network failure: \(reason)"
        case .decoding(let reason):
            return "Decoding failure: \(reason)"
        case .invalidInput(let field, let reason):
            return "Invalid input for \(field): \(reason)"
        case .unknown(let reason):
            return reason
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .commandNotFound(let executable) where executable.contains("utmctl"):
            return "This UTM build does not include utmctl. Update UTM, or start and stop the VM from inside UTM."
        case .commandNotFound:
            return "Install the missing tool or choose a component that does not require it."
        case .commandLaunchFailed, .commandFailed, .commandTimedOut:
            return "Try again after checking that the related app is running and responsive."
        case .fileNotFound:
            return "Install or restore the missing file, then run the check again."
        case .permissionDenied:
            return "Check the file permissions or macOS privacy settings, then try again."
        case .invalidURL, .unsupportedURLScheme, .invalidInput:
            return "Correct the value and try again."
        case .cleartextRemoteURL:
            return "Serve the replay on this Mac at localhost, open an SSH tunnel, or use an HTTPS address."
        case .httpStatus(let statusCode, _) where statusCode == 404:
            return "Check that the server is running and that the path is correct."
        case .httpStatus:
            return "Check the server and try again."
        case .network:
            return "Check the network or Tailscale connection and try again."
        case .decoding:
            return "Try again; if it repeats, the service response may have changed."
        case .unknown:
            return nil
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .commandFailed, .commandTimedOut, .network:
            return true
        case .httpStatus(let statusCode, _):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        default:
            return false
        }
    }

    /// The message shown in compact UI rows: explanation plus recovery when
    /// the recovery is short enough to be useful in place.
    public var displayMessage: String {
        if let recoverySuggestion {
            return "\(userMessage) \(recoverySuggestion)"
        }
        return userMessage
    }

    private static func truncated(_ value: String, maxCharacters: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(maxCharacters)) + "…"
    }
}

// MARK: - Process execution

public struct CommandOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public var isSuccess: Bool { exitCode == 0 }
}

public protocol CommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandOutput
}

public extension CommandRunning {
    func run(executable: String, arguments: [String]) throws -> CommandOutput {
        try run(executable: executable, arguments: arguments, timeout: 10)
    }

    /// Converts a non-zero process result into the typed error used by the
    /// rest of the app. A missing executable remains `commandNotFound`.
    func runChecked(executable: String, arguments: [String], timeout: TimeInterval = 10) throws -> CommandOutput {
        let output = try run(executable: executable, arguments: arguments, timeout: timeout)
        guard output.isSuccess else {
            throw DarkstarError.commandFailed(
                executable: executable,
                exitCode: output.exitCode,
                output: output.combinedOutput
            )
        }
        return output
    }
}

/// Foundation process runner. It distinguishes "the tool is not there" from
/// "the tool ran and failed" — the distinction the old RuntimeController
/// lost by returning only an integer and a string.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        let fm = FileManager.default
        guard fm.fileExists(atPath: executable) else {
            throw DarkstarError.commandNotFound(executable: executable)
        }
        guard fm.isExecutableFile(atPath: executable) else {
            throw DarkstarError.permissionDenied(path: executable, reason: "The file exists but is not executable.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw DarkstarError.commandLaunchFailed(executable: executable, reason: error.localizedDescription)
        }

        final class DataBox: @unchecked Sendable {
            var data = Data()
        }
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        // Wait for the process itself as well as its pipes: reading
        // terminationStatus before the process has registered its exit
        // traps in swift-corelibs-foundation (found by the E2E suite).
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 1)
            throw DarkstarError.commandTimedOut(executable: executable, timeoutSeconds: timeout)
        }

        return CommandOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBox.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.data, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - Runtime status parsing

public enum VMStatus: Equatable, Sendable {
    case running
    case stopped
    case paused
    case present
    case notFound
    case toolMissing(path: String)
    case probeFailed(DarkstarError)
    case malformed(output: String)

    public var legacyState: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .present: return "Present"
        case .notFound: return "Not found"
        case .toolMissing: return "UTM control unavailable"
        case .probeFailed: return "UTM probe failed"
        case .malformed: return "Unknown"
        }
    }

    public var detail: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .present: return "Present"
        case .notFound: return "Not found in UTM"
        case .toolMissing:
            return DarkstarError.commandNotFound(executable: "/Applications/UTM.app/Contents/MacOS/utmctl").displayMessage
        case .probeFailed(let error):
            return error.displayMessage
        case .malformed:
            return "UTM returned output Darkstar could not interpret."
        }
    }

    public var isRunning: Bool { self == .running }
}

public enum UTMListParser {
    public static func parse(output: String, vmName: String) -> VMStatus {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .malformed(output: output) }

        for rawLine in trimmed.split(separator: "\n") {
            let line = String(rawLine)
            guard line.contains(vmName) else { continue }
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 2 else { return .present }
            switch tokens[1].lowercased() {
            case "started", "running": return .running
            case "stopped": return .stopped
            case "paused", "suspended": return .paused
            default: return .present
            }
        }
        return .notFound
    }
}

public enum TailscaleStatus: Equatable, Sendable {
    case connected
    case stopped(backendState: String)
    case notInstalled
    case probeFailed(DarkstarError)
    case malformed

    public var legacyState: String {
        switch self {
        case .connected: return "Connected"
        case .stopped: return "Stopped"
        case .notInstalled: return "Not installed"
        case .probeFailed: return "Probe failed"
        case .malformed: return "Unknown"
        }
    }

    public var detail: String {
        switch self {
        case .connected: return "Connected"
        case .stopped(let state): return state.isEmpty ? "Stopped" : "Stopped (\(state))"
        case .notInstalled: return "Not installed"
        case .probeFailed(let error): return error.displayMessage
        case .malformed: return "Tailscale returned output Darkstar could not interpret."
        }
    }
}

public enum TailscaleStatusParser {
    public static func parse(output: String) -> TailscaleStatus {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return .malformed
        }
        let state = dict["BackendState"] as? String ?? ""
        return state == "Running" ? .connected : .stopped(backendState: state)
    }
}

/// Composes command execution and status parsing into the two runtime
/// probes the app performs. Keeping the composition in DarkstarCore means
/// the integration tests exercise the exact logic the app ships, with a
/// fake command runner in place of real processes.
public struct RuntimeProbe {
    private let runner: any CommandRunning
    private let fileExists: (String) -> Bool

    public init(runner: any CommandRunning, fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.runner = runner
        self.fileExists = fileExists
    }

    public func vmStatus(utmctlPath: String, vmName: String) -> VMStatus {
        do {
            let output = try runner.runChecked(executable: utmctlPath, arguments: ["list"], timeout: 10)
            return UTMListParser.parse(output: output.stdout, vmName: vmName)
        } catch let error as DarkstarError {
            if case .commandNotFound = error {
                return .toolMissing(path: utmctlPath)
            }
            return .probeFailed(error)
        } catch {
            return .probeFailed(.unknown(error.localizedDescription))
        }
    }

    public func tailscaleStatus(candidatePaths: [String]) -> TailscaleStatus {
        for path in candidatePaths where fileExists(path) {
            do {
                let output = try runner.runChecked(executable: path, arguments: ["status", "--json"], timeout: 10)
                return TailscaleStatusParser.parse(output: output.stdout)
            } catch let error as DarkstarError {
                return .probeFailed(error)
            } catch {
                return .probeFailed(.unknown(error.localizedDescription))
            }
        }
        return .notInstalled
    }
}

// MARK: - Semantic versions and update evaluation

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let components: [Int]
    public let original: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        // Build metadata does not affect precedence. A pre-release is kept
        // comparable by its numeric core; Darkstar release tags are simple
        // vX.Y.Z values, and refusing surprising input is safer than
        // pretending to rank it.
        let core = withoutPrefix.split(separator: "+").first.map(String.init) ?? withoutPrefix
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }), let value = Int(part) else { return nil }
            parsed.append(value)
        }
        self.components = parsed
        self.original = raw
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidateVersion = SemanticVersion(candidate),
              let currentVersion = SemanticVersion(current) else { return false }
        return candidateVersion > currentVersion
    }
}

public struct GitHubReleaseDTO: Decodable, Equatable, Sendable {
    public let tagName: String
    public let htmlURL: String
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
    }
}

public enum UpdateEvaluation: Equatable, Sendable {
    case upToDate(latest: String)
    case updateAvailable(version: String, url: URL)
    case noReleases
    case failed(DarkstarError)
}

public enum UpdateEvaluator {
    public static func evaluate(
        statusCode: Int?,
        data: Data?,
        networkErrorDescription: String?,
        currentVersion: String
    ) -> UpdateEvaluation {
        if let networkErrorDescription, !networkErrorDescription.isEmpty {
            return .failed(.network("Check failed: \(networkErrorDescription)"))
        }
        guard let statusCode else {
            return .failed(.network("Check failed: no response from GitHub."))
        }
        if statusCode == 404 {
            return .noReleases
        }
        guard statusCode == 200 else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            return .failed(.httpStatus(statusCode: statusCode, body: body))
        }
        guard let data else {
            return .failed(.decoding("GitHub returned an empty response."))
        }
        do {
            let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
            guard let url = URL(string: release.htmlURL), url.scheme == "https" else {
                return .failed(.decoding("GitHub returned a release without a valid HTTPS URL."))
            }
            let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            guard SemanticVersion(latest) != nil else {
                return .failed(.decoding("GitHub returned an unrecognized version tag: \(release.tagName)."))
            }
            if SemanticVersion.isNewer(latest, than: currentVersion) {
                return .updateAvailable(version: latest, url: url)
            }
            return .upToDate(latest: latest)
        } catch {
            return .failed(.decoding(error.localizedDescription))
        }
    }
}

// MARK: - Viewer URL policy

public enum ViewerURLPolicy {
    public static let defaultReplayURLString = "http://localhost:8000/demo/"

    public static var defaultReplayURL: URL {
        // Force-unwrapping a compile-time constant is intentional: if this
        // ever fails, the test suite catches a programming error, not a user
        // input problem.
        URL(string: defaultReplayURLString)!
    }

    public static func validate(_ rawValue: String?) -> Result<URL, DarkstarError> {
        let raw = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return .failure(.invalidInput(field: "Viewer URL", reason: "Enter the replay server address."))
        }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            return .failure(.invalidURL(raw))
        }
        guard scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedURLScheme(scheme))
        }
        guard let host = url.host, !host.isEmpty else {
            return .failure(.invalidInput(field: "Viewer URL", reason: "The address has no host."))
        }
        if scheme == "http", !isLocalHost(host) {
            return .failure(.cleartextRemoteURL(host: host))
        }
        return .success(url)
    }

    public static func isLocalHost(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
            || normalized.hasSuffix(".local")
    }
}

// MARK: - SSH destination validation

public struct SSHDestination: Equatable, Sendable {
    public let user: String
    public let host: String

    public static func validate(user: String, host: String) -> Result<SSHDestination, DarkstarError> {
        let cleanUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else {
            return .failure(.invalidInput(field: "SSH user", reason: "The user is empty."))
        }
        guard !cleanHost.isEmpty else {
            return .failure(.invalidInput(field: "SSH host", reason: "The host is empty."))
        }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "@;|&$`\\\"'<>"))
        guard cleanUser.rangeOfCharacter(from: forbidden) == nil else {
            return .failure(.invalidInput(field: "SSH user", reason: "The user contains characters that are not safe for a terminal command."))
        }
        guard cleanHost.rangeOfCharacter(from: forbidden) == nil, !cleanHost.contains("/") else {
            return .failure(.invalidInput(field: "SSH host", reason: "The host contains characters that are not safe for a terminal command."))
        }
        return .success(SSHDestination(user: cleanUser, host: cleanHost))
    }

    public var target: String { "\(user)@\(host)" }
    public var terminalCommand: String { "ssh \(target)" }
}

// MARK: - Preflight thresholds

public enum PreflightRuleStatus: Equatable, Sendable {
    case pass, warn, fail, unknown
}

public enum PreflightRules {
    public static func memoryStatus(installedGB: Double) -> PreflightRuleStatus {
        guard installedGB > 0 else { return .unknown }
        return installedGB >= 16 ? .pass : .warn
    }

    public static func diskStatus(freeGB: Double?) -> PreflightRuleStatus {
        guard let freeGB, freeGB >= 0 else { return .unknown }
        if freeGB >= 100 { return .pass }
        if freeGB >= 40 { return .warn }
        return .fail
    }

    public static func vmStatus(_ status: VMStatus) -> PreflightRuleStatus {
        switch status {
        case .running: return .pass
        case .stopped, .paused: return .warn
        case .present: return .unknown
        case .notFound, .toolMissing, .probeFailed, .malformed: return .fail
        }
    }

    public static func tailscaleStatus(_ status: TailscaleStatus) -> PreflightRuleStatus {
        switch status {
        case .connected: return .pass
        case .stopped: return .fail
        case .notInstalled, .probeFailed, .malformed: return .fail
        }
    }
}
