//
//  AnimatedGIFView.swift
//  closet
//
//  Bundle GIF playback (e.g. AuthView intro). Set `shouldAnimate` to start playback.
//

import ImageIO
import SwiftUI
import UIKit

struct AnimatedGIFView: UIViewRepresentable {
    let name: String
    /// Width ÷ height of the GIF asset (e.g. 675÷1200 for RedressAuthView.gif).
    var aspectRatio: CGFloat = 675.0 / 1200.0
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    /// When false, shows the first frame only. Toggle to true to start playback.
    var shouldAnimate: Bool = false
    /// `0` = loop forever; `1` = play once (UIImageView semantics).
    var animationRepeatCount: Int = 1

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        Self.layoutSize(for: aspectRatio, proposal: proposal)
    }

    /// Sizes the representable from the width/height SwiftUI proposes (no artificial cap).
    static func layoutSize(for aspectRatio: CGFloat, proposal: ProposedViewSize) -> CGSize? {
        guard aspectRatio > 0 else { return nil }

        if let width = proposal.width, width > 0, width.isFinite {
            var height = width / aspectRatio
            if let cap = proposal.height, cap > 0, cap.isFinite, height > cap {
                height = cap
                let fittedWidth = height * aspectRatio
                return CGSize(width: fittedWidth, height: height)
            }
            return CGSize(width: width, height: height)
        }

        if let height = proposal.height, height > 0, height.isFinite {
            let width = height * aspectRatio
            return CGSize(width: width, height: height)
        }

        return nil
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.configure(
            imageView: imageView,
            name: name,
            contentMode: contentMode,
            reduceMotion: reduceMotion,
            shouldAnimate: shouldAnimate,
            animationRepeatCount: animationRepeatCount
        )
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.configure(
            imageView: uiView,
            name: name,
            contentMode: contentMode,
            reduceMotion: reduceMotion,
            shouldAnimate: shouldAnimate,
            animationRepeatCount: animationRepeatCount
        )
    }

    final class Coordinator {
        private var loadedName: String?
        private var loadedFrames: GIFrames?
        private var lastShouldAnimate = false
        private var lastReduceMotion = false
        private var lastRepeatCount = 1

        func configure(
            imageView: UIImageView,
            name: String,
            contentMode: UIView.ContentMode,
            reduceMotion: Bool,
            shouldAnimate: Bool,
            animationRepeatCount: Int
        ) {
            imageView.contentMode = contentMode

            if loadedName != name {
                loadedName = name
                loadedFrames = Self.loadFrames(named: name)
                lastShouldAnimate = false
                showFirstFrame(on: imageView)
            }

            guard let frames = loadedFrames, !frames.images.isEmpty else {
                imageView.image = nil
                return
            }

            let animateTriggered = shouldAnimate && !lastShouldAnimate
            lastReduceMotion = reduceMotion
            lastRepeatCount = animationRepeatCount

            if reduceMotion {
                stopAnimation(on: imageView)
                imageView.image = frames.images[0]
                lastShouldAnimate = shouldAnimate
                return
            }

            if !shouldAnimate {
                stopAnimation(on: imageView)
                showFirstFrame(on: imageView, frames: frames)
                lastShouldAnimate = false
                return
            }

            guard animateTriggered else { return }

            lastShouldAnimate = true
            startAnimation(
                on: imageView,
                frames: frames,
                repeatCount: animationRepeatCount
            )
        }

        private func showFirstFrame(on imageView: UIImageView, frames: GIFrames? = nil) {
            let frames = frames ?? loadedFrames
            imageView.image = frames?.images.first
            imageView.animationImages = nil
            imageView.animationDuration = 0
            imageView.stopAnimating()
        }

        private func stopAnimation(on imageView: UIImageView) {
            imageView.stopAnimating()
            imageView.animationImages = nil
            imageView.animationDuration = 0
        }

        private func startAnimation(
            on imageView: UIImageView,
            frames: GIFrames,
            repeatCount: Int
        ) {
            guard frames.images.count > 1 else {
                imageView.image = frames.images[0]
                return
            }

            // Resting `image` is the last frame so UIKit does not snap back to frame 0 when animation ends.
            imageView.image = frames.images.last
            imageView.animationImages = frames.images
            imageView.animationDuration = frames.duration
            imageView.animationRepeatCount = repeatCount
            imageView.startAnimating()
        }

        private struct GIFrames {
            let images: [UIImage]
            let duration: TimeInterval
        }

        private static func loadFrames(named name: String) -> GIFrames? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }

            let count = CGImageSourceGetCount(source)
            guard count > 0 else { return nil }

            var images: [UIImage] = []
            var totalDuration: TimeInterval = 0

            for index in 0 ..< count {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                images.append(UIImage(cgImage: cgImage))

                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let unclamped = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
                let clamped = gifProperties?[kCGImagePropertyGIFDelayTime] as? TimeInterval
                let delay = unclamped ?? clamped ?? 0.1
                totalDuration += max(delay, 0.02)
            }

            guard !images.isEmpty else { return nil }
            return GIFrames(images: images, duration: max(totalDuration, 0.1))
        }
    }
}
