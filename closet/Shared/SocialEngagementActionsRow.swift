//
//  SocialEngagementActionsRow.swift
//  closet
//

import SwiftUI

enum SocialEngagementToolbarSegment: Int, CaseIterable, Hashable {
    case tshirt
    case worn

    var systemImage: String {
        switch self {
        case .tshirt: "tshirt"
        case .worn: "person.crop.square.badge.camera"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .tshirt: "T-shirt"
        case .worn: "Worn photo"
        }
    }
}

struct SocialEngagementActionsRow: View {
    @Binding private var segmentSelection: SocialEngagementToolbarSegment

    /// When non-`nil`, the heart reflects liked/favorited on/off (`true` = `heart.fill`). When `nil`, shows outline `heart`.
    var favoriteSelection: Bool?
    /// When non-`nil`, shows the social like count next to the heart (other-user profiles).
    var likeCount: Int? = nil
    var showsLikeButton: Bool = true
    var isLikeInteractive: Bool = true
    var showsRedressButton: Bool = false
    var showsShareButton: Bool
    var showsMoveToClosetButton: Bool
    var showsWornSegment: Bool = true
    var disabledSegments: Set<SocialEngagementToolbarSegment> = []
    var onLike: () -> Void
    var onRedress: () -> Void
    var onShare: () -> Void
    var onMoveToCloset: () -> Void

    private var heartSystemImage: String {
        guard let isOn = favoriteSelection else { return "heart" }
        return isOn ? "heart.fill" : "heart"
    }

    private var heartAccessibilityLabel: String {
        let base: String
        if let isOn = favoriteSelection {
            base = isOn ? "Unlike" : "Like"
        } else {
            base = "Like"
        }
        if let likeCount, likeCount > 0 {
            return "\(base), \(likeCount) \(likeCount == 1 ? "like" : "likes")"
        }
        return base
    }

    init(
        segmentSelection: Binding<SocialEngagementToolbarSegment> = .constant(.tshirt),
        favoriteSelection: Bool? = nil,
        likeCount: Int? = nil,
        showsLikeButton: Bool = true,
        isLikeInteractive: Bool = true,
        showsRedressButton: Bool = false,
        showsShareButton: Bool = true,
        showsMoveToClosetButton: Bool = false,
        showsWornSegment: Bool = true,
        disabledSegments: Set<SocialEngagementToolbarSegment> = [],
        onLike: @escaping () -> Void = {},
        onRedress: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {},
        onMoveToCloset: @escaping () -> Void = {}
    ) {
        _segmentSelection = segmentSelection
        self.favoriteSelection = favoriteSelection
        self.likeCount = likeCount
        self.showsLikeButton = showsLikeButton
        self.isLikeInteractive = isLikeInteractive
        self.showsRedressButton = showsRedressButton
        self.showsShareButton = showsShareButton
        self.showsMoveToClosetButton = showsMoveToClosetButton
        self.showsWornSegment = showsWornSegment
        self.disabledSegments = disabledSegments
        self.onLike = onLike
        self.onRedress = onRedress
        self.onShare = onShare
        self.onMoveToCloset = onMoveToCloset
    }

    private var visibleSegments: [SocialEngagementToolbarSegment] {
        showsWornSegment
            ? SocialEngagementToolbarSegment.allCases
            : [.tshirt]
    }

    /// Shared column width so the count centers under the heart without shifting the actions row.
    private let likeColumnWidth: CGFloat = 28

    @ViewBuilder
    private var likeControlLabel: some View {
        Image(systemName: heartSystemImage)
            .imageScale(.large)
            .frame(width: likeColumnWidth, alignment: .center)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 24) {
                if showsLikeButton {
                    Group {
                        if isLikeInteractive {
                            Button(action: onLike) {
                                likeControlLabel
                            }
                            .buttonStyle(.plain)
                        } else {
                            likeControlLabel
                        }
                    }
                    .accessibilityLabel(heartAccessibilityLabel)
                }

                if showsRedressButton {
                    Button(action: onRedress) {
                        Image("Redress.SFSymbol")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Redress")
                }

                if showsMoveToClosetButton {
                    Button(action: onMoveToCloset) {
                        Image(systemName: "hanger")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to closet")
                }

                if showsShareButton {
                    Button(action: onShare) {
                        Image(systemName: "paperplane")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }

                Spacer(minLength: 12)

                if !visibleSegments.isEmpty {
                    Picker("", selection: $segmentSelection) {
                        ForEach(visibleSegments, id: \.self) { segment in
                            Image(systemName: segment.systemImage)
                                .tag(segment)
                                .selectionDisabled(disabledSegments.contains(segment))
                                .accessibilityLabel(segment.accessibilityLabel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: showsWornSegment ? 140 : 70)
                }
            }

            // Always reserve this slot when social likes are enabled (`likeCount != nil`)
            // so revealing the count after a tap doesn't shift the actions row upward.
            // Centered in the same column width as the heart.
            if showsLikeButton, let likeCount {
                Text(likeCount > 0 ? "\(likeCount)" : "0")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(likeCount > 0 ? 1 : 0)
                    .frame(width: likeColumnWidth, alignment: .center)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.top, 4)
       // .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}
