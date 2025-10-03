//
//  ItemAddViewModel.swift
//  closet
//
//  Created by Dan Warner on 8/16/25.
//


import SwiftUI
import CoreData

// MARK: - ViewModel
final class ItemAddViewModel: ObservableObject {
    let childContext: NSManagedObjectContext
    @Published var draftItem: Item
    @Published var photoRefreshToken = UUID()

    init(parentContext: NSManagedObjectContext, selectedWardrobe: Wardrobe?) {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.parent = parentContext
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.childContext = ctx

        let item = Item(context: ctx)
        item.id = UUID()
        item.timestamp = Date()

        // ✅ Attach item to the selected Wardrobe
        if let wardrobe = selectedWardrobe {
            // Re-fault into child context
            if let childWardrobe = ctx.object(with: wardrobe.objectID) as? Wardrobe {
                childWardrobe.addToItems(item)
            }
        }

        self.draftItem = item
    }

    func persistToParent() throws {
        if childContext.hasChanges { try childContext.save() }
        try childContext.parent?.save()
    }

    func discard() {
        childContext.rollback()
    }
}



// MARK: - Reusable attributes section (unchanged rows, but sheets inherit child ctx)
private struct ItemAttributesSection: View {
    @ObservedObject var item: Item

    @State private var isCategoryDrawerPresented = false
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
            categoryRow()
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
            CategorySelectionView(item: item)
                .environment(\.managedObjectContext, item.managedObjectContext!) // ensure child ctx
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
            ColorSelectionView(item: item)
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
            SeasonSelectionView(item: item)
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
            PriceSelectionView(item: item)
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
            LinkSelectionView(item: item)
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
            LocationSelectionView(item: item)
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
            TagSelectionView(item: item)
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
       // .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
          /*  ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    vm.discard()
                    dismiss()
                }
            }*/
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
        let item = vm.draftItem
        if let existing = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }) {
            vm.childContext.delete(existing)
        }
        let photo = Photo(context: vm.childContext)
        photo.id = UUID()
        photo.isPrimary = true
        photo.data = image.pngData()
        photo.item = item
        // ⬅️ no save here; stays staged in child
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
