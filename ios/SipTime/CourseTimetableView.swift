import SwiftUI

let courseWeekdays = ["一", "二", "三", "四", "五", "六", "日"]

private enum CoursePage: String, CaseIterable {
    case timetable = "课表", courses = "课程"
}

struct CourseTimetableView: View {
    @EnvironmentObject private var store: AppStore
    @State private var browsingWeek: Int?
    @State private var page: CoursePage = .timetable
    @State private var showImport = false
    @State private var showManage = false
    @State private var selection: CourseSelection?
    private var timetable: CourseTimetable { store.state.timetable ?? CourseTimetable() }
    private var currentWeek: Int? { ScheduleEngine.weekNumber(on: Date(), plan: store.state.plan) }
    private var shownWeek: Int? { browsingWeek ?? currentWeek }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekControls
                Picker("课表页面", selection: $page) {
                    ForEach(CoursePage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 10)
                if timetable.courses.isEmpty {
                    ContentUnavailableView {
                        Label("把选课结果变成课表", systemImage: "tablecells")
                    } description: {
                        Text("导入选课网页或完整截图，识别后核对并保存。也可以手动添加课程。")
                    } actions: {
                        Button("导入课表") { showImport = true }.buttonStyle(.borderedProminent)
                        Button("手动添加") { showManage = true }
                    }
                } else if page == .courses {
                    CourseCatalogView(courses: timetable.courses, week: shownWeek) { course in
                        selection = CourseSelection(courseIDs: [course.id], title: "课程详情")
                    }
                } else if let week = shownWeek {
                    CourseTimetableGrid(courses: timetable.courses, week: week,
                                        termStart: store.state.plan.termStart, onSelect: { entries in
                        selection = CourseSelection(courseIDs: distinctCourses(entries.map(\.course)).map(\.id),
                                                    title: "课程详情")
                    })
                    Text("淡色为非本周课程；同一节优先显示本周课程。点击课程查看详情或设置备注。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8)
                } else {
                    ContentUnavailableView("当前不在学期内", systemImage: "calendar.badge.exclamationmark",
                        description: Text("请在提醒计划核对第一周日期，或选择周次查看课表。"))
                }
            }
            .navigationTitle("课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("管理") { showManage = true } }
                ToolbarItem(placement: .primaryAction) {
                    Button("导入", systemImage: "square.and.arrow.down") { showImport = true }
                }
            }
            .sheet(isPresented: $showImport) { CourseImportView() }
            .sheet(isPresented: $showManage) { CourseManagerView(timetable: timetable) }
            .sheet(item: $selection) { selected in
                CourseDetailSheet(courseIDs: selected.courseIDs, week: shownWeek, title: selected.title)
            }
            .onChange(of: store.state.plan.termWeeks) { _, weeks in
                if let browsingWeek, browsingWeek > weeks { self.browsingWeek = nil }
            }
        }
    }

    private var weekControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu {
                    Button("跟随本周") { browsingWeek = nil }
                    ForEach(1...store.state.plan.termWeeks, id: \.self) { week in
                        Button("第 \(week) 周 · \(week % 2 == 1 ? "单周" : "双周")") { browsingWeek = week }
                    }
                } label: {
                    if let week = shownWeek {
                        Label("第 \(week) 周 · \(week % 2 == 1 ? "单周" : "双周")", systemImage: "chevron.down")
                            .font(.headline)
                    } else { Label("选择周次", systemImage: "chevron.down").font(.headline) }
                }
                Spacer()
                if browsingWeek != nil { Button("回到本周") { browsingWeek = nil }.font(.subheadline) }
            }
            Text(browsingWeek == nil ? "跟随当前学期周 · 学期日期与提醒计划共用" : "正在预览所选周次")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal).padding(.vertical, 10)
    }
}

/// The whole week uses the available width; every period occupies one equally sized cell.
/// The optional frame observer is used by the simulator layout regression tests.
struct CourseGridPosition: Hashable {
    var weekday: Int
    var period: Int
}

private struct CourseCellFramesKey: PreferenceKey {
    static var defaultValue: [CourseGridPosition: CGRect] = [:]
    static func reduce(value: inout [CourseGridPosition: CGRect], nextValue: () -> [CourseGridPosition: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct CourseTimetableGrid: View {
    let courses: [Course]
    let week: Int
    let termStart: LocalDay
    var onSelect: ([TimetableEntry]) -> Void = { _ in }
    var onCellFrames: (([CourseGridPosition: CGRect]) -> Void)? = nil
    @ScaledMetric(relativeTo: .caption) private var cellHeight: CGFloat = 88
    private let gutter: CGFloat = 24
    private let gap: CGFloat = 2
    private let sidePadding: CGFloat = 8
    private var lastPeriod: Int { max(12, courses.flatMap(\.meetings).map(\.endPeriod).max() ?? 12) }

    init(courses: [Course], week: Int, termStart: LocalDay,
         onSelect: @escaping ([TimetableEntry]) -> Void = { _ in },
         onCellFrames: (([CourseGridPosition: CGRect]) -> Void)? = nil) {
        self.courses = courses
        self.week = week
        self.termStart = termStart
        self.onSelect = onSelect
        self.onCellFrames = onCellFrames
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - sidePadding * 2 - gutter - gap * 7) / 7)
            ScrollView(.vertical) {
                VStack(spacing: gap) {
                    dayHeader(width: width)
                    ForEach(1...lastPeriod, id: \.self) { period in
                        periodRow(period, width: width)
                    }
                }
                .padding(.horizontal, sidePadding).padding(.bottom, 8)
                .frame(width: geometry.size.width)
            }
            .coordinateSpace(name: "course-grid")
            .onPreferenceChange(CourseCellFramesKey.self) { onCellFrames?($0) }
        }
    }

    private func dayHeader(width: CGFloat) -> some View {
        HStack(spacing: gap) {
            Text("节次").font(.system(size: 10)).frame(width: gutter)
            ForEach(1...7, id: \.self) { day in
                VStack(spacing: 3) {
                    Text("周\(courseWeekdays[day - 1])").font(.caption2.bold())
                    if let date = ScheduleEngine.calendar.date(byAdding: .day, value: (week - 1) * 7 + day - 1,
                                                              to: termStart.date) {
                        Text(date, format: .dateTime.month().day())
                            .font(.system(size: 9).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .frame(width: width, height: 42)
            }
        }.foregroundStyle(.secondary)
    }

    private func periodRow(_ period: Int, width: CGFloat) -> some View {
        HStack(spacing: gap) {
            Text("\(period)").font(.caption.monospacedDigit())
                .frame(width: gutter, height: cellHeight).foregroundStyle(.secondary)
            ForEach(1...7, id: \.self) { day in
                let entries = TimetableEngine.entries(courses: courses, week: week, weekday: day, period: period)
                CoursePeriodCell(entries: entries) { onSelect(entries) }
                    .frame(width: width, height: cellHeight)
                    .accessibilityIdentifier("course-cell-\(day)-\(period)")
                    .accessibilityLabel(cellLabel(entries, day: day, period: period))
                    .background {
                        if onCellFrames != nil {
                            GeometryReader { cell in
                                Color.clear.preference(key: CourseCellFramesKey.self,
                                    value: [CourseGridPosition(weekday: day, period: period): cell.frame(in: .named("course-grid"))])
                            }
                        }
                    }
            }
        }
    }

    private func cellLabel(_ entries: [TimetableEntry], day: Int, period: Int) -> String {
        let names = entries.map { entry in
            "\(entry.course.displayTitle)，\(entry.meeting.location)，\(entry.meeting.kind.title)，\(entry.isActive ? "本周有课" : "非本周课程")"
        }.joined(separator: "；")
        return "星期\(courseWeekdays[day - 1])第\(period)节，\(names.isEmpty ? "无课程" : names)"
    }
}

private struct CoursePeriodCell: View {
    let entries: [TimetableEntry]
    let onSelect: () -> Void
    private var active: Bool { entries.contains(where: \.isActive) }
    private var hasConflict: Bool { entries.filter(\.isActive).count > 1 }

    var body: some View {
        if entries.isEmpty {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.045))
                .accessibilityHidden(true)
        } else {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    if entries.count == 1, let entry = entries.first {
                        Text(entry.course.displayTitle).font(.caption2.weight(.semibold))
                            .lineLimit(3).minimumScaleFactor(0.85)
                        if !entry.meeting.location.isEmpty {
                            Text(entry.meeting.location).font(.system(size: 9)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text(entry.isActive ? entry.meeting.kind.title : "非本周")
                            .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        ForEach(Array(entries.prefix(2))) { entry in
                            Text(entry.course.displayTitle).font(.caption2.weight(.semibold))
                                .lineLimit(2).minimumScaleFactor(0.85)
                        }
                        Spacer(minLength: 0)
                        Text(hasConflict ? "冲突 \(entries.count)" : "\(entries.count) 门课")
                            .font(.system(size: 9).bold()).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(hasConflict ? Color.orange : Color.secondary)
                    }
                }
                .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .background(active ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 6))
                .opacity(active ? 1 : 0.4)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityHint("查看这一节的所有课程和备注")
        }
    }
}

private struct CourseSelection: Identifiable {
    let id = UUID()
    var courseIDs: [String]
    var title: String
}

private enum CourseListStyle: String, CaseIterable {
    case concise = "简洁", detailed = "详细"
}

private enum CourseListScope: String, CaseIterable {
    case week = "本周", all = "全部"
}

private struct CourseCatalogView: View {
    let courses: [Course]
    let week: Int?
    let onSelect: (Course) -> Void
    @State private var style: CourseListStyle = .concise
    @State private var scope: CourseListScope = .week
    private var visibleCourses: [Course] {
        scope == .all ? courses : courses.filter { course in
            guard let week else { return false }
            return course.meetings.contains { $0.isActive(in: week) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("课程信息", selection: $style) {
                    ForEach(CourseListStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Picker("课程范围", selection: $scope) {
                    ForEach(CourseListScope.allCases, id: \.self) { value in
                        Text(value == .week ? (week.map { "第\($0)周" } ?? "本周") : value.rawValue).tag(value)
                    }
                }.pickerStyle(.menu).fixedSize()
            }.padding(.horizontal).padding(.bottom, 8)
            if visibleCourses.isEmpty {
                ContentUnavailableView(scope == .week ? "本周没有课程" : "还没有课程", systemImage: "books.vertical",
                    description: Text(week == nil && scope == .week ? "当前不在学期内，可切换“全部”查看已有课程。" : "可切换范围查看全部课程，或导入并添加课程。"))
            } else {
                List {
                    Section {
                        ForEach(visibleCourses) { course in
                            Button { onSelect(course) } label: {
                                if style == .concise {
                                    CourseCompactSummary(course: course, meetings: visibleMeetings(course))
                                } else {
                                    CourseFullDetails(course: course, week: week)
                                }
                            }.buttonStyle(.plain)
                        }
                    } header: { Text("\(scope == .all ? "全部" : "本周") · \(visibleCourses.count) 门课程") }
                }.listStyle(.insetGrouped)
            }
        }
    }

    private func visibleMeetings(_ course: Course) -> [CourseMeeting] {
        guard scope == .week, let week else { return course.meetings }
        return course.meetings.filter { $0.isActive(in: week) }
    }
}

private struct CourseCompactSummary: View {
    let course: Course
    let meetings: [CourseMeeting]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.displayTitle).font(.headline).foregroundStyle(.primary)
            Text("教师：\(course.teacher.isEmpty ? "未填写" : course.teacher)")
            Text("教室：\(uniqueLabels(meetings.map(\.location)).isEmpty ? "未填写" : uniqueLabels(meetings.map(\.location)).joined(separator: "、"))")
            Text("单双周：\(uniqueLabels(meetings.map { $0.kind.title }).joined(separator: "、"))")
        }
        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 5)
    }
}

private struct CourseFullDetails: View {
    let course: Course
    let week: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(course.title).font(.headline).foregroundStyle(.primary)
            VStack(spacing: 7) {
                detailLine("课程备注", course.remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置" : course.remark)
                detailLine("课表显示名", course.displayTitle)
                detailLine("课程号", course.number.isEmpty ? "未填写" : course.number)
                detailLine("教师", course.teacher.isEmpty ? "未填写" : course.teacher)
            }
            ForEach(Array(course.meetings.enumerated()), id: \.element.id) { index, meeting in
                VStack(alignment: .leading, spacing: 7) {
                    Text("上课安排 \(index + 1)").font(.subheadline.bold()).foregroundStyle(.primary)
                    detailLine("星期", "星期\(courseWeekdays[max(1, min(7, meeting.weekday)) - 1])")
                    detailLine("节次", meeting.periodLabel)
                    detailLine("起止周", "第 \(meeting.startWeek)–\(meeting.endWeek) 周")
                    if !meeting.weeks.isEmpty {
                        detailLine("指定周", meeting.weeks.sorted().map(String.init).joined(separator: "、"))
                    }
                    detailLine("单双周", meeting.kind.title)
                    detailLine("教室", meeting.location.isEmpty ? "未填写" : meeting.location)
                    if let week { detailLine("第 \(week) 周", meeting.isActive(in: week) ? "有课" : "无课") }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
        }.padding(.vertical, 6)
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(.primary)
        }.font(.subheadline)
    }
}

private struct CourseDetailSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let courseIDs: [String]
    let week: Int?
    let title: String
    @State private var editing: Course?
    private var courses: [Course] {
        courseIDs.compactMap { id in store.state.timetable?.courses.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(courses) { course in
                    Section {
                        CourseFullDetails(course: course, week: week)
                        Button("编辑课程 / 备注", systemImage: "pencil") { editing = course }
                    }
                }
                if courses.isEmpty { Text("课程已移除").foregroundStyle(.secondary) }
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .disabled(store.isBusy)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { course in
                CourseEditor(course: course) { updated in
                    Task {
                        guard var timetable = store.state.timetable,
                              let index = timetable.courses.firstIndex(where: { $0.id == updated.id }) else { return }
                        timetable.courses[index] = updated
                        await store.applyTimetable(timetable)
                    }
                }
            }
        }
    }
}

struct CourseManagerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var timetable: CourseTimetable
    @State private var editing: Course?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(timetable.courses) { course in
                        Button { editing = course } label: { CourseSummary(course: course) }
                            .foregroundStyle(.primary)
                    }.onDelete { timetable.courses.remove(atOffsets: $0) }
                    Button("添加课程", systemImage: "plus") { editing = blankCourse() }
                } header: { Text("全部课程 · \(timetable.courses.count) 门") } footer: {
                    Text("点击课程修改备注、周次、单双周、节次和地点；左滑删除。点击保存后生效。课表不会自动修改喝水课间的点选。")
                }
            }
            .navigationTitle("管理课程")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { if await store.applyTimetable(timetable) { dismiss() } }
                    }.disabled(store.isBusy)
                }
            }
            .sheet(item: $editing) { course in
                CourseEditor(course: course) { updated in
                    if let index = timetable.courses.firstIndex(where: { $0.id == updated.id }) {
                        timetable.courses[index] = updated
                    } else { timetable.courses.append(updated) }
                }
            }
            .safeAreaInset(edge: .bottom) { if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red).padding() } }
        }
    }
}

struct CourseSummary: View {
    let course: Course
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.displayTitle).font(.headline)
            if course.displayTitle != course.title { Text(course.title).font(.caption).foregroundStyle(.secondary) }
            if !course.number.isEmpty || !course.teacher.isEmpty {
                Text([course.number, course.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(course.meetings) { meeting in
                Text("星期\(courseWeekdays[max(1, min(7, meeting.weekday)) - 1]) \(meeting.startPeriod)–\(meeting.endPeriod)节 · \(meeting.weekLabel)\(meeting.location.isEmpty ? "" : " · " + meeting.location)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

func blankCourse() -> Course {
    Course(title: "", number: "", teacher: "", meetings: [CourseMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)])
}

struct CourseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var course: Course
    let onSave: (Course) -> Void
    private var valid: Bool {
        !course.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !course.meetings.isEmpty &&
        course.meetings.allSatisfy(\.isValid)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程全称", text: $course.title)
                    TextField("课程号（可选）", text: $course.number)
                    TextField("教师（可选）", text: $course.teacher)
                }
                Section {
                    TextField("课程备注 / 显示名称（可选）", text: $course.remark, axis: .vertical)
                        .lineLimit(1...3)
                } header: { Text("课表显示名称") } footer: {
                    Text("有备注时课表显示备注，留空则显示课程全称；原课程名称会保留在详细信息中。")
                }
                ForEach($course.meetings) { $meeting in
                    Section("上课安排") {
                        Picker("星期", selection: $meeting.weekday) {
                            ForEach(1...7, id: \.self) { Text("星期\(courseWeekdays[$0 - 1])").tag($0) }
                        }
                        Stepper("开始：第 \(meeting.startPeriod) 节", value: $meeting.startPeriod, in: 1...24)
                        Stepper("结束：第 \(meeting.endPeriod) 节", value: $meeting.endPeriod, in: 1...24)
                        Stepper("第 \(meeting.startWeek) 周起", value: $meeting.startWeek, in: 1...52)
                        Stepper("第 \(meeting.endWeek) 周止", value: $meeting.endWeek, in: 1...52)
                        Picker("重复", selection: $meeting.kind) {
                            ForEach(WeekKind.allCases) { Text($0.title).tag($0) }
                        }
                        if !meeting.weeks.isEmpty {
                            Text("指定周：\(meeting.weeks.map(String.init).joined(separator: "、"))").font(.caption)
                            Button("改用上面的周次范围") { meeting.weeks = [] }
                        }
                        TextField("教室 / 地点", text: $meeting.location)
                        Button("移除此安排", role: .destructive) {
                            let id = meeting.id
                            course.meetings.removeAll { $0.id == id }
                        }
                    }
                }
                Section {
                    Button("添加上课安排", systemImage: "plus") {
                        course.meetings.append(CourseMeeting(weekday: 1, startPeriod: 1, endPeriod: 2))
                    }
                    if !valid { Text("请填写课程名称并保留至少一个有效安排。结束节次和周次不能早于开始；指定周需在周次范围内。").font(.caption).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("编辑课程")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        course.title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        course.remark = course.remark.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(course); dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}

private func distinctCourses(_ courses: [Course]) -> [Course] {
    var seen = Set<String>()
    return courses.filter { seen.insert($0.id).inserted }
}

private func uniqueLabels(_ labels: [String]) -> [String] {
    var seen = Set<String>()
    return labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
}
