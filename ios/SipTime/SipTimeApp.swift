import SwiftUI
import UIKit

@main
@MainActor
struct SipTimeApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).tint(.teal) }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var body: some View {
        TabView {
            TodayView().tabItem { Label("今天", systemImage: "drop") }
            CourseTimetableView().tabItem { Label("课表", systemImage: "tablecells") }
            PlanView().tabItem { Label("提醒计划", systemImage: "calendar") }
            FriendView().tabItem { Label("好友", systemImage: "bubble.left.and.bubble.right") }
        }
        .disabled(store.isBusy)
        .overlay(alignment: .top) {
            if store.isBusy { ProgressView().padding(10).background(.regularMaterial, in: Capsule()) }
        }
        .task { await store.refresh() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active { Task { await store.refresh() } }
        }
        .onReceive(timer) { _ in
            if phase == .active { Task { await store.refresh(online: false) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await store.refresh(online: false) }
        }
        .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    private var today: [Date] { store.dates.filter { Calendar.current.isDateInToday($0) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(.teal)
                        Text("课间一口").font(.title.bold())
                        if let next = store.dates.first {
                            Text("下次提醒").foregroundStyle(.secondary)
                            Text(next, format: .dateTime.month().day().weekday().hour().minute())
                                .font(.title2.monospacedDigit())
                        } else {
                            Text("给课间留一点喝水的时间").foregroundStyle(.secondary)
                        }
                        Text(store.status).font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                Section {
                    Button("允许喝水通知", systemImage: "bell.badge") { Task { await store.requestNotifications() } }
                    Button("打开系统通知设置", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Button(store.state.plan.pausedDay == LocalDay(Date()) ? "恢复今天的提醒" : "今天先暂停",
                           systemImage: "pause.circle") { Task { await store.togglePauseToday() } }
                    if let last = store.dates.last {
                        LabeledContent("已安排至") { Text(last, format: .dateTime.month().day().hour().minute()) }
                    }
                } header: { Text("提醒状态") } footer: {
                    Text("打开 App 会补充最多 60 条本地通知。超过已安排日期后，需要再次打开补充。专注模式或通知摘要可能影响显示时间。")
                }
                Section("今天接下来的提醒") {
                    if today.isEmpty { Text("今天暂无后续提醒").foregroundStyle(.secondary) }
                    ForEach(today, id: \.self) { date in
                        HStack {
                            Label(date.formatted(date: .omitted, time: .shortened), systemImage: "drop")
                            Spacer()
                            if let assignment = store.state.assignments.first(where: { $0.date == date }),
                               let note = store.state.notes.first(where: { $0.id == assignment.noteID }) {
                                Text("\(note.senderName) 的留言").font(.caption).foregroundStyle(.teal)
                            }
                        }
                    }
                }
                if let notice = store.notice { Section { Text(notice).foregroundStyle(.teal) } }
            }
            .navigationTitle("今天")
            .refreshable { await store.refresh() }
        }
    }
}
