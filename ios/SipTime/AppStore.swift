import Foundation
import Combine
#if SIPTIME_WIDGETS
import WidgetKit
#endif

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state = LocalState()
    @Published private(set) var profile: Profile?
    @Published private(set) var dates: [Date] = []
    @Published private(set) var status = "正在检查提醒"
    @Published private(set) var isBusy = false
    @Published var error: String?
#if SIPTIME_WIDGETS
    @Published private(set) var widgetStatus = "打开 App 会同步课程到小组件"
#endif
    @Published var notice: String?
    private let scheduler = NotificationScheduler()
    private let file: URL
    private var storageReady = true

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SipTime", isDirectory: true)
        file = directory.appendingPathComponent("state.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: file))
            }
        } catch {
            storageReady = false
            self.error = "本地记录无法读取，已停止覆盖。请保留数据并联系开发者：\(error.localizedDescription)"
        }
    }

    var hasAccount: Bool { TokenVault.read(server: state.serverURL) != nil }
    private var api: APIClient {
        get throws {
            APIClient(baseURL: try APIClient.normalizedURL(state.serverURL),
                      token: TokenVault.read(server: state.serverURL))
        }
    }
    private func save() throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#if SIPTIME_WIDGETS
        do {
            let snapshot = CourseWidgetSnapshot(plan: state.plan, timetable: state.timetable ?? CourseTimetable())
            if try CourseWidgetStorage.write(snapshot) { WidgetCenter.shared.reloadTimelines(ofKind: CourseWidgetStorage.kind) }
            widgetStatus = "课程已同步，可在主屏幕添加“课间一口课表”"
        } catch {
            widgetStatus = "小组件暂未同步，请检查 App 与小组件的共享配置；App 内课表已保存"
        }
#endif
    }
    private func perform(_ action: () async throws -> Void) async {
        guard !isBusy, storageReady else { return }
        isBusy = true
        error = nil
        notice = nil
        defer { isBusy = false }
        do { try await action() }
        catch { self.error = error.localizedDescription }
    }
    private func settleElapsedNotes() throws {
        let elapsed = Set(state.assignments.filter { $0.date <= Date() }.map(\.noteID))
        state.pendingAcknowledgements = Array(Set(state.pendingAcknowledgements).union(elapsed))
        state.notes.removeAll { elapsed.contains($0.id) }
        state.assignments.removeAll { elapsed.contains($0.noteID) }
        try save()
    }
    private func rebuild() async throws {
        try settleElapsedNotes()
        do {
            let result = try await scheduler.rebuild(plan: state.plan, notes: state.notes)
            state.assignments = result.assignments
            dates = result.dates
            status = result.status
            try save()
        } catch {
            state.assignments = []
            dates = []
            status = "提醒安排失败，请重试"
            try? save()
            throw error
        }
    }
    private func sync() async throws {
        let client = try api
        if !state.pendingAcknowledgements.isEmpty {
            _ = try await client.raw("v1/notes/ack", method: "POST", body: ["ids": state.pendingAcknowledgements])
            state.pendingAcknowledgements = []
            try save()
        }
        let fetchedProfile: Profile = try await client.request("v1/me")
        let fetched: [FriendNote] = try await client.request("v1/notes/inbox")
        profile = fetchedProfile
        state.accountID = fetchedProfile.id
        // Server is authoritative after unlinking; remove cached notes no longer in the inbox.
        state.notes = fetched
        try save()
    }

    func refresh(online: Bool = true) async {
        await perform {
            try self.settleElapsedNotes()
            var networkError: Error?
            if online && self.hasAccount {
                do { try await self.sync() }
                catch { networkError = error }
            }
            try await self.rebuild()
            if let networkError {
                self.error = "留言同步失败，本地提醒已更新：\(networkError.localizedDescription)"
            }
        }
    }
    func apply(_ plan: ReminderPlan) async {
        await perform {
            try self.settleElapsedNotes()
            self.state.plan = plan
            try self.save()
            try await self.rebuild()
            self.notice = "提醒计划已保存"
        }
    }
    func togglePauseToday() async {
        var plan = state.plan
        plan.pausedDay = plan.pausedDay == LocalDay(Date()) ? nil : LocalDay(Date())
        await apply(plan)
    }
    @discardableResult
    func applyTimetable(_ timetable: CourseTimetable, termStart: LocalDay? = nil,
                        termWeeks: Int? = nil) async -> Bool {
        var saved = false
        await perform {
            let previous = self.state
            if let termStart { self.state.plan.termStart = termStart }
            if let termWeeks { self.state.plan.termWeeks = termWeeks }
            self.state.timetable = timetable
            do { try self.save() }
            catch { self.state = previous; throw error }
            saved = true
            if previous.plan.termStart != self.state.plan.termStart || previous.plan.termWeeks != self.state.plan.termWeeks {
                try await self.rebuild()
            }
            self.notice = "课表已保存"
        }
        return saved
    }
    func requestNotifications() async {
        await perform {
            try await self.scheduler.requestPermission()
            try await self.rebuild()
        }
    }
    func register(server: String, name: String) async {
        await perform {
            guard !self.hasAccount else { throw AppError(message: "此设备已创建账号，请直接同步") }
            let url = try APIClient.normalizedURL(server)
            let normalized = url.absoluteString
            if TokenVault.read(server: normalized) != nil {
                self.state.serverURL = normalized
            } else {
                struct Registration: Decodable { let token: String }
                let client = APIClient(baseURL: url, token: nil)
                let result: Registration = try await client.request("v1/accounts", method: "POST", body: ["name": name])
                try TokenVault.save(result.token, server: normalized)
                self.state.serverURL = normalized
            }
            // No account data is shared across server identities.
            self.state.notes = []
            self.state.assignments = []
            self.state.pendingAcknowledgements = []
            try self.save()
            try await self.sync()
            try await self.rebuild()
        }
    }
    func bind(code: String) async {
        await perform {
            let client = try self.api
            self.profile = try await client.request("v1/pair", method: "POST",
                body: ["invite_code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
            try await self.sync()
            try await self.rebuild()
        }
    }
    func updateServer(address: String) async {
        await perform {
            guard let token = TokenVault.read(server: self.state.serverURL),
                  let accountID = self.state.accountID else {
                throw AppError(message: "请先成功同步一次账号，再修改地址")
            }
            let url = try APIClient.normalizedURL(address)
            let candidate = APIClient(baseURL: url, token: token)
            let checked: Profile = try await candidate.request("v1/me")
            guard checked.id == accountID else { throw AppError(message: "新地址不是原账号所在的服务器") }
            try TokenVault.save(token, server: url.absoluteString)
            self.state.serverURL = url.absoluteString
            try self.save()
            try await self.sync()
            try await self.rebuild()
            self.notice = "服务器地址已更新"
        }
    }
    func unpair() async {
        await perform {
            _ = try await self.api.raw("v1/pair", method: "DELETE")
            self.state.notes = []
            self.state.assignments = []
            self.state.pendingAcknowledgements = []
            self.state.outgoingID = nil
            self.state.outgoingText = nil
            try self.save()
            // Remove cached notes from pending notifications even if a later sync fails.
            try await self.rebuild()
            try await self.sync()
        }
    }
    func send(text: String) async {
        await perform {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 140 else { throw AppError(message: "请输入 1–140 字的留言") }
            if let pending = self.state.outgoingText, pending != text {
                throw AppError(message: "上一条留言发送结果尚未确认，请先重试原文：\(pending)")
            }
            let requestID = self.state.outgoingID ?? UUID().uuidString
            self.state.outgoingID = requestID
            self.state.outgoingText = text
            try self.save()
            do {
                _ = try await self.api.raw("v1/notes", method: "POST", body: ["text": text, "client_id": requestID])
            } catch {
                // A 4xx response confirms rejection; transport/5xx failures may have committed.
                if let status = (error as? AppError)?.statusCode, (400..<500).contains(status) {
                    self.state.outgoingID = nil
                    self.state.outgoingText = nil
                    try self.save()
                }
                throw error
            }
            self.state.outgoingID = nil
            self.state.outgoingText = nil
            try self.save()
            self.notice = "留言已发送，对方同步后会加入接下来的提醒"
        }
    }
}
