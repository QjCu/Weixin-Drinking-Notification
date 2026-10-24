import SwiftUI

let courseWeekdays = ["一", "二", "三", "四", "五", "六", "日"]

struct CourseTimetableView: View {
    @EnvironmentObject private var store: AppStore
    @State private var browsingWeek: Int?
    @State private var showImport = false
    @State private var showManage = false
    private var timetable: CourseTimetable { store.state.timetable ?? CourseTimetable() }
    private var currentWeek: Int? { ScheduleEngine.weekNumber(on: Date(), plan: store.state.plan) }
    private var shownWeek: Int? { browsingWeek ?? currentWeek }
    private var lastPeriod: Int { max(12, timetable.courses.flatMap(\.meetings).map(\.endPeriod).max() ?? 12) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekControls
                if timetable.courses.isEmpty {
                    ContentUnavailableView {
                        Label("把选课结果变成课表", systemImage: "tablecells")
                    } description: {
                        Text("导入选课网页或完整截图，识别后核对并保存。也可以手动添加课程。")
                    } actions: {
                        Button("导入课表") { showImport = true }.buttonStyle(.borderedProminent)
                        Button("手动添加") { showManage = true }
                    }
                } else if let week = shownWeek {
                    timetableGrid(week: week)
                    Text("淡色为非本周课程；同一节有本周课程时仅显示本周课程。左右滑动查看全周。")
                        .font(.caption).foregroundStyle(.secondary).padding(10)
                } else {
                    ContentUnavailableView("当前不在学期内", systemImage: "calendar.badge.exclamationmark",
                        description: Text("请在提醒计划核对第一周日期，或选择周次查看课表。"))
                }
            }
            .navigationTitle("课表")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("管理") { showManage = true } }
                ToolbarItem(placement: .primaryAction) {
                    Button("导入", systemImage: "square.and.arrow.down") { showImport = true }
                }
            }
            .sheet(isPresented: $showImport) { CourseImportView() }
            .sheet(isPresented: $showManage) { CourseManagerView(timetable: timetable) }
            .onChange(of: store.state.plan.termWeeks) { _, weeks in
                if let browsingWeek, browsingWeek > weeks { self.browsingWeek = nil }
            }
        }
    }

    private var weekControls: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }.padding()
    }

    private func timetableGrid(week: Int) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("节次").frame(width: 42)
                    ForEach(1...7, id: \.self) { day in
                        VStack(spacing: 4) {
                            Text("星期\(courseWeekdays[day - 1])").font(.subheadline.bold())
                            if let date = ScheduleEngine.calendar.date(byAdding: .day, value: (week - 1) * 7 + day - 1,
                                                                      to: store.state.plan.termStart.date) {
                                Text(date, format: .dateTime.month().day()).font(.caption)
                            }
                        }.frame(width: 116).padding(.vertical, 8)
                    }
                }.foregroundStyle(.secondary)
                ForEach(1...lastPeriod, id: \.self) { period in
                    HStack(alignment: .top, spacing: 4) {
                        Text("\(period)").font(.subheadline.monospacedDigit())
                            .frame(width: 42, height: 132).foregroundStyle(.secondary)
                        ForEach(1...7, id: \.self) { day in
                            CoursePeriodCell(entries: TimetableEngine.entries(courses: timetable.courses,
                                week: week, weekday: day, period: period))
                                .frame(width: 116, height: 132)
                                .accessibilityLabel("星期\(courseWeekdays[day - 1])第\(period)节")
                        }
                    }
                }
            }.padding(.horizontal, 8).padding(.bottom)
        }
    }
}

private struct CoursePeriodCell: View {
    let entries: [TimetableEntry]
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 5) {
                if entries.filter(\.isActive).count > 1 {
                    Text("本周时间冲突").font(.caption2.bold()).foregroundStyle(.orange)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.course.title).font(.caption.bold()).fixedSize(horizontal: false, vertical: true)
                        if !entry.meeting.location.isEmpty {
                            Text(entry.meeting.location).font(.caption2).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(entry.meeting.weekLabel).font(.caption2)
                        if !entry.isActive { Text("非本周").font(.caption2) }
                    }
                    .foregroundStyle(entry.isActive ? Color.primary : Color.secondary)
                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(entry.isActive ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 8))
                    .opacity(entry.isActive ? 1 : 0.40)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
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
                    Text("点击课程修改周次、单双周、节次和地点；左滑删除。点击保存后生效。课表不会自动修改喝水课间的点选。")
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
            Text(course.title).font(.headline)
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
                    TextField("课程名称", text: $course.title)
                    TextField("课程号（可选）", text: $course.number)
                    TextField("教师（可选）", text: $course.teacher)
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
                        onSave(course); dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}
