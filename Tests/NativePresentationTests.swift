import Foundation

@main struct NativePresentationTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
        func message(_ id: String, _ role: String, _ text: String) -> ChatMessage {
            ChatMessage(id: id, value: .object(["role": .string(role), "content": .string(text)]))
        }
        let user = message("u", "user", "检查服务器")
        let plan = message("p", "assistant", "检查服务状态\n这里是详细过程")
        let call = ChatMessage(id: "call", value: try WireValue.parse(#"{"role":"assistant","content":[{"type":"toolCall","name":"bash","arguments":{"command":"very long command"}}]}"#))
        let result = message("r", "toolResult", "long output")
        let final = message("f", "assistant", "## 结论\n已修复。")
        let complete = [user, plan, call, result, final]
        let turns = NativeConversationPresentation.turns(complete, live: nil, running: false)
        check(NativeOutputMode.allCases.map(\.title) == ["原版", "思考与执行", "结论优先"], "All three modes remain available")
        check(turns.count == 1 && turns[0].user?.id == "u", "Group each user turn")
        check(turns[0].conclusion?.id == "f", "Trailing assistant answer is the conclusion")
        check(turns[0].process.map(\.id) == ["p", "call", "r"], "All process details remain available")
        check(NativeConversationPresentation.turns(complete, live: nil, running: true)[0].conclusion == nil, "Running answer remains folded until settled")
        let live = message("streaming", "assistant", "not final yet")
        check(NativeConversationPresentation.turns(Array(complete.dropLast()), live: live, running: true)[0].process.last?.id == "streaming", "Streaming deltas remain in process")
        check(NativeConversationPresentation.turns([user, plan, call, result], live: nil, running: false)[0].conclusion == nil, "Do not promote an earlier progress message after tool execution")
        let second = NativeConversationPresentation.turns(complete + [message("u2", "user", "next")], live: live, running: true)
        check(second.count == 2 && second[0].conclusion?.id == "f" && second[1].running, "Previous conclusions remain visible during next run")
        check(NativeConversationPresentation.step(call) == "执行命令", "Step label omits raw command")
        check(NativeConversationPresentation.step(plan) == "检查服务状态", "Step excerpt uses source text, no invented summary")
        check(NativeConversationPresentation.turns([], live: nil, running: false).isEmpty, "Empty transcript")
        func path(_ raw: String) -> String? { NativeFileRules.downloadPath(NativeDownloadLinks.url(raw)!, host: "agy.yectech.uk", cwd: "/workspace") }
        check(path("sandbox:/workspace/报告%20一.pdf") == "/workspace/报告 一.pdf", "Sandbox path: \(String(describing: path("sandbox:/workspace/报告%20一.pdf")))")
        check(path("https://agy.yectech.uk/workspace/report.zip") == "/workspace/report.zip", "Same-origin absolute artifact link")
        check(path("/api/files/download?path=%2Fworkspace%2Fa.zip") == "/workspace/a.zip", "Query-path download links")
        check(NativeFileRules.downloadPath(URL(string: "a.pdf")!, host: "agy.yectech.uk", cwd: "/") == "/a.pdf", "Relative file at root workspace")
        check(path("https://other.example/workspace/a.pdf") == nil, "External hosts never use authenticated Pi request")
        check(path("sandbox:/workspace/100%25.pdf") == "/workspace/100%.pdf", "Do not double-decode literal percent")
        let links = NativeDownloadLinks.files(in: "[报告](sandbox:/workspace/report.pdf)\n[包](output.zip)\n[来源](https://example.org/article)", cwd: "/workspace")
        check(links.count == 2, "Discover local artifacts, leave ordinary web links alone")
        check(NativeDownloadLinks.files(in: "```shell\nhttps://example.org/test.zip\n```", cwd: "/workspace").isEmpty, "Commands do not generate file actions")
        check(NativeDownloadLinks.files(in: "[包](https://example.org/a(1).zip)", cwd: "/workspace").count == 1, "Balanced parentheses in a file link")
        check(NativeDownloadLinks.files(in: "https://example.org/report.pdf", cwd: "").count == 1, "Bare external download URL")
        check(!NativeDownloadLinks.isExternalFile(URL(string: "https://user:pass@example.org/a.zip")!), "Reject userinfo in external link")
        check(!NativeDownloadLinks.isExternalFile(URL(string: "javascript:alert(1)")!), "Reject executable link scheme")
        let imageRead = ChatMessage(id: "image", value: try WireValue.parse(#"{"role":"toolResult","content":[{"type":"image","source":{"url":"sandbox:/workspace/p.png"}}]}"#))
        check(imageRead.content[0]["url"].string == "sandbox:/workspace/p.png", "Image source URL normalized")
        check(NativeMediaReferences.isImage(URL(string: "sandbox:/workspace/p.svg")!), "SVG is an inline image")
        check(NativeMediaReferences.svg("```svg\n<svg width=\"10\" height=\"10\"></svg>\n```") != nil, "SVG source extracted from code")
        let nextSummary = message("p2", "assistant", "验证通过，接下来整理结果")
        let sections = NativeConversationPresentation.sections([plan, call, result, nextSummary, message("r2", "toolResult", "output")])
        check(sections.map(\.kind) == [.summary, .tools, .summary, .tools], "Interleave summaries with consecutive tool groups")
        check(sections.map { $0.messages.count } == [1, 2, 1, 1], "Tools stay grouped until the next summary")
        let stoppedSummary = ChatMessage(id: "s", value: .object(["role": .string("assistant"), "presentationKind": .string("summary"), "content": .string("检查中")]))
        check(NativeConversationPresentation.turns([user, stoppedSummary], live: nil, running: false)[0].conclusion == nil, "A stopped summary never becomes a final answer")
        let response = AGYMessage(id: "a", role: "assistant", text: "最终答复", tools: [
            AGYTool(id: "1", name: "read", state: "DONE", parameters: .object([:]), output: "read"),
            AGYTool(id: "3", name: "write", state: "DONE", parameters: .object([:]), output: "written")], steps: [
                AGYResponseStep(index: 0, text: "先检查"), AGYResponseStep(index: 2, text: "再修改"),
                AGYResponseStep(index: 4, text: "最终答复")], finalText: "最终答复")
        let mapped = response.presented
        check(mapped.map(\.id) == ["a-step-0", "a-tool-1", "a-step-2", "a-tool-3", "a"], "Preserve AGY event order and avoid duplicate final summary")
        let completed = NativeConversationPresentation.turns([user] + mapped, live: nil, running: false)[0]
        check(completed.conclusion?.text == "最终答复" && completed.process.count == 4, "Final answer is outside the whole folded process")
        let active = NativeConversationPresentation.turns([user] + mapped, live: nil, running: true)[0]
        check(active.conclusion == nil && active.process.count == 5, "While running, keep all progress in execution order")
        let noResult = AGYMessage(id: "incomplete", role: "assistant", text: "先检查", tools: [AGYTool(id: "1", name: "read", state: "DONE", parameters: .object([:]), output: "output")], steps: [AGYResponseStep(index: 0, text: "先检查")], finalText: "")
        check(noResult.presented.map(\.id) == ["incomplete-step-0", "incomplete-tool-1"], "Explicit empty final does not reuse progress as the answer")
        let repeated = AGYMessage(id: "repeat", role: "assistant", text: "相同文字", tools: [AGYTool(id: "1", name: "read", state: "DONE", parameters: .object([:]), output: "output")], steps: [AGYResponseStep(index: 0, text: "相同文字")], finalText: "相同文字")
        check(repeated.presented.count == 3, "Preserve identical earlier summary when a tool separates it from the final")
        let thinking = AGYMessage(id: "thought", role: "assistant", text: "done", tools: [AGYTool(id: "1", name: "read", state: "DONE", parameters: .object([:]), output: "output")], steps: [AGYResponseStep(index: 0, text: "", thinking: "先核对依赖"), AGYResponseStep(index: 2, text: "done", thinking: "检查完毕")], finalText: "done")
        check(thinking.presented.map(\.id) == ["thought-thinking-0", "thought-tool-1", "thought-thinking-2", "thought"], "Preserve provider-supplied thinking between tools, including textless steps")
        check(NativeConversationPresentation.summaryExcerpt("第一段\n\n第二段") == "第一段…", "Summary excerpts use source text only")
        let guided = AGYMessage(id: "guided", role: "assistant", text: "完成", tools: [AGYTool(id: "1", name: "read", state: "DONE", parameters: .object([:]), output: "output")], steps: [AGYResponseStep(index: 0, text: "先检查")], finalText: "完成", guidance: [AGYGuidance(id: "guidance-1", index: 1, text: "注意兼容旧版本")])
        let guidedTurns = NativeConversationPresentation.turns([user]+guided.presented, live: nil, running: false)
        check(guidedTurns.count == 1 && guidedTurns[0].conclusion?.text == "完成", "Mid-turn guidance stays inside the same process and does not split the answer")
        check(NativeConversationPresentation.sections(guidedTurns[0].process).map(\.kind) == [.summary, .guidance, .tools], "Guidance is distinguishable from provider summaries")
        print("Passed \(checks) conversation presentation and download link checks")
    }
}
