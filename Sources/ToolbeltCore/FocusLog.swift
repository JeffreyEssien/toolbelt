import Foundation

public struct FocusSession: Codable, Equatable {
    /// When the session finished.
    public var end: Date
    /// Planned length. Time spent paused isn't counted.
    public var length: TimeInterval

    public init(end: Date, length: TimeInterval) {
        self.end = end
        self.length = length
    }
}

/// Completed focus sessions. Breaks and stopped sessions are not logged.
public struct FocusLog: Codable, Equatable {
    public private(set) var sessions: [FocusSession] = []

    public init(sessions: [FocusSession] = []) {
        self.sessions = sessions
    }

    public mutating func record(_ session: FocusSession) {
        sessions.append(session)
    }

    public func sessions(on day: Date, calendar: Calendar = .current) -> [FocusSession] {
        sessions.filter { calendar.isDate($0.end, inSameDayAs: day) }
    }

    public func focusedTime(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        sessions(on: day, calendar: calendar).reduce(0) { $0 + $1.length }
    }

    /// Focus time for each of the last `days` days, oldest first, ending with `day`.
    public func dailyTotals(days: Int, endingOn day: Date, calendar: Calendar = .current) -> [(day: Date, time: TimeInterval)] {
        let end = calendar.startOfDay(for: day)
        return (0..<max(0, days)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return (date, focusedTime(on: date, calendar: calendar))
        }
    }
}
