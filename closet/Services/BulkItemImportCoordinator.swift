//
//  BulkItemImportCoordinator.swift
//  closet
//
//  Background bulk import after Add Multiple → From Library: Vision background removal,
//  aspect-fit subject in 1:1, R2-safe encoding, Core Data save + sync.
//

import SwiftUI
import CoreData

@MainActor
final class BulkItemImportCoordinator: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var statusMessage: String = ""

    private var cancelled = false

    init() {}

    func cancel() {
        cancelled = true
        statusMessage = "Cancelling…"
    }

    /// Final square master side (subject aspect-fit inside).
    private static let storageSquareSide: CGFloat = 1200
    /// Max long edge sent to Vision (keeps mask pass bounded).
    private static let visionMaxInputDimension: CGFloat = 2048

    func startImport(
        images: [UIImage],
        context: NSManagedObjectContext,
        wardrobeObjectID: NSManagedObjectID,
        userId: String
    ) {
        guard !isActive else { return }
        guard !images.isEmpty else { return }

        cancelled = false
        isActive = true
        totalCount = images.count
        completedCount = 0
        statusMessage = "Preparing…"

        Task {
            await runImport(images: images, context: context, wardrobeObjectID: wardrobeObjectID, userId: userId)
            isActive = false
            totalCount = 0
            completedCount = 0
            statusMessage = ""
            cancelled = false
        }
    }

    private func runImport(
        images: [UIImage],
        context: NSManagedObjectContext,
        wardrobeObjectID: NSManagedObjectID,
        userId: String
    ) async {
        for (index, image) in images.enumerated() {
            if cancelled { break }

            statusMessage = "Image \(index + 1) of \(images.count)…"
            let pack = await Self.processImageOffMain(image: image)
            if cancelled { break }

            guard !pack.photoData.isEmpty else {
                print("⚠️ Bulk import: skipping image \(index + 1) — could not encode photo data")
                completedCount = index + 1
                continue
            }

            context.performAndWait {
                let item = Item(context: context)
                item.id = UUID()
                let now = Date()
                item.timestamp = now
                item.createdAt = now
                item.updatedAt = now
                item.isDraft = false
                item.userId = userId

                let photo = Photo(context: context)
                photo.id = UUID()
                photo.data = pack.photoData
                photo.thumbnailData = pack.thumbnailData
                photo.contentBoundsX = Double(pack.bounds.x)
                photo.contentBoundsY = Double(pack.bounds.y)
                photo.contentBoundsW = Double(pack.bounds.width)
                photo.contentBoundsH = Double(pack.bounds.height)
                photo.isPrimary = true
                photo.type = "front"
                photo.timestamp = now
                photo.createdAt = now
                photo.item = item

                Self.attachDefaultWardrobes(to: item, wardrobeObjectID: wardrobeObjectID, in: context)
                setUpdatedAt(item)

                do {
                    try context.save()
                    context.refresh(item, mergeChanges: true)
                    SyncService.shared.syncItemIfNeeded(item)
                } catch {
                    print("❌ Bulk import save failed: \(error.localizedDescription)")
                }
            }
            completedCount = index + 1
        }

        if cancelled {
            statusMessage = "Cancelled"
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    /// Vision background removal → detect subject bounds → aspect-fit in 1:1 → encode.
    private static func processImageOffMain(image: UIImage) async -> (photoData: Data, thumbnailData: Data?, bounds: NormalizedContentBounds) {
        let side = storageSquareSide
        return await Task.detached(priority: .userInitiated) { @Sendable in
            let visionInput = image.resizeForStorage(maxDimension: visionMaxInputDimension) ?? image
            let cutout = await BackgroundRemovalService.removeBackground(from: visionInput)
            let framed = cutout.squareAspectFitSubjectInSquare(side: side)
            let photoData = framed.encodeForR2Upload()
                ?? framed.processForStorage(maxDimension: side, maxFileSizeKB: 450)
                ?? Data()
            let thumbnailData = framed.gridThumbnailDataFromSquareMaster()
            let bounds = PhotoContentBounds.normalizedBounds(for: framed)
            return (photoData, thumbnailData, bounds)
        }.value
    }

    private static func attachDefaultWardrobes(to item: Item, wardrobeObjectID: NSManagedObjectID, in context: NSManagedObjectContext) {
        guard let wardrobe = try? context.existingObject(with: wardrobeObjectID) as? Wardrobe else { return }
        item.addToWardrobes(wardrobe)
        if let wardrobeType = wardrobe.type,
           let uid = item.userId ?? wardrobe.userId,
           let primary = try? WardrobeBootstrap.fetchPrimaryWardrobe(forType: wardrobeType, userIdString: uid, in: context),
           primary.objectID != wardrobe.objectID {
            item.addToWardrobes(primary)
        }
    }
}

// MARK: - Progress overlay (Closet / Wishlist tab, above tab bar)

struct BulkImportProgressOverlay: View {
    @EnvironmentObject private var bulkImport: BulkItemImportCoordinator

    var body: some View {
        Group {
            if bulkImport.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Adding items")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Cancel") {
                            bulkImport.cancel()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    ProgressView(
                        value: Double(bulkImport.completedCount),
                        total: Double(max(bulkImport.totalCount, 1))
                    )
                    Text(bulkImport.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
    }
}
