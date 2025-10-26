struct EventDetailView: View {
    let event: Event

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header image (if location image exists)
                if let locationImage = getLocationImage(for: event.location) {
                    Image(uiImage: locationImage)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.name ?? "Untitled Event")
                        .font(.title)
                        .fontWeight(.bold)
                    if let time = event.time {
                        Text(dateFormatter.string(from: time))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let location = event.location {
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Outfits
                if let outfitsSet = event.outfits as? Set<Outfit>, !outfitsSet.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Outfits")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(Array(outfitsSet), id: \.objectID) { outfit in
                            if let data = outfit.image, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal)
                            }
                        }
                    }
                }

                // Individual items
                if let itemsSet = event.items as? Set<Item>, !itemsSet.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Items")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(Array(itemsSet), id: \.objectID) { item in
                            if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                               let data = primaryPhoto.data,
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Example placeholder: you can integrate with WeatherKit/MapKit for real location images
    func getLocationImage(for location: String?) -> UIImage? {
        guard let location = location, !location.isEmpty else { return nil }
        return UIImage(systemName: "map") // placeholder
    }
}
