import Foundation

/// Phone labels never use the server's absolute path as display text.
enum AGYFilePresentation {
    static func label(scope: String, folder: String, name: String, directory: Bool) -> String {
        let relative = [folder, name].filter { !$0.isEmpty }.joined(separator: "/")
        let prefix = scope == "uploads" ? "上传/" : scope == "artifacts" ? "产物/" : ""
        return prefix + relative + (directory && !relative.hasSuffix("/") ? "/" : "")
    }
    static func opensMention(old: String, new: String) -> Bool {
        new.hasSuffix("@") && !old.hasSuffix("@")
    }
    static func modifiedText(_ timestamp: Double, calendar: Calendar = .current) -> String? {
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
    static func metadataLine(directory: Bool, size: Int64, modified: Double, calendar: Calendar = .current) -> String {
        let base = directory ? "文件夹" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        guard let mod = modifiedText(modified, calendar: calendar) else { return base }
        return "\(base) · \(mod)"
    }
}
