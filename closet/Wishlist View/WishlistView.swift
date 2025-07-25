import SwiftUI
import CoreData

struct WishlistView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var filterModel = FilterModel()
    
    var body: some View {
        NavigationView {
            let basePredicate = makePredicate(for: filterModel)
            let wishlistPredicate = NSPredicate(format: "isWishlist == true")
            
            let finalPredicate = basePredicate.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [$0, wishlistPredicate])
            } ?? wishlistPredicate
            
            ItemGridView(predicate: finalPredicate, filterModel: filterModel)
                .navigationTitle("Wishlist")
        }
    }
}
