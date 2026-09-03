import SwiftUI
import UIKit

/// UIKit-backed single-line field. SwiftUI `TextField` often drops hardware /
/// preview keystrokes (letters never appear even when the field looks focused).
/// `UITextField` as first responder receives them.
struct KeyboardTextField: View {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var returnKeyType: UIReturnKeyType = .default
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var autocorrection: UITextAutocorrectionType = .no
    var font: UIFont = .systemFont(ofSize: 16, weight: .semibold)
    var textColor: Color = Theme.ink
    var placeholderColor: Color = Theme.inkFaint
    var tint: Color = Theme.ember
    var keyboardAppearance: UIKeyboardAppearance = .default
    var textAlignment: NSTextAlignment = .natural
    var onSubmit: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    var body: some View {
        Representable(
            placeholder: placeholder,
            text: $text,
            isSecure: isSecure,
            keyboardType: keyboardType,
            textContentType: textContentType,
            returnKeyType: returnKeyType,
            autocapitalization: autocapitalization,
            autocorrection: autocorrection,
            font: font,
            textColor: UIColor(textColor),
            placeholderColor: UIColor(placeholderColor),
            tint: UIColor(tint),
            keyboardAppearance: keyboardAppearance,
            textAlignment: textAlignment,
            onSubmit: onSubmit,
            onFocusChange: onFocusChange
        )
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
    }
}

/// UIKit-backed multiline field. Same reason as `KeyboardTextField`.
struct KeyboardTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = .systemFont(ofSize: 16, weight: .regular)
    var textColor: Color = Theme.ink
    var placeholderColor: Color = Theme.inkFaint
    var tint: Color = Theme.ember
    var keyboardAppearance: UIKeyboardAppearance = .default
    var minHeight: CGFloat = 88
    var onFocusChange: ((Bool) -> Void)? = nil

    var body: some View {
        EditorRepresentable(
            text: $text,
            placeholder: placeholder,
            font: font,
            textColor: UIColor(textColor),
            placeholderColor: UIColor(placeholderColor),
            tint: UIColor(tint),
            keyboardAppearance: keyboardAppearance,
            onFocusChange: onFocusChange
        )
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

// MARK: - UITextField

private struct Representable: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool
    var keyboardType: UIKeyboardType
    var textContentType: UITextContentType?
    var returnKeyType: UIReturnKeyType
    var autocapitalization: UITextAutocapitalizationType
    var autocorrection: UITextAutocorrectionType
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var tint: UIColor
    var keyboardAppearance: UIKeyboardAppearance
    var textAlignment: NSTextAlignment
    var onSubmit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HostView {
        let host = HostView()
        host.textField.delegate = context.coordinator
        host.textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        context.coordinator.host = host
        return host
    }

    func updateUIView(_ host: HostView, context: Context) {
        let field = host.textField
        context.coordinator.parent = self
        context.coordinator.host = host

        // Push external changes (mic, clear) without fighting in-flight typing.
        if field.text != text {
            field.text = text
        }
        if field.isSecureTextEntry != isSecure {
            field.isSecureTextEntry = isSecure
        }
        field.keyboardType = keyboardType
        field.textContentType = textContentType
        field.returnKeyType = returnKeyType
        field.autocapitalizationType = autocapitalization
        field.autocorrectionType = autocorrection
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.font = font
        field.textColor = textColor
        field.tintColor = tint
        field.keyboardAppearance = keyboardAppearance
        field.textAlignment = textAlignment
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: font,
            ]
        )
        // Never resign here — that is what kills the keyboard on re-render.
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: Representable?
        weak var host: HostView?

        @objc func editingChanged(_ sender: UITextField) {
            parent?.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent?.onFocusChange?(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent?.onFocusChange?(false)
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent?.onSubmit?()
            if parent?.onSubmit == nil {
                textField.resignFirstResponder()
            }
            return true
        }
    }

    final class HostView: UIView {
        let textField = UITextField()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = true
            backgroundColor = .clear

            textField.borderStyle = .none
            textField.backgroundColor = .clear
            textField.clearButtonMode = .never
            textField.adjustsFontForContentSizeCategory = true
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: trailingAnchor),
                textField.topAnchor.constraint(equalTo: topAnchor),
                textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: 28)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard bounds.contains(point), !isHidden, alpha > 0.01, isUserInteractionEnabled else {
                return nil
            }
            return textField
        }
    }
}

// MARK: - UITextView

private struct EditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var tint: UIColor
    var keyboardAppearance: UIKeyboardAppearance
    var onFocusChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> EditorHost {
        let host = EditorHost()
        host.textView.delegate = context.coordinator
        context.coordinator.host = host
        return host
    }

    func updateUIView(_ host: EditorHost, context: Context) {
        context.coordinator.parent = self
        context.coordinator.host = host
        let view = host.textView
        if view.text != text {
            view.text = text
        }
        view.font = font
        view.textColor = textColor
        view.tintColor = tint
        view.keyboardAppearance = keyboardAppearance
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        host.placeholderLabel.text = placeholder
        host.placeholderLabel.font = font
        host.placeholderLabel.textColor = placeholderColor
        host.placeholderLabel.isHidden = !text.isEmpty || placeholder.isEmpty
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorRepresentable?
        weak var host: EditorHost?

        func textViewDidChange(_ textView: UITextView) {
            parent?.text = textView.text ?? ""
            host?.placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
                || (parent?.placeholder.isEmpty ?? true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent?.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent?.onFocusChange?(false)
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            true
        }
    }

    final class EditorHost: UIView {
        let textView = UITextView()
        let placeholderLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = true
            backgroundColor = .clear

            textView.backgroundColor = .clear
            textView.isScrollEnabled = true
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.adjustsFontForContentSizeCategory = true
            textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            placeholderLabel.numberOfLines = 0
            placeholderLabel.isUserInteractionEnabled = false

            addSubview(textView)
            addSubview(placeholderLabel)
            textView.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard bounds.contains(point), !isHidden, alpha > 0.01, isUserInteractionEnabled else {
                return nil
            }
            return textView
        }
    }
}
