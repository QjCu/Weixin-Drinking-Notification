import SwiftUI
import UniformTypeIdentifiers
import CoreFoundation

@MainActor
struct CourseImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var schoolID = "pku"
    @State private var sourceText = ""
    @State private var courses: [Course] = []
    @State private var warnings: [String] = []
    @State private var editing: Course?
    @State private var showWeb = false
    @State private var showFile = false
    @State private var showReplaceConfirmation = false
    @State private var replaceExisting = false
    @State private var isParsing = false
    @State private var failure: String?
    @State private var termStart = Date()
    @State private var termWeeks = 20
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("学校", selection: $schoolID) {
                        ForEach(CourseImportParser.schools, id: \.id) { school in Text(school.title).tag(school.id) }
                    }
                    ScreenshotImportButton(onRecognized: { lines in
                        recognize { school in CourseImportParser.parse(lines: lines, schoolID: school) }
                    }, onFailure: { failure = $0 })
                    Button("打开学校网页并识别", systemImage: "globe") { showWeb = true }
                    Button("导入 HTML / 文本文件", systemImage: "doc") { showFile = true }
                } header: { Text("自动识别") } footer: {
                    Text("请使用上方完整的选课结果表，包含课程名、教室信息和选课结果。当前适配北京大学；仅有下方课表网格或模糊、截断的图片可能识别不全。图片在本机识别，不上传到留言服务器。")
                }
                Section {
                    DisclosureGroup("粘贴网页文字或 HTML") {
                        TextEditor(text: $sourceText).frame(minHeight: 140)
                            .font(.footnote).autocorrectionDisabled()
                        Button("识别粘贴内容") {
                            guard sourceText.utf8.count <= 5 * 1024 * 1024 else {
                                failure = "内容超过 5 MB，请仅保留课程结果表。"; return
                            }
                            let text = sourceText
                            recognize { school in CourseImportParser.parse(text: text, schoolID: school) }
                        }.disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if isParsing { Section { ProgressView("正在整理课程…") } }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if !warnings.isEmpty {
                    Section("需要核对") {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    ForEach(courses) { course in
                        Button { editing = course } label: { CourseSummary(course: course) }.foregroundStyle(.primary)
                    }.onDelete { courses.remove(atOffsets: $0) }
                    Button("手动补充课程", systemImage: "plus") { editing = blankCourse() }
                } header: { Text("导入预览 · \(courses.count) 门") } footer: {
                    Text("点击课程可校正名称、星期、节次、周次、单双周及教室，左滑可移除。每次识别会替换这份预览，保存前不会改变现有课表。请核对是否与学校最终课表一致。")
                }
                Section {
                    DatePicker("第一周的周一", selection: $termStart, displayedComponents: .date)
                        .onChange(of: termStart) { _, value in termStart = ScheduleEngine.monday(of: value) }
                    Stepper("学期共 \(termWeeks) 周", value: $termWeeks, in: 1...52)
                    if let largestWeek = courses.flatMap(\.meetings).map(\.endWeek).max(), largestWeek > termWeeks {
                        Text("部分课程持续到第 \(largestWeek) 周，超出当前学期，请核对学期周数。")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: { Text("学期设置") } footer: {
                    Text("单双周按学期周数计算。此处日期与提醒计划共用，修改后也会更新喝水提醒的学期范围；不会自动点选喝水课间。")
                }
                if !(store.state.timetable?.courses.isEmpty ?? true) {
                    Section {
                        Toggle("替换现有全部课程", isOn: $replaceExisting)
                    } footer: {
                        Text(replaceExisting ? "保存后移除旧课表，用此预览替换。" : "默认合并：相同课程号的课程更新安排，其余保留；无课程号时按名称匹配。")
                    }
                }
                if let error = store.error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .disabled(isParsing || store.isBusy)
            .navigationTitle("导入课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存课表") {
                        if replaceExisting && !(store.state.timetable?.courses.isEmpty ?? true) {
                            showReplaceConfirmation = true
                        } else { save() }
                    }.disabled(courses.isEmpty || isParsing || store.isBusy)
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                termStart = store.state.plan.termStart.date
                termWeeks = store.state.plan.termWeeks
            }
            .sheet(isPresented: $showWeb) {
                CourseWebImportView { html in recognize { school in CourseImportParser.parse(html: html, schoolID: school) } }
            }
            .sheet(item: $editing) { course in
                CourseEditor(course: course) { updated in
                    if let index = courses.firstIndex(where: { $0.id == updated.id }) { courses[index] = updated }
                    else { courses.append(updated) }
                }
            }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.html, .plainText]) { result in
                importFile(result)
            }
            .confirmationDialog("替换现有课表？旧课程将被移除。", isPresented: $showReplaceConfirmation,
                                titleVisibility: .visible) {
                Button("用预览替换课表", role: .destructive) { save() }
            }
        }
    }

    private func recognize(_ parse: @escaping (String) -> CourseImportResult) {
        guard !isParsing else { return }
        isParsing = true
        failure = nil
        let school = schoolID
        // Parsing is bounded to one small page; run away from the UI actor.
        Task {
            let result = await Task.detached(priority: .userInitiated) { parse(school) }.value
            courses = result.courses
            warnings = result.warnings
            if courses.isEmpty { failure = "没有找到可导入课程。请确认包含完整结果表，或手动补充课程。" }
            isParsing = false
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5 * 1024 * 1024 else { failure = "文件超过 5 MB，请仅导出课程结果表。"; return }
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024 else { failure = "文件超过 5 MB。"; return }
            let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            let utf16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
            guard let text = utf16BOM ? String(data: data, encoding: .utf16) :
                    (String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030)) else {
                failure = "文件文字编码无法读取，请改用网页或截图导入。"; return
            }
            recognize { school in CourseImportParser.parse(text: text, schoolID: school) }
        } catch { failure = "读取文件失败：\(error.localizedDescription)" }
    }

    private func save() {
        var timetable = CourseTimetable(schoolID: schoolID, courses: courses)
        if !replaceExisting, let existing = store.state.timetable {
            timetable = existing.merging(courses, schoolID: schoolID)
        }
        let start = LocalDay(ScheduleEngine.monday(of: termStart))
        Task { if await store.applyTimetable(timetable, termStart: start, termWeeks: termWeeks) { dismiss() } }
    }
}
