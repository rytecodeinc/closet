struct CreateOutfitView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var canvasItems: [CanvasItem] = []
    @State private var selectedItems: [Item] = []

    let canvasSize = UIScreen.main.bounds.width

    var body: some View {
        VStack {
            // Canvas area
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: canvasSize, height: canvasSize)

                ForEach($canvasItems) { $canvasItem in
                    if let photoData = canvasItem.item.photos?.first?.imageData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .offset(canvasItem.offset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        canvasItem.offset = value.translation
                                    }
                            )
                    }
                }
            }

            Divider()

            // Grid view of items to add
            ItemGridView(items: fetchAllItems(), selectionHandler: { item in
                addItemToCanvas(item)
            })
        }
        .navigationTitle("Create an Outfit")
        .toolbar {
            Button("Save") {
                saveOutfit()
            }
        }
    }
}
