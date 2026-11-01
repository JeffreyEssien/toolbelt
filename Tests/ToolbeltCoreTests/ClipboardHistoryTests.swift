import Foundation
import Testing
@testable import ToolbeltCore

struct ClipboardHistoryTests {
    @Test func newestCopyComesFirst() {
        var history = ClipboardHistory()
        history.add("one")
        history.add("two")
        #expect(history.items.map(\.text) == ["two", "one"])
    }

    @Test func copyingAgainMovesItemToTopWithoutDuplicating() {
        var history = ClipboardHistory()
        history.add("one", at: Date(timeIntervalSince1970: 1))
        history.add("two", at: Date(timeIntervalSince1970: 2))
        history.add("one", at: Date(timeIntervalSince1970: 3))
        #expect(history.items.map(\.text) == ["one", "two"])
        #expect(history.items[0].copiedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func dropsOldestPastLimit() {
        var history = ClipboardHistory(limit: 3)
        for text in ["a", "b", "c", "d"] { history.add(text) }
        #expect(history.items.map(\.text) == ["d", "c", "b"])
    }

    @Test func ignoresBlankAndHugeText() {
        var history = ClipboardHistory()
        #expect(history.add("   \n\t") == false)
        #expect(history.add(String(repeating: "x", count: ClipboardHistory.maxTextLength + 1)) == false)
        #expect(history.items.isEmpty)
    }

    @Test func searchMatchesEveryWordIgnoringCaseAndAccents() {
        var history = ClipboardHistory()
        history.add("Café opening hours")
        history.add("cafe menu")
        history.add("dentist")
        #expect(history.search("CAFE hours").map(\.text) == ["Café opening hours"])
        #expect(history.search("cafe").count == 2)
        #expect(history.search("  ").count == 3)
    }

    @Test func removeAndClear() {
        var history = ClipboardHistory()
        history.add("keep")
        history.add("drop")
        history.remove(id: history.items[0].id)
        #expect(history.items.map(\.text) == ["keep"])
        history.clear()
        #expect(history.items.isEmpty)
    }

    @Test func previewSkipsBlankLeadingLines() {
        let item = ClipItem(text: "\n   \n  first line  \nsecond", copiedAt: Date())
        #expect(item.preview == "first line")
    }
}
