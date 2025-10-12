struct EventIndividualItemSelection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let event: Event

    @State private var items: [Item] = []
    @State private var selectedItemIDs: Set<UUID> = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 2.0

    var body: some View {
        VStack {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No items in closet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add items to your closet to see them here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        ForEach(items, id: \.objectID) { item in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    toggleSelection(for: item)
                                } label: {
                                    if let photoData = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary })?.data,
                                       let uiImage = UIImage(data: photoData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: squareSize)
                                            .clipped()
                                            .border(selectedItemIDs.contains(item.id ?? UUID()) ? Color.blue : Color.gray.opacity(0), width: 2)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray5))
                                            .frame(width: squareSize, height: squareSize)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if selectedItemIDs.contains(item.id ?? UUID()) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 20))
                                        .padding(6)
                                }
                            }
                        }
                    }
                }
            }
            
            Button("Done") {
                saveSelectedItems()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle("Select Items for Event")
        .onAppear {
            fetchItems()
            preselectExistingItems()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Core Data fetch
    private func fetchItems() {
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)]
        do {
            let results = try viewContext.fetch(request)
            DispatchQueue.main.async { self.items = results }
        } catch {
            print("Failed to fetch items: \(error)")
            DispatchQueue.main.async { self.items = [] }
        }
    }

    // MARK: - Preselect items already linked to event
    private func preselectExistingItems() {
        if let existingItems = event.items as? Set<Item> {
            selectedItemIDs = Set(existingItems.compactMap { $0.id })
        }
    }

    // MARK: - Selection
    private func toggleSelection(for item: Item) {
        guard let id = item.id else { return }
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
            event.removeFromItems(item)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    // MARK: - Save selection to event
    private func saveSelectedItems() {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id ?? UUID()) }
        for item in selectedItems {
            event.addToItems(item)
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to save items to event: \(error)")
        }
    }
}
