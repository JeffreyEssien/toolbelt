import Foundation

/// A countdown that can be paused. Time is always passed in, so the
/// logic can be tested without waiting for real seconds.
public struct FocusTimer: Equatable {
    public enum Kind: String, Codable, Equatable {
        case focus, rest
    }

    public enum State: Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    public private(set) var state: State = .idle
    public private(set) var kind: Kind = .focus
    public private(set) var duration: TimeInterval = 0
    public private(set) var startedAt: Date?

    public init() {}

    public var isActive: Bool { state != .idle }

    public mutating func start(_ kind: Kind, duration: TimeInterval, now: Date) {
        self.kind = kind
        self.duration = duration
        startedAt = now
        state = .running(endsAt: now.addingTimeInterval(duration))
    }

    public mutating func pause(now: Date) {
        guard case .running(let endsAt) = state else { return }
        state = .paused(remaining: max(0, endsAt.timeIntervalSince(now)))
    }

    public mutating func resume(now: Date) {
        guard case .paused(let remaining) = state else { return }
        state = .running(endsAt: now.addingTimeInterval(remaining))
    }

    public mutating func stop() {
        state = .idle
        startedAt = nil
    }

    public func remaining(now: Date) -> TimeInterval? {
        switch state {
        case .idle: return nil
        case .running(let endsAt): return max(0, endsAt.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        }
    }

    /// Call regularly. Returns true exactly once, when a running timer reaches zero.
    public mutating func tick(now: Date) -> Bool {
        guard case .running(let endsAt) = state, now >= endsAt else { return false }
        state = .idle
        return true
    }
}
