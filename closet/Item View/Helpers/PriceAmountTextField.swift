//
//  PriceAmountTextField.swift
//  closet
//
//  Decimal-pad price field with reliable sheet autofocus
//  (UIKit becomeFirstResponder avoids FocusState + presentation gesture-gate delay).
//

import SwiftUI
import UIKit

struct PriceAmountTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Enter price"
    var onEditingEnded: (() -> Void)?

    /// Matches `RoundedBorderTextFieldStyle` / the adjacent currency control height.
    private static let fieldHeight: CGFloat = 36

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = IntrinsicHeightTextField()
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.keyboardType = .decimalPad
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.font = .preferredFont(forTextStyle: .body)
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.text = text
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.setContentCompressionResistancePriority(.required, for: .vertical)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.placeholder = placeholder
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.requestAutofocusIfNeeded(uiView)
    }

    private final class IntrinsicHeightTextField: UITextField {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: PriceAmountTextField.fieldHeight)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PriceAmountTextField
        private var didRequestAutofocus = false

        init(_ parent: PriceAmountTextField) {
            self.parent = parent
        }

        func requestAutofocusIfNeeded(_ textField: UITextField) {
            guard !didRequestAutofocus, textField.window != nil else { return }
            didRequestAutofocus = true
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
            }
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingEnded?()
            if textField.text != parent.text {
                textField.text = parent.text
            }
        }
    }
}
