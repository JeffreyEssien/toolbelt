import AppKit
import ToolbeltCore

/// A Spotlight-style window: type to search, arrows to move, Return to paste, Esc to close.
final class ClipboardPanel: NSPanel, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let onChoose: (ClipItem) -> Void
    private let onDelete: (ClipItem) -> Void
    private let search = NSSearchField()
    private let table = NSTableView()
    private var all: [ClipItem] = []
    private var shown: [ClipItem] = []

    init(onChoose: @escaping (ClipItem) -> Void, onDelete: @escaping (ClipItem) -> Void) {
        self.onChoose = onChoose
        self.onDelete = onDelete
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Clipboard"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        buildViews()
    }

    private func buildViews() {
        search.placeholderString = "Search copies"
        search.delegate = self
        search.font = .systemFont(ofSize: 15)
        search.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("clip"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 40
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(chooseSelected)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Return to paste · ⌘⌫ to delete · Esc to close")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let content = NSVisualEffectView()
        content.material = .popover
        content.state = .active
        [search, scroll, hint].forEach(content.addSubview)
        contentView = content

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    override var canBecomeKey: Bool { true }

    func show(_ items: [ClipItem]) {
        search.stringValue = ""
        reload(items)
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
    }

    func reload(_ items: [ClipItem]) {
        all = items
        filter()
    }

    private func filter() {
        shown = ClipboardHistory(limit: max(1, all.count), items: all).search(search.stringValue)
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    @objc private func chooseSelected() {
        guard shown.indices.contains(table.selectedRow) else { return }
        onChoose(shown[table.selectedRow])
    }

    private func moveSelection(by offset: Int) {
        guard !shown.isEmpty else { return }
        let row = min(max(table.selectedRow + offset, 0), shown.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: Keyboard

    func controlTextDidChange(_ obj: Notification) {
        filter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(moveUp(_:)): moveSelection(by: -1)
        case #selector(moveDown(_:)): moveSelection(by: 1)
        case #selector(insertNewline(_:)): chooseSelected()
        case #selector(cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘⌫ deletes the selected copy, even while typing in the search field.
        if event.modifierFlags.contains(.command), event.keyCode == 51, shown.indices.contains(table.selectedRow) {
            onDelete(shown[table.selectedRow])
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        shown.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? ClipCell ?? ClipCell(identifier: id)
        cell.show(shown[row])
        return cell
    }
}

final class ClipCell: NSTableCellView {
    private let text = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private static let relative = RelativeDateTimeFormatter()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: 13)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [text, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ item: ClipItem) {
        text.stringValue = item.preview
        let lines = item.text.split(whereSeparator: \.isNewline).count
        let when = Self.relative.localizedString(for: item.copiedAt, relativeTo: Date())
        detail.stringValue = lines > 1 ? "\(when) · \(lines) lines" : when
    }
}
