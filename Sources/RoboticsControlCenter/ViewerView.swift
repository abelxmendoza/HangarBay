import SwiftUI
import WebKit
import DarkstarCore

/// The viewer: watch flights and telemetry without leaving the app.
/// v0.1 embeds a web view pointed at the missions replay server; the
/// native telemetry viewer (Lichtblick lineage) replaces this later —
/// never a from-scratch graph stack.
///
/// Error-handling rule: a bad address, a blocked cleartext address, an
/// unreachable server, and a web-view navigation failure are different
/// problems and are reported differently. The viewer never sits blank and
/// silent when a load has failed.
struct ViewerView: View {
    @State private var urlText: String = ViewerURLPolicy.defaultReplayURLString
    @State private var loadedURL: URL? = ViewerURLPolicy.defaultReplayURL
    @State private var loadError: DarkstarError? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(.secondary)
                TextField("Viewer URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { load() }
                Button("Load") { load() }
                    .buttonStyle(.borderedProminent)
                EvidenceChip(.recorded, label: "REPLAY")
            }
            .padding(12)
            if let loadError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HB.alert)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loadError.userMessage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(HB.frost)
                        if let recovery = loadError.recoverySuggestion {
                            Text(recovery)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Dismiss") { self.loadError = nil }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(HB.panel)
            }
            Divider()
            WebView(url: loadedURL) { error in
                loadError = error
            }
            Text("Tip: serve the replay from the PX4 missions project — python3 -m http.server 8000 --directory web/replay — inside the runtime or on this Mac.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(8)
        }
        .background(HB.obsidian)
        .navigationTitle("Viewer")
    }

    private func load() {
        switch ViewerURLPolicy.validate(urlText) {
        case .success(let url):
            loadedURL = url
            loadError = nil
        case .failure(let error):
            loadedURL = nil
            loadError = error
        }
    }
}

struct WebView: NSViewRepresentable {
    let url: URL?
    var onError: (DarkstarError) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        if let url {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let url else {
            nsView.stopLoading()
            nsView.loadHTMLString("", baseURL: nil)
            return
        }
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onError(Self.map(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onError(Self.map(error))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.onError(.unknown("The viewer web content process stopped. Load the replay again."))
        }

        static func map(_ error: Error) -> DarkstarError {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                let failingURL = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
                    .flatMap(URL.init(string:))
                if nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
                    return .cleartextRemoteURL(host: failingURL?.host ?? "that address")
                }
                switch nsError.code {
                case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                    return .network("The replay server is not reachable at \(failingURL?.host ?? "that address"). Start the server, then load again.")
                case NSURLErrorTimedOut:
                    return .network("The replay server took too long to answer. Check that it is running, then load again.")
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return .network("The network connection was lost before the replay loaded.")
                default:
                    return .network(error.localizedDescription)
                }
            }
            return .unknown(error.localizedDescription)
        }
    }
}
