import XCTest
#if canImport(SipTimeCore)
@testable import SipTimeCore
#else
@testable import SipTime
#endif

final class CourseImportTests: XCTestCase {
    func testPKUHTMLKeepsSelectedRowsAndAllMeetings() {
        let html = """
        <table><tr><th>课程号</th><th>课程名</th><th>教师</th><th>教室信息</th><th>选课结果</th></tr>
        <tr><td>00131300</td><td>概率论</td><td>章复熹</td><td>1~16周 双周周四1~2节 二教407<br/>1~16周 每周周二3~4节 二教407<br>考试时间：20261229上午</td><td>已选上</td></tr>
        <tr><td>02131310</td><td>中国传统官僚政治制度</td><td>叶炜</td><td>1~16周 每周周二10~11节 二教207</td><td>未选上</td></tr>
        <tr><td>02333100</td><td>分析哲学概论</td><td>李麒麟</td><td>1~16周 每周周三10~11节</td><td>候补</td></tr></table>
        """
        let result = CourseImportParser.parse(html: html)
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.courses[0].teacher, "章复熹")
        XCTAssertEqual(result.courses[0].meetings.count, 2)
        XCTAssertEqual(result.courses[0].meetings[0].kind, .even)
        XCTAssertEqual(result.courses[0].meetings[0].weekday, 4)
        XCTAssertEqual(result.courses[0].meetings[0].location, "二教407")
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testTextKeepsIndependentMeetingsAndExcludesUnselected() {
        let text = """
        00132330\t偏微分方程\t任选\t3.0\t1~16周 单周周五3~4节 理教103；1~16周 每周周四5~6节 理教103\t已选上
        02131310\t中国传统官僚政治制度\t通识课\t1~16周 每周周二10~11节 二教207\t未选上
        """
        let result = CourseImportParser.parse(text: text)
        XCTAssertEqual(result.courses.map(\.title), ["偏微分方程"])
        XCTAssertEqual(result.courses[0].meetings.map(\.weekday), [5, 4])
        XCTAssertEqual(result.courses[0].meetings.map(\.kind), [.odd, .all])
    }

    func testExplicitWeeksAndFullWidthPunctuation() {
        let result = CourseImportParser.parse(text: "00131300\t测试课程\t第１～４，８，１０～１２周 单周星期日第１～２节 教室A\t已选上")
        let meeting = try! XCTUnwrap(result.courses.first?.meetings.first)
        XCTAssertEqual(meeting.weeks, [1, 2, 3, 4, 8, 10, 11, 12])
        XCTAssertTrue(meeting.isActive(in: 3))
        XCTAssertFalse(meeting.isActive(in: 8))
        XCTAssertFalse(meeting.isActive(in: 9))
        XCTAssertEqual(meeting.weekday, 7)
    }

    func testUnknownSelectionStatusRequiresReview() {
        let result = CourseImportParser.parse(text: "00131300\t概率论\t1~16周 每周周二3~4节 二教407")
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("无法确认已选上") }))
    }

    func testInvalidAndTruncatedSchedulesAreNotGuessed() {
        for text in ["00131300\t概率论\t16~1周 每周周二3~4节 已选上",
                     "00131300\t概率论\t1~16周 每周周二5~3节 已选上",
                     "00131300\t概率论\t1~16周 双周周四1~ 已选上",
                     "00131300\t概率论\t考试时间：20261229上午 已选上"] {
            let result = CourseImportParser.parse(text: text)
            XCTAssertTrue(result.courses.isEmpty, text)
            XCTAssertFalse(result.warnings.isEmpty)
        }
    }

    func testRepeatedRowsMergeWithoutDuplicateMeetings() {
        let row = "00131300\t概率论\t1~16周 每周周二3~4节 二教407\t已选上"
        let result = CourseImportParser.parse(text: row + "\n" + row)
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.courses[0].meetings.count, 1)
    }

    func testOCRGeometryAssociatesMultilineTeachingWithItsCourseAndRejectsUnselected() {
        let lines = [
            line("00131300", x: 0.03, y: 0.8), line("概率论", x: 0.08, y: 0.8),
            line("1~16周 双周周四1~2节 二教407", x: 0.56, y: 0.82),
            line("1~16周 每周周二3~4节 二教407", x: 0.56, y: 0.795),
            line("已选上", x: 0.82, y: 0.8),
            line("02131310", x: 0.03, y: 0.65), line("中国传统官僚政治制度", x: 0.08, y: 0.65),
            line("1~16周 每周周二10~11节 二教207", x: 0.56, y: 0.65), line("未选上", x: 0.82, y: 0.65)
        ]
        let result = CourseImportParser.parse(lines: lines)
        XCTAssertEqual(result.courses.map(\.title), ["概率论"])
        XCTAssertEqual(result.courses[0].meetings.count, 2)
    }

    func testOCRMixedMergedNamesDoesNotTreatExamDatesAsCourseAnchors() {
        let lines = [
            line("00131300 概率论", x: 0.03, y: 0.8),
            line("1~16周 双周周四1~2节 二教407", x: 0.56, y: 0.82),
            line("1~16周 每周周二3~4节 二教407", x: 0.56, y: 0.795),
            line("20261229", x: 0.62, y: 0.77), line("已选上", x: 0.82, y: 0.8),
            line("00132330", x: 0.03, y: 0.65), line("偏微分方程", x: 0.08, y: 0.65),
            line("1~16周 每周周四5~6节 理教103", x: 0.56, y: 0.65), line("已选上", x: 0.82, y: 0.65)
        ]
        let result = CourseImportParser.parse(lines: lines)
        XCTAssertEqual(result.courses.map(\.title), ["概率论", "偏微分方程"])
        XCTAssertEqual(result.courses.map(\.number), ["00131300", "00132330"])
        XCTAssertEqual(result.courses[0].meetings.count, 2)
    }

    func testValidAndTruncatedMeetingsRaisePartialImportWarning() {
        let result = CourseImportParser.parse(text: "00131300\t概率论\t1~16周 每周周二3~4节 二教407；1~16周 双周周四1~ 已选上")
        XCTAssertEqual(result.courses.first?.meetings.count, 1)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("部分上课安排") }))
    }

    func testWholeProvidedSelectionTableHasEightSelectedCoursesThirteenMeetings() {
        let text = """
        00131300\t概率论\t1~16周 双周周四1~2节 二教407；1~16周 每周周二3~4节 二教407\t已选上
        00132330\t偏微分方程\t1~16周 单周周五3~4节 理教103；1~16周 每周周四5~6节 理教103\t已选上
        00135460\t数理统计\t1~16周 双周周三5~6节 理教309；1~16周 每周周一7~8节 理教309\t已选上
        01034310\t普通化学\t1~16周 每周周一3~4节 二教102；1~16周 每周周五1~2节 二教102\t已选上
        02131310\t中国传统官僚政治制度\t1~16周 每周周二10~11节 二教207\t未选上
        02333100\t分析哲学概论\t1~16周 每周周三10~11节(备注:一教101)\t未选上
        02533160\t经济学原理(I)\t1~16周 每周周二7~9节 二教101\t已选上
        04130103\t排球提高班\t1~16周 每周周二1~2节(备注:一体)\t已选上
        00134330\t金融经济学\t1~16周 每周周一5~6节 二教416；1~16周 单周周四3~4节 二教416\t已选上
        02533161\t经济学原理(I)讨论课\t1~16周 每周周四11~11节(备注:地学楼208)\t已选上
        """
        let result = CourseImportParser.parse(text: text)
        XCTAssertEqual(result.courses.count, 8)
        XCTAssertEqual(result.courses.flatMap(\.meetings).count, 13)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.courses.last!.meetings[0].location.contains("地学楼208"))
        let oddMonday = TimetableEngine.entries(courses: result.courses, week: 3, weekday: 1, period: 5)
        XCTAssertEqual(oddMonday.map(\.course.title), ["金融经济学"])
        let evenMonday = TimetableEngine.entries(courses: result.courses, week: 4, weekday: 1, period: 5)
        XCTAssertEqual(evenMonday.map(\.course.title), ["金融经济学"])
        let evenWednesday = TimetableEngine.entries(courses: result.courses, week: 4, weekday: 3, period: 5)
        XCTAssertEqual(evenWednesday.map(\.course.title), ["数理统计"])
    }

    func testActiveAlternatingCourseHidesInactiveCourse() {
        let courses = [course("单周课", kind: .odd), course("双周课", kind: .even)]
        XCTAssertEqual(TimetableEngine.entries(courses: courses, week: 3, weekday: 1, period: 2).map(\.course.title), ["单周课"])
        XCTAssertEqual(TimetableEngine.entries(courses: courses, week: 4, weekday: 1, period: 2).map(\.course.title), ["双周课"])
    }

    func testInactiveCourseGhostAndPartialOverlapResolvedPerPeriod() {
        var odd = course("单周课", kind: .odd)
        odd.meetings[0].endPeriod = 3
        let even = course("双周课", kind: .even)
        let courses = [odd, even]
        let overlap = TimetableEngine.entries(courses: courses, week: 2, weekday: 1, period: 2)
        XCTAssertEqual(overlap.map(\.course.title), ["双周课"])
        let ghost = TimetableEngine.entries(courses: courses, week: 2, weekday: 1, period: 3)
        XCTAssertEqual(ghost.map(\.course.title), ["单周课"])
        XCTAssertFalse(ghost[0].isActive)
    }

    func testGenuineActiveConflictKeepsBothAndWeekRangeBoundaries() {
        let courses = [course("每周A", kind: .all), course("每周B", kind: .all)]
        XCTAssertEqual(TimetableEngine.entries(courses: courses, week: 1, weekday: 1, period: 1).count, 2)
        XCTAssertTrue(courses[0].meetings[0].isActive(in: 16))
        XCTAssertFalse(courses[0].meetings[0].isActive(in: 17))
    }

    func testCourseTimetablePersistenceRoundTrip() throws {
        let state = CourseTimetable(courses: [course("概率论", kind: .even)])
        let copy = try JSONDecoder().decode(CourseTimetable.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state, copy)
    }

    func testOldLocalStateDecodesAndCourseRoundTripPreservesOtherData() throws {
        var state = LocalState()
        state.accountID = "account-1"
        state.plan.school = "我的学校"
        state.plan.rules = [ReminderRule(weekday: 2, minute: 600, kind: .odd)]
        state.notes = [FriendNote(id: "note-1", text: "记得喝水", senderName: "好友", createdAt: "2026-10-25")]
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        oldJSON.removeValue(forKey: "timetable")
        let legacy = try JSONDecoder().decode(LocalState.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertNil(legacy.timetable)
        XCTAssertEqual(legacy.accountID, state.accountID)
        XCTAssertEqual(legacy.plan.rules.count, 1)
        XCTAssertEqual(legacy.notes.first?.text, "记得喝水")
        state.timetable = CourseTimetable(courses: [course("概率论", kind: .even)])
        let updated = try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(updated.timetable, state.timetable)
        XCTAssertEqual(updated.accountID, state.accountID)
        XCTAssertEqual(updated.plan.school, "我的学校")
        XCTAssertEqual(updated.plan.rules.first?.kind, .odd)
        XCTAssertEqual(updated.notes.first?.id, "note-1")
    }

    func testUnknownSchoolReturnsHelpfulFailure() {
        let result = CourseImportParser.parse(text: "anything", schoolID: "unknown")
        XCTAssertTrue(result.courses.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testMalformedHTMLProducesReviewWarningWithoutRecursiveFallback() {
        let result = CourseImportParser.parse(text: "incomplete <tr")
        XCTAssertTrue(result.courses.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testReimportUpdatesCoursesAndRetainsUnrelatedOnes() {
        var initial = course("旧名字", kind: .odd)
        initial.number = "00131300"
        var imported = course("概率论", kind: .even)
        imported.number = "00131300"
        let state = CourseTimetable(courses: [initial, course("普通化学", kind: .all)])
        let once = state.merging([imported], schoolID: "pku")
        let twice = once.merging([imported], schoolID: "pku")
        XCTAssertEqual(twice.courses.count, 2)
        XCTAssertEqual(twice.courses[0].id, initial.id)
        XCTAssertEqual(twice.courses[0].title, "概率论")
        XCTAssertEqual(twice.courses[0].meetings[0].kind, .even)
    }

    private func course(_ title: String, kind: WeekKind) -> Course {
        Course(title: title, meetings: [CourseMeeting(weekday: 1, startPeriod: 1, endPeriod: 2, kind: kind)])
    }
    private func line(_ text: String, x: Double, y: Double) -> CourseOCRLine {
        CourseOCRLine(text: text, x: x, y: y, width: text.count == 8 ? 0.04 : 0.1, height: 0.018)
    }
}
