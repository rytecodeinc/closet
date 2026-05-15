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
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#8A000A"), Color(hex: "#000000")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            Text("Redress")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .foregroundStyle(.white)
        }
        .task {
            await supabaseService.awaitSessionRestoration()
            persistence.warmPersistentStoreForLaunch()
            authSession.refreshIdentityFromSupabase()
            launchBootstrapComplete = true
        }
    }
}
