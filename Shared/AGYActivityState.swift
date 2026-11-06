import Foundation

struct AGYActivityState: Codable, Hashable {
    var phase: String
    var title: String
    var detail: String
    var updatedAt: Date
    var elapsed: Int
    var finished: Bool { ["done", "failed", "stopped"].contains(phase) }
    var label: String {
        switch phase {
        case "review": return "等待审批"
        case "done": return "已完成"
        case "failed": return "任务出错"
        case "stopped": return "任务已停止"
        case "paused": return "待同步"
        default: return "正在工作"
        }
    }
    var symbol: String {
        switch phase {
        case "review": return "hand.raised.fill"
        case "done": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.circle.fill"
        case "stopped": return "stop.circle.fill"
        case "paused": return "arrow.clockwise"
        default: return "ellipsis"
        }
    }
}
enum AGYActivityPolicy {
    static func excerpt(_ text: String, limit: Int = 120) -> String {
        String(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ").prefix(limit))
    }
    static func state(running: Bool, approvalCount: Int, error: String, title: String,
                      progress: String, previews: Bool, startedAt: Date, now: Date) -> AGYActivityState {
        let phase = running ? (approvalCount > 0 ? "review" : "running") : error.isEmpty ? "done" : error.contains("停止") ? "stopped" : "failed"
        return AGYActivityState(phase: phase, title: previews ? excerpt(title, limit: 64) : "AGY 任务",
                                detail: phase == "review" ? "打开 AGY 查看并审批" : previews ? excerpt(progress) : "点按返回会话",
                                updatedAt: now, elapsed: max(0, Int(now.timeIntervalSince(startedAt))))
    }
    static func link(session: String, scope: String) -> URL? {
        guard UUID(uuidString: session) != nil, !scope.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "agy"; components.host = "session"; components.path = "/" + session
        components.queryItems = [URLQueryItem(name: "scope", value: scope)]
        return components.url
    }
    static func session(from url: URL, scope: String) -> String? {
        guard url.scheme == "agy", url.host == "session", url.user == nil, url.password == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.filter({ $0.name == "scope" }).count == 1,
              parts.queryItems?.first(where: { $0.name == "scope" })?.value == scope else { return nil }
        let id = String(url.path.dropFirst())
        return UUID(uuidString: id) != nil ? id : nil
    }
}
