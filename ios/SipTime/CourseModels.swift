import Foundation

/// School-independent course data. One course may meet on different days, weeks and locations.
struct Course: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var number = ""
    var teacher = ""
    var meetings: [CourseMeeting] = []
    /// Personal display name; the imported title remains available in course details.
    var remark = ""

    var displayTitle: String {
        let personalTitle = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        return personalTitle.isEmpty ? title : personalTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, number, teacher, meetings, remark
    }
}

extension Course {
    /// Older state.json files have no personal display name; retain every original field.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        number = try values.decode(String.self, forKey: .number)
        teacher = try values.decode(String.self, forKey: .teacher)
        meetings = try values.decode([CourseMeeting].self, forKey: .meetings)
        remark = try values.decodeIfPresent(String.self, forKey: .remark) ?? ""
    }
}

struct CourseMeeting: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var startWeek = 1
    var endWeek = 16
    var kind: WeekKind = .all
    /// Empty means the inclusive startWeek...endWeek range; otherwise an explicit week list.
    var weeks: [Int] = []
    var location = ""

    var isValid: Bool {
        (1...7).contains(weekday) && (1...24).contains(startPeriod)
            && (startPeriod...24).contains(endPeriod) && (1...52).contains(startWeek)
            && (startWeek...52).contains(endWeek)
            && weeks.allSatisfy { (startWeek...endWeek).contains($0) }
    }
    func isActive(in week: Int) -> Bool {
        isValid && (startWeek...endWeek).contains(week) && kind.matches(week)
            && (weeks.isEmpty || weeks.contains(week))
    }
    var weekLabel: String {
        let range = weeks.isEmpty ? "\(startWeek)–\(endWeek)周" : weeks.sorted().map(String.init).joined(separator: "、") + "周"
        return range + " · " + kind.title
    }
    var periodLabel: String { startPeriod == endPeriod ? "第\(startPeriod)节" : "第\(startPeriod)–\(endPeriod)节" }
}

struct CourseTimetable: Codable, Equatable {
    var schoolID = "pku"
    var courses: [Course] = []

    /// Reimport updates a course instead of duplicating it. Unknown courses retain their place.
    func merging(_ imported: [Course], schoolID: String) -> CourseTimetable {
        var updated = self
        updated.schoolID = schoolID
        for course in imported {
            let match = updated.courses.firstIndex {
                if !course.number.isEmpty && !$0.number.isEmpty { return course.number == $0.number }
                return course.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    == $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let match {
                var replacement = course
                replacement.id = updated.courses[match].id
                // Reimport updates school data while preserving the user's personal label.
                if course.remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    replacement.remark = updated.courses[match].remark
                }
                updated.courses[match] = replacement
            } else { updated.courses.append(course) }
        }
        return updated
    }
}

struct TimetableEntry: Identifiable {
    var course: Course
    var meeting: CourseMeeting
    var isActive: Bool
    var id: String { course.id + ":" + meeting.id }
}

enum TimetableEngine {
    /// Resolve each period separately, so even a partial active overlap suppresses the ghost.
    static func entries(courses: [Course], week: Int, weekday: Int, period: Int) -> [TimetableEntry] {
        let entries = courses.flatMap { course in
            course.meetings.filter {
                $0.isValid && $0.weekday == weekday && ($0.startPeriod...$0.endPeriod).contains(period)
            }.map { TimetableEntry(course: course, meeting: $0, isActive: $0.isActive(in: week)) }
        }
        let active = entries.filter(\.isActive)
        return (active.isEmpty ? entries : active).sorted {
            $0.course.title == $1.course.title ? $0.id < $1.id : $0.course.title < $1.course.title
        }
    }
}

/// Course periods are the teaching intervals between the reminder plan's school breaks.
/// Reminder selections, offsets and paused days do not change the school timetable.
enum CourseClock {
    struct Period: Equatable {
        var start: Int
        var end: Int
    }
    static let dayStart = 8 * 60
    static let dayEnd = 21 * 60 + 30

    static func periods(plan: ReminderPlan) -> [Period] {
        let breaks = plan.slots.sorted { $0.minute < $1.minute }
        var cursor = dayStart
        var result: [Period] = []
        for slot in breaks {
            guard slot.duration > 0, slot.minute > cursor,
                  slot.minute + slot.duration < dayEnd else { return [] }
            result.append(Period(start: cursor, end: slot.minute))
            cursor = slot.minute + slot.duration
        }
        result.append(Period(start: cursor, end: dayEnd))
        return result
    }

    static func minute(on date: Date, calendar: Calendar = ScheduleEngine.calendar) -> Double {
        Double(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
            + Double(calendar.component(.second, from: date)) / 60
    }

    static func weekday(on date: Date, displayedWeek: Int, plan: ReminderPlan,
                        calendar: Calendar = ScheduleEngine.calendar) -> Int? {
        guard ScheduleEngine.weekNumber(on: date, plan: plan, calendar: calendar) == displayedWeek else { return nil }
        return (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    static func activePeriod(at minute: Double, periods: [Period]) -> Int? {
        periods.firstIndex { minute >= Double($0.start) && minute < Double($0.end) }.map { $0 + 1 }
    }

    /// Row coordinates: class rows have height 1, breaks interpolate across the row gaps.
    static func position(at minute: Double, periods: [Period], rowHeight: Double, gap: Double) -> Double? {
        guard !periods.isEmpty, minute >= Double(dayStart), minute <= Double(dayEnd) else { return nil }
        for (index, period) in periods.enumerated() {
            let top = Double(index) * (rowHeight + gap)
            if minute <= Double(period.end) {
                let fraction = (minute - Double(period.start)) / Double(period.end - period.start)
                return top + max(0, min(1, fraction)) * rowHeight
            }
            if index + 1 < periods.count, minute < Double(periods[index + 1].start) {
                let fraction = (minute - Double(period.end)) / Double(periods[index + 1].start - period.end)
                return top + rowHeight + fraction * gap
            }
        }
        return nil
    }
}
