import Foundation
import Testing
@testable import ToolbeltCore

struct FormattingTests {
    @Test func clock() {
        #expect(Formatting.clock(1500) == "25:00")
        #expect(Formatting.clock(65) == "1:05")
        #expect(Formatting.clock(3723) == "1:02:03")
        #expect(Formatting.clock(0.2) == "0:01")
    }

    @Test func duration() {
        #expect(Formatting.duration(45 * 60) == "45 min")
        #expect(Formatting.duration(2 * 3600) == "2 h")
        #expect(Formatting.duration(75 * 60) == "1 h 15 min")
    }

    @Test func batteryHealth() {
        #expect(Formatting.batteryHealth(maxCapacity: 4500, designCapacity: 5000) == 90)
        #expect(Formatting.batteryHealth(maxCapacity: 5200, designCapacity: 5000) == 100)
        #expect(Formatting.batteryHealth(maxCapacity: 0, designCapacity: 5000) == nil)
    }
}

struct JSONStoreTests {
    @Test func roundTripsAndCreatesFolders() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolbelt-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONStore<ClipboardHistory>(url: dir.appendingPathComponent("nested/clipboard.json"))

        #expect(store.load() == nil)
        var history = ClipboardHistory()
        history.add("hello", at: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(history)
        #expect(store.load() == history)
    }

    @Test func unreadableFileLoadsAsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toolbelt-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(JSONStore<FocusLog>(url: url).load() == nil)
    }
}
