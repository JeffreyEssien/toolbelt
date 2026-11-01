import Foundation
import Testing
@testable import ToolbeltCore

struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func countsDownAndFinishesOnce() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 60, now: t0)
        #expect(timer.remaining(now: t0.addingTimeInterval(20)) == 40)
        #expect(timer.tick(now: t0.addingTimeInterval(59)) == false)
        #expect(timer.tick(now: t0.addingTimeInterval(60)) == true)
        #expect(timer.tick(now: t0.addingTimeInterval(61)) == false)
        #expect(timer.state == .idle)
    }

    @Test func pauseFreezesRemainingTime() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 100, now: t0)
        timer.pause(now: t0.addingTimeInterval(30))
        #expect(timer.remaining(now: t0.addingTimeInterval(500)) == 70)
        #expect(timer.tick(now: t0.addingTimeInterval(500)) == false)
        timer.resume(now: t0.addingTimeInterval(500))
        #expect(timer.remaining(now: t0.addingTimeInterval(510)) == 60)
        #expect(timer.tick(now: t0.addingTimeInterval(570)) == true)
    }

    @Test func stopClearsTimer() {
        var timer = FocusTimer()
        timer.start(.rest, duration: 300, now: t0)
        #expect(timer.kind == .rest)
        timer.stop()
        #expect(!timer.isActive)
        #expect(timer.remaining(now: t0) == nil)
    }

    @Test func pauseAndResumeIgnoredInWrongState() {
        var timer = FocusTimer()
        timer.pause(now: t0)
        #expect(timer.state == .idle)
        timer.start(.focus, duration: 10, now: t0)
        timer.resume(now: t0.addingTimeInterval(5))
        #expect(timer.state == .running(endsAt: t0.addingTimeInterval(10)))
    }
}

struct FocusLogTests {
    @Test func totalsOnlyTheRequestedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10)))
        let nextDay = day.addingTimeInterval(86_400)

        var log = FocusLog()
        log.record(FocusSession(end: day, length: 25 * 60))
        log.record(FocusSession(end: day.addingTimeInterval(3600), length: 50 * 60))
        log.record(FocusSession(end: nextDay, length: 25 * 60))

        #expect(log.sessions(on: day, calendar: calendar).count == 2)
        #expect(log.focusedTime(on: day, calendar: calendar) == 75 * 60)
    }

    @Test func dailyTotalsCoverEachDayOldestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 15)))
        var log = FocusLog()
        log.record(FocusSession(end: today, length: 25 * 60))
        log.record(FocusSession(end: today.addingTimeInterval(-2 * 86_400), length: 50 * 60))
        log.record(FocusSession(end: today.addingTimeInterval(-30 * 86_400), length: 25 * 60))

        let totals = log.dailyTotals(days: 7, endingOn: today, calendar: calendar)
        #expect(totals.count == 7)
        #expect(totals.map(\.time) == [0, 0, 0, 0, 50 * 60, 0, 25 * 60])
        #expect(totals.last?.day == calendar.startOfDay(for: today))
    }
}
