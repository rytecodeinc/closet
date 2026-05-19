//
//  ItemPhotoStorageSheet.swift
//  closet
//

import SwiftUI
import CoreData

struct ItemPhotoStorageSheet: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var isCompressingItemImage = false
    @State private var isCompressingWornImage = false
    @State private var refreshToken = UUID()
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var frontPhoto: Photo? { ItemPhotoStorage.frontPhoto(for: item) }
    private var wornPhoto: Photo? { ItemPhotoStorage.wornPhoto(for: item) }

    private var itemImageBytes: Int { ItemPhotoStorage.dataByteCount(for: frontPhoto) }
    private var wornImageBytes: Int { ItemPhotoStorage.dataByteCount(for: wornPhoto) }

    private var canCompressItemImage: Bool {
        ItemPhotoStorage.needsCompression(for: frontPhoto)
    }

    private var canCompressWornImage: Bool {
        ItemPhotoStorage.needsCompression(for: wornPhoto)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    storageSizeRow(title: "Item image", byteCount: itemImageBytes)
                    storageSizeRow(title: "Worn image", byteCount: wornImageBytes)
                } footer: {
                    Text("Cutouts (PNG): resize to 1200px max—file size may stay above \(ItemPhotoStorage.compressionMaxKB) KB. Opaque photos: resize to 1200px and target under \(ItemPhotoStorage.compressionMaxKB) KB.")
                }

                Section {
                    Button {
                        compressItemImage()
                    } label: {
                        HStack {
                            if isCompressingItemImage {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(ItemPhotoStorage.compressButtonTitle(for: frontPhoto, imageLabel: "item image"))
                        }
                    }
                    .disabled(!canCompressItemImage || isCompressingItemImage || isCompressingWornImage)

                    Button {
                        compressWornImage()
                    } label: {
                        HStack {
                            if isCompressingWornImage {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(ItemPhotoStorage.compressButtonTitle(for: wornPhoto, imageLabel: "worn image"))
                        }
                    }
                    .disabled(!canCompressWornImage || isCompressingItemImage || isCompressingWornImage)
                }
            }
            .id(refreshToken)
            .navigationTitle("Image storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func storageSizeRow(title: String, byteCount: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(ItemPhotoStorage.formatByteCount(byteCount))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func compressItemImage() {
        guard let photo = frontPhoto else { return }
        isCompressingItemImage = true
        Task { @MainActor in
            defer { isCompressingItemImage = false }
            do {
                let didCompress = try ItemPhotoStorage.compressPhotoIfNeeded(photo, item: item, in: viewContext)
                if didCompress {
                    viewContext.refresh(item, mergeChanges: true)
                    refreshToken = UUID()
                    SyncService.shared.syncItemIfNeeded(item)
                    alertTitle = "Item image compressed"
                    alertMessage = "New size: \(ItemPhotoStorage.formatByteCount(ItemPhotoStorage.dataByteCount(for: photo)))."
                } else {
                    alertTitle = "No change"
                    alertMessage = ItemPhotoStorage.compressSkippedMessage(for: frontPhoto, imageLabel: "Item image")
                }
                showAlert = true
            } catch {
                alertTitle = "Compression failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func compressWornImage() {
        guard let photo = wornPhoto else { return }
        isCompressingWornImage = true
        Task { @MainActor in
            defer { isCompressingWornImage = false }
            do {
                let didCompress = try ItemPhotoStorage.compressPhotoIfNeeded(photo, item: item, in: viewContext)
                if didCompress {
                    viewContext.refresh(item, mergeChanges: true)
                    refreshToken = UUID()
                    SyncService.shared.syncItemIfNeeded(item)
                    alertTitle = "Worn image compressed"
                    alertMessage = "New size: \(ItemPhotoStorage.formatByteCount(ItemPhotoStorage.dataByteCount(for: photo)))."
                } else {
                    alertTitle = "No change"
                    alertMessage = ItemPhotoStorage.compressSkippedMessage(for: wornPhoto, imageLabel: "Worn image")
                }
                showAlert = true
            } catch {
                alertTitle = "Compression failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}
