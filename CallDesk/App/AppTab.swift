import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case calling
    case statistics
    case boards
    case settings

    nonisolated var id: Self {
        self
    }

    nonisolated var title: String {
        switch self {
        case .calling:
            "叫号"
        case .statistics:
            String(localized: "数据")
        case .boards:
            String(localized: "面板")
        case .settings:
            String(localized: "设置")
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .calling:
            "speaker.wave.2.fill"
        case .statistics:
            "chart.line.uptrend.xyaxis"
        case .boards:
            "square.grid.2x2"
        case .settings:
            "gearshape"
        }
    }
}
