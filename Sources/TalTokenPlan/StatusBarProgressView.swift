import AppKit

struct BillingSnapshot {
    var ratioPct: Double
    var remaining: Double
    var used: Double
}

enum StatusBarState {
    case loading
    case notLoggedIn
    case data(BillingSnapshot)
}

final class StatusBarProgressView: NSView {
    private var state: StatusBarState = .loading

    private let horizontalPadding: CGFloat = 7
    private let verticalPadding: CGFloat = 2
    private let ringLineWidth: CGFloat = 2.0
    /// 状态栏固定高度，不随剩余费用显隐变化（容纳双行 8pt 文字）
    private let fixedBarHeight: CGFloat = 22
    private let primaryFontSize: CGFloat = 8.5
    private let secondaryFontSize: CGFloat = 8
    /// 从字体默认行高中裁掉的 leading，用于压紧双行间距
    private let lineHeightTrim: CGFloat = 0.5

    private func compactParagraphStyle(for font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let naturalHeight = font.ascender - font.descender + font.leading
        let tightHeight = max(font.pointSize, naturalHeight - lineHeightTrim)
        style.minimumLineHeight = tightHeight
        style.maximumLineHeight = tightHeight
        style.alignment = .center
        return style
    }

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        let height = fixedBarHeight
        switch state {
        case .notLoggedIn:
            return NSSize(width: 52, height: height)
        case .loading:
            return NSSize(width: 40, height: height)
        case .data(let billing):
            let settings = currentSettings()
            if settings.showProgressBar {
                return capsuleLayoutSize(for: billing, settings: settings, height: height)
            }
            if settings.showPercentage || settings.showRemaining {
                let text = displayText(billing: billing, settings: settings)
                let size = NSAttributedString(
                    string: text,
                    attributes: textAttributes(size: 9, weight: .semibold)
                ).size()
                return NSSize(width: ceil(size.width), height: height)
            }
            return NSSize(width: 40, height: height)
        }
    }

    private struct RenderSettings {
        var showPercentage: Bool
        var showProgressBar: Bool
        var showRemaining: Bool
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
        let lines = innerTextLines(billing: billing, settings: settings)
        let attr = capsuleTextAttributedString(lines: lines)
        let textSize = attr.size()

        let capsuleHeight = min(bounds.height, textSize.height + verticalPadding * 2)
        let capsuleRect = NSRect(
            x: bounds.minX,
            y: (bounds.height - capsuleHeight) / 2,
            width: bounds.width,
            height: capsuleHeight
        )
        let cornerRadius = capsuleRect.height / 2

        drawRoundedRectRingProgress(ratio: billing.ratioPct / 100, in: capsuleRect, cornerRadius: cornerRadius)

        let textRect = capsuleRect.insetBy(dx: horizontalPadding, dy: verticalPadding)
        attr.draw(in: NSRect(
            x: textRect.midX - textSize.width / 2,
            y: textRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        ))
    }

    /// 圆角矩形环形进度：沿边框描边，背景透明；从左侧中点顺时针填充
    private func drawRoundedRectRingProgress(ratio: Double, in rect: NSRect, cornerRadius: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset = ringLineWidth / 2
        let strokeRect = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius - inset, strokeRect.height / 2, strokeRect.width / 2))
        let path = clockwiseRoundedRectRingPath(from: strokeRect, radius: radius)
        let perimeter = ringPerimeter(of: strokeRect, radius: radius)

        ctx.saveGState()
        ctx.setLineWidth(ringLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.addPath(path)
        ctx.setStrokeColor(trackRingColor.cgColor)
        ctx.strokePath()

        let clamped = max(0, min(1, ratio))
        if clamped > 0.001 {
            ctx.setLineDash(phase: 0, lengths: [perimeter * clamped, perimeter])
            ctx.addPath(path)
            ctx.setStrokeColor(progressRingColor.cgColor)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        ctx.restoreGState()
    }

    /// 从左中点开始、顺时针的圆角矩形闭合路径
    private func clockwiseRoundedRectRingPath(from rect: CGRect, radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midY = rect.midY

        path.move(to: CGPoint(x: minX, y: midY))
        path.addLine(to: CGPoint(x: minX, y: maxY - r))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + r, y: maxY), radius: r)
        path.addLine(to: CGPoint(x: maxX - r, y: maxY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX, y: maxY - r), radius: r)
        path.addLine(to: CGPoint(x: maxX, y: minY + r))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX - r, y: minY), radius: r)
        path.addLine(to: CGPoint(x: minX + r, y: minY))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX, y: minY + r), radius: r)
        path.addLine(to: CGPoint(x: minX, y: midY))
        path.closeSubpath()
        return path
    }

    private func ringPerimeter(of rect: CGRect, radius: CGFloat) -> CGFloat {
        2 * (rect.width + rect.height - 4 * radius) + 2 * .pi * radius
    }

    private func capsuleLayoutSize(for billing: BillingSnapshot, settings: RenderSettings, height: CGFloat) -> NSSize {
        let lines = innerTextLines(billing: billing, settings: settings)
        let textSize = capsuleTextAttributedString(lines: lines).size()
        let width = textSize.width + horizontalPadding * 2 + ringLineWidth
        return NSSize(width: ceil(width), height: height)
    }

    private func capsuleTextAttributedString(lines: [String]) -> NSAttributedString {
        guard lines.count >= 2 else {
            return NSAttributedString(
                string: lines[0],
                attributes: textAttributes(size: primaryFontSize, weight: .semibold)
            )
        }
        let result = NSMutableAttributedString(
            string: lines[0],
            attributes: textAttributes(size: primaryFontSize, weight: .semibold)
        )
        result.append(NSAttributedString(
            string: "\n" + lines[1],
            attributes: textAttributes(size: secondaryFontSize, weight: .medium, secondary: true)
        ))
        return result
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
        } else {
            lines.append(String(format: "¥%.1f", billing.used))
        }
        if lines.isEmpty {
            lines.append("—")
        }
        return lines
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
            guard let self else { return .systemOrange }
            return self.isDarkMenuBar(appearance)
                ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.16, alpha: 1.0)
                : NSColor(calibratedRed: 0.90, green: 0.46, blue: 0.05, alpha: 1.0)
        }
    }

    private func textAttributes(size: CGFloat, weight: NSFont.Weight, secondary: Bool = false) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return [
            .font: font,
            .foregroundColor: secondary ? secondaryTextColor : primaryTextColor,
            .paragraphStyle: compactParagraphStyle(for: font),
        ]
    }
}
