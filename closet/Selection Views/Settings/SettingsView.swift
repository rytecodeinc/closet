//
//  SettingsView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct SettingsView: View {
    @Binding var navigationPath: NavigationPath

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var supabaseService: SupabaseService

    @AppStorage("userWeightKg") private var storedWeightKg: Double = 0
    @AppStorage("userWeightUnit") private var storedWeightUnit: String = ""
    @State private var showWeightView = false

    @State private var isSigningOut = false
    @State private var signOutErrorMessage: String?
    @State private var showSignOutError = false
    @State private var showSignOutConfirmation = false

    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var showDeleteAccountError = false

    private var displayWeightText: String? {
        guard storedWeightKg > 0 else { return nil }
        let unit = storedWeightUnit.isEmpty ? (Locale.current.measurementSystem == .metric ? "kg" : "lbs") : storedWeightUnit
        let displayWeight = unit == "kg" ? storedWeightKg : storedWeightKg * 2.20462
        return "\(String(format: "%.1f", displayWeight)) \(unit)"
    }

    var body: some View {
            List {
                Section("Account") {
                    if authSession.isAuthenticated {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(authSession.userEmail ?? "—")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("App Version")
                        Spacer()
                        Text(appCapabilities.tier.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Support") {
                    HStack {
                        Text("Feedback Email")
                        Spacer()
                        Text("redressme@icloud.com")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Privacy")
                        Spacer()
                        Text("redress.me/privacy")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Terms")
                        Spacer()
                        Text("redress.me/terms")
                            .foregroundStyle(.secondary)
                    }
                }

                if appCapabilities.showsWeightAttribute {
                    Button {
                        showWeightView = true
                    } label: {
                        HStack {
                            Text("Weight")
                                .foregroundColor(.primary)
                            Spacer()
                            if let weightText = displayWeightText {
                                Text(weightText)
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }

                if appCapabilities.showsColorSeasonSettings {
                    Button {
                        navigationPath.append(ProfileRoute.attributePreferences)
                    } label: {
                        HStack {
                            Text("Attribute Preferences")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }

                if appCapabilities.showsDeveloperSettings {
                    Section("Developer") {
                        Button {
                            navigationPath.append(ProfileRoute.developerSettings)
                        } label: {
                            HStack {
                                Text("Developer Settings")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if authSession.isAuthenticated {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAccountConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                if isDeletingAccount {
                                    ProgressView()
                                } else {
                                    Text("Delete Account")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isDeletingAccount || isSigningOut)
                    } footer: {
                        Text("Deleting your account permanently removes your Redress account and clears your data on this device. This cannot be undone.")
                    }

                    Section {
                        Button(role: .destructive) {
                            showSignOutConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                if isSigningOut {
                                    ProgressView()
                                } else {
                                    Text("Sign Out")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isSigningOut || isDeletingAccount)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $showWeightView) {
                UserWeightView()
            }
            .confirmationDialog(
                "Confirm Sign Out?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage ?? "")
            }
            .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your account and removes your closet data from this device. This action cannot be undone.")
            }
            .alert("Delete Account Failed", isPresented: $showDeleteAccountError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountErrorMessage ?? "")
            }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await supabaseService.signOut()
        } catch {
            signOutErrorMessage = error.localizedDescription
            showSignOutError = true
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        defer { isDeletingAccount = false }
        do {
            try await supabaseService.deleteAccount()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
            showDeleteAccountError = true
        }
    }
}
