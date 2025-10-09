struct AllOutfitsGridView: View {
    let outfits: [Outfit]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(outfits, id: \.objectID) { outfit in
                    NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                        VStack(alignment: .leading, spacing: 4) {
                            OutfitImageView(outfit: outfit)
                                .frame(height: 180)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.2))
                                )
                            
                            if let name = outfit.name, !name.isEmpty {
                                Text(name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Featured Outfits")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
