//
//  ProfileSerifTypography.swift
//  closet
//

import SwiftUI
import UIKit

private struct UsesProfileSerifTypographyKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SelectionTitleFontDesignKey: EnvironmentKey {
    static let defaultValue: Font.Design = .default
}

extension EnvironmentValues {
    /// When true, other-user profile chrome prefers serif text (including filter/sort bars).
    var usesProfileSerifTypography: Bool {
        get { self[UsesProfileSerifTypographyKey.self] }
        set { self[UsesProfileSerifTypographyKey.self] = newValue }
    }

    /// Font design for `SelectionHeader` titles (e.g. Wardrobes sheet).
    var selectionTitleFontDesign: Font.Design {
        get { self[SelectionTitleFontDesignKey.self] }
        set { self[SelectionTitleFontDesignKey.self] = newValue }
    }
}

extension View {
    /// Serif typography for other-user Profile (SwiftUI text + segmented picker titles).
    func profileSerifTypography() -> some View {
        self
            .environment(\.usesProfileSerifTypography, true)
            .environment(\.font, Font.system(.body, design: .serif))
            .environment(\.selectionTitleFontDesign, .serif)
    }
}

struct OtherUserProfileSerifModifier: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.profileSerifTypography()
        } else {
            content
        }
    }
}

extension Font {
    static func profileSerif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

/// Finds the nearest `UISegmentedControl` and applies a serif title font.
struct SerifSegmentedPickerConfigurer: UIViewRepresentable {
    var pointSize: CGFloat = 13

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.pointSize = pointSize
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        uiView.pointSize = pointSize
        uiView.applySerifIfNeeded()
    }

    final class BridgeView: UIView {
        var pointSize: CGFloat = 13

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applySerifIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applySerifIfNeeded()
        }

        func applySerifIfNeeded() {
            guard let segmented = nearestSegmentedControl() else { return }
            let base = UIFont.systemFont(ofSize: pointSize, weight: .regular)
            let font = base.fontDescriptor.withDesign(.serif)
                .map { UIFont(descriptor: $0, size: pointSize) }
                ?? base
            segmented.setTitleTextAttributes([.font: font], for: .normal)
            segmented.setTitleTextAttributes([.font: font], for: .selected)
        }

        private func nearestSegmentedControl() -> UISegmentedControl? {
            var node: UIView? = superview
            while let current = node {
                if let segmented = current as? UISegmentedControl {
                    return segmented
                }
                if let segmented = current.findSubview(ofType: UISegmentedControl.self) {
                    return segmented
                }
                node = current.superview
            }
            return nil
        }
    }
}

private extension UIView {
    func findSubview<T: UIView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let nested = subview.findSubview(ofType: type) { return nested }
        }
        return nil
    }
}
