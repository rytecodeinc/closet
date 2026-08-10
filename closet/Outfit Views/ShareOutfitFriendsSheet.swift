//
//  ShareOutfitFriendsSheet.swift
//  closet
//
//  Sheet: pick a friend to share an outfit with.
//

import SwiftUI

struct ShareOutfitFriendsSheet: View {
    let targetId: UUID
    var onSent: (() -> Void)? = nil

    var body: some View {
        ShareFriendsPickerSheet(
            navigationTitle: "Share Outfit",
            contentKind: .outfit,
            targetId: targetId,
            onSent: onSent
        )
    }
}
