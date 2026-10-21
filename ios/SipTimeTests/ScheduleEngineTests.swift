import XCTest
#if canImport(SipTimeCore)
@testable import SipTimeCore
#else
@testable import SipTime
#endif

final class ScheduleEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }
    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func plan() -> ReminderPlan {
        var plan = ReminderPlan()
        plan.termStart = LocalDay(date(2026, 10, 19), calendar: calendar) // Monday
        return plan
    }
    func testSemesterParityAndSundayBoundary() {
        let plan = plan()
        XCTAssertNil(ScheduleEngine.weekNumber(on: date(2026, 10, 18), plan: plan, calendar: calendar))
        XCTAssertEqual(ScheduleEngine.weekNumber(on: date(2026, 10, 19), plan: plan, calendar: calendar), 1)
        XCTAssertEqual(ScheduleEngine.weekNumber(on: date(2026, 10, 25, 23, 59), plan: plan, calendar: calendar), 1)
        XCTAssertEqual(ScheduleEngine.weekNumber(on: date(2026, 10, 26), plan: plan, calendar: calendar), 2)
    }
    func testOddAndEvenRules() {
        var plan = plan()
        plan.termWeeks = 3
        plan.rules = [ReminderRule(weekday: 1, minute: 600, kind: .odd),
                      ReminderRule(weekday: 1, minute: 660, kind: .even)]
        let dates = ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 10, 19, 10), date(2026, 10, 26, 11), date(2026, 11, 2, 10)])
    }
    func testPauseTodayRetainsFutureRules() {
        var plan = plan()
        plan.rules = [ReminderRule(weekday: 1, minute: 600, kind: .all)]
        plan.pausedDay = LocalDay(date(2026, 10, 19), calendar: calendar)
        XCTAssertEqual(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), limit: 1, calendar: calendar),
                       [date(2026, 10, 26, 10)])
    }
    func testEditingSlotChangesExistingSelectionAndAppliesOffset() {
        var plan = plan()
        plan.slots = [BreakSlot(title: "课间", minute: 580)]
        plan.rules = [ReminderRule(weekday: 1, minute: 580, kind: .all, slotID: plan.slots[0].id)]
        plan.slots[0].minute = 600
        plan.offsetMinutes = 5
        XCTAssertEqual(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), limit: 1, calendar: calendar),
                       [date(2026, 10, 19, 10, 5)])
        plan.offsetMinutes = 20
        XCTAssertTrue(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), calendar: calendar).isEmpty)
    }
    func testDuplicateTimesCollapseAndPastTimesExcluded() {
        var plan = plan()
        plan.rules = [ReminderRule(weekday: 1, minute: 600, kind: .all),
                      ReminderRule(weekday: 1, minute: 600, kind: .odd),
                      ReminderRule(weekday: 1, minute: 660, kind: .all)]
        XCTAssertEqual(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19, 10), limit: 1, calendar: calendar),
                       [date(2026, 10, 19, 11)])
        XCTAssertEqual(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), limit: 2, calendar: calendar),
                       [date(2026, 10, 19, 10), date(2026, 10, 19, 11)])
    }
    func testNotificationCapAndTermEnd() {
        var plan = plan()
        plan.rules = (1...7).flatMap { day in (8...20).map { ReminderRule(weekday: day, minute: $0 * 60, kind: .all) } }
        XCTAssertEqual(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), calendar: calendar).count, 60)
        plan.termWeeks = 1
        XCTAssertEqual(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 25, 19), calendar: calendar),
                       [date(2026, 10, 25, 20)])
        plan.enabled = false
        XCTAssertTrue(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), calendar: calendar).isEmpty)
    }
    func testYearBoundaryUsesSemesterWeeks() {
        var plan = plan()
        plan.termStart = LocalDay(date(2026, 12, 28), calendar: calendar)
        XCTAssertEqual(ScheduleEngine.weekNumber(on: date(2027, 1, 4), plan: plan, calendar: calendar), 2)
    }
    func testMissingSlotNeverBecomesAnOrdinaryReminder() {
        var plan = plan()
        plan.rules = [ReminderRule(weekday: 1, minute: 600, kind: .all, slotID: "deleted")]
        XCTAssertTrue(ScheduleEngine.dates(plan: plan, after: date(2026, 10, 19), calendar: calendar).isEmpty)
    }
    func testDaylightSavingDoesNotShiftNonexistentTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        var plan = plan()
        plan.termStart = LocalDay(start, calendar: cal)
        plan.termWeeks = 1
        plan.rules = [ReminderRule(weekday: 7, minute: 150, kind: .all)] // March 8, 02:30 doesn't exist
        XCTAssertTrue(ScheduleEngine.dates(plan: plan, after: start, calendar: cal).isEmpty)
    }
    func testStateRoundTripPreservesNotesAndCalendarDay() throws {
        var state = LocalState()
        state.plan = plan()
        state.notes = [FriendNote(id: "n1", text: "喝水啦", senderName: "小林", createdAt: "2026-10-21T00:00:00+00:00")]
        state.assignments = [NoteAssignment(noteID: "n1", date: date(2026, 10, 21, 10))]
        let copy = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(copy.plan.termStart, state.plan.termStart)
        XCTAssertEqual(copy.notes[0].text, "喝水啦")
        XCTAssertEqual(copy.assignments[0].date, state.assignments[0].date)
    }
}
