//
//  FittingView.swift
//  closet
//
//  Created by Dan Warner on 1/7/26.
//

import SwiftUI
import UIKit

struct Chat: Identifiable {
    let id = UUID()
    let userName: String
    let profileImageName: String
    let lastMessageStatus: MessageStatus
    let timeAgo: String
}

enum MessageStatus {
    case sent
    case received
    
    var icon: String {
        switch self {
        case .sent:
            return "paperplane"
        case .received:
            return "tray.and.arrow.down"
        }
    }
    
    var text: String {
        switch self {
        case .sent:
            return "sent"
        case .received:
            return "received"
        }
    }
}

struct FittingView: View {
    @Environment(\.appCapabilities) private var appCapabilities

    // Placeholder chat data
    @State private var chats: [Chat] = [
        Chat(userName: "Alex", profileImageName: "person.circle.fill", lastMessageStatus: .sent, timeAgo: "2s"),
        Chat(userName: "Sarah", profileImageName: "person.circle.fill", lastMessageStatus: .received, timeAgo: "5m"),
        Chat(userName: "Jordan", profileImageName: "person.circle.fill", lastMessageStatus: .sent, timeAgo: "1h"),
        Chat(userName: "Taylor", profileImageName: "person.circle.fill", lastMessageStatus: .received, timeAgo: "3h"),
        Chat(userName: "Morgan", profileImageName: "person.circle.fill", lastMessageStatus: .sent, timeAgo: "1d"),
        Chat(userName: "Casey", profileImageName: "person.circle.fill", lastMessageStatus: .received, timeAgo: "2d"),
        Chat(userName: "Riley", profileImageName: "person.circle.fill", lastMessageStatus: .sent, timeAgo: "1w"),
        Chat(userName: "Avery", profileImageName: "person.circle.fill", lastMessageStatus: .received, timeAgo: "2w"),
        Chat(userName: "Quinn", profileImageName: "person.circle.fill", lastMessageStatus: .sent, timeAgo: "3w"),
        Chat(userName: "Blake", profileImageName: "person.circle.fill", lastMessageStatus: .received, timeAgo: "13w")
    ]
    
    // Image picker state
    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    @State private var selectedUIImage: UIImage?
    @State private var isNotificationsPresented = false

    private var shouldHideTabBar: Bool {
        isNotificationsPresented
    }

    var body: some View {
        List {
            ForEach(chats) { chat in
                ChatRow(chat: chat)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Fitting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isNotificationsPresented) {
            UserNotificationsView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 16) {
                    Button {
                        // Checkmark action
                    } label: {
                        Image(systemName: "checkmark.gobackward")
                    }
                    
                    NavigationLink(destination: WhatSizeView()) {
                        Image(systemName: "ruler")
                            .rotationEffect(Angle(degrees: 135))
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if appCapabilities.enablesFriendsAndSharing {
                        UserNotificationsBellButton(isPresented: $isNotificationsPresented)
                    }

                    Menu {
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            imagePickerSource = .camera
                            isImagePickerPresented = true
                        }
                    } label: {
                        Label("Try On", systemImage: "camera")
                    }
                    
                    Button {
                        // Yes/No action
                    } label: {
                        Label("Yes/No", systemImage: "checkmark.bubble")
                    }
                    
                    Button {
                        // Rate 1-5 action
                    } label: {
                        Label("Rate 1-5", systemImage: "star")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                }
            }
        }
        .toolbar(shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
        .fullScreenCover(isPresented: $isImagePickerPresented) {
            ImagePicker(
                image: $selectedUIImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let newImage = image {
                    selectedUIImage = newImage
                    // Handle the captured image here if needed
                }
                isImagePickerPresented = false
            }
            .ignoresSafeArea()
        }
    }
}

struct ChatRow: View {
    let chat: Chat
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile photo
            Image(systemName: chat.profileImageName)
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.blue)
                .clipShape(Circle())
            
            // User name and message status
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.userName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    // Sent/received icon
                    Image(systemName: chat.lastMessageStatus.icon)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // Sent/received text
                    Text(chat.lastMessageStatus.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Time ago
                    Text(chat.timeAgo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Camera icon
            Image(systemName: "camera")
                .font(.title3)
                .foregroundColor(.secondary)
        }
      //  .padding(.vertical, 4)
    }
}
/*
#Preview {
    FittingView()
}
*/
