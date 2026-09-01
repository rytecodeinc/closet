//
//  EventLocationShareActionsRow.swift
//  closet
//
//  Share / copy / directions actions for an event location, plus a tappable map snapshot.
//

import SwiftUI
import UIKit

struct EventLocationShareActionsRow: View {
    let shareText: String
    let mapsQueryAddress: String?
    let latitude: Double?
    let longitude: Double?
    var rowInsets: EdgeInsets = EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
    var onCopiedAddress: (() -> Void)? = nil

    @State private var showingMapOptions = false

    private var hasNavigableLocation: Bool {
        if let mapsQueryAddress, !mapsQueryAddress.isEmpty { return true }
        if let latitude, let longitude, latitude != 0 || longitude != 0 { return true }
        return false
    }

    var body: some View {
        Group {
            shareActionsRow

            if hasNavigableLocation {
                LocationSnapshotView(
                    address: mapsQueryAddress,
                    latitude: latitude,
                    longitude: longitude
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    showingMapOptions = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open location in maps")
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .confirmationDialog("Open Location", isPresented: $showingMapOptions, titleVisibility: .visible) {
            if hasGoogleMaps {
                Button("Open in Google Maps") {
                    openGoogleMaps()
                }
            }
            Button("Open in Maps") {
                openAppleMaps()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var shareActionsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Share")
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 18) {
                Button {
                    UIPasteboard.general.string = shareText
                    onCopiedAddress?()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy location")

                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share location")

                Button {
                    showingMapOptions = true
                } label: {
                    Image(systemName: "car")
                }
                .disabled(!hasNavigableLocation)
                .accessibilityLabel("Open in maps")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
    }

    private var hasGoogleMaps: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func openAppleMaps() {
        if let address = mapsQueryAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty,
           let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
            return
        }
        guard let latitude, let longitude, latitude != 0 || longitude != 0,
              let url = URL(string: "maps://?q=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url)
    }

    private func openGoogleMaps() {
        if let address = mapsQueryAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty,
           let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "comgooglemaps://?q=\(encoded)") {
            UIApplication.shared.open(url)
            return
        }
        guard let latitude, let longitude, latitude != 0 || longitude != 0,
              let url = URL(string: "comgooglemaps://?q=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url)
    }
}
