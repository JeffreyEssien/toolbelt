import AppKit
import Carbon
import ToolbeltCore
import UserNotifications

enum Paths {
    /// ~/Library/Application Support/Toolbelt
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Toolbelt", isDirectory: true)
    }()

    static let clipboard = support.appendingPathComponent("clipboard.json")
    static let focusLog = support.appendingPathComponent("focus-log.json")
    static let notes = support.appendingPathComponent("notes.md")
    static let settings = support.appendingPathComponent("settings.json")
}

/// Registers the saved shortcuts and re-registers them whenever they change.
final class HotKeyCenter {
    private(set) var settings: ShortcutSettings
    private let store = JSONStore<ShortcutSettings>(url: Paths.settings)
    private let perform: (ShortcutAction) -> Void
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    /// Called after shortcuts change, so menus and windows can refresh.
    var onChange: (() -> Void)?

    init(perform: @escaping (ShortcutAction) -> Void) {
        settings = store.load() ?? .defaults
        self.perform = perform
        registerAll()
    }

    /// Actions whose shortcut macOS wouldn't register.
    var failed: [ShortcutAction] {
        ShortcutAction.allCases.filter { settings.shortcut(for: $0) != nil && hotKeys[$0]?.isRegistered != true }
    }

    /// Returns the action that lost this shortcut to the new one, if any.
    @discardableResult
    func set(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutAction? {
        let moved = settings.set(shortcut, for: action)
        save()
        return moved
    }

    func resetToDefaults() {
        settings = .defaults
        save()
    }

    /// Turns shortcuts off while one is being recorded, so pressing it doesn't also run it.
    func suspend() {
        hotKeys.removeAll()
    }

    func resume() {
        registerAll()
    }

    private func save() {
        try? store.save(settings)
        registerAll()
        onChange?()
    }

    private func registerAll() {
        hotKeys.removeAll()
        for action in ShortcutAction.allCases {
            guard let shortcut = settings.shortcut(for: action) else { continue }
            hotKeys[action] = HotKey(shortcut) { [weak self] in self?.perform(action) }
        }
    }
}

/// A system-wide keyboard shortcut, registered through Carbon so it
/// works without the Accessibility permission.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32
    /// False when macOS refused it, usually because another app already uses that shortcut.
    let isRegistered: Bool

    /// `keyCode` is a kVK_ constant, `modifiers` a mix of controlKey, optionKey, cmdKey and shiftKey.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x54424C54), id: id) // "TBLT"
        isRegistered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                           GetApplicationEventTarget(), 0, &ref) == noErr
    }

    convenience init(_ shortcut: Shortcut, action: @escaping () -> Void) {
        self.init(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, action: action)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { HotKey.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Banner notifications, with a sound as a fallback when they're turned off.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Notifications only work from inside the .app bundle, not from `swift run`.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestPermission() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        NSSound(named: "Glass")?.play()
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show banners even though Toolbelt counts as the active app while its menu is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

/// Starts Toolbelt at login with a LaunchAgent, the same way the other launchd jobs on this Mac work.
enum LoginItem {
    private static let label = "com.jeffreyessien.toolbelt"
    private static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func setEnabled(_ enabled: Bool) throws {
        if !enabled {
            try? FileManager.default.removeItem(at: plist)
            return
        }
        guard let executable = Bundle.main.executablePath else { return }
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plist, options: .atomic)
    }
}

extension NSMenuItem {
    /// Shows a global shortcut next to the item. It's only a label: the hotkey itself does the work.
    func showShortcut(_ shortcut: Shortcut?) {
        guard let shortcut, let key = shortcut.menuKey else {
            keyEquivalent = ""
            return
        }
        keyEquivalent = key
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers & Shortcut.control != 0 { mask.insert(.control) }
        if shortcut.modifiers & Shortcut.option != 0 { mask.insert(.option) }
        if shortcut.modifiers & Shortcut.shift != 0 { mask.insert(.shift) }
        if shortcut.modifiers & Shortcut.command != 0 { mask.insert(.command) }
        keyEquivalentModifierMask = mask
    }
}

extension NSMenu {
    /// A greyed-out line of text.
    func addInfo(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    @discardableResult
    func addAction(_ title: String, target: AnyObject, action: Selector, key: String = "",
                   modifiers: NSEvent.ModifierFlags = .command, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        item.representedObject = represented
        addItem(item)
        return item
    }
}
