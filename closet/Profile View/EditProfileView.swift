//
//  EditProfileView.swift
//  closet
//

import SwiftUI
import CoreData
import UIKit

struct EditProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var supabaseService: SupabaseService

    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: []
    ) private var allUserProfiles: FetchedResults<UserProfile>

    @State private var draftUsername = ""
    @State private var baselineUsername = ""
    @State private var draftDisplayName = ""
    @State private var baselineDisplayName = ""

    @State private var isPhotoActionDialogPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var pickerImage: UIImage?
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary

    @State private var isSaving = false
    @State private var isAvatarUploading = false
    @State private var saveError: String?
    @State private var avatarUploadError: String?
    @State private var avatarRefreshToken = UUID()
    /// Same pattern as Friends → other-user profile (`navigationDestination(item:)`).
    @State private var editProfileDestination: EditProfileDestination?

    private static let avatarDisplaySize: CGFloat = 120
    private static let pencilBadgeSize: CGFloat = 28

    private var userProfile: UserProfile? {
        guard let userId = authSession.userId?.uuidString else { return nil }
        return allUserProfiles.first { $0.userId == userId }
    }

    private var isDirty: Bool {
        let trimmedDraft = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseline = baselineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayDirty = trimmedDraft != trimmedBaseline
        guard canEditUsername else { return displayDirty }
        let trimmedUsername = draftUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsernameBaseline = baselineUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayDirty || trimmedUsername != trimmedUsernameBaseline
    }

    /// See UsernameChangePolicy / username-change-cooldown-deferred.mdc
    private var canEditUsername: Bool {
        UsernameChangePolicy.canChangeUsername(lastChangedAt: userProfile?.usernameChangedAt)
    }

    private var usernameCooldownFooter: String? {
        guard let next = UsernameChangePolicy.nextAllowedChangeDate(after: userProfile?.usernameChangedAt),
              !canEditUsername else { return nil }
        return UsernameChangePolicy.lockedMessage(until: next)
    }

    private var avatarProfile: PublicUserProfile? {
        guard let uid = authSession.userId else { return nil }
        return PublicUserProfile(
            userId: uid,
            username: userProfile?.username ?? supabaseService.cachedUsername ?? "",
            displayName: draftDisplayName,
            avatarUrl: userProfile?.storedProfileAvatarURL
        )
    }

    var body: some View {
        List {
            Section {
                avatarSection
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listSectionSpacing(0)

            Section {
                TextField("Username", text: $draftUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.username)
                    .disabled(!canEditUsername)
                    .foregroundStyle(canEditUsername ? .primary : .secondary)
            } header: {
                sectionHeader("USERNAME")
            } footer: {
                if let usernameCooldownFooter {
                    Text(usernameCooldownFooter)
                }
            }

            Section {
                TextField("Display name", text: $draftDisplayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
            } header: {
                sectionHeader("DISPLAY NAME")
            }

            Section {
                Button {
                    editProfileDestination = .wardrobePrivacy
                } label: {
                    HStack {
                        Text("Wardrobe Privacy")
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                sectionHeader("WARDROBES")
            }

            // TODO: Revisit profile style tags — restore STYLE TAGS section (ProfileStyleTag pickers) when shipping the feature.
        }
        .listStyle(.plain)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $editProfileDestination) { destination in
            // Stay on the parent Profile NavigationStack (no nested stack) — same as FriendsView.
            switch destination {
            case .wardrobePrivacy:
                WardrobePrivacyView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!isDirty || isSaving || isAvatarUploading)
            }
        }
        .onAppear {
            loadDraftFromProfile()
            Task {
                guard appCapabilities.enablesCloudSync else { return }
                _ = try? await supabaseService.getUsername(forceRefresh: true)
                await MainActor.run { loadDraftFromProfile() }
            }
        }
        .confirmationDialog(
            "Profile Photo",
            isPresented: $isPhotoActionDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Take Photo") { }
            Button("Choose from Library") {
                imagePickerSource = .photoLibrary
                isLibraryPickerPresented = true
            }
            Button("Remove Current Photo", role: .destructive) {
                Task { await removeProfileAvatar() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isLibraryPickerPresented) {
            ImagePicker(
                image: $pickerImage,
                sourceType: $imagePickerSource,
                allowsEditing: true,
                usesProfileCrop: true
            ) { image in
                isLibraryPickerPresented = false
                guard let image else { return }
                Task { await uploadProfileAvatarFromLibrary(image) }
            }
        }
        .alert("Could Not Save", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .alert("Photo", isPresented: avatarUploadErrorPresented) {
            Button("OK", role: .cancel) { avatarUploadError = nil }
        } message: {
            Text(avatarUploadError ?? "")
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private var avatarUploadErrorPresented: Binding<Bool> {
        Binding(
            get: { avatarUploadError != nil },
            set: { if !$0 { avatarUploadError = nil } }
        )
    }

    private var avatarSection: some View {
        HStack {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                avatarImageContent
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)

                Button {
                    isPhotoActionDialogPresented = true
                } label: {
                    Color.clear
                        .frame(width: Self.avatarDisplaySize, height: Self.avatarDisplaySize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isAvatarUploading || isSaving)

                // Decorative edit badge — matches ProfileView header; tap target is the avatar.
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: Self.pencilBadgeSize, height: Self.pencilBadgeSize)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
                    .offset(x: 2, y: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: Self.avatarDisplaySize, height: Self.avatarDisplaySize)
            Spacer()
        }
        .padding(.vertical, 16)
        .id(avatarRefreshToken)
    }

    private var avatarImageContent: some View {
        ZStack {
            if let profile = avatarProfile {
                PublicUserProfileAvatarView(profile: profile, size: Self.avatarDisplaySize)
            } else {
                avatarPlaceholder
            }
            if isAvatarUploading {
                Circle()
                    .fill(.ultraThinMaterial)
                ProgressView()
            }
        }
        .frame(width: Self.avatarDisplaySize, height: Self.avatarDisplaySize)
        .clipShape(Circle())
        .contentShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.gray)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .fontWeight(.semibold)
    }

    private func loadDraftFromProfile() {
        let username = (userProfile?.username ?? supabaseService.cachedUsername ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        draftUsername = username
        baselineUsername = username

        let name = userProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        draftDisplayName = name
        baselineDisplayName = name
    }

    private func save() async {
        guard let userId = authSession.userId else { return }
        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }

        let repository = UserProfileRepository(context: viewContext)
        let trimmedUsername = draftUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernameChanged = canEditUsername
            && trimmedUsername != baselineUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayNameChanged = trimmedName != baselineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if usernameChanged {
                if appCapabilities.enablesCloudSync {
                    try await supabaseService.updateUsername(trimmedUsername)
                } else {
                    try repository.updateUsername(trimmedUsername, userId: userId.uuidString)
                }
            }
            if displayNameChanged {
                try repository.updateDisplayName(trimmedName, userId: userId.uuidString)
            }
            // TODO: Revisit profile style tags — re-enable repository.updateStyleTags when shipping the feature.

            await MainActor.run {
                viewContext.refreshAllObjects()
                dismiss()
            }
        } catch {
            await MainActor.run {
                saveError = error.localizedDescription
            }
        }
    }

    /// Square-crops, flattens to opaque JPEG. Production uploads to R2 + Supabase; TestFlight stores on device only.
    private func uploadProfileAvatarFromLibrary(_ image: UIImage) async {
        guard let userId = authSession.userId else { return }
        let prepared = image.profileAvatarImageForUpload()
        guard let data = prepared.encodeForR2Upload() else {
            await MainActor.run {
                avatarUploadError = "Could not process image."
            }
            return
        }

        await MainActor.run {
            isAvatarUploading = true
            avatarUploadError = nil
        }
        defer {
            Task { @MainActor in
                isAvatarUploading = false
            }
        }

        do {
            let previousAvatarURL = userProfile?.storedProfileAvatarURL
            if appCapabilities.enablesCloudSync {
                let url = try await supabaseService.uploadProfileAvatar(imageData: data, userId: userId)
                try await supabaseService.updateProfileAvatarURL(url)
                ProfileAvatarLocalStorage.delete(userId: userId)
            } else {
                _ = try ProfileAvatarLocalStorage.saveJPEG(userId: userId, data: data)
                let repository = UserProfileRepository(context: viewContext)
                try repository.updateAvatarUrl(
                    ProfileAvatarLocalStorage.canonicalStoredURLString(for: userId),
                    userId: userId.uuidString,
                    syncToCloud: false
                )
            }
            if let previousAvatarURL {
                ProfileAvatarImageCache.remove(for: previousAvatarURL)
            }
            await MainActor.run {
                viewContext.refreshAllObjects()
                avatarRefreshToken = UUID()
            }
        } catch {
            await MainActor.run {
                avatarUploadError = error.localizedDescription
            }
        }
    }

    private func removeProfileAvatar() async {
        guard let userId = authSession.userId else { return }
        let previousAvatarURL = userProfile?.storedProfileAvatarURL
        await MainActor.run {
            isAvatarUploading = true
            avatarUploadError = nil
        }
        defer {
            Task { @MainActor in
                isAvatarUploading = false
            }
        }
        do {
            if appCapabilities.enablesCloudSync {
                try? await supabaseService.deleteProfileAvatar(userId: userId)
                try await supabaseService.updateProfileAvatarURL(nil)
                ProfileAvatarLocalStorage.delete(userId: userId)
            } else {
                ProfileAvatarLocalStorage.delete(userId: userId)
                let repository = UserProfileRepository(context: viewContext)
                try repository.updateAvatarUrl(nil, userId: userId.uuidString, syncToCloud: false)
            }
            if let previousAvatarURL {
                ProfileAvatarImageCache.remove(for: previousAvatarURL)
            }
            await MainActor.run {
                viewContext.refreshAllObjects()
                avatarRefreshToken = UUID()
            }
        } catch {
            await MainActor.run {
                avatarUploadError = error.localizedDescription
            }
        }
    }
}

/// Nested destinations from Edit Profile — pushed via `navigationDestination(item:)`
/// on the parent Profile stack (same pattern as Friends → other-user profile).
private enum EditProfileDestination: String, Identifiable, Hashable {
    case wardrobePrivacy

    var id: String { rawValue }
}
