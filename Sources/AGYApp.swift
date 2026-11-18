import SwiftUI
import UIKit

@main struct AGYApp: App {
    @StateObject private var store = AGYStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            AGYRoot().environmentObject(store).tint(NativeTheme.accent)
                .task { await store.restore() }
                .onOpenURL { url in Task { await store.openActivity(url) } }
                .onChange(of: phase) { _, value in store.scene(value) }
        }
    }
}

struct AGYRoot: View {
    @EnvironmentObject private var store: AGYStore
    @State private var file: PreviewDocument?
    @State private var downloading = false
    var body: some View {
        Group {
            if store.connected {
                TabView(selection: $store.tab) {
                    AGYChat().tag(0).tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
                    AGYFiles().tag(3).tabItem { Label("文件", systemImage: "folder") }
                    AGYHistory().tag(1).tabItem { Label("历史", systemImage: "clock") }
                    AGYSettings().tag(2).tabItem { Label("设置", systemImage: "gearshape") }
                }
            } else { AGYConnection() }
        }
        .environment(\.nativeMediaAPI, store.api)
        .environment(\.nativeWorkspace, store.cwd)
        .environment(\.nativeSessionID, store.selected?.id ?? "")
        .environment(\.nativeMediaRunning, store.selected?.running ?? false)
        .environment(\.openURL, OpenURLAction { url in
            guard let api = store.api else { return .systemAction }
            let path = NativeFileRules.downloadPath(url, host: api.credentials.url.host ?? "", cwd: store.cwd)
            guard path != nil || NativeDownloadLinks.isExternalFile(url) else { return .systemAction }
            guard !downloading else { return .handled }
            let sid = store.selected?.id ?? ""
            downloading = true
            Task {
                defer { downloading = false }
                do {
                    let target: URL
                    if let path { target = try await api.download(path, sessionID: sid) }
                    else { target = try await api.downloadExternal(url) }
                    file = PreviewDocument(url: target)
                } catch { store.error = error.localizedDescription }
            }
            return .handled
        })
        .sheet(item: $file) { NativeDownloadedFile(url: $0.url) }
        .overlay {
            if downloading {
                ProgressView("正在下载文件…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
            }
        }
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
                    VStack(alignment: .leading, spacing: 10) {
                        NativeAGYLogo(size: 60)
                            .padding(.top, 28)
                        Text("AGY，随身同行。")
                            .font(.largeTitle.bold())
                        Text("连接你的服务器，在 iPhone 上继续工作。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("服务器地址")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("https://你的服务器", text: $address)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.URL)
                                .padding(13)
                                .background(NativeTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("连接密钥")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack {
                                Group {
                                    if visible { TextField("服务器提供的连接密钥", text: $key) }
                                    else { SecureField("服务器提供的连接密钥", text: $key) }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focused)

                                Button { visible.toggle() } label: {
                                    Image(systemName: visible ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("显示或隐藏连接密钥")
                            }
                            .padding(13)
                            .background(NativeTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button {
                            focused = false
                            do {
                                let c = try AGYCredentials.validated(address, token: key.trimmingCharacters(in: .whitespacesAndNewlines))
                                Task { await store.connect(c) }
                            } catch { store.error = error.localizedDescription }
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                if store.busy { ProgressView().tint(NativeTheme.onAccent) }
                                Text("连接 AGY").fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(store.busy || address.isEmpty || key.isEmpty)
                    }
                    .padding(20)
                    .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))

                    if let error = store.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                            NativeSelectableText(text: error, style: .callout, markdown: false, textColor: .systemRed)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Text("连接信息保存在本机钥匙串。Google 账号由服务器上的 AGY 管理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .background(NativeTheme.canvas)
            .navigationTitle("AGY")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if !store.storedURL.isEmpty { address = store.storedURL } }
        }
    }
}

struct AGYChat: View {
    @EnvironmentObject private var store: AGYStore
    @State private var showConfiguration = false
    @AppStorage("nativeOutputMode") private var outputMode = NativeOutputMode.steps.rawValue
    @State private var showFiles = false
    @State private var attachmentPicker: AGYAttachmentPicker?
    @State private var pickerContext = UUID()
    @State private var homeComposerFocused = false

    private var homeStatusColor: Color {
        if store.connection.contains("中断") || store.connection.contains("失败") { return .red }
        return .green
    }

    private var homeModelSummary: String {
        store.modelSummary(for: store.selected == nil ? store.model : store.homeConfig.model)
    }

    private var homeCwd: String {
        store.selected == nil ? store.cwd : store.homeConfig.workspace
    }

    private var homeMode: String {
        store.selected == nil ? store.mode : store.homeConfig.mode
    }

    private var homeApprovalMode: String {
        store.selected == nil ? store.approvalMode : store.homeConfig.approvalMode
    }

    var body: some View {
        NavigationStack(path: $store.chatPath) {
            homeScreen
                .navigationDestination(for: String.self) { sessionID in
                    AGYConversationScreen(
                        sessionID: sessionID,
                        outputMode: $outputMode,
                        onOpenConfiguration: { showConfiguration = true },
                        onOpenFiles: openFilesPicker,
                        onPickPhotos: { startAttachmentPicker(.photos) },
                        onPickDocuments: { startAttachmentPicker(.files) }
                    )
                }
        }
        .onChange(of: store.chatPath) { oldValue, newValue in
            if !oldValue.isEmpty && newValue.isEmpty {
                store.handlePoppedToHome()
            }
        }
        .sheet(isPresented: $showFiles) {
            AGYFiles(picking: true).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showConfiguration) { AGYConfiguration() }
        .sheet(item: $attachmentPicker) { picker in
            if picker == .photos {
                NativePhotoPicker(limit: max(1, 8 - store.attachments.count)) { results in
                    let context = pickerContext; attachmentPicker = nil
                    Task { await store.importPhotos(results, context: context) }
                }
            } else {
                NativeDocumentPicker { urls in
                    let context = pickerContext; attachmentPicker = nil
                    Task { await store.importFiles(urls, context: context) }
                }
            }
        }
    }

    private var homeScreen: some View {
        ScrollView {
            AGYHomeContent(
                recentSessions: Array(store.sessions.prefix(3)),
                totalSessionCount: store.sessions.count,
                cwd: homeCwd,
                modelSummary: homeModelSummary,
                mode: homeMode,
                approvalMode: homeApprovalMode,
                error: store.selected == nil ? store.error : nil,
                pendingSessionID: store.pending?.sessionID,
                busy: store.busy,
                onSelectPrompt: { prompt in
                    store.draft = prompt
                    store.saveDraft(debounced: true)
                    homeComposerFocused = true
                },
                onOpenConfiguration: { showConfiguration = true },
                onOpenFiles: openFilesPicker,
                onPickPhotos: {
                    if !store.busy && !store.importing && store.pending == nil && store.attachments.count < 8 {
                        startAttachmentPicker(.photos)
                    }
                },
                onSelectSession: { id in Task { await store.select(id) } },
                onOpenHistory: { store.tab = 1 },
                onRetryPending: { Task { await store.retryPending() } }
            )
            .equatable()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AGYComposerDock(
                focused: $homeComposerFocused,
                outputMode: $outputMode,
                activeInbox: [],
                running: false,
                onOpenFiles: openFilesPicker,
                onOpenConfiguration: { showConfiguration = true },
                onPickPhotos: { startAttachmentPicker(.photos) },
                onPickDocuments: { startAttachmentPicker(.files) },
                onJumpToLatest: nil
            )
        }
        .background(NativeTheme.canvas)
        .navigationTitle("AGY")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showConfiguration = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("模型和工作目录")
            }
            ToolbarItem(placement: .principal) {
                Button { showConfiguration = true } label: {
                    VStack(spacing: 1) {
                        Text("AGY")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(homeStatusColor)
                                .frame(width: 6, height: 6)
                            Text(homeModelSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.newConversation() } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
                .disabled(store.busy || store.pending != nil)
            }
        }
    }

    private func openFilesPicker() {
        if !store.busy && store.pending == nil {
            showFiles = true
        }
    }

    private func startAttachmentPicker(_ picker: AGYAttachmentPicker) {
        pickerContext = store.attachmentContext
        attachmentPicker = picker
    }
}

private struct AGYConversationScreen: View {
    @EnvironmentObject private var store: AGYStore
    let sessionID: String
    @Binding var outputMode: String
    let onOpenConfiguration: () -> Void
    let onOpenFiles: () -> Void
    let onPickPhotos: () -> Void
    let onPickDocuments: () -> Void

    @State private var following = true
    @State private var jumpToLatest = 0
    @State private var composerFocused = false

    private var displayedSession: AGYSession? {
        store.selected?.id == sessionID ? store.selected : nil
    }

    private var activeInbox: [AGYInboxItem] {
        (displayedSession?.inbox ?? []).filter(\.visibleInComposer)
    }

    private var statusColor: Color {
        if displayedSession?.approvals?.isEmpty == false { return .orange }
        if displayedSession?.running == true { return NativeTheme.accent }
        if store.connection.contains("中断") || store.connection.contains("失败") { return .red }
        return .green
    }

    private var headerSubtitle: String {
        if displayedSession?.running == true {
            return store.connection + " · " + (store.currentFamily?.name ?? "运行中")
        }
        return store.modelSummary(for: displayedSession?.model ?? store.model)
    }

    var body: some View {
        ScrollView {
            AGYConversationTranscript(
                sessionID: sessionID,
                selected: displayedSession,
                outputMode: outputMode,
                error: store.error,
                pendingSessionID: store.pending?.sessionID,
                busy: store.busy,
                onSelectSession: { id in Task { await store.select(id) } },
                onRetryPending: { Task { await store.retryPending() } }
            )
            .equatable()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(NativeScrollFollow(conversation: sessionID, active: true, jump: jumpToLatest, following: $following).frame(width: 0, height: 0))
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottomTrailing) {
            if !following {
                Button { jumpToLatest += 1 } label: {
                    Image(systemName: "arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                }
                .accessibilityLabel("回到最新消息")
                .padding(.trailing, 16)
                .padding(.bottom, 10)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AGYComposerDock(
                focused: $composerFocused,
                outputMode: $outputMode,
                activeInbox: activeInbox,
                running: displayedSession?.running == true,
                onOpenFiles: onOpenFiles,
                onOpenConfiguration: onOpenConfiguration,
                onPickPhotos: onPickPhotos,
                onPickDocuments: onPickDocuments,
                onJumpToLatest: { jumpToLatest += 1 }
            )
        }
        .background(NativeInteractivePopConfigurator().frame(width: 0, height: 0))
        .background(NativeTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: onOpenConfiguration) {
                    VStack(spacing: 1) {
                        Text(displayedSession?.name ?? "对话")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(headerSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onOpenConfiguration) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("模型和工作目录")

                Button { store.newConversation() } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
                .disabled(store.busy || store.pending != nil)
            }
        }
    }
}

private struct NativeInteractivePopConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) { uiView.enableInteractivePop() }

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            enableInteractivePop()
        }

        func enableInteractivePop() {
            DispatchQueue.main.async { [weak self] in
                var responder: UIResponder? = self
                while let current = responder {
                    if let nav = current as? UINavigationController {
                        if nav.viewControllers.count > 1 {
                            nav.interactivePopGestureRecognizer?.isEnabled = true
                        }
                        break
                    }
                    responder = current.next
                }
            }
        }
    }
}

private struct AGYComposerDock: View {
    @EnvironmentObject private var store: AGYStore
    @Binding var focused: Bool
    @Binding var outputMode: String
    let activeInbox: [AGYInboxItem]
    let running: Bool
    let onOpenFiles: () -> Void
    let onOpenConfiguration: () -> Void
    let onPickPhotos: () -> Void
    let onPickDocuments: () -> Void
    let onJumpToLatest: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !activeInbox.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(activeInbox) { item in
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: item.delivery == "steer" ? "arrow.turn.up.right" : "clock.arrow.circlepath")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.status == "held" ? .orange : NativeTheme.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(item.status == "held" ? .orange : .secondary)
                                    Text(item.text.isEmpty ? "文件与工作区引用" : item.text)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if !item.error.isEmpty {
                                        Text(item.error)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer(minLength: 4)
                                if item.status == "held" {
                                    Button("继续") { Task { await store.changeInbox(item, resume: true) } }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                }
                                if ["pending", "held"].contains(item.status) {
                                    Button { Task { await store.changeInbox(item, resume: false) } } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("取消这条消息")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        }
                    }
                }
                .frame(maxHeight: 128)
                .disabled(store.busy)
            }

            if !store.references.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.references) { entry in
                            HStack(spacing: 5) {
                                Image(systemName: entry.directory ? "folder.fill" : "doc.text")
                                    .font(.caption2)
                                    .foregroundStyle(NativeTheme.accent)
                                Text(entry.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Button {
                                    store.references.removeAll { $0.id == entry.id }
                                    store.saveDraft()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .accessibilityLabel("移除引用 " + entry.name)
                                .disabled(store.busy || store.pending != nil)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NativeTheme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        }
                    }
                }
            }

            if !store.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.attachments) { item in
                            HStack(spacing: 8) {
                                if item.imported.mime.hasPrefix("image/"), let image = UIImage(data: item.imported.data) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    Image(systemName: "doc.fill").foregroundStyle(NativeTheme.accent).frame(width: 28)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.imported.name).font(.caption.weight(.medium)).lineLimit(1)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.imported.data.count), countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(width: 104, alignment: .leading)
                                Button { store.attachments.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).frame(width: 28, height: 36)
                                }
                                .disabled(store.busy)
                                .accessibilityLabel("移除 \(item.imported.name)")
                            }
                            .padding(8)
                            .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        }
                    }
                }
                .frame(height: 58)
            }

            if store.importing || !store.uploadProgress.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(store.importing ? "正在读取附件…" : store.uploadProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button(action: onOpenFiles) {
                    HStack(spacing: 4) {
                        Image(systemName: "at")
                        Text("引用文件")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(NativeTheme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(NativeTheme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NativeTheme.accent)
                .disabled(store.busy || store.pending != nil)

                Button(action: onOpenConfiguration) {
                    HStack(spacing: 4) {
                        Image(systemName: store.approvalMode == "turbo" ? "bolt.fill" : "checkmark.shield")
                            .font(.caption2)
                        Text(store.approvalMode == "turbo" ? "Turbo" : store.approvalMode == "review" ? "逐项审批" : "旧版策略")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(NativeTheme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(NativeTheme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Menu {
                    Picker("输出展示", selection: $outputMode) {
                        ForEach(NativeOutputMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.indent")
                            .font(.caption2)
                        Text(NativeOutputMode(rawValue: outputMode)?.title ?? "原版")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(NativeTheme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(NativeTheme.border, lineWidth: 0.5))
                }
            }

            AGYComposerInputRow(
                composer: store.composer,
                focused: $focused,
                canSendReady: store.canSendReady,
                hasAttachmentsOrRefs: !store.attachments.isEmpty || !store.references.isEmpty,
                attachmentDisabled: store.busy || store.importing || store.pending != nil || store.attachments.count >= 8,
                busy: store.busy,
                running: running,
                canSteer: store.steeringReady && store.approvalMode != "legacy",
                onOpenFiles: onOpenFiles,
                onPickPhotos: onPickPhotos,
                onPickDocuments: onPickDocuments,
                onTextChanged: { store.saveDraft(debounced: true) },
                onStop: { Task { await store.stop() } },
                onSend: {
                    focused = false
                    store.composer.dismissKeyboard()
                    onJumpToLatest?()
                    Task { await store.send() }
                },
                onDeliver: { delivery in
                    focused = false
                    store.composer.dismissKeyboard()
                    Task { await store.send(delivery: delivery) }
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}

private struct AGYComposerInputRow: View {
    @ObservedObject var composer: AGYComposerState
    @Binding var focused: Bool
    let canSendReady: Bool
    let hasAttachmentsOrRefs: Bool
    let attachmentDisabled: Bool
    let busy: Bool
    let running: Bool
    let canSteer: Bool
    let onOpenFiles: () -> Void
    let onPickPhotos: () -> Void
    let onPickDocuments: () -> Void
    let onTextChanged: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void
    let onDeliver: (String) -> Void

    private var canSend: Bool {
        canSendReady && (composer.hasContent || hasAttachmentsOrRefs)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button("引用工作文件", systemImage: "at", action: onOpenFiles)
                Divider()
                Button("照片图库", systemImage: "photo.on.rectangle", action: onPickPhotos)
                Button("选择文件", systemImage: "doc", action: onPickDocuments)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NativeTheme.accent)
                    .frame(width: 34, height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .disabled(attachmentDisabled)
            .accessibilityLabel("添加照片、文件或引用")

            NativeComposerInput(
                state: composer,
                focused: $focused,
                placeholder: "发送消息…",
                maxLines: 6,
                onMentionTyped: onOpenFiles,
                onTextChanged: onTextChanged
            )

            if running {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 36)
                        .background(Color.red.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("停止任务并暂停排队消息")

                Menu {
                    Button("立即引导 · 下一次思考生效", systemImage: "arrow.turn.up.right") {
                        onDeliver("steer")
                    }
                    .disabled(!canSteer)
                    Button("排队跟进 · 本轮结束后发送", systemImage: "text.badge.plus") {
                        onDeliver("queue")
                    }
                } label: {
                    sendButtonIcon
                }
                .disabled(!canSend)
                .accessibilityLabel("引导或排队发送")
            } else {
                Button(action: onSend) {
                    sendButtonIcon
                }
                .disabled(!canSend)
                .accessibilityLabel("发送消息")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(NativeTheme.composer, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var sendButtonIcon: some View {
        Group {
            if busy {
                ProgressView().controlSize(.small).tint(NativeTheme.onAccent)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
            }
        }
        .frame(width: 36, height: 36)
        .background(canSend ? NativeTheme.accent : NativeTheme.inactiveControl, in: Circle())
        .foregroundStyle(canSend ? NativeTheme.onAccent : NativeTheme.inactiveSymbol)
    }
}

private struct AGYQuickActionItem: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let prompt: String
}

private struct AGYHomeContent: View, Equatable {
    let recentSessions: [AGYSession]
    let totalSessionCount: Int
    let cwd: String
    let modelSummary: String
    let mode: String
    let approvalMode: String
    let error: String?
    let pendingSessionID: String?
    let busy: Bool
    let onSelectPrompt: (String) -> Void
    let onOpenConfiguration: () -> Void
    let onOpenFiles: () -> Void
    let onPickPhotos: () -> Void
    let onSelectSession: (String) -> Void
    let onOpenHistory: () -> Void
    let onRetryPending: () -> Void

    static func == (lhs: AGYHomeContent, rhs: AGYHomeContent) -> Bool {
        lhs.recentSessions == rhs.recentSessions
            && lhs.totalSessionCount == rhs.totalSessionCount
            && lhs.cwd == rhs.cwd
            && lhs.modelSummary == rhs.modelSummary
            && lhs.mode == rhs.mode
            && lhs.approvalMode == rhs.approvalMode
            && lhs.error == rhs.error
            && lhs.pendingSessionID == rhs.pendingSessionID
            && lhs.busy == rhs.busy
    }

    private static let quickActions: [AGYQuickActionItem] = [
        AGYQuickActionItem(
            id: "explore",
            icon: "folder.badge.gearshape",
            tint: .blue,
            title: "梳理项目架构",
            subtitle: "目录结构与核心职责",
            prompt: "查看当前目录，梳理项目结构与关键模块职责"
        ),
        AGYQuickActionItem(
            id: "debug",
            icon: "ladybug.fill",
            tint: .orange,
            title: "排查与修复问题",
            subtitle: "定位根因并给出方案",
            prompt: "帮我排查一个问题，先定位根因再给出修改方案"
        ),
        AGYQuickActionItem(
            id: "design",
            icon: "paintbrush.pointed.fill",
            tint: .purple,
            title: "绘制 SVG 与界面",
            subtitle: "矢量图示或界面原型",
            prompt: "根据当前项目绘制一张清晰的架构 SVG 示意图，让我直接在对话中预览"
        ),
        AGYQuickActionItem(
            id: "verify",
            icon: "checkmark.seal.fill",
            tint: .green,
            title: "检查改动与验证",
            subtitle: "查看状态并运行测试",
            prompt: "检查当前的 git 状态与最近改动，并运行必要的验证"
        )
    ]

    private var workspaceTitle: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? (cwd.isEmpty ? "默认工作区" : cwd) : name
    }

    private var modeLabel: String {
        mode == "accept-edits" ? "直接实施" : "先做计划"
    }

    private var approvalLabel: String {
        approvalMode == "turbo" ? "Turbo 自动" : approvalMode == "review" ? "逐项审批" : "旧版策略"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 13) {
                NativeAGYLogo(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("今天想做些什么？")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("选择工作区或快捷任务，直接开始对话。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)

            Button(action: onOpenConfiguration) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NativeTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(NativeTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2.5) {
                            Text(workspaceTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(cwd.isEmpty ? "点击选择服务器工作目录" : cwd)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 6)

                        HStack(spacing: 3) {
                            Text("配置")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            statusPill(icon: "cpu", text: modelSummary, tint: NativeTheme.accent)
                            statusPill(icon: mode == "accept-edits" ? "hammer.fill" : "list.clipboard", fallbackIcon: "sparkles", text: modeLabel, tint: .indigo)
                            statusPill(icon: approvalMode == "turbo" ? "bolt.fill" : "checkmark.shield", text: approvalLabel, tint: approvalMode == "turbo" ? .orange : .green)
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                Text("快速开始")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.quickActions) { item in
                        Button { onSelectPrompt(item.prompt) } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(item.tint)
                                    .frame(width: 32, height: 32)
                                    .background(item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onOpenFiles) {
                        HStack(spacing: 6) {
                            Image(systemName: "at")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NativeTheme.accent)
                            Text("引用工作区文件")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onPickPhotos) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                            Text("附上截图提问")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("继续最近对话")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if totalSessionCount > recentSessions.count {
                            Button(action: onOpenHistory) {
                                HStack(spacing: 3) {
                                    Text("全部 \(totalSessionCount) 条")
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(NativeTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)

                    VStack(spacing: 0) {
                        ForEach(Array(recentSessions.enumerated()), id: \.element.id) { index, session in
                            Button { onSelectSession(session.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: session.running ? "bolt.horizontal.circle.fill" : "bubble.left.and.text.bubble.right")
                                        .font(.subheadline)
                                        .foregroundStyle(session.running ? NativeTheme.accent : .secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(session.name.isEmpty ? "未命名对话" : session.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if session.running {
                                                ProgressView().controlSize(.mini)
                                            }
                                        }
                                        HStack(spacing: 5) {
                                            Text(URL(fileURLWithPath: session.cwd).lastPathComponent)
                                            Text("·")
                                            Text(Date(timeIntervalSince1970: session.modified), style: .relative)
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }

                                    Spacer(minLength: 6)

                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index + 1 < recentSessions.count {
                                Divider().padding(.leading, 52).opacity(0.5)
                            }
                        }
                    }
                    .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                }
            }

            if let issue = error {
                AGYStatusBanner(text: issue, icon: "wifi.exclamationmark", tint: .red, uiColor: .systemRed)
            }

            if let pendingSessionID {
                AGYPendingBanner(
                    pendingSessionID: pendingSessionID,
                    busy: busy,
                    onSelectSession: onSelectSession,
                    onRetryPending: onRetryPending
                )
            }
        }
    }

    private func statusPill(icon: String, fallbackIcon: String? = nil, text: String, tint: Color) -> some View {
        let resolvedIcon = UIImage(systemName: icon) != nil ? icon : (fallbackIcon ?? "circle.fill")
        return HStack(spacing: 5) {
            Image(systemName: resolvedIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

private struct AGYConversationTranscript: View, Equatable {
    let sessionID: String
    let selected: AGYSession?
    let outputMode: String
    let error: String?
    let pendingSessionID: String?
    let busy: Bool
    let onSelectSession: (String) -> Void
    let onRetryPending: () -> Void

    static func == (lhs: AGYConversationTranscript, rhs: AGYConversationTranscript) -> Bool {
        lhs.sessionID == rhs.sessionID
            && lhs.selected == rhs.selected
            && lhs.outputMode == rhs.outputMode
            && lhs.error == rhs.error
            && lhs.pendingSessionID == rhs.pendingSessionID
            && lhs.busy == rhs.busy
    }

    private var presentedMessages: [ChatMessage] {
        (selected?.messages ?? []).flatMap(\.presented)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if !presentedMessages.isEmpty {
                if outputMode == NativeOutputMode.original.rawValue {
                    ForEach(presentedMessages) { message in
                        NativeMessageRow(
                            message: message,
                            streaming: message.id == selected?.messages?.last?.id && selected?.running == true
                        )
                    }
                } else {
                    NativeConversationTurns(
                        turns: NativeConversationPresentation.turns(presentedMessages, live: nil, running: selected?.running ?? false),
                        mode: NativeOutputMode(rawValue: outputMode) ?? .steps
                    )
                }
            } else if selected?.approvals?.isEmpty != false {
                if busy || (selected == nil && error == nil) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(selected?.id == sessionID ? "正在发送消息…" : "正在加载对话…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                } else if selected != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还没有消息")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("在下方输入内容开始对话，或向右滑动返回主界面。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                }
            }

            ForEach(selected?.approvals ?? []) { request in
                AGYApprovalCard(request: request)
            }

            if selected?.running == true && outputMode == NativeOutputMode.original.rawValue {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("AGY 正在工作…").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NativeTheme.surface, in: Capsule())
            }

            if let issue = error {
                AGYStatusBanner(text: issue, icon: "wifi.exclamationmark", tint: .red, uiColor: .systemRed)
            }
            if let sessionError = selected?.error, !sessionError.isEmpty {
                AGYStatusBanner(text: sessionError, icon: "exclamationmark.circle.fill", tint: .orange, uiColor: .systemOrange)
            }

            if let pendingSessionID {
                AGYPendingBanner(
                    pendingSessionID: pendingSessionID,
                    busy: busy,
                    onSelectSession: onSelectSession,
                    onRetryPending: onRetryPending
                )
            }

            Color.clear.frame(height: 1).id("bottom")
        }
    }
}

private struct AGYStatusBanner: View {
    let text: String
    let icon: String
    let tint: Color
    let uiColor: UIColor

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(tint)
                .padding(.top, 2)
            NativeSelectableText(text: text, style: .callout, markdown: false, textColor: uiColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
    }
}

private struct AGYPendingBanner: View {
    let pendingSessionID: String
    let busy: Bool
    let onSelectSession: (String) -> Void
    let onRetryPending: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("上一条消息的发送结果待确认", systemImage: "clock.badge.questionmark")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 10) {
                Button("核对会话") { onSelectSession(pendingSessionID) }
                Button("按原编号重试", action: onRetryPending)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(busy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
    }
}

enum AGYAttachmentPicker: String, Identifiable { case photos, files; var id: String { rawValue } }

struct AGYConfiguration: View {
    @EnvironmentObject private var store: AGYStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("主动修改的配置会记住，供新对话沿用；已有对话使用各自保存的配置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("1 · 选择模型") {
                    Picker("模型", selection: Binding(get: { store.baseModel }, set: { value in Task { await store.setModel(value) } })) {
                        ForEach(store.families) { family in Text(family.name).tag(family.id) }
                    }
                    Button { Task { await store.refreshModels() } } label: {
                        HStack {
                            Text("刷新可用模型")
                            Spacer()
                            if store.modelsLoading { ProgressView() }
                        }
                    }
                    .disabled(store.modelsLoading)
                }
                .disabled(store.busy || store.selected?.running == true || !store.gatewayReady)

                Section("2 · 思考强度") {
                    if let family = store.currentFamily, family.efforts != [""] {
                        Picker("思考强度", selection: Binding(get: { store.effort }, set: { value in Task { await store.setThinking(value) } })) {
                            ForEach(family.efforts, id: \.self) { Text(AGYThinking.title($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Text("当前模型未提供独立的思考强度选项").foregroundStyle(.secondary)
                    }
                }
                .disabled(store.busy || store.selected?.running == true || !store.gatewayReady)

                Section("3 · 审批策略") {
                    Picker("审批策略", selection: Binding(get: { store.approvalMode }, set: { value in Task { await store.configure(permission: value) } })) {
                        if store.approvalMode == "legacy" { Text("旧版策略 · 请重新选择").tag("legacy") }
                        ForEach(AGYApprovalMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text(AGYApprovalMode(rawValue: store.approvalMode)?.detail ?? "旧会话尚未选择新版审批策略。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .disabled(store.busy || store.selected?.running == true || !store.gatewayReady)

                Section("执行方式") {
                    Picker("执行方式", selection: Binding(get: { store.mode }, set: { value in Task { await store.configure(agentMode: value) } })) {
                        Text("先做计划").tag("plan")
                        Text("直接实施").tag("accept-edits")
                    }
                    Text("执行方式决定先计划还是直接工作；审批策略单独控制工具是否需要你确认。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .disabled(store.busy || store.selected?.running == true || !store.gatewayReady)

                Section("工作空间") {
                    LabeledContent("当前目录", value: URL(fileURLWithPath: store.cwd).lastPathComponent)
                    NavigationLink("浏览并选择项目目录") { AGYWorkspacePicker() }
                    if store.selected != nil {
                        Text("工作目录在新建会话时设置。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(store.selected != nil || store.busy)

                if !store.gatewayReady {
                    Section {
                        Text("此服务器尚未启用新版账号与审批后端，见源码包中的部署说明。")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("模型与任务配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await store.refreshModels() }
        }
    }
}

struct AGYApprovalCard: View {
    let request: AGYApproval
    @EnvironmentObject private var store: AGYStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("等待审批 · " + request.tool, systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("到期 " + Date(timeIntervalSince1970: request.expiresAt).formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !request.parameters["CommandLine"].string.isEmpty {
                NativeSelectableText(text: request.parameters["CommandLine"].string, style: .monospacedCallout, markdown: false)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let path = ["AbsolutePath", "TargetFile", "path", "Url"].map({ request.parameters[$0].string }).first(where: { !$0.isEmpty }) {
                NativeSelectableText(text: path, style: .callout, markdown: false)
            }
            Text("只有这一次操作会被批准，不会记住为始终允许。")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup("查看完整操作参数") {
                NativeSelectableText(text: request.parameters.pretty, style: .monospacedCaption, markdown: false)
                    .padding(.top, 4)
            }
            .font(.caption)
            HStack(spacing: 12) {
                Button("拒绝", role: .destructive) { Task { await store.answer(request, allow: false) } }
                    .buttonStyle(.bordered)
                Spacer()
                Button("仅允许本次") { Task { await store.answer(request, allow: true) } }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(store.approvalBusy || request.expiresAt <= Date().timeIntervalSince1970)
        }
        .padding(16)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.orange.opacity(0.5), lineWidth: 1))
    }
}

struct AGYHistory: View {
    @EnvironmentObject private var store: AGYStore
    @State private var search = ""
    @State private var renaming: AGYSession?
    @State private var newName = ""
    @State private var deleting: AGYSession?

    private var filtered: [AGYSession] {
        store.sessions.filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.cwd.localizedStandardContains(search) }
    }
    private var groups: [NativeSessionHistory.Group] {
        let formatter = ISO8601DateFormatter()
        let rows = filtered.map { PiSession(id: $0.id, cwd: $0.cwd, name: $0.name, firstMessage: nil, modified: formatter.string(from: Date(timeIntervalSince1970: $0.modified)), relation: nil) }
        return NativeSessionHistory.groups(rows)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { entry in
                            if let s = filtered.first(where: { $0.id == entry.id }) {
                                Button {
                                    store.tab = 0
                                    Task { await store.select(s.id) }
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 6) {
                                                if store.selected?.id == s.id {
                                                    Circle().fill(NativeTheme.accent).frame(width: 7, height: 7)
                                                }
                                                Text(s.name)
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                                if s.running { ProgressView().controlSize(.mini) }
                                            }
                                            HStack(spacing: 6) {
                                                Image(systemName: "folder")
                                                    .font(.caption2)
                                                Text(URL(fileURLWithPath: s.cwd).lastPathComponent)
                                                Text("·")
                                                Text(Date(timeIntervalSince1970: s.modified), style: .relative)
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .swipeActions {
                                    Button("删除", role: .destructive) { deleting = s }.disabled(s.running)
                                    Button("重命名") { renaming = s; newName = s.name }.tint(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("历史对话")
            .searchable(text: $search, prompt: "搜索名称或目录")
            .refreshable { await store.reload() }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView("还没有对话", systemImage: "bubble.left.and.bubble.right", description: Text("在对话页发送第一条消息。"))
                }
            }
            .toolbar {
                Button { Task { await store.reload() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新历史")
            }
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
    @AppStorage("nativeOutputMode") private var settingsOutputMode = NativeOutputMode.original.rawValue
    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    LabeledContent("地址") {
                        NativeSelectableText(text: store.storedURL, style: .callout, markdown: false, wraps: false)
                    }
                    LabeledContent("状态", value: store.connection)
                    ForEach(store.roots, id: \.self) { root in
                        NativeSelectableText(text: root, style: .caption, markdown: false)
                    }
                }
                Section {
                    NavigationLink { AGYLimitsView() } label: { Label("账户额度", systemImage: "chart.bar") }
                }
                AGYLiveActivitySettings(activity: store.liveActivity)
                Section("输出展示") {
                    Picker("展示方式", selection: $settingsOutputMode) {
                        ForEach(NativeOutputMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("步骤摘要和结论优先保留真实过程，随时可以展开。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("账号") {
                    Text("Google 账号在服务器独立配置中登录；更换账号后会重新读取模型和额度，并隔离历史及草稿。")
                        .font(.footnote)
                }
                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("独立的原生 AGY 客户端，沿用 Pi iPhone 的聊天体验。Google 登录与任务运行在服务器上完成。")
                        .font(.footnote)
                    Text("App 会话由独立网关管理，当前不导入官方 Remote Control 的会话列表。切到后台后服务器任务继续，回到前台重新同步。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("断开并清除本机连接", role: .destructive) { disconnect = true }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("断开连接？", isPresented: $disconnect, titleVisibility: .visible) {
                Button("断开连接", role: .destructive) { store.disconnect() }
            } message: { Text("服务器上的会话与正在执行的任务会保留。") }
        }
    }
}

struct AGYLiveActivitySettings: View {
    @ObservedObject var activity: AGYLiveActivity
    @EnvironmentObject private var store: AGYStore
    var body: some View {
        Section("锁屏与灵动岛") {
            Toggle("任务实时活动", isOn: $activity.enabled)
            Toggle("显示任务标题和进展", isOn: $activity.previews).disabled(!activity.enabled)
            if !activity.available {
                Text("请在 iPhone 设置中允许 AGY 的实时活动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("进展到达即更新，运行时每 8 秒核对状态；切到后台后在系统允许的短时间内继续刷新。系统挂起后显示最近状态和更新时间，点按恢复同步。默认隐藏任务内容。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let issue = activity.issue {
                Text(issue).font(.footnote).foregroundStyle(.orange)
            }
        }
        .onChange(of: activity.enabled) { _, _ in store.updateLiveActivity() }
        .onChange(of: activity.previews) { _, _ in store.updateLiveActivity() }
    }
}
