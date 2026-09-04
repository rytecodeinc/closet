//
//  ShareItemFriendsSheet.swift
//  closet
//
//  Sheet: pick a friend to share an item with.
//

import SwiftUI

enum ShareFriendsContentKind {
    case item
    case outfit

    var noun: String {
        switch self {
        case .item: return "item"
        case .outfit: return "outfit"
        }
    }

    var targetType: String { noun }
}

struct ShareItemFriendsSheet: View {
    var navigationTitle: String = "Share Item"
    let targetId: UUID
    var onSent: (() -> Void)? = nil

    var body: some View {
        ShareFriendsPickerSheet(
            navigationTitle: navigationTitle,
            contentKind: .item,
            targetId: targetId,
            onSent: onSent
        )
    }
}

/// Pick a friend to share an item or outfit with — reuses `FriendsListView` layout.
struct ShareFriendsPickerSheet: View {
    let navigationTitle: String
    let contentKind: ShareFriendsContentKind
    let targetId: UUID
    var onSent: (() -> Void)? = nil

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var sendingRecipientId: UUID?
    @State private var sentRecipientIds: Set<UUID> = []
    @State private var sendError: String?

    private var isSending: Bool {
        sendingRecipientId != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectionHeader(title: navigationTitle)
                if let userId = authSession.userId {
                    FriendsListView(
                        userId: userId,
                        emptyMessage: "You don’t have any friends yet. Add friends from your profile.",
                        isPushed: false,
                        allowsOpeningProfile: false
                    ) { friend in
                        shareTrailingControl(for: friend)
                    }
                } else {
                    Text("Sign in to see your friends.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            sendingRecipientId = nil
            sentRecipientIds = []
        }
        .alert("Couldn’t send", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    @ViewBuilder
    private func shareTrailingControl(for friend: PublicUserProfile) -> some View {
        let isSendingThisRow = sendingRecipientId == friend.userId
        let isSent = sentRecipientIds.contains(friend.userId)
        let isDisabled = isSending && sendingRecipientId != friend.userId

        Button {
            Task { await sendTapped(to: friend) }
        } label: {
            if isSendingThisRow {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else if isSent {
                Label("Sent", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                Label("Share", systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
            (isSent ? Color.secondary : Color.accentColor),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .disabled(isSent || isDisabled || isSendingThisRow)
        .opacity(isDisabled && !isSendingThisRow && !isSent ? 0.45 : 1)
        .accessibilityLabel(
            isSent
                ? "Sent to \(friend.username)"
                : "Share with \(friend.username)"
        )
    }

    private func sendTapped(to recipient: PublicUserProfile) async {
        await MainActor.run {
            sendingRecipientId = recipient.userId
            sendError = nil
        }
        do {
            try await supabaseService.shareContentWithFriend(
                recipientUserId: recipient.userId,
                targetType: contentKind.targetType,
                targetId: targetId
            )
            await MainActor.run {
                sendingRecipientId = nil
                sentRecipientIds.insert(recipient.userId)
                onSent?()
            }
        } catch {
            await MainActor.run {
                sendingRecipientId = nil
                sendError = error.localizedDescription
            }
        }
    }
}
