import SwiftUI

struct NativeConversationTurns: View {
    let turns: [NativeConversationTurn]
    let mode: NativeOutputMode
    var body: some View {
        ForEach(turns) { turn in NativeTurnTimeline(turn: turn) }
    }
}
private struct NativeTurnTimeline: View {
    let turn: NativeConversationTurn
    @State private var processExpanded = false
    var body: some View {
        if let user = turn.user { NativeMessageRow(message: user).id(user.id) }
        VStack(alignment: .leading, spacing: 14) {
            if turn.running {
                process
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在处理…").font(.callout).foregroundStyle(.secondary)
                }
            } else if !turn.process.isEmpty {
                DisclosureGroup(isExpanded: $processExpanded) { process } label: {
                    Text("查看思考与执行过程").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let final = turn.conclusion { NativeMessageRow(message: final).id(final.id) }
            if !turn.running, turn.conclusion == nil, !turn.process.isEmpty {
                Text("本轮未产生最终答复，可展开过程查看执行结果。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: turn.running) { _, running in
            if !running { processExpanded = false }
        }
    }
    private var process: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(NativeConversationPresentation.sections(turn.process)) { section in
                if section.kind == .summary {
                    ForEach(section.messages) { message in
                        NativeSummaryCard(message: message)
                            .id(message.id + (turn.running ? "-working" : "-finished"))
                    }
                } else {
                    NativeToolGroup(section: section)
                        // Reset expanded tool details at completion, once, without
                        // tying identity or scroll position to token/revision counts.
                        .id(section.id + (turn.running ? "-working" : "-finished"))
                }
            }
        }
    }
}
private struct NativeToolGroup: View {
    let section: NativeProcessSection
    @State private var expanded = false
    private var active: Bool { section.messages.contains { ["ACTIVE", "RUNNING"].contains($0.value["toolState"].string) } }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(section.messages) { message in NativeMessageRow(message: message) }
        } label: {
            HStack(spacing: 8) {
                if active { ProgressView().controlSize(.mini) }
                Text("工具调用 · \(section.messages.count) 项")
                Spacer()
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NativeSummaryCard: View {
    let message: ChatMessage
    @State private var expanded = false
    private var excerpt: String { NativeConversationPresentation.summaryExcerpt(message.text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("思考摘要").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            NativeMarkdown(text: expanded ? message.text : excerpt)
            if excerpt != message.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                Button(expanded ? "收起摘要" : "展开摘要") { expanded.toggle() }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
