//
//  LaunchView.swift
//  closet
//
//  Cold-start gate: brand surface while session restore and local store warm-up run.
//

import SwiftUI

struct LaunchView: View {
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    let persistence: PersistenceController
    @Binding var launchBootstrapComplete: Bool

    @State private var logoScale: CGFloat = 1.0
    @State private var logoOpacity: Double = 1.0

    private static let brandGradientTop = Color(hex: "#d13438")
    private static let brandGradientBottom = Color(hex: "#931013")
    private static let logoSize: CGFloat = 150
    private static let logoExpandedScale: CGFloat = 1.35
    private static let minimumSplashNanoseconds: UInt64 = 400_000_000
    private static let exitAnimationNanoseconds: UInt64 = 480_000_000

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.brandGradientTop, Self.brandGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Image("AppIconTransparent")
                .resizable()
                .scaledToFit()
                .frame(width: Self.logoSize, height: Self.logoSize)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .accessibilityLabel("Redress")
        }
        .task {
            await runLaunchSequence()
        }
    }

    @MainActor
    private func runLaunchSequence() async {
        async let bootstrap: Void = {
            await supabaseService.awaitSessionRestoration()
            await persistence.warmPersistentStoreForLaunch()
            await authSession.refreshIdentityFromSupabase()
        }()
        async let minimumSplash: Void = {
            try? await Task.sleep(nanoseconds: Self.minimumSplashNanoseconds)
        }()

        _ = await (bootstrap, minimumSplash)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            logoScale = Self.logoExpandedScale
            logoOpacity = 0
        }

        try? await Task.sleep(nanoseconds: Self.exitAnimationNanoseconds)
        launchBootstrapComplete = true
    }
}
