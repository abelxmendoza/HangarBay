import SwiftUI

/// DARKSTAR design tokens — docs/DARKSTAR-UI-UX-PLAN.md.
/// Industrial cyberpunk × aerospace mission control, macOS-native manners.
/// Signal red is brand + alert ONLY; telemetry green is verified success ONLY.
enum HB {
    static let obsidian = Color(hex: 0x090D13)
    static let gunmetal = Color(hex: 0x1C2630)
    static let panel = Color(hex: 0x11181F)
    static let hairline = Color.white.opacity(0.09)
    static let signal = Color(hex: 0xFF553D)
    static let telemetry = Color(hex: 0x55D6A0)
    static let warning = Color(hex: 0xE8B44A)
    static let frost = Color(hex: 0xE9EEF3)
    static let steel = Color(hex: 0x8B98A5)
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

/// The Hangar Bay mark (user-supplied brand art, bundled as a resource).
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
                .accessibilityLabel("Hangar Bay logo")
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
