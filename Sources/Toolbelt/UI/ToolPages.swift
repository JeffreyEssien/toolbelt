import AppKit
import ToolbeltCore

// MARK: - Clipboard

final class ClipboardPage: PageView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let tools: Tools
    private let search = NSSearchField()
    private let saveSwitch = NSSwitch()
    private let table = NSTableView()
    private let preview = NSTextView()
    private let meta = UI.label("", size: 12, color: .secondaryLabelColor)
    private let autoPaste = UI.label("", size: 12, color: .secondaryLabelColor)
    private let autoPasteButton = NSButton()
    private var subtitle: NSTextField!
    private var copyButton: NSButton!
    private var deleteButton: NSButton!
    private var shown: [ClipItem] = []

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)
        let (header, subtitle) = header("Clipboard history", subtitle: "", symbol: "doc.on.clipboard.fill", color: .systemBlue)
        self.subtitle = subtitle

        search.placeholderString = "Search copies"
        search.delegate = self
        search.controlSize = .large
        saveSwitch.target = self
        saveSwitch.action = #selector(toggleSaving)
        let clear = UI.button("Clear All", symbol: "trash", target: self, action: #selector(clearAll))
        let toolbar = UI.hStack([search, UI.label("Save new copies", size: 13, color: .secondaryLabelColor), saveSwitch, clear], spacing: 10)
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // List
        table.addTableColumn(NSTableColumn(identifier: .init("clip")))
        table.headerView = nil
        table.rowHeight = 44
        table.style = .inset
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        let listScroll = NSScrollView()
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        let list = CardView(listScroll, padding: 6)

        // Preview
        preview.isEditable = false
        preview.isRichText = false
        preview.drawsBackground = false
        preview.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        preview.textContainerInset = NSSize(width: 4, height: 8)
        preview.isVerticallyResizable = true
        preview.autoresizingMask = [.width]
        let previewScroll = NSScrollView()
        previewScroll.documentView = preview
        previewScroll.hasVerticalScroller = true
        previewScroll.drawsBackground = false
        copyButton = UI.button("Copy", symbol: "doc.on.doc.fill", color: .systemBlue, target: self, action: #selector(copySelected))
        deleteButton = UI.button("Delete", symbol: "trash", target: self, action: #selector(deleteSelected))
        let previewTitle = UI.label("Preview", size: 13, weight: .semibold, color: .secondaryLabelColor)
        let previewStack = UI.vStack([previewTitle, meta, previewScroll, UI.hStack([copyButton, deleteButton])], spacing: 10)
        previewScroll.widthAnchor.constraint(equalTo: previewStack.widthAnchor).isActive = true
        let previewCard = CardView(previewStack, padding: 18)

        let split = UI.hStack([list, previewCard], spacing: 14)
        split.alignment = .top
        list.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.52).isActive = true
        previewCard.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.48, constant: -14).isActive = true
        list.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true
        previewCard.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true

        autoPasteButton.bezelStyle = .rounded
        autoPasteButton.title = "Turn On Auto-paste…"
        autoPasteButton.target = tools.clipboard
        autoPasteButton.action = #selector(ClipboardController.askForAccessibility)
        let footer = UI.hStack([NSImageView(image: UI.symbol("keyboard", size: 13, color: .secondaryLabelColor) ?? NSImage()),
                                autoPaste, NSView(), autoPasteButton])

        let body = UI.vStack([toolbar, split, footer], spacing: 14)
        [toolbar, split, footer].forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        layout(header: header, body: body, fills: true)
        clipboardDidChange()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        let shortcut = tools.hotKeys.settings.shortcut(for: .clipboard)?.display
        let hint = shortcut.map { "Press \($0) in any app to search and paste." } ?? "Set a shortcut in Settings to search from any app."
        autoPaste.stringValue = tools.clipboard.autoPasteOn ? "\(hint) Auto-paste is on." : "\(hint) Without auto-paste, press ⌘V after choosing."
        autoPasteButton.isHidden = tools.clipboard.autoPasteOn
        saveSwitch.state = tools.clipboard.isPaused ? .off : .on
    }

    func clipboardDidChange() {
        let selectedID = shown.indices.contains(table.selectedRow) ? shown[table.selectedRow].id : nil
        shown = tools.clipboard.history.search(search.stringValue)
        table.reloadData()
        let row = selectedID.flatMap { id in shown.firstIndex { $0.id == id } } ?? (shown.isEmpty ? -1 : 0)
        if row >= 0 { table.selectRowIndexes([row], byExtendingSelection: false) }
        let count = tools.clipboard.history.items.count
        subtitle.stringValue = "\(count) saved \(count == 1 ? "copy" : "copies") · the last 50 are kept · passwords are never saved"
        showSelection()
        refresh()
    }

    private func showSelection() {
        guard shown.indices.contains(table.selectedRow) else {
            preview.string = ""
            meta.stringValue = search.stringValue.isEmpty ? "Copy some text and it shows up here." : "No copies match your search."
            copyButton.isEnabled = false
            deleteButton.isEnabled = false
            return
        }
        let item = shown[table.selectedRow]
        preview.string = item.text
        let lines = item.text.split(whereSeparator: \.isNewline).count
        let when = RelativeDateTimeFormatter().localizedString(for: item.copiedAt, relativeTo: Date())
        meta.stringValue = "Copied \(when) · \(item.text.count) characters · \(max(lines, 1)) \(lines == 1 ? "line" : "lines")"
        copyButton.isEnabled = true
        deleteButton.isEnabled = true
    }

    @objc private func copySelected() {
        guard shown.indices.contains(table.selectedRow) else { return }
        tools.clipboard.copy(shown[table.selectedRow])
        copyButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.copyButton.title = "Copy" }
    }

    @objc private func deleteSelected() {
        guard shown.indices.contains(table.selectedRow) else { return }
        tools.clipboard.delete(shown[table.selectedRow])
    }

    @objc private func clearAll() { tools.clipboard.clearHistory() }
    @objc private func toggleSaving() { tools.clipboard.togglePause() }

    func controlTextDidChange(_ obj: Notification) { clipboardDidChange() }
    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }
    func tableViewSelectionDidChange(_ notification: Notification) { showSelection() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? ClipCell ?? ClipCell(identifier: id)
        cell.show(shown[row])
        return cell
    }
}

// MARK: - Notes

final class NotesPage: PageView {
    private let tools: Tools
    private var subtitle: NSTextField!

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)
        let (header, subtitle) = header("Quick notes", subtitle: "", symbol: "note.text", color: .systemYellow)
        self.subtitle = subtitle
        let (scroll, _) = tools.notes.makeEditor()
        let editor = CardView(scroll, padding: 4)
        let footer = UI.hStack([
            UI.label("Saves as you type to notes.md", size: 12, color: .secondaryLabelColor), NSView(),
            UI.button("Open Floating Notes", symbol: "macwindow.on.rectangle", color: .systemYellow,
                      target: tools.notes, action: #selector(NotesController.toggle)),
            UI.button("Show in Finder", symbol: "folder", target: tools.notes, action: #selector(NotesController.revealFile)),
        ])
        let body = UI.vStack([editor, footer], spacing: 14)
        [editor, footer].forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        editor.setContentHuggingPriority(.defaultLow, for: .vertical)
        layout(header: header, body: body, fills: true)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        let words = tools.notes.wordCount
        let shortcut = tools.hotKeys.settings.shortcut(for: .notes)?.display
        subtitle.stringValue = "\(words) \(words == 1 ? "word" : "words")"
            + (shortcut.map { " · press \($0) anywhere for the floating window" } ?? "")
    }
}

// MARK: - Keep awake

final class AwakePage: PageView {
    private let tools: Tools
    private let icon = NSImageView()
    private let title = UI.label("", size: 24, weight: .bold)
    private let detail = UI.label("", size: 14, color: .secondaryLabelColor)
    private let buttons = UI.hStack([], spacing: 10)
    private var wasAwake: Bool?

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)
        let (header, _) = header("Keep awake", subtitle: "Stop your Mac and its display from going to sleep.",
                                 symbol: "cup.and.saucer.fill", color: .systemOrange)
        let status = UI.vStack([icon, title, detail, buttons], spacing: 10, alignment: .centerX)
        status.setCustomSpacing(24, after: detail)
        let card = CardView(status, padding: 44)

        let info = CardView(UI.vStack([
            UI.label("Good for", size: 13, weight: .semibold, color: .secondaryLabelColor),
            UI.wrapping("Long downloads and installs, presentations, video calls, or reading without touching the trackpad. It turns off by itself when the time runs out or when you quit Toolbelt."),
        ], spacing: 8), padding: 18)

        let body = UI.vStack([card, info], spacing: 16)
        [card, info].forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        layout(header: header, body: body)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        let awake = tools.awake
        icon.image = UI.symbol(awake.isAwake ? "cup.and.saucer.fill" : "moon.zzz.fill", size: 64,
                               color: awake.isAwake ? .systemOrange : .tertiaryLabelColor, weight: .regular)
        title.stringValue = awake.isAwake ? "Your Mac is staying awake" : "Your Mac sleeps normally"
        detail.stringValue = awake.isAwake ? awake.statusText : "Pick how long to keep it awake."
        guard wasAwake != awake.isAwake else { return }
        wasAwake = awake.isAwake
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if awake.isAwake {
            buttons.addArrangedSubview(UI.button("Let the Mac Sleep", symbol: "moon.fill", color: .systemOrange,
                                                 target: awake, action: #selector(AwakeController.turnOff)))
        } else {
            buttons.addArrangedSubview(UI.button("1 Hour", target: self, action: #selector(oneHour)))
            buttons.addArrangedSubview(UI.button("2 Hours", target: self, action: #selector(twoHours)))
            buttons.addArrangedSubview(UI.button("Until I Turn It Off", symbol: "infinity", color: .systemOrange,
                                                 target: self, action: #selector(indefinitely)))
        }
    }

    @objc private func oneHour() { tools.awake.keepAwake(minutes: 60) }
    @objc private func twoHours() { tools.awake.keepAwake(minutes: 120) }
    @objc private func indefinitely() { tools.awake.keepAwake(minutes: 0) }
}

// MARK: - System

final class SystemPage: PageView {
    private let tools: Tools
    private let battery = MetricCard(title: "Battery", symbol: "battery.100percent", color: .systemGreen)
    private let health = MetricCard(title: "Battery health", symbol: "heart.fill", color: .systemPink)
    private let memory = MetricCard(title: "Memory", symbol: "memorychip.fill", color: .systemPurple)
    private let cpu = MetricCard(title: "CPU", symbol: "cpu.fill", color: .systemBlue)
    private let heat = MetricCard(title: "Heat", symbol: "thermometer.medium", color: .systemOrange)
    private let disk = MetricCard(title: "Disk", symbol: "internaldrive.fill", color: .systemTeal)
    private var ticks = 0

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)
        let (header, _) = header("System", subtitle: "Live readings from your Mac, updated every few seconds.",
                                 symbol: "gauge.with.dots.needle.67percent", color: .systemGreen)
        let row1 = UI.hStack([battery, health, memory], spacing: 14)
        let row2 = UI.hStack([cpu, heat, disk], spacing: 14)
        [row1, row2].forEach { $0.distribution = .fillEqually; $0.alignment = .top }
        let footer = UI.hStack([
            UI.wrapping("Heat shows macOS's own level because Apple doesn't share the exact CPU temperature on Apple silicon.", size: 12),
            NSView(),
            UI.button("Open Activity Monitor", symbol: "chart.bar.xaxis", target: tools.system, action: #selector(SystemMonitor.openActivityMonitor)),
        ])
        let body = UI.vStack([row1, row2, footer], spacing: 14)
        [row1, row2, footer].forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        layout(header: header, body: body)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func tick() {
        ticks += 1
        if ticks % 2 == 0 { refresh() }
    }

    override func refresh() {
        let s = tools.system.snapshot()
        if let b = s.battery {
            battery.update(value: "\(b.percent)%", detail: b.status.capitalizingFirst, fraction: Double(b.percent) / 100,
                           color: b.percent <= 20 ? .systemRed : .systemGreen)
            health.update(value: b.health.map { "\($0)%" } ?? "—",
                          detail: b.cycles.map { "\($0) charge cycles" } ?? "Of its original capacity",
                          fraction: Double(b.health ?? 0) / 100)
        } else {
            battery.update(value: "—", detail: "No battery (desktop Mac)", fraction: 0)
            health.update(value: "—", detail: "No battery", fraction: 0)
        }
        if let used = s.memoryUsed {
            memory.update(value: Formatting.bytes(used), detail: "used of \(Formatting.bytes(s.memoryTotal))",
                          fraction: Double(used) / Double(max(s.memoryTotal, 1)))
        }
        if let load = s.cpuLoad {
            cpu.update(value: "\(Int((load * 100).rounded()))%", detail: "busy · up \(Self.uptime(s.uptime))", fraction: load)
        } else {
            cpu.update(value: "…", detail: "Measuring", fraction: 0)
        }
        heat.update(value: s.thermalText, detail: s.thermalDetail, fraction: s.thermalFraction,
                    color: s.thermal == .nominal ? .systemGreen : (s.thermal == .fair ? .systemYellow : .systemRed))
        if let free = s.diskFree, let total = s.diskTotal, total > 0 {
            disk.update(value: "\(Formatting.bytes(free)) free", detail: "of \(Formatting.bytes(total)) · \(Int((1 - Double(free) / Double(total)) * 100))% used",
                        fraction: 1 - Double(free) / Double(total))
        }
    }

    private static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3600
        return days > 0 ? "\(days) d \(hours) h" : Formatting.duration(seconds)
    }
}
