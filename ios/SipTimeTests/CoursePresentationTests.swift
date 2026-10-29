import XCTest
#if canImport(SipTimeCore)
@testable import SipTimeCore
#else
@testable import SipTime
#endif

final class CoursePresentationTests: XCTestCase {
    func testPersonalRemarkIsDisplayNameWithoutChangingImportedTitle() {
        var course = exampleCourse()
        course.remark = "  数统 🧪\n"
        XCTAssertEqual(course.displayTitle, "数统 🧪")
        XCTAssertEqual(course.title, "数理统计（荣誉课程）")
        XCTAssertEqual(course.remark, "  数统 🧪\n")
    }

    func testBlankAndUnicodeWhitespaceRemarksFallBackToFullName() {
        for blank in ["", " \t\r\n", "\u{00a0}\u{3000}\u{2003}\n"] {
            var course = exampleCourse()
            course.remark = blank
            XCTAssertEqual(course.displayTitle, course.title)
        }
    }

    func testOldStateWithCoursesButWithoutRemarksPreservesAllStoredData() throws {
        var original = LocalState()
        original.accountID = "existing-account"
        original.plan.school = "北京大学"
        original.plan.rules = [ReminderRule(weekday: 3, minute: 11 * 60, kind: .even)]
        original.notes = [FriendNote(id: "existing-note", text: "记得喝水", senderName: "同学", createdAt: "2026-10-29")]
        original.timetable = CourseTimetable(courses: [exampleCourse()])
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var timetableJSON = try XCTUnwrap(legacyJSON["timetable"] as? [String: Any])
        var courseJSON = try XCTUnwrap((timetableJSON["courses"] as? [[String: Any]])?.first)
        courseJSON.removeValue(forKey: "remark")
        timetableJSON["courses"] = [courseJSON]
        legacyJSON["timetable"] = timetableJSON

        let decoded = try JSONDecoder().decode(LocalState.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        let course = try XCTUnwrap(decoded.timetable?.courses.first)
        XCTAssertEqual(course, original.timetable?.courses.first)
        XCTAssertEqual(course.remark, "")
        XCTAssertEqual(course.displayTitle, original.timetable?.courses.first?.title)
        XCTAssertEqual(course.meetings.map(\.id), ["meeting-odd", "meeting-even"])
        XCTAssertEqual(decoded.accountID, original.accountID)
        XCTAssertEqual(decoded.plan.school, original.plan.school)
        XCTAssertEqual(decoded.plan.rules.first?.id, original.plan.rules.first?.id)
        XCTAssertEqual(decoded.notes.first?.text, "记得喝水")
    }

    func testRemarkAndCompleteCourseDetailsPersistAcrossStateRoundTrip() throws {
        var course = exampleCourse()
        course.remark = "数统 · 周老师"
        var state = LocalState()
        state.timetable = CourseTimetable(courses: [course])
        let restored = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.timetable, state.timetable)
        let result = try XCTUnwrap(restored.timetable?.courses.first)
        XCTAssertEqual(result.id, "course-existing")
        XCTAssertEqual(result.displayTitle, "数统 · 周老师")
        XCTAssertEqual(result.title, "数理统计（荣誉课程）")
        XCTAssertEqual(result.number, "00135460")
        XCTAssertEqual(result.teacher, "周晓华（教授）")
        XCTAssertEqual(result.meetings, course.meetings)
    }

    func testNumberedReimportUpdatesSchoolDataAndKeepsPersonalRemarkAndIdentity() throws {
        var existing = exampleCourse()
        existing.remark = "数统"
        var imported = existing
        imported.id = "new-import-id"
        imported.title = "数理统计（更新后的全名）"
        imported.teacher = "新授课教师"
        imported.meetings = [CourseMeeting(weekday: 5, startPeriod: 5, endPeriod: 6, location: "理教301")]
        imported.remark = ""

        let timetable = CourseTimetable(courses: [existing])
        let updated = timetable.merging([imported], schoolID: "pku")
        let result = try XCTUnwrap(updated.courses.first)
        XCTAssertEqual(updated.courses.count, 1)
        XCTAssertEqual(result.id, existing.id)
        XCTAssertEqual(result.remark, "数统")
        XCTAssertEqual(result.displayTitle, "数统")
        XCTAssertEqual(result.title, imported.title)
        XCTAssertEqual(result.teacher, imported.teacher)
        XCTAssertEqual(result.meetings, imported.meetings)
        XCTAssertEqual(updated.merging([imported], schoolID: "pku"), updated)
    }

    func testTitleMatchedReimportRetainsRemarkAndNewCourseKeepsOwnRemark() throws {
        var existing = exampleCourse()
        existing.number = ""
        existing.remark = "我喜欢的数统课"
        var imported = existing
        imported.id = "reimport"
        imported.remark = ""
        let newCourse = Course(title: "概率论", meetings: [], remark: "概率")
        let result = CourseTimetable(courses: [existing]).merging([imported, newCourse], schoolID: "pku")
        XCTAssertEqual(result.courses.count, 2)
        XCTAssertEqual(result.courses[0].id, existing.id)
        XCTAssertEqual(result.courses[0].remark, "我喜欢的数统课")
        XCTAssertEqual(result.courses[1].displayTitle, "概率")
    }

    func testClearingSavedRemarkRestoresFullTitle() throws {
        var course = exampleCourse()
        course.remark = "数统"
        course.remark = ""
        let restored = try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(course))
        XCTAssertEqual(restored.displayTitle, restored.title)
        XCTAssertEqual(restored.remark, "")
    }

    private func exampleCourse() -> Course {
        Course(id: "course-existing", title: "数理统计（荣誉课程）", number: "00135460", teacher: "周晓华（教授）", meetings: [
            CourseMeeting(id: "meeting-odd", weekday: 1, startPeriod: 7, endPeriod: 8, startWeek: 1, endWeek: 16,
                          kind: .odd, weeks: [1, 3, 5, 7], location: "理教309"),
            CourseMeeting(id: "meeting-even", weekday: 3, startPeriod: 5, endPeriod: 6, startWeek: 2, endWeek: 16,
                          kind: .even, location: "二教407")
        ])
    }
}
