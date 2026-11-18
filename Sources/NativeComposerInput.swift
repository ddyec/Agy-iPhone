import SwiftUI
import UIKit

/// Isolated observable state for the composer input so typing and handwriting
/// never trigger `AGYStore.objectWillChange` or re-render the chat transcript.
@MainActor final class AGYComposerState: ObservableObject {
    @Published var text: String = ""
    @Published var hasUncommittedText: Bool = false
    private let mountedViews = NSHashTable<UITextView>.weakObjects()
    weak var lastFocusedView: UITextView?
    var isApplyingProgrammaticText = false

    func register(_ view: UITextView) {
        if !mountedViews.contains(view) {
            mountedViews.add(view)
        }
    }

    var activeTextView: UITextView? {
        let views = mountedViews.allObjects
        return views.first(where: { $0.isFirstResponder })
            ?? (lastFocusedView?.window != nil ? lastFocusedView : nil)
            ?? views.first(where: { $0.window != nil })
    }

    var hasContent: Bool {
        hasUncommittedText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func flushActiveInput() {
        guard let tv = activeTextView else { return }
        isApplyingProgrammaticText = true
        defer { isApplyingProgrammaticText = false }
        if tv.markedTextRange != nil {
            tv.unmarkText()
        }
        let latest = tv.text ?? ""
        if text != latest {
            text = latest
        }
        if hasUncommittedText {
            hasUncommittedText = false
        }
        for other in mountedViews.allObjects where other !== tv && other.text != latest {
            UIView.performWithoutAnimation {
                other.text = latest
                let length = (latest as NSString).length
                other.selectedRange = NSRange(location: latest.isEmpty ? 0 : length, length: 0)
                if let composerView = other as? NativeComposerInput.ComposerTextView {
                    composerView.refreshPlaceholderVisibility()
                    composerView.refreshScrollState(maxLines: 6)
                }
                other.invalidateIntrinsicContentSize()
            }
        }
    }

    func setText(_ newValue: String, maxLines: Int = 6) {
        isApplyingProgrammaticText = true
        defer { isApplyingProgrammaticText = false }
        for tv in mountedViews.allObjects {
            if tv.markedTextRange != nil {
                tv.unmarkText()
            }
            if tv.text != newValue {
                UIView.performWithoutAnimation {
                    tv.text = newValue
                    let length = (newValue as NSString).length
                    tv.selectedRange = NSRange(location: newValue.isEmpty ? 0 : length, length: 0)
                    if let composerView = tv as? NativeComposerInput.ComposerTextView {
                        composerView.refreshPlaceholderVisibility()
                        composerView.refreshScrollState(maxLines: maxLines)
                    }
                    tv.invalidateIntrinsicContentSize()
                }
            } else if let composerView = tv as? NativeComposerInput.ComposerTextView {
                composerView.refreshPlaceholderVisibility()
            }
        }
        if hasUncommittedText {
            hasUncommittedText = false
        }
        if text != newValue {
            text = newValue
        }
    }

    func clear() {
        setText("")
    }

    func dismissKeyboard() {
        for tv in mountedViews.allObjects where tv.isFirstResponder {
            tv.resignFirstResponder()
        }
    }
}

/// Native UIKit composer input that preserves active IME/handwriting marked text
/// (`markedTextRange`), avoids cursor jumping, and eliminates per-stroke SwiftUI
/// re-layout of the conversation transcript.
struct NativeComposerInput: UIViewRepresentable {
    @ObservedObject var state: AGYComposerState
    @Binding var focused: Bool
    var placeholder: String = "发送消息…"
    var maxLines: Int = 6
    var onMentionTyped: (() -> Void)? = nil
    var onTextChanged: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.tintColor = UIColor(NativeTheme.accent)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.keyboardDismissMode = .interactive
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.text = state.text
        view.configurePlaceholder(placeholder)
        view.refreshPlaceholderVisibility()
        state.register(view)
        return view
    }

    func updateUIView(_ uiView: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        state.register(uiView)
        uiView.updatePlaceholderText(placeholder)

        // Never overwrite UITextView while Chinese handwriting / Pinyin IME has
        // uncommitted marked text, otherwise strokes lag or the cursor jumps.
        if uiView.markedTextRange == nil && uiView.text != state.text {
            context.coordinator.isProgrammaticUpdate = true
            let previousRange = uiView.selectedRange
            UIView.performWithoutAnimation {
                uiView.text = state.text
                let length = (state.text as NSString).length
                if state.text.isEmpty {
                    uiView.selectedRange = NSRange(location: 0, length: 0)
                } else if !uiView.isFirstResponder {
                    uiView.selectedRange = NSRange(location: length, length: 0)
                } else {
                    let clamped = min(previousRange.location, length)
                    uiView.selectedRange = NSRange(location: clamped, length: 0)
                }
                uiView.refreshPlaceholderVisibility()
                uiView.refreshScrollState(maxLines: maxLines)
                uiView.invalidateIntrinsicContentSize()
            }
            context.coordinator.isProgrammaticUpdate = false
        } else {
            uiView.refreshPlaceholderVisibility()
        }

        if !focused && uiView.isFirstResponder {
            DispatchQueue.main.async {
                if !context.coordinator.parent.focused && uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
            }
        } else if focused && !uiView.isFirstResponder && uiView.window != nil {
            DispatchQueue.main.async {
                if context.coordinator.parent.focused && !uiView.isFirstResponder && uiView.window != nil {
                    uiView.becomeFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? max(160, UIScreen.main.bounds.width - 120)
        guard width.isFinite, width > 0 else { return nil }
        let lineHeight = (uiView.font ?? UIFont.preferredFont(forTextStyle: .body)).lineHeight
        let verticalInset = uiView.textContainerInset.top + uiView.textContainerInset.bottom
        let minHeight = ceil(lineHeight + verticalInset)
        let maxHeight = ceil(lineHeight * CGFloat(maxLines) + verticalInset)
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let clampedHeight = min(max(fitting.height, minHeight), maxHeight)
        let shouldScroll = fitting.height > maxHeight + 1
        if uiView.isScrollEnabled != shouldScroll {
            DispatchQueue.main.async {
                uiView.isScrollEnabled = shouldScroll
            }
        }
        return CGSize(width: width, height: ceil(clampedHeight))
    }

    final class ComposerTextView: UITextView {
        private let placeholderLabel = UILabel()

        func configurePlaceholder(_ value: String) {
            placeholderLabel.text = value
            placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
            placeholderLabel.adjustsFontForContentSizeCategory = true
            placeholderLabel.textColor = .placeholderText
            placeholderLabel.isUserInteractionEnabled = false
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
            ])
            refreshPlaceholderVisibility()
        }

        func updatePlaceholderText(_ value: String) {
            if placeholderLabel.text != value {
                placeholderLabel.text = value
            }
        }

        func refreshPlaceholderVisibility() {
            placeholderLabel.isHidden = !text.isEmpty || markedTextRange != nil
        }

        func refreshScrollState(maxLines: Int) {
            let width = bounds.width > 0 ? bounds.width : max(160, UIScreen.main.bounds.width - 120)
            let lineHeight = (font ?? UIFont.preferredFont(forTextStyle: .body)).lineHeight
            let maxHeight = ceil(lineHeight * CGFloat(maxLines) + textContainerInset.top + textContainerInset.bottom)
            let fitting = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            isScrollEnabled = fitting.height > maxHeight + 1
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeComposerInput
        var isProgrammaticUpdate = false

        init(parent: NativeComposerInput) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.state.register(textView)
            parent.state.lastFocusedView = textView
            if !parent.focused {
                parent.focused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused {
                parent.focused = false
            }
            guard !isProgrammaticUpdate && !parent.state.isApplyingProgrammaticText else { return }
            guard textView === parent.state.lastFocusedView || textView.window != nil else { return }
            let latest = textView.text ?? ""
            if parent.state.hasUncommittedText {
                parent.state.hasUncommittedText = false
            }
            if parent.state.text != latest {
                parent.state.text = latest
                parent.onTextChanged?()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let composerView = textView as? ComposerTextView else { return }
            composerView.refreshPlaceholderVisibility()
            composerView.refreshScrollState(maxLines: parent.maxLines)
            composerView.invalidateIntrinsicContentSize()

            guard !isProgrammaticUpdate && !parent.state.isApplyingProgrammaticText else { return }

            // Wait until handwriting/IME composition commits before syncing full
            // text back to SwiftUI state so stroke recognition stays completely fluid.
            if textView.markedTextRange != nil {
                let nonWhitespace = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if parent.state.hasUncommittedText != nonWhitespace {
                    parent.state.hasUncommittedText = nonWhitespace
                }
                return
            }

            if parent.state.hasUncommittedText {
                parent.state.hasUncommittedText = false
            }

            let updated = textView.text ?? ""
            let previous = parent.state.text
            if previous != updated {
                parent.state.text = updated
                parent.onTextChanged?()
                if AGYFilePresentation.opensMention(old: previous, new: updated) {
                    parent.onMentionTyped?()
                }
            }
        }
    }
}
