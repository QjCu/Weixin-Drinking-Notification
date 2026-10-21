import Foundation

enum WeekKind: String, Codable, CaseIterable, Identifiable {
    case all, odd, even
    var id: String { rawValue }
    var title: String { self == .all ? "每周" : self == .odd ? "单周" : "双周" }
    func matches(_ week: Int) -> Bool {
        self == .all || (self == .odd ? week % 2 == 1 : week % 2 == 0)
    }
}

struct LocalDay: Codable, Equatable {
    var year: Int
    var month: Int
    var day: Int
    init(_ date: Date, calendar: Calendar = ScheduleEngine.calendar) {
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }
    var date: Date {
        date(in: ScheduleEngine.calendar)
    }
    func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

struct BreakSlot: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var minute: Int
    var duration: Int = 20
    var timeLabel: String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    var rangeLabel: String {
        let end = minute + duration
        return "\(timeLabel)–\(String(format: "%02d:%02d", end / 60, end % 60))"
    }
}

struct ReminderRule: Codable, Identifiable {
    var id = UUID().uuidString
    var weekday: Int // Monday=1 ... Sunday=7
    var minute: Int
    var kind: WeekKind
    var slotID: String? = nil
}

struct ReminderPlan: Codable {
    var school = "我的大学"
    var termStart = LocalDay(ScheduleEngine.monday(of: Date()))
    var termWeeks = 20
    var enabled = true
    var pausedDay: LocalDay? = nil
    var offsetMinutes = 0
    var slots = [
        BreakSlot(title: "上午课间", minute: 9 * 60 + 40),
        BreakSlot(title: "午间", minute: 11 * 60 + 40, duration: 60),
        BreakSlot(title: "下午课间", minute: 15 * 60 + 40),
        BreakSlot(title: "傍晚", minute: 17 * 60 + 30, duration: 60),
        BreakSlot(title: "晚间课间", minute: 20 * 60 + 30)
    ]
    var rules: [ReminderRule] = []
}

enum ScheduleEngine {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
    static func monday(of date: Date, calendar: Calendar = ScheduleEngine.calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }
    static func weekNumber(on date: Date, plan: ReminderPlan, calendar: Calendar = ScheduleEngine.calendar) -> Int? {
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: plan.termStart.date(in: calendar)),
                                            to: calendar.startOfDay(for: date)).day!
        guard delta >= 0, delta < plan.termWeeks * 7 else { return nil }
        return delta / 7 + 1
    }
    static func dates(plan: ReminderPlan, after now: Date, limit: Int = 60,
                      calendar: Calendar = ScheduleEngine.calendar) -> [Date] {
        guard plan.enabled, limit > 0 else { return [] }
        var dates = Set<Date>()
        let start = calendar.startOfDay(for: now)
        // 52 weeks is the maximum term length in the editor.
        for offset in 0...364 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let week = weekNumber(on: day, plan: plan, calendar: calendar) else { continue }
            if plan.pausedDay == LocalDay(day, calendar: calendar) { continue }
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            for rule in plan.rules where rule.weekday == weekday && rule.kind.matches(week) {
                let minute: Int
                if let slotID = rule.slotID {
                    guard let slot = plan.slots.first(where: { $0.id == slotID }),
                          plan.offsetMinutes < slot.duration else { continue }
                    minute = slot.minute + plan.offsetMinutes
                } else {
                    minute = rule.minute
                }
                guard (0..<1440).contains(minute),
                      let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60,
                                               second: 0, of: day), date > now else { continue }
                // Ignore nonexistent wall times during daylight-saving transitions.
                guard calendar.component(.hour, from: date) == minute / 60,
                      calendar.component(.minute, from: date) == minute % 60 else { continue }
                dates.insert(date)
            }
            if dates.count >= limit { break }
        }
        return Array(dates.sorted().prefix(limit))
    }
}

struct Profile: Decodable {
    let id: String
    let name: String
    let inviteCode: String
    let peerName: String?
}

struct FriendNote: Codable, Identifiable {
    let id: String
    let text: String
    let senderName: String
    let createdAt: String
}

struct NoteAssignment: Codable {
    var noteID: String
    var date: Date
}

struct LocalState: Codable {
    var plan = ReminderPlan()
    var serverURL = "http://localhost:8000"
    var accountID: String? = nil
    var notes: [FriendNote] = []
    var assignments: [NoteAssignment] = []
    var pendingAcknowledgements: [String] = []
    // Keep uncertain send retries idempotent across connection failures and restarts.
    var outgoingID: String? = nil
    var outgoingText: String? = nil
}
