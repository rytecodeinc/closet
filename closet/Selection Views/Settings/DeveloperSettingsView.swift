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
    @State private var showStalePrimaryResultAlert = false
    @State private var showStalePrimaryConfirmAlert = false
    @State private var pendingStalePrimaryPlan: StalePrimaryPhotoRepair.Plan?

    @State private var isRecompressingWorn = false
    @State private var wornRecompressAlertTitle = ""
    @State private var wornRecompressAlertMessage = ""
    @State private var showWornRecompressAlert = false

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
                    scanStalePrimaryPhotos()
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
                Text("Scans for leftover primary / duplicate front photos from an older replace-front bug in Core Data and Supabase + R2, then asks for confirmation before deleting. Safe to run more than once.")
            }

            Section {
                Button {
                    recompressWornPhotos()
                } label: {
                    HStack {
                        if isRecompressingWorn {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text("Recompress worn photos")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isRecompressingWorn || authSession.userId == nil)
            } footer: {
                Text("Re-encodes item worn and outfit worn images over 400 KB with the Add Item worn pipeline (opaque JPEG, long edge ≤ 2048, ~0.8 quality, ~1 MB max). Skips front/back cutouts. Marks dirty and syncs. Safe to run more than once.")
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
        .alert("Delete stale photos?", isPresented: $showStalePrimaryConfirmAlert) {
            Button("Cancel", role: .cancel) {
                pendingStalePrimaryPlan = nil
            }
            Button("Delete", role: .destructive) {
                confirmStalePrimaryPhotoDeletion()
            }
        } message: {
            Text(pendingStalePrimaryPlan?.confirmationMessage ?? "")
        }
        .alert(stalePrimaryAlertTitle, isPresented: $showStalePrimaryResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(stalePrimaryAlertMessage)
        }
        .alert(wornRecompressAlertTitle, isPresented: $showWornRecompressAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wornRecompressAlertMessage)
        }
        .fullScreenCover(isPresented: $showHowToOnboardingPreview) {
            HowToOnboardingView(marksCompleteOnFinish: false) {
                showHowToOnboardingPreview = false
            }
        }
    }

    private func recompressWornPhotos() {
        guard let userId = authSession.userId else {
            wornRecompressAlertTitle = "Not signed in"
            wornRecompressAlertMessage = "Sign in to run this repair."
            showWornRecompressAlert = true
            return
        }
        isRecompressingWorn = true
        Task { @MainActor in
            defer { isRecompressingWorn = false }
            do {
                let result = try await WornImageCompression.recompressExisting(
                    for: userId,
                    in: viewContext
                )
                wornRecompressAlertTitle = "Worn recompress complete"
                wornRecompressAlertMessage = result.summaryMessage
                showWornRecompressAlert = true
            } catch {
                wornRecompressAlertTitle = "Worn recompress failed"
                wornRecompressAlertMessage = error.localizedDescription
                showWornRecompressAlert = true
            }
        }
    }

    private func scanStalePrimaryPhotos() {
        guard let userId = authSession.userId else {
            stalePrimaryAlertTitle = "Not signed in"
            stalePrimaryAlertMessage = "Sign in to run this repair."
            showStalePrimaryResultAlert = true
            return
        }
        isPurgingStalePrimaries = true
        pendingStalePrimaryPlan = nil
        Task { @MainActor in
            defer { isPurgingStalePrimaries = false }
            do {
                let plan = try await StalePrimaryPhotoRepair.scanStalePrimaryPhotos(
                    for: userId,
                    in: viewContext
                )
                if plan.isEmpty {
                    stalePrimaryAlertTitle = "Repair complete"
                    stalePrimaryAlertMessage = plan.confirmationMessage
                    showStalePrimaryResultAlert = true
                } else {
                    pendingStalePrimaryPlan = plan
                    showStalePrimaryConfirmAlert = true
                }
            } catch {
                stalePrimaryAlertTitle = "Scan failed"
                stalePrimaryAlertMessage = error.localizedDescription
                showStalePrimaryResultAlert = true
            }
        }
    }

    private func confirmStalePrimaryPhotoDeletion() {
        guard let userId = authSession.userId else {
            pendingStalePrimaryPlan = nil
            stalePrimaryAlertTitle = "Not signed in"
            stalePrimaryAlertMessage = "Sign in to run this repair."
            showStalePrimaryResultAlert = true
            return
        }
        guard let plan = pendingStalePrimaryPlan else { return }
        pendingStalePrimaryPlan = nil
        isPurgingStalePrimaries = true
        Task { @MainActor in
            defer { isPurgingStalePrimaries = false }
            do {
                let result = try await StalePrimaryPhotoRepair.applyStalePrimaryPhotoPlan(
                    plan,
                    for: userId,
                    in: viewContext
                )
                stalePrimaryAlertTitle = "Repair complete"
                stalePrimaryAlertMessage = result.summaryMessage
                showStalePrimaryResultAlert = true
            } catch {
                stalePrimaryAlertTitle = "Repair failed"
                stalePrimaryAlertMessage = error.localizedDescription
                showStalePrimaryResultAlert = true
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
