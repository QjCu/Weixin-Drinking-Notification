import SwiftUI

private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

struct PlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = ReminderPlan()
    @State private var kind: WeekKind = .odd
    @State private var editingSlot: BreakSlot?
    @State private var showWeeklyRule = false
    @State private var showPreset = false
    @State private var showCopy = false
    private var regularRules: [ReminderRule] { draft.rules.filter { $0.slotID == nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("学校名称", text: $draft.school)
                    DatePicker("第一周的周一", selection: Binding(
                        get: { draft.termStart.date },
                        set: { draft.termStart = LocalDay(ScheduleEngine.monday(of: $0)) }), displayedComponents: .date)
                    Stepper("学期共 \(draft.termWeeks) 周", value: $draft.termWeeks, in: 1...52)
                    Toggle("开启提醒", isOn: $draft.enabled)
                    if let week = ScheduleEngine.weekNumber(on: Date(), plan: draft) {
                        Text("当前第 \(week) 周 · \(week % 2 == 1 ? "单周" : "双周")").foregroundStyle(.secondary)
                    } else { Text("今天不在设定的学期内").foregroundStyle(.orange) }
                } header: { Text("学期与学校") } footer: { Text("选定日期会自动对齐到所在周的周一。所有提醒仅在这个学期内生效，包括普通提醒。") }

                Section {
                    Picker("单双周", selection: $kind) {
                        Text("单周").tag(WeekKind.odd)
                        Text("双周").tag(WeekKind.even)
                    }.pickerStyle(.segmented)
                    ScrollView(.horizontal) {
                        VStack(spacing: 10) {
                            HStack {
                                Text("课间").frame(width: 100, alignment: .leading)
                                ForEach(weekdayNames, id: \.self) { day in Text(day).frame(width: 38) }
                            }.font(.caption).foregroundStyle(.secondary)
                            ForEach(draft.slots) { slot in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(slot.title).lineLimit(1)
                                        Text(slot.rangeLabel).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(width: 100, alignment: .leading)
                                    ForEach(1...7, id: \.self) { day in
                                        let selected = isSelected(slot, day)
                                        Button { toggle(slot, day) } label: {
                                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                .font(.title3).foregroundStyle(selected ? Color.teal : Color.secondary)
                                                .frame(width: 38, height: 36)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(kind.title)星期\(weekdayNames[day - 1])，\(slot.title)，\(slot.rangeLabel)")
                                        .accessibilityValue(selected ? "已选择" : "未选择")
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    Stepper("课间开始后 \(draft.offsetMinutes) 分钟提醒", value: $draft.offsetMinutes, in: 0...15)
                    Button("将\(kind.title)课间选择复制到\(kind == .odd ? "双周" : "单周")") { showCopy = true }
                } header: { Text("点击想喝水的课间") } footer: {
                    Text("左右滑动查看一整周。若延后分钟数达到或超过课间长度，该课间将跳过提醒。普通提醒不受此延后设置影响。")
                }

                Section {
                    ForEach(draft.slots) { slot in
                        Button { editingSlot = slot } label: {
                            HStack {
                                Text(slot.title).foregroundStyle(.primary)
                                Spacer()
                                Text(slot.rangeLabel).foregroundStyle(.secondary)
                                Image(systemName: "pencil").font(.caption)
                            }
                        }
                    }.onDelete { offsets in
                        let ids = Set(offsets.map { draft.slots[$0].id })
                        draft.rules.removeAll { $0.slotID.map(ids.contains) ?? false }
                        draft.slots.remove(atOffsets: offsets)
                    }
                    Button("添加课间", systemImage: "plus") {
                        editingSlot = BreakSlot(title: "新课间", minute: 10 * 60)
                    }
                    Button("使用示例作息") { showPreset = true }
                } header: { Text("学校作息表") } footer: { Text("内置作息为示例，请按学校实际时间修改。编辑时间会同步影响已选择的课间；左滑可删除。") }

                Section {
                    ForEach(regularRules) { rule in
                        HStack {
                            Text("\(rule.kind.title) · 星期\(weekdayNames[rule.weekday - 1])")
                            Spacer()
                            Text(String(format: "%02d:%02d", rule.minute / 60, rule.minute % 60))
                        }
                    }.onDelete { offsets in
                        let ids = Set(offsets.map { regularRules[$0].id })
                        draft.rules.removeAll { ids.contains($0.id) }
                    }
                    Button("添加普通提醒", systemImage: "plus") { showWeeklyRule = true }
                } header: { Text("普通每周提醒") } footer: { Text("修改后点击右上角“保存”才会更新通知。同一天同一时刻的提醒会自动合并。") }
            }
            .navigationTitle("提醒计划")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await store.apply(draft) } }.fontWeight(.semibold)
                }
            }
            .onAppear { draft = store.state.plan }
            .sheet(item: $editingSlot) { slot in
                SlotEditor(slot: slot) { updated in
                    if let index = draft.slots.firstIndex(where: { $0.id == updated.id }) { draft.slots[index] = updated }
                    else { draft.slots.append(updated) }
                    draft.slots.sort { $0.minute < $1.minute }
                }
            }
            .sheet(isPresented: $showWeeklyRule) {
                WeeklyRuleEditor { rules in draft.rules.append(contentsOf: rules) }
            }
            .confirmationDialog("替换另一周的课间选择？普通提醒将保留。", isPresented: $showCopy, titleVisibility: .visible) {
                Button("复制并替换") {
                    let target: WeekKind = kind == .odd ? .even : .odd
                    let source = draft.rules.filter { $0.slotID != nil && $0.kind == kind }
                    draft.rules.removeAll { $0.slotID != nil && $0.kind == target }
                    draft.rules.append(contentsOf: source.map {
                        ReminderRule(weekday: $0.weekday, minute: $0.minute, kind: target, slotID: $0.slotID)
                    })
                }
            }
            .confirmationDialog("应用示例会清除原课间选择，普通提醒将保留。", isPresented: $showPreset, titleVisibility: .visible) {
                Button("示例 A · 09:40 / 11:40 / 15:40") { usePreset(early: false) }
                Button("示例 B · 09:30 / 11:30 / 15:30") { usePreset(early: true) }
            }
        }
    }
    private func isSelected(_ slot: BreakSlot, _ weekday: Int) -> Bool {
        draft.rules.contains { $0.slotID == slot.id && $0.weekday == weekday && $0.kind == kind }
    }
    private func toggle(_ slot: BreakSlot, _ weekday: Int) {
        if isSelected(slot, weekday) {
            draft.rules.removeAll { $0.slotID == slot.id && $0.weekday == weekday && $0.kind == kind }
        } else {
            draft.rules.append(ReminderRule(weekday: weekday, minute: slot.minute, kind: kind, slotID: slot.id))
        }
    }
    private func usePreset(early: Bool) {
        draft.rules.removeAll { $0.slotID != nil }
        draft.slots = ReminderPlan().slots
        if early {
            for index in draft.slots.indices where index != 3 { draft.slots[index].minute -= 10 }
        }
    }
}

private struct SlotEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var slot: BreakSlot
    let onSave: (BreakSlot) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("课间名称", text: $slot.title)
                DatePicker("开始时间", selection: Binding(get: { dateForMinute(slot.minute) },
                    set: { slot.minute = minuteOfDay($0) }), displayedComponents: .hourAndMinute)
                Stepper("课间长度 \(slot.duration) 分钟", value: $slot.duration, in: 5...180, step: 5)
                if slot.minute + slot.duration >= 1440 { Text("课间结束时间必须在当天内").foregroundStyle(.orange) }
            }
            .navigationTitle("编辑课间")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { onSave(slot); dismiss() }
                        .disabled(slot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || slot.minute + slot.duration >= 1440)
                }
            }
        }
    }
}

private struct WeeklyRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int> = []
    @State private var time = dateForMinute(9 * 60)
    @State private var kind: WeekKind = .all
    let onSave: ([ReminderRule]) -> Void
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
                Picker("重复", selection: $kind) {
                    ForEach(WeekKind.allCases) { Text($0.title).tag($0) }
                }
                Section("选择星期") {
                    ForEach(1...7, id: \.self) { day in
                        Toggle("星期\(weekdayNames[day - 1])", isOn: Binding(get: { days.contains(day) }, set: {
                            if $0 { days.insert(day) } else { days.remove(day) }
                        }))
                    }
                }
            }
            .navigationTitle("普通提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onSave(days.sorted().map { ReminderRule(weekday: $0, minute: minuteOfDay(time), kind: kind) })
                        dismiss()
                    }.disabled(days.isEmpty)
                }
            }
        }
    }
}

private func dateForMinute(_ minute: Int) -> Date {
    ScheduleEngine.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())!
}
private func minuteOfDay(_ date: Date) -> Int {
    ScheduleEngine.calendar.component(.hour, from: date) * 60 + ScheduleEngine.calendar.component(.minute, from: date)
}
