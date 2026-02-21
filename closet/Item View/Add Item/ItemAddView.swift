//
//  ItemAddViewModel.swift
//  closet
//
//  Created by Dan Warner on 8/16/25.
//


import SwiftUI
import UIKit
import CoreData

// MARK: - ItemAddView (init with parentContext; child ctx ready before body)
struct ItemAddView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: ItemAddViewModel
    @ObservedObject private var queueCoordinator: ImageQueueCoordinator
    
    @State private var attributesSheet: AttributesSectionView.Sheet?
    
    // Image handling
    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedUIImage: UIImage?
    @State private var pendingImageType: ImageType? // Track which image type is being added/edited
    @State private var imageToEdit: UIImage? // Store the image to edit directly
    @State private var shouldNavigateToCropper = false // For navigation to cropper
    @State private var selectedImageType: ImageType = .front
    
    enum ImageType {
        case front
        case back
        case worn
    }

    // Save warning
    @State private var showMissingWarning = false
    @State private var missingFieldsDescription = ""
    
    // Draft confirmation
    @State private var showingSaveDraftConfirmation = false
    @State private var showingDraftSaveAlert = false

    // Original init for backward compatibility (creates dummy coordinator)
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?, initialURL: URL? = nil, initialImage: UIImage? = nil) {
        _vm = StateObject(wrappedValue: ItemAddViewModel(parentContext: parentContext, selectedWardrobe: selectedWardrobe, initialURL: initialURL, initialImage: initialImage))
        _queueCoordinator = ObservedObject(wrappedValue: ImageQueueCoordinator())
    }
    
    // New init with queue coordinator
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?, queueCoordinator: ImageQueueCoordinator, initialURL: URL? = nil) {
        // Get initial image from cropped image if available
        let initialImage = queueCoordinator.nextCroppedImage
        _vm = StateObject(wrappedValue: ItemAddViewModel(parentContext: parentContext, selectedWardrobe: selectedWardrobe, initialURL: initialURL, initialImage: initialImage))
        _queueCoordinator = ObservedObject(wrappedValue: queueCoordinator)
    }

    var body: some View {
        
        List {
            // Image Gallery Section
            Section {
                VStack(spacing: 0) {
                    // Large primary image display
                    itemImageDisplay()
                }
                // Row of 3 square images
                imageThumbnailRow()
            }
                .listRowInsets(EdgeInsets(.zero))
                .listRowSeparator(.hidden)
            
            // ATTRIBUTES Section
            Section {
                AttributesSectionView(item: vm.draftItem, activeSheet: $attributesSheet)
                    .listRowInsets(EdgeInsets(top: 05, leading: 20, bottom: 05, trailing: 20))
            }
        }
        .sheet(item: $attributesSheet) { $0.destination(for: vm.draftItem) }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets())
        .navigationTitle(queueCoordinator.hasMore ? 
            "Add Item (\(queueCoordinator.remainingCount) remaining)" : 
            "Add Item")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(role: queueCoordinator.hasMore ? .destructive : .none) {
                    handleCancelTapped()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Cancel")
                    }
                    .foregroundColor(queueCoordinator.hasMore ? .red : .primary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    handleSaveTapped()
                }
                .bold()
                .disabled(getImage(for: .front) == nil)
            }
            
        }
        // Make the whole subtree use the child context
        .environment(\.managedObjectContext, vm.childContext)
        // Sheets below…

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
        .background {
            // Hidden NavigationLink for cropper (when editing images)
            NavigationLink(
                destination: Group {
                    if let imageType = pendingImageType, let image = imageToEdit {
                        ImageCropperView(
                            originalImage: image,
                            onCrop: { croppedImage in
                                // Update image - use async to ensure it completes
                                Task { @MainActor in
                                    switch imageType {
                                    case .front:
                                        await replaceFrontImageSync(with: croppedImage)
                                    case .back:
                                        await replaceBackImageSync(with: croppedImage)
                                    case .worn:
                                        await replaceWornImageSync(with: croppedImage)
                                    }
                                    
                                    // Reset state and pop navigation after image is updated
                                    pendingImageType = nil
                                    imageToEdit = nil
                                    shouldNavigateToCropper = false
                                }
                            },
                            isEditing: true
                        )
                        .navigationBarTitleDisplayMode(.inline)
                    } else {
                        Text("No image found to edit.")
                            .padding()
                    }
                }
                .onDisappear {
                    // Only reset navigation state if we're not in the middle of updating an image
                    // This prevents premature reset while image is being processed
                    if pendingImageType == nil {
                        shouldNavigateToCropper = false
                    }
                },
                isActive: $shouldNavigateToCropper
            ) {
                EmptyView()
            }
            .hidden()
        }
        .alert("Add Item?", isPresented: $showMissingWarning) {
            Button("Proceed", role: .none) {
                persistAndDismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You are saving with the following empty fields: \(missingFieldsDescription). You can fill them later in Item Details.")
        }
        .alert("Draft Saved", isPresented: $showingDraftSaveAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your item has been saved as a draft.")
        }
        .alert("Save as draft?", isPresented: $showingSaveDraftConfirmation) {
            Button("Yes") {
                saveDraft()
            }
            Button("No", role: .cancel) {
                // If queue is active and has more items, discard current and move to next
                if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                    discardCurrentAndMoveToNext()
                } else {
                    // Otherwise, discard and dismiss
                    vm.discard()
                    if queueCoordinator.isQueueActive {
                        queueCoordinator.clear()
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            initializeSelectedImageType()
            
            // Handle initial image if provided (from share sheet or queue)
            if let initialImage = vm.initialImage {
                print("📸 ItemAddView: Received initial cropped image from queue")
                replaceFrontImage(with: initialImage)
            } else {
                print("📸 ItemAddView: No initial image provided")
                /* Automatically show camera/library choice when no initial image
                if getImage(for: .front) == nil && !queueCoordinator.isQueueActive {
                    // Small delay to ensure view is fully presented
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        presentImagePicker(for: .front)
                    }
                }*/
            }
            
            // Handle initial URL if provided (from share sheet)
            if let initialURL = vm.initialURL {
                print("🔗 ItemAddView: Received initial URL from share sheet: \(initialURL)")
                Task {
                    await vm.extractAndApplyMetadata()
                }
            }
        }
        .overlay {
            if vm.isExtractingMetadata {
                ProgressView("Extracting product details...")
                    .padding()
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Image Display
    
    private func initializeSelectedImageType() {
        // Default to front if it exists, otherwise try back, then worn
        let photos = vm.draftItem.photos as? Set<Photo> ?? []
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
            } else {
                Button {
                    presentImagePicker(for: .front)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 40, weight: .semibold))
                        Text("Add Item Image")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func imageThumbnailRow() -> some View {
        let size: CGFloat = (UIScreen.main.bounds.width - 6) / 3
        
        return HStack(spacing: 2) {
            // Front image thumbnail
            thumbnailButton(for: .front) {
                imageThumbnail(type: .front, image: getImage(for: .front), size: size)
                    .contentShape(Rectangle())
            }
            
            // Back image thumbnail
            thumbnailButton(for: .back) {
                imageThumbnail(type: .back, image: getImage(for: .back), size: size)
                    .contentShape(Rectangle())
            }
            
            // Worn image thumbnail
            thumbnailButton(for: .worn) {
                imageThumbnail(type: .worn, image: getImage(for: .worn), size: size)
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func thumbnailButton<Content: View>(for type: ImageType, @ViewBuilder content: () -> Content) -> some View {
        content()
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
        // Fetch the image immediately and store it
        guard let image = getImage(for: type) else {
            print("⚠️ No image found for type \(type)")
            return
        }
        
        print("📸 Presenting cropper for \(type) with image size: \(image.size)")
        
        // Store both the type and the actual image
        pendingImageType = type
        imageToEdit = image
        
        // Navigate to cropper (same flow as initial image selection)
        shouldNavigateToCropper = true
    }
    
    // MARK: - Replace Image Functions
    private func replaceFrontImage(with image: UIImage) {
        // Remove existing front photo (either type="front" or isPrimary with no type)
        let photos = vm.draftItem.photos as? Set<Photo> ?? []
        if let existingFront = photos.first(where: { $0.type == "front" || ($0.isPrimary && $0.type == nil) }) {
            vm.childContext.delete(existingFront)
        }

        // Process image on background queue
        Task {
            let processedData = await processImageForStorage(image)
            
            // Analyze image with Vision for category suggestion (only if category not already set)
            if vm.draftItem.category == nil {
                print("🔍 Analyzing user-selected image with Vision for category classification...")
                do {
                    let visionResult = try await VisionAnalysisService.shared.analyzeCategory(from: image)
                    if let suggestedCategory = visionResult.suggestedCategory, visionResult.confidence >= 0.3 {
                        await MainActor.run {
                            vm.setCategory(name: suggestedCategory)
                            print("✅ Vision suggested category: \(suggestedCategory) (confidence: \(visionResult.confidence))")
                        }
                    } else if let suggestedCategory = visionResult.suggestedCategory {
                        // Still suggest even if confidence is lower (user can override)
                        await MainActor.run {
                            vm.setCategory(name: suggestedCategory)
                            print("⚠️ Vision suggested category with low confidence: \(suggestedCategory) (confidence: \(visionResult.confidence))")
                        }
                    }
                } catch {
                    print("⚠️ Vision analysis failed: \(error.localizedDescription)")
                    // Continue without Vision result
                }
            }
            
            await MainActor.run {
                // Create and assign new photo
                let newPhoto = Photo(context: vm.childContext)
                newPhoto.id = UUID()
                newPhoto.data = processedData
                newPhoto.thumbnailData = image.generateThumbnail()
                newPhoto.type = "front"
                newPhoto.isPrimary = true // Front images are primary by default
                newPhoto.item = vm.draftItem
                
                // CRITICAL: Update the item's updatedAt timestamp
                setUpdatedAt(vm.draftItem)
                
                // Refresh UI
                vm.photoRefreshToken = UUID()
                selectedImageType = .front
            }
        }
    }
    
    private func replaceBackImage(with image: UIImage) {
        // Remove existing back photo
        let photos = vm.draftItem.photos as? Set<Photo> ?? []
        if let existingBack = photos.first(where: { $0.type == "back" }) {
            vm.childContext.delete(existingBack)
        }

        // Process image on background queue
        Task {
            let processedData = await processImageForStorage(image)
            
            await MainActor.run {
                // Create and assign new photo
                let newPhoto = Photo(context: vm.childContext)
                newPhoto.id = UUID()
                newPhoto.data = processedData
                newPhoto.thumbnailData = image.generateThumbnail()
                newPhoto.type = "back"
                newPhoto.isPrimary = false
                newPhoto.item = vm.draftItem
                
                // CRITICAL: Update the item's updatedAt timestamp
                setUpdatedAt(vm.draftItem)
                
                // Refresh UI
                vm.photoRefreshToken = UUID()
                selectedImageType = .back
            }
        }
    }
    
    private func replaceWornImage(with image: UIImage) {
        // Remove existing worn photo
        let photos = vm.draftItem.photos as? Set<Photo> ?? []
        if let existingWorn = photos.first(where: { $0.type == "worn" }) {
            vm.childContext.delete(existingWorn)
        }

        // Process image on background queue
        Task {
            let processedData = await processImageForStorage(image)
            
            await MainActor.run {
                // Create and assign new photo
                let newPhoto = Photo(context: vm.childContext)
                newPhoto.id = UUID()
                newPhoto.data = processedData
                newPhoto.thumbnailData = image.generateThumbnail()
                newPhoto.type = "worn"
                newPhoto.isPrimary = false
                newPhoto.item = vm.draftItem
                
                // CRITICAL: Update the item's updatedAt timestamp
                setUpdatedAt(vm.draftItem)
                
                // Refresh UI
                vm.photoRefreshToken = UUID()
                selectedImageType = .worn
            }
        }
    }
    
    // Synchronous versions for editing (await the image update)
    private func replaceFrontImageSync(with image: UIImage) async {
        await MainActor.run {
            // Remove ALL existing front photos (there might be multiple if editing was done)
            let photos = vm.draftItem.photos as? Set<Photo> ?? []
            let photosToDelete = photos.filter { photo in
                photo.type == "front" || (photo.isPrimary && (photo.type == nil || photo.type == ""))
            }
            
            for photo in photosToDelete {
                // Remove from relationship first
                vm.draftItem.removeFromPhotos(photo)
                vm.childContext.delete(photo)
            }
        }

        // Process image
        let processedData = await processImageForStorage(image)
        
        // Analyze image with Vision for category suggestion (only if category not already set)
        if vm.draftItem.category == nil {
            print("🔍 Analyzing edited image with Vision for category classification...")
            do {
                let visionResult = try await VisionAnalysisService.shared.analyzeCategory(from: image)
                if let suggestedCategory = visionResult.suggestedCategory, visionResult.confidence >= 0.3 {
                    await MainActor.run {
                        vm.setCategory(name: suggestedCategory)
                        print("✅ Vision suggested category: \(suggestedCategory) (confidence: \(visionResult.confidence))")
                    }
                } else if let suggestedCategory = visionResult.suggestedCategory {
                    await MainActor.run {
                        vm.setCategory(name: suggestedCategory)
                        print("⚠️ Vision suggested category with low confidence: \(suggestedCategory) (confidence: \(visionResult.confidence))")
                    }
                }
            } catch {
                print("⚠️ Vision analysis failed: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            // Create and assign new photo
            let newPhoto = Photo(context: vm.childContext)
            newPhoto.id = UUID()
            newPhoto.data = processedData
            newPhoto.thumbnailData = image.generateThumbnail()
            newPhoto.type = "front"
            newPhoto.isPrimary = true
            newPhoto.item = vm.draftItem
            
            // CRITICAL: Update the item's updatedAt timestamp
            setUpdatedAt(vm.draftItem)
            
            // Refresh UI
            vm.photoRefreshToken = UUID()
            selectedImageType = .front
        }
    }
    
    private func replaceBackImageSync(with image: UIImage) async {
        await MainActor.run {
            // Remove ALL existing back photos
            let photos = vm.draftItem.photos as? Set<Photo> ?? []
            let photosToDelete = photos.filter { $0.type == "back" }
            
            for photo in photosToDelete {
                // Remove from relationship first
                vm.draftItem.removeFromPhotos(photo)
                vm.childContext.delete(photo)
            }
        }

        // Process image
        let processedData = await processImageForStorage(image)
        
        await MainActor.run {
            // Create and assign new photo
            let newPhoto = Photo(context: vm.childContext)
            newPhoto.id = UUID()
            newPhoto.data = processedData
            newPhoto.thumbnailData = image.generateThumbnail()
            newPhoto.type = "back"
            newPhoto.isPrimary = false
            newPhoto.item = vm.draftItem
            
            // CRITICAL: Update the item's updatedAt timestamp
            setUpdatedAt(vm.draftItem)
            
            // Refresh UI
            vm.photoRefreshToken = UUID()
            selectedImageType = .back
        }
    }
    
    private func replaceWornImageSync(with image: UIImage) async {
        await MainActor.run {
            // Remove ALL existing worn photos
            let photos = vm.draftItem.photos as? Set<Photo> ?? []
            let photosToDelete = photos.filter { $0.type == "worn" }
            
            for photo in photosToDelete {
                // Remove from relationship first
                vm.draftItem.removeFromPhotos(photo)
                vm.childContext.delete(photo)
            }
        }

        // Process image
        let processedData = await processImageForStorage(image)
        
        await MainActor.run {
            // Create and assign new photo
            let newPhoto = Photo(context: vm.childContext)
            newPhoto.id = UUID()
            newPhoto.data = processedData
            newPhoto.thumbnailData = image.generateThumbnail()
            newPhoto.type = "worn"
            newPhoto.isPrimary = false
            newPhoto.item = vm.draftItem
            
            // CRITICAL: Update the item's updatedAt timestamp
            setUpdatedAt(vm.draftItem)
            
            // Refresh UI
            vm.photoRefreshToken = UUID()
            selectedImageType = .worn
        }
    }

    private func deleteImage(type: ImageType) {
        let photos = vm.draftItem.photos as? Set<Photo> ?? []
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
            vm.childContext.delete(photo)
            // Refresh UI
            vm.photoRefreshToken = UUID()
            // Reset to front if we deleted the currently selected image
            if selectedImageType == type {
                selectedImageType = .front
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getImage(for type: ImageType) -> UIImage? {
        // Ensure we have the latest photos by accessing the relationship
        guard let photosSet = vm.draftItem.photos as? Set<Photo> else {
            return nil
        }
        // Convert to array to ensure all faults are loaded
        let photos = Array(photosSet)
        
        // Also ensure each photo's data is loaded by accessing the type property
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

    // MARK: - Image Processing
    
    /// Processes image for storage: resizes to max 4096x4096 for better quality
    private func processImageForStorage(_ image: UIImage) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            // Use higher max dimension for better quality
            let maxDimension: CGFloat = 4096
            let resizedImage: UIImage
            
            if image.size.width > maxDimension || image.size.height > maxDimension {
                let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                
                // Use high-quality rendering format
                let format = UIGraphicsImageRendererFormat()
                format.opaque = false
                format.scale = image.scale
                format.preferredRange = .extended // Better color range
                
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                resizedImage = renderer.image { context in
                    // Use high-quality interpolation
                    context.cgContext.interpolationQuality = .high
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                resizedImage = image
            }
            
            // Use PNG to preserve transparency (for user-edited images)
            return resizedImage.pngData()
        }.value
    }

    // MARK: - Save flow
    private func handleSaveTapped() {
        let empties = missingAttributes(of: vm.draftItem)
        if empties.isEmpty {
            persistAndDismiss()
        } else {
            missingFieldsDescription = empties.joined(separator: ", ")
            showMissingWarning = true
        }
    }

    private func persistAndDismiss() {
        do {
            // Save the current item first
            try vm.persistToParent()
            print("✅ Item saved successfully")
            
            // Move to next in queue if available
            // Note: We move to next BEFORE dismissing, so handleItemAddViewDismiss can check if there's a current image
            if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                print("📸 Moving to next image in queue")
                queueCoordinator.moveToNext()
            }
            // If hasMore is false, we're on the last image and it's already been processed in ItemAddView
            // We don't move, so currentImage will still be the last image
            // But wait - we already processed it, so we should clear it
            // Actually, the issue is: when we're on the last image, we show cropper → ItemAddView → save
            // After save, we should clear because we've processed all images
            // But handleItemAddViewDismiss checks currentImage, and if it exists, shows cropper again
            // So we need to track that we've processed the current image
        } catch {
            print("❌ Save failed: \(error.localizedDescription)")
        }
        
        // Always dismiss - ItemGridView's onDisappear will handle showing next cropper or clearing
        DispatchQueue.main.async {
            self.dismiss()
        }
    }
    
    private func handleCancelTapped() {
        // Always check for changes first, regardless of queue status
        if hasItemChanges() {
            showingSaveDraftConfirmation = true
        } else {
            // No changes - if queue is active and has more, discard current and move to next
            if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                discardCurrentAndMoveToNext()
            } else {
                // Otherwise, just discard and dismiss
                vm.discard()
                if queueCoordinator.isQueueActive {
                    queueCoordinator.clear()
                }
                dismiss()
            }
        }
    }
    
    private func discardCurrentAndMoveToNext() {
        // Discard the current item
        vm.discard()
        
        // Move to next in queue if available
        if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
            print("📸 Discarding current item and moving to next in queue")
            queueCoordinator.moveToNext()
        } else {
            // No more images, clear queue
            if queueCoordinator.isQueueActive {
                queueCoordinator.clear()
            }
        }
        
        // Dismiss - ItemGridView's onDisappear will handle showing next cropper
        dismiss()
    }
    
    // MARK: - Draft flow
    private func hasItemChanges() -> Bool {
        let item = vm.draftItem
        
        // Check if front image is set
        if getImage(for: .front) != nil {
            return true
        }
        
        // Check attributes (excluding wardrobe since it's set on navigation)
        if item.category != nil { return true }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty { return true }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty { return true }
        if item.brand != nil { return true }
        if item.price != nil { return true }
        if let links = item.links as? Set<Link>, !links.isEmpty { return true }
        if item.location != nil { return true }
        if let tags = item.tags as? Set<Tag>, !tags.isEmpty { return true }
        if item.size != nil { return true }
        if !(item.notes?.isEmpty ?? true) { return true }
        
        return false
    }
    
    private func saveDraft() {
        do {
            try vm.persistDraftToParent()
            
            // Move to next in queue if available
            if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                print("📸 Draft saved, moving to next image in queue")
                queueCoordinator.moveToNext()
                dismiss() // ItemGridView will show next cropper
            } else {
                // Check if there's still a current image (last image in queue)
                if queueCoordinator.isQueueActive, let _ = queueCoordinator.currentImage {
                    // Still have the last image to process, dismiss and let handleItemAddViewDismiss show cropper
                    dismiss()
                } else {
                    // No more items, show alert and dismiss
                    if queueCoordinator.isQueueActive {
                        queueCoordinator.clear()
                    }
                    showingDraftSaveAlert = true
                }
            }
        } catch {
            print("❌ Draft save failed: \(error.localizedDescription)")
        }
    }

    private func missingAttributes(of item: Item) -> [String] {
        var blanks: [String] = []
        // Check for front image specifically
        let photos = item.photos as? Set<Photo> ?? []
        let hasFrontImage = photos.contains(where: { $0.type == "front" || ($0.isPrimary && ($0.type == nil || $0.type == "")) })
        if !hasFrontImage { blanks.append("Photo") }
        if (item.category?.name?.isEmpty ?? true) { blanks.append("Category") }
        if (item.colors as? Set<AppColor>)?.isEmpty ?? true { blanks.append("Colors") }
        if (item.seasons as? Set<Season>)?.isEmpty ?? true { blanks.append("Seasons") }
        if (item.brand?.name?.isEmpty ?? true) { blanks.append("Brand") }
        if item.price?.amount == nil { blanks.append("Price") }
        if (item.links as? Set<Link>)?.isEmpty ?? true { blanks.append("Links") }
        if (item.location?.name?.isEmpty ?? true) { blanks.append("Location") }
        if (item.tags as? Set<Tag>)?.isEmpty ?? true { blanks.append("Tags") }
        return blanks
    }
}

// MARK: - ViewModel
final class ItemAddViewModel: ObservableObject {
    let childContext: NSManagedObjectContext
    @Published var draftItem: Item
    @Published var photoRefreshToken = UUID()
    @Published var isExtractingMetadata = false

    let selectedWardrobeObjectID: NSManagedObjectID?
    let initialURL: URL?
    let initialImage: UIImage?
    
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?, initialURL: URL? = nil, initialImage: UIImage? = nil) {
        self.initialURL = initialURL
        self.initialImage = initialImage
        // Store the wardrobe's objectID for later re-fetching in child context
        self.selectedWardrobeObjectID = selectedWardrobe?.objectID
        
        // Create a child context
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.parent = parentContext
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // IMPORTANT: Disable automatic saving
        ctx.automaticallyMergesChangesFromParent = false
        self.childContext = ctx
        
        // Create a new Item in the child context
        let item = Item(context: ctx)
        item.id = UUID()
        let now = Date()
        item.timestamp = now
        item.createdAt = now
        
        // If a wardrobe was selected, re-fetch it in the child context and assign to item immediately
        // This ensures the wardrobe name appears in the UI right away
        if let wardrobeObjectID = selectedWardrobe?.objectID {
            do {
                // Re-fetch the wardrobe in the child context using its objectID
                let wardrobeInChild = try ctx.existingObject(with: wardrobeObjectID) as? Wardrobe
                if let wardrobe = wardrobeInChild {
                    item.addToWardrobes(wardrobe)
                }
            } catch {
                print("⚠️ Warning: Could not re-fetch wardrobe in child context during init: \(error.localizedDescription)")
                // Continue even if wardrobe assignment fails
            }
        }
        
        self.draftItem = item
    }
    
    @MainActor
    func persistToParent() throws {
        // Only save if there are actual changes
        guard childContext.hasChanges else { return }
        
        // Require authentication before saving
        guard SupabaseService.shared.isAuthenticated,
              let userId = SupabaseService.shared.currentUser?.id else {
            throw NSError(
                domain: "ItemAdd",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User must be authenticated to save items"]
            )
        }
        
        // Mark as not draft (explicitly set to false for regular items)
        draftItem.isDraft = false
        
        // Set createdAt if not already set (for new items)
        if draftItem.createdAt == nil {
            draftItem.createdAt = Date()
        }
        
        // Set updatedAt (this is a modification, even if it's a new item being finalized)
        setUpdatedAt(draftItem)
        
        // Set userId on draft item before saving
        if draftItem.userId == nil || draftItem.userId?.isEmpty == true {
            draftItem.userId = userId.uuidString
        }
        
        // Save the child context first
        try childContext.save()
        
        // Get the item's objectID before saving parent (in case it changes)
        let itemObjectID = draftItem.objectID
        
        // Then save the parent context to persist to disk
        // IMPORTANT: Always save parent if it exists, don't check hasChanges
        // because child context save pushes changes to parent
        if let parent = childContext.parent {
            do {
                try parent.save()
                
                // After saving, get the item from parent context
                // Use the objectID we captured before save
                let savedItem: Item?
                if itemObjectID.isTemporaryID {
                    // If still temporary, try to get by ID
                    if let itemId = draftItem.id {
                        let request: NSFetchRequest<Item> = Item.fetchRequest()
                        request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
                        request.fetchLimit = 1
                        savedItem = try parent.fetch(request).first
                    } else {
                        savedItem = nil
                    }
                } else {
                    savedItem = try parent.existingObject(with: itemObjectID) as? Item
                }
                
                    if let item = savedItem {
                    parent.refresh(item, mergeChanges: true)
                    
                    // Ensure userId is set before syncing (should already be set above)
                    if item.userId == nil || item.userId?.isEmpty == true {
                        item.userId = userId.uuidString
                        try parent.save()
                    }
                    
                    // Trigger automatic sync for the saved item
                    print("🔄 Triggering sync for newly saved item: \(item.name ?? "unnamed")")
                        SyncService.shared.syncItemIfNeeded(item)
                } else {
                    print("⚠️ Could not find saved item in parent context for sync")
                }
            } catch let error as NSError {
                // Handle constraint conflicts specifically (error code 133021)
                if error.domain == NSCocoaErrorDomain && error.code == 133021 {
                    print("⚠️ Constraint conflict detected, attempting to resolve...")
                    // Try to resolve conflicts by merging
                    try resolveConstraintConflicts(in: parent, error: error)
                    // Retry save after conflict resolution
                    try parent.save()
                    
                    // Try to get item again after conflict resolution
                    let savedItem: Item?
                    if itemObjectID.isTemporaryID {
                        if let itemId = draftItem.id {
                            let request: NSFetchRequest<Item> = Item.fetchRequest()
                            request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
                            request.fetchLimit = 1
                            savedItem = try parent.fetch(request).first
                        } else {
                            savedItem = nil
                        }
                    } else {
                        savedItem = try parent.existingObject(with: itemObjectID) as? Item
                    }
                    
                        if let item = savedItem {
                        parent.refresh(item, mergeChanges: true)
                        
                        // Ensure userId is set before syncing (userId is already unwrapped from guard above)
                        if item.userId == nil || item.userId?.isEmpty == true {
                            item.userId = userId.uuidString
                            try parent.save()
                        }
                        
                        // Trigger automatic sync for the saved item
                        print("🔄 Triggering sync for saved item (after conflict resolution): \(item.name ?? "unnamed")")
                            SyncService.shared.syncItemIfNeeded(item)
                    }
                } else {
                    throw error
                }
            }
        }
    }
    
    func resetForNewItem(selectedWardrobe: Wardrobe?) {
        print("🔄 Resetting for new item...")
        
        // IMPORTANT: Don't rollback! This would undo the previous save.
        // The child context should already be clean after the previous save.
        
        // Create a new Item in the child context for the next image in queue
        let item = Item(context: childContext)
        item.id = UUID()
        let now = Date()
        item.timestamp = now
        item.createdAt = now
        
        // Assign wardrobe if provided
        if let wardrobe = selectedWardrobe {
            // Re-fetch the wardrobe in child context to ensure it's in the right context
            do {
                if let wardrobeInChild = try childContext.existingObject(with: wardrobe.objectID) as? Wardrobe {
                    item.addToWardrobes(wardrobeInChild)
                    print("✅ Assigned wardrobe: \(wardrobeInChild.name ?? "unknown")")
                }
            } catch {
                print("⚠️ Warning: Could not re-fetch wardrobe in child context: \(error.localizedDescription)")
            }
        } else if let wardrobeObjectID = selectedWardrobeObjectID {
            // Try to re-fetch wardrobe in child context using stored objectID
            do {
                if let wardrobeInChild = try childContext.existingObject(with: wardrobeObjectID) as? Wardrobe {
                    item.addToWardrobes(wardrobeInChild)
                    print("✅ Assigned wardrobe from objectID: \(wardrobeInChild.name ?? "unknown")")
                }
            } catch {
                print("⚠️ Warning: Could not re-fetch wardrobe in child context: \(error.localizedDescription)")
            }
        }
        
        self.draftItem = item
        self.photoRefreshToken = UUID()
        
        print("✅ New item created and ready for next image")
    }
    
    private func resolveConstraintConflicts(in context: NSManagedObjectContext, error: NSError) throws {
        // Get conflict list from error
        guard let conflictList = error.userInfo["conflictList"] as? [NSConstraintConflict] else {
            print("⚠️ Could not extract conflict list from error")
            return
        }
        
        for conflict in conflictList {
            // Use conflictingObjects property (not conflictedObjects)
            let conflictingObjects = conflict.conflictingObjects
            
            // For Size conflicts, merge by keeping the first one and transferring relationships
            if let firstSize = conflictingObjects.first as? Size {
                print("🔧 Resolving Size conflict: keeping size with value '\(firstSize.value ?? "nil")', scale '\(firstSize.scale ?? "nil")'")
                
                for conflictedObject in conflictingObjects.dropFirst() {
                    if let sizeToMerge = conflictedObject as? Size {
                        print("   Merging duplicate size: value '\(sizeToMerge.value ?? "nil")', scale '\(sizeToMerge.scale ?? "nil")'")
                        
                        // Transfer items from duplicate to first
                        if let items = sizeToMerge.items as? Set<Item> {
                            for item in items {
                                item.size = firstSize
                            }
                            print("   Transferred \(items.count) items to first size")
                        }
                        // Delete the duplicate
                        context.delete(sizeToMerge)
                    }
                }
            }
        }
        
        // Save the context after resolving conflicts
        try context.save()
        print("✅ Constraint conflicts resolved")
    }
    
    func persistDraftToParent() throws {
        // Only save if there are actual changes
        guard childContext.hasChanges else { return }
        
        // Mark as draft
        draftItem.isDraft = true
        
        // Save the child context first
        try childContext.save()
        
        // Then save the parent context to persist to disk
        if let parent = childContext.parent, parent.hasChanges {
            try parent.save()
        }
    }
    
    func discard() {
        // Rollback discards all changes in the child context
        childContext.rollback()
    }
    
    // MARK: - Metadata Extraction
    
    func extractAndApplyMetadata() async {
        guard let url = initialURL else { return }
        
        await MainActor.run { isExtractingMetadata = true }
        
        do {
            let metadata = try await ProductMetadataService.shared.fetchMetadata(from: url)
            
            // Fetch and set image - store original data without processing
            var fetchedImage: UIImage?
            if let imageURL = metadata.imageURL {
                print("📸 Attempting to fetch image from: \(imageURL)")
                do {
                    // Fetch and validate image data
                    let imageData = try await ProductMetadataService.shared.fetchImageData(from: imageURL)
                    
                    // Create UIImage from validated data to display, preserving original scale
                    guard let image = UIImage(data: imageData) else {
                        print("⚠️ Could not create UIImage from validated data")
                        await MainActor.run {
                            applyMetadata(metadata, visionCategory: nil)
                            isExtractingMetadata = false
                        }
                        return
                    }
                    
                    fetchedImage = image
                    
                    await MainActor.run {
                        print("📸 Setting image in UI (original data, no processing)")
                        setPrimaryImageFromURL(image: image, originalData: imageData)
                    }
                } catch let error as ProductMetadataService.MetadataError {
                    // Handle specific error types with detailed messages
                    switch error {
                    case .invalidImageData(let message):
                        print("❌ Invalid image data: \(message)")
                    case .networkError:
                        print("❌ Network error fetching image from: \(imageURL)")
                    case .invalidHTML:
                        print("❌ Invalid HTML (shouldn't happen for image fetch)")
                    case .webViewTimeout:
                        print("❌ WebView timeout while fetching metadata")
                    }
                } catch {
                    print("❌ Failed to fetch image: \(error.localizedDescription)")
                }
            } else {
                print("⚠️ No image URL found in metadata")
            }
            
            // Analyze image with Vision if available
            var visionCategory: String? = nil
            if let image = fetchedImage {
                print("🔍 Analyzing image with Vision for category classification...")
                do {
                    let visionResult = try await VisionAnalysisService.shared.analyzeCategory(from: image)
                    let combined = VisionAnalysisService.shared.combineCategorySources(
                        urlCategory: metadata.category,
                        visionResult: visionResult
                    )
                    
                    visionCategory = combined.category
                    print("✅ Vision analysis complete: \(combined.category ?? "none") (confidence: \(combined.confidence), source: \(combined.source))")
                } catch {
                    print("⚠️ Vision analysis failed: \(error.localizedDescription)")
                    // Continue without Vision result
                }
            }
            
            await MainActor.run {
                applyMetadata(metadata, visionCategory: visionCategory)
                isExtractingMetadata = false
            }
        } catch {
            await MainActor.run { isExtractingMetadata = false }
            print("❌ Failed to extract metadata: \(error)")
        }
    }
    
    private func applyMetadata(_ metadata: ProductMetadata, visionCategory: String?) {
        // Set item name
        if let title = metadata.title, !title.isEmpty {
            draftItem.name = title
        }
        
        // Set brand (fetch or create)
        if let brandName = metadata.brand, !brandName.isEmpty {
            setBrand(name: brandName)
        }
        
        // Set category using combined URL + Vision result
        // Vision category takes precedence if available (it's already combined in extractAndApplyMetadata)
        if let categoryName = visionCategory ?? VisionAnalysisService.shared.normalizeCategoryFromURL(metadata.category), !categoryName.isEmpty {
            setCategory(name: categoryName)
        }
        
        // Set price - prefer priceString when available to preserve exact precision (cents)
        if let priceAmount = metadata.price {
            let price = Price(context: childContext)
            
            // Use original priceString if available to preserve exact precision including cents
            if let originalPriceString = metadata.priceString, !originalPriceString.isEmpty {
                // Parse the original price string to preserve decimal precision
                let cleanedPrice = originalPriceString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                if !cleanedPrice.isEmpty {
                    // NSDecimalNumber(string:locale:) returns non-optional, so use directly
                    price.amount = NSDecimalNumber(string: cleanedPrice, locale: Locale(identifier: "en_US"))
                    print("✅ Applied price using original string: \(originalPriceString) -> \(cleanedPrice) -> \(price.amount ?? 0)")
                } else {
                    // Fallback to Decimal if cleaned price is empty
                    price.amount = NSDecimalNumber(decimal: priceAmount)
                    print("⚠️ Failed to parse priceString, using Decimal: \(priceAmount)")
                }
            } else {
                // Fallback to Decimal if no priceString available
                price.amount = NSDecimalNumber(decimal: priceAmount)
                print("✅ Applied price using Decimal: \(priceAmount)")
            }
            
            price.currency = metadata.priceCurrency ?? "USD"
            draftItem.price = price
            print("✅ Final price stored: \(price.amount ?? 0) \(price.currency ?? "USD")")
        } else {
            print("⚠️ No price found in metadata")
        }
        
        // Add link
        let link = Link(context: childContext)
        link.id = UUID()
        link.url = metadata.sourceURL
        link.name = extractWebsiteName(from: metadata.sourceURL)
        link.item = draftItem
    }
    
    private func setBrand(name: String) {
        // First check if brand exists in child context
        let childRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
        childRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
        
        if let existingInChild = try? childContext.fetch(childRequest).first {
            draftItem.brand = existingInChild
            return
        }
        
        // If not in child context, check parent context
        // This ensures we don't create duplicate brands
        if let parentContext = childContext.parent {
            let parentRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
            parentRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
            
            if let existingInParent = try? parentContext.fetch(parentRequest).first {
                // Get the brand in the child context using its objectID
                if let brandInChild = try? childContext.existingObject(with: existingInParent.objectID) as? Brand {
                    draftItem.brand = brandInChild
                    return
                }
            }
        }
        
        // Brand doesn't exist - create new one in child context (not persisted until save)
        let newBrand = Brand(context: childContext)
        newBrand.id = UUID()
        newBrand.name = name
        newBrand.isVisible = true
        draftItem.brand = newBrand
    }
    
    func setCategory(name: String) {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        
        if let existing = try? childContext.fetch(request).first {
            draftItem.category = existing
        } else {
            let newCategory = Category(context: childContext)
            newCategory.id = UUID()
            newCategory.name = name
            draftItem.category = newCategory
        }
    }
    
    /// Sets primary image from URL - processes and compresses the image
    func setPrimaryImageFromURL(image: UIImage, originalData: Data) {
        // Remove existing front photo (either type="front" or isPrimary with no type)
        let photos = draftItem.photos as? Set<Photo> ?? []
        if let existingFront = photos.first(where: { $0.type == "front" || ($0.isPrimary && ($0.type == nil || $0.type == "")) }) {
            childContext.delete(existingFront)
        }
        
        // Process and compress the image
        let processedData = image.processForStorage()
        
        let photo = Photo(context: childContext)
        photo.id = UUID()
        photo.isPrimary = true
        photo.type = "front"
        photo.data = processedData
        photo.thumbnailData = image.generateThumbnail()
        photo.item = draftItem
        
        photoRefreshToken = UUID()
        if let data = processedData {
            print("✅ Stored compressed image data: \(data.count / 1024)KB (original: \(originalData.count / 1024)KB)")
        }
    }
    
    /// Sets primary image from user selection - processes for storage
    func setPrimaryImage(_ image: UIImage) {
        Task {
            let processedData = await processImageForStorage(image)
            
            await MainActor.run {
                if let existing = (draftItem.photos as? Set<Photo>)?.first(where: { $0.isPrimary }) {
                    childContext.delete(existing)
                }
                let photo = Photo(context: childContext)
                photo.id = UUID()
                photo.isPrimary = true
                photo.data = processedData
                photo.thumbnailData = image.generateThumbnail()
                photo.item = draftItem
                
                photoRefreshToken = UUID()
            }
        }
    }
    
    private func processImageForStorage(_ image: UIImage) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            // Use the optimized compression method: resize first, then compress
            return image.processForStorage(maxDimension: 1200, maxFileSizeKB: 200)
        }.value
    }
    
    private func extractWebsiteName(from url: URL) -> String {
        guard let host = url.host else {
            return "Product Link"
        }
        
        // Use the same logic as ProductMetadataService for consistency
        var domain = host.lowercased()
        
        // Remove common subdomain patterns (www, www2, www3, etc.)
        let subdomainPattern = #"^(www\d*|shop|store|shop-|store-|www-|m|mobile|app)\.?"#
        if let regex = try? NSRegularExpression(pattern: subdomainPattern, options: .caseInsensitive) {
            let range = NSRange(domain.startIndex..., in: domain)
            domain = regex.stringByReplacingMatches(in: domain, options: [], range: range, withTemplate: "")
        }
        
        // Remove leading/trailing dots
        domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        
        // Extract main domain (part before first dot)
        if let firstDot = domain.firstIndex(of: ".") {
            domain = String(domain[..<firstDot])
        }
        
        // Handle special brand cases
        let brandMappings: [String: String] = [
            "hm": "H&M",
            "zara": "ZARA",
            "nike": "Nike",
            "adidas": "adidas",
            "puma": "PUMA",
            "gap": "Gap",
            "oldnavy": "Old Navy",
            "bananarepublic": "Banana Republic",
            "athleta": "Athleta"
        ]
        
        if let mappedBrand = brandMappings[domain] {
            return mappedBrand
        }
        
        // Skip common shopping domains
        let shoppingDomains = ["amazon", "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
        if shoppingDomains.contains(domain) {
            // For shopping sites, use a more descriptive name
            return domain.capitalized
        }
        
        // Capitalize appropriately
        if domain.count > 0 {
            // Check if it's all uppercase (like ZARA)
            if domain == domain.uppercased() && domain.count <= 5 {
                return domain.uppercased()
            }
            // Otherwise capitalize first letter
            return domain.capitalized
        }
        
        return "Product Link"
    }
}



// MARK: - Reusable attributes section (unchanged rows, but sheets inherit child ctx)
private struct ItemAttributesSection: View {
    @ObservedObject var item: Item
    
    @State private var isWardrobeDrawerPresented = false
    @State private var isCategoryDrawerPresented = false
    @State private var isSizeDrawerPresented = false
    @State private var isColorDrawerPresented = false
    @State private var isSeasonDrawerPresented = false
    @State private var isBrandDrawerPresented = false
    @State private var isLocationDrawerPresented = false
    @State private var isPriceDrawerPresented = false
    @State private var isLinkDrawerPresented = false
    @State private var isTagDrawerPresented = false

    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    var body: some View {
        Section {
            wardrobeRow()
            categoryRow()
            sizeRow()
            colorRow()
            seasonRow()
            brandRow()
            priceRow()
            linkRow()
            locationRow()
            tagRow()
        } header: {
            Text("ATTRIBUTES").fontWeight(.semibold)
        }
    }
    
    
    
    private func wardrobeRow() -> some View {
        Button { isWardrobeDrawerPresented = true } label: {
            HStack {
                Text("Wardrobes").foregroundColor(.primary)
                Spacer()
                if let selected = item.wardrobes as? Set<Wardrobe>, !selected.isEmpty {
                    // Show the first 2 names + ellipsis if more
                    let names = selected.compactMap { $0.name }.sorted()
                    Text(names.prefix(2).joined(separator: ", "))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    if names.count > 2 { Text("…").foregroundColor(.gray) }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isWardrobeDrawerPresented) {
            SetWardrobeView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func categoryRow() -> some View {
        Button { isCategoryDrawerPresented = true } label: {
            HStack {
                Text("Category").foregroundColor(.primary)
                Spacer()
                if let name = item.category?.name, !name.isEmpty { Text(name).foregroundColor(.gray) }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isCategoryDrawerPresented) {
            SetCategoryView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!) // ensure child ctx
        }
    }
    
    private func sizeRow() -> some View {
        Button { isSizeDrawerPresented = true } label: {
            HStack {
                Text("Size").foregroundColor(.primary)
                Spacer()
                if let size = item.size, let value = size.value, !value.isEmpty {
                    Text(value).foregroundColor(.gray)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isSizeDrawerPresented) {
            SetSizeView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func colorRow() -> some View {
        Button { isColorDrawerPresented = true } label: {
            HStack {
                Text("Colors").foregroundColor(.primary)
                Spacer()
                if let selected = item.colors as? Set<AppColor>, !selected.isEmpty {
                    let sorted = selected.sorted { ($0.name ?? "") < ($1.name ?? "") }
                    HStack(spacing: 8) {
                        ForEach(sorted.prefix(4), id: \.self) { appColor in
                            Circle()
                                .fill(colorFromName(appColor.name ?? ""))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                        }
                        if sorted.count > 4 { Text("…").foregroundColor(.gray).font(.headline) }
                    }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isColorDrawerPresented) {
            SetColorView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func seasonRow() -> some View {
        Button { isSeasonDrawerPresented = true } label: {
            HStack {
                Text("Seasons").foregroundColor(.primary)
                Spacer()
                if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
                    let names = seasons.compactMap { $0.name }.sorted()
                    Text(names.prefix(2).joined(separator: ", ")).foregroundColor(.gray)
                    if names.count > 2 { Text("…").foregroundColor(.gray).font(.headline) }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isSeasonDrawerPresented) {
            SetSeasonView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func brandRow() -> some View {
        Button { isBrandDrawerPresented = true } label: {
            HStack {
                Text("Brand").foregroundColor(.primary)
                Spacer()
                if let brand = item.brand?.name, !brand.isEmpty { Text(brand).foregroundColor(.gray) }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isBrandDrawerPresented) {
            BrandSelectionView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func priceRow() -> some View {
        Button { isPriceDrawerPresented = true } label: {
            HStack {
                Text("Price").foregroundColor(.primary)
                Spacer()
                if let amount = item.price?.amount {
                    HStack(spacing: 0) {
                        Text(currencySymbol).foregroundColor(.gray)
                        Text(NumberFormatter.currency2.string(from: amount) ?? "0.00")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray).padding(.leading, 4)
            }
        }
        .sheet(isPresented: $isPriceDrawerPresented) {
            SetPriceView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func linkRow() -> some View {
        let names = (item.links as? Set<Link>)?.compactMap { $0.name }.sorted() ?? []
        let display = names.prefix(2).joined(separator: ", ")
        let hasMore = names.count > 2

        return Button { isLinkDrawerPresented = true } label: {
            HStack {
                Text(names.count <= 1 ? "Link" : "Links").foregroundColor(.primary)
                Spacer()
                if !display.isEmpty {
                    HStack(spacing: 2) {
                        Text(display).foregroundColor(.gray).lineLimit(1)
                        if hasMore { Text("…").foregroundColor(.gray).font(.headline) }
                    }
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isLinkDrawerPresented) {
            SetLinkView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func locationRow() -> some View {
        Button { isLocationDrawerPresented = true } label: {
            HStack {
                Text("Location").foregroundColor(.primary)
                Spacer()
                if let loc = item.location?.name, !loc.isEmpty { Text(loc).foregroundColor(.gray) }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isLocationDrawerPresented) {
            SetLocationView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }

    private func tagRow() -> some View {
        Button { isTagDrawerPresented = true } label: {
            HStack {
                Text("Tags").foregroundColor(.primary)
                Spacer()
                if let tagSet = item.tags as? Set<Tag>, !tagSet.isEmpty {
                    let names = tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
                    Text(names.prefix(20))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $isTagDrawerPresented) {
            SetTagView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!)
        }
    }
}
/*
private extension NumberFormatter {
    static let currency2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}
*/
