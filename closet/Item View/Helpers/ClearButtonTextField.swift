//
//  ClearButtonTextField.swift
//  closet
//
//  UITextField with system clear button (clearButtonMode) for SwiftUI.
//

import SwiftUI
import UIKit

struct ClearButtonTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.clearButtonMode = .whileEditing
        tf.autocorrectionType = .default
        tf.autocapitalizationType = .words
        tf.returnKeyType = .done
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.text = text
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.placeholder = placeholder
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ClearButtonTextField

        init(_ parent: ClearButtonTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
            parent.onTextChange?()
        }

        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            parent.text = ""
            parent.onTextChange?()
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
