//
//  SettingsView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession

    @AppStorage("userWeightKg") private var storedWeightKg: Double = 0
    @AppStorage("userWeightUnit") private var storedWeightUnit: String = ""
    @State private var showWeightView = false

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
    
    private var displayWeightText: String? {
        guard storedWeightKg > 0 else { return nil }
        let unit = storedWeightUnit.isEmpty ? (Locale.current.measurementSystem == .metric ? "kg" : "lbs") : storedWeightUnit
        let displayWeight = unit == "kg" ? storedWeightKg : storedWeightKg * 2.20462
        return "\(String(format: "%.1f", displayWeight)) \(unit)"
    }
    
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LoginView()
                } label: {
                    HStack {
                        Image(systemName: "lock")
                        Text("Login")
                    }
                }
                
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
                
                NavigationLink(destination: ColorVisibilityView()) {
                    Text("Colors")
                }
                NavigationLink(destination: SeasonVisibilityView()) {
                    Text("Seasons")
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
                // Add more categories here later (Size, etc)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showWeightView) {
                UserWeightView()
            }
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


