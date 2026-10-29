import XCTest
#if canImport(SipTimeCore)
@testable import SipTimeCore
#else
@testable import SipTime
#endif

final class CourseClockTests: XCTestCase {
    func testDefaultTeachingIntervalsFollowAllElevenSchoolBreaks() {
        let periods = CourseClock.periods(plan: ReminderPlan())
        XCTAssertEqual(periods.count, 12)
        XCTAssertEqual(periods.first, CourseClock.Period(start: 480, end: 530))
        XCTAssertEqual(periods[4], CourseClock.Period(start: 780, end: 830))
        XCTAssertEqual(periods.last, CourseClock.Period(start: 1240, end: 1290))
    }
    func testCourseHighlightStopsDuringBreakAndAtEnd() {
        let periods = CourseClock.periods(plan: ReminderPlan())
        XCTAssertEqual(CourseClock.activePeriod(at: 480, periods: periods), 1)
        XCTAssertEqual(CourseClock.activePeriod(at: 529.9, periods: periods), 1)
        XCTAssertNil(CourseClock.activePeriod(at: 530, periods: periods))
        XCTAssertEqual(CourseClock.activePeriod(at: 540, periods: periods), 2)
        XCTAssertNil(CourseClock.activePeriod(at: 1290, periods: periods))
    }
    func testIndicatorInterpolatesClassAndLunchAndHidesOutsideDay() {
        let periods = CourseClock.periods(plan: ReminderPlan())
        func y(_ minute: Double) -> Double? { CourseClock.position(at: minute, periods: periods, rowHeight: 88, gap: 2) }
        XCTAssertEqual(y(480), 0)
        XCTAssertEqual(y(505), 44)
        XCTAssertEqual(y(535), 89)
        XCTAssertEqual(y(750), 359) // Lunch is between the fourth and fifth rows.
        XCTAssertEqual(y(1290), 1078)
        XCTAssertNil(y(479))
        XCTAssertNil(y(1291))
    }
    func testCustomBreaksChangeClockButReminderOffsetAndPauseDoNot() {
        var plan = ReminderPlan()
        plan.slots[0].minute = 525
        plan.offsetMinutes = 15
        plan.enabled = false
        plan.pausedDay = LocalDay(Date())
        XCTAssertEqual(CourseClock.periods(plan: plan).first?.end, 525)
        plan.slots[1].minute = 524
        XCTAssertTrue(CourseClock.periods(plan: plan).isEmpty)
    }
    func testTodayColumnUsesLocalCalendarAndDisplayedSemesterWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        var plan = ReminderPlan()
        plan.termStart = LocalDay(monday, calendar: cal)
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9, minute: 25, second: 30))!
        XCTAssertEqual(CourseClock.weekday(on: today, displayedWeek: 1, plan: plan, calendar: cal), 4)
        XCTAssertNil(CourseClock.weekday(on: today, displayedWeek: 2, plan: plan, calendar: cal))
        XCTAssertEqual(CourseClock.minute(on: today, calendar: cal), 565.5)
    }
}
