import AppKit
import ToolbeltCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let focus = FocusController()
    private let clipboard = ClipboardController()
    private let notes = NotesController()
    private let system = SystemMonitor()
    private let awake = AwakeController()
    private var hotKeys: HotKeyCenter!
    private var mainWindow: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        NSApp.mainMenu = makeMainMenu()

        focus.onChange = { [weak self] in
            self?.updateStatusItem()
            NotificationCenter.default.post(name: .toolbeltChanged, object: nil)
        }
        awake.onChange = { [weak self] in
            self?.updateStatusItem()
            NotificationCenter.default.post(name: .toolbeltChanged, object: nil)
        }
        clipboard.start()
        system.start()
        hotKeys = HotKeyCenter { [weak self] action in self?.perform(action) }
        hotKeys.onChange = { NotificationCenter.default.post(name: .toolbeltChanged, object: nil) }
        updateStatusItem()

        let tools = Tools(focus: focus, clipboard: clipboard, notes: notes, system: system, awake: awake, hotKeys: hotKeys)
        mainWindow = MainWindowController(tools: tools)

        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            // Development aid: ./Toolbelt --snapshot <folder> saves a PNG of each page and quits.
            mainWindow.saveSnapshots(to: URL(fileURLWithPath: arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }
        Notifier.shared.requestPermission()
        // Started at login: stay in the menu bar and Dock without opening the window.
        if !arguments.contains("--background") { mainWindow.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Dock icon brings the window back.
        if !flag { mainWindow.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        notes.save()
        awake.turnOff()
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .clipboard: clipboard.showPanel()
        case .notes: notes.toggle()
        case .focus: focus.toggle()
        case .keepAwake: awake.toggle()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let symbol = awake.isAwake ? "cup.and.saucer.fill" : "wrench.and.screwdriver"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Toolbelt")
        button.image?.isTemplate = true
        if let text = focus.menuBarText {
            button.title = " " + text
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    // Rebuild the menu each time it opens, so every reading is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let shortcuts = hotKeys.settings
        menu.removeAllItems()
        menu.addAction("Open Toolbelt", target: self, action: #selector(openWindow), key: "o")
        menu.addItem(.separator())
        focus.addItems(to: menu, shortcut: shortcuts.shortcut(for: .focus))
        menu.addItem(.separator())
        clipboard.addItems(to: menu, shortcut: shortcuts.shortcut(for: .clipboard))
        menu.addItem(.separator())
        notes.addItems(to: menu, shortcut: shortcuts.shortcut(for: .notes))
        menu.addItem(.separator())
        awake.addItems(to: menu, shortcut: shortcuts.shortcut(for: .keepAwake))
        menu.addItem(.separator())
        system.addItems(to: menu)
        menu.addItem(.separator())

        menu.addAction("Settings…", target: self, action: #selector(showSettings), key: ",")
        let quit = menu.addAction("Quit Toolbelt", target: NSApp, action: #selector(NSApplication.terminate(_:)), key: "q")
        if let quitShortcut = shortcuts.shortcut(for: .quit) { quit.showShortcut(quitShortcut) }
    }

    @objc private func openWindow() {
        mainWindow.show()
    }

    @objc private func showSettings() {
        mainWindow.show(.settings)
    }

    @objc private func showSection(_ sender: NSMenuItem) {
        mainWindow.show(Section(rawValue: sender.tag))
    }

    /// The menu bar shown while Toolbelt's window is in front.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Toolbelt", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addAction("Settings…", target: self, action: #selector(showSettings), key: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Toolbelt", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Toolbelt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Toolbelt", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        // ⌘1 to ⌘7 jump between pages, like tabs.
        let view = NSMenu(title: "View")
        for section in Section.allCases {
            let item = view.addAction(section.title, target: self, action: #selector(showSection(_:)), key: "\(section.rawValue + 1)")
            item.tag = section.rawValue
        }
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = view

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(.separator())
        window.addAction("Toolbelt", target: self, action: #selector(openWindow), key: "0")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        return main
    }
}
