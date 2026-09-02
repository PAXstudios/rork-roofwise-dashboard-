import SwiftUI
import UIKit

/// UIKit-backed login field. SwiftUI `TextField` inside a ScrollView/GeometryReader
/// often fails to present the keyboard on device; `UITextField` does not.
struct LoginKeyboardField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool
    var keyboardType: UIKeyboardType
    var textContentType: UITextContentType?
    var returnKeyType: UIReturnKeyType
    var isFocused: Bool
    var onFocus: () -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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

        if field.text != text {
            field.text = text
        }
        if field.isSecureTextEntry != isSecure {
            field.isSecureTextEntry = isSecure
        }
        field.keyboardType = keyboardType
        field.textContentType = textContentType
        field.returnKeyType = returnKeyType
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.45),
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            ]
        )

        if isFocused {
            if !field.isFirstResponder {
                DispatchQueue.main.async {
                    guard field.window != nil, !field.isFirstResponder else { return }
                    field.becomeFirstResponder()
                }
            }
        } else if field.isFirstResponder {
            DispatchQueue.main.async {
                guard !self.isFocused, field.isFirstResponder else { return }
                field.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LoginKeyboardField?
        weak var host: HostView?

        @objc func editingChanged(_ sender: UITextField) {
            parent?.text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent?.onFocus()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent?.onSubmit()
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
            textField.font = .systemFont(ofSize: 16, weight: .medium)
            textField.textColor = .white
            textField.tintColor = UIColor(red: 0.961, green: 0.518, blue: 0.149, alpha: 1)
            textField.keyboardAppearance = .dark
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.spellCheckingType = .no
            textField.smartDashesType = .no
            textField.smartQuotesType = .no
            textField.smartInsertDeleteType = .no
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

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: 44)
        }

        /// Any tap in the row (including padding around the glyph) focuses the field.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard bounds.contains(point), !isHidden, alpha > 0.01, isUserInteractionEnabled else {
                return nil
            }
            return textField
        }
    }
}
