import SwiftUI
import WidgetKit

struct CourseWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CourseWidgetSnapshot?
}

struct CourseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CourseWidgetEntry {
        var plan = ReminderPlan()
        plan.termStart = LocalDay(ScheduleEngine.monday(of: Date()))
        let day = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
        let course = Course(title: "高等数学", teacher: "授课教师", meetings: [CourseMeeting(weekday: day, startPeriod: 1, endPeriod: 2, location: "理教103")])
        return CourseWidgetEntry(date: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date(), snapshot: CourseWidgetSnapshot(plan: plan, timetable: CourseTimetable(courses: [course])))
    }
    func getSnapshot(in context: Context, completion: @escaping (CourseWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : CourseWidgetEntry(date: Date(), snapshot: CourseWidgetStorage.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = CourseWidgetStorage.read()
        let dates = snapshot.map { CourseWidgetEngine.refreshDates(after: now, snapshot: $0) } ?? []
        let entries = ([now] + dates).map { CourseWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

struct CourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CourseWidgetEntry
    private var today: [WidgetLesson] {
        entry.snapshot.map { CourseWidgetEngine.lessons(on: entry.date, snapshot: $0) } ?? []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(family == .systemSmall ? "下一节课" : family == .systemLarge ? "本周课表" : "今日课表").font(.headline)
                Spacer(minLength: 0)
                if family != .systemSmall { Text(entry.date, format: .dateTime.month().day().weekday()).font(.caption).foregroundStyle(.secondary) }
            }
            if let snapshot = entry.snapshot {
                if snapshot.timetable.courses.isEmpty {
                    empty("还没有课程", detail: "打开 App 导入课表")
                } else if CourseClock.periods(plan: snapshot.plan).count != max(12, snapshot.timetable.courses.flatMap(\.meetings).map(\.endPeriod).max() ?? 12) {
                    empty("请核对学校作息", detail: "打开 App 检查节次与课间")
                } else if family == .systemLarge {
                    weekGrid(snapshot)
                } else if family == .systemSmall {
                    if let next = CourseWidgetEngine.upcoming(after: entry.date, snapshot: snapshot) { lesson(next, compact: false) }
                    else { empty("近期没有课程", detail: "未来七天暂无安排") }
                } else {
                    let remaining = today.filter { $0.end > entry.date }
                    if remaining.isEmpty {
                        empty(today.isEmpty ? "今天没有课" : "今天课程已结束", detail: "点击打开 App 查看完整课表")
                    } else {
                        let limit = family == .systemLarge ? 4 : 2
                        ForEach(Array(remaining.prefix(limit))) { lesson($0, compact: family == .systemMedium) }
                        if remaining.count > limit { Text("另有 \(remaining.count - limit) 个安排 · 点击查看").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            } else { empty("请先同步课表", detail: "打开课间一口并保存课表") }
            Spacer(minLength: 0)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "siptime://timetable"))
    }
    @ViewBuilder
    private func weekGrid(_ snapshot: CourseWidgetSnapshot) -> some View {
        if let week = ScheduleEngine.weekNumber(on: entry.date, plan: snapshot.plan) {
            Text("第 \(week) 周 · \(week % 2 == 1 ? "单周" : "双周")").font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let rows = max(12, snapshot.timetable.courses.flatMap(\.meetings).map(\.endPeriod).max() ?? 12)
                let height = max(8, (geometry.size.height - 18) / CGFloat(rows) - 2)
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text("节").frame(width: 13)
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                            Text($0).frame(maxWidth: .infinity)
                        }
                    }.font(.system(size: 9)).frame(height: 14)
                    ForEach(1...rows, id: \.self) { period in
                        HStack(spacing: 2) {
                            Text("\(period)").font(.system(size: 8)).frame(width: 13)
                            ForEach(1...7, id: \.self) { day in
                                let entries = TimetableEngine.entries(courses: snapshot.timetable.courses, week: week, weekday: day, period: period)
                                let active = entries.contains(where: \.isActive)
                                Text(entries.map { $0.course.displayTitle }.joined(separator: "/"))
                                    .font(.system(size: 8)).lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                                    .background(active ? Color.teal.opacity(0.23) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 3))
                                    .opacity(entries.isEmpty || active ? 1 : 0.35)
                            }
                        }
                    }
                }
            }
        } else { empty("当前不在学期内", detail: "打开 App 核对学期日期") }
    }

    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func lesson(_ item: WidgetLesson, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.course.displayTitle).font(compact ? .subheadline.bold() : .headline).lineLimit(2)
            HStack(spacing: 3) {
                Text(item.start, format: .dateTime.hour().minute())
                Text("–")
                Text(item.end, format: .dateTime.hour().minute())
                if item.isOngoing(at: entry.date) { Text("上课中").foregroundStyle(.teal) }
            }.font(.caption.monospacedDigit())
            if !Calendar.current.isDate(item.start, inSameDayAs: entry.date) {
                Text(item.start, format: .dateTime.month().day().weekday()).font(.caption2)
            }
            Text([item.meeting.location, item.course.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct SipTimeCourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CourseWidgetStorage.kind, provider: CourseWidgetProvider()) { CourseWidgetView(entry: $0) }
            .configurationDisplayName("课间一口课表")
            .description("查看今天接下来的课程、教室和下一节课。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
