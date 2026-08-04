//
//  DeveloperSettingsView.swift
//  closet
//

import SwiftUI
import CoreData

struct DeveloperSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var supabaseService: SupabaseService

    @State private var isSeedingDefaultCatalog = false
    @State private var seedCatalogAlertTitle = ""
    @State private var seedCatalogAlertMessage = ""
    @State private var showSeedCatalogAlert = false

    @State private var isRunningWishlistRepair = false
    @State private var wishlistRepairAlertTitle = ""
    @State private var wishlistRepairAlertMessage = ""
    @State private var showWishlistRepairAlert = false

    @State private var isCheckingPhotoStorage = false
    @State private var photoStorageAlertTitle = ""
    @State private var photoStorageAlertMessage = ""
    @State private var showPhotoStorageAlert = false

    @State private var isPurgingStalePrimaries = false
    @State private var stalePrimaryAlertTitle = ""
    @State private var stalePrimaryAlertMessage = ""
    @State private var showStalePrimaryAlert = false

    @State private var showHowToOnboardingPreview = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SignInView()
                } label: {
                    HStack {
                        Image(systemName: "lock")
                        Text("Sign In")
                    }
                }

                NavigationLink {
                    RegisterView()
                        .environmentObject(supabaseService)
                        .environmentObject(authSession)
                        .environment(\.managedObjectContext, viewContext)
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Registration flow")
                    }
                }

                Button {
                    showHowToOnboardingPreview = true
                } label: {
                    HStack {
                        Image(systemName: "book.pages")
                        Text("How-to onboarding")
                    }
                }
            }

            Section {
                Button {
                    seedMissingDefaultCatalog()
                } label: {
                    HStack {
                        if isSeedingDefaultCatalog {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text("Add missing default catalog")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isSeedingDefaultCatalog || authSession.userId == nil)
            } footer: {
                Text("Adds any default colors, seasons, categories, subcategories, and sizes that are not already stored for your account (same lists as app defaults). Safe to run more than once.")
            }

            Section {
                Button {
                    runWishlistClosetRepair()
                } label: {
                    HStack {
                        if isRunningWishlistRepair {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text("Fix wishlist items in closet")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isRunningWishlistRepair || authSession.userId == nil)
            } footer: {
                Text("Removes your closet wardrobe link from items that are also on your wishlist. Safe to run again if duplicates reappear.")
            }

            Section {
                Button {
                    reportPhotoStorageStats()
                } label: {
                    HStack {
                        if isCheckingPhotoStorage {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text("Photo storage report")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isCheckingPhotoStorage)
            } footer: {
                Text("Logs total local photo data size and how many stored images (item photos, thumbnails, outfit images) are over 200 KB. Details also appear in the Xcode console.")
            }

            Section {
                Button {
                    purgeStalePrimaryPhotos()
                } label: {
                    HStack {
                        if isPurgingStalePrimaries {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text("Delete stale primary photos")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isPurgingStalePrimaries || authSession.userId == nil)
            } footer: {
                Text("Removes leftover primary / duplicate front photos from an older replace-front bug (Core Data, then Supabase + R2). Keeps one canonical front per item. Safe to run more than once.")
            }
        }
        .navigationTitle("Developer Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert(seedCatalogAlertTitle, isPresented: $showSeedCatalogAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(seedCatalogAlertMessage)
        }
        .alert(wishlistRepairAlertTitle, isPresented: $showWishlistRepairAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wishlistRepairAlertMessage)
        }
        .alert(photoStorageAlertTitle, isPresented: $showPhotoStorageAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoStorageAlertMessage)
        }
        .alert(stalePrimaryAlertTitle, isPresented: $showStalePrimaryAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(stalePrimaryAlertMessage)
        }
        .fullScreenCover(isPresented: $showHowToOnboardingPreview) {
            HowToOnboardingView(marksCompleteOnFinish: false) {
                showHowToOnboardingPreview = false
            }
        }
    }

    private func purgeStalePrimaryPhotos() {
        guard let userId = authSession.userId else {
            stalePrimaryAlertTitle = "Not signed in"
            stalePrimaryAlertMessage = "Sign in to run this repair."
            showStalePrimaryAlert = true
            return
        }
        isPurgingStalePrimaries = true
        Task { @MainActor in
            defer { isPurgingStalePrimaries = false }
            do {
                let result = try await StalePrimaryPhotoRepair.purgeStalePrimaryPhotos(
                    for: userId,
                    in: viewContext
                )
                stalePrimaryAlertTitle = "Repair complete"
                stalePrimaryAlertMessage = result.summaryMessage
                showStalePrimaryAlert = true
            } catch {
                stalePrimaryAlertTitle = "Repair failed"
                stalePrimaryAlertMessage = error.localizedDescription
                showStalePrimaryAlert = true
            }
        }
    }

    private func reportPhotoStorageStats() {
        isCheckingPhotoStorage = true
        Task { @MainActor in
            defer { isCheckingPhotoStorage = false }
            do {
                let stats = try collectPhotoStorageStats(context: viewContext)
                printPhotoStorageStats(stats, context: viewContext)
                photoStorageAlertTitle = "Photo storage"
                photoStorageAlertMessage = stats.summaryMessage
                showPhotoStorageAlert = true
            } catch {
                photoStorageAlertTitle = "Could not read storage"
                photoStorageAlertMessage = error.localizedDescription
                showPhotoStorageAlert = true
            }
        }
    }

    private func runWishlistClosetRepair() {
        guard let userId = authSession.userId else {
            wishlistRepairAlertTitle = "Not signed in"
            wishlistRepairAlertMessage = "Sign in to run this repair."
            showWishlistRepairAlert = true
            return
        }
        isRunningWishlistRepair = true
        Task { @MainActor in
            defer { isRunningWishlistRepair = false }
            do {
                let count = try WishlistClosetRepair.removeClosetLinksFromWishlistItems(for: userId, in: viewContext)
                wishlistRepairAlertTitle = "Repair complete"
                wishlistRepairAlertMessage = count == 0
                    ? "No items needed changes."
                    : "Updated \(count) item(s): removed closet links from items that were also on your wishlist."
                showWishlistRepairAlert = true
            } catch {
                wishlistRepairAlertTitle = "Repair failed"
                wishlistRepairAlertMessage = error.localizedDescription
                showWishlistRepairAlert = true
            }
        }
    }

    private func seedMissingDefaultCatalog() {
        guard let userId = authSession.userId else {
            seedCatalogAlertTitle = "Not signed in"
            seedCatalogAlertMessage = "Sign in to update your catalog."
            showSeedCatalogAlert = true
            return
        }
        isSeedingDefaultCatalog = true
        Task { @MainActor in
            defer { isSeedingDefaultCatalog = false }
            do {
                let result = try ReferenceDataBootstrap.mergeMissingDefaults(for: userId, in: viewContext)
                if result.isEmpty {
                    seedCatalogAlertTitle = "Already complete"
                    seedCatalogAlertMessage = "Your account already has all default colors, seasons, categories, subcategories, and sizes."
                } else {
                    seedCatalogAlertTitle = "Catalog updated"
                    seedCatalogAlertMessage = [
                        "Added missing rows:",
                        "• \(result.colorsInserted) colors",
                        "• \(result.seasonsInserted) seasons",
                        "• \(result.categoriesInserted) categories",
                        "• \(result.subcategoriesInserted) subcategories",
                        "• \(result.sizesInserted) sizes",
                    ].joined(separator: "\n")
                }
                showSeedCatalogAlert = true
            } catch {
                seedCatalogAlertTitle = "Could not update"
                seedCatalogAlertMessage = error.localizedDescription
                showSeedCatalogAlert = true
            }
        }
    }
}
