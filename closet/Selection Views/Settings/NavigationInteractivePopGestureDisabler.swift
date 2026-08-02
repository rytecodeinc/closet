//
//  NavigationInteractivePopGestureDisabler.swift
//  closet
//

import SwiftUI
import UIKit

/// Disables the UINavigationController interactive pop gesture while hosted.
/// Re-enables it on disappear so sibling screens keep swipe-back.
struct NavigationInteractivePopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.setPopGestureEnabled(false)
    }

    final class Controller: UIViewController {
        private weak var navigation: UINavigationController?
        private var wasEnabled: Bool?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setPopGestureEnabled(false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restorePopGesture()
        }

        func setPopGestureEnabled(_ enabled: Bool) {
            guard let nav = navigationController else { return }
            navigation = nav
            if wasEnabled == nil {
                wasEnabled = nav.interactivePopGestureRecognizer?.isEnabled
            }
            nav.interactivePopGestureRecognizer?.isEnabled = enabled
        }

        private func restorePopGesture() {
            guard let nav = navigation ?? navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = wasEnabled ?? true
            wasEnabled = nil
        }
    }
}

extension View {
    /// Prefer the custom Back control (with discard confirmation) over edge-swipe pop.
    func disableInteractivePopGesture() -> some View {
        background(NavigationInteractivePopGestureDisabler())
    }
}
