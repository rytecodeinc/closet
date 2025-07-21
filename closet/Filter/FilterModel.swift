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
    @Published var selectedSeasons: Set<String> = []
}


func makePredicate(for filterModel: FilterModel) -> NSPredicate? {
    var subpredicates: [NSPredicate] = []

    if !filterModel.selectedColors.isEmpty {
        let colorPredicate = NSPredicate(format: "ANY colors.name IN %@", Array(filterModel.selectedColors))
        subpredicates.append(colorPredicate)
    }

    if !filterModel.selectedSeasons.isEmpty {
        let seasonPredicate = NSPredicate(format: "ANY seasons.name IN %@", Array(filterModel.selectedSeasons))
        subpredicates.append(seasonPredicate)
    }

    if subpredicates.isEmpty {
        return nil
    } else if subpredicates.count == 1 {
        return subpredicates.first
    } else {
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
}
