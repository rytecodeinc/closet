import SwiftUI
import CoreData

struct OutfitCategorySelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [Category] = []
    @State private var selectedCategoryNames: Set<String> = []

    var onComplete: ([Category]) -> Void

    var body: some View {
        VStack {
            SelectionHeader(title: "Choose Categories for Outfits")

            if categories.isEmpty {
                Text("No categories have been added.")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(categories, id: \.self) { category in
                        let name = category.name ?? ""
                        HStack {
                            Text(name)
                                .foregroundColor(.black)
                            Spacer()
                            if selectedCategoryNames.contains(name) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(for: name)
                        }
                    }
                }
                .listStyle(.plain)
            }

            Button("Done") {
                let selectedCategories = categories.filter { selectedCategoryNames.contains($0.name ?? "") }
                onComplete(selectedCategories)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .onAppear(perform: fetchCategories)
        .presentationDetents([.medium, .large])
    }

    private func fetchCategories() {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        do {
            categories = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch categories: \(error)")
        }
    }

    private func toggleSelection(for name: String) {
        if selectedCategoryNames.contains(name) {
            selectedCategoryNames.remove(name)
        } else {
            selectedCategoryNames.insert(name)
        }
    }
}
