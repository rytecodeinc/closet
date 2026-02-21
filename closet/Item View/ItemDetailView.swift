//
//  ItemDetailView.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//


import SwiftUI
import UIKit
import CoreData

struct ItemDetailView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var outfits: [Outfit] = []
    @State private var isEditingAttributes = false
    @State private var attributesSheet: AttributesSectionView.Sheet?
    @State private var isImageFullScreen = false
    @State private var isAttributesExpanded = true
    @State private var isSetsExpanded = true
    
    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedUIImage: UIImage?
    @State private var pendingImageType: ImageType? // Track which image type is being added/edited
    
    @State private var isCropperPresented = false
    @State private var imageToEdit: UIImage? // Store the image to edit directly
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showShareSelectionSheet = false
    @State private var selectedShareAttributes: Set<ShareableAttribute> = []
    @State private var pendingShareText: String?
    @State private var pendingShareImage: UIImage?
    @State private var selectedImageType: ImageType = .front
    @State private var showThumbnailActionSheet: Bool = false
    @State private var thumbnailActionSheetType: ImageType?
    @State private var showDeleteConfirmation = false
    @State private var showPairItemSelection = false
    
    // Computed property to get paired items, sorted by date/time added (oldest first)
    // Note: We use updatedAt as a proxy for when pairs were added, since Core Data doesn't
    // track relationship creation timestamps. When a pair is added, both items get updatedAt set.
    // We use createdAt as a tiebreaker to ensure stable sorting.
    private var pairedItems: [Item] {
        if let pairedItemsSet = item.pairedItems as? Set<Item> {
            return Array(pairedItemsSet).sorted { item1, item2 in
                // Primary sort: updatedAt ascending (oldest first)
                // If updatedAt is nil, treat as oldest (put at beginning)
                let date1 = item1.updatedAt ?? Date.distantPast
                let date2 = item2.updatedAt ?? Date.distantPast
                
                if date1 != date2 {
                    return date1 < date2
                }
                
                // Tiebreaker: createdAt ascending (older items first if updatedAt is the same)
                let created1 = item1.createdAt ?? Date.distantPast
                let created2 = item2.createdAt ?? Date.distantPast
                
                if created1 != created2 {
                    return created1 < created2
                }
                
                // Final tiebreaker: Use item ID for stable sorting
                let id1 = item1.id?.uuidString ?? ""
                let id2 = item2.id?.uuidString ?? ""
                return id1 < id2
            }
        }
        return []
    }
    
    enum ImageType {
        case front
        case back
        case worn
    }
    
    private func initializeSelectedImageType() {
        // Default to front if it exists, otherwise try back, then worn
        let photos = item.photos as? Set<Photo> ?? []
        if photos.contains(where: { $0.type == "front" || ($0.isPrimary && $0.type == nil) }) {
            selectedImageType = .front
        } else if photos.contains(where: { $0.type == "back" }) {
            selectedImageType = .back
        } else if photos.contains(where: { $0.type == "worn" }) {
            selectedImageType = .worn
        } else {
            selectedImageType = .front
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                List {
                    // Image Gallery Section
                    Section {
                        // Large primary image display
                        itemImageDisplay()
                        
                        // Row of 3 square images
                        imageThumbnailRow()
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listRowSeparator(.hidden)
                    .listSectionSpacing(0)
                    
                    
                    // ATTRIBUTES Section
                    Section {
                        if isAttributesExpanded {
                            AttributesSectionView(item: item, activeSheet: $attributesSheet)
                                .transition(.opacity.combined(with: .slide))
                                .listRowInsets(EdgeInsets(top: 05, leading: 20, bottom: 05, trailing: 20))
                        }
                    } header: {
                        HStack {
                            Text("ATTRIBUTES")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: isAttributesExpanded ? "minus" : "plus")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isAttributesExpanded.toggle()
                            }
                        }
                    }
                    //  .listRowInsets(EdgeInsets(.zero))
                    
                    // Show Sets section only if there are paired items
                    if !pairedItems.isEmpty {
                        Section {
                            if isSetsExpanded {
                                SetsSection(pairedItems: pairedItems)
                            }
                        } header: {
                            HStack {
                                Text("PAIRS")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: isSetsExpanded ? "minus" : "plus")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    isSetsExpanded.toggle()
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(.zero))
                        .listSectionSpacing(0)
                        .padding(.horizontal)
                    }
                    
                    // Show outfits section only if there are results
                    if !outfits.isEmpty {
                        Section {
                            FeaturedOutfitsSection(outfits: outfits)
                        } header: {
                            HStack {
                                Text("FEATURED OUTFITS")
                                    .fontWeight(.semibold)
                                Spacer()
                                NavigationLink(destination: AllOutfitsGridView(item: item)) {
                                    Image(systemName: "arrow.right")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(.zero))
                     //   .listRowSeparator(.hidden)
                        .listSectionSpacing(0)
                        .padding(.horizontal)
                    }
                }
                .listStyle(.plain)
               // .listSectionSpacing(.compact)
            }
        }
        .sheet(item: $attributesSheet) { $0.destination(for: item) }
        .onAppear {
            fetchOutfits()
            initializeSelectedImageType()
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Add to or Remove from Wardrobe button
                    Button {
                        attributesSheet = .wardrobe
                    } label: {
                        Label("Manage Wardrobes", systemImage: "hanger")
                    }
                    
                    // Favorite button - first option
                    Button {
                        toggleFavorite()
                    } label: {
                        Label(
                            item.isFavorite ? "Remove Favorite" : "Favorite Item",
                            systemImage: item.isFavorite ? "heart.slash" : "heart"
                        )
                    }
                    
                    // Share button - only show if front image exists
                    if let frontImage = getImage(for: .front) {
                        Button {
                            // Initialize with defaults if they exist, otherwise all available attributes
                            let available = getAvailableAttributes()
                            let defaults = DefaultShareAttributes.load().intersection(available)
                            selectedShareAttributes = defaults.isEmpty ? available : defaults
                            showShareSelectionSheet = true
                        } label: {
                            Label("Share Item", systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    // Pair Item button
                    Button {
                        showPairItemSelection = true
                    } label: {
                        Label(pairedItems.isEmpty ? "Pair Item" : "Manage Pairs", systemImage: "link")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Item", systemImage: "trash")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }

            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(
                image: $selectedUIImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let newImage = image, let imageType = pendingImageType {
                    switch imageType {
                    case .front:
                        replaceFrontImage(with: newImage)
                    case .back:
                        replaceBackImage(with: newImage)
                    case .worn:
                        replaceWornImage(with: newImage)
                    }
                    pendingImageType = nil
                }
                isImagePickerPresented = false
            }
        }
        .sheet(isPresented: $isCropperPresented) {
            if let imageType = pendingImageType, let image = imageToEdit {
                NavigationView {
                    ImageCropperView(
                        originalImage: image,
                        onCrop: { croppedImage in
                            switch imageType {
                            case .front:
                                replaceFrontImage(with: croppedImage)
                            case .back:
                                replaceBackImage(with: croppedImage)
                            case .worn:
                                replaceWornImage(with: croppedImage)
                            }
                            pendingImageType = nil
                            imageToEdit = nil
                        }, isEditing: true
                    )
                }
            } else {
                Text("No image found to edit.")
                    .padding()
            }
        }
        .sheet(isPresented: $showShareSelectionSheet, onDismiss: {
            // When selection sheet dismisses, check if we should show share sheet
            if let shareText = pendingShareText, let image = pendingShareImage {
                shareItems = [shareText, image]
                pendingShareText = nil
                pendingShareImage = nil
                // Small delay to ensure sheet is fully dismissed
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    showShareSheet = true
                }
            }
        }) {
            if let frontImage = getImage(for: .front) {
                ShareSelectionView(
                    item: item,
                    selectedAttributes: $selectedShareAttributes,
                    onShare: { shareText in
                        pendingShareText = shareText
                        pendingShareImage = frontImage
                        showShareSelectionSheet = false
                    }
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            let isWishlist = (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
            if isWishlist {
                moveToClosetButton()
                    .background(Color(UIColor.systemBackground))
                // .shadow(radius: 5)
            }
                
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isImageFullScreen) {
            fullScreenImageView()
        }
        .overlay {
            if showShareSheet {
                ActivityViewController(activityItems: shareItems, isPresented: $showShareSheet)
                    .frame(width: 0, height: 0)
            }
        }
        .alert("Delete Item", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("Delete this item from all wardrobes? This action cannot be undone.")
        }
        .sheet(isPresented: $showPairItemSelection) {
            PairItemSelectionView(item: item)
        }
    }
    
    // MARK: - Edit Button (deprecated, using presentCropperForImage instead)


    // MARK: - Replace Image Functions
    private func replaceFrontImage(with image: UIImage) {
        // Remove existing front photo (either type="front" or isPrimary with no type)
        let photos = item.photos as? Set<Photo> ?? []
        if let existingFront = photos.first(where: { $0.type == "front" || ($0.isPrimary && $0.type == nil) }) {
            viewContext.delete(existingFront)
        }

        // Process and compress image
        let processedData = image.processForStorage()
        
        // Create and assign new photo
        let newPhoto = Photo(context: viewContext)
        newPhoto.id = UUID()
        newPhoto.data = processedData
        newPhoto.thumbnailData = image.generateThumbnail()
        newPhoto.type = "front"
        newPhoto.isPrimary = true // Front images are primary by default
        newPhoto.item = item
        
        // Set updatedAt on item since we're modifying it
        setUpdatedAt(item)

        do {
            try viewContext.save()
            print("✅ Replaced front photo.")
            selectedImageType = .front
            
            // Trigger automatic sync for the modified item
            SyncService.shared.syncItemIfNeeded(item)
        } catch {
            print("❌ Failed to save new photo: \(error.localizedDescription)")
        }
    }
    
    private func replaceBackImage(with image: UIImage) {
        // Remove existing back photo
        if let existingBack = (item.photos as? Set<Photo>)?.first(where: { $0.type == "back" }) {
            viewContext.delete(existingBack)
        }

        // Process and compress image
        let processedData = image.processForStorage()
        
        // Create and assign new photo
        let newPhoto = Photo(context: viewContext)
        newPhoto.id = UUID()
        newPhoto.data = processedData
        newPhoto.thumbnailData = image.generateThumbnail()
        newPhoto.type = "back"
        newPhoto.isPrimary = false
        newPhoto.item = item
        
        // Set updatedAt on item since we're modifying it
        setUpdatedAt(item)

        do {
            try viewContext.save()
            print("✅ Replaced back photo.")
            selectedImageType = .back
            
            // Trigger automatic sync for the modified item
            SyncService.shared.syncItemIfNeeded(item)
        } catch {
            print("❌ Failed to save new photo: \(error.localizedDescription)")
        }
    }
    
    private func replaceWornImage(with image: UIImage) {
        // Remove existing worn photo
        if let existingWorn = (item.photos as? Set<Photo>)?.first(where: { $0.type == "worn" }) {
            viewContext.delete(existingWorn)
        }

        // Process and compress image
        let processedData = image.processForStorage()
        
        // Create and assign new photo
        let newPhoto = Photo(context: viewContext)
        newPhoto.id = UUID()
        newPhoto.data = processedData
        newPhoto.thumbnailData = image.generateThumbnail()
        newPhoto.type = "worn"
        newPhoto.isPrimary = false
        newPhoto.item = item
        
        // Set updatedAt on item since we're modifying it
        setUpdatedAt(item)

        do {
            try viewContext.save()
            print("✅ Replaced worn photo.")
            selectedImageType = .worn
            
            // Trigger automatic sync for the modified item
            SyncService.shared.syncItemIfNeeded(item)
        } catch {
            print("❌ Failed to save new photo: \(error.localizedDescription)")
        }
    }

    private func deleteImage(type: ImageType) {
        let photos = item.photos as? Set<Photo> ?? []
        let photoToDelete: Photo?
        
        switch type {
        case .front:
            photoToDelete = photos.first(where: { $0.type == "front" || ($0.isPrimary && $0.type == nil) })
        case .back:
            photoToDelete = photos.first(where: { $0.type == "back" })
        case .worn:
            photoToDelete = photos.first(where: { $0.type == "worn" })
        }
        
        if let photo = photoToDelete {
            viewContext.delete(photo)
            
            // Set updatedAt on item since we're modifying it
            setUpdatedAt(item)
            
            do {
                try viewContext.save()
                print("✅ Deleted \(placeholderText(for: type)) photo.")
                // Reset to front if we deleted the currently selected image
                if selectedImageType == type {
                    selectedImageType = .front
                }
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to delete photo: \(error.localizedDescription)")
            }
        }
    }


    // MARK: - Image Display
    
    private func fullScreenImageView() -> some View {
        let frontImage = getImage(for: .front)
        let backImage = getImage(for: .back)
        let wornImage = getImage(for: .worn)
        
        // Calculate initial index based on selected image type
        // Images are always in order: front, back, worn (if available)
        var initialIndex = 0
        switch selectedImageType {
        case .front:
            initialIndex = 0
        case .back:
            initialIndex = frontImage != nil ? 1 : 0
        case .worn:
            var index = 0
            if frontImage != nil { index += 1 }
            if backImage != nil { index += 1 }
            initialIndex = index
        }
        
        return ItemFullScreenView(
            frontImage: frontImage,
            backImage: backImage,
            wornImage: wornImage,
            initialIndex: initialIndex,
            isPresented: $isImageFullScreen
        )
    }
    
    private func itemImageDisplay() -> some View {
        // Try to get the selected image, fall back to front if not available
        var displayImage = getImage(for: selectedImageType)
        if displayImage == nil && selectedImageType != .front {
            displayImage = getImage(for: .front)
        }
        
        return Group {
            if let uiImage = displayImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width)
                    .clipped()
                    .onTapGesture { isImageFullScreen = true }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width)
                    .foregroundColor(.gray)
                    .clipped()
            }
        }
    }
    
    private func shareActiveImage() {
        shareImage(type: selectedImageType)
    }
    
    private func shareImage(type: ImageType) {
        let image = getImage(for: type)
        if let image = image {
            // Create share text: item name, or brand + category if name is nil
            var shareText: String?
            
            if let name = item.name, !name.isEmpty {
                shareText = name
            } else {
                var components: [String] = []
                if let brandName = item.brand?.name, !brandName.isEmpty {
                    components.append(brandName)
                }
                if let categoryName = item.category?.name, !categoryName.isEmpty {
                    if let subcategoryName = item.subcategory?.name, !subcategoryName.isEmpty {
                        components.append("\(categoryName) • \(subcategoryName)")
                    } else {
                        components.append(categoryName)
                    }
                }
                if !components.isEmpty {
                    shareText = components.joined(separator: " ")
                }
            }
            
            // Add text and image to share items
            if let text = shareText {
                shareItems = [text, image]
            } else {
                shareItems = [image]
            }
            showShareSheet = true
        }
    }
    
    private func imageThumbnailRow() -> some View {
        let size: CGFloat = (UIScreen.main.bounds.width - 6) / 3
        
        return HStack(spacing: 2) {
            // Front image thumbnail with menu
            thumbnailMenu(for: .front) {
                imageThumbnail(type: .front, image: getImage(for: .front), size: size)
                    .contentShape(Rectangle())
            }
            
            // Back image thumbnail with menu
            thumbnailMenu(for: .back) {
                imageThumbnail(type: .back, image: getImage(for: .back), size: size)
                    .contentShape(Rectangle())
            }
            
            // Worn image thumbnail with menu
            thumbnailMenu(for: .worn) {
                imageThumbnail(type: .worn, image: getImage(for: .worn), size: size)
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func imageThumbnail(type: ImageType, image: UIImage?, size: CGFloat) -> some View {
        let isSelected = selectedImageType == type
        
        return ZStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // If already selected, show action sheet; otherwise select it
                        if selectedImageType == type {
                            showThumbnailActionSheet(for: type)
                        } else {
                            withAnimation {
                                selectedImageType = type
                            }
                            // Ensure photos relationship is loaded when switching images
                            _ = item.photos
                        }
                    }
                
            } else {
                // Placeholder with text
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .foregroundColor(.gray.opacity(0.5))
                                .font(.system(size: 20))
                            Text(placeholderText(for: type))
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    )
                    .overlay(
                        Rectangle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
                    .onTapGesture {
                        // If no image, open image picker
                        presentImagePicker(for: type)
                    }
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func thumbnailMenu<Content: View>(for type: ImageType, @ViewBuilder content: () -> Content) -> some View {
        content()
    }
    
    private func placeholderText(for type: ImageType) -> String {
        switch type {
        case .front:
            return "Front"
        case .back:
            return "Back"
        case .worn:
            return "Worn"
        }
    }
    
    private func showThumbnailActionSheet(for type: ImageType) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Camera option
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Retake Photo", style: .default) { _ in
                pendingImageType = type
                imagePickerSource = .camera
                isImagePickerPresented = true
            })
        }
        
        // Replace from library
        alert.addAction(UIAlertAction(title: "Replace from Library", style: .default) { _ in
            pendingImageType = type
            imagePickerSource = .photoLibrary
            isImagePickerPresented = true
        })
        
        // Edit option (only if image exists)
        if getImage(for: type) != nil {
            alert.addAction(UIAlertAction(title: "Edit Image", style: .default) { _ in
                presentCropperForImage(type: type)
            })
            
            // Share Image option (only if image exists)
            alert.addAction(UIAlertAction(title: "Share Image", style: .default) { _ in
                shareImage(type: type)
            })
        }
        
        // Remove Image option (only for back and worn, not front)
        if (type == .back || type == .worn) && getImage(for: type) != nil {
            alert.addAction(UIAlertAction(title: "Remove Image", style: .destructive) { _ in
                deleteImage(type: type)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // For iPad
            if let popover = alert.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func presentImagePicker(for type: ImageType) {
        pendingImageType = type
        
        // Show action sheet to choose camera or library
        let alert = UIAlertController(title: "Add \(placeholderText(for: type)) Photo", message: nil, preferredStyle: .actionSheet)
        
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in
                imagePickerSource = .camera
                isImagePickerPresented = true
            })
        }
        
        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default) { _ in
            imagePickerSource = .photoLibrary
            isImagePickerPresented = true
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            pendingImageType = nil
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // For iPad
            if let popover = alert.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func presentCropperForImage(type: ImageType) {
        // Refresh the item to ensure photos relationship is up to date
        viewContext.refresh(item, mergeChanges: true)
        
        if let image = getImage(for: type) {
            // Store both the type and image we're editing
            pendingImageType = type
            imageToEdit = image
            isCropperPresented = true
        }
    }
    
    // MARK: - Helper Functions
    
    private func getImage(for type: ImageType) -> UIImage? {
        // Ensure we have the latest photos by accessing the relationship
        // Force fault loading by accessing the relationship and converting to array
        guard let photosSet = item.photos as? Set<Photo> else {
            return nil
        }
        // Convert to array to ensure all faults are loaded
        let photos = Array(photosSet)
        
        // Also ensure each photo's data is loaded by accessing the type property
        // This helps with Core Data faulting
        _ = photos.compactMap { $0.type }
        
        switch type {
        case .front:
            // Look for type="front" first, then fall back to isPrimary (for backward compatibility)
            if let frontPhoto = photos.first(where: { $0.type == "front" }) {
                return UIImage(data: frontPhoto.data ?? Data())
            } else if let primaryPhoto = photos.first(where: { $0.isPrimary && ($0.type == nil || $0.type == "") }) {
                    return UIImage(data: primaryPhoto.data ?? Data())
                }
                return nil
        case .back:
            if let backPhoto = photos.first(where: { $0.type == "back" }) {
                return UIImage(data: backPhoto.data ?? Data())
            }
            return nil
        case .worn:
            if let wornPhoto = photos.first(where: { $0.type == "worn" }) {
                return UIImage(data: wornPhoto.data ?? Data())
            }
            return nil
        }
    }
    
    // MARK: - Header Image (deprecated, keeping for reference)

    private func itemImageHeader() -> some View {
        ZStack {
            // Get front photo data if available
            let displayImage = getImage(for: .front)
            
            if let uiImage = displayImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .onTapGesture { isImageFullScreen = true }
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.gray)
                    .clipped()
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            }

        }
    }

    
    // MARK: - Move to Closet Button
    private func moveToClosetButton() -> some View {
        SlideToConfirmButton {
            if let closetWardrobe = fetchWardrobe(type: "closet") {
                // Safely cast wardrobes to a mutable set
                var currentWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
                currentWardrobes.insert(closetWardrobe)
                item.wardrobes = currentWardrobes as NSSet
                
                let now = Date()
                item.timestamp = now
                item.createdAt = now
                
                do {
                    try viewContext.save()
                } catch {
                    print("Failed to save item: \(error)")
                }
            }
        }
        .transition(.move(edge: .bottom))
        .padding(.horizontal)
    }

    
    private func fetchWardrobe(type: String) -> Wardrobe? {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", type)
        return try? viewContext.fetch(request).first
    }
    
    private func fetchOutfits() {
        // Only fetch if the object has been saved and has an ID
        guard !item.objectID.isTemporaryID else {
            outfits = []
            return
        }
        
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        // Exclude drafts and soft-deleted outfits from outfit listings
        let basePredicate = NSPredicate(format: "ANY items == %@ AND isDraft != YES", item)
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [basePredicate, softDeleteFilter])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: false)]
        
        do {
            outfits = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch outfits: \(error.localizedDescription)")
            outfits = []
        }
    }
    
    
    struct SlideToConfirmButton: View {
        var action: () -> Void
        var labelText: String = "Swipe to Move to Closet"
        
        @State private var dragOffset: CGFloat = 0
        @State private var completed: Bool = false
        
        let thumbSize = CGSize(width: 60, height: 40)
        let trackHeight: CGFloat = 50
        
        var body: some View {
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                
                ZStack {
                    // Background track
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: trackHeight)
                    
                    // Instruction Text
                    Text(completed ? "Moved!" : labelText)
                        .foregroundColor(.blue)
                        .font(.footnote)
                        .opacity(Double(1.0 - (dragOffset / (trackWidth - thumbSize.width))))
                        .animation(.easeInOut, value: dragOffset)
                    
                    // Draggable Thumb
                    HStack {
                        ZStack {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: thumbSize.width, height: thumbSize.height)
                                .shadow(radius: 2)
                            
                            Image(systemName: completed ? "checkmark" : "arrow.right")
                                .foregroundColor(.blue)
                        }
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    if !completed {
                                        let maxOffset = trackWidth - thumbSize.width
                                        dragOffset = min(max(0, gesture.translation.width), maxOffset)
                                    }
                                }
                                .onEnded { _ in
                                    let maxOffset = trackWidth - thumbSize.width
                                    if dragOffset > maxOffset * 0.85 {
                                        // Confirmed
                                        dragOffset = maxOffset
                                        completed = true
                                        action()
                                    } else {
                                        // Reset
                                        dragOffset = 0
                                    }
                                }
                        )
                        
                        Spacer()
                    }
                }
            }
            .frame(height: trackHeight)
            .padding(.horizontal)
        }
    }

    func toggleFavorite() {
        item.isFavorite.toggle()
        
        // Set updatedAt on item since we're modifying it
        setUpdatedAt(item)
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    func deleteItem() {
        // Store the brand before deletion to check if cleanup is needed
        let itemBrand = item.brand
        
        // Soft delete the item (for sync)
        softDelete(item)

        do {
            try viewContext.save()
            
            // Trigger sync for the soft-deleted item
            SyncService.shared.syncItemIfNeeded(item)
            
            // Cleanup brand if it's now orphaned (has 0 items)
            if let brand = itemBrand {
                cleanupBrandIfOrphaned(brand)
            }
            
            dismiss() // Go back after deletion
        } catch {
            // Handle the error (e.g., log it or show alert)
            print("Failed to delete item: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup Orphaned Brand
    private func cleanupBrandIfOrphaned(_ brand: Brand) {
        // Refresh the brand to get current item count
        viewContext.refresh(brand, mergeChanges: true)
        
        // Check if brand has any items
        if let items = brand.items as? Set<Item>, items.isEmpty {
            viewContext.delete(brand)
            do {
                try viewContext.save()
                print("✅ Cleaned up orphaned brand: \(brand.name ?? "unknown")")
            } catch {
                print("❌ Failed to cleanup orphaned brand: \(error)")
            }
        }
    }
    
    private func SearchWithGoogleLens() {
        guard let image = getImage(for: .front) else {
            print("❌ No front image found")
            return
        }
        
        // Save image to temporary directory
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "lens_search_\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to JPEG")
            return
        }
        
        do {
            try jpegData.write(to: fileURL)
            
            // Try Google app first, then fall back to browser
            if let googleLensURL = URL(string: "googleapp://lens") {
                if UIApplication.shared.canOpenURL(googleLensURL) {
                    // Copy image to pasteboard so Google Lens can access it
                    UIPasteboard.general.image = image
                    UIApplication.shared.open(googleLensURL)
                } else {
                    // Fallback: Open Google Lens web version
                    openGoogleLensWeb(with: image)
                }
            }
        } catch {
            print("❌ Failed to save image: \(error.localizedDescription)")
        }
    }
    
    private func openGoogleLensWeb(with image: UIImage) {
        // Copy image to pasteboard for potential paste
        UIPasteboard.general.image = image
        
        // Open Google Lens web interface
        if let url = URL(string: "https://lens.google.com/") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Share Functions
    private func getAvailableAttributes() -> Set<ShareableAttribute> {
        var available: Set<ShareableAttribute> = []
        
        if let name = item.name, !name.isEmpty {
            available.insert(.name)
        }
        if item.category != nil {
            available.insert(.category)
        }
        if item.brand != nil {
            available.insert(.brand)
        }
        if item.size != nil {
            available.insert(.size)
        }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
            available.insert(.color)
        }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
            available.insert(.season)
        }
        if let location = item.location?.name, !location.isEmpty {
            available.insert(.location)
        }
        if item.price != nil {
            available.insert(.price)
        }
        // Use primitiveValue to properly check optional scalar types
        if item.primitiveValue(forKey: "minTemperature") != nil && item.primitiveValue(forKey: "maxTemperature") != nil {
            available.insert(.weather)
        }
        // Use primitiveValue to properly check optional scalar types
        if item.primitiveValue(forKey: "weight") != nil {
            available.insert(.weight)
        }
        if let links = item.links as? Set<Link>, !links.isEmpty {
            available.insert(.link)
        }
        if let tags = item.tags as? Set<Tag>, !tags.isEmpty {
            available.insert(.tag)
        }
        if let notes = item.notes, !notes.isEmpty {
            available.insert(.notes)
        }
        
        return available
    }
}

// MARK: - ShareableAttribute Enum
enum ShareableAttribute: String, CaseIterable, Identifiable {
    case name
    case category
    case brand
    case size
    case color
    case season
    case location
    case price
    case weather
    case weight
    case link
    case tag
    case notes
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        case .category: return "Category"
        case .brand: return "Brand"
        case .size: return "Size"
        case .color: return "Colors"
        case .season: return "Seasons"
        case .location: return "Location"
        case .price: return "Price"
        case .weather: return "Weather"
        case .weight: return "Weight"
        case .link: return "Links"
        case .tag: return "Tags"
        case .notes: return "Notes"
        }
    }
}

// MARK: - Default Share Attributes
private struct DefaultShareAttributes {
    private static let userDefaultsKey = "defaultShareAttributes"
    
    static func save(_ attributes: Set<ShareableAttribute>) {
        let attributeStrings = attributes.map { $0.rawValue }
        UserDefaults.standard.set(attributeStrings, forKey: userDefaultsKey)
    }
    
    static func load() -> Set<ShareableAttribute> {
        guard let attributeStrings = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return []
        }
        return Set(attributeStrings.compactMap { ShareableAttribute(rawValue: $0) })
    }
    
    static func hasDefaults() -> Bool {
        return UserDefaults.standard.array(forKey: userDefaultsKey) != nil
    }
}

// MARK: - ShareSelectionView
struct ShareSelectionView: View {
    @ObservedObject var item: Item
    @Binding var selectedAttributes: Set<ShareableAttribute>
    let onShare: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private let currencySymbol = Locale.current.currencySymbol ?? "$"
    
    var availableAttributes: Set<ShareableAttribute> {
        var available: Set<ShareableAttribute> = []
        
        if let name = item.name, !name.isEmpty {
            available.insert(.name)
        }
        if item.category != nil {
            available.insert(.category)
        }
        if item.brand != nil {
            available.insert(.brand)
        }
        if item.size != nil {
            available.insert(.size)
        }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
            available.insert(.color)
        }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
            available.insert(.season)
        }
        if let location = item.location?.name, !location.isEmpty {
            available.insert(.location)
        }
        if item.price != nil {
            available.insert(.price)
        }
        // Use primitiveValue to properly check optional scalar types
        if item.primitiveValue(forKey: "minTemperature") != nil && item.primitiveValue(forKey: "maxTemperature") != nil {
            available.insert(.weather)
        }
        // Use primitiveValue to properly check optional scalar types
        if item.primitiveValue(forKey: "weight") != nil {
            available.insert(.weight)
        }
        if let links = item.links as? Set<Link>, !links.isEmpty {
            available.insert(.link)
        }
        if let tags = item.tags as? Set<Tag>, !tags.isEmpty {
            available.insert(.tag)
        }
        if let notes = item.notes, !notes.isEmpty {
            available.insert(.notes)
        }
        
        return available
    }
    
    var allSelected: Bool {
        !availableAttributes.isEmpty && availableAttributes.isSubset(of: selectedAttributes)
    }
    
    var defaultAttributes: Set<ShareableAttribute> {
        DefaultShareAttributes.load()
    }
    
    var hasDefaultAttributes: Bool {
        DefaultShareAttributes.hasDefaults()
    }
    
    var isDefaultSelected: Bool {
        guard hasDefaultAttributes else { return false }
        let defaults = defaultAttributes.intersection(availableAttributes)
        return !defaults.isEmpty && defaults == selectedAttributes.intersection(availableAttributes)
    }
    
    var matchesDefaultAttributes: Bool {
        guard hasDefaultAttributes else { return false }
        let defaults = defaultAttributes.intersection(availableAttributes)
        return defaults == selectedAttributes.intersection(availableAttributes)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { allSelected },
                        set: { newValue in
                            if newValue {
                                selectedAttributes = availableAttributes
                            } else {
                                selectedAttributes.removeAll()
                            }
                        }
                    )) {
                        Text("All Attributes")
                           // .fontWeight(.semibold)
                            .foregroundColor(.black)
                    }
                    
                    if hasDefaultAttributes {
                        Toggle(isOn: Binding(
                            get: { isDefaultSelected },
                            set: { newValue in
                                let defaults = defaultAttributes.intersection(availableAttributes)
                                if newValue {
                                    selectedAttributes = defaults
                                } else {
                                    selectedAttributes.removeAll()
                                }
                            }
                        )) {
                            Text("Default Attributes")
                              //  .fontWeight(.semibold)
                                .foregroundColor(.black)
                        }
                    }
                }
                
                Section {
                    ForEach(ShareableAttribute.allCases) { attribute in
                        if availableAttributes.contains(attribute) {
                            Toggle(isOn: Binding(
                                get: { selectedAttributes.contains(attribute) },
                                set: { newValue in
                                    if newValue {
                                        selectedAttributes.insert(attribute)
                                    } else {
                                        selectedAttributes.remove(attribute)
                                    }
                                }
                            )) {
                                Text(attribute.displayName)
                                    .foregroundColor(.black)
                            }
                        }
                    }
                } header: {
                    Text("Attributes")
                } footer: {
                    HStack {
                        Spacer()
                        if selectedAttributes.isEmpty || (hasDefaultAttributes && matchesDefaultAttributes) {
                            Button {
                                if !selectedAttributes.isEmpty {
                                    DefaultShareAttributes.save(selectedAttributes)
                                }
                            } label: {
                                Text("Save as Default")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .padding(.vertical, 7)
                            .foregroundColor(.gray)
                            .disabled(true)
                        } else {
                            Button {
                                DefaultShareAttributes.save(selectedAttributes)
                            } label: {
                                Text("Save as Default")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Select Attributes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Share") {
                        let shareText = generateShareText(from: selectedAttributes)
                        onShare(shareText)
                    }
                    .disabled(selectedAttributes.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func generateShareText(from attributes: Set<ShareableAttribute>) -> String {
        var lines: [String] = []
        
        if attributes.contains(.name), let name = item.name, !name.isEmpty {
            lines.append(name)
        }
        
        if attributes.contains(.category) {
            if let categoryName = item.category?.name {
                if let subName = item.subcategory?.name {
                    lines.append("Category: \(categoryName) • \(subName)")
                } else {
                    lines.append("Category: \(categoryName)")
                }
            }
        }
        
        if attributes.contains(.brand), let brand = item.brand?.name {
            lines.append("Brand: \(brand)")
        }
        
        if attributes.contains(.size), let size = item.size?.value {
            lines.append("Size: \(size)")
        }
        
        if attributes.contains(.color), let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
            let colorNames = colors.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Colors: \(colorNames)")
        }
        
        if attributes.contains(.season), let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
            let seasonNames = seasons.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Seasons: \(seasonNames)")
        }
        
        if attributes.contains(.location), let location = item.location?.name {
            lines.append("Location: \(location)")
        }
        
        if attributes.contains(.price), let price = item.price {
            let currencySymbol = (price.currency != nil)
                ? Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: price.currency!]))
                    .currencySymbol ?? "$"
                : Locale.current.currencySymbol ?? "$"
            if let amount = price.amount {
                let formattedAmount = NumberFormatter.currency2.string(from: amount) ?? "0.00"
                lines.append("Price: \(currencySymbol)\(formattedAmount)")
            }
        }
        
        if attributes.contains(.weather),
           let minC = item.primitiveValue(forKey: "minTemperature") as? Double,
           let maxC = item.primitiveValue(forKey: "maxTemperature") as? Double {
            let unit = (item.primitiveValue(forKey: "temperatureUnit") as? String) ?? "C"
            let symbol = unit == "C" ? "°C" : "°F"
            let displayMin = unit == "C" ? Int(minC) : Int((minC * 9/5) + 32)
            let displayMax = unit == "C" ? Int(maxC) : Int((maxC * 9/5) + 32)
            lines.append("Weather: \(displayMin) to \(displayMax)\(symbol)")
        }
        
        if attributes.contains(.weight),
           let weightKg = item.primitiveValue(forKey: "weight") as? Double {
            let unit = (item.primitiveValue(forKey: "weightUnit") as? String) ?? "kg"
            let symbol = unit == "kg" ? "kg" : "lbs"
            let displayWeight = unit == "kg" ? weightKg : weightKg * 2.20462
            lines.append("Weight: \(String(format: "%.1f", displayWeight)) \(symbol)")
        }
        
        if attributes.contains(.link), let links = item.links as? Set<Link>, !links.isEmpty {
            let linkStrings = links.compactMap { link -> String? in
                if let url = link.url?.absoluteString {
                    return url
                }
                return nil
            }
            if !linkStrings.isEmpty {
                lines.append("Links: \(linkStrings.joined(separator: ", "))")
            }
        }
        
        if attributes.contains(.tag), let tags = item.tags as? Set<Tag>, !tags.isEmpty {
            let tagNames = tags.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Tags: \(tagNames)")
        }
        
        if attributes.contains(.notes), let notes = item.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - ActivityViewController Wrapper
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && uiViewController.presentedViewController == nil {
            let activityVC = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: applicationActivities
            )
            
            // Configure for iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = uiViewController.view
                popover.sourceRect = CGRect(x: uiViewController.view.bounds.midX, y: uiViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            // Dismiss handler
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                DispatchQueue.main.async {
                    isPresented = false
                }
            }
            
            uiViewController.present(activityVC, animated: true)
        }
    }
}




