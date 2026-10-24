import SwiftUI
import WebKit

/// The viewer: watch flights and telemetry without leaving the app.
/// v0.1 embeds a web view pointed at the missions replay server; the
/// native telemetry viewer (Lichtblick lineage) replaces this later —
/// never a from-scratch graph stack.
struct ViewerView: View {
    @State private var urlText: String = "http://localhost:8000/demo/"
    @State private var loadedURL: URL? = URL(string: "http://localhost:8000/demo/")

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(.secondary)
                TextField("Viewer URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { loadedURL = URL(string: urlText) }
                Button("Load") { loadedURL = URL(string: urlText) }
                    .buttonStyle(.borderedProminent)
                EvidenceChip(.recorded, label: "REPLAY")
            }
            .padding(12)
            Divider()
            WebView(url: loadedURL)
            Text("Tip: serve the replay from the PX4 missions project — python3 -m http.server 8000 --directory web/replay — inside the runtime or on this Mac.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(8)
        }
        .background(HB.obsidian)
        .navigationTitle("Viewer")
    }
}

struct WebView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        if let url { view.load(URLRequest(url: url)) }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let url else { return }
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
