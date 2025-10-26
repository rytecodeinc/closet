struct WardrobeListView: View {
    @Binding var selectedWardrobes: Set<Wardrobe>

    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var wardrobes: FetchedResults<Wardrobe>

    var body: some View {
        List {
            ForEach(wardrobes, id: \.self) { wardrobe in
                let name = wardrobe.name ?? "Untitled"
                
                HStack {
                    Text(name)
                        .foregroundColor(.black)
                    Spacer()
                    if selectedWardrobes.contains(wardrobe) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedWardrobes.contains(wardrobe) {
                        selectedWardrobes.remove(wardrobe)
                    } else {
                        selectedWardrobes.insert(wardrobe)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Wardrobes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
