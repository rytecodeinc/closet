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
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var bulkItemImportCoordinator: BulkItemImportCoordinator
    @EnvironmentObject private var authSession: AuthSession

    @StateObject private var vm: ItemAddViewModel
    @ObservedObject private var queueCoordinator: ImageQueueCoordinator
    
    @State private var attributesSheet: AttributesSectionView.Sheet?
    @State private var isAttributesExpanded = true

    // Image handling
    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedUIImage: UIImage?
    @State private var pendingImageType: ImageType?
    @State private var imageToEdit: UIImage?
    @State private var selectedImageType: ImageType = .front

    // Match ItemDetailView: hero shows "Item(front)" + "Worn" with a segmented picker row.
    @State private var heroCarouselPage: Int = 0 // 0 = item(front), 1 = worn
    @State private var showAddMultipleDialog: Bool = false
    @State private var showMultiImagePicker: Bool = false
    @State private var multiPickedImages: [UIImage] = []
    @State private var showBulkCameraImport = false

    // KEY FIX: Drafts is now a sheet, not a navigation push
    @State private var showingDraftsSheet = false

    // Cropper navigation — this is the ONLY navigation push from this view
    enum CropperDestination: Hashable {
        case cropper(ImageType, UIImage)

        static func == (lhs: CropperDestination, rhs: CropperDestination) -> Bool {
            if case .cropper(let lt, _) = lhs, case .cropper(let rt, _) = rhs {
                return lt == rt
            }
            return false
        }

        func hash(into hasher: inout Hasher) {
            if case .cropper(let imageType, _) = self {
                hasher.combine(1)
                hasher.combine(imageType)
            }
        }
    }

    @State private var cropperDestination: CropperDestination? = nil

    enum ImageType: Hashable {
        case front
        case worn
    }

    // Save warning
    @State private var showMissingWarning = false
    @State private var missingFieldsDescription = ""
    
    // Draft confirmation
    @State private var showingSaveDraftConfirmation = false
    @State private var showingDraftSaveAlert = false

    // Original init for backward compatibility (creates dummy coordinator)
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?, initialURL: URL? = nil, initialImage: UIImage? = nil, sessionAccountId: String? = nil) {
        let authUserId = sessionAccountId ?? SupabaseService.shared.currentUser?.id.uuidString
        _vm = StateObject(wrappedValue: ItemAddViewModel(
            parentContext: parentContext,
            selectedWardrobe: selectedWardrobe,
            initialURL: initialURL,
            initialImage: initialImage,
            authUserId: authUserId
        ))
        _queueCoordinator = ObservedObject(wrappedValue: ImageQueueCoordinator())
    }
    
    // New init with queue coordinator
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?, queueCoordinator: ImageQueueCoordinator, initialURL: URL? = nil, sessionAccountId: String? = nil) {
        let initialImage = queueCoordinator.nextCroppedImage
        let authUserId = sessionAccountId ?? SupabaseService.shared.currentUser?.id.uuidString
        _vm = StateObject(wrappedValue: ItemAddViewModel(
            parentContext: parentContext,
            selectedWardrobe: selectedWardrobe,
            initialURL: initialURL,
            initialImage: initialImage,
            authUserId: authUserId
        ))
        _queueCoordinator = ObservedObject(wrappedValue: queueCoordinator)
    }

    // Init for editing an existing draft item
    init(parentContext: NSManagedObjectContext, existingDraft: Item, sessionAccountId: String? = nil) {
        let authUserId = sessionAccountId ?? SupabaseService.shared.currentUser?.id.uuidString
        _vm = StateObject(wrappedValue: ItemAddViewModel(
            parentContext: parentContext,
            existingDraft: existingDraft,
            authUserId: authUserId
        ))
        _queueCoordinator = ObservedObject(wrappedValue: ImageQueueCoordinator())
    }

    var body: some View {
        List {
            // Image Gallery Section
            Section {
                VStack(spacing: 0) {
                    itemImageDisplay()
                }
                itemWornPickerRow()
            }
            .listRowInsets(EdgeInsets(.zero))
            .listRowSeparator(.hidden)
            
            // ATTRIBUTES Section
            Section {
                if isAttributesExpanded {
                    AttributesSectionView(item: vm.draftItem, activeSheet: $attributesSheet)
                        .transition(.opacity.combined(with: .slide))
                        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
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
        }
        // Attribute sheets
        .sheet(item: $attributesSheet) { $0.destination(for: vm.draftItem) }
        // KEY FIX: Drafts presented as sheet — no navigation push conflict
        .sheet(isPresented: $showingDraftsSheet) {
            NavigationView {
                ItemDraftsView(onSelectDraft: { selectedDraft in
                    // Load the selected draft directly into the current VM and dismiss the sheet.
                    // This repopulates ItemAddView in place — no second sheet needed.
                    vm.loadExistingDraft(selectedDraft)
                    purgeRetiredBackPhotosIfNeeded()
                    initializeSelectedImageType()
                    showingDraftsSheet = false
                })
            }
        }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets())
        .navigationTitle(queueCoordinator.hasMore ?
            "Add Item (\(queueCoordinator.remainingCount) remaining)" :
            "Add Item")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // Only ONE navigationDestination — solely for the image cropper
        .navigationDestination(item: $cropperDestination) { destination in
            if case .cropper(let imageType, let image) = destination {
                ImageCropperView(
                    originalImage: image,
                    onCrop: { croppedImage in
                        Task { @MainActor in
                            switch imageType {
                            case .front:  await replaceFrontImageSync(with: croppedImage)
                            case .worn:   await replaceWornImageSync(with: croppedImage)
                            }
                            pendingImageType = nil
                            imageToEdit = nil
                            cropperDestination = nil
                        }
                    },
                    isEditing: true
                )
                .navigationBarTitleDisplayMode(.inline)
                .onDisappear {
                    if pendingImageType == nil {
                        cropperDestination = nil
                    }
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(role: queueCoordinator.hasMore ? .destructive : .none) {
                    handleCancelTapped()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(queueCoordinator.hasMore ? .red : .primary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // KEY FIX: folder button now sets showingDraftsSheet, not a nav push
                    Button {
                        showingDraftsSheet = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    Button("Save") {
                        handleSaveTapped()
                    }
                    .bold()
                    .disabled(getImage(for: .front) == nil)
                }
            }
        }
        // Make the whole subtree use the child context
        .environment(\.managedObjectContext, vm.childContext)
        .sheet(isPresented: $isImagePickerPresented) {
            if imagePickerSource == .photoLibrary {
                SingleItemLibraryPickAndCropSheet(
                    onCropped: { newImage in
                        if let imageType = pendingImageType {
                            switch imageType {
                            case .front: replaceFrontImage(with: newImage)
                            case .worn:  replaceWornImage(with: newImage)
                            }
                            pendingImageType = nil
                        }
                        isImagePickerPresented = false
                    },
                    onLibraryCancel: {
                        pendingImageType = nil
                        isImagePickerPresented = false
                    }
                )
            } else {
                ImagePicker(
                    image: $selectedUIImage,
                    sourceType: $imagePickerSource,
                    allowsEditing: true
                ) { image in
                    if let newImage = image, let imageType = pendingImageType {
                        switch imageType {
                        case .front: replaceFrontImage(with: newImage)
                        case .worn:  replaceWornImage(with: newImage)
                        }
                        pendingImageType = nil
                    }
                    isImagePickerPresented = false
                }
            }
        }
        .sheet(isPresented: $showMultiImagePicker) {
            MultiImagePicker(selectedImages: $multiPickedImages, selectionLimit: 10) {
                showMultiImagePicker = false
                let picked = multiPickedImages
                multiPickedImages.removeAll()
                guard !picked.isEmpty else { return }
                beginBulkLibraryImport(with: picked)
            }
        }
        .fullScreenCover(isPresented: $showBulkCameraImport) {
            BulkCameraImportFlowView(
                onAdd: { images in
                    showBulkCameraImport = false
                    beginBulkLibraryImport(with: images)
                },
                onCancel: {
                    showBulkCameraImport = false
                }
            )
        }
        .alert("Add Item?", isPresented: $showMissingWarning) {
            Button("Proceed", role: .none) { persistAndDismiss() }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You are saving with the following empty fields: \(missingFieldsDescription). You can fill them later in Item Details.")
        }
        .alert("Draft Saved", isPresented: $showingDraftSaveAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your item has been saved as a draft.")
        }
        .alert("Save draft?", isPresented: $showingSaveDraftConfirmation) {
            Button("Yes") { saveDraft() }
            Button("No", role: .cancel) {
                if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                    discardCurrentAndMoveToNext()
                } else {
                    discardItem()
                    if queueCoordinator.isQueueActive { queueCoordinator.clear() }
                    dismiss()
                }
            }
        } message: {
            Text("Saving this item to drafts will allow you to finish editing it later.")
        }
        .onAppear {
            purgeRetiredBackPhotosIfNeeded()
            initializeSelectedImageType()
            if let initialImage = vm.initialImage {
                print("📸 ItemAddView: Received initial cropped image from queue")
                replaceFrontImage(with: initialImage)
            } else {
                print("📸 ItemAddView: No initial image provided")
            }
            if let initialURL = vm.initialURL {
                print("🔗 ItemAddView: Received initial URL from share sheet: \(initialURL)")
                Task { await vm.extractAndApplyMetadata() }
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
        let photos = vm.draftItem.photos as? Set<Photo> ?? []
        if photos.contains(where: { $0.type == "front" || ($0.isPrimary && $0.type == nil) }) {
            selectedImageType = .front
        } else if photos.contains(where: { $0.type == "worn" }) {
            selectedImageType = .worn
        } else {
            selectedImageType = .front
        }
        heroCarouselPage = (selectedImageType == .worn) ? 1 : 0
    }

    private func purgeRetiredBackPhotosIfNeeded() {
        guard ItemPhotoSlot.purgeRetiredBackPhotos(in: vm.draftItem, context: vm.childContext) else { return }
        setUpdatedAt(vm.draftItem)
        vm.photoRefreshToken = UUID()
        print("🧹 Purged retired item back photo(s) from draft")
    }

    /// Hero carousel + segmented picker only use front/worn slots (page 0 / 1).
    private func syncHeroCarouselWithSelectedImageType() {
        let page = (selectedImageType == .worn) ? 1 : 0
        guard heroCarouselPage != page else { return }
        withAnimation { heroCarouselPage = page }
    }
    
    private func itemWornPickerRow() -> some View {
        SocialEngagementActionsRow(
            segmentSelection: Binding(
                get: { heroCarouselPage == 0 ? .tshirt : .worn },
                set: { segment in
                    withAnimation {
                        heroCarouselPage = (segment == .tshirt) ? 0 : 1
                        selectedImageType = (segment == .tshirt) ? .front : .worn
                    }
                }
            ),
            favoriteSelection: vm.draftItem.isFavorite,
            showsLikeButton: true,
            showsShareButton: false,
            showsMoveToClosetButton: false,
            onLike: {
                withAnimation {
                    toggleDraftFavorite()
                }
            }
        )
        .id(vm.photoRefreshToken)
        .confirmationDialog("Add Multiple Images", isPresented: $showAddMultipleDialog, titleVisibility: .visible) {
            if appCapabilities.enablesAddMultipleCamera,
               UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("From Camera") {
                    showBulkCameraImport = true
                }
            }
            Button("From Library") {
                showMultiImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func toggleDraftFavorite() {
        vm.draftItem.isFavorite.toggle()
        setUpdatedAt(vm.draftItem)
        vm.photoRefreshToken = UUID()
    }
    
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private func itemImageDisplay() -> some View {
        let frontImage = getImage(for: .front)
        let wornImage = getImage(for: .worn)
        
        return TabView(selection: $heroCarouselPage) {
                Group {
                    if let uiImage = frontImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenWidth, height: screenWidth)
                            .clipped()
                    } else {
                        heroImagePlaceholder(for: .front)
                    }
                }
                .tag(0)
                
                Group {
                    if let uiImage = wornImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenWidth, height: screenWidth)
                            .clipped()
                    } else {
                        heroImagePlaceholder(for: .worn)
                    }
                }
                .tag(1)
            }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: screenWidth, height: screenWidth)
        .onChange(of: heroCarouselPage) { _, newPage in
            selectedImageType = (newPage == 0) ? .front : .worn
            _ = vm.draftItem.photos
        }
    }

    @ViewBuilder
    private func heroImagePlaceholder(for type: ImageType) -> some View {
        if type == .front, getImage(for: .worn) == nil {
            ZStack(alignment: .bottomLeading) {
                heroSingleTapPlaceholder(for: .front)
                addMultipleButton
                    .padding(.leading, 14)
                    .padding(.bottom, 14)
            }
            .frame(width: screenWidth, height: screenWidth)
        } else {
            heroSingleTapPlaceholder(for: type)
        }
    }

    private var addMultipleButton: some View {
        Button {
            showAddMultipleDialog = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .imageScale(.large)
                Text("Add Multiple")
                    .font(.subheadline)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .accessibilityLabel("Auto-add multiple items from camera or library")
    }

    private func heroSingleTapPlaceholder(for type: ImageType) -> some View {
        Button {
            presentImagePicker(for: type)
        } label: {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: heroPlaceholderSystemImage(for: type))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 40))
                        Text(heroPlaceholderMessage(for: type))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: screenWidth, height: screenWidth)
        .accessibilityLabel(heroPlaceholderAccessibilityLabel(for: type))
    }

    private func heroPlaceholderAccessibilityLabel(for type: ImageType) -> String {
        switch type {
        case .front:
            return "Add a photo of the front of the item"
        case .worn:
            return "Add a photo of you wearing this item"
        }
    }

    private func heroPlaceholderSystemImage(for type: ImageType) -> String {
        switch type {
        case .worn:
            return "person.crop.square.badge.camera"
        case .front:
            return "photo"
        }
    }

    private func heroPlaceholderMessage(for type: ImageType) -> String {
        switch type {
        case .front:
            return "Tap to add a photo of the front of the item"
        case .worn:
            return "Tap to add a photo of you wearing this item"
        }
    }
    
    private func imageThumbnailRow() -> some View {
        let size: CGFloat = (UIScreen.main.bounds.width - 4) / 2
        
        return HStack(spacing: 2) {
            imageThumbnail(type: .front, image: getImage(for: .front), size: size).contentShape(Rectangle())
            imageThumbnail(type: .worn,  image: getImage(for: .worn),  size: size).contentShape(Rectangle())
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
                    .overlay(Rectangle().stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedImageType == type {
                            showThumbnailActionSheet(for: type)
                        } else {
                            withAnimation {
                                selectedImageType = type
                                if type == .worn {
                                    heroCarouselPage = 1
                                } else if type == .front {
                                    heroCarouselPage = 0
                                }
                            }
                        }
                    }
            } else {
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
                    .overlay(Rectangle().stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3))
                    .onTapGesture { presentImagePicker(for: type) }
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func placeholderText(for type: ImageType) -> String {
        switch type {
        case .front: return "Front"
        case .worn:  return "Worn"
        }
    }
    
    private func showThumbnailActionSheet(for type: ImageType) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Retake Photo", style: .default) { _ in
                pendingImageType = type
                imagePickerSource = .camera
                isImagePickerPresented = true
            })
        }
        alert.addAction(UIAlertAction(title: "Replace from Library", style: .default) { _ in
            pendingImageType = type
            imagePickerSource = .photoLibrary
            isImagePickerPresented = true
        })
        if getImage(for: type) != nil {
            alert.addAction(UIAlertAction(title: "Edit Image", style: .default) { _ in
                presentCropperForImage(type: type)
            })
        }
        if type == .worn && getImage(for: type) != nil {
            alert.addAction(UIAlertAction(title: "Remove Image", style: .destructive) { _ in
                deleteImage(type: type)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
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
            if let popover = alert.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func presentCropperForImage(type: ImageType) {
        guard let image = getImage(for: type) else {
            print("⚠️ No image found for type \(type)")
            return
        }
        print("📸 Presenting cropper for \(type) with image size: \(image.size)")
        pendingImageType = type
        imageToEdit = image
        cropperDestination = .cropper(type, image)
    }
    
    // MARK: - Replace Image Functions

    private func replaceFrontImage(with image: UIImage) {
        ItemPhotoSlot.deleteMatching(in: vm.draftItem, slot: "front", context: vm.childContext)
        Task {
            let processedData = await processImageForStorage(image)
            if vm.draftItem.category == nil {
                print("🔍 Analyzing user-selected image with Vision for category classification...")
                do {
                    let visionResult = try await VisionAnalysisService.shared.analyzeCategory(from: image)
                    if let suggestedCategory = visionResult.suggestedCategory {
                        await MainActor.run {
                            vm.setCategory(name: suggestedCategory)
                            print("✅ Vision suggested category: \(suggestedCategory) (confidence: \(visionResult.confidence))")
                        }
                    }
                } catch {
                    print("⚠️ Vision analysis failed: \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                let newPhoto = Photo(context: vm.childContext)
                ItemPhotoSlot.configureReplacedPhoto(
                    newPhoto,
                    on: vm.draftItem,
                    image: image,
                    processedData: processedData,
                    type: "front",
                    asPrimary: true
                )
                setUpdatedAt(vm.draftItem)
                vm.photoRefreshToken = UUID()
                selectedImageType = .front
            }
        }
    }
    
    private func replaceWornImage(with image: UIImage) {
        ItemPhotoSlot.deleteMatching(in: vm.draftItem, slot: "worn", context: vm.childContext)
        Task {
            let processedData = await processWornImageForStorage(image)
            await MainActor.run {
                let newPhoto = Photo(context: vm.childContext)
                ItemPhotoSlot.configureReplacedPhoto(
                    newPhoto,
                    on: vm.draftItem,
                    image: image,
                    processedData: processedData,
                    type: "worn",
                    asPrimary: false
                )
                setUpdatedAt(vm.draftItem)
                vm.photoRefreshToken = UUID()
                selectedImageType = .worn
                syncHeroCarouselWithSelectedImageType()
            }
        }
    }
    
    // MARK: - Sync versions for cropper editing

    private func replaceFrontImageSync(with image: UIImage) async {
        await MainActor.run {
            ItemPhotoSlot.deleteMatching(in: vm.draftItem, slot: "front", context: vm.childContext)
        }
        let processedData = await processImageForStorage(image)
        if vm.draftItem.category == nil {
            do {
                let visionResult = try await VisionAnalysisService.shared.analyzeCategory(from: image)
                if let suggestedCategory = visionResult.suggestedCategory {
                    await MainActor.run { vm.setCategory(name: suggestedCategory) }
                }
            } catch {
                print("⚠️ Vision analysis failed: \(error.localizedDescription)")
            }
        }
        await MainActor.run {
            let newPhoto = Photo(context: vm.childContext)
            ItemPhotoSlot.configureReplacedPhoto(
                newPhoto,
                on: vm.draftItem,
                image: image,
                processedData: processedData,
                type: "front",
                asPrimary: true
            )
            setUpdatedAt(vm.draftItem)
            vm.photoRefreshToken = UUID()
            selectedImageType = .front
        }
    }
    
    private func replaceWornImageSync(with image: UIImage) async {
        await MainActor.run {
            ItemPhotoSlot.deleteMatching(in: vm.draftItem, slot: "worn", context: vm.childContext)
        }
        let processedData = await processWornImageForStorage(image)
        await MainActor.run {
            let newPhoto = Photo(context: vm.childContext)
            ItemPhotoSlot.configureReplacedPhoto(
                newPhoto,
                on: vm.draftItem,
                image: image,
                processedData: processedData,
                type: "worn",
                asPrimary: false
            )
            setUpdatedAt(vm.draftItem)
            vm.photoRefreshToken = UUID()
            selectedImageType = .worn
            syncHeroCarouselWithSelectedImageType()
        }
    }

    private func deleteImage(type: ImageType) {
        let slot: String
        switch type {
        case .front: slot = "front"
        case .worn: slot = "worn"
        }
        let before = (vm.draftItem.photos as? Set<Photo>) ?? []
        guard !ItemPhotoSlot.photosMatching(before, slot: slot).isEmpty else { return }

        ItemPhotoSlot.deleteMatching(in: vm.draftItem, slot: slot, context: vm.childContext)
        vm.photoRefreshToken = UUID()
        if selectedImageType == type {
            selectedImageType = .front
            syncHeroCarouselWithSelectedImageType()
        }
    }
    
    // MARK: - Helper Functions
    
    private func getImage(for type: ImageType) -> UIImage? {
        guard let photosSet = vm.draftItem.photos as? Set<Photo> else { return nil }
        let photos = Array(photosSet)
        _ = photos.compactMap { $0.type }
        switch type {
        case .front:
            if let frontPhoto = photos.first(where: {
                ItemPhotoSlot.normalizedType($0) == "front"
            }) {
                return UIImage(data: frontPhoto.data ?? Data())
            } else if let primaryPhoto = photos.first(where: {
                $0.isPrimary && ItemPhotoSlot.normalizedType($0).isEmpty
            }) {
                return UIImage(data: primaryPhoto.data ?? Data())
            }
            return nil
        case .worn:
            if let wornPhoto = photos.first(where: { ItemPhotoSlot.normalizedType($0) == "worn" }) {
                return UIImage(data: wornPhoto.data ?? Data())
            }
            return nil
        }
    }

    // MARK: - Image Processing
    
    /// Front path (unchanged): large PNG for cutout alpha.
    private func processImageForStorage(_ image: UIImage) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            let maxDimension: CGFloat = 4096
            let resizedImage: UIImage
            if image.size.width > maxDimension || image.size.height > maxDimension {
                let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat()
                format.opaque = false
                format.scale = image.scale
                format.preferredRange = .extended
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                resizedImage = renderer.image { context in
                    context.cgContext.interpolationQuality = .high
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                resizedImage = image
            }
            return resizedImage.pngData()
        }.value
    }

    /// Worn photos only: shared JPEG pipeline (opaque flatten, ≤2048, q~0.8, ~1 MB).
    private func processWornImageForStorage(_ image: UIImage) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            WornImageCompression.encode(image, logLabel: "Worn")
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
            purgeRetiredBackPhotosIfNeeded()
            try vm.persistToParent()
            print("✅ Item saved successfully")
            if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                print("📸 Moving to next image in queue")
                queueCoordinator.moveToNext()
            }
        } catch {
            print("❌ Save failed: \(error.localizedDescription)")
        }
        DispatchQueue.main.async { self.dismiss() }
    }
    
    /// Single discard entry point — deletes the original draft if one was loaded, otherwise plain rollback.
    private func discardItem() {
        if vm.originalDraftObjectID != nil {
            vm.discardAndDeleteOriginalDraft()
        } else {
            vm.discard()
        }
    }

    private func handleCancelTapped() {
        if hasItemChanges() {
            showingSaveDraftConfirmation = true
        } else {
            if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                discardCurrentAndMoveToNext()
            } else {
                discardItem()
                if queueCoordinator.isQueueActive { queueCoordinator.clear() }
                dismiss()
            }
        }
    }
    
    private func discardCurrentAndMoveToNext() {
        discardItem()
        if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
            print("📸 Discarding current item and moving to next in queue")
            queueCoordinator.moveToNext()
        } else {
            if queueCoordinator.isQueueActive { queueCoordinator.clear() }
        }
        dismiss()
    }
    
    // MARK: - Draft flow

    private func hasItemChanges() -> Bool {
        let item = vm.draftItem

        // Photos (front, worn)
        if getImage(for: .front) != nil { return true }
        if getImage(for: .worn) != nil { return true }

        // AttributesSectionView fields
        if hasNonEmptyTrimmedText(item.name) { return true }
        if vm.wardrobesDifferFromBaseline() { return true }
        if item.category != nil { return true }
        if item.subcategory != nil { return true }
        if hasNonEmptyTrimmedText(item.brand?.name) { return true }
        if item.itemSize != nil { return true }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty { return true }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty { return true }
        if hasNonEmptyTrimmedText(item.location?.name) { return true }
        if item.price?.amount != nil { return true }
        if appCapabilities.showsWeatherAttribute, hasWeatherAttribute(on: item) { return true }
        if appCapabilities.showsWeightAttribute, hasWeightAttribute(on: item) { return true }
        if let links = item.links as? Set<Link>, !links.isEmpty { return true }
        if let tags = item.tags as? Set<Tag>, !tags.isEmpty { return true }
        if hasNonEmptyTrimmedText(item.notes) { return true }

        return false
    }

    private func hasNonEmptyTrimmedText(_ value: String?) -> Bool {
        !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func hasWeatherAttribute(on item: Item) -> Bool {
        item.primitiveValue(forKey: "minTemperature") != nil
            && item.primitiveValue(forKey: "maxTemperature") != nil
    }

    private func hasWeightAttribute(on item: Item) -> Bool {
        guard let weightKg = item.primitiveValue(forKey: "weight") as? Double else { return false }
        return weightKg > 0 && weightKg.isFinite && !weightKg.isNaN
    }
    
    private func saveDraft() {
        do {
            purgeRetiredBackPhotosIfNeeded()
            try vm.persistDraftToParent()
            if queueCoordinator.isQueueActive && queueCoordinator.hasMore {
                print("📸 Draft saved, moving to next image in queue")
                queueCoordinator.moveToNext()
                dismiss()
            } else {
                if queueCoordinator.isQueueActive, let _ = queueCoordinator.currentImage {
                    dismiss()
                } else {
                    if queueCoordinator.isQueueActive { queueCoordinator.clear() }
                    showingDraftSaveAlert = true
                }
            }
        } catch {
            print("❌ Draft save failed: \(error.localizedDescription)")
        }
    }

    private func missingAttributes(of item: Item) -> [String] {
        var blanks: [String] = []
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

    /// Add Multiple → From Library: dismiss add UI, then process on the grid tab (progress overlay + cancel).
    private func beginBulkLibraryImport(with images: [UIImage]) {
        let userIdStr = authSession.userId?.uuidString ?? SupabaseService.shared.currentUser?.id.uuidString
        guard let parentContext = vm.childContext.parent,
              let wardrobeOID = vm.selectedWardrobeObjectID,
              let userIdStr else {
            print("⚠️ Bulk import: missing parent context, wardrobe, or auth")
            return
        }

        vm.discard()
        queueCoordinator.clear()
        dismiss()

        DispatchQueue.main.async {
            bulkItemImportCoordinator.startImport(
                images: images,
                context: parentContext,
                wardrobeObjectID: wardrobeOID,
                userId: userIdStr
            )
        }
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
    /// Captured on the main actor when the view model is created; used where `selectedWardrobe.userId` may be nil.
    private let authUserId: String?
    /// Wardrobes assigned at init / draft load; used to detect user edits in SetWardrobeView.
    private(set) var baselineWardrobeObjectIDs: Set<NSManagedObjectID> = []

    /// User's primary wardrobe for `type` (`isDefault` when set). Used to prepend the default closet/wishlist when adding from a secondary wardrobe of the same type.
    private static func fetchPrimaryWardrobe(forType type: String, userId: String, in context: NSManagedObjectContext) -> Wardrobe? {
        try? WardrobeBootstrap.fetchPrimaryWardrobe(forType: type, userIdString: userId, in: context)
    }

    private static func stampUserId(_ authUserId: String?, on item: Item) {
        if let authUserId = authUserId, !authUserId.isEmpty,
           item.userId == nil || item.userId?.isEmpty == true {
            item.userId = authUserId
        }
    }

    private func stampUserId(on item: Item) {
        Self.stampUserId(authUserId, on: item)
    }

    private func captureWardrobeBaseline(for item: Item) {
        baselineWardrobeObjectIDs = Set((item.wardrobes as? Set<Wardrobe>)?.map(\.objectID) ?? [])
    }

    func wardrobesDifferFromBaseline() -> Bool {
        let current = Set((draftItem.wardrobes as? Set<Wardrobe>)?.map(\.objectID) ?? [])
        return current != baselineWardrobeObjectIDs
    }
    
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?, initialURL: URL? = nil, initialImage: UIImage? = nil, authUserId: String? = nil) {
        self.initialURL = initialURL
        self.initialImage = initialImage
        self.selectedWardrobeObjectID = selectedWardrobe?.objectID
        self.authUserId = authUserId
        
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.parent = parentContext
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = false
        self.childContext = ctx
        
        let item = Item(context: ctx)
        item.id = UUID()
        item.timestamp = Date()
        
        if let wardrobeObjectID = selectedWardrobe?.objectID {
            do {
                let wardrobeInChild = try ctx.existingObject(with: wardrobeObjectID) as? Wardrobe
                if let selected = wardrobeInChild {
                    let type = (selected.type ?? "closet").lowercased()
                    let userId = selected.userId ?? authUserId
                    if let userId = userId, !userId.isEmpty,
                       let primary = Self.fetchPrimaryWardrobe(forType: type, userId: userId, in: ctx),
                       primary.objectID != selected.objectID {
                        // Secondary closet/wishlist: item belongs in that wardrobe and the default row for that type.
                        item.addToWardrobes(primary)
                    }
                    item.addToWardrobes(selected)
                }
            } catch {
                print("⚠️ Warning: Could not re-fetch wardrobe in child context during init: \(error.localizedDescription)")
            }
        }
        
        Self.stampUserId(authUserId, on: item)
        self.draftItem = item
        captureWardrobeBaseline(for: item)
    }

    /// Loads an existing draft item into the child context so edits are sandboxed until save.
    init(parentContext: NSManagedObjectContext, existingDraft: Item, authUserId: String? = nil) {
        self.initialURL = nil
        self.initialImage = nil
        self.selectedWardrobeObjectID = (existingDraft.wardrobes?.anyObject() as? Wardrobe)?.objectID
        self.authUserId = authUserId

        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.parent = parentContext
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = false
        self.childContext = ctx

        if let draftInChild = try? ctx.existingObject(with: existingDraft.objectID) as? Item {
            Self.stampUserId(authUserId, on: draftInChild)
            self.draftItem = draftInChild
        } else {
            // Fallback: create a blank item (shouldn't happen in practice)
            let item = Item(context: ctx)
            item.id = UUID()
            item.timestamp = Date()
            Self.stampUserId(authUserId, on: item)
            self.draftItem = item
            print("⚠️ Could not load existing draft into child context — creating blank item")
        }
        captureWardrobeBaseline(for: draftItem)
    }
    
    // MARK: - Load Existing Draft

    /// Object ID of the original draft loaded via loadExistingDraft.
    /// Used to delete the original when the user cancels without re-saving.
    private(set) var originalDraftObjectID: NSManagedObjectID? = nil

    /// Swaps the active draft item in place so ItemAddView repopulates without opening a new sheet.
    func loadExistingDraft(_ draft: Item) {
        childContext.rollback()
        originalDraftObjectID = draft.objectID
        if let draftInChild = try? childContext.existingObject(with: draft.objectID) as? Item {
            stampUserId(on: draftInChild)
            draftItem = draftInChild
        } else {
            print("⚠️ Could not load draft into child context")
        }
        captureWardrobeBaseline(for: draftItem)
        photoRefreshToken = UUID()
    }

    /// Rolls back the child context and hard-deletes the original draft from the parent context.
    /// Called when the user selects an existing draft then cancels without saving.
    func discardAndDeleteOriginalDraft() {
        childContext.rollback()
        guard let objectID = originalDraftObjectID,
              let parent = childContext.parent else {
            originalDraftObjectID = nil
            return
        }
        do {
            if let original = try? parent.existingObject(with: objectID) as? Item {
                parent.delete(original)
                try parent.save()
                print("🗑️ Deleted original draft after cancel")
            }
        } catch {
            print("⚠️ Could not delete original draft: \(error.localizedDescription)")
        }
        originalDraftObjectID = nil
    }

    @MainActor
    func persistToParent() throws {
        guard let userId = (authUserId.flatMap { UUID(uuidString: $0) }) ?? SupabaseService.shared.currentUser?.id else {
            throw NSError(domain: "ItemAdd", code: -1, userInfo: [NSLocalizedDescriptionKey: "User must be authenticated to save items"])
        }

        // Mutations first — setting isDraft = false on a loaded draft makes childContext.hasChanges
        // true even when the user made no other edits, so the guard below won't prematurely bail out.
        draftItem.isDraft = false
        let savedAt = Date()
        ItemLifecycleDates.applyOnFirstFinalSave(for: draftItem, at: savedAt)
        setUpdatedAt(draftItem)
        if draftItem.userId == nil || draftItem.userId?.isEmpty == true {
            draftItem.userId = userId.uuidString
        }

        guard childContext.hasChanges else { return }

        try childContext.save()
        let itemObjectID = draftItem.objectID
        
        if let parent = childContext.parent {
            do {
                try parent.save()
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
                    if item.userId == nil || item.userId?.isEmpty == true {
                        item.userId = userId.uuidString
                        try parent.save()
                    }
                    let outfitsToSync = OutfitSanitizer.regenerateCollagesForOutfitsContaining(item: item, in: parent)
                    if !outfitsToSync.isEmpty {
                        try parent.save()
                        for outfit in outfitsToSync {
                            SyncService.shared.syncOutfitIfNeeded(outfit)
                        }
                    }
                    print("🔄 Triggering sync for newly saved item: \(item.name ?? "unnamed")")
                    SyncService.shared.syncItemIfNeeded(item)
                } else {
                    print("⚠️ Could not find saved item in parent context for sync")
                }
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && error.code == 133021 {
                    print("⚠️ Constraint conflict detected, attempting to resolve...")
                    try resolveConstraintConflicts(in: parent, error: error)
                    try parent.save()
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
                        if item.userId == nil || item.userId?.isEmpty == true {
                            item.userId = userId.uuidString
                            try parent.save()
                        }
                        let outfitsToSync = OutfitSanitizer.regenerateCollagesForOutfitsContaining(item: item, in: parent)
                        if !outfitsToSync.isEmpty {
                            try parent.save()
                            for outfit in outfitsToSync {
                                SyncService.shared.syncOutfitIfNeeded(outfit)
                            }
                        }
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
        let item = Item(context: childContext)
        item.id = UUID()
        item.timestamp = Date()
        
        if let wardrobe = selectedWardrobe {
            do {
                if let wardrobeInChild = try childContext.existingObject(with: wardrobe.objectID) as? Wardrobe {
                    let type = (wardrobeInChild.type ?? "closet").lowercased()
                    let userId = wardrobeInChild.userId ?? authUserId
                    if let userId = userId, !userId.isEmpty,
                       let primary = Self.fetchPrimaryWardrobe(forType: type, userId: userId, in: childContext),
                       primary.objectID != wardrobeInChild.objectID {
                        item.addToWardrobes(primary)
                    }
                    item.addToWardrobes(wardrobeInChild)
                    print("✅ Assigned wardrobe: \(wardrobeInChild.name ?? "unknown")")
                }
            } catch {
                print("⚠️ Warning: Could not re-fetch wardrobe in child context: \(error.localizedDescription)")
            }
        } else if let wardrobeObjectID = selectedWardrobeObjectID {
            do {
                if let wardrobeInChild = try childContext.existingObject(with: wardrobeObjectID) as? Wardrobe {
                    let type = (wardrobeInChild.type ?? "closet").lowercased()
                    let userId = wardrobeInChild.userId ?? authUserId
                    if let userId = userId, !userId.isEmpty,
                       let primary = Self.fetchPrimaryWardrobe(forType: type, userId: userId, in: childContext),
                       primary.objectID != wardrobeInChild.objectID {
                        item.addToWardrobes(primary)
                    }
                    item.addToWardrobes(wardrobeInChild)
                    print("✅ Assigned wardrobe from objectID: \(wardrobeInChild.name ?? "unknown")")
                }
            } catch {
                print("⚠️ Warning: Could not re-fetch wardrobe in child context: \(error.localizedDescription)")
            }
        }
        
        stampUserId(on: item)
        self.draftItem = item
        self.photoRefreshToken = UUID()
        print("✅ New item created and ready for next image")
    }
    
    private func resolveConstraintConflicts(in context: NSManagedObjectContext, error: NSError) throws {
        guard let conflictList = error.userInfo["conflictList"] as? [NSConstraintConflict] else {
            print("⚠️ Could not extract conflict list from error")
            return
        }
        for conflict in conflictList {
            let conflictingObjects = conflict.conflictingObjects
            if let firstSize = conflictingObjects.first as? Size {
                print("🔧 Resolving Size conflict: keeping size with value '\(firstSize.value ?? "nil")'")
                for conflictedObject in conflictingObjects.dropFirst() {
                    if let sizeToMerge = conflictedObject as? Size {
                        if let items = sizeToMerge.items as? Set<Item> {
                            for item in items { item.itemSize = firstSize }
                        }
                        context.delete(sizeToMerge)
                    }
                }
            }
        }
        try context.save()
        print("✅ Constraint conflicts resolved")
    }
    
    func persistDraftToParent() throws {
        guard childContext.hasChanges else { return }
        draftItem.isDraft = true
        try childContext.save()
        if let parent = childContext.parent, parent.hasChanges {
            try parent.save()
        }
    }
    
    func discard() {
        childContext.rollback()
        originalDraftObjectID = nil
    }
    
    // MARK: - Metadata Extraction
    
    func extractAndApplyMetadata() async {
        guard let url = initialURL else { return }
        await MainActor.run { isExtractingMetadata = true }
        do {
            let metadata = try await ProductMetadataService.shared.fetchMetadata(from: url)
            var fetchedImage: UIImage?
            if let imageURL = metadata.imageURL {
                print("📸 Attempting to fetch image from: \(imageURL)")
                do {
                    let imageData = try await ProductMetadataService.shared.fetchImageData(from: imageURL)
                    guard let image = UIImage(data: imageData) else {
                        await MainActor.run { applyMetadata(metadata, visionCategory: nil); isExtractingMetadata = false }
                        return
                    }
                    fetchedImage = image
                    await MainActor.run { setPrimaryImageFromURL(image: image, originalData: imageData) }
                } catch let error as ProductMetadataService.MetadataError {
                    switch error {
                    case .invalidImageData(let message): print("❌ Invalid image data: \(message)")
                    case .networkError: print("❌ Network error fetching image from: \(imageURL)")
                    case .invalidHTML: print("❌ Invalid HTML")
                    case .webViewTimeout: print("❌ WebView timeout")
                    }
                } catch {
                    print("❌ Failed to fetch image: \(error.localizedDescription)")
                }
            }
            
            var visionCategory: String? = nil
            if let image = fetchedImage {
                do {
                    let visionResult = try await VisionAnalysisService.shared.analyzeCategory(from: image)
                    let combined = VisionAnalysisService.shared.combineCategorySources(urlCategory: metadata.category, visionResult: visionResult)
                    visionCategory = combined.category
                } catch {
                    print("⚠️ Vision analysis failed: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run { applyMetadata(metadata, visionCategory: visionCategory); isExtractingMetadata = false }
        } catch {
            await MainActor.run { isExtractingMetadata = false }
            print("❌ Failed to extract metadata: \(error)")
        }
    }
    
    private func applyMetadata(_ metadata: ProductMetadata, visionCategory: String?) {
        if let title = metadata.title, !title.isEmpty { draftItem.name = title }
        if let brandName = metadata.brand, !brandName.isEmpty { setBrand(name: brandName) }
        if let categoryName = visionCategory ?? VisionAnalysisService.shared.normalizeCategoryFromURL(metadata.category), !categoryName.isEmpty {
            setCategory(name: categoryName)
        }
        if let priceAmount = metadata.price {
            let price = Price(context: childContext)
            if let originalPriceString = metadata.priceString, !originalPriceString.isEmpty {
                let cleanedPrice = originalPriceString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                if !cleanedPrice.isEmpty {
                    price.amount = NSDecimalNumber(string: cleanedPrice, locale: Locale(identifier: "en_US"))
                } else {
                    price.amount = NSDecimalNumber(decimal: priceAmount)
                }
            } else {
                price.amount = NSDecimalNumber(decimal: priceAmount)
            }
            price.currency = metadata.priceCurrency ?? "USD"
            draftItem.price = price
        }
        let link = Link(context: childContext)
        link.id = UUID()
        link.url = metadata.sourceURL
        link.name = extractWebsiteName(from: metadata.sourceURL)
        link.itemLinkType = .purchase
        link.item = draftItem
    }
    
    private func setBrand(name: String) {
        let childRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
        childRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
        if let existingInChild = try? childContext.fetch(childRequest).first {
            draftItem.brand = existingInChild
            return
        }
        if let parentContext = childContext.parent {
            let parentRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
            parentRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
            if let existingInParent = try? parentContext.fetch(parentRequest).first,
               let brandInChild = try? childContext.existingObject(with: existingInParent.objectID) as? Brand {
                draftItem.brand = brandInChild
                return
            }
        }
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
            newCategory.isVisible = true
            draftItem.category = newCategory
        }
    }
    
    func setPrimaryImageFromURL(image: UIImage, originalData: Data) {
        ItemPhotoSlot.deleteMatching(in: draftItem, slot: "front", context: childContext)
        let processedData = image.processForStorage()
        let photo = Photo(context: childContext)
        ItemPhotoSlot.configureReplacedPhoto(
            photo,
            on: draftItem,
            image: image,
            processedData: processedData,
            type: "front",
            asPrimary: true
        )
        photoRefreshToken = UUID()
    }
    
    func setPrimaryImage(_ image: UIImage) {
        Task {
            let processedData = await processImageForStorage(image)
            await MainActor.run {
                ItemPhotoSlot.deleteMatching(in: draftItem, slot: "front", context: childContext)
                let photo = Photo(context: childContext)
                ItemPhotoSlot.configureReplacedPhoto(
                    photo,
                    on: draftItem,
                    image: image,
                    processedData: processedData,
                    type: "front",
                    asPrimary: true
                )
                photoRefreshToken = UUID()
            }
        }
    }
    
    private func processImageForStorage(_ image: UIImage) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            return image.processForStorage(maxDimension: 1200, maxFileSizeKB: 200)
        }.value
    }
    
    private func extractWebsiteName(from url: URL) -> String {
        guard let host = url.host else { return "Product Link" }
        var domain = host.lowercased()
        let subdomainPattern = #"^(www\d*|shop|store|shop-|store-|www-|m|mobile|app)\.?"#
        if let regex = try? NSRegularExpression(pattern: subdomainPattern, options: .caseInsensitive) {
            let range = NSRange(domain.startIndex..., in: domain)
            domain = regex.stringByReplacingMatches(in: domain, options: [], range: range, withTemplate: "")
        }
        domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let firstDot = domain.firstIndex(of: ".") { domain = String(domain[..<firstDot]) }
        let brandMappings: [String: String] = ["hm": "H&M", "zara": "ZARA", "nike": "Nike", "adidas": "adidas", "puma": "PUMA", "gap": "Gap", "oldnavy": "Old Navy", "bananarepublic": "Banana Republic", "athleta": "Athleta"]
        if let mappedBrand = brandMappings[domain] { return mappedBrand }
        let shoppingDomains = ["amazon", "target", "walmart", "ebay", "etsy", "shopify", "bigcommerce"]
        if shoppingDomains.contains(domain) { return domain.capitalized }
        if domain.count > 0 {
            if domain == domain.uppercased() && domain.count <= 5 { return domain.uppercased() }
            return domain.capitalized
        }
        return "Product Link"
    }
}
