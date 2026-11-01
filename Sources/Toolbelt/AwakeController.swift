import AppKit
import IOKit.pwr_mgt
import ToolbeltCore

/// Keeps the Mac and its display awake, like the `caffeinate` command.
final class AwakeController: NSObject {
    var onChange: (() -> Void)?

    private var assertionID: IOPMAssertionID = 0
    private(set) var isAwake = false
    private(set) var until: Date?
    private var endTimer: Timer?

    /// "Until 15:30", "Until you turn it off" or "Off".
    var statusText: String {
        guard isAwake else { return "Off" }
        guard let until else { return "Until you turn it off" }
        return "Until \(until.formatted(date: .omitted, time: .shortened))"
    }

    func addItems(to menu: NSMenu, shortcut: Shortcut?) {
        menu.addInfo("Keep awake")
        if isAwake {
            if let until {
                let time = until.formatted(date: .omitted, time: .shortened)
                menu.addInfo("Awake until \(time)")
            } else {
                menu.addInfo("Awake until you turn it off")
            }
            menu.addAction("Let the Mac sleep", target: self, action: #selector(turnOff)).showShortcut(shortcut)
        } else {
            menu.addAction("For 1 hour", target: self, action: #selector(keepAwake(_:)), represented: 60)
            menu.addAction("For 2 hours", target: self, action: #selector(keepAwake(_:)), represented: 120)
            menu.addAction("Until I turn it off", target: self, action: #selector(keepAwake(_:)), represented: 0)
                .showShortcut(shortcut)
        }
    }

    /// For the hotkey: on until you turn it off, or off again.
    func toggle() {
        if isAwake {
            turnOff()
            Notifier.shared.post(title: "Keep awake is off", body: "Your Mac can sleep normally again.")
        } else {
            keepAwake(minutes: 0)
            Notifier.shared.post(title: "Keep awake is on", body: "Your Mac will stay awake until you turn it off.")
        }
    }

    @objc private func keepAwake(_ sender: NSMenuItem) {
        keepAwake(minutes: sender.representedObject as? Int ?? 0)
    }

    /// 0 minutes means until it's turned off.
    func keepAwake(minutes: Int) {
        turnOff()
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Toolbelt: keep awake" as CFString, &assertionID)
        guard result == kIOReturnSuccess else { return }
        isAwake = true
        if minutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            until = end
            let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.turnOff() }
            RunLoop.main.add(timer, forMode: .common)
            endTimer = timer
        }
        onChange?()
    }

    @objc func turnOff() {
        endTimer?.invalidate()
        endTimer = nil
        until = nil
        if isAwake {
            IOPMAssertionRelease(assertionID)
            isAwake = false
        }
        onChange?()
    }
}
