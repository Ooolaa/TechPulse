import SwiftUI
import UIKit

/// Word-level text selection. SwiftUI's `.textSelection(.enabled)` only
/// selects the entire Text block; UITextView gives native iOS selection —
/// long-press a single word, drag the handles, Look Up / Search Web.
///
/// Adds an **Explain** item to the selection menu, so a confusing word can be
/// looked up against the reader's own knowledge map rather than the system
/// dictionary. `onExplain` receives the selection and a window of surrounding
/// prose for disambiguation.
struct SelectableText: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 15
    var lineSpacing: CGFloat = 6
    var textColor: UIColor = UIColor(Theme.textBody)
    var onExplain: ((String, String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // No dataDetectorTypes: article bodies are attacker-controlled RSS
        // content, so auto-linking them turns hostile feed text into tappable
        // links. The canonical URL is already a toolbar button.
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        view.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableText

        init(parent: SelectableText) {
            self.parent = parent
        }

        /// Prepend "Explain" to the system selection menu, but only when the
        /// selection actually looks like a term — no point offering it for a
        /// dragged paragraph.
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let full = textView.text,
                  let swiftRange = Range(range, in: full) else { return nil }

            let raw = String(full[swiftRange])
            guard let term = WordSelection.normalize(raw) else { return nil }
            let excerpt = WordSelection.context(in: full, around: swiftRange)

            let explain = UIAction(title: "Explain", image: UIImage(systemName: "sparkles")) {
                [weak self] _ in
                self?.parent.onExplain?(term, excerpt)
                textView.selectedTextRange = nil        // dismiss the selection
            }
            return UIMenu(children: [explain] + suggestedActions)
        }
    }
}
