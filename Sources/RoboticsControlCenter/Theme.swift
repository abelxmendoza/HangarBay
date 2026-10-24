import SwiftUI

/// Darkstar Robotics design tokens (rebrand palette, 2026-10-23).
/// Industrial cyberpunk × aerospace mission control, macOS-native manners.
/// Starfire is the brand/primary color ONLY; Alert Red is errors ONLY;
/// System Green is verified success ONLY; Signal Cyan is instrumentation.
enum HB {
    static let obsidian = Color(hex: 0x0A0F14)   // Void Black — main background
    static let gunmetal = Color(hex: 0x1F2937)   // Gunmetal — cards, elevated surfaces
    static let panel = Color(hex: 0x111821)      // Deep Slate — panels, navigation
    static let hairline = Color.white.opacity(0.09)
    static let signal = Color(hex: 0xFF4A2F)    // Starfire — primary actions, brand
    static let ember = Color(hex: 0xFF785A)      // Ember — hover, illuminated accents
    static let cyan = Color(hex: 0x00CFFF)       // Signal Cyan — information, instrumentation
    static let telemetry = Color(hex: 0x28D97A)  // System Green — verified success ONLY
    static let warning = Color(hex: 0xFFC857)    // Amber — warnings
    static let alert = Color(hex: 0xF64D4D)     // Alert Red — errors and failures ONLY
    static let frost = Color(hex: 0xE8EAF0)      // Ice White — primary typography
    static let steel = Color(hex: 0x8A97A8)      // Steel Gray — secondary typography
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The honesty taxonomy. Every status shown in the app carries one of
/// these states; nothing presents recorded or sample data as live.
enum EvidenceState: String, CaseIterable {
    case live = "LIVE"
    case recorded = "RECORDED"
    case demo = "DEMO"
    case pending = "PENDING"
    case unknown = "UNKNOWN"

    var color: Color {
        switch self {
        case .live: return HB.telemetry
        case .recorded: return HB.frost
        case .demo: return HB.warning
        case .pending, .unknown: return HB.steel
        }
    }
}

/// Small monospaced status pill: colored dot + tracked uppercase label.
/// Color is never the only signal — the label always names the state.
struct EvidenceChip: View {
    let state: EvidenceState
    var label: String?

    init(_ state: EvidenceState, label: String? = nil) {
        self.state = state
        self.label = label
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
            Text(label ?? state.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(state.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(state.color.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Status: \(label ?? state.rawValue)")
    }
}

/// The Darkstar Robotics mark (user-supplied brand art, bundled as a resource).
/// Shown in the sidebar brand block and big on the Dashboard landing.
struct BrandLogo: View {
    var height: CGFloat = 56
    var cornerRadius: CGFloat = 12

    var body: some View {
        if let url = Bundle.module.url(forResource: "hangar-bay-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(HB.hairline, lineWidth: 1))
                .accessibilityLabel("Darkstar Robotics logo")
        }
    }
}

/// Condensed uppercase section eyebrow, e.g. "COMMAND DECK / 01".
struct Eyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2.2)
            .foregroundStyle(HB.steel)
    }
}
