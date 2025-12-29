//
//  ItemAddViewModel.swift
//  closet
//
//  Created by Dan Warner on 8/16/25.
//


import SwiftUI
import CoreData

// MARK: - ItemAddView (init with parentContext; child ctx ready before body)
struct ItemAddView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: ItemAddViewModel
    
    @State private var attributesSheet: AttributesSectionView.Sheet?
    
    // Image handling
    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedUIImage: UIImage?
    @State private var isCropperPresented = false

    // Save warning
    @State private var showMissingWarning = false
    @State private var missingFieldsDescription = ""

    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?) {
        _vm = StateObject(wrappedValue: ItemAddViewModel(parentContext: parentContext, selectedWardrobe: selectedWardrobe))
    }

    var body: some View {
        
        List {
            photoPlaceholderHeader()
                .listRowInsets(EdgeInsets(.zero))
            AttributesSectionView(item: vm.draftItem, activeSheet: $attributesSheet)
        }
        .sheet(item: $attributesSheet) { $0.destination(for: vm.draftItem) }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets())
        .navigationTitle("Add Item")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(role: .destructive) {
                    vm.discard()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .foregroundColor(.red)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    handleSaveTapped()
                }
                .bold()
                .disabled((selectedUIImage ?? currentPrimaryUIImage()) == nil)
            }
            
        }
        // Make the whole subtree use the child context
        .environment(\.managedObjectContext, vm.childContext)
        // Sheets below…

        .fullScreenCover(isPresented: $isImagePickerPresented) {
            ImagePicker(
                image: $selectedUIImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let newImage = image {
                    selectedUIImage = newImage    // <-- show immediately
                    attachPrimaryImage(newImage)      // <-- stage in child
                }
                isImagePickerPresented = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isCropperPresented) {
            if let image = (selectedUIImage ?? currentPrimaryUIImage()) {
                NavigationView {
                    ImageCropperView(
                        originalImage: image,
                        onCrop: { cropped in
                            selectedUIImage = cropped  // <-- show immediately
                            attachPrimaryImage(cropped)   // <-- restage
                        }
                    )
                }
            } else {
                Text("No image to edit").padding()
            }
        }
        .alert("Add Item?", isPresented: $showMissingWarning) {
            Button("Proceed", role: .none) { persistAndDismiss() }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You are saving with the following empty fields: \(missingFieldsDescription). You can fill them later in Item Details.")
        }
    }

    // MARK: - Header (Photo placeholder)
    private func photoPlaceholderHeader() -> some View {
        let displayImage = selectedUIImage ?? currentPrimaryUIImage()

        return
        VStack {
                    ZStack {
                        if let ui = selectedUIImage {
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.width)
                                .clipped()
                                .onTapGesture { isCropperPresented = true }
                                .id(vm.photoRefreshToken)
                                
                        } else {
                            Button {
                                imagePickerSource = .photoLibrary
                                isImagePickerPresented = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 40, weight: .semibold))
                                    Text("Add Photo From Library")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.width)
                                
                             /*   .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                        .foregroundColor(.secondary)
                                )*/
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.gray.opacity(0.1))
                   // .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Quick actions for photo
            Section {
                HStack {
                    Menu {
                        Button {
                            self.imagePickerSource = .camera
                            isImagePickerPresented = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        Button {
                            imagePickerSource = .photoLibrary
                            isImagePickerPresented = true
                        } label: {
                            Label("Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label("Replace Photo", systemImage: "photo.stack")
                    }
                    .disabled(currentPrimaryUIImage() == nil)
                   
                    Spacer()
                    Button {
                        isCropperPresented = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPrimaryUIImage() == nil)
                }
              //  .foregroundColor(.blue)
            }
            .padding(.horizontal)
           // .padding(.vertical, 5)
        }
        
        
        
    }

    // MARK: - Image helpers
    private func currentPrimaryUIImage() -> UIImage? {
        let item = vm.draftItem
        if let primary = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let data = primary.data {
            return UIImage(data: data)
        }
        return nil
    }

    private func attachPrimaryImage(_ image: UIImage) {
        // Process image on background queue to avoid blocking main thread
        Task {
            // Resize and compress image on background queue
            let processedData = await processImageForStorage(image)
            
            // Assign to Core Data on main queue (child context is mainQueueConcurrencyType)
            await MainActor.run {
                let item = vm.draftItem
                if let existing = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }) {
                    vm.childContext.delete(existing)
                }
                let photo = Photo(context: vm.childContext)
                photo.id = UUID()
                photo.isPrimary = true
                photo.data = processedData
                photo.item = item
                // ⬅️ no save here; stays staged in child
                
                // Refresh UI
                vm.photoRefreshToken = UUID()
            }
        }
    }
    
    /// Processes image for storage: resizes to max 2048x2048 and compresses as JPEG
    private func processImageForStorage(_ image: UIImage) async -> Data? {
        return await Task.detached(priority: .userInitiated) {
            // Resize image if needed (max 2048x2048)
            let maxDimension: CGFloat = 2048
            let resizedImage: UIImage
            
            if image.size.width > maxDimension || image.size.height > maxDimension {
                let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                
                // ✅ Make sure the renderer doesn't use opaque format
                let format = UIGraphicsImageRendererFormat()
                format.opaque = false
                format.scale = image.scale
                
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                resizedImage = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                resizedImage = image
            }
            
            // ✅ Use PNG to preserve transparency
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
            try vm.persistToParent()
            dismiss()
        } catch {
            print("❌ Save failed: \(error.localizedDescription)")
        }
    }

    private func missingAttributes(of item: Item) -> [String] {
        var blanks: [String] = []
        if (item.photos as? Set<Photo>)?.isEmpty ?? true { blanks.append("Photo") }
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

    private let selectedWardrobeObjectID: NSManagedObjectID?
    
    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?) {
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
        item.timestamp = Date()
        
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
    
    func persistToParent() throws {
        // Only save if there are actual changes
        guard childContext.hasChanges else { return }
        
        // Note: Wardrobe is already assigned in init, but if it wasn't (e.g., if user removed it),
        // we ensure it's still assigned here as a fallback. However, since we assign it in init,
        // this is mainly for safety. The wardrobe relationship should already be set.
        
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
