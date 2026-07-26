//
//  OutfitView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//


import SwiftUI
import CoreData

struct OutfitView: View {
    @ObservedObject var outfit: Outfit
    var usesFlexibleSizing: Bool = false
    /// When false (e.g. profile read-only grid), hides the favorite heart overlay.
    var showsFavoriteOverlay: Bool = true
    /// When false, hides the Redress suggester avatar (e.g. Closet Redress filter).
    var showsRedressSuggesterAvatar: Bool = true

    // Matches the soft neutral color you used for items
    private let backgroundColor = Color(red: 247/255, green: 247/255, blue: 247/255)

    var body: some View {
        VStack(spacing: 2) {
            if let imageData = outfit.image,
               let uiImage = UIImage(data: imageData) {
                outfitImage(
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                )
            } else {
                outfitPlaceholder
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func outfitImage<Content: View>(_ image: Content) -> some View {
        let shaped = image
            .aspectRatio(1, contentMode: .fill)
            .clipped()

        if usesFlexibleSizing {
            shaped
                .overlay(alignment: .bottomLeading) { favoriteGradientOverlay }
                .overlay(alignment: .bottomLeading) { favoriteHeartOverlay }
                .overlay(alignment: .bottomTrailing) { redressSuggesterAvatarOverlay }
        } else {
            shaped
                .frame(minWidth: 120, minHeight: 120)
                .overlay(alignment: .bottomLeading) { favoriteGradientOverlay }
                .overlay(alignment: .bottomLeading) { favoriteHeartOverlay }
                .overlay(alignment: .bottomTrailing) { redressSuggesterAvatarOverlay }
        }
    }

    private var outfitPlaceholder: some View {
        Group {
            if usesFlexibleSizing {
                Rectangle()
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.system(size: 20))
                    }
                    .overlay(alignment: .bottomLeading) { favoriteGradientOverlay }
                    .overlay(alignment: .bottomLeading) { favoriteHeartOverlay }
                    .overlay(alignment: .bottomTrailing) { redressSuggesterAvatarOverlay }
            } else {
                Rectangle()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.system(size: 20))
                    }
                    .overlay(alignment: .bottomLeading) { favoriteGradientOverlay }
                    .overlay(alignment: .bottomLeading) { favoriteHeartOverlay }
                    .overlay(alignment: .bottomTrailing) { redressSuggesterAvatarOverlay }
            }
        }
    }

    @ViewBuilder
    private var favoriteGradientOverlay: some View {
        if showsFavoriteOverlay, outfit.isFavorite {
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.55),
                    Color.gray.opacity(0.55),
                    Color.clear
                ]),
                center: UnitPoint(x: -0.2, y: 1.5),
                startRadius: 0,
                endRadius: 100
            )
        }
    }

    @ViewBuilder
    private var favoriteHeartOverlay: some View {
        if showsFavoriteOverlay, outfit.isFavorite {
            Image(systemName: "heart.fill")
                .foregroundColor(.white)
                .font(.system(size: 12))
                .padding(.leading, 6)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var redressSuggesterAvatarOverlay: some View {
        if showsRedressSuggesterAvatar, let profile = outfit.redressSuggesterProfile {
            GeometryReader { geo in
                RedressSuggesterAvatarBadge(
                    profile: profile,
                    size: max(22, geo.size.width * 0.28)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(6)
            }
        }
    }
}
