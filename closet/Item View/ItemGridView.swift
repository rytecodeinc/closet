//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//


import SwiftUI
import UIKit
import CoreData

struct ItemGridView: View {
    @FetchRequest var closetItems: FetchedResults<Item>
    
    @ObservedObject var filterModel: ItemFilterModel
    var wardrobeType: String
    var selectedWardrobe: Wardrobe
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    @State private var selectedTab: String = "Items"
    
    @State private var outfits: [Outfit] = []
    
    @State private var currentTopIndex: Int? = nil
    @State private var isControlsHidden: Bool = false
    
    init(filterModel: ItemFilterModel, wardrobeType: String, selectedWardrobe: Wardrobe) {
        self.filterModel = filterModel
        self.wardrobeType = wardrobeType
        self.selectedWardrobe = selectedWardrobe
        
        // Base filter from the filterModel
        let basePredicate = makePredicate(for: filterModel)
        
        // Always filter by selected wardrobe
        let wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", selectedWardrobe)
        
        var predicates: [NSPredicate] = []
        if let base = basePredicate { predicates.append(base) }
        predicates.append(wardrobePredicate)
        
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        _closetItems = FetchRequest(
            entity: Item.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
            predicate: finalPredicate
        )
    }

    let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
          //  Divider()
            UnderlineTabBar(
                selectedTab: $selectedTab,
                tabs: ["Items (\(closetItems.count))", "Outfits (\(outfits.count))"]
            )
            
         /*   if !isControlsHidden {
                ControlsBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .top),
                            removal: .push(from: .bottom)
                        )
                    )
            }*/
            
            TabView(selection: $selectedTab) {
                itemsTab.tag("Items")
                outfitsTab.tag("Outfits")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: isControlsHidden)
        .onAppear(perform: fetchOutfits)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: ItemFilterView(filterModel: filterModel)) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == "Items" {
                    NavigationLink(
                        destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)
                    ) {
                        Image(systemName: "plus")
                    }
                } else if selectedTab == "Outfits" {
                    NavigationLink(destination: OutfitCanvasView()) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(
                image: $pickedImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let image = image {
                    createNewItem(with: image, in: selectedWardrobe)
                }
                isImagePickerPresented = false
            }
        }
    }

/*    private var ControlsBar: some View {
        HStack {
            NavigationLink(destination: FilterView(filterModel: filterModel)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            Spacer()
            Image(systemName: "arrow.up.arrow.down")
            Spacer()
            Image(systemName: "square.grid.3x2")
            Spacer()
            NavigationLink(
                destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)
            ) {
                Image(systemName: "plus")
            }
        }
      //  .font(.system(size: 20))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }*/
    
    // MARK: - Core Data fetch
    func fetchOutfits() {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: false)]

        do {
            let allOutfits = try viewContext.fetch(request)
            let filtered = allOutfits.filter { outfit in
                (outfit.items as? Set<Item>)?.contains(where: { $0.wardrobes?.contains(selectedWardrobe) ?? false }) ?? false
            }
            DispatchQueue.main.async {
                self.outfits = filtered
            }
        } catch {
            print("Failed to fetch outfits: \(error)")
            DispatchQueue.main.async {
                self.outfits = []
            }
        }
    }


    // MARK: - Create New Item
    private func createNewItem(with image: UIImage, in wardrobe: Wardrobe) {
        let item = Item(context: viewContext)
        item.id = UUID()
        item.timestamp = Date()
        
        if let imageData = image.pngData() {
            let photo = Photo(context: viewContext)
            photo.data = imageData
            photo.isPrimary = true
            photo.id = UUID()
            photo.item = item
        }

        wardrobe.addToItems(item)   // <-- attach to the correct wardrobe

        do {
            try viewContext.save()
            print("✅ New item saved in \(wardrobe.name ?? "unknown wardrobe")")
            path.append(item)
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
    
    private var itemsTab: some View {
        Group {
            if closetItems.isEmpty {
                EmptyItemStateView()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(Array(closetItems.enumerated()), id: \.element.objectID) { index, item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemView(item: item)
                                  /*  .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(
                                                    key: ScrollOffsetPreferenceKey.self,
                                                    value: geo.frame(in: .named("scroll")).minY < 100 ? index : nil
                                                )
                                        }
                                    )*/
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            /*    .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { topIndex in
                    guard let topIndex = topIndex else { return }
                    handleScroll(topIndex)
                }*/
            }
        }
    }

    private var outfitsTab: some View {
        Group {
            if outfits.isEmpty {
                EmptyOutfitStateView()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(outfits, id: \.objectID) { outfit in
                            NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                                OutfitView(outfit: outfit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

  /*  private func handleScroll(_ topIndex: Int) {
        if let last = currentTopIndex {
            if topIndex > last && !isControlsHidden {
                // Scrolling down
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsHidden = true
                }
            } else if topIndex < last && isControlsHidden {
                // Scrolling up
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsHidden = false
                }
            }
        }
        currentTopIndex = topIndex
    }*/
}

/* MARK: - Scroll Offset PreferenceKey
struct ScrollOffsetPreferenceKey: PreferenceKey {
    typealias Value = Int?
    static var defaultValue: Int? = nil
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
}*/








