//
//  UnderlineTabBar.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI

struct UnderlineTabBar: View {
    @Binding var selectedTab: String
    let tabs: [String]

    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tabLabel in
                let baseName = tabLabel.components(separatedBy: " ").first ?? tabLabel
                VStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = baseName
                        }
                    }) {
                        Text(tabLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(selectedTab == baseName ? .primary : .secondary)
                            .contentShape(Rectangle())
                            .padding(.bottom, 6)
                    }

                    // underline
                    if selectedTab == baseName {
                        Capsule()
                            .fill(Color.primary)
                            .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                            .frame(height: 2)
                            .transition(.opacity)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
       // .padding(.vertical, 2)
    }
}

