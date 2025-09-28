import SwiftUI
import CoreData

struct EventOutfitSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let event: Event
    var onComplete: ([Outfit]) -> Void

    @State private var outfits: [Outfit] = []
    @State private var selectedOutfitIDs: Set<NSManagedObjectID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SelectionHeader(title: "Select Outfits for Event")

            if outfits.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hanger")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No outfits available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add outfits to your closet first")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(outfits, id: \.objectID) { outfit in
                            OutfitRowView(outfit: outfit, isSelected: selectedOutfitIDs.contains(outfit.objectID))
                                .onTapGesture {
                                    toggleSelection(for: outfit)
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
            }

            Button("Done") {
                let selectedOutfits = outfits.filter { selectedOutfitIDs.contains($0.objectID) }
                onComplete(selectedOutfits)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .onAppear(perform: fetchOutfits)
        .presentationDetents([.medium, .large])
    }

    private func fetchOutfits() {
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.name, ascending: true)]
        do {
            outfits = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch outfits: \(error)")
            outfits = []
        }

        // Preselect outfits already added to the event
        if let eventOutfits = event.outfits as? Set<Outfit> {
            selectedOutfitIDs = Set(eventOutfits.map { $0.objectID })
        }
    }

    private func toggleSelection(for outfit: Outfit) {
        if selectedOutfitIDs.contains(outfit.objectID) {
            selectedOutfitIDs.remove(outfit.objectID)
        } else {
            selectedOutfitIDs.insert(outfit.objectID)
        }
    }
}

// MARK: - Outfit Row View
struct OutfitRowView: View {
    let outfit: Outfit
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(outfit.name ?? "Unnamed Outfit")
                .foregroundColor(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Selection Header
struct SelectionHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary)
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.vertical, 12)

            Divider()
        }
        .padding(.horizontal)
    }
}
