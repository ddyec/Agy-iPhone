import Foundation

enum NativeMediaReferences {
    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "tiff"].contains(url.pathExtension.lowercased())
    }
    static func svgs(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<svg\b[^>]*>[\s\S]*?</svg>"#, options: .caseInsensitive) else { return [] }
        var found: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                let snippet = String(text[range])
                if !found.contains(snippet) { found.append(snippet) }
            }
        }
        return found
    }
    static func svg(_ text: String) -> String? {
        svgs(text).first
    }
    static func htmlDocument(language: String, code: String) -> String? {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 1_500_000 else { return nil }
        let lower = trimmed.lowercased()
        if lang == "html" || lang == "htm" {
            if lower.contains("<html") || lower.contains("<!doctype html") || lower.contains("<body") || lower.contains("<svg") || lower.contains("<canvas") || (lower.contains("<style") && lower.contains("<div")) {
                return trimmed
            }
        } else if lang.isEmpty && (lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html")) {
            return trimmed
        }
        return nil
    }
    static func paths(_ message: ChatMessage) -> [URL] {
        var paths: [URL] = []
        var fields = [message.value, message.value["details"]]
        for block in message.content where block["type"].string == "toolCall" { fields.append(block["arguments"]) }
        for field in fields {
            for key in ["Path", "path", "file_path", "filePath", "filename", "AbsolutePath", "TargetFile", "ImagePath"] {
                let raw = field[key].string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let candidate: URL?
                if raw.hasPrefix("/") {
                    candidate = URL(fileURLWithPath: raw)
                } else {
                    candidate = NativeDownloadLinks.url(raw) ?? URL(string: raw)
                }
                if let url = candidate, isImage(url), !paths.contains(url) {
                    paths.append(url)
                }
            }
        }
        return paths
    }
    static func writtenSVG(_ message: ChatMessage) -> [String] {
        var sources: [String] = []
        var fields = [message.value["details"]]
        for block in message.content where block["type"].string == "toolCall" { fields.append(block["arguments"]) }
        for field in fields {
            for key in ["Content", "content", "Replacement", "text"] {
                if let source = svg(field[key].string), !sources.contains(source) {
                    sources.append(source)
                }
            }
        }
        return sources
    }
}
