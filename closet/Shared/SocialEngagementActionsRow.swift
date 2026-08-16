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
    /// When non-`nil`, shows the social like count under the heart (other-user profiles).
    var likeCount: Int? = nil
    /// When non-`nil`, shows completed-calendar count under the calendar icon (owned closet item detail).
    var calendarCount: Int? = nil
    var showsLikeButton: Bool = true
    var isLikeInteractive: Bool = true
    var showsCalendarButton: Bool = false
    var showsRedressButton: Bool = false
    var showsShareButton: Bool
    var showsMoveToClosetButton: Bool
    var showsWornSegment: Bool = true
    var disabledSegments: Set<SocialEngagementToolbarSegment> = []
    var onLike: () -> Void
    var onCalendar: () -> Void
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

    private var calendarAccessibilityLabel: String {
        if let calendarCount, calendarCount > 0 {
            return "Calendar, worn \(calendarCount) \(calendarCount == 1 ? "time" : "times")"
        }
        return "Calendar"
    }

    private var showsCountRow: Bool {
        (showsLikeButton && likeCount != nil) || (showsCalendarButton && calendarCount != nil)
    }

    init(
        segmentSelection: Binding<SocialEngagementToolbarSegment> = .constant(.tshirt),
        favoriteSelection: Bool? = nil,
        likeCount: Int? = nil,
        calendarCount: Int? = nil,
        showsLikeButton: Bool = true,
        isLikeInteractive: Bool = true,
        showsCalendarButton: Bool = false,
        showsRedressButton: Bool = false,
        showsShareButton: Bool = true,
        showsMoveToClosetButton: Bool = false,
        showsWornSegment: Bool = true,
        disabledSegments: Set<SocialEngagementToolbarSegment> = [],
        onLike: @escaping () -> Void = {},
        onCalendar: @escaping () -> Void = {},
        onRedress: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {},
        onMoveToCloset: @escaping () -> Void = {}
    ) {
        _segmentSelection = segmentSelection
        self.favoriteSelection = favoriteSelection
        self.likeCount = likeCount
        self.calendarCount = calendarCount
        self.showsLikeButton = showsLikeButton
        self.isLikeInteractive = isLikeInteractive
        self.showsCalendarButton = showsCalendarButton
        self.showsRedressButton = showsRedressButton
        self.showsShareButton = showsShareButton
        self.showsMoveToClosetButton = showsMoveToClosetButton
        self.showsWornSegment = showsWornSegment
        self.disabledSegments = disabledSegments
        self.onLike = onLike
        self.onCalendar = onCalendar
        self.onRedress = onRedress
        self.onShare = onShare
        self.onMoveToCloset = onMoveToCloset
    }

    private var visibleSegments: [SocialEngagementToolbarSegment] {
        showsWornSegment
            ? SocialEngagementToolbarSegment.allCases
            : [.tshirt]
    }

    /// Shared column width so counts center under icons without shifting the actions row.
    private let actionColumnWidth: CGFloat = 28

    @ViewBuilder
    private var likeControlLabel: some View {
        Image(systemName: heartSystemImage)
            .imageScale(.large)
            .frame(width: actionColumnWidth, alignment: .center)
    }

    @ViewBuilder
    private func countText(_ count: Int) -> some View {
        Text(count > 0 ? "\(count)" : "0")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .opacity(count > 0 ? 1 : 0)
            .frame(width: actionColumnWidth, alignment: .center)
            .accessibilityHidden(true)
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

                if showsCalendarButton {
                    Button(action: onCalendar) {
                        Image(systemName: "calendar")
                            .imageScale(.large)
                            .frame(width: actionColumnWidth, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendarAccessibilityLabel)
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

            // Counts under like / calendar columns (same spacing as the icon row).
            // Reserve slots when enabled so revealing a count doesn't shift layout.
            if showsCountRow {
                HStack(spacing: 24) {
                    if showsLikeButton {
                        if let likeCount {
                            countText(likeCount)
                        } else {
                            Color.clear.frame(width: actionColumnWidth, height: 1)
                        }
                    }

                    if showsCalendarButton {
                        if let calendarCount {
                            Button(action: onCalendar) {
                                countText(calendarCount)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(calendarAccessibilityLabel)
                        } else {
                            Color.clear.frame(width: actionColumnWidth, height: 1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .background(Color(.systemBackground))
    }
}
