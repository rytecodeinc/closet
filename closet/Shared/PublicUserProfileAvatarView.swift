//
//  PublicUserProfileAvatarView.swift
//  closet
//
//  Circular avatar for public profiles: remote image when `avatarUrl` is set, otherwise initials.
//

import SwiftUI
import UIKit

struct PublicUserProfileAvatarView: View {
    let profile: PublicUserProfile
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let localImage = localFileAvatarImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = resolvedAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        initialsPlaceholder
                    @unknown default:
                        initialsPlaceholder
                    }
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var resolvedAvatarURL: URL? {
        guard let raw = profile.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// TestFlight-tier avatars are stored under Application Support (`file://…`).
    private var localFileAvatarImage: UIImage? {
        if let url = resolvedAvatarURL, url.isFileURL,
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if !AppEnvironment.capabilities.enablesCloudSync,
           ProfileAvatarLocalStorage.hasSavedAvatar(userId: profile.userId) {
            let path = ProfileAvatarLocalStorage.fileURL(for: profile.userId).path
            return UIImage(contentsOfFile: path)
        }
        return nil
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Circle()
                .fill(initialsBackgroundColor)
            Text(profileInitials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private var profileInitials: String {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            let parts = name.split(separator: " ").filter { !$0.isEmpty }
            if parts.count >= 2 {
                let a = parts[0].prefix(1)
                let b = parts[parts.count - 1].prefix(1)
                return "\(a)\(b)".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return String(profile.username.prefix(2)).uppercased()
    }

    private var initialsBackgroundColor: Color {
        var hasher = Hasher()
        hasher.combine(profile.userId)
        let h = abs(hasher.finalize()) % 360
        return Color(hue: Double(h) / 360.0, saturation: 0.38, brightness: 0.88)
    }
}
