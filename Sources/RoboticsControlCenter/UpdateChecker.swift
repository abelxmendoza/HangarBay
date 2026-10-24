import Foundation
import DarkstarCore

enum UpdateState: Equatable {
    case notChecked
    case checking
    case upToDate(String)
    case updateAvailable(version: String, url: URL)
    case failed(String)
}

/// Honest, on-demand update check against GitHub Releases.
/// No background polling: a check runs only when the user presses the button,
/// and the UI reports exactly what the check found — including failure.
///
/// All response classification lives in DarkstarCore's `UpdateEvaluator`, so
/// the network, HTTP, decoding, no-release, and version-comparison branches
/// are unit-tested without touching GitHub.
final class UpdateChecker: ObservableObject {
    @Published var state: UpdateState = .notChecked
    static let currentVersion = "0.4.0"
    private let endpoint = URL(string: "https://api.github.com/repos/abelxmendoza/HangarBay/releases/latest")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check() {
        state = .checking
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            let evaluation = UpdateEvaluator.evaluate(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                data: data,
                networkErrorDescription: error?.localizedDescription,
                currentVersion: Self.currentVersion
            )
            DispatchQueue.main.async {
                guard let self else { return }
                switch evaluation {
                case .upToDate(let latest):
                    self.state = .upToDate(latest)
                case .updateAvailable(let version, let url):
                    self.state = .updateAvailable(version: version, url: url)
                case .noReleases:
                    self.state = .failed("No published releases yet — nothing to compare against.")
                case .failed(let darkstarError):
                    self.state = .failed(Self.message(for: darkstarError))
                }
            }
        }.resume()
    }

    private static func message(for error: DarkstarError) -> String {
        switch error {
        case .network(let reason):
            return reason.hasPrefix("Check failed:") ? reason : "Check failed: \(reason)"
        case .httpStatus(let statusCode, _):
            return "Check failed: unexpected response (\(statusCode))."
        case .decoding:
            return "Check failed: GitHub returned a response Darkstar could not read."
        default:
            return "Check failed: \(error.userMessage)"
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        SemanticVersion.isNewer(candidate, than: current)
    }
}
