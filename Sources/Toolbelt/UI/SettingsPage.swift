import AppKit
import Carbon
import ToolbeltCore

/// Shortcuts, open at login and Quit, as a page in the main window.
final class SettingsPage: PageView {
    private let tools: Tools
    private var hotKeys: HotKeyCenter { tools.hotKeys }
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private let message = UI.wrapping("", size: 12, color: .systemOrange)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Toolbelt when I log in", target: nil, action: nil)
    private var resignObserver: Any?

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)
        let (header, _) = header("Settings", subtitle: "Keyboard shortcuts and startup.", symbol: "gearshape.fill", color: .systemGray)

        let rows: [[NSView]] = ShortcutAction.allCases.map { action in
            let recorder = ShortcutRecorder()
            recorder.onRecordingChange = { [weak self] recording in
                guard let self else { return }
                if recording {
                    // Only one recorder listens at a time.
                    self.recorders.filter { $0.key != action }.forEach { $0.value.cancel() }
                    self.hotKeys.suspend()
                } else {
                    self.hotKeys.resume()
                }
            }
            recorder.onRecorded = { [weak self] shortcut in self?.record(shortcut, for: action) }
            recorder.onInvalid = { [weak self] in
                self?.message.stringValue = "Shortcuts need ⌘, ⌃ or ⌥ as well as a key."
            }
            recorders[action] = recorder

            let clear = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove shortcut")!,
                                 target: self, action: #selector(clearShortcut(_:)))
            clear.isBordered = false
            clear.contentTintColor = .tertiaryLabelColor
            clear.toolTip = "Remove shortcut"
            clear.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            return [UI.label(action.title, size: 13), UI.hStack([recorder, clear], spacing: 8)]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).width = 260

        let hint = UI.wrapping("Click a shortcut, then press the keys you want. Esc cancels. Shortcuts work in every app.", size: 12)
        let reset = UI.button("Reset to Defaults", symbol: "arrow.counterclockwise", target: self, action: #selector(resetDefaults))
        let shortcutsCard = CardView(UI.vStack([
            UI.label("Keyboard shortcuts", size: 13, weight: .semibold, color: .secondaryLabelColor),
            grid, hint, message, reset,
        ], spacing: 12), padding: 20)

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        let generalCard = CardView(UI.vStack([
            UI.label("General", size: 13, weight: .semibold, color: .secondaryLabelColor),
            loginCheckbox,
            UI.wrapping("At login Toolbelt starts in the menu bar without opening this window.", size: 12),
        ], spacing: 10), padding: 20)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let quit = UI.button("Quit Toolbelt", symbol: "power", color: .systemRed, target: NSApp,
                             action: #selector(NSApplication.terminate(_:)))
        let about = CardView(UI.hStack([
            UI.vStack([
                UI.label("Toolbelt \(version)", size: 13, weight: .semibold),
                UI.label("Your data stays on this Mac in ~/Library/Application Support/Toolbelt.", size: 12, color: .secondaryLabelColor),
            ], spacing: 2),
            NSView(), quit,
        ]), padding: 20)

        let body = UI.vStack([shortcutsCard, generalCard, about], spacing: 14)
        [shortcutsCard, generalCard, about].forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        layout(header: header, body: body)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else {
            cancelRecording()
            return
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                                                queue: .main) { [weak self] _ in self?.cancelRecording() }
        message.stringValue = failedMessage() ?? ""
    }

    func cancelRecording() {
        recorders.values.forEach { $0.cancel() }
    }

    private func record(_ shortcut: Shortcut, for action: ShortcutAction) {
        let moved = hotKeys.set(shortcut, for: action)
        refresh()
        if let moved {
            message.stringValue = "\(shortcut.display) was moved here from “\(moved.title)”."
        } else if hotKeys.failed.contains(action) {
            message.stringValue = "\(shortcut.display) is already used by macOS or another app. Try a different one."
        } else {
            message.stringValue = ""
        }
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let action = ShortcutAction(rawValue: raw) else { return }
        hotKeys.set(nil, for: action)
        message.stringValue = ""
        refresh()
    }

    @objc private func resetDefaults() {
        hotKeys.resetToDefaults()
        message.stringValue = failedMessage() ?? ""
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(loginCheckbox.state == .on)
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    override func refresh() {
        for (action, recorder) in recorders {
            recorder.shortcut = hotKeys.settings.shortcut(for: action)
        }
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off
    }

    private func failedMessage() -> String? {
        let failed = hotKeys.failed.compactMap { hotKeys.settings.shortcut(for: $0)?.display }
        guard !failed.isEmpty else { return nil }
        return "\(failed.joined(separator: ", ")) couldn't be turned on because something else uses it. Pick another."
    }
}

/// A button that shows a shortcut and records a new one when clicked.
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var onRecorded: ((Shortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private var monitor: Any?
    private var isRecording: Bool { monitor != nil }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(clicked)
        widthAnchor.constraint(equalToConstant: 160).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func clicked() {
        isRecording ? cancel() : startRecording()
    }

    private func startRecording() {
        onRecordingChange?(true)
        title = "Type shortcut…"
        // A local monitor sees every key, including ⌘ combinations, before menus do.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func cancel() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        updateTitle()
        onRecordingChange?(false)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancel()
            return
        }
        let recorded = Shortcut(keyCode: Int(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
        guard recorded.isValid else {
            NSSound.beep()
            onInvalid?()
            return
        }
        cancel()
        shortcut = recorded
        onRecorded?(recorded)
    }

    private func updateTitle() {
        title = shortcut?.display ?? "Click to set"
        contentTintColor = shortcut == nil ? .secondaryLabelColor : nil
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= Shortcut.command }
        if flags.contains(.shift) { modifiers |= Shortcut.shift }
        if flags.contains(.option) { modifiers |= Shortcut.option }
        if flags.contains(.control) { modifiers |= Shortcut.control }
        return modifiers
    }
}
