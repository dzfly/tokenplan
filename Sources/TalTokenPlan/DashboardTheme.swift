import SwiftUI
import AppKit

extension AppearanceMode {
    /// system 档返回 nil（跟随系统），light/dark 强制对应外观
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// 单一外观（明/暗）下的界面用色
struct SurfaceColors {
    /// 毛玻璃上的着色层
    let windowTint: Color
    let cardBackground: Color
    let cardStroke: Color
    let textPrimary: Color
    let textSecondary: Color
    let trackBackground: Color
    let accentPrimary: Color
    let accentSecondary: Color
    let progress: Color
    let ringGradient: LinearGradient
}

struct DashboardPalette {
    let id: String
    let name: String
    /// 设置色卡
    let swatchColors: [Color]
    let dark: SurfaceColors
    let light: SurfaceColors
}

enum DashboardTheme {
    static let defaultPaletteID = "deepsea"

    static let all: [DashboardPalette] = [.deepsea, .porcelain, .palace, .dunhuang]

    static var current: SurfaceColors = DashboardPalette.deepsea.dark
    static private(set) var currentPaletteID: String = defaultPaletteID
    static private(set) var isDark = true

    /// 按当前设置（外观 + 配色）重建用色
    static func apply() {
        let palette = all.first { $0.id == AppSettings.paletteID } ?? .deepsea
        currentPaletteID = palette.id
        switch AppSettings.appearanceMode {
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .light: isDark = false
        case .dark: isDark = true
        }
        current = isDark ? palette.dark : palette.light
    }

    // MARK: - 视图静态入口（保持既有调用点不变）

    static var windowBackground: Color { current.windowTint }
    static var cardBackground: Color { current.cardBackground }
    static var cardStroke: Color { current.cardStroke }
    static var textPrimary: Color { current.textPrimary }
    static var textSecondary: Color { current.textSecondary }
    static var trackBackground: Color { current.trackBackground }
    static var blue: Color { current.accentPrimary }
    static var purple: Color { current.accentSecondary }
    static var green: Color { current.progress }
    static var ringGradient: LinearGradient { current.ringGradient }

    // MARK: - 色板定义
}

extension DashboardPalette {
    fileprivate static func darkSurface(
        tint: Color, a1: Color, a2: Color, progress: Color
    ) -> SurfaceColors {
        SurfaceColors(
            windowTint: tint.opacity(0.45),
            cardBackground: Color.white.opacity(0.06),
            cardStroke: Color.white.opacity(0.10),
            textPrimary: Color.white.opacity(0.92),
            textSecondary: Color.white.opacity(0.55),
            trackBackground: Color.white.opacity(0.10),
            accentPrimary: a1,
            accentSecondary: a2,
            progress: progress,
            ringGradient: LinearGradient(colors: [a1, a2], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    fileprivate static func lightSurface(
        tint: Color, a1: Color, a2: Color, progress: Color
    ) -> SurfaceColors {
        SurfaceColors(
            windowTint: tint.opacity(0.45),
            cardBackground: Color.white.opacity(0.75),
            cardStroke: Color.black.opacity(0.08),
            textPrimary: Color.black.opacity(0.85),
            textSecondary: Color.black.opacity(0.50),
            trackBackground: Color.black.opacity(0.08),
            accentPrimary: a1,
            accentSecondary: a2,
            progress: progress,
            ringGradient: LinearGradient(colors: [a1, a2], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    fileprivate static func palette(
        id: String, name: String, tintD: Color, tintL: Color,
        a1: Color, a2: Color, progress: Color
    ) -> DashboardPalette {
        DashboardPalette(
            id: id,
            name: name,
            swatchColors: [a1, a2],
            dark: darkSurface(tint: tintD, a1: a1, a2: a2, progress: progress),
            light: lightSurface(tint: tintL, a1: a1, a2: a2, progress: progress)
        )
    }

    static let deepsea = palette(
        id: "deepsea", name: "深海蓝",
        tintD: Color(red: 0.043, green: 0.067, blue: 0.118), tintL: Color(red: 0.95, green: 0.96, blue: 0.97),
        a1: Color(red: 0.31, green: 0.56, blue: 0.97), a2: Color(red: 0.55, green: 0.36, blue: 0.96),
        progress: Color(red: 0.20, green: 0.78, blue: 0.35)
    )
    static let porcelain = palette(
        id: "porcelain", name: "青花瓷",
        tintD: Color(red: 0.045, green: 0.11, blue: 0.17), tintL: Color(red: 0.92, green: 0.96, blue: 0.97),
        a1: Color(red: 0.36, green: 0.72, blue: 0.90), a2: Color(red: 0.13, green: 0.42, blue: 0.72),
        progress: Color(red: 0.26, green: 0.76, blue: 0.76)
    )
    static let palace = palette(
        id: "palace", name: "故宫红",
        tintD: Color(red: 0.13, green: 0.045, blue: 0.05), tintL: Color(red: 0.97, green: 0.94, blue: 0.93),
        a1: Color(red: 0.86, green: 0.28, blue: 0.23), a2: Color(red: 0.92, green: 0.66, blue: 0.23),
        progress: Color(red: 0.95, green: 0.75, blue: 0.30)
    )
    static let dunhuang = palette(
        id: "dunhuang", name: "敦煌金",
        tintD: Color(red: 0.12, green: 0.085, blue: 0.045), tintL: Color(red: 0.97, green: 0.95, blue: 0.90),
        a1: Color(red: 0.93, green: 0.62, blue: 0.21), a2: Color(red: 0.80, green: 0.40, blue: 0.24),
        progress: Color(red: 0.55, green: 0.72, blue: 0.35)
    )
}

struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DashboardTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DashboardTheme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func dashboardCard() -> some View {
        modifier(DashboardCardModifier())
    }
}
