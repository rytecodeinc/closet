//
//  AuthView.swift
//  closet
//
//  Created for Redress — unauthenticated entry (sign in / register).
//

import SwiftUI
import CoreData

struct AuthView: View {
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext

    @State private var path: [AuthRoute] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAuthChrome = false
    @State private var shouldAnimateGIF = false

    /// RedressAuthView.gif is 675×1200.
    private let authGIFAspectRatio: CGFloat = 4000.0 / 5926.0

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                AnimatedGIFView(
                    name: "Redress235",
                    aspectRatio: authGIFAspectRatio,
                    contentMode: .scaleAspectFit,
                    reduceMotion: reduceMotion,
                    shouldAnimate: shouldAnimateGIF,
                    animationRepeatCount: 1
                )
                .aspectRatio(authGIFAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
                .padding(.top, 10)
                .scaleEffect(1.2)
                
                VStack(spacing: 35) {
                    VStack(spacing: 5) {
                        Text("Redress")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Beta Version 1.0")
                            .font(.subheadline)
                    }
                    
                    VStack(spacing: 14) {
                        NavigationLink(value: AuthRoute.signIn) {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                                .background(.teal.gradient)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink(value: AuthRoute.register) {
                            Text("Register")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.teal)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.black.opacity(0.95), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 40)
                }
                .offset(y: -50)
            }
            .opacity(showAuthChrome ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AuthRoute.self) { destination in
                let router = AuthFlowRouter(path: $path)
                switch destination {
                case .signIn:
                    SignInView()
                        .environmentObject(supabaseService)
                        .environmentObject(syncService)
                        .environmentObject(authSession)
                        .environment(\.managedObjectContext, viewContext)
                        .authFlowRouter(router)
                case .register:
                    RegisterView()
                        .environmentObject(supabaseService)
                        .environmentObject(authSession)
                        .environment(\.managedObjectContext, viewContext)
                        .authFlowRouter(router)
                }
            }
        }
        .onAppear {
            presentAuthChromeThenPlayGIF()
        }
        .onChange(of: authSession.isAuthenticated) { _, isAuthed in
            if isAuthed {
                path.removeAll()
            }
        }
    }

    private func presentAuthChromeThenPlayGIF() {
        showAuthChrome = false
        shouldAnimateGIF = false

        withAnimation(.easeOut(duration: 0.4)) {
            showAuthChrome = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !reduceMotion else { return }
            shouldAnimateGIF = true
        }
    }
}
