import SwiftUI
import UIKit

/// Read-only UITextView bridge that provides native iOS word/range selection
/// handles instead of SwiftUI's whole-paragraph context-menu highlight.
struct NativeSelectableText: UIViewRepresentable {
    enum Style: Equatable {
        case body, secondaryBody, callout, footnote, caption, monospacedCallout, monospacedCaption, headline, title3, title2

        var baseFont: UIFont {
            switch self {
            case .body, .secondaryBody:
                return UIFont.preferredFont(forTextStyle: .body)
            case .callout:
                return UIFont.preferredFont(forTextStyle: .callout)
            case .footnote:
                return UIFont.preferredFont(forTextStyle: .footnote)
            case .caption:
                return UIFont.preferredFont(forTextStyle: .caption1)
            case .monospacedCallout:
                let size = UIFont.preferredFont(forTextStyle: .callout).pointSize
                let base = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
                return UIFontMetrics(forTextStyle: .callout).scaledFont(for: base)
            case .monospacedCaption:
                let size = UIFont.preferredFont(forTextStyle: .caption1).pointSize
                let base = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
                return UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
            case .headline:
                return UIFont.preferredFont(forTextStyle: .headline)
            case .title3:
                let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold)
                return desc.map { UIFont(descriptor: $0, size: 0) } ?? UIFont.preferredFont(forTextStyle: .title3)
            case .title2:
                let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2).withSymbolicTraits(.traitBold)
                return desc.map { UIFont(descriptor: $0, size: 0) } ?? UIFont.preferredFont(forTextStyle: .title2)
            }
        }
    }

    let text: String
    var style: Style = .body
    var markdown: Bool = true
    var wraps: Bool = true
    var textColor: UIColor? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory

    func makeCoordinator() -> Coordinator { Coordinator(openURL: openURL) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.tintColor = UIColor(NativeTheme.accent)
        view.linkTextAttributes = [
            .foregroundColor: UIColor(NativeTheme.accent),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.openURL = openURL
        let key = RenderKey(text: text, style: style, markdown: markdown, wraps: wraps, scheme: colorScheme, sizeCategory: sizeCategory, hasCustomColor: textColor != nil)
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        view.textContainer.widthTracksTextView = wraps
        if !wraps {
            view.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        view.attributedText = buildAttributedText()
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        if !wraps {
            let measured = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: ceil(measured.width), height: ceil(measured.height))
        }
        let fallbackWidth = UIScreen.main.bounds.width - 64
        let proposedWidth = proposal.width ?? fallbackWidth
        guard proposedWidth.isFinite, proposedWidth > 0 else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: proposedWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: proposedWidth, height: ceil(measured.height))
    }

    private func buildAttributedText() -> NSAttributedString {
        let baseFont = style.baseFont
        let resolvedColor = textColor ?? (style == .secondaryBody ? .secondaryLabel : .label)
        let paragraph = NSMutableParagraphStyle()
        switch style {
        case .monospacedCallout, .monospacedCaption:
            paragraph.lineSpacing = 2
        case .title2, .title3, .headline:
            paragraph.lineSpacing = 2
        default:
            paragraph.lineSpacing = 3
        }

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: resolvedColor,
            .paragraphStyle: paragraph
        ]

        guard markdown, !text.isEmpty,
              let parsed = try? AttributedString(markdown: NativeDownloadLinks.normalizedMarkdown(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: text, attributes: baseAttributes)
        }

        let result = NSMutableAttributedString(string: String(parsed.characters), attributes: baseAttributes)
        for run in parsed.runs {
            let nsRange = NSRange(run.range, in: parsed)
            guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    let monoBase = UIFont.monospacedSystemFont(ofSize: max(12, baseFont.pointSize * 0.92), weight: intent.contains(.stronglyEmphasized) ? .semibold : .regular)
                    font = monoBase
                    result.addAttribute(.backgroundColor, value: UIColor.tertiarySystemFill, range: nsRange)
                } else {
                    var traits = font.fontDescriptor.symbolicTraits
                    if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                    if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                    if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
                        font = UIFont(descriptor: desc, size: font.pointSize)
                    }
                }
                if intent.contains(.strikethrough) {
                    result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                }
            }
            result.addAttribute(.font, value: font, range: nsRange)
            if let link = run.link {
                result.addAttribute(.link, value: link, range: nsRange)
            }
        }
        return result
    }

    fileprivate struct RenderKey: Equatable {
        let text: String
        let style: Style
        let markdown: Bool
        let wraps: Bool
        let scheme: ColorScheme
        let sizeCategory: ContentSizeCategory
        let hasCustomColor: Bool
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction
        fileprivate var lastKey: RenderKey?

        init(openURL: OpenURLAction) { self.openURL = openURL }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [openURL] _ in openURL(url) }
            }
            return defaultAction
        }
    }
}
