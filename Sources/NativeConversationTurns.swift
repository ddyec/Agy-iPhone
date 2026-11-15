import SwiftUI

struct NativeConversationTurns: View {
    let turns: [NativeConversationTurn]
    let mode: NativeOutputMode
    var body: some View {
        ForEach(turns) { turn in NativeTurnTimeline(turn: turn, mode: mode) }
    }
}

private struct NativeTurnTimeline: View {
    let turn: NativeConversationTurn
    let mode: NativeOutputMode
    @State private var thinkingExpanded = false
    @State private var executionExpanded = false

    private var sections: [NativeProcessSection] {
        NativeConversationPresentation.sections(turn.process)
    }

    private var thinkingMessages: [ChatMessage] {
        sections.filter { $0.kind == .thinking }.flatMap(\.messages)
    }

    private var executionSections: [NativeProcessSection] {
        sections.filter { $0.kind != .thinking }
    }

    private var toolMessages: [ChatMessage] {
        executionSections.filter { $0.kind == .tools }.flatMap(\.messages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let user = turn.user {
                NativeMessageRow(message: user).id(user.id)
            }
            if turn.running {
                if mode != .conclusion {
                    runningProcess
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("AGY 正在思考与执行…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NativeTheme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(NativeTheme.border, lineWidth: 0.5))
            } else {
                settledProcess
            }
            if let final = turn.conclusion {
                NativeMessageRow(message: final).id(final.id)
            }
            if !turn.running, turn.conclusion == nil, !turn.process.isEmpty {
                Text("本轮未产生最终答复，可展开上方过程查看执行结果。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: turn.running) { _, running in
            if !running {
                thinkingExpanded = false
                executionExpanded = false
            }
        }
    }

    private var runningProcess: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections) { section in
                switch section.kind {
                case .guidance:
                    ForEach(section.messages) { message in
                        NativeMessageRow(message: message)
                    }
                case .thinking:
                    ForEach(section.messages) { message in
                        NativeThinkingCard(message: message)
                            .id(message.id + "-working")
                    }
                case .summary:
                    ForEach(section.messages) { message in
                        NativeSummaryCard(message: message)
                            .id(message.id + "-working")
                    }
                case .tools:
                    NativeToolGroup(section: section, defaultExpanded: true)
                        .id(section.id + "-working")
                }
            }
        }
    }

    @ViewBuilder private var settledProcess: some View {
        if !thinkingMessages.isEmpty || !executionSections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !thinkingMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { thinkingExpanded.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "brain")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.purple)
                                Text(thinkingExpanded ? "收起思考过程" : "思考过程")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.primary)
                                if !thinkingExpanded, let first = thinkingMessages.first {
                                    Text(firstLineExcerpt(first.text))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text("\(thinkingMessages.count) 段")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Image(systemName: thinkingExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(NativeTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        if thinkingExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(thinkingMessages) { message in
                                    NativeThinkingCard(message: message, initiallyExpanded: true)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                }

                if !executionSections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { executionExpanded.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NativeTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(executionExpanded ? "收起执行记录" : "执行操作")
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !toolMessages.isEmpty {
                                            Text("\(toolMessages.count) 项工具")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if !executionExpanded {
                                        Text(executionPreview)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: executionExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(NativeTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        if executionExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(executionSections) { section in
                                    switch section.kind {
                                    case .guidance:
                                        ForEach(section.messages) { message in
                                            NativeMessageRow(message: message)
                                        }
                                    case .summary:
                                        ForEach(section.messages) { message in
                                            NativeSummaryCard(message: message)
                                                .id(message.id + "-finished")
                                        }
                                    case .tools:
                                        NativeToolGroup(section: section, defaultExpanded: true)
                                            .id(section.id + "-finished")
                                    case .thinking:
                                        EmptyView()
                                    }
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    private var executionPreview: String {
        if !toolMessages.isEmpty {
            return NativeConversationPresentation.toolGroupPreview(toolMessages)
        }
        if let firstSummary = executionSections.first(where: { $0.kind == .summary })?.messages.first {
            return firstLineExcerpt(firstSummary.text)
        }
        return "查看完整执行步骤"
    }

    private func firstLineExcerpt(_ raw: String) -> String {
        let line = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# *>-")) }
            .first { !$0.isEmpty } ?? ""
        return line.count > 42 ? String(line.prefix(42)) + "…" : line
    }
}

private struct NativeToolGroup: View {
    let section: NativeProcessSection
    var defaultExpanded = false
    @State private var expanded: Bool
    private var active: Bool { section.messages.contains { ["ACTIVE", "RUNNING"].contains($0.value["toolState"].string) } }
    private var hasError: Bool { section.messages.contains { $0.value["isError"].bool } }

    init(section: NativeProcessSection, defaultExpanded: Bool = false) {
        self.section = section
        self.defaultExpanded = defaultExpanded
        _expanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if active {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: hasError ? "exclamationmark.triangle.fill" : "hammer.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(hasError ? .orange : NativeTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("执行步骤 · \(section.messages.count) 项")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(hasError ? .orange : .primary)
                        if !expanded {
                            Text(NativeConversationPresentation.toolGroupPreview(section.messages))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.messages) { message in
                        NativeToolActionRow(message: message)
                    }
                }
            }
        }
    }
}

private struct NativeToolActionRow: View {
    let message: ChatMessage
    @State private var showDetail = false

    private var brief: NativeToolBrief { NativeConversationPresentation.toolBrief(message) }
    private var failed: Bool { message.value["isError"].bool }
    private var active: Bool { ["ACTIVE", "RUNNING"].contains(message.value["toolState"].string) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { showDetail.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if active {
                        ProgressView().controlSize(.mini).frame(width: 16)
                    } else {
                        Image(systemName: failed ? "exclamationmark.triangle.fill" : brief.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(failed ? .orange : NativeTheme.accent)
                            .frame(width: 16)
                    }
                    Text(brief.action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(failed ? .orange : .primary)
                    if !brief.detail.isEmpty {
                        Text(brief.detail)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if failed {
                        Text("失败")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: showDetail ? "chevron.up" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NativeMessageMedia(message: message)

            if showDetail {
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                        if block["type"].string == "text" {
                            NativeMarkdown(text: block["text"].string, secondary: true)
                        } else if block["type"].string == "toolCall" {
                            NativeCodeBlock(
                                language: "参数",
                                code: block["rawInput"].string.isEmpty ? block["arguments"].pretty : block["rawInput"].string,
                                collapsed: false
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(failed ? Color.orange.opacity(0.45) : NativeTheme.border, lineWidth: 0.5))
    }
}

private struct NativeThinkingCard: View {
    let message: ChatMessage
    var initiallyExpanded = false
    @State private var expanded: Bool
    private var excerpt: String { NativeConversationPresentation.summaryExcerpt(message.text) }

    init(message: ChatMessage, initiallyExpanded: Bool = false) {
        self.message = message
        self.initiallyExpanded = initiallyExpanded
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("思考")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if excerpt != message.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Button(expanded ? "收起" : "展开") { expanded.toggle() }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(NativeTheme.accent)
                }
            }
            NativeMarkdown(text: expanded ? message.text : excerpt, secondary: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
    }
}

private struct NativeSummaryCard: View {
    let message: ChatMessage
    @State private var expanded = false
    private var excerpt: String { NativeConversationPresentation.summaryExcerpt(message.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.accent)
                Text("阶段进展")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if excerpt != message.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Button(expanded ? "收起" : "展开") { expanded.toggle() }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(NativeTheme.accent)
                }
            }
            NativeMarkdown(text: expanded ? message.text : excerpt, secondary: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
    }
}
