//
//  PriceSelectionView.swift
//  closet
//
//  Created by Dan Warner on 8/3/25.
//


import SwiftUI
import CoreData

struct PriceSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var priceInput: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            SelectionHeader(title: "Set Price")

            HStack {
                TextField("Enter price", text: $priceInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Save") {
                    savePrice()
                }
                .disabled(!isValidDecimal)
            }
            .padding(.horizontal)
            Spacer()
        }
        .onAppear {
            if let existingAmount = item.price?.amount as Decimal? {
                priceInput = NSDecimalNumber(decimal: existingAmount).stringValue
            }
        }
        .presentationDetents([.medium])
    }

    private var isValidDecimal: Bool {
        Decimal(string: priceInput) != nil
    }

    private func savePrice() {
        guard let decimalValue = Decimal(string: priceInput) else { return }

        // Always create a new Price object to ensure SwiftUI detects the change
        let newPrice = Price(context: viewContext)
        newPrice.amount = NSDecimalNumber(decimal: decimalValue)
        item.price = newPrice

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Failed to save price: \(error.localizedDescription)")
        }
    }
}


