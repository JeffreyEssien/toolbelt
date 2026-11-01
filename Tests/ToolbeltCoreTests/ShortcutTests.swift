import Foundation
import Testing
@testable import ToolbeltCore

struct ShortcutTests {
    @Test func displaysModifiersInMenuOrder() {
        let all = Shortcut.control | Shortcut.option | Shortcut.shift | Shortcut.command
        #expect(Shortcut(keyCode: 9, modifiers: all).display == "⌃⌥⇧⌘V")
        #expect(Shortcut(keyCode: 49, modifiers: Shortcut.command).display == "⌘Space")
        #expect(Shortcut(keyCode: 122, modifiers: Shortcut.option).display == "⌥F1")
    }

    @Test func needsCommandControlOrOption() {
        #expect(Shortcut(keyCode: 9, modifiers: Shortcut.shift).isValid == false)
        #expect(Shortcut(keyCode: 9, modifiers: 0).isValid == false)
        #expect(Shortcut(keyCode: 9, modifiers: Shortcut.option).isValid)
        // Esc (53) isn't allowed because it cancels recording.
        #expect(Shortcut(keyCode: 53, modifiers: Shortcut.command).isValid == false)
    }

    @Test func ignoresOtherModifierBits() {
        // 0x0001 is a Carbon flag unrelated to modifiers.
        #expect(Shortcut(keyCode: 9, modifiers: Shortcut.option | 0x0001).modifiers == Shortcut.option)
    }

    @Test func menuKeyOnlyForPlainCharacters() {
        #expect(Shortcut(keyCode: 9, modifiers: Shortcut.command).menuKey == "v")
        #expect(Shortcut(keyCode: 43, modifiers: Shortcut.command).menuKey == ",")
        #expect(Shortcut(keyCode: 49, modifiers: Shortcut.command).menuKey == nil)
        #expect(Shortcut(keyCode: 123, modifiers: Shortcut.command).menuKey == nil)
    }
}

struct ShortcutSettingsTests {
    @Test func defaultsLeaveQuitUnassigned() {
        let settings = ShortcutSettings.defaults
        #expect(settings.shortcut(for: .clipboard)?.display == "⌃⌥V")
        #expect(settings.shortcut(for: .notes)?.display == "⌃⌥N")
        #expect(settings.shortcut(for: .quit) == nil)
    }

    @Test func takingAnotherActionsShortcutMovesIt() throws {
        var settings = ShortcutSettings()
        let clipboardKeys = try #require(settings.shortcut(for: .clipboard))
        let moved = settings.set(clipboardKeys, for: .quit)
        #expect(moved == .clipboard)
        #expect(settings.shortcut(for: .clipboard) == nil)
        #expect(settings.action(for: clipboardKeys) == .quit)
    }

    @Test func settingSameShortcutAgainIsNotAConflict() throws {
        var settings = ShortcutSettings()
        let keys = try #require(settings.shortcut(for: .notes))
        #expect(settings.set(keys, for: .notes) == nil)
        #expect(settings.shortcut(for: .notes) == keys)
    }

    @Test func clearAndSaveRoundTrip() throws {
        var settings = ShortcutSettings()
        settings.set(nil, for: .focus)
        settings.set(Shortcut(keyCode: 12, modifiers: Shortcut.control | Shortcut.command), for: .quit)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ShortcutSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.shortcut(for: .focus) == nil)
        #expect(decoded.shortcut(for: .quit)?.display == "⌃⌘Q")
    }
}
