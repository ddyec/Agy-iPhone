import SwiftUI
import UIKit
import ImageIO
import WebKit
import SwiftDraw

private struct NativeMediaRunningKey: EnvironmentKey { static let defaultValue = false }
private struct NativeMediaAPIKey: EnvironmentKey { static let defaultValue: AGYAPI? = nil }
extension EnvironmentValues {
    var nativeMediaRunning: Bool {
        get { self[NativeMediaRunningKey.self] }
        set { self[NativeMediaRunningKey.self] = newValue }
    }
    var nativeMediaAPI: AGYAPI? {
        get { self[NativeMediaAPIKey.self] }
        set { self[NativeMediaAPIKey.self] = newValue }
    }
}

@MainActor struct NativeMediaPreview: View {
    var data: Data? = nil
    var url: URL? = nil
    var svgMarkup: String? = nil

    @Environment(\.nativeMediaAPI) private var api
    @Environment(\.nativeWorkspace) private var cwd
    @Environment(\.nativeSessionID) private var sessionID
    @Environment(\.nativeMediaRunning) private var running
    @Environment(\.openURL) private var openURL

    @State private var image: UIImage?
    @State private var resolvedSVG: String?
    @State private var loading = false
    @State private var failed = false
    @State private var fullScreen = false

    private var key: String {
        if let svgMarkup { return "svg:" + String(svgMarkup.hashValue) }
        return url?.absoluteString ?? String(data?.hashValue ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Button { fullScreen = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 280, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(NativeTheme.border, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("点击全屏查看图片")
            } else if let resolvedSVG {
                VStack(alignment: .leading, spacing: 6) {
                    NativeSandboxedWebPreview(markup: resolvedSVG, isSVG: true, interactive: false)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(NativeTheme.border, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { fullScreen = true }

                    Button { fullScreen = true } label: {
                        Label("全屏缩放查看 SVG", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NativeTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            } else if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在载入预览…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if failed {
                Label("预览暂不可用，可下载原文件查看", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let url {
                Button { openURL(url) } label: {
                    Label("保存或分享 " + url.lastPathComponent, systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: key + (running ? "-running" : "-settled")) { await load() }
        .fullScreenCover(isPresented: $fullScreen) {
            if let image {
                NativeFullScreenImageViewer(image: image) { fullScreen = false }
            } else if let resolvedSVG {
                NativeFullScreenWebViewer(title: "SVG 矢量预览", markup: resolvedSVG, isSVG: true) { fullScreen = false }
            }
        }
    }

    private func load() async {
        if let svgMarkup {
            let bytes = Data(svgMarkup.utf8)
            resolvedSVG = svgMarkup
            if let svg = NativeSVGDocument.parse(bytes) {
                let raster = svg.rasterize(scale: 2)
                image = (raster.size.width > 0 && raster.size.height > 0) ? raster : nil
            } else {
                image = nil
            }
            failed = false
            return
        }

        loading = true; failed = false
        defer { loading = false }
        do {
            var bytes = data
            if let url, let api {
                let file: URL
                if let path = NativeFileRules.downloadPath(url, host: api.credentials.url.host ?? "", cwd: cwd) {
                    file = try await api.download(path, sessionID: sessionID)
                } else {
                    file = try await api.downloadExternal(url)
                }
                let values = try file.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= 25 * 1024 * 1024 else { throw AttachmentImportError.tooLarge }
                bytes = try Data(contentsOf: file)
            }
            guard let bytes, bytes.count <= 25 * 1024 * 1024 else { throw AttachmentImportError.unreadable }

            if let rawText = String(data: bytes, encoding: .utf8), let extractedSVG = NativeMediaReferences.svg(rawText) {
                resolvedSVG = extractedSVG
                if let svg = NativeSVGDocument.parse(Data(extractedSVG.utf8)) {
                    let raster = svg.rasterize(scale: 2)
                    image = (raster.size.width > 0 && raster.size.height > 0) ? raster : nil
                } else {
                    image = nil
                }
                failed = false
                return
            }

            let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                if let svg = NativeSVGDocument.parse(bytes) { return svg.rasterize(scale: 2) }
                guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 2400
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            try Task.checkCancellation()
            image = rendered
            failed = rendered == nil
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

/// Native iOS full-screen photo viewer with fit-to-screen initial layout,
/// pinch-to-zoom (1x–5x), double-tap zoom toggle, and share/save controls.
struct NativeFullScreenImageViewer: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            NativeZoomableImageView(image: image, onSingleTap: onClose)
                .ignoresSafeArea()

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("关闭图片预览")

                Spacer()

                ShareLink(item: Image(uiImage: image), preview: SharePreview("图片", image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("分享或保存图片")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }
}

private struct NativeZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onSingleTap: onSingleTap) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView(image: image)
        scroll.delegate = context.coordinator
        context.coordinator.imageView = scroll.imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        return scroll
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if uiView.imageView.image !== image {
            uiView.updateImage(image)
        }
    }

    final class ZoomScrollView: UIScrollView {
        let imageView = UIImageView()
        private var lastBoundsSize: CGSize = .zero

        init(image: UIImage) {
            super.init(frame: .zero)
            backgroundColor = .clear
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            minimumZoomScale = 1.0
            maximumZoomScale = 5.0
            bouncesZoom = true
            contentInsetAdjustmentBehavior = .never

            imageView.image = image
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
        }

        required init?(coder: NSCoder) { fatalError() }

        func updateImage(_ newImage: UIImage) {
            zoomScale = 1.0
            imageView.image = newImage
            lastBoundsSize = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0, let img = imageView.image, img.size.width > 0, img.size.height > 0 else { return }
            if bounds.size != lastBoundsSize {
                lastBoundsSize = bounds.size
                zoomScale = 1.0
                let widthRatio = bounds.width / img.size.width
                let heightRatio = bounds.height / img.size.height
                let fitScale = min(widthRatio, heightRatio)
                let fittedWidth = img.size.width * fitScale
                let fittedHeight = img.size.height * fitScale
                imageView.frame = CGRect(x: 0, y: 0, width: fittedWidth, height: fittedHeight)
                contentSize = CGSize(width: fittedWidth, height: fittedHeight)
            }
            centerContent()
        }

        func centerContent() {
            let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
            let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
            contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: (() -> Void)?

        init(onSingleTap: (() -> Void)?) { self.onSingleTap = onSingleTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = recognizer.view as? ZoomScrollView else { return }
            if scroll.zoomScale > 1.05 {
                scroll.setZoomScale(1.0, animated: true)
            } else {
                let point = recognizer.location(in: scroll.imageView)
                let targetScale: CGFloat = 2.6
                let width = scroll.bounds.width / targetScale
                let height = scroll.bounds.height / targetScale
                let rect = CGRect(x: point.x - width * 0.5, y: point.y - height * 0.5, width: width, height: height)
                scroll.zoom(to: rect, animated: true)
            }
        }

        @objc func handleSingleTap() {
            onSingleTap?()
        }
    }
}

/// Offline CSP-locked WKWebView for rendering SVG and self-contained HTML
/// snippets directly inside chat cards or in full-screen zoom mode.
struct NativeSandboxedWebPreview: UIViewRepresentable {
    let markup: String
    var isSVG: Bool = false
    var interactive: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.dataDetectorTypes = []
        config.defaultWebpagePreferences.allowsContentJavaScript = !isSVG && interactive

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = interactive
        webView.scrollView.bounces = interactive
        webView.isUserInteractionEnabled = interactive
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let key = "\(isSVG):\(interactive):\(markup.hashValue)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        webView.loadHTMLString(wrappedHTML(), baseURL: URL(string: "about:blank"))
    }

    private func wrappedHTML() -> String {
        let csp = isSVG
            ? "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:;"
            : "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:;"

        if isSVG {
            return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes">
            <meta http-equiv="Content-Security-Policy" content="\(csp)">
            <style>
            html, body { margin: 0; padding: 12px; width: 100%; height: 100%; box-sizing: border-box; display: flex; align-items: center; justify-content: center; background: #ffffff; overflow: \(interactive ? "auto" : "hidden"); }
            svg { max-width: 100%; max-height: 100%; width: auto; height: auto; display: block; }
            </style>
            </head>
            <body>\(markup)</body>
            </html>
            """
        }

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <style>
        html, body { margin: 0; padding: 12px; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #ffffff; color: #1c1c1e; }
        </style>
        </head>
        <body>\(markup)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedKey: String?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.request.url?.scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

struct NativeFullScreenWebViewer: View {
    let title: String
    let markup: String
    var isSVG: Bool = false
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            NativeSandboxedWebPreview(markup: markup, isSVG: isSVG, interactive: true)
                .background(Color.white)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", action: onClose)
                    }
                }
        }
    }
}
