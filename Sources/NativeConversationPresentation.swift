import Foundation

enum NativeOutputMode: String, CaseIterable, Identifiable {
    case original, steps, conclusion
    var id: String { rawValue }
    var title: String {
        switch self { case .original: return "原版"; case .steps: return "思考与执行"; case .conclusion: return "结论优先" }
    }
}

struct NativeConversationTurn: Identifiable {
    let id: String
    var user: ChatMessage?
    var process: [ChatMessage]
    var conclusion: ChatMessage?
    var running: Bool
}

struct NativeToolBrief: Equatable {
    let action: String
    let detail: String
    let icon: String

    var combined: String {
        detail.isEmpty ? action : "\(action) · \(detail)"
    }
}

enum NativeConversationPresentation {
    static func turns(_ messages: [ChatMessage], live: ChatMessage?, running: Bool) -> [NativeConversationTurn] {
        var all = messages
        if let live { all.append(live) }
        var groups: [[ChatMessage]] = []
        for message in all {
            if groups.isEmpty || (message.role == "user" && message.value["presentationKind"].string != "guidance") { groups.append([]) }
            groups[groups.count - 1].append(message)
        }
        return groups.enumerated().map { index, group in
            let active = running && index == groups.count - 1
            let user = group.first?.role == "user" ? group.first : nil
            var process = user == nil ? group : Array(group.dropFirst())
            var finalMessage: ChatMessage?
            // Only the trailing assistant response after all tool results can be
            // final. Do not promote an earlier progress message or running text.
            if !active, let last = process.last, last.role == "assistant",
               !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !["summary", "thinking"].contains(last.value["presentationKind"].string),
               !last.content.contains(where: { $0["type"].string == "toolCall" }) {
                finalMessage = process.removeLast()
            }
            return NativeConversationTurn(id: group.first!.id, user: user, process: process, conclusion: finalMessage, running: active)
        }
    }

    static func step(_ message: ChatMessage) -> String {
        if message.value["isError"].bool || !message.value["errorMessage"].string.isEmpty { return "执行失败 · 展开查看详情" }
        if message.role == "toolResult" {
            return toolBrief(message).combined
        }
        if message.role == "bashExecution" {
            let cmd = compactCommand(message.value["command"].string)
            return cmd.isEmpty ? "执行命令" : "执行命令 · \(cmd)"
        }
        if let call = message.content.first(where: { $0["type"].string == "toolCall" }) {
            let name = call["name"].string.isEmpty ? "调用工具" : call["name"].string
            if message.text.isEmpty {
                return toolBrief(name: name, parameters: call["arguments"]).combined
            }
        }
        let text = message.text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("```") })
        if let text { return String(text.trimmingCharacters(in: CharacterSet(charactersIn: "# *>-")).prefix(120)) }
        return message.content.contains(where: { $0["type"].string == "thinking" }) || message.value["presentationKind"].string == "thinking" ? "思考过程" : "处理步骤"
    }

    static func toolBrief(_ message: ChatMessage) -> NativeToolBrief {
        if let call = message.content.first(where: { $0["type"].string == "toolCall" }) {
            let name = call["name"].string.isEmpty ? call["toolName"].string : call["name"].string
            return toolBrief(name: name, parameters: call["arguments"])
        }
        return toolBrief(name: message.value["toolName"].string, parameters: message.value["details"])
    }

    static func toolBrief(name rawName: String, parameters: WireValue) -> NativeToolBrief {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionLabels: [String: (String, String)] = [
            "read": ("读取", "doc.text"),
            "read_file": ("读取", "doc.text"),
            "view_file": ("读取", "doc.text"),
            "write": ("写入", "square.and.pencil"),
            "write_file": ("写入", "square.and.pencil"),
            "write_to_file": ("写入", "square.and.pencil"),
            "edit": ("修改", "pencil.line"),
            "edit_file": ("修改", "pencil.line"),
            "replace_file_content": ("修改", "pencil.line"),
            "multi_replace_file_content": ("修改", "pencil.line"),
            "bash": ("命令", "terminal"),
            "run_command": ("命令", "terminal"),
            "grep": ("搜索内容", "doc.text.magnifyingglass"),
            "grep_search": ("搜索内容", "doc.text.magnifyingglass"),
            "find": ("查找文件", "folder.badge.questionmark"),
            "find_by_name": ("查找文件", "folder.badge.questionmark"),
            "list_dir": ("浏览目录", "folder"),
            "search_web": ("网页搜索", "globe"),
            "read_url_content": ("读取网页", "globe"),
            "invoke_subagent": ("子智能体", "person.2"),
            "define_subagent": ("定义子智能体", "person.badge.plus"),
            "manage_subagents": ("管理子智能体", "person.2"),
            "send_message": ("发送协作消息", "paperplane"),
            "manage_task": ("后台任务", "clock.arrow.circlepath"),
            "schedule": ("定时任务", "timer"),
            "ask_question": ("向你提问", "questionmark.bubble"),
            "run_workflow": ("运行工作流", "flowchart"),
            "swarm": ("协作编队", "person.3")
        ]
        let (action, icon) = actionLabels[name] ?? (name.isEmpty ? "工具执行" : name, "wrench.and.screwdriver")

        if let summary = firstNonEmpty(parameters, keys: ["toolSummary", "Description"]), name == "run_command" || name == "run_workflow" {
            if name == "run_command", let cmd = firstNonEmpty(parameters, keys: ["CommandLine", "command"]) {
                let shortCmd = compactCommand(cmd, limit: 38)
                return NativeToolBrief(action: action, detail: shortCmd.isEmpty ? truncate(summary, 52) : "\(truncate(summary, 28)) (\(shortCmd))", icon: icon)
            }
            return NativeToolBrief(action: action, detail: truncate(summary, 56), icon: icon)
        }

        if let path = firstNonEmpty(parameters, keys: ["Path", "TargetFile", "AbsolutePath", "path", "file_path", "DirectoryPath", "SearchPath", "Cwd"]) {
            let short = compactPath(path)
            if let start = positiveInt(parameters["StartLine"]), let end = positiveInt(parameters["EndLine"]) {
                return NativeToolBrief(action: action, detail: "\(short) #L\(start)-\(end)", icon: icon)
            } else if let start = positiveInt(parameters["StartLine"]) {
                return NativeToolBrief(action: action, detail: "\(short) #L\(start)+", icon: icon)
            }
            return NativeToolBrief(action: action, detail: short, icon: icon)
        }

        if let cmd = firstNonEmpty(parameters, keys: ["CommandLine", "command", "cmd"]) {
            return NativeToolBrief(action: action, detail: compactCommand(cmd), icon: icon)
        }

        if let query = firstNonEmpty(parameters, keys: ["query", "Query", "Pattern", "pattern"]) {
            return NativeToolBrief(action: action, detail: truncate(query, 54), icon: icon)
        }

        if let url = firstNonEmpty(parameters, keys: ["Url", "url"]) {
            return NativeToolBrief(action: action, detail: truncate(url, 54), icon: icon)
        }

        if let role = firstNonEmpty(parameters, keys: ["Role", "TypeName", "Name"]) {
            return NativeToolBrief(action: action, detail: truncate(role, 48), icon: icon)
        }

        if let taskAction = firstNonEmpty(parameters, keys: ["Action", "action"]) {
            let tid = firstNonEmpty(parameters, keys: ["TaskId", "name"]) ?? ""
            return NativeToolBrief(action: action, detail: tid.isEmpty ? taskAction : "\(taskAction) · \(truncate(tid, 28))", icon: icon)
        }

        return NativeToolBrief(action: action, detail: "", icon: icon)
    }

    private static func firstNonEmpty(_ value: WireValue, keys: [String]) -> String? {
        for key in keys {
            let text = value[key].string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func positiveInt(_ value: WireValue) -> Int? {
        let n = value.int
        return n > 0 ? n : nil
    }

    private static func compactPath(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        if normalized == "/" { return "/" }
        let parts = normalized.split(separator: "/").map(String.init)
        guard let last = parts.last else { return truncate(normalized, 48) }
        if parts.count >= 2 {
            let parent = parts[parts.count - 2]
            if ![".agy-uploads", "workspace", "ubuntu", "home", "Users"].contains(parent) {
                return truncate("\(parent)/\(last)", 52)
            }
        }
        return truncate(last, 48)
    }

    private static func compactCommand(_ raw: String, limit: Int = 56) -> String {
        var line = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
        if line.hasPrefix("cd "), let range = line.range(of: "&&") {
            let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { line = rest }
        }
        line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return truncate(line, limit)
    }

    private static func truncate(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

struct NativeProcessSection: Identifiable {
    enum Kind: Equatable { case thinking, summary, tools, guidance }
    let id: String
    let kind: Kind
    var messages: [ChatMessage]
}

extension NativeConversationPresentation {
    static func summaryExcerpt(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraph = normalized.components(separatedBy: "\n\n").first ?? normalized
        let excerpt = String(paragraph.prefix(320))
        return excerpt.count < normalized.count ? excerpt + "…" : excerpt
    }

    static func toolGroupPreview(_ messages: [ChatMessage]) -> String {
        var seen: [String] = []
        for message in messages {
            let brief = toolBrief(message)
            let item = brief.detail.isEmpty ? brief.action : "\(brief.action) \(brief.detail)"
            if !item.isEmpty, !seen.contains(item) {
                seen.append(item)
            }
            if seen.count >= 2 { break }
        }
        if seen.isEmpty { return "共 \(messages.count) 项操作" }
        let suffix = messages.count > seen.count ? " 等 \(messages.count) 项" : ""
        return seen.joined(separator: " · ") + suffix
    }

    static func sections(_ process: [ChatMessage]) -> [NativeProcessSection] {
        var result: [NativeProcessSection] = []
        for message in process {
            let kindKey = message.value["presentationKind"].string
            if kindKey == "guidance" {
                result.append(NativeProcessSection(id: message.id, kind: .guidance, messages: [message]))
                continue
            }
            if kindKey == "thinking" {
                result.append(NativeProcessSection(id: message.id, kind: .thinking, messages: [message]))
                continue
            }
            let tool = message.role == "toolResult" || message.role == "bashExecution" || message.content.contains { $0["type"].string == "toolCall" }
            if tool, result.last?.kind == .tools {
                result[result.count - 1].messages.append(message)
            } else {
                result.append(NativeProcessSection(id: message.id, kind: tool ? .tools : .summary, messages: [message]))
            }
        }
        return result
    }
}
