//
//  AutofocusTextField.swift
//  closet
//
//  Sheet-friendly text field: UIKit becomeFirstResponder avoids FocusState +
//  presentation gesture-gate delay (same approach as PriceAmountTextField).
//  Retries until the field is first responder so sheet open feels immediate.
//

import SwiftUI
import UIKit

struct AutofocusTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var borderStyle: UITextField.BorderStyle = .roundedRect
    var autocapitalizationType: UITextAutocapitalizationType = .words
    var autocorrectionType: UITextAutocorrectionType = .default
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var onSubmit: (() -> Void)? = nil

    private static let roundedFieldHeight: CGFloat = 36
    private static let plainFieldHeight: CGFloat = 22

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = IntrinsicHeightTextField(
            fixedHeight: borderStyle == .roundedRect ? Self.roundedFieldHeight : Self.plainFieldHeight
        )
        tf.placeholder = placeholder
        tf.borderStyle = borderStyle
        tf.keyboardType = keyboardType
        tf.autocorrectionType = autocorrectionType
        tf.autocapitalizationType = autocapitalizationType
        tf.textContentType = textContentType
        tf.font = .preferredFont(forTextStyle: .body)
        tf.returnKeyType = onSubmit == nil ? .default : .done
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.text = text
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.setContentCompressionResistancePriority(.required, for: .vertical)
        tf.onMovedToWindow = { [weak coordinator = context.coordinator, weak tf] in
            guard let coordinator, let tf else { return }
            coordinator.scheduleAutofocus(tf)
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if let intrinsic = uiView as? IntrinsicHeightTextField {
            intrinsic.fixedHeight = borderStyle == .roundedRect ? Self.roundedFieldHeight : Self.plainFieldHeight
            intrinsic.onMovedToWindow = { [weak coordinator = context.coordinator, weak uiView] in
                guard let coordinator, let uiView else { return }
                coordinator.scheduleAutofocus(uiView)
            }
        }
        uiView.placeholder = placeholder
        uiView.borderStyle = borderStyle
        uiView.keyboardType = keyboardType
        uiView.autocorrectionType = autocorrectionType
        uiView.autocapitalizationType = autocapitalizationType
        uiView.textContentType = textContentType
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.scheduleAutofocus(uiView)
    }

    private final class IntrinsicHeightTextField: UITextField {
        var fixedHeight: CGFloat
        var onMovedToWindow: (() -> Void)?

        init(fixedHeight: CGFloat) {
            self.fixedHeight = fixedHeight
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: fixedHeight)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                onMovedToWindow?()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AutofocusTextField
        private var didBecomeFirstResponder = false
        private var isSchedulingAutofocus = false

        init(_ parent: AutofocusTextField) {
            self.parent = parent
        }

        func scheduleAutofocus(_ textField: UITextField) {
            guard !didBecomeFirstResponder, !isSchedulingAutofocus else { return }
            isSchedulingAutofocus = true
            attemptAutofocus(textField, remainingAttempts: 24)
        }

        private func attemptAutofocus(_ textField: UITextField, remainingAttempts: Int) {
            if textField.isFirstResponder {
                didBecomeFirstResponder = true
                isSchedulingAutofocus = false
                return
            }
            guard remainingAttempts > 0 else {
                isSchedulingAutofocus = false
                return
            }
            guard textField.window != nil else {
                DispatchQueue.main.async { [weak self] in
                    self?.attemptAutofocus(textField, remainingAttempts: remainingAttempts - 1)
                }
                return
            }
            if textField.becomeFirstResponder() {
                didBecomeFirstResponder = true
                isSchedulingAutofocus = false
                return
            }
            // Sheet presentation gesture gate can reject the first focus attempt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.attemptAutofocus(textField, remainingAttempts: remainingAttempts - 1)
            }
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let onSubmit = parent.onSubmit {
                onSubmit()
                return true
            }
            return true
        }
    }
}
