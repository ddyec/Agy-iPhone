import SwiftUI

@main struct AGYApp: App {
    @StateObject private var store = AGYStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            AGYRoot().environmentObject(store).tint(NativeTheme.accent)
                .task { await store.restore() }
                .onChange(of: phase) { _, value in store.scene(value) }
        }
    }
}
struct AGYRoot: View {
    @EnvironmentObject private var store: AGYStore
    var body: some View {
        if store.connected {
            TabView(selection: $store.tab) {
                AGYChat().tag(0).tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
                AGYHistory().tag(1).tabItem { Label("历史", systemImage: "clock") }
                AGYSettings().tag(2).tabItem { Label("设置", systemImage: "gearshape") }
            }
        } else { AGYConnection() }
    }
}
struct AGYConnection: View {
    @EnvironmentObject private var store: AGYStore
    @State private var address = "https://agy.yectech.uk"
    @State private var key = ""
    @State private var visible = false
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    NativeAGYLogo(size: 64).padding(.top, 36)
                    Text("AGY，随身同行。 ").font(.largeTitle.bold())
                    Text("连接你的服务器，在 iPhone 上继续工作。").font(.body).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("服务器地址").font(.headline)
                        TextField("https://你的服务器", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.URL).padding(12).background(NativeTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        Text("连接密钥").font(.headline)
                        HStack {
                            Group { if visible { TextField("服务器提供的连接密钥", text: $key) } else { SecureField("服务器提供的连接密钥", text: $key) } }
                                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                            Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye") }.accessibilityLabel("显示或隐藏连接密钥")
                        }.padding(12).background(NativeTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        Button {
                            focused = false
                            do { let c = try AGYCredentials.validated(address, token: key.trimmingCharacters(in: .whitespacesAndNewlines)); Task { await store.connect(c) } }
                            catch { store.error = error.localizedDescription }
                        } label: { HStack { Spacer(); if store.busy { ProgressView() }; Text("连接 AGY").fontWeight(.semibold); Spacer() }.padding(.vertical, 10) }
                            .buttonStyle(.borderedProminent).disabled(store.busy || address.isEmpty || key.isEmpty)
                    }.padding(20).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    if let error = store.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                    Text("连接信息保存在本机钥匙串。Google 账号由服务器上的 AGY 管理。").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(NativeTheme.canvas).navigationTitle("AGY").navigationBarTitleDisplayMode(.inline)
                .onAppear { if !store.storedURL.isEmpty { address = store.storedURL } }
        }
    }
}
struct AGYChat: View {
    @EnvironmentObject private var store: AGYStore
    @State private var showConfiguration = false
    @FocusState private var composerFocused: Bool
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.selected?.messages?.isEmpty != false {
                            VStack(alignment: .leading, spacing: 16) {
                                NativeAGYLogo(size: 52)
                                Text("今天想做些什么？").font(.title.bold())
                                Text("分析代码、整理思路，或继续服务器上的工作。").foregroundStyle(.secondary)
                                ForEach(["查看当前目录，介绍项目结构", "帮我分析一个问题，先给出计划"], id: \.self) { text in
                                    Button { store.draft = text } label: { HStack { Text(text).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.up.left") }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain)
                                }
                            }.padding(.vertical, 36)
                        }
                        ForEach(store.selected?.messages ?? []) { message in
                            if !message.text.isEmpty { NativeMessageRow(message: message.rendered, streaming: message.id == store.selected?.messages?.last?.id && store.selected?.running == true) }
                            ForEach(message.tools ?? []) { tool in
                                DisclosureGroup {
                                    if tool.parameters != .object([:]) { Text(tool.parameters.pretty).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                                    if !tool.output.isEmpty { Text(tool.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                                } label: { Label(tool.name + (tool.state == "DONE" ? " · 完成" : " · 运行中"), systemImage: "terminal") }.font(.callout).padding(14).background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        if store.selected?.running == true { HStack { ProgressView(); Text("AGY 正在工作…").font(.callout).foregroundStyle(.secondary) }.padding(10) }
                        if let issue = store.error { Label(issue, systemImage: "wifi.exclamationmark").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                        if let error = store.selected?.error, !error.isEmpty { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                        if store.pending != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("上一条消息的发送结果待确认。").font(.callout)
                                HStack {
                                    Button("核对会话") { if let id = store.pending?.sessionID { Task { await store.select(id) } } }
                                    Button("按原编号重试") { Task { await store.retryPending() } }
                                }.buttonStyle(.bordered).disabled(store.busy)
                            }.padding().background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(16)
                }.scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: store.selected?.revision) { _, _ in if store.selected?.running == true { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                    .background(NativeTheme.canvas)
            }
            .navigationTitle(store.selected?.name ?? "AGY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showConfiguration = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 36, height: 36) }.accessibilityLabel("模型和工作目录") }
                ToolbarItem(placement: .topBarTrailing) { Button { store.newConversation() } label: { Image(systemName: "square.and.pencil").frame(width: 36, height: 36) }.accessibilityLabel("新建对话").disabled(store.busy || store.pending != nil) }
            }
            .sheet(isPresented: $showConfiguration) { AGYConfiguration() }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(store.selected?.running == true ? .orange : NativeTheme.accent).frame(width: 6, height: 6)
                Text(store.connection).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showConfiguration = true } label: { Text(store.models.first(where: { $0.id == store.model })?.name ?? "选择模型").lineLimit(1).font(.caption) }
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("发送消息…", text: $store.draft, axis: .vertical).lineLimit(1...6).focused($composerFocused).padding(.vertical, 9)
                if store.selected?.running == true {
                    Button { Task { await store.stop() } } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44).background(NativeTheme.accent, in: Circle()).foregroundStyle(NativeTheme.onAccent) }.accessibilityLabel("停止任务")
                } else {
                    Button { composerFocused = false; Task { await store.send() } } label: {
                        Group { if store.busy { ProgressView() } else { Image(systemName: "arrow.up").fontWeight(.semibold) } }.frame(width: 44, height: 44)
                            .background(store.canSend ? NativeTheme.accent : NativeTheme.inactiveControl, in: Circle()).foregroundStyle(store.canSend ? NativeTheme.onAccent : NativeTheme.inactiveSymbol)
                    }.disabled(!store.canSend).accessibilityLabel("发送消息")
                }
            }.padding(10).background(NativeTheme.composer, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(NativeTheme.border, lineWidth: 1))
        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10).background(NativeTheme.canvas)
            .onChange(of: store.draft) { _, _ in store.saveDraft() }
    }
}
struct AGYConfiguration: View {
    @EnvironmentObject private var store: AGYStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("模型") { Picker("模型", selection: $store.model) { ForEach(store.models) { Text($0.name).tag($0.id) } }.pickerStyle(.inline) }
                Section("工作空间") {
                    Picker("目录", selection: $store.cwd) { ForEach(store.roots, id: \.self) { Text($0).tag($0) } }
                    Picker("执行方式", selection: $store.mode) { Text("先做计划").tag("plan"); Text("允许编辑文件").tag("accept-edits") }
                    Text("计划模式用于分析。允许编辑文件后，AGY 可在服务器工作目录修改文件；需要额外批准的操作可能被无头 CLI 拒绝。").font(.footnote).foregroundStyle(.secondary)
                }
                if store.selected != nil { Section { Text("这些选项在新建会话时设置。要更换模型或工作目录，请新建对话。").font(.footnote) } }
            }.disabled(store.selected != nil || store.busy).navigationTitle("对话配置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
struct AGYHistory: View {
    @EnvironmentObject private var store: AGYStore
    @State private var search = ""
    @State private var renaming: AGYSession?
    @State private var newName = ""
    @State private var deleting: AGYSession?
        private var filtered: [AGYSession] { store.sessions.filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.cwd.localizedStandardContains(search) } }
    var body: some View {
        NavigationStack {
            List(filtered) { s in
                Button { Task { await store.select(s.id); store.tab = 0 } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(s.name).font(.headline).foregroundStyle(.primary).lineLimit(2); if s.running { ProgressView().controlSize(.small) } }
                        Text(s.cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(Date(timeIntervalSince1970: s.modified), style: .relative).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }.swipeActions {
                    Button("删除", role: .destructive) { deleting = s }.disabled(s.running)
                    Button("重命名") { renaming = s; newName = s.name }.tint(.blue)
                }
            }.navigationTitle("历史对话").searchable(text: $search, prompt: "搜索名称或目录").refreshable { await store.reload() }
                .overlay { if filtered.isEmpty { ContentUnavailableView("还没有对话", systemImage: "bubble.left.and.bubble.right", description: Text("在对话页发送第一条消息。")) } }
                .toolbar { Button { Task { await store.reload() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新历史") }
                .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("名称", text: $newName)
                    Button("保存") { if let s = renaming { Task { await store.rename(s, name: newName) } }; renaming = nil }
                    Button("取消", role: .cancel) { renaming = nil }
                }
                .confirmationDialog("删除此对话？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("删除", role: .destructive) { if let s = deleting { Task { await store.delete(s) } }; deleting = nil }
                } message: { Text("删除 App 网关中的历史记录；不会删除 AGY 自己保存的原始会话。") }
        }
    }
}
struct AGYSettings: View {
    @EnvironmentObject private var store: AGYStore
    @State private var disconnect = false
    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    LabeledContent("地址", value: store.storedURL).textSelection(.enabled)
                    LabeledContent("状态", value: store.connection)
                    ForEach(store.roots, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("独立的原生 AGY 客户端，沿用 Pi iPhone 的聊天体验。Google 登录与任务运行在服务器上完成。").font(.footnote)
                    Text("App 会话由独立网关管理，当前不导入官方 Remote Control 的会话列表。切到后台后服务器任务继续，回到前台重新同步。").font(.footnote).foregroundStyle(.secondary)
                }
                Section { Button("断开并清除本机连接", role: .destructive) { disconnect = true } }
            }.navigationTitle("设置").confirmationDialog("断开连接？", isPresented: $disconnect, titleVisibility: .visible) {
                Button("断开连接", role: .destructive) { store.disconnect() }
            } message: { Text("服务器上的会话与正在执行的任务会保留。") }
        }
    }
}
