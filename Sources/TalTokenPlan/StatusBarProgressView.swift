import AppKit

struct BillingSnapshot {
    var ratioPct: Double
    var remaining: Double
}

enum StatusBarState {
    case loading
    case notLoggedIn
    case data(BillingSnapshot)
}

final class StatusBarProgressView: NSView {
    private var state: StatusBarState = .loading

    private let horizontalPadding: CGFloat = 7
    private let verticalPadding: CGFloat = 3
    private let ringLineWidth: CGFloat = 2.0

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        switch state {
        case .notLoggedIn:
            return NSSize(width: 52, height: 16)
        case .loading:
            return NSSize(width: 40, height: 16)
        case .data(let billing):
            let settings = currentSettings()
            if settings.showProgressBar {
                return capsuleLayoutSize(for: billing, settings: settings)
            }
            if settings.showPercentage || settings.showRemaining {
                let text = displayText(billing: billing, settings: settings)
                let size = NSAttributedString(
                    string: text,
                    attributes: textAttributes(size: 9, weight: .semibold)
                ).size()
                return NSSize(width: ceil(size.width), height: 16)
            }
            return NSSize(width: 40, height: 16)
        }
    }

    private struct RenderSettings {
        var showPercentage: Bool
        var showProgressBar: Bool
        var showRemaining: Bool
    }

    private struct TextLayout {
        var lines: [String]
        var textSize: NSSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func currentSettings() -> RenderSettings {
        RenderSettings(
            showPercentage: AppSettings.showPercentage,
            showProgressBar: AppSettings.showProgressBar,
            showRemaining: AppSettings.showRemainingCost
        )
    }

    func update(state: StatusBarState) {
        self.state = state
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let settings = currentSettings()

        switch state {
        case .loading:
            drawCenteredPlainText("...", size: 10)
        case .notLoggedIn:
            drawCenteredPlainText("未登录", size: 10)
        case .data(let billing):
            if settings.showProgressBar {
                drawCapsuleLayout(billing: billing, settings: settings)
            } else if settings.showPercentage || settings.showRemaining {
                drawTextOnlyLayout(billing: billing, settings: settings)
            } else {
                drawCenteredPlainText("—", size: 10)
            }
        }
    }

    // MARK: - Capsule layout

    private func drawCapsuleLayout(billing: BillingSnapshot, settings: RenderSettings) {
        let layout = measureText(billing: billing, settings: settings)
        let capsuleRect = NSRect(
            x: bounds.minX,
            y: (bounds.height - layout.textSize.height - verticalPadding * 2) / 2,
            width: bounds.width,
            height: layout.textSize.height + verticalPadding * 2
        )
        let cornerRadius = capsuleRect.height / 2

        drawRoundedRectRingProgress(ratio: billing.ratioPct / 100, in: capsuleRect, cornerRadius: cornerRadius)

        let textRect = capsuleRect.insetBy(dx: horizontalPadding, dy: verticalPadding)
        drawCenteredLines(layout.lines, in: textRect, singleSize: 9, dualPrimary: 8.5, dualSecondary: 8)
    }

    /// 圆角矩形环形进度：沿边框描边，背景透明；从顶部中点顺时针填充
    private func drawRoundedRectRingProgress(ratio: Double, in rect: NSRect, cornerRadius: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset = ringLineWidth / 2
        let strokeRect = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius - inset, strokeRect.height / 2, strokeRect.width / 2))
        let path = CGPath(
            roundedRect: strokeRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        let perimeter = ringPerimeter(of: strokeRect, radius: radius)
        let startPhase = ringPhaseToTopCenter(of: strokeRect, radius: radius)

        ctx.saveGState()
        ctx.setLineWidth(ringLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.addPath(path)
        ctx.setStrokeColor(trackRingColor.cgColor)
        ctx.strokePath()

        let clamped = max(0, min(1, ratio))
        if clamped > 0.001 {
            ctx.setLineDash(phase: startPhase, lengths: [perimeter * clamped, perimeter])
            ctx.addPath(path)
            ctx.setStrokeColor(progressRingColor.cgColor)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        ctx.restoreGState()
    }

    private func ringPerimeter(of rect: CGRect, radius: CGFloat) -> CGFloat {
        2 * (rect.width + rect.height - 4 * radius) + 2 * .pi * radius
    }

    /// CGPath 圆角矩形起点在左下，换算到顶部中点的相位
    private func ringPhaseToTopCenter(of rect: CGRect, radius: CGFloat) -> CGFloat {
        let straightW = rect.width - 2 * radius
        let straightH = rect.height - 2 * radius
        let quarterArc = .pi * radius / 2
        return straightW + quarterArc + straightH + quarterArc + straightW / 2
    }

    private func capsuleLayoutSize(for billing: BillingSnapshot, settings: RenderSettings) -> NSSize {
        let layout = measureText(billing: billing, settings: settings)
        let width = layout.textSize.width + horizontalPadding * 2 + ringLineWidth
        let height = layout.textSize.height + verticalPadding * 2 + ringLineWidth
        return NSSize(width: ceil(width), height: ceil(max(height, 18)))
    }

    private func measureText(billing: BillingSnapshot, settings: RenderSettings) -> TextLayout {
        let lines = innerTextLines(billing: billing, settings: settings)
        if lines.count <= 1 {
            let text = lines.first ?? "—"
            let size = NSAttributedString(string: text, attributes: textAttributes(size: 9, weight: .semibold)).size()
            return TextLayout(lines: lines, textSize: size)
        }

        let primary = NSAttributedString(string: lines[0], attributes: textAttributes(size: 8.5, weight: .semibold))
        let secondary = NSAttributedString(string: lines[1], attributes: textAttributes(size: 8, weight: .medium, secondary: true))
        let width = max(primary.size().width, secondary.size().width)
        let height = primary.size().height + 1 + secondary.size().height
        return TextLayout(lines: lines, textSize: NSSize(width: width, height: height))
    }

    // MARK: - Text-only layout

    private func drawTextOnlyLayout(billing: BillingSnapshot, settings: RenderSettings) {
        let text = displayText(billing: billing, settings: settings)
        drawCenteredPlainText(text, size: 9, weight: .semibold)
    }

    private func displayText(billing: BillingSnapshot, settings: RenderSettings) -> String {
        innerTextLines(billing: billing, settings: settings).joined(separator: "  ")
    }

    private func innerTextLines(billing: BillingSnapshot, settings: RenderSettings) -> [String] {
        var lines: [String] = []
        if settings.showPercentage {
            lines.append(String(format: "%.2f%%", billing.ratioPct))
        }
        if settings.showRemaining {
            lines.append(String(format: "¥%.1f", billing.remaining))
        }
        if lines.isEmpty {
            lines.append("—")
        }
        return lines
    }

    private func drawCenteredLines(
        _ lines: [String],
        in rect: NSRect,
        singleSize: CGFloat,
        dualPrimary: CGFloat,
        dualSecondary: CGFloat
    ) {
        guard !lines.isEmpty else { return }

        if lines.count == 1 {
            let str = NSAttributedString(string: lines[0], attributes: textAttributes(size: singleSize, weight: .semibold))
            str.draw(at: NSPoint(x: rect.midX - str.size().width / 2, y: rect.midY - str.size().height / 2))
            return
        }

        let primary = NSAttributedString(string: lines[0], attributes: textAttributes(size: dualPrimary, weight: .semibold))
        let secondary = NSAttributedString(string: lines[1], attributes: textAttributes(size: dualSecondary, weight: .medium, secondary: true))
        let gap: CGFloat = 1
        let totalHeight = primary.size().height + gap + secondary.size().height
        var y = rect.midY + totalHeight / 2 - primary.size().height

        primary.draw(at: NSPoint(x: rect.midX - primary.size().width / 2, y: y))
        y -= gap + secondary.size().height
        secondary.draw(at: NSPoint(x: rect.midX - secondary.size().width / 2, y: y))
    }

    private func drawCenteredPlainText(_ text: String, size: CGFloat, weight: NSFont.Weight = .medium) {
        let str = NSAttributedString(string: text, attributes: textAttributes(size: size, weight: weight))
        let point = NSPoint(
            x: bounds.midX - str.size().width / 2,
            y: (bounds.height - str.size().height) / 2
        )
        str.draw(at: point)
    }

    // MARK: - Appearance

    private func isDarkMenuBar(_ appearance: NSAppearance) -> Bool {
        let best = appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight])
        return best == .darkAqua || best == .vibrantDark
    }

    private var primaryTextColor: NSColor {
        NSColor(name: "StatusBarPrimaryText") { [weak self] appearance in
            guard let self else { return .labelColor }
            return self.isDarkMenuBar(appearance) ? .white : .black
        }
    }

    private var secondaryTextColor: NSColor {
        NSColor(name: "StatusBarSecondaryText") { [weak self] appearance in
            guard let self else { return .secondaryLabelColor }
            return self.isDarkMenuBar(appearance)
                ? NSColor(white: 1.0, alpha: 0.75)
                : NSColor(white: 0.0, alpha: 0.65)
        }
    }

    private var trackRingColor: NSColor {
        NSColor(name: "StatusBarTrackRing") { [weak self] appearance in
            guard let self else { return .separatorColor }
            return self.isDarkMenuBar(appearance)
                ? NSColor(white: 1.0, alpha: 0.30)
                : NSColor(white: 0.0, alpha: 0.20)
        }
    }

    private var progressRingColor: NSColor {
        NSColor(name: "StatusBarProgressRing") { [weak self] appearance in
            guard let self else { return .systemBlue }
            return self.isDarkMenuBar(appearance)
                ? NSColor(calibratedRed: 0.25, green: 0.58, blue: 0.98, alpha: 1.0)
                : NSColor(calibratedRed: 0.05, green: 0.32, blue: 0.78, alpha: 1.0)
        }
    }

    private func textAttributes(size: CGFloat, weight: NSFont.Weight, secondary: Bool = false) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: secondary ? secondaryTextColor : primaryTextColor,
        ]
    }
}
