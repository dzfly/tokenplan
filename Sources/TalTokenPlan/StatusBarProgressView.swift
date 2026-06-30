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
    private let borderWidth: CGFloat = 1.5

    override var intrinsicContentSize: NSSize {
        switch state {
        case .notLoggedIn:
            return NSSize(width: 52, height: 16)
        case .loading:
            return NSSize(width: 40, height: 16)
        case .data(let billing):
            let settings = currentSettings()
            if settings.showProgressBar {
                return capsuleSize(for: billing, settings: settings)
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
        var textWidth: CGFloat
    }

    private struct TextLayout {
        var lines: [String]
        var textSize: NSSize
    }

    private func currentSettings() -> RenderSettings {
        let showPct = AppSettings.showPercentage
        let showBar = AppSettings.showProgressBar
        let showRem = AppSettings.showRemainingCost
        var width: CGFloat = 56
        if showRem && showPct { width = 96 }
        else if showRem { width = 72 }
        else if showPct { width = 56 }
        else { width = 40 }
        return RenderSettings(showPercentage: showPct, showProgressBar: showBar, showRemaining: showRem, textWidth: width)
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

        drawRoundedRectProgress(ratio: billing.ratioPct / 100, in: capsuleRect, cornerRadius: cornerRadius)

        let textRect = capsuleRect.insetBy(dx: horizontalPadding, dy: verticalPadding)
        drawCenteredLines(layout.lines, in: textRect, singleSize: 9, dualPrimary: 8.5, dualSecondary: 8)
    }

    private func drawRoundedRectProgress(ratio: Double, in rect: NSRect, cornerRadius: CGFloat) {
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        trackBackgroundColor.setFill()
        trackPath.fill()

        let clamped = max(0, min(1, ratio))
        if clamped > 0.001 {
            let progressWidth = max(rect.height, rect.width * CGFloat(clamped))
            let progressRect = NSRect(x: rect.minX, y: rect.minY, width: progressWidth, height: rect.height)

            NSGraphicsContext.saveGraphicsState()
            trackPath.addClip()
            let fillPath = NSBezierPath(roundedRect: progressRect, xRadius: cornerRadius, yRadius: cornerRadius)
            progressFillColor.setFill()
            fillPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        borderColor.setStroke()
        trackPath.lineWidth = borderWidth
        trackPath.stroke()
    }

    private func capsuleSize(for billing: BillingSnapshot, settings: RenderSettings) -> NSSize {
        let layout = measureText(billing: billing, settings: settings)
        let width = layout.textSize.width + horizontalPadding * 2 + borderWidth
        let height = layout.textSize.height + verticalPadding * 2 + borderWidth
        return NSSize(width: ceil(width), height: ceil(max(height, 18)))
    }

    private func measureText(billing: BillingSnapshot, settings: RenderSettings) -> TextLayout {
        let lines = innerTextLines(billing: billing, settings: settings)
        if lines.count <= 1 {
            let text = lines.first ?? "—"
            let attrs = textAttributes(size: 9, weight: .semibold)
            let size = NSAttributedString(string: text, attributes: attrs).size()
            return TextLayout(lines: lines, textSize: size)
        }

        let primary = NSAttributedString(string: lines[0], attributes: textAttributes(size: 8.5, weight: .semibold))
        let secondary = NSAttributedString(string: lines[1], attributes: textAttributes(size: 8, weight: .medium))
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
            lines.append(String(format: "%.1f%%", billing.ratioPct))
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
        let secondary = NSAttributedString(string: lines[1], attributes: textAttributes(size: dualSecondary, weight: .medium))
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

    private func textAttributes(size: CGFloat, weight: NSFont.Weight) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private var trackBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.38, alpha: 0.45)
                : NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1)
        }
    }

    private var progressFillColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.35, green: 0.58, blue: 0.82, alpha: 0.55)
                : NSColor(calibratedRed: 0.72, green: 0.87, blue: 1.0, alpha: 1)
        }
    }

    private var borderColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.45, green: 0.68, blue: 0.95, alpha: 0.85)
                : NSColor(calibratedRed: 0.45, green: 0.70, blue: 0.98, alpha: 1)
        }
    }
}
