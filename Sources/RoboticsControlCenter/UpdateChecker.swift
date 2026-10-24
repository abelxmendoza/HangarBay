import Foundation

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let name: String?
}

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
final class UpdateChecker: ObservableObject {
    @Published var state: UpdateState = .notChecked
    static let currentVersion = "0.3.0"
    private let endpoint = URL(string: "https://api.github.com/repos/abelxmendoza/HangarBay/releases/latest")!

    func check() {
        state = .checking
        var req = URLRequest(url: endpoint)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.state = .failed("Check failed: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.state = .failed("Check failed: no response from GitHub.")
                    return
                }
                if http.statusCode == 404 {
                    self.state = .failed("No published releases yet — nothing to compare against.")
                    return
                }
                guard http.statusCode == 200, let data,
                      let rel = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    self.state = .failed("Check failed: unexpected response (\(http.statusCode)).")
                    return
                }
                let latest = rel.tag_name.hasPrefix("v") ? String(rel.tag_name.dropFirst()) : rel.tag_name
                if Self.isNewer(latest, than: Self.currentVersion), let url = URL(string: rel.html_url) {
                    self.state = .updateAvailable(version: latest, url: url)
                } else {
                    self.state = .upToDate(latest)
                }
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
