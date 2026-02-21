//
//  SelectionHeader.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//


import SwiftUI

struct SelectionHeader: View {
    var title: String = "Selection Header"
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
                .padding(.top)
                .padding(.bottom)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
}
