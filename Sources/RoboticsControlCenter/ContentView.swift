import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case preflight = "Preflight"
    case environments = "Environments"
    case hardware = "Hardware"
    case missions = "Missions"
    case viewer = "Viewer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .preflight: return "checklist.checked"
        case .environments: return "square.stack.3d.up"
        case .hardware: return "cpu"
        case .missions: return "paperplane"
        case .viewer: return "waveform.path.ecg.rectangle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var runtime: RuntimeController
    @State private var selection: SidebarSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Hangar Bay")
            .safeAreaInset(edge: .top) {
                brandHeader
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if runtime.vmState == "Running" {
                        EvidenceChip(.live, label: "RUNTIME LIVE")
                    } else {
                        EvidenceChip(.unknown, label: "RUNTIME \(runtime.vmState.uppercased())")
                    }
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .preflight: PreflightView()
            case .environments: EnvironmentsView()
            case .hardware: HardwareView()
            case .missions: MissionsView()
            case .viewer: ViewerView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            BrandLogo(height: 54, cornerRadius: 10)
                .padding(.bottom, 4)
            Text("HANGAR BAY")
                .font(.system(.title3, design: .default).weight(.heavy))
                .tracking(2.4)
                .foregroundStyle(HB.frost)
            Eyebrow("AUTONOMOUS SYSTEMS CONTROL")
            Rectangle()
                .fill(HB.signal)
                .frame(width: 44, height: 2)
                .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
