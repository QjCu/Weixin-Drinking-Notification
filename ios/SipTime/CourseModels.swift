import Foundation

/// School-independent course data. One course may meet on different days, weeks and locations.
struct Course: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var number = ""
    var teacher = ""
    var meetings: [CourseMeeting] = []
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
