//
//  NavigationBarHairlineHidden.swift
//  closet
//
//  Hides the navigation bar bottom hairline / shadow for a specific screen.
//

import SwiftUI
import UIKit

struct NavigationBarHairlineHidden: ViewModifier {
    var backgroundColor: UIColor = UIColor.systemBackground

    func body(content: Content) -> some View {
        content.background(NavigationBarHairlineHider(backgroundColor: backgroundColor))
    }
}

extension View {
    /// Hides the navigation bar bottom hairline for this screen.
    func hidesNavigationBarHairline(backgroundColor: UIColor = UIColor.systemBackground) -> some View {
        modifier(NavigationBarHairlineHidden(backgroundColor: backgroundColor))
    }
}

private struct NavigationBarHairlineHider: UIViewControllerRepresentable {
    let backgroundColor: UIColor

    func makeUIViewController(context: Context) -> Controller {
        Controller(backgroundColor: backgroundColor)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.backgroundColor = backgroundColor
        uiViewController.scheduleApplyAppearance()
    }

    final class Controller: UIViewController {
        var backgroundColor: UIColor
        private var applyWorkItem: DispatchWorkItem?

        init(backgroundColor: UIColor) {
            self.backgroundColor = backgroundColor
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyAppearance()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleApplyAppearance()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAppearance()
        }

        func scheduleApplyAppearance() {
            applyWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applyAppearance()
            }
            applyWorkItem = work
            // SwiftUI may re-apply toolbar chrome after first layout.
            DispatchQueue.main.async(execute: work)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        func applyAppearance() {
            guard let navBar = resolvedNavigationBar() else { return }

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = backgroundColor
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            appearance.backgroundEffect = nil

            navBar.standardAppearance = appearance
            navBar.scrollEdgeAppearance = appearance
            navBar.compactAppearance = appearance
            navBar.compactScrollEdgeAppearance = appearance
            navBar.isTranslucent = false

            // Legacy 1pt hairline image views SwiftUI sometimes still inserts.
            hideLegacyHairline(in: navBar)
            if let superview = navBar.superview {
                hideLegacyHairline(in: superview)
            }
        }

        private func resolvedNavigationBar() -> UINavigationBar? {
            if let navBar = navigationController?.navigationBar {
                return navBar
            }

            var node: UIView? = view.superview
            while let current = node {
                if let navBar = current as? UINavigationBar {
                    return navBar
                }
                if let bar = current.subviews.compactMap({ $0 as? UINavigationBar }).first {
                    return bar
                }
                if let host = current.next as? UIViewController,
                   let navBar = host.navigationController?.navigationBar {
                    return navBar
                }
                node = current.superview
            }

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows where window.isKeyWindow || window == view.window {
                    if let navBar = findNavigationBar(in: window) {
                        return navBar
                    }
                }
            }
            return nil
        }

        private func findNavigationBar(in root: UIView) -> UINavigationBar? {
            if let navBar = root as? UINavigationBar { return navBar }
            for subview in root.subviews {
                if let found = findNavigationBar(in: subview) { return found }
            }
            return nil
        }

        private func hideLegacyHairline(in root: UIView) {
            for subview in root.subviews {
                if let imageView = subview as? UIImageView,
                   imageView.bounds.height <= 1.0 || imageView.frame.height <= 1.0 {
                    imageView.isHidden = true
                    imageView.alpha = 0
                }
                // `_UIBarBackground` shadow / separator layers
                if String(describing: type(of: subview)).contains("BarBackground") {
                    for nested in subview.subviews {
                        if nested.bounds.height <= 1.0 || nested.frame.height <= 1.0 {
                            nested.isHidden = true
                            nested.alpha = 0
                        }
                    }
                }
                hideLegacyHairline(in: subview)
            }
        }
    }
}
