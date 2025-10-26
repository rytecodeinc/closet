import SwiftUI
import MapKit

struct LocationSnapshotView: View {
    let address: String
    @State private var snapshotImage: UIImage? = nil

    var body: some View {
        Group {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                    )
                    .aspectRatio(16/9, contentMode: .fill)
            }
        }
        .task {
            await generateSnapshot(for: address)
        }
    }

    // MARK: - Map Snapshot Generation
    func generateSnapshot(for address: String) async {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let location = placemarks.first?.location else { return }

            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            options.size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 9 / 16)
            options.scale = UIScreen.main.scale

            let snapshotter = MKMapSnapshotter(options: options)
            let snapshot = try await snapshotter.start()
            snapshotImage = snapshot.image
        } catch {
            print("Error generating map snapshot: \(error)")
        }
    }
}
