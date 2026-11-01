import AppKit

extension Notification.Name {
    /// Focus, keep awake, notes or shortcuts changed.
    static let toolbeltChanged = Notification.Name("ToolbeltChanged")
    /// The clipboard history changed. Separate so the list doesn't reload every focus tick.
    static let clipboardChanged = Notification.Name("ToolbeltClipboardChanged")
}

enum UI {
    static func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func wrapping(_ text: String, size: CGFloat = 13, color: NSColor = .secondaryLabelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        return field
    }

    static func button(_ title: String, symbol: String? = nil, color: NSColor? = nil,
                       target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        if let symbol, let image = UI.symbol(symbol, size: 12, color: color == nil ? .labelColor : .white) {
            button.image = image
            button.imagePosition = .imageLeading
        }
        if let color { button.bezelColor = color }
        return button
    }

    static func hStack(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        return stack
    }

    static func vStack(_ views: [NSView], spacing: CGFloat = 10, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = alignment
        return stack
    }

    /// Pins `view` to every edge of `container`, inset by `padding`.
    static func pin(_ view: NSView, in container: NSView, padding: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])
    }
}

/// A rounded panel in the window background colour, like the cards in System Settings.
final class CardView: NSView {
    init(_ content: NSView? = nil, padding: CGFloat = 18) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        if let content { UI.pin(content, in: self, padding: padding) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    // updateLayer runs with the current appearance, so dynamic colours resolve for light and dark mode.
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
    }
}

/// Rounded card with a fixed diagonal gradient, the same in light and dark mode.
final class GradientView: NSView {
    private let colors: [CGColor]

    init(colors: [NSColor]) {
        self.colors = colors.map(\.cgColor)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        gradient.colors = colors
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        return gradient
    }
}

/// A translucent white button for use on a gradient.
final class HeroButton: NSButton {
    init(_ title: String, symbol: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        image = UI.symbol(symbol, size: 12, color: .white)
        imagePosition = .imageLeading
        setTitle(title)
        heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setTitle(_ text: String) {
        attributedTitle = NSAttributedString(string: "  \(text)  ", attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ])
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// A thin rounded bar from 0 to 1.
final class ProgressBar: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor { didSet { needsDisplay = true } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 8).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let width = bounds.width * CGFloat(min(max(value, 0), 1))
        guard width > 0 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(width, bounds.height), height: bounds.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

/// A circular countdown with the time in the middle.
final class RingView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    let timeLabel = UI.label("25:00", size: 48, weight: .semibold)
    let caption = UI.label("Ready", size: 14, weight: .medium, color: .secondaryLabelColor)

    init() {
        super.init(frame: .zero)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .semibold)
        let stack = UI.vStack([timeLabel, caption], spacing: 2, alignment: .centerX)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = 14
        let rect = bounds.insetBy(dx: lineWidth / 2 + 2, dy: lineWidth / 2 + 2)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.15).setStroke()
        track.stroke()

        guard progress > 0 else { return }
        let arc = NSBezierPath()
        // Clockwise from 12 o'clock.
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(min(progress, 1)), clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }
}

/// Simple vertical bars with a label under each.
final class BarChart: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var labels: [String] = [] { didSet { needsDisplay = true } }
    var highlightLast = true
    var color: NSColor = .systemRed
    var emptyText = "Nothing yet"

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        let labelHeight: CGFloat = 18
        if values.allSatisfy({ $0 == 0 }) {
            let text = emptyText as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.midY), withAttributes: attributes)
        }
        let chart = NSRect(x: 0, y: labelHeight, width: bounds.width, height: bounds.height - labelHeight)
        let slot = chart.width / CGFloat(values.count)
        let barWidth = min(28, slot * 0.6)
        let top = max(values.max() ?? 0, 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for (index, value) in values.enumerated() {
            let x = chart.minX + slot * CGFloat(index) + (slot - barWidth) / 2
            let height = max(4, chart.height * CGFloat(value / top))
            let bar = NSRect(x: x, y: chart.minY, width: barWidth, height: height)
            let isLast = index == values.count - 1
            (value == 0 ? NSColor.quaternaryLabelColor : (highlightLast && !isLast ? color.withAlphaComponent(0.45) : color)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).fill()
            if index < labels.count {
                let text = labels[index] as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: x + (barWidth - size.width) / 2, y: 0), withAttributes: attributes)
            }
        }
    }
}

/// A card with an icon, a big value, a caption and an optional bar.
final class MetricCard: NSView {
    private let value = UI.label("—", size: 26, weight: .bold)
    private let detail = UI.label("", size: 12, color: .secondaryLabelColor)
    private let bar: ProgressBar?

    init(title: String, symbol: String, color: NSColor, showsBar: Bool = true) {
        bar = showsBar ? ProgressBar(color: color) : nil
        super.init(frame: .zero)
        let icon = NSImageView(image: UI.symbol(symbol, size: 14, color: color) ?? NSImage())
        let heading = UI.hStack([icon, UI.label(title, size: 13, weight: .semibold, color: .secondaryLabelColor)], spacing: 6)
        var views: [NSView] = [heading, value, detail]
        if let bar { views.append(bar) }
        let stack = UI.vStack(views, spacing: 6)
        let card = CardView(stack, padding: 16)
        UI.pin(card, in: self)
        bar?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        detail.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(value: String, detail: String, fraction: Double? = nil, color: NSColor? = nil) {
        self.value.stringValue = value
        self.detail.stringValue = detail
        if let fraction { bar?.value = fraction }
        if let color { bar?.color = color }
    }
}

/// Base for each page in the main window.
class PageView: NSView {
    /// Data changed: reload everything.
    func refresh() {}
    /// Called every second while the page is showing, for clocks and live readings.
    func tick() {}

    /// Big title with a coloured icon and a subtitle.
    func header(_ title: String, subtitle: String, symbol: String, color: NSColor) -> (NSView, NSTextField) {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 10
        badge.layer?.backgroundColor = color.cgColor
        let icon = NSImageView(image: UI.symbol(symbol, size: 18, color: .white) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(icon)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 40),
            badge.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        let subtitleLabel = UI.label(subtitle, size: 13, color: .secondaryLabelColor)
        let text = UI.vStack([UI.label(title, size: 26, weight: .bold), subtitleLabel], spacing: 2)
        return (UI.hStack([badge, text], spacing: 14), subtitleLabel)
    }

    /// Lays out a page: header at the top, then the body. With `fills`, the body stretches
    /// to the bottom of the window (lists, editors); otherwise it keeps its natural height.
    func layout(header: NSView, body: NSView, fills: Bool = false) {
        var views = [header, body]
        let spacer = NSView()
        if !fills {
            spacer.setContentHuggingPriority(.init(1), for: .vertical)
            views.append(spacer)
        }
        let stack = UI.vStack(views, spacing: 22)
        stack.distribution = .fill
        UI.pin(stack, in: self, padding: 0)
        stack.edgeInsets = NSEdgeInsets(top: 52, left: 36, bottom: 32, right: 36)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -72).isActive = true
        body.setContentHuggingPriority(fills ? .init(1) : .required, for: .vertical)
    }
}

/// Fills itself with the window background colour, in light and dark mode.
final class BackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
