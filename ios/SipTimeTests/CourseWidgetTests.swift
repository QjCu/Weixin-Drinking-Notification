import XCTest
#if canImport(SipTimeCore)
@testable import SipTimeCore
#else
@testable import SipTime
#endif

final class CourseWidgetTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func snapshot() -> CourseWidgetSnapshot {
        var plan = ReminderPlan()
        plan.termStart = LocalDay(date(26), calendar: cal)
        return CourseWidgetSnapshot(plan: plan, timetable: CourseTimetable(courses: [
            Course(title: "数学全称", teacher: "教师", meetings: [CourseMeeting(weekday: 1, startPeriod: 1, endPeriod: 2, kind: .odd, location: "理教103")], remark: "数学"),
            Course(title: "双周课", meetings: [CourseMeeting(weekday: 1, startPeriod: 1, endPeriod: 2, kind: .even)])
        ]))
    }
    func testWidgetUsesSemesterParityAliasAndActualTimes() throws {
        let lessons = CourseWidgetEngine.lessons(on: date(26), snapshot: snapshot(), calendar: cal)
        XCTAssertEqual(lessons.count, 1)
        let lesson = try XCTUnwrap(lessons.first)
        XCTAssertEqual(lesson.course.displayTitle, "数学")
        XCTAssertEqual(lesson.meeting.location, "理教103")
        XCTAssertEqual(lesson.start, date(26, 8))
        XCTAssertEqual(lesson.end, date(26, 9, 50))
        XCTAssertTrue(lesson.isOngoing(at: date(26, 8, 30)))
        XCTAssertFalse(lesson.isOngoing(at: date(26, 8, 55)))
        XCTAssertFalse(lesson.isOngoing(at: date(26, 9, 50)))
    }
    func testNoClassesOutsideTermAndNextDayLookup() {
        let s = snapshot()
        XCTAssertTrue(CourseWidgetEngine.lessons(on: date(25), snapshot: s, calendar: cal).isEmpty)
        XCTAssertEqual(CourseWidgetEngine.upcoming(after: date(25, 22), snapshot: s, calendar: cal)?.course.displayTitle, "数学")
        XCTAssertEqual(CourseWidgetEngine.upcoming(after: date(26, 10), snapshot: s, calendar: cal)?.course.title, "双周课")
    }
    func testNextClassCanSkipAnEmptyEvenWeek() throws {
        var s = snapshot()
        s.timetable.courses.removeLast()
        let next = try XCTUnwrap(CourseWidgetEngine.upcoming(after: date(26, 10), snapshot: s, calendar: cal))
        XCTAssertEqual(cal.dateComponents([.day], from: date(26), to: cal.startOfDay(for: next.start)).day, 14)
        XCTAssertEqual(next.course.displayTitle, "数学")
    }
    func testSnapshotDoesNotContainAccountsOrFriendNotes() throws {
        let encoded = try JSONEncoder().encode(snapshot())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["plan", "timetable"])
        let restored = try JSONDecoder().decode(CourseWidgetSnapshot.self, from: encoded)
        XCTAssertEqual(restored.timetable.courses.first?.remark, "数学")
    }
    func testRefreshIncludesClassAndBreakBoundariesAndMidnight() {
        let dates = CourseWidgetEngine.refreshDates(after: date(26, 7), snapshot: snapshot(), calendar: cal)
        for expected in [date(26, 8), date(26, 8, 50), date(26, 9), date(26, 9, 50), date(27)] { XCTAssertTrue(dates.contains(expected)) }
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertTrue(dates.allSatisfy { $0 > date(26, 7) })
    }
    func testDisabledRemindersDoNotDisableClassesAndInvalidPeriodsAreSkipped() {
        var s = snapshot()
        s.plan.enabled = false
        XCTAssertEqual(CourseWidgetEngine.lessons(on: date(26), snapshot: s, calendar: cal).count, 1)
        s.timetable.courses[0].meetings[0].endPeriod = 24
        XCTAssertTrue(CourseWidgetEngine.lessons(on: date(26), snapshot: s, calendar: cal).isEmpty)
    }
}
