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
    @State private var selection: SidebarSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Hangar Bay")
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
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
    }
}
