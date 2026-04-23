//
//  OutfitDetailView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import Foundation
import SwiftUI
import CoreData
import UIKit

private enum OutfitHeroImageSlot {
    case collage
    case worn
}

struct OutfitDetailView: View {
    @ObservedObject var outfit: Outfit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var attributesSheet: OutfitAttributesSectionView.Sheet?
    @State private var isFeaturedItemsExpanded = true
    
    @State private var isEditingOutfit = false
    /// Inline hero: 0 = collage (tshirt), 1 = worn (person).
    @State private var heroCarouselPage: Int = 0
    @State private var isOutfitImageFullScreen = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showDeleteOutfitConfirmation = false

    @State private var showOutfitHeroOptionsDialog = false
    @State private var isOutfitHeroImagePickerPresented = false
    @State private var outfitHeroImagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedOutfitHeroUIImage: UIImage?
    @State private var outfitHeroImagePickerSlot: OutfitHeroImageSlot = .collage

    @State private var isOutfitImageCropperPresented = false
    @State private var outfitHeroImageToEdit: UIImage?
    @State private var outfitHeroCropSlot: OutfitHeroImageSlot = .collage
    @State private var isOutfitCropReplacePickerPresented = false
    @State private var outfitCropEditorSessionID = UUID()

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    
    // Computed property to get ordered items array (preserves insertion order from canvas)
    private var orderedItems: [Item] {
        // Try to use transformationData first (preserves order from canvas)
        if let transformationData = outfit.transformationData {
            let decoder = JSONDecoder()
            if let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) {
                let itemsSet = outfit.items as? Set<Item> ?? []
                // Build lookup by both portable UUID and legacy Core Data ObjectID URI
                var itemsByUUID: [String: Item] = [:]
                var itemsByObjectID: [String: Item] = [:]
                for item in itemsSet {
                    if let uuid = item.id?.uuidString { itemsByUUID[uuid] = item }
                    itemsByObjectID[item.objectID.uriRepresentation().absoluteString] = item
                }
                // Return items in canvas order; match UUID first, then legacy ObjectID
                return savedItems.compactMap { savedItem in
                    itemsByUUID[savedItem.itemID] ?? itemsByObjectID[savedItem.itemID]
                }
            }
        }
        // Fallback: if no transformationData, use Set (unordered, but better than nothing)
        if let itemsSet = outfit.items as? Set<Item> {
            return Array(itemsSet)
        }
        return []
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                outfitDisplayArea

                SocialEngagementActionsRow(
                    segmentSelection: Binding(
                        get: { heroCarouselPage == 0 ? .tshirt : .person },
                        set: { segment in
                            withAnimation {
                                heroCarouselPage = segment == .tshirt ? 0 : 1
                            }
                        }
                    ),
                    onShare: { shareOutfitImage() }
                )
                
                // Featured Items Toggle Row
                featuredItemsToggleRow()
                  //  .padding(.horizontal, 6)
                // Divider before Featured Items
                Divider()
                    .padding(.leading, 12)
                // Featured Items Grid (shown when expanded)
                if isFeaturedItemsExpanded {
                    if !orderedItems.isEmpty {
                        let gridItems = [
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4)
                        ]
                        LazyVGrid(columns: gridItems, spacing: 4) {
                            ForEach(orderedItems, id: \.objectID) { item in
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemView(item: item)
                                }
                            }
                        }
                      //  .padding(.horizontal, 10)
                      //  .padding(.top, 4)
                    }
                }
                
                
                
                // Attributes Section
                OutfitAttributesSectionView(outfit: outfit, activeSheet: $attributesSheet)
                   // .padding(.horizontal, 6)
                
                
            }
        }
        .navigationTitle("Outfit Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            heroCarouselPage = 0
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if currentOutfitHeroUIImage() != nil {
                    Button {
                        shareOutfitImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share outfit")
                }
                Button(role: .destructive) {
                    showDeleteOutfitConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Delete outfit")
            }
        }
        .fullScreenCover(isPresented: $isEditingOutfit) {
            NavigationView {
                OutfitAddView(outfitToEdit: outfit)
            }
        }
        .fullScreenCover(isPresented: $isOutfitImageFullScreen) {
            fullScreenOutfitImageView()
        }
        .sheet(item: $attributesSheet) { sheet in
            NavigationView {
                sheet.destination(for: outfit)
            }
            .presentationDetents([.medium, .large])
        }
        .overlay {
            if showShareSheet {
                ActivityViewController(activityItems: shareItems, isPresented: $showShareSheet)
                    .frame(width: 0, height: 0)
            }
        }
        .alert("Delete Outfit", isPresented: $showDeleteOutfitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteOutfit()
            }
        } message: {
            Text("Delete this outfit? This action cannot be undone.")
        }
        .confirmationDialog(outfitHeroOptionsDialogTitle, isPresented: $showOutfitHeroOptionsDialog, titleVisibility: .visible) {
            outfitHeroOptionsDialogContent
        }
        .sheet(isPresented: $isOutfitHeroImagePickerPresented) {
            ImagePicker(
                image: $pickedOutfitHeroUIImage,
                sourceType: $outfitHeroImagePickerSource,
                allowsEditing: true,
                completionHandler: { image in
                    if let image = image {
                        switch outfitHeroImagePickerSlot {
                        case .collage:
                            saveCollageOutfitImage(image)
                        case .worn:
                            saveWornOutfitImage(image)
                        }
                    }
                    isOutfitHeroImagePickerPresented = false
                    pickedOutfitHeroUIImage = nil
                }
            )
        }
        .sheet(isPresented: $isOutfitImageCropperPresented, onDismiss: {
            isOutfitCropReplacePickerPresented = false
        }) {
            outfitImageCropperSheetContent
        }
    }

    private var outfitHeroOptionsDialogTitle: String {
        heroCarouselPage == 0 ? "Collage" : "Photo"
    }

    @ViewBuilder
    private var outfitHeroOptionsDialogContent: some View {
        if heroCarouselPage == 0 {
            Button("Edit Collage") {
                isEditingOutfit = true
            }
            Button("Cancel", role: .cancel) {}
        } else {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Retake Photo") {
                    outfitHeroImagePickerSlot = .worn
                    outfitHeroImagePickerSource = .camera
                    isOutfitHeroImagePickerPresented = true
                }
            }
            Button("Replace from Library") {
                outfitHeroImagePickerSlot = .worn
                outfitHeroImagePickerSource = .photoLibrary
                isOutfitHeroImagePickerPresented = true
            }
            if currentOutfitHeroUIImage() != nil {
                Button("Edit Image") {
                    presentOutfitHeroImageCropper()
                }
                Button("Share Image") {
                    shareOutfitImage()
                }
            }
            if outfit.wornImage != nil {
                Button("Remove Image", role: .destructive) {
                    removeOutfitWornImage()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var outfitImageCropperSheetContent: some View {
        if let image = outfitHeroImageToEdit {
            NavigationView {
                ImageCropperView(
                    originalImage: image,
                    onCrop: { croppedImage in
                        switch outfitHeroCropSlot {
                        case .collage:
                            saveCollageOutfitImage(croppedImage)
                        case .worn:
                            saveWornOutfitImage(croppedImage)
                        }
                        outfitHeroImageToEdit = nil
                        isOutfitImageCropperPresented = false
                    },
                    isEditing: true,
                    onReplaceFromCamera: {
                        outfitHeroImagePickerSource = .camera
                        isOutfitCropReplacePickerPresented = true
                    },
                    onReplaceFromLibrary: {
                        outfitHeroImagePickerSource = .photoLibrary
                        isOutfitCropReplacePickerPresented = true
                    },
                    isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
                )
                .id(outfitCropEditorSessionID)
                .sheet(isPresented: $isOutfitCropReplacePickerPresented) {
                    ImagePicker(
                        image: $pickedOutfitHeroUIImage,
                        sourceType: $outfitHeroImagePickerSource,
                        allowsEditing: true,
                        skipEmbeddedCrop: true,
                        completionHandler: { newImage in
                            if let newImage = newImage {
                                outfitCropEditorSessionID = UUID()
                                outfitHeroImageToEdit = newImage
                            }
                            isOutfitCropReplacePickerPresented = false
                            pickedOutfitHeroUIImage = nil
                        }
                    )
                }
            }
        } else {
            Text("No image found to edit.")
                .padding()
        }
    }

    /// Hero pages present in fullscreen (skips missing): collage first, then worn when both exist.
    private func outfitFullscreenHeroPages(hasCollage: Bool, hasWorn: Bool) -> [Int] {
        var pages: [Int] = []
        if hasCollage { pages.append(0) }
        if hasWorn { pages.append(1) }
        return pages
    }

    private func outfitFullscreenIndexForHero(hasCollage: Bool, hasWorn: Bool, heroPage: Int) -> Int {
        let slots = outfitFullscreenHeroPages(hasCollage: hasCollage, hasWorn: hasWorn)
        return slots.firstIndex(of: heroPage) ?? 0
    }

    private func heroCarouselPageForOutfitFullscreenIndex(hasCollage: Bool, hasWorn: Bool, fsIndex: Int) -> Int {
        let slots = outfitFullscreenHeroPages(hasCollage: hasCollage, hasWorn: hasWorn)
        guard fsIndex >= 0, fsIndex < slots.count else { return 0 }
        return slots[fsIndex]
    }

    private func outfitFullscreenSelectedPageIndexBinding(collage: UIImage?, worn: UIImage?) -> Binding<Int> {
        let hasCollage = collage != nil
        let hasWorn = worn != nil
        return Binding(
            get: {
                self.outfitFullscreenIndexForHero(
                    hasCollage: hasCollage,
                    hasWorn: hasWorn,
                    heroPage: self.heroCarouselPage
                )
            },
            set: { newIndex in
                let newHero = self.heroCarouselPageForOutfitFullscreenIndex(
                    hasCollage: hasCollage,
                    hasWorn: hasWorn,
                    fsIndex: newIndex
                )
                if self.heroCarouselPage != newHero {
                    self.heroCarouselPage = newHero
                }
                _ = self.outfit.image
                _ = self.outfit.wornImage
            }
        )
    }

    private func fullScreenOutfitImageView() -> some View {
        let collageUIImage = outfit.image.flatMap { UIImage(data: $0) }
        let wornUIImage = outfit.wornImage.flatMap { UIImage(data: $0) }
        return OutfitFullScreenView(
            collageImage: collageUIImage,
            wornImage: wornUIImage,
            selectedPageIndex: outfitFullscreenSelectedPageIndexBinding(collage: collageUIImage, worn: wornUIImage),
            isPresented: $isOutfitImageFullScreen
        )
    }

    private var outfitDisplayArea: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $heroCarouselPage) {
                Group {
                    if let imageData = outfit.image,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: screenWidth, height: screenWidth)
                            .clipped()
                            .onTapGesture {
                                isOutfitImageFullScreen = true
                            }
                    } else {
                        collageEmptyPlaceholder
                    }
                }
                .tag(0)

                Group {
                    if let wornData = outfit.wornImage,
                       let uiImage = UIImage(data: wornData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: screenWidth, height: screenWidth)
                            .clipped()
                            .onTapGesture {
                                isOutfitImageFullScreen = true
                            }
                    } else {
                        wornEmptyPlaceholder
                    }
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if (heroCarouselPage == 0 && outfit.image != nil)
                || (heroCarouselPage == 1 && outfit.wornImage != nil) {
                outfitDisplayAreaOptionsButton
            }
        }
        .frame(width: screenWidth, height: screenWidth)
        .onChange(of: heroCarouselPage) { _, _ in
            _ = outfit.image
            _ = outfit.wornImage
        }
    }

    private var collageEmptyPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "tshirt")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text("No collage yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Tap to edit outfit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isEditingOutfit = true
            }
    }

    /// Top-trailing control on the hero image area.
    private var outfitDisplayAreaOptionsButton: some View {
        Button {
            showOutfitHeroOptionsDialog = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("More options")
    }

    private var wornEmptyPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "person.and.background.striped.horizontal")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text("Tap to add a photo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showOutfitHeroOptionsDialog = true
            }
    }

    private func currentOutfitHeroUIImage() -> UIImage? {
        if heroCarouselPage == 0 {
            guard let data = outfit.image else { return nil }
            return UIImage(data: data)
        }
        guard let data = outfit.wornImage else { return nil }
        return UIImage(data: data)
    }

    private func presentOutfitHeroImageCropper() {
        guard let uiImage = currentOutfitHeroUIImage() else { return }
        outfitHeroCropSlot = heroCarouselPage == 0 ? .collage : .worn
        outfitHeroImageToEdit = uiImage
        outfitCropEditorSessionID = UUID()
        isOutfitImageCropperPresented = true
    }

    private func saveCollageOutfitImage(_ image: UIImage) {
        guard let data = image.processForStorage() else { return }
        outfit.image = data
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            if outfit.isDraft != true {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
        } catch {
            print("Failed to save outfit collage image: \(error.localizedDescription)")
        }
    }

    private func removeOutfitWornImage() {
        outfit.wornImage = nil
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            if outfit.isDraft != true {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
        } catch {
            print("Failed to remove worn outfit image: \(error.localizedDescription)")
        }
    }

    private func saveWornOutfitImage(_ image: UIImage) {
        guard let data = image.processForStorage() else { return }
        outfit.wornImage = data
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            if outfit.isDraft != true {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
        } catch {
            print("Failed to save worn outfit image: \(error.localizedDescription)")
        }
    }

    private func shareOutfitImage() {
        let imageData: Data?
        if heroCarouselPage == 0 {
            imageData = outfit.image
        } else {
            imageData = outfit.wornImage
        }
        guard let imageData = imageData,
              let image = UIImage(data: imageData) else { return }

        if let name = outfit.name, !name.isEmpty {
            shareItems = [name, image]
        } else {
            shareItems = [image]
        }
        showShareSheet = true
    }

    private func deleteOutfit() {
        softDelete(outfit)
        do {
            try viewContext.save()
            SyncService.shared.syncOutfitIfNeeded(outfit)
            dismiss()
        } catch {
            print("Failed to delete outfit: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Featured Items Toggle Row
    private func featuredItemsToggleRow() -> some View {
        Button { 
            withAnimation {
                isFeaturedItemsExpanded.toggle()
            }
        } label: {
            HStack {
                Text("Featured Items")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isFeaturedItemsExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
          //  .cornerRadius(8)
        }
    }
    
}
