import Foundation

/// Only the school plan and course data are shared. No accounts, passwords or friend notes.
struct CourseWidgetSnapshot: Codable {
    var plan: ReminderPlan
    var timetable: CourseTimetable
}

struct WidgetLesson: Identifiable {
    var course: Course
    var meeting: CourseMeeting
    var start: Date
    var end: Date
    var teachingIntervals: [DateInterval]
    var id: String { course.id + meeting.id + String(start.timeIntervalSince1970) }
    func isOngoing(at date: Date) -> Bool { teachingIntervals.contains { $0.start <= date && date < $0.end } }
}

enum CourseWidgetEngine {
    static func lessons(on date: Date, snapshot: CourseWidgetSnapshot,
                        calendar: Calendar = ScheduleEngine.calendar) -> [WidgetLesson] {
        guard let week = ScheduleEngine.weekNumber(on: date, plan: snapshot.plan, calendar: calendar) else { return [] }
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        let periods = CourseClock.periods(plan: snapshot.plan)
        return snapshot.timetable.courses.flatMap { course in
            course.meetings.compactMap { meeting -> WidgetLesson? in
                guard meeting.isActive(in: week), meeting.weekday == weekday,
                      meeting.startPeriod > 0, meeting.endPeriod <= periods.count else { return nil }
                let first = periods[meeting.startPeriod - 1].start
                let last = periods[meeting.endPeriod - 1].end
                guard let start = calendar.date(bySettingHour: first / 60, minute: first % 60, second: 0, of: date),
                      let end = calendar.date(bySettingHour: last / 60, minute: last % 60, second: 0, of: date) else { return nil }
                let intervals = periods[(meeting.startPeriod - 1)...(meeting.endPeriod - 1)].compactMap { period -> DateInterval? in
                    guard let a = calendar.date(bySettingHour: period.start / 60, minute: period.start % 60, second: 0, of: date),
                          let b = calendar.date(bySettingHour: period.end / 60, minute: period.end % 60, second: 0, of: date) else { return nil }
                    return DateInterval(start: a, end: b)
                }
                return WidgetLesson(course: course, meeting: meeting, start: start, end: end, teachingIntervals: intervals)
            }
        }.sorted { $0.start == $1.start ? $0.course.title < $1.course.title : $0.start < $1.start }
    }

    static func upcoming(after date: Date, snapshot: CourseWidgetSnapshot,
                         calendar: Calendar = ScheduleEngine.calendar) -> WidgetLesson? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if let lesson = lessons(on: day, snapshot: snapshot, calendar: calendar).first(where: { $0.end > date }) { return lesson }
        }
        return nil
    }

    static func refreshDates(after date: Date, snapshot: CourseWidgetSnapshot,
                             calendar: Calendar = ScheduleEngine.calendar) -> [Date] {
        var dates = Set<Date>()
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { continue }
            dates.insert(day)
            for lesson in lessons(on: day, snapshot: snapshot, calendar: calendar) {
                dates.insert(lesson.start)
                dates.insert(lesson.end)
                for interval in lesson.teachingIntervals { dates.insert(interval.start); dates.insert(interval.end) }
            }
        }
        return Array(dates.filter { $0 > date }.sorted().prefix(60))
    }
}

#if os(iOS)
enum CourseWidgetStorage {
    static let kind = "SipTime.CourseTimetable"
    static func file() throws -> URL {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SipTimeAppGroup") as? String,
              !group.isEmpty, !group.contains("$("),
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory.appendingPathComponent("course-widget.json")
    }
    static func read() -> CourseWidgetSnapshot? {
        guard let file = try? file(), let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CourseWidgetSnapshot.self, from: data)
    }
    static func write(_ snapshot: CourseWidgetSnapshot) throws -> Bool {
        let destination = try file()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        if let old = try? Data(contentsOf: destination), old == data { return false }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}
#endif
