import Foundation

public struct ClipItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var copiedAt: Date

    public init(id: UUID = UUID(), text: String, copiedAt: Date) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }

    /// First non-empty line, trimmed, for showing in a list.
    public var preview: String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }
}

/// Text the user copied, newest first. Copying something already in the
/// history moves it back to the top instead of adding a duplicate.
public struct ClipboardHistory: Codable, Equatable {
    public private(set) var items: [ClipItem] = []
    public var limit: Int

    /// Anything longer is skipped so one huge copy can't bloat the history file.
    public static let maxTextLength = 200_000

    public init(limit: Int = 50, items: [ClipItem] = []) {
        self.limit = max(1, limit)
        self.items = Array(items.prefix(self.limit))
    }

    /// Returns false when the text was ignored (blank or too long).
    @discardableResult
    public mutating func add(_ text: String, at date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maxTextLength else { return false }
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.copiedAt = date
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(text: text, copiedAt: date), at: 0)
            if items.count > limit { items.removeLast(items.count - limit) }
        }
        return true
    }

    /// Case- and accent-insensitive match on every word of the query.
    public func search(_ query: String) -> [ClipItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            words.allSatisfy { item.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func clear() {
        items.removeAll()
    }
}
