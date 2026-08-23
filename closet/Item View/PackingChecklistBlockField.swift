//
//  PackingChecklistBlockField.swift
//  closet
//
//  Single-line field with Notes-like Return / empty-Backspace for checklist blocks.
//

import SwiftUI
import UIKit

struct PackingChecklistBlockField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var font: UIFont
    var textColor: UIColor
    var strikethrough: Bool
    var onSubmit: () -> Void
    var onBackspaceWhenEmpty: () -> Void
    var onBecameFocused: () -> Void
    var onTextChanged: () -> Void
    var onDismissKeyboard: () -> Void

    private static func fontsEqual(_ a: UIFont?, _ b: UIFont) -> Bool {
        guard let a else { return false }
        return a.fontName == b.fontName && abs(a.pointSize - b.pointSize) < 0.01
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ChecklistKeyTextField {
        let field = ChecklistKeyTextField()
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.returnKeyType = .default
        field.autocorrectionType = .yes
        field.autocapitalizationType = .sentences
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.attachKeyboardAccessory(to: field)
        field.onBackspaceWhenEmpty = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBackspaceWhenEmpty()
        }
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.applyTypingAttributes(to: field)
        return field
    }

    func updateUIView(_ uiView: ChecklistKeyTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textField = uiView
        context.coordinator.attachKeyboardAccessory(to: uiView)
        uiView.onBackspaceWhenEmpty = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBackspaceWhenEmpty()
        }

        let styleChanged =
            !Self.fontsEqual(context.coordinator.lastFont, font)
            || !(context.coordinator.lastTextColor?.isEqual(textColor) ?? false)
            || context.coordinator.lastStrikethrough != strikethrough
        context.coordinator.lastFont = font
        context.coordinator.lastTextColor = textColor
        context.coordinator.lastStrikethrough = strikethrough

        let current = uiView.text ?? ""
        if current != text {
            // Text changed from SwiftUI — replace contents, preserve caret when possible.
            let selected = uiView.selectedTextRange
            context.coordinator.applyAttributedText(text, to: uiView)
            if let selected, uiView.isFirstResponder {
                uiView.selectedTextRange = selected
            }
        } else if styleChanged {
            let selected = uiView.selectedTextRange
            context.coordinator.applyAttributedText(current, to: uiView)
            if let selected, uiView.isFirstResponder {
                uiView.selectedTextRange = selected
            }
        } else {
            context.coordinator.applyTypingAttributes(to: uiView)
        }

        // Focus handoff: become first responder without resigning the previous field here.
        // Resigning in updateUIView during Return/Backspace handoff drops the keyboard.
        // Tap-outside clears focus via UIApplication.resignFirstResponder.
        if isFocused, !uiView.isFirstResponder {
            if uiView.window != nil {
                _ = uiView.becomeFirstResponder()
            } else {
                DispatchQueue.main.async {
                    guard context.coordinator.parent.isFocused, !uiView.isFirstResponder else { return }
                    _ = uiView.becomeFirstResponder()
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PackingChecklistBlockField
        weak var textField: UITextField?
        private var keyboardToolbar: UIToolbar?
        var lastFont: UIFont?
        var lastTextColor: UIColor?
        var lastStrikethrough: Bool?

        init(_ parent: PackingChecklistBlockField) {
            self.parent = parent
        }

        func attachKeyboardAccessory(to field: UITextField) {
            textField = field
            if keyboardToolbar == nil {
                keyboardToolbar = makeKeyboardAccessory()
            }
            if field.inputAccessoryView !== keyboardToolbar {
                field.inputAccessoryView = keyboardToolbar
            }
        }

        func makeKeyboardAccessory() -> UIToolbar {
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
            toolbar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let dismiss = UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain,
                target: self,
                action: #selector(dismissKeyboardTapped)
            )
            dismiss.accessibilityLabel = "Dismiss Keyboard"
            toolbar.items = [flex, dismiss]
            toolbar.layoutIfNeeded()
            return toolbar
        }

        @objc func dismissKeyboardTapped() {
            textField?.resignFirstResponder()
            parent.onDismissKeyboard()
        }

        func applyTypingAttributes(to field: UITextField) {
            field.typingAttributes = typingAttributes()
        }

        func applyAttributedText(_ string: String, to field: UITextField) {
            let attrs = typingAttributes()
            field.typingAttributes = attrs
            field.attributedText = NSAttributedString(string: string, attributes: attrs)
        }

        private func typingAttributes() -> [NSAttributedString.Key: Any] {
            [
                .font: parent.font,
                .foregroundColor: parent.textColor,
                .strikethroughStyle: parent.strikethrough ? NSUnderlineStyle.single.rawValue : 0
            ]
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            self.textField = textField
            parent.onBecameFocused()
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        @objc func editingChanged(_ textField: UITextField) {
            let value = textField.text ?? ""
            if parent.text != value {
                parent.text = value
                parent.onTextChanged()
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let value = textField.text ?? ""
            if parent.text != value {
                parent.text = value
                parent.onTextChanged()
            }
        }
    }
}

final class ChecklistKeyTextField: UITextField {
    var onBackspaceWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        let wasEmpty = (text ?? "").isEmpty
        super.deleteBackward()
        if wasEmpty {
            onBackspaceWhenEmpty?()
        }
    }
}
