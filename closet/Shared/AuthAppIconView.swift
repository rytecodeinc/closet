//
//  AuthAppIconView.swift
//  closet
//

import SwiftUI

/// App icon shown on sign-in, register, and password-reset headers.
struct AuthAppIconView: View {
    var size: CGFloat = 80

    var body: some View {
        Image("appIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("Redress")
    }
}
