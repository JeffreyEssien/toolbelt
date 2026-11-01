import AppKit
import ToolbeltCore

/// Everything the pages need, created once by the app delegate.
final class Tools {
    let focus: FocusController
    let clipboard: ClipboardController
    let notes: NotesController
    let system: SystemMonitor
    let awake: AwakeController
    let hotKeys: HotKeyCenter

    init(focus: FocusController, clipboard: ClipboardController, notes: NotesController,
         system: SystemMonitor, awake: AwakeController, hotKeys: HotKeyCenter) {
        self.focus = focus
        self.clipboard = clipboard
        self.notes = notes
        self.system = system
        self.awake = awake
        self.hotKeys = hotKeys
    }
}

// MARK: - Overview

final class OverviewPage: PageView {
    private let tools: Tools
    private let kicker = UI.label("", size: 12, weight: .bold, color: NSColor.white.withAlphaComponent(0.75))
    private let heroTitle = UI.label("", size: 30, weight: .bold, color: .white)
    private let heroDetail = UI.label("", size: 14, color: NSColor.white.withAlphaComponent(0.9))
    private var focusButton: HeroButton!
    private let focusCard = MetricCard(title: "Focus today", symbol: "timer", color: .systemRed)
    private let clipCard = MetricCard(title: "Clipboard", symbol: "doc.on.clipboard.fill", color: .systemBlue, showsBar: false)
    private let batteryCard = MetricCard(title: "Battery", symbol: "battery.75percent", color: .systemGreen)
    private let awakeCard = MetricCard(title: "Keep awake", symbol: "cup.and.saucer.fill", color: .systemOrange, showsBar: false)
    private let shortcutGrid = NSGridView()
    private var shortcutLabels: [ShortcutAction: NSTextField] = [:]

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)

        let (header, _) = header("Overview", subtitle: Date().formatted(date: .complete, time: .omitted),
                                 symbol: "square.grid.2x2.fill", color: .systemIndigo)

        // Hero card, in the same style as Mac AI Hub's focus card.
        let hero = GradientView(colors: [NSColor.systemIndigo, NSColor.systemPurple, NSColor.systemPink])
        focusButton = HeroButton("Start focus", symbol: "play.fill", target: self, action: #selector(toggleFocus))
        let buttons = UI.hStack([
            focusButton,
            HeroButton("Search clipboard", symbol: "magnifyingglass", target: tools.clipboard, action: #selector(ClipboardController.showPanel)),
            HeroButton("Quick note", symbol: "square.and.pencil", target: tools.notes, action: #selector(NotesController.toggle)),
        ], spacing: 10)
        let heroStack = UI.vStack([kicker, heroTitle, heroDetail, buttons], spacing: 6)
        heroStack.setCustomSpacing(18, after: heroDetail)
        UI.pin(heroStack, in: hero, padding: 26)

        let metrics = UI.hStack([focusCard, clipCard, batteryCard, awakeCard], spacing: 14)
        metrics.distribution = .fillEqually
        metrics.alignment = .top

        shortcutGrid.rowSpacing = 8
        shortcutGrid.columnSpacing = 24
        for action in ShortcutAction.allCases {
            let keys = UI.label("", size: 13, weight: .semibold)
            keys.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
            shortcutLabels[action] = keys
            shortcutGrid.addRow(with: [UI.label(action.title, size: 13, color: .secondaryLabelColor), keys])
        }
        let shortcutsTitle = UI.label("Keyboard shortcuts", size: 13, weight: .semibold, color: .secondaryLabelColor)
        let shortcuts = CardView(UI.vStack([shortcutsTitle, shortcutGrid], spacing: 12), padding: 18)

        let body = UI.vStack([hero, metrics, shortcuts], spacing: 16)
        for view in [hero, metrics, shortcuts] {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        layout(header: header, body: body)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "GOOD MORNING" : (hour < 18 ? "GOOD AFTERNOON" : "GOOD EVENING")
        let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        kicker.stringValue = firstName.isEmpty ? greeting : "\(greeting), \(firstName.uppercased())"

        let shortcuts = tools.hotKeys.settings
        for (action, label) in shortcutLabels {
            let shortcut = shortcuts.shortcut(for: action)
            label.stringValue = shortcut?.display ?? "Not set"
            label.textColor = shortcut == nil ? .tertiaryLabelColor : .labelColor
        }
        tick()
    }

    override func tick() {
        let focus = tools.focus
        if let remaining = focus.remaining {
            let paused: Bool = { if case .paused = focus.timer.state { return true }; return false }()
            let what = focus.timer.kind == .rest ? "Break" : "Focus"
            heroTitle.stringValue = "\(what): \(Formatting.clock(remaining)) left" + (paused ? " (paused)" : "")
            focusButton.setTitle(paused ? "Resume" : "Pause")
            focusButton.image = UI.symbol(paused ? "play.fill" : "pause.fill", size: 12, color: .white)
        } else {
            heroTitle.stringValue = "Ready to focus?"
            focusButton.setTitle("Start 25 min focus")
            focusButton.image = UI.symbol("play.fill", size: 12, color: .white)
        }
        heroDetail.stringValue = focus.todaySummary

        let goal: TimeInterval = 2 * 3600
        focusCard.update(value: Formatting.duration(focus.todayTime),
                         detail: "\(focus.todayCount) sessions · goal \(Formatting.duration(goal))",
                         fraction: focus.todayTime / goal)
        let copies = tools.clipboard.history.items.count
        clipCard.update(value: "\(copies)", detail: tools.clipboard.isPaused ? "Saving paused" : "copies saved")
        if let battery = tools.system.snapshot().battery {
            batteryCard.update(value: "\(battery.percent)%", detail: battery.status.capitalizingFirst,
                               fraction: Double(battery.percent) / 100,
                               color: battery.percent <= 20 ? .systemRed : .systemGreen)
        } else {
            batteryCard.update(value: "—", detail: "No battery", fraction: 0)
        }
        awakeCard.update(value: tools.awake.isAwake ? "On" : "Off", detail: tools.awake.isAwake ? tools.awake.statusText : "Mac sleeps normally")
    }

    @objc private func toggleFocus() {
        tools.focus.toggle()
    }
}

// MARK: - Focus

final class FocusPage: PageView {
    private let tools: Tools
    private let ring = RingView()
    private let buttons = UI.hStack([], spacing: 10)
    private let sessionsCard = MetricCard(title: "Sessions today", symbol: "checkmark.circle.fill", color: .systemRed, showsBar: false)
    private let timeCard = MetricCard(title: "Focus time today", symbol: "clock.fill", color: .systemOrange, showsBar: false)
    private let chart = BarChart()
    private let weekTotal = UI.label("", size: 13, color: .secondaryLabelColor)
    private var lastState: FocusTimer.State?

    init(tools: Tools) {
        self.tools = tools
        super.init(frame: .zero)
        let (header, _) = header("Focus timer", subtitle: "Work in focused blocks, then take a short break.",
                                 symbol: "timer", color: .systemRed)

        ring.heightAnchor.constraint(equalToConstant: 260).isActive = true
        let left = CardView(UI.vStack([ring, buttons], spacing: 24, alignment: .centerX), padding: 28)

        let today = UI.hStack([sessionsCard, timeCard], spacing: 14)
        today.distribution = .fillEqually
        chart.color = .systemRed
        chart.emptyText = "Finish a focus session to see it here"
        chart.heightAnchor.constraint(equalToConstant: 170).isActive = true
        let weekTitle = UI.label("Last 7 days", size: 13, weight: .semibold, color: .secondaryLabelColor)
        let weekStack = UI.vStack([UI.hStack([weekTitle, NSView(), weekTotal]), chart], spacing: 14)
        let week = CardView(weekStack, padding: 18)
        weekStack.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: weekStack.widthAnchor).isActive = true }
        let right = UI.vStack([today, week], spacing: 14)
        today.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        week.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true

        let body = UI.hStack([left, right], spacing: 16)
        body.distribution = .fillEqually
        body.alignment = .top
        layout(header: header, body: body)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        let focus = tools.focus
        if lastState.map({ !Self.sameKind($0, focus.timer.state) }) ?? true {
            rebuildButtons()
            lastState = focus.timer.state
        }
        sessionsCard.update(value: "\(focus.todayCount)", detail: "completed")
        timeCard.update(value: Formatting.duration(focus.todayTime), detail: "of focused work")

        let totals = focus.log.dailyTotals(days: 7, endingOn: Date())
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        chart.values = totals.map { $0.time / 60 }
        chart.labels = totals.map { formatter.string(from: $0.day) }
        weekTotal.stringValue = "\(Formatting.duration(totals.reduce(0) { $0 + $1.time })) total"
        tick()
    }

    override func tick() {
        let focus = tools.focus
        let isRest = focus.timer.kind == .rest && focus.timer.isActive
        ring.color = isRest ? .systemTeal : .systemRed
        if let remaining = focus.remaining {
            ring.timeLabel.stringValue = Formatting.clock(remaining)
            ring.progress = focus.progress
            if case .paused = focus.timer.state {
                ring.caption.stringValue = "Paused"
            } else {
                ring.caption.stringValue = isRest ? "Break" : "Focusing"
            }
        } else {
            ring.timeLabel.stringValue = "25:00"
            ring.progress = 0
            ring.caption.stringValue = "Ready when you are"
        }
        if lastState.map({ !Self.sameKind($0, focus.timer.state) }) ?? true { refresh() }
    }

    private static func sameKind(_ a: FocusTimer.State, _ b: FocusTimer.State) -> Bool {
        switch (a, b) {
        case (.idle, .idle), (.running, .running), (.paused, .paused): return true
        default: return false
        }
    }

    private func rebuildButtons() {
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let views: [NSButton]
        switch tools.focus.timer.state {
        case .idle:
            views = [
                UI.button("Focus 25 min", symbol: "play.fill", color: .systemRed, target: self, action: #selector(focus25)),
                UI.button("Focus 50 min", target: self, action: #selector(focus50)),
                UI.button("Break 5 min", symbol: "cup.and.saucer", target: self, action: #selector(break5)),
            ]
        case .running:
            views = [
                UI.button("Pause", symbol: "pause.fill", color: .systemOrange, target: tools.focus, action: #selector(FocusController.pause)),
                UI.button("Stop", symbol: "stop.fill", target: tools.focus, action: #selector(FocusController.stop)),
            ]
        case .paused:
            views = [
                UI.button("Resume", symbol: "play.fill", color: .systemRed, target: tools.focus, action: #selector(FocusController.resume)),
                UI.button("Stop", symbol: "stop.fill", target: tools.focus, action: #selector(FocusController.stop)),
            ]
        }
        views.forEach(buttons.addArrangedSubview)
    }

    @objc private func focus25() { tools.focus.start(.focus, minutes: 25) }
    @objc private func focus50() { tools.focus.start(.focus, minutes: 50) }
    @objc private func break5() { tools.focus.start(.rest, minutes: 5) }
}

extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
