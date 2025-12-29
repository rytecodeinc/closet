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
    
    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedUIImage: UIImage?
    
    @State private var isCropperPresented = false

    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                List {
                    ItemView(item: item)
                        .listRowInsets(EdgeInsets(.zero))
                        .listRowSeparator(.hidden)
                        .listSectionSpacing(.compact)
                    
                    /* Share button icon
                    if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                       let imageData = primaryPhoto.data,
                       let image = UIImage(data: imageData) {
                        
                        HStack {
                               // Text("Search with Google Lens")
                                Spacer()
                                ShareLink(item: Image(uiImage: image), preview: SharePreview("Share Item", image: Image(uiImage: image))) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        .listRowSeparator(.hidden)
                    }*/
                    
                    // ATTRIBUTES Section
                //    if isEditingAttributes {
                        Section{
                            AttributesSectionView(item: item, activeSheet: $attributesSheet)
                                .transition(.opacity.combined(with: .slide))
                                .listRowInsets(EdgeInsets(top: 05, leading: 20, bottom: 05, trailing: 20))
                        } header: {
                            HStack {
                                Text("ATTRIBUTES")
                                    .fontWeight(.semibold)
                                Spacer()
                                if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                                   let imageData = primaryPhoto.data,
                                   let image = UIImage(data: imageData) {

                                    let shareText = """
                                    \(item.name ?? "Wishlist Item")
                                    Brand: \(item.brand?.name ?? "N/A")
                                    Size: \(item.size?.value ?? "N/A")
                                    Category: \(item.category?.name ?? "N/A")
                                    """

                                    let sharePayload = ShareableItem(text: shareText, image: image)

                                    ShareLink(
                                        item: sharePayload,
                                        preview: SharePreview(item.name ?? "Share Item", image: Image(uiImage: image))
                                    ) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                }
                            }
                        }
                      //  .listRowInsets(EdgeInsets(.zero))
                            
                /*    } else {
                        Section {
                            AttributesDisplayView(item: item)
                                .transition(.opacity.combined(with: .slide))
                               // .listRowInsets(EdgeInsets(top: 05, leading: 20, bottom: 05, trailing: 20))
                        } header: {
                            HStack {
                                Text("ATTRIBUTES")
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(isEditingAttributes ? "Done" : "Edit") {
                                    withAnimation {
                                        isEditingAttributes.toggle()
                                        attributesSheet = nil // reset binding when switching
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                        }
                       // .listRowInsets(EdgeInsets(.zero))
                    }*/
                    
                    
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
                                    Text("View All")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
               // .listSectionSpacing(.compact)
            }
        }
        .sheet(item: $attributesSheet) { $0.destination(for: item) }
        .onAppear {
            fetchOutfits()
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        imagePickerSource = .camera
                        isImagePickerPresented = true
                    } label: {
                        Label("Take New Photo", systemImage: "camera")
                    }

                    Button {
                        imagePickerSource = .photoLibrary
                        isImagePickerPresented = true
                    } label: {
                        Label("Replace Image", systemImage: "photo.on.rectangle.angled")
                    }

                    Button {
                        presentCropperForExistingImage()
                    } label: {
                        Label("Edit Image", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        deleteItem()
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
                if let newImage = image {
                    replacePrimaryImage(with: newImage)
                }
                isImagePickerPresented = false
            }
        }
        .sheet(isPresented: $isCropperPresented) {
            if let image = getCurrentPrimaryUIImage() {
                NavigationView {
                    ImageCropperView(
                        originalImage: image,
                        onCrop: { croppedImage in
                            replacePrimaryImage(with: croppedImage)
                        }
                    )
                }
            } else {
                Text("No image found to edit.")
                    .padding()
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
        
    }
    
    // MARK: - Edit Button
    private func presentCropperForExistingImage() {
        isCropperPresented = true
    }
    private func getCurrentPrimaryUIImage() -> UIImage? {
        if let primary = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let data = primary.data,
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }


    // MARK: - Replace Button
    private func replacePrimaryImage(with image: UIImage) {
        // Remove existing primary photo
        if let existingPrimary = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }) {
            viewContext.delete(existingPrimary)
        }

        // Create and assign new photo
        let newPhoto = Photo(context: viewContext)
        newPhoto.id = UUID()
        newPhoto.data = image.pngData()
        newPhoto.isPrimary = true
        newPhoto.item = item

        do {
            try viewContext.save()
            print("✅ Replaced primary photo.")
        } catch {
            print("❌ Failed to save new photo: \(error.localizedDescription)")
        }
    }


    // MARK: - Header Image

    private func itemImageHeader() -> some View {
        ZStack {
            // Get primary photo data if available
            let displayImage: UIImage? = {
                if let primaryPhoto = item.photos?.compactMap({ $0 as? Photo }).first(where: { $0.isPrimary }) {
                    return UIImage(data: primaryPhoto.data ?? Data())
                }
                return nil
            }()
            
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
                
                item.timestamp = Date()
                
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
        request.predicate = NSPredicate(format: "type == %@", type)
        return try? viewContext.fetch(request).first
    }
    
    private func fetchOutfits() {
        // Only fetch if the object has been saved and has an ID
        guard !item.objectID.isTemporaryID else {
            outfits = []
            return
        }
        
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.predicate = NSPredicate(format: "ANY items == %@", item)
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

    func deleteItem() {
        viewContext.delete(item)

        do {
            try viewContext.save()
            dismiss() // Go back after deletion
        } catch {
            // Handle the error (e.g., log it or show alert)
            print("Failed to delete item: \(error.localizedDescription)")
        }
    }
    
    private func SearchWithGoogleLens() {
        guard let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
              let imageData = primaryPhoto.data,
              let image = UIImage(data: imageData) else {
            print("❌ No primary image found")
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
}




