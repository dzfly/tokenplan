import AppKit
import SwiftUI

// MARK: - 设置页视觉常量（对齐 codexU SettingsPanelView）

private enum SettingsMetrics {
    static let accessoryColumnWidth: CGFloat = 220
    static let controlCornerRadius: CGFloat = 8
    static let segmentHeight: CGFloat = 30
    static let controlVisualHeight: CGFloat = segmentHeight + 6
    static let sectionTitleFontSize: CGFloat = 12.5
    static let sectionDetailFontSize: CGFloat = 10
    static let rowTitleFontSize: CGFloat = 11.5
    static let rowDetailFontSize: CGFloat = 9.5
    static let controlFontSize: CGFloat = 11
}

private enum ControlPalette {
    static func fill(_ dark: Bool) -> Color { dark ? Color.white.opacity(0.085) : Color.white.opacity(0.52) }
    static func selectedFill(_ dark: Bool) -> Color { dark ? Color.white.opacity(0.18) : Color.black.opacity(0.105) }
    static func stroke(_ dark: Bool) -> Color { dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05) }
    static func cardFill(_ dark: Bool) -> Color { dark ? Color.white.opacity(0.05) : Color.white.opacity(0.45) }
    static func cardStroke(_ dark: Bool) -> Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
}

/// 玻璃窗口背景（对齐 codexU LiquidGlassWindowBackdrop）
private struct GlassBackdrop: View {
    let dark: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color.white.opacity(0.055), Color.clear, Color.black.opacity(0.10)]
                    : [Color.white.opacity(0.40), Color.white.opacity(0.10), Color.black.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(dark ? 0.05 : 0.35), Color.clear],
                center: UnitPoint(x: 0.88, y: 0.02),
                startRadius: 10,
                endRadius: 420
            )
        }
    }
}

// MARK: - 行与分区组件

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: SettingsMetrics.rowTitleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: SettingsMetrics.rowDetailFontSize, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
                .frame(width: SettingsMetrics.accessoryColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String
    let dark: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: SettingsMetrics.sectionTitleFontSize, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(detail)
                    .font(.system(size: SettingsMetrics.sectionDetailFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ControlPalette.cardFill(dark))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ControlPalette.cardStroke(dark), lineWidth: 0.8)
                )
        }
    }
}

private struct SettingsSegmentedControl: View {
    let dark: Bool
    let accent: Color
    @Binding var selection: String
    let options: [(value: String, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: SettingsMetrics.controlFontSize, weight: selection == option.value ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(selection == option.value ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.segmentHeight)
                        .background(
                            RoundedRectangle(cornerRadius: SettingsMetrics.controlCornerRadius, style: .continuous)
                                .fill(selection == option.value ? accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < options.count - 1 {
                    Rectangle()
                        .fill(ControlPalette.stroke(dark))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 1)
                }
            }
        }
        .padding(3)
        .frame(width: SettingsMetrics.accessoryColumnWidth, height: SettingsMetrics.controlVisualHeight)
        .background(
            RoundedRectangle(cornerRadius: SettingsMetrics.controlCornerRadius, style: .continuous)
                .fill(ControlPalette.fill(dark))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.controlCornerRadius, style: .continuous)
                        .strokeBorder(ControlPalette.stroke(dark), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.controlCornerRadius, style: .continuous))
    }
}

private struct StatusPreview: NSViewRepresentable {
    /// 持有 style 以便样式变化时触发 updateNSView（绘制本身读取全局设置）
    let style: StatusBarStyle

    func makeNSView(context: Context) -> StatusBarProgressView {
        let view = StatusBarProgressView(frame: NSRect(x: 0, y: 0, width: 10, height: 22))
        view.update(state: .data(Self.sample))
        return view
    }

    func updateNSView(_ view: StatusBarProgressView, context: Context) {
        view.update(state: .data(Self.sample))
    }

    private static let sample = BillingSnapshot(
        ratioPct: 45.20, remaining: 1234.5, used: 987.6, limit: 2222.1,
        maxModelUsed: 45.0, maxModelLimit: 100.0, maxModelRemaining: 55.0,
        maxModelRatioPct: 45.0
    )
}

// MARK: - 设置面板（SwiftUI，结构对齐 codexU SettingsPanelView）

private struct SettingsPanelView: View {
    @State private var appearance = AppSettings.appearanceMode.rawValue
    @State private var paletteID = AppSettings.paletteID
    @State private var style = AppSettings.statusBarStyle.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }
    private var accent: Color { DashboardTheme.current.accentPrimary }

    var body: some View {
        ZStack {
            GlassBackdrop(dark: dark)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsHeader
                    generalSection
                    menuBarSection
                    aboutSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(preferredScheme)
        .onChange(of: appearance) { newValue in
            AppSettings.appearanceMode = AppearanceMode(rawValue: newValue) ?? .dark
        }
        .onChange(of: paletteID) { newValue in
            AppSettings.paletteID = newValue
        }
        .onChange(of: style) { newValue in
            AppSettings.statusBarStyle = StatusBarStyle(rawValue: newValue) ?? .classic
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "system": return nil
        case "light": return .light
        default: return .dark
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("设置")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(AppInfo.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "通用", detail: "界面偏好", dark: dark) {
            SettingsRow(title: "外观", detail: "默认深色，可跟随系统") {
                SettingsSegmentedControl(
                    dark: dark,
                    accent: accent,
                    selection: $appearance,
                    options: [
                        (AppearanceMode.system.rawValue, "跟随系统"),
                        (AppearanceMode.light.rawValue, "浅色"),
                        (AppearanceMode.dark.rawValue, "深色"),
                    ]
                )
            }
            SettingsRow(title: "配色", detail: "精选内置配色，同时适配浅色与深色") {
                SettingsSegmentedControl(
                    dark: dark,
                    accent: accent,
                    selection: $paletteID,
                    options: DashboardTheme.all.map { ($0.id, $0.name) }
                )
            }
        }
    }

    private var menuBarSection: some View {
        SettingsSection(title: "状态栏", detail: "内容与显示密度", dark: dark) {
            SettingsRow(title: "显示样式", detail: "简约 / 经典 / 丰富") {
                SettingsSegmentedControl(
                    dark: dark,
                    accent: accent,
                    selection: $style,
                    options: StatusBarStyle.allCases.map { ($0.rawValue, $0.title) }
                )
            }
            SettingsRow(title: "实时预览", detail: "菜单栏中的实际效果") {
                StatusPreview(style: StatusBarStyle(rawValue: style) ?? .classic)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                    )
                    .frame(width: SettingsMetrics.accessoryColumnWidth, alignment: .center)
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "关于", detail: AppInfo.name, dark: dark) {
            SettingsRow(title: "版本", detail: "当前安装的版本") {
                Text("v\(AppInfo.version)")
                    .font(.system(size: SettingsMetrics.controlFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            SettingsRow(title: "检查更新", detail: "从发布源检查新版本") {
                Button {
                    AppUpdaterManager.shared.checkForUpdates()
                } label: {
                    Text("检查更新")
                        .font(.system(size: SettingsMetrics.controlFontSize, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: SettingsMetrics.controlCornerRadius, style: .continuous)
                                .fill(ControlPalette.fill(dark))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - 窗口壳（AppKit 毛玻璃 + SwiftUI 面板）

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "设置"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isOpaque = false
        win.backgroundColor = .clear
        win.minSize = NSSize(width: 500, height: 560)
        win.center()
        self.init(window: win)
        setupUI()
    }

    private func setupUI() {
        guard let container = window?.contentView else { return }
        DashboardTheme.apply()
        window?.appearance = AppSettings.appearanceMode.nsAppearance

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        let hostingView = NSHostingView(rootView: SettingsPanelView())
        hostingView.frame = effect.bounds
        hostingView.autoresizingMask = [.width, .height]
        effect.addSubview(hostingView)
    }

    func syncAppearance(_ mode: AppearanceMode) {
        DashboardTheme.apply()
        window?.appearance = mode.nsAppearance
    }

    func showSettings() {
        syncAppearance(AppSettings.appearanceMode)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
