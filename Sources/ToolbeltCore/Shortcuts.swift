import Foundation

/// A key plus modifiers, stored as Carbon key codes and modifier flags
/// so it can be registered as a system-wide hotkey.
public struct Shortcut: Codable, Equatable, Hashable {
    public var keyCode: Int
    public var modifiers: Int

    // Carbon modifier flags (cmdKey, shiftKey, optionKey, controlKey).
    public static let command = 0x0100
    public static let shift = 0x0200
    public static let option = 0x0800
    public static let control = 0x1000

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    /// Shift alone isn't enough: ⇧A would stop you typing a capital A anywhere.
    public var isValid: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0 && Self.keyNames[keyCode] != nil
    }

    /// "⌃⌥V", in the order macOS menus use.
    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    /// The character an NSMenuItem needs to show this shortcut, when it has one.
    public var menuKey: String? {
        guard let name = Self.keyNames[keyCode], name.count == 1, name.first?.isASCII == true else { return nil }
        return name.lowercased()
    }

    /// Keys that can be used, by kVK_ key code. Esc is left out because it cancels recording.
    public static let keyNames: [Int: String] = {
        var names: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        let functionKeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (index, code) in functionKeys.enumerated() { names[code] = "F\(index + 1)" }
        return names
    }()
}

/// Everything Toolbelt can do from a keyboard shortcut.
public enum ShortcutAction: String, Codable, CaseIterable {
    case clipboard, notes, focus, keepAwake, quit

    public var title: String {
        switch self {
        case .clipboard: return "Search clipboard history"
        case .notes: return "Open quick notes"
        case .focus: return "Start, pause or resume focus"
        case .keepAwake: return "Turn keep awake on or off"
        case .quit: return "Quit Toolbelt"
        }
    }

    /// Quit has no default so it can't be pressed by accident.
    public var defaultShortcut: Shortcut? {
        let ctrlOption = Shortcut.control | Shortcut.option
        switch self {
        case .clipboard: return Shortcut(keyCode: 9, modifiers: ctrlOption) // ⌃⌥V
        case .notes: return Shortcut(keyCode: 45, modifiers: ctrlOption) // ⌃⌥N
        case .focus: return Shortcut(keyCode: 3, modifiers: ctrlOption) // ⌃⌥F
        case .keepAwake: return Shortcut(keyCode: 0, modifiers: ctrlOption) // ⌃⌥A
        case .quit: return nil
        }
    }
}

/// Which shortcut each action uses. One shortcut can only belong to one action.
public struct ShortcutSettings: Codable, Equatable {
    // Keyed by raw value so the JSON stays a plain object.
    private var assigned: [String: Shortcut]

    public init() {
        assigned = [:]
        for action in ShortcutAction.allCases {
            if let shortcut = action.defaultShortcut { assigned[action.rawValue] = shortcut }
        }
    }

    public static let defaults = ShortcutSettings()

    public func shortcut(for action: ShortcutAction) -> Shortcut? {
        assigned[action.rawValue]
    }

    /// Sets or clears an action's shortcut. If another action already used it,
    /// that action loses it and is returned so the change can be explained.
    @discardableResult
    public mutating func set(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutAction? {
        guard let shortcut else {
            assigned[action.rawValue] = nil
            return nil
        }
        let previousOwner = ShortcutAction.allCases.first { $0 != action && assigned[$0.rawValue] == shortcut }
        if let previousOwner { assigned[previousOwner.rawValue] = nil }
        assigned[action.rawValue] = shortcut
        return previousOwner
    }

    public func action(for shortcut: Shortcut) -> ShortcutAction? {
        ShortcutAction.allCases.first { assigned[$0.rawValue] == shortcut }
    }
}
