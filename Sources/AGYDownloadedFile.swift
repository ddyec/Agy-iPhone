import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct PreviewDocument: Identifiable { let id = UUID(); let url: URL }
struct NativeDownloadedFile: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var saving = false
    @State private var saved: String?
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            Group {
                if QLPreviewController.canPreview(url as NSURL) { NativeQuickLook(url: url) }
                else { ContentUnavailableView("文件已下载", systemImage: "doc", description: Text("此类型暂不支持预览，可以存储到文件或分享给其他 App。")) }
            }
            .navigationTitle(url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") } }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text("已保存在本机：文件 App → 我的 iPhone → AGY → 下载").font(.caption2).foregroundStyle(.secondary)
                    if saving { ProgressView("正在写入所选文件夹…") }
                    if let saved { Text(saved).font(.caption).foregroundStyle(.green).textSelection(.enabled) }
                    if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    HStack {
                    Button("存储到文件", systemImage: "folder") { exporting = true }.buttonStyle(.borderedProminent)
                    ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    }.disabled(saving)
                }.frame(maxWidth: .infinity).padding().background(.regularMaterial)
            }
            .sheet(isPresented: $exporting) {
                NativeExportPicker { folder in
                    exporting = false
                    guard let folder else { return }
                    saving = true; saved = nil; issue = nil
                    Task {
                        defer { saving = false }
                        do {
                            let source = url
                            let destination = try await Task.detached { try NativeLocalFileStore.export(source, to: folder) }.value
                            saved = "已写入所选文件夹：" + destination.lastPathComponent
                        } catch { issue = "保存失败：" + error.localizedDescription }
                    }
                }
            }
        }
    }
}
private struct NativeExportPicker: UIViewControllerRepresentable {
    let onComplete: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onComplete(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onComplete(nil) }
    }
}
struct AGYLocalDownloads: View {
    @State private var files: [URL] = []
    @State private var preview: PreviewDocument?
    @State private var issue: String?
    var body: some View {
        List {
            Text("文件 App → 我的 iPhone → AGY → 下载").font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).foregroundStyle(.red) }
            if files.isEmpty { Text("尚无本机下载").foregroundStyle(.secondary) }
            ForEach(files, id: \.self) { file in
                Button { preview = PreviewDocument(url: file) } label: { Label(file.lastPathComponent, systemImage: "doc") }
            }
        }.navigationTitle("本机已下载")
            .task { load() }.refreshable { load() }
            .sheet(item: $preview) { NativeDownloadedFile(url: $0.url) }
    }
    private func load() {
        do { files = try NativeLocalFileStore.list(); issue = nil }
        catch { issue = error.localizedDescription }
    }
}
private struct NativeQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
