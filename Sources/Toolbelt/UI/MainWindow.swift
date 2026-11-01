import AppKit
import ToolbeltCore

enum Section: Int, CaseIterable {
    case overview, focus, clipboard, notes, awake, system, settings

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .focus: return "Focus"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .awake: return "Keep Awake"
        case .system: return "System"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .focus: return "timer"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notes: return "note.text"
        case .awake: return "cup.and.saucer.fill"
        case .system: return "gauge.with.dots.needle.67percent"
        case .settings: return "gearshape.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .overview: return .systemIndigo
        case .focus: return .systemRed
        case .clipboard: return .systemBlue
        case .notes: return .systemYellow
        case .awake: return .systemOrange
        case .system: return .systemGreen
        case .settings: return .systemGray
        }
    }
}

/// A Reminders-style tile: coloured badge, live value and name. Fills with its colour when selected.
final class SidebarTile: NSView {
    var onClick: (() -> Void)?
    var value = "" { didSet { valueLabel.stringValue = value } }
    var isSelected = false { didSet { needsDisplay = true; applyStyle() } }
    private let color: NSColor
    private let symbol: String
    private let badge = NSView()
    private let icon = NSImageView()
    private let valueLabel = UI.label("", size: 18, weight: .bold)
    private let nameLabel: NSTextField

    init(section: Section) {
        color = section.color
        symbol = section.symbol
        nameLabel = UI.label(section.title, size: 12, weight: .semibold)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 13
        valueLabel.alignment = .right
        for view in [badge, icon, valueLabel, nameLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 104),
            heightAnchor.constraint(equalToConstant: 70),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badge.widthAnchor.constraint(equalToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 26),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: badge.trailingAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(section.title)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    private func applyStyle() {
        // Layer colours are CGColors, so resolve the dynamic NSColors for light and dark mode first.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isSelected ? color : NSColor.controlBackgroundColor).cgColor
            badge.layer?.backgroundColor = (isSelected ? NSColor.white : color).cgColor
        }
        icon.image = UI.symbol(symbol, size: 12, color: isSelected ? color : .white, weight: .bold)
        valueLabel.textColor = isSelected ? .white : .labelColor
        nameLabel.textColor = isSelected ? .white : .secondaryLabelColor
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let tools: Tools
    private var tiles: [Section: SidebarTile] = [:]
    private var settingsButton: NSButton!
    private let content = BackgroundView()
    private var pages: [Section: PageView] = [:]
    private(set) var current: Section = .overview
    private var ticker: Timer?

    init(tools: Tools) {
        self.tools = tools
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Toolbelt"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 1000, height: 680)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ToolbeltMain")
        super.init(window: window)
        window.delegate = self
        buildWindow()
        observeChanges()
        select(.overview)
        if window.frame.origin == .zero { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ section: Section? = nil) {
        if let section { select(section) }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        startTicking()
    }

    // MARK: Layout

    private func buildWindow() {
        guard let root = window?.contentView else { return }

        // Sidebar: translucent like Apple's own apps, with colourful tiles for each tool.
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState

        let appIcon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        appIcon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let brand = UI.hStack([appIcon, UI.vStack([
            UI.label("Toolbelt", size: 17, weight: .bold),
            UI.label("Five tools, one place", size: 11, color: .secondaryLabelColor),
        ], spacing: 0)], spacing: 10)

        let toolSections: [Section] = [.overview, .focus, .clipboard, .notes, .awake, .system]
        for section in toolSections {
            let tile = SidebarTile(section: section)
            tile.onClick = { [weak self] in self?.select(section) }
            tiles[section] = tile
        }
        let grid = NSGridView(views: stride(from: 0, to: toolSections.count, by: 2).map {
            [tiles[toolSections[$0]]!, tiles[toolSections[$0 + 1]]!]
        })
        grid.rowSpacing = 10
        grid.columnSpacing = 10

        let actionsTitle = UI.label("QUICK ACTIONS", size: 11, weight: .bold, color: .tertiaryLabelColor)
        let actions = UI.vStack([
            actionsTitle,
            sidebarButton("Search Clipboard", "magnifyingglass", .systemBlue, tools.clipboard, #selector(ClipboardController.showPanel)),
            sidebarButton("Floating Notes", "macwindow.on.rectangle", .systemYellow, tools.notes, #selector(NotesController.toggle)),
            sidebarButton("Activity Monitor", "chart.bar.xaxis", .systemGreen, tools.system, #selector(SystemMonitor.openActivityMonitor)),
        ], spacing: 6)

        settingsButton = sidebarButton("Settings", "gearshape.fill", .systemGray, self, #selector(showSettings))
        let quit = sidebarButton("Quit Toolbelt", "power", .systemRed, NSApp, #selector(NSApplication.terminate(_:)))
        let bottom = UI.vStack([settingsButton, quit], spacing: 6)

        for view in [brand, grid, actions, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(view)
        }
        for view in [sidebar, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 248),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 48),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            grid.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 22),
            grid.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 15),
            actions.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 26),
            actions.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            bottom.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            bottom.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    private func sidebarButton(_ title: String, _ symbol: String, _ color: NSColor,
                               _ target: AnyObject, _ action: Selector) -> NSButton {
        let button = NSButton(title: "  " + title, image: UI.symbol(symbol, size: 14, color: color) ?? NSImage(),
                              target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    // MARK: Pages

    func select(_ section: Section) {
        (pages[current] as? SettingsPage)?.cancelRecording()
        current = section
        for (tileSection, tile) in tiles { tile.isSelected = tileSection == section }
        settingsButton.font = .systemFont(ofSize: 13, weight: section == .settings ? .bold : .medium)

        content.subviews.forEach { $0.removeFromSuperview() }
        let page = pages[section] ?? makePage(section)
        pages[section] = page
        UI.pin(page, in: content)
        page.refresh()
        updateTiles()
    }

    private func makePage(_ section: Section) -> PageView {
        switch section {
        case .overview: return OverviewPage(tools: tools)
        case .focus: return FocusPage(tools: tools)
        case .clipboard: return ClipboardPage(tools: tools)
        case .notes: return NotesPage(tools: tools)
        case .awake: return AwakePage(tools: tools)
        case .system: return SystemPage(tools: tools)
        case .settings: return SettingsPage(tools: tools)
        }
    }

    @objc func showSettings() {
        select(.settings)
    }

    private func updateTiles() {
        let focus = tools.focus
        tiles[.overview]?.value = "\(Calendar.current.component(.day, from: Date()))"
        tiles[.focus]?.value = focus.remaining.map { Formatting.clock($0) } ?? "\(focus.todayCount)"
        tiles[.clipboard]?.value = "\(tools.clipboard.history.items.count)"
        tiles[.notes]?.value = "\(tools.notes.wordCount)"
        tiles[.awake]?.value = tools.awake.isAwake ? "On" : "Off"
        tiles[.system]?.value = tools.system.snapshot().battery.map { "\($0.percent)%" }
            ?? tools.system.snapshot().cpuLoad.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    // MARK: Updates

    private func observeChanges() {
        NotificationCenter.default.addObserver(forName: .toolbeltChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.pages[self.current]?.refresh()
            self.updateTiles()
        }
        NotificationCenter.default.addObserver(forName: .clipboardChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            (self.pages[.clipboard] as? ClipboardPage)?.clipboardDidChange()
            if self.window?.isVisible == true {
                if self.current != .clipboard { self.pages[self.current]?.refresh() }
                self.updateTiles()
            }
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.pages[self.current]?.tick()
            self.updateTiles()
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func windowWillClose(_ notification: Notification) {
        ticker?.invalidate()
        ticker = nil
        (pages[.settings] as? SettingsPage)?.cancelRecording()
    }

    // MARK: Snapshots

    /// Saves a PNG of every page, for checking the layout without clicking through. The
    /// translucent sidebar renders plain here; use ⌘⇧4 then Space for real screenshots.
    func saveSnapshots(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let view = window?.contentView else { return }
        // Overview again at the end: the first capture happens before the window has drawn its background.
        for section in Section.allCases + [.overview] {
            select(section)
            view.layoutSubtreeIfNeeded()
            view.display()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = String(format: "%d-%@.png", section.rawValue + 1, section.title.lowercased().replacingOccurrences(of: " ", with: "-"))
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
        }
    }
}
