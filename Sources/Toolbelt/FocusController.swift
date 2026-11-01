import AppKit
import ToolbeltCore

/// Pomodoro-style focus sessions and breaks, with a log of finished sessions.
final class FocusController: NSObject {
    var onChange: (() -> Void)?

    private(set) var timer = FocusTimer()
    private(set) var log: FocusLog
    private let store = JSONStore<FocusLog>(url: Paths.focusLog)
    private var ticker: Timer?

    override init() {
        log = store.load() ?? FocusLog()
        super.init()
    }

    var remaining: TimeInterval? { timer.remaining(now: Date()) }

    /// 0 at the start of a session, 1 when it's done.
    var progress: Double {
        guard let remaining, timer.duration > 0 else { return 0 }
        return 1 - remaining / timer.duration
    }

    var todayCount: Int { log.sessions(on: Date()).count }
    var todayTime: TimeInterval { log.focusedTime(on: Date()) }

    var todaySummary: String {
        todayCount == 0
            ? "No sessions yet today"
            : "\(todayCount) \(todayCount == 1 ? "session" : "sessions") · \(Formatting.duration(todayTime)) today"
    }

    /// "12:34" for the menu bar while a session runs, nil otherwise.
    var menuBarText: String? {
        guard let remaining else { return nil }
        let clock = Formatting.clock(remaining)
        if case .paused = timer.state { return "⏸ \(clock)" }
        return timer.kind == .rest ? "☕︎ \(clock)" : clock
    }

    /// The shortcut's item is the one the hotkey does: start 25 min, pause or resume.
    func addItems(to menu: NSMenu, shortcut: Shortcut?) {
        menu.addInfo("Focus")
        switch timer.state {
        case .idle:
            menu.addAction("Focus for 25 min", target: self, action: #selector(startFocus(_:)), represented: 25)
                .showShortcut(shortcut)
            menu.addAction("Focus for 50 min", target: self, action: #selector(startFocus(_:)), represented: 50)
            menu.addAction("Break for 5 min", target: self, action: #selector(startBreak(_:)), represented: 5)
        case .running:
            menu.addAction("Pause", target: self, action: #selector(pause)).showShortcut(shortcut)
            menu.addAction("Stop", target: self, action: #selector(stop))
        case .paused:
            menu.addAction("Resume", target: self, action: #selector(resume)).showShortcut(shortcut)
            menu.addAction("Stop", target: self, action: #selector(stop))
        }
        menu.addInfo(todaySummary)
    }

    /// For the hotkey: starts a 25 minute session, or pauses or resumes the current one.
    func toggle() {
        switch timer.state {
        case .idle:
            start(.focus, minutes: 25)
            Notifier.shared.post(title: "Focus started", body: "25 minutes. You've got this.")
        case .running: pause()
        case .paused: resume()
        }
    }

    @objc private func startFocus(_ sender: NSMenuItem) {
        start(.focus, minutes: sender.representedObject as? Int ?? 25)
    }

    @objc private func startBreak(_ sender: NSMenuItem) {
        start(.rest, minutes: sender.representedObject as? Int ?? 5)
    }

    func start(_ kind: FocusTimer.Kind, minutes: Int) {
        timer.start(kind, duration: TimeInterval(minutes * 60), now: Date())
        startTicking()
        onChange?()
    }

    @objc func pause() {
        timer.pause(now: Date())
        onChange?()
    }

    @objc func resume() {
        timer.resume(now: Date())
        onChange?()
    }

    @objc func stop() {
        timer.stop()
        stopTicking()
        onChange?()
    }

    private func startTicking() {
        stopTicking()
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        // .common keeps the countdown moving while the menu is open.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let now = Date()
        if timer.tick(now: now) {
            stopTicking()
            finished(timer.kind, length: timer.duration, at: now)
        }
        onChange?()
    }

    private func finished(_ kind: FocusTimer.Kind, length: TimeInterval, at date: Date) {
        switch kind {
        case .focus:
            log.record(FocusSession(end: date, length: length))
            try? store.save(log)
            Notifier.shared.post(title: "Focus session done", body: "\(Formatting.duration(length)) of focus. Time for a break.")
        case .rest:
            Notifier.shared.post(title: "Break's over", body: "Ready for another focus session?")
        }
    }
}
