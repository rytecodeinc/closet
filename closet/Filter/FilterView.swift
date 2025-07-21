//
//  FilterView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI

struct FilterView: View {
    @ObservedObject var filterModel: FilterModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: ColorListView(selectedColorNames: $filterModel.selectedColors)) {
                    HStack {
                        Text("Colors")
                        Spacer()
                        if !filterModel.selectedColors.isEmpty {
                            Text(filterModel.selectedColors.sorted().joined(separator: ", "))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


