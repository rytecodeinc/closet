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
    #if !TESTFLIGHT
    @State private var shouldAnimateGIF = false
    #endif

    /// RedressAuthView.gif is 675×1200.
    private let authGIFAspectRatio: CGFloat = 4000.0 / 5926.0

    #if TESTFLIGHT
    private static let brandGradientTop = Color(hex: "#d13438")
    private static let brandGradientBottom = Color.cayenne
    private static let brandLogoSize: CGFloat = 150
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                #if TESTFLIGHT
                testFlightAuthContent
                #else
                productionAuthContent
                #endif
            }
            .opacity(showAuthChrome ? 1 : 0)
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
            #if TESTFLIGHT
            presentAuthChrome()
            #else
            presentAuthChromeThenPlayGIF()
            #endif
        }
        .onChange(of: authSession.isAuthenticated) { _, isAuthed in
            if isAuthed {
                path.removeAll()
            }
        }
    }

    #if TESTFLIGHT
    private var testFlightAuthContent: some View {
        ZStack {
            LinearGradient(
                colors: [Self.brandGradientTop, Self.brandGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 35) {
                VStack(spacing: 16) {
                    Image("Redress.SFSymbol")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: Self.brandLogoSize, height: Self.brandLogoSize)
                        .accessibilityHidden(true)

                    authTitleBlock
                }

                authButtons
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif

    #if !TESTFLIGHT
    private var productionAuthContent: some View {
        VStack(spacing: 0) {
            Image("AuthViewCollage")
                .resizable()
                .scaledToFit()
                .aspectRatio(authGIFAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
                .padding(.top, 10)
                .scaleEffect(1.2)

//            AnimatedGIFView(
//                name: "Redress235",
//                aspectRatio: authGIFAspectRatio,
//                contentMode: .scaleAspectFit,
//                reduceMotion: reduceMotion,
//                shouldAnimate: shouldAnimateGIF,
//                animationRepeatCount: 1
//            )
//            .aspectRatio(authGIFAspectRatio, contentMode: .fit)
//            .frame(maxWidth: .infinity)
//            .ignoresSafeArea()
//            .padding(.top, 10)
//            .scaleEffect(1.2)

            VStack(spacing: 35) {
                authTitleBlock
                authButtons
            }
            .offset(y: -50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    #endif

    private var authTitleBlock: some View {
        VStack(spacing: 5) {
            Text("Redress")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Beta Version 1.0")
                .font(.subheadline)
        }
        #if TESTFLIGHT
        .foregroundStyle(.white)
        #endif
    }

    private var authButtons: some View {
        VStack(spacing: 14) {
            NavigationLink(value: AuthRoute.signIn) {
                Text("Sign In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    #if TESTFLIGHT
                    .background(Color.black.gradient)
                    #else
                    .background(.teal.gradient)
                    #endif
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            NavigationLink(value: AuthRoute.register) {
                Text("Register")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    #if TESTFLIGHT
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.95), lineWidth: 1)
                    )
                    #else
                    .foregroundStyle(.teal)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.black.opacity(0.95), lineWidth: 1)
                    )
                    #endif
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }

    #if TESTFLIGHT
    private func presentAuthChrome() {
        showAuthChrome = false
        withAnimation(.easeOut(duration: 0.4)) {
            showAuthChrome = true
        }
    }
    #endif

    #if !TESTFLIGHT
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
    #endif
}
