import AppKit
import ToolbeltCore

/// A scratchpad that saves itself to a plain text file as you type. The floating
/// window and the main window's Notes page share one text storage, so they always match.
final class NotesController: NSObject, NSTextViewDelegate, NSWindowDelegate {
    let storage: NSTextStorage
    private var panel: NSPanel?
    private var panelTextView: NSTextView?
    private var saveWork: DispatchWorkItem?
    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    override init() {
        let text = (try? String(contentsOf: Paths.notes, encoding: .utf8)) ?? ""
        storage = NSTextStorage(string: text, attributes: [.font: Self.font, .foregroundColor: NSColor.textColor])
        super.init()
    }

    var wordCount: Int {
        storage.string.split { $0.isWhitespace || $0.isNewline }.count
    }

    func addItems(to menu: NSMenu, shortcut: Shortcut?) {
        menu.addInfo("Quick notes")
        menu.addAction("Open notes", target: self, action: #selector(toggle)).showShortcut(shortcut)
        menu.addAction("Show notes file in Finder", target: self, action: #selector(revealFile))
    }

    /// A new text view showing the shared notes, inside a scroll view.
    func makeEditor() -> (NSScrollView, NSTextView) {
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.textColor]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return (scroll, textView)
    }

    @objc func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow {
            save()
            panel.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panelTextView)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Quick notes"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.center()
        // Remembers where you left the window.
        panel.setFrameAutosaveName("ToolbeltNotes")
        let (scroll, textView) = makeEditor()
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        panel.contentView = scroll
        panelTextView = textView
        return panel
    }

    func textDidChange(_ notification: Notification) {
        NotificationCenter.default.post(name: .toolbeltChanged, object: nil)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func windowWillClose(_ notification: Notification) {
        save()
    }

    func save() {
        saveWork?.cancel()
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? storage.string.write(to: Paths.notes, atomically: true, encoding: .utf8)
    }

    @objc func revealFile() {
        save()
        NSWorkspace.shared.activateFileViewerSelecting([Paths.notes])
    }
}
