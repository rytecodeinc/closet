//
//  FilterModel.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

class FilterModel: ObservableObject {
    @Published var selectedColors: Set<String> = []
   
}

func makePredicate(for selectedColors: Set<String>) -> NSPredicate? {
    guard !selectedColors.isEmpty else { return nil } // no filter
    
    // Predicate for colors' name being in the selectedColors set
    return NSPredicate(format: "ANY colors.name IN %@", Array(selectedColors))
}
