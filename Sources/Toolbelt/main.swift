import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A normal app with a Dock icon and window, plus the menu bar icon.
app.setActivationPolicy(.regular)
app.run()
