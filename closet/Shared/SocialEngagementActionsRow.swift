//
//  SocialEngagementActionsRow.swift
//  closet
//

import SwiftUI

enum SocialEngagementToolbarSegment: Int, CaseIterable, Hashable {
    case tshirt
    // case arrowBackward
    case person

    var systemImage: String {
        switch self {
        case .tshirt: "tshirt"
        // case .arrowBackward: "arrowshape.turn.up.backward"
        case .person: "person.and.background.striped.horizontal"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .tshirt: "T-shirt"
        // case .arrowBackward: "Back"
        case .person: "Person"
        }
    }
}

struct SocialEngagementActionsRow: View {
    @Binding private var segmentSelection: SocialEngagementToolbarSegment

    /// When non-`nil`, the heart reflects favorite on/off (`true` = `heart.fill`). When `nil`, shows outline `heart` (e.g. outfits).
    var favoriteSelection: Bool?
    var onLike: () -> Void
    var onShare: () -> Void

    private var heartSystemImage: String {
        guard let isOn = favoriteSelection else { return "heart" }
        return isOn ? "heart.fill" : "heart"
    }

    private var heartAccessibilityLabel: String {
        guard let isOn = favoriteSelection else { return "Like" }
        return isOn ? "Remove from favorites" : "Add to favorites"
    }

    init(
        segmentSelection: Binding<SocialEngagementToolbarSegment> = .constant(.tshirt),
        favoriteSelection: Bool? = nil,
        onLike: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {}
    ) {
        _segmentSelection = segmentSelection
        self.favoriteSelection = favoriteSelection
        self.onLike = onLike
        self.onShare = onShare
    }

    var body: some View {
        HStack(spacing: 24) {
            Button(action: onLike) {
                Image(systemName: heartSystemImage)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(heartAccessibilityLabel)

            Button(action: onShare) {
                Image(systemName: "paperplane")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            Spacer(minLength: 12)

            Picker("", selection: $segmentSelection) {
                ForEach(SocialEngagementToolbarSegment.allCases, id: \.self) { segment in
                    Image(systemName: segment.systemImage)
                        .tag(segment)
                        .accessibilityLabel(segment.accessibilityLabel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
       // .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}
