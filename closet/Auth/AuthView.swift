//
//  AuthView.swift
//  closet
//
//  Created for Redress — unauthenticated entry (login / register).
//

import SwiftUI
import CoreData

private enum AuthNavigation: Hashable {
    case login
    case register
}

struct AuthView: View {
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext

    @State private var path: [AuthNavigation] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.red.ignoresSafeArea()

                VStack(spacing: 28) {
                    Text("Redress")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    VStack(spacing: 14) {
                        NavigationLink(value: AuthNavigation.login) {
                            Text("Log In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.white)
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: AuthNavigation.register) {
                            Text("Register")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AuthNavigation.self) { destination in
                switch destination {
                case .login:
                    LoginView()
                        .environmentObject(supabaseService)
                        .environmentObject(syncService)
                        .environment(\.managedObjectContext, viewContext)
                case .register:
                    SignUpView()
                        .environmentObject(supabaseService)
                }
            }
        }
        .onChange(of: supabaseService.isAuthenticated) { _, isAuthed in
            if isAuthed {
                path.removeAll()
            }
        }
    }
}
