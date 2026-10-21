import SwiftUI

struct FriendView: View {
    @EnvironmentObject private var store: AppStore
    @State private var server = ""
    @State private var nickname = ""
    @State private var invite = ""
    @State private var text = ""
    @State private var showUnpair = false
    var body: some View {
        NavigationStack {
            Form {
                if !store.hasAccount {
                    Section {
                        TextField("服务器地址", text: $server)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("你的昵称", text: $nickname)
                        Button("创建本机账号") { Task { await store.register(server: server, name: nickname) } }
                            .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: { Text("连接你的服务器") } footer: {
                        Text("模拟器可用 http://localhost:8000；真机填写电脑的局域网地址。第一版账号与本机绑定，没有密码找回。")
                    }
                } else {
                    Section("我的账号") {
                        Text(store.profile?.name ?? "账号已保存，请同步")
                        Text(store.state.serverURL).font(.caption).foregroundStyle(.secondary)
                        if let code = store.profile?.inviteCode {
                            LabeledContent("我的邀请码") { Text(code).monospaced().textSelection(.enabled) }
                            ShareLink("分享邀请码", item: code)
                        }
                        Button("同步留言与账号", systemImage: "arrow.triangle.2.circlepath") { Task { await store.refresh() } }
                    }
                    Section {
                        TextField("服务器地址", text: $server)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("更新服务器地址") { Task { await store.updateServer(address: server) } }
                    } header: { Text("服务器") } footer: {
                        Text("仅在你自己的服务器地址变化时使用。账号凭据将发送到新地址，并核对是否为原账号。")
                    }
                    if let peer = store.profile?.peerName {
                        Section {
                            TextField("下次提醒时想说的话…", text: $text, axis: .vertical).lineLimit(3...5)
                            Text("\(text.count)/140").font(.caption).foregroundStyle(text.count > 140 ? Color.red : Color.secondary)
                            Button("发送留言") {
                                Task {
                                    await store.send(text: text)
                                    if store.error == nil { text = "" }
                                }
                            }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 140)
                            if let pending = store.state.outgoingText {
                                Button("重试尚未确认的留言") { Task { await store.send(text: pending) } }
                                Text(pending).font(.caption).foregroundStyle(.secondary)
                            }
                        } header: { Text("给 \(peer) 留一句话") } footer: { Text("对方打开 App 或点击同步后，留言会按顺序加入接下来的提醒。每人最多有 20 条待提醒留言。") }
                        Section {
                            Button("解除与 \(peer) 的绑定", role: .destructive) { showUnpair = true }
                        }
                    } else {
                        Section {
                            TextField("对方的 12 位邀请码", text: $invite)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            Button("绑定好友") { Task { await store.bind(code: invite) } }
                                .disabled(invite.trimmingCharacters(in: .whitespacesAndNewlines).count != 12)
                        } header: { Text("绑定一位好友") } footer: { Text("一方输入邀请码即可互相绑定。仅向你希望绑定的人分享邀请码。") }
                    }
                    Section {
                        if store.state.notes.isEmpty { Text("还没有待提醒留言").foregroundStyle(.secondary) }
                        ForEach(store.state.notes) { note in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.senderName).font(.caption).foregroundStyle(.teal)
                                Text(note.text)
                            }
                        }
                    } header: { Text("已同步的待提醒留言") } footer: { Text("提醒时间经过后，下次打开 App 会将留言标记为已安排结束；这不代表对方已阅读。锁屏通知预览遵循系统隐私设置。") }
                }
                if let notice = store.notice { Section { Text(notice).foregroundStyle(.teal) } }
            }
            .navigationTitle("好友")
            .onAppear { server = store.state.serverURL; text = store.state.outgoingText ?? "" }
            .confirmationDialog("解除绑定会删除双方服务端留言。对方需要同步后才会移除已下载的留言。", isPresented: $showUnpair, titleVisibility: .visible) {
                Button("解除绑定", role: .destructive) { Task { await store.unpair() } }
            }
        }
    }
}
