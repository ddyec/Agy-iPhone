import SwiftUI
import UIKit

struct NativeMessageRow: View {
    let message: ChatMessage
    var streaming = false
    @State private var copied = false

    private var isUser: Bool { message.role == "user" }
    private var isGuidance: Bool { message.value["presentationKind"].string == "guidance" }
    private var isTool: Bool { message.role == "toolResult" }

    var body: some View {
        Group {
            if isUser {
                userBubble
            } else if isTool {
                toolCard
            } else {
                assistantCard
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 42)
            VStack(alignment: .leading, spacing: 8) {
                if isGuidance {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.right").font(.caption2.weight(.semibold))
                        Text("运行中补充引导")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(NativeTheme.accent)
                }
                NativeMessageMedia(message: message)
                ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in content(block) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isGuidance ? NativeTheme.guidanceBubble : NativeTheme.userBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isGuidance ? NativeTheme.accent.opacity(0.28) : NativeTheme.border, lineWidth: 0.5)
            )
        }
    }

    private var toolCard: some View {
        let failed = message.value["isError"].bool
        let running = ["ACTIVE", "RUNNING"].contains(message.value["toolState"].string)
        let brief = NativeConversationPresentation.toolBrief(message)
        return VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    NativeMessageMedia(message: message)
                    ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in content(block) }
                }.padding(.top, 6)
            } label: {
                HStack(spacing: 8) {
                    if running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: failed ? "exclamationmark.triangle.fill" : brief.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(failed ? .orange : NativeTheme.accent)
                            .frame(width: 16)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(brief.action)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(failed ? .orange : .primary)
                            if failed {
                                Text("失败")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        if !brief.detail.isEmpty {
                            Text(brief.detail)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 4)
                }
            }
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(failed ? Color.orange.opacity(0.45) : NativeTheme.border, lineWidth: 0.5))
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NativeAGYLogo(size: 18)
                Text("AGY")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                if streaming { ProgressView().controlSize(.mini) }
                Spacer()
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(copied ? .green : .secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制全文")

                    ShareLink(item: message.text) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分享消息")
                }
            }
            NativeMessageMedia(message: message)
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in content(block) }
            if !message.value["errorMessage"].string.isEmpty {
                NativeSelectableText(text: message.value["errorMessage"].string, style: .footnote, markdown: false, textColor: .systemRed)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
    }

    @ViewBuilder private func content(_ block: WireValue) -> some View {
        switch block["type"].string {
        case "text":
            NativeMarkdown(text: block["text"].string)
        case "thinking":
            DisclosureGroup("思考过程") {
                NativeMarkdown(text: block["thinking"].string, secondary: true)
                    .padding(.top, 4)
            }.font(.callout)
        case "toolCall":
            let brief = NativeConversationPresentation.toolBrief(name: block["name"].string.isEmpty ? block["toolName"].string : block["name"].string, parameters: block["arguments"])
            DisclosureGroup {
                NativeCodeBlock(language: "命令参数", code: block["rawInput"].string.isEmpty ? block["arguments"].pretty : block["rawInput"].string, collapsed: false)
                    .padding(.top, 4)
            } label: {
                Label(brief.combined, systemImage: brief.icon)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
            }.font(.callout)
        case "image":
            EmptyView() // Image blocks are visible above collapsed tool details.
        default:
            EmptyView()
        }
    }
}

struct NativeMarkdown: View {
    let text: String
    var secondary: Bool = false
    @AppStorage("nativeOutputMode") private var outputMode = NativeOutputMode.original.rawValue

    private enum Segment: Identifiable {
        case body(String)
        case heading(Int, String)
        case quote(String)
        case listItem(String, String)
        case divider

        var id: String {
            switch self {
            case .body(let s): return "b:" + s
            case .heading(let l, let s): return "h\(l):" + s
            case .quote(let s): return "q:" + s
            case .listItem(let b, let s): return "l:" + b + ":" + s
            case .divider: return "hr"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    if let svg = NativeMediaReferences.svg(value) {
                        let stripped = value.replacingOccurrences(of: svg, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !stripped.isEmpty { paragraphs(stripped) }
                        NativeMediaPreview(data: Data(svg.utf8))
                        NativeCodeBlock(language: "SVG 源码", code: svg, collapsed: true)
                    } else {
                        paragraphs(value)
                    }
                case .code(let language, let code):
                    if let svg = NativeMediaReferences.svg(code) { NativeMediaPreview(data: Data(svg.utf8)) }
                    NativeCodeBlock(language: language, code: code, collapsed: NativeMediaReferences.svg(code) != nil || outputMode != NativeOutputMode.original.rawValue)
                        .id(outputMode + language)
                case .table(let rows):
                    ScrollView(.horizontal) {
                        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { row, cells in
                                GridRow {
                                    ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                                        NativeSelectableText(text: cell, style: row == 0 ? .headline : .callout)
                                            .frame(width: tableWidth(rows, column: column), alignment: .leading)
                                            .padding(10)
                                            .background(row == 0 ? NativeTheme.accent.opacity(0.08) : Color(uiColor: .tertiarySystemFill))
                                            .overlay(Rectangle().stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 0.5))
                                    }
                                }
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).reservesHorizontalSwipe()
                }
            }
            NativeFileLinks(text: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableWidth(_ rows: [[String]], column: Int) -> CGFloat {
        let longest = rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        return CGFloat(min(240, max(110, longest * 10)))
    }

    private func parseSegments(_ value: String) -> [Segment] {
        var result: [Segment] = []
        var bodyLines: [String] = []
        var quoteLines: [String] = []

        func flushBody() {
            let joined = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { result.append(.body(joined)) }
            bodyLines.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            let joined = quoteLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { result.append(.quote(joined)) }
            quoteLines.removeAll(keepingCapacity: true)
        }

        for line in value.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushBody(); flushQuote()
                result.append(.divider)
            } else if line.hasPrefix("### ") {
                flushBody(); flushQuote()
                result.append(.heading(3, String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushBody(); flushQuote()
                result.append(.heading(2, String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushBody(); flushQuote()
                result.append(.heading(1, String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") || trimmed == ">" {
                flushBody()
                quoteLines.append(line.hasPrefix("> ") ? String(line.dropFirst(2)) : "")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushBody(); flushQuote()
                let content = String(trimmed.dropFirst(2))
                result.append(.listItem("•", content))
            } else if let dotRange = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                flushBody(); flushQuote()
                let marker = String(trimmed[..<dotRange.upperBound]).trimmingCharacters(in: .whitespaces)
                let content = String(trimmed[dotRange.upperBound...])
                result.append(.listItem(marker, content))
            } else {
                flushQuote()
                if trimmed.isEmpty {
                    flushBody()
                } else {
                    bodyLines.append(line)
                }
            }
        }
        flushBody(); flushQuote()
        return result
    }

    @ViewBuilder private func paragraphs(_ value: String) -> some View {
        let segments = parseSegments(value)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .heading(let level, let content):
                    NativeSelectableText(
                        text: content,
                        style: level == 1 ? .title2 : level == 2 ? .title3 : .headline,
                        textColor: secondary ? .secondaryLabel : nil
                    )
                    .padding(.top, 2)
                case .quote(let content):
                    HStack(alignment: .top, spacing: 10) {
                        Capsule()
                            .fill(NativeTheme.accent.opacity(0.7))
                            .frame(width: 3)
                        NativeSelectableText(text: content, style: .secondaryBody)
                    }
                    .padding(.vertical, 2)
                case .listItem(let marker, let content):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        NativeSelectableText(text: content, style: secondary ? .secondaryBody : .body)
                    }
                case .divider:
                    Divider().padding(.vertical, 4)
                case .body(let content):
                    NativeSelectableText(text: content, style: secondary ? .secondaryBody : .body)
                }
            }
        }
    }
}

struct NativeCodeBlock: View {
    let language: String
    let code: String
    let collapsed: Bool
    @State private var expanded = false
    @State private var wrap = true
    @State private var copied = false

    init(language: String, code: String, collapsed: Bool) {
        self.language = language
        self.code = code
        self.collapsed = collapsed
        _expanded = State(initialValue: !collapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                        Text(language.isEmpty ? "代码" : language)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { wrap.toggle() } label: {
                    Image(systemName: wrap ? "text.word.spacing" : "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(wrap ? "自动换行已开启，切换为横向滚动" : "开启自动换行")

                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(copied ? .green : NativeTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .quaternarySystemFill))

            if expanded {
                Divider().opacity(0.5)
                Group {
                    if wrap {
                        NativeSelectableText(text: code, style: .monospacedCallout, markdown: false, wraps: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal) {
                            NativeSelectableText(text: code, style: .monospacedCallout, markdown: false, wraps: false)
                        }.reservesHorizontalSwipe()
                    }
                }
                .padding(12)
            }
        }
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NativeTheme.border, lineWidth: 0.5))
    }
}
