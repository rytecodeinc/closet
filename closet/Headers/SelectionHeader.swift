//
//  SelectionHeader.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//


import SwiftUI

struct SelectionHeader: View {
    var title: String = "Selection Header"
    var backgroundColor: Color = Color(UIColor.secondarySystemBackground)
    var onTitleTap: (() -> Void)? = nil
    var compactTopSpacing: Bool = false

    var body: some View {
        VStack {
            if let onTitleTap {
                Button(action: onTitleTap) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.black)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.black)
                    }
                }
                .modifier(TitleTapTopPadding(compact: compactTopSpacing))
                .padding(.bottom)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.top)
                    .padding(.bottom)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(backgroundColor)
    }
}

private struct TitleTapTopPadding: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content.padding(.top, 4)
        } else {
            content.padding(.top, 4).padding(.top)
        }
    }
}
