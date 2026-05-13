//
//  LoginView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI
import CoreData

struct LoginView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSignUp = false
    @State private var isEditingUsername = false
    @State private var editedUsername: String = ""
    @State private var isSavingUsername = false
    @State private var isEditingDisplayName = false
    @State private var editedDisplayName: String = ""
    @State private var isSavingDisplayName = false
    @State private var showCleanupConfirmation = false
    @State private var isCleaningUp = false
    @State private var cleanupMessage: String?
    @State private var refreshToken = UUID()
    @State private var showPurgeOutfitsConfirmation = false
    @State private var isPurgingOutfits = false
    @State private var purgeOutfitsMessage: String?
    @State private var showPurgeOrphanedWardrobesConfirmation = false
    @State private var isPurgingOrphanedWardrobes = false
    @State private var purgeOrphanedWardrobesMessage: String?
    
    // Fetch user profile to observe changes
    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: []
    ) private var allUserProfiles: FetchedResults<UserProfile>
    
    // Filter user profiles by current user (if authenticated)
    private var userProfiles: [UserProfile] {
        guard let userId = supabaseService.currentUser?.id.uuidString else {
            return []
        }
        return allUserProfiles.filter { $0.userId == userId }
    }
    
    private var profileRepository: UserProfileRepository {
        UserProfileRepository(context: viewContext)
    }
    
    // Get profile from fetched results (observes Core Data changes)
    private var userProfile: UserProfile? {
        userProfiles.first
    }
    
    private var currentDisplayName: String? {
        userProfile?.displayName
    }
    
    private var currentUsername: String? {
        userProfile?.username ?? supabaseService.cachedUsername
    }
    
    var body: some View {
        ScrollView {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.accentColor)
                    
                    Text(supabaseService.isAuthenticated ? "Hello, \(supabaseService.currentUser?.email ?? "User")!" :"Login")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Sign in to sync your closet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                if supabaseService.isAuthenticated {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.green)
                        
                        Text("Successfully Logged In")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        // Display Name with edit functionality
                        HStack(spacing: 8) {
                            Text("Display Name:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if isEditingDisplayName {
                                TextField("Display Name", text: $editedDisplayName)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.words)
                                    .frame(maxWidth: 200)
                            } else {
                                Text(currentDisplayName ?? "Name")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button {
                                if isEditingDisplayName {
                                    Task { await saveDisplayName() }
                                } else {
                                    startEditingDisplayName()
                                }
                            } label: {
                                if isSavingDisplayName {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(0.8)
                                } else if isEditingDisplayName {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                } else {
                                    Image(systemName: "pencil").foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSavingDisplayName)
                        }
                        .padding(.horizontal)
                        
                        // Username with edit functionality
                        HStack(spacing: 8) {
                            Text("Username:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if isEditingUsername {
                                TextField("username", text: $editedUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled(true)
                                    .frame(maxWidth: 150)
                            } else {
                                Text(currentUsername ?? "username")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button {
                                if isEditingUsername {
                                    Task { await saveUsername() }
                                } else {
                                    startEditingUsername()
                                }
                            } label: {
                                if isSavingUsername {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(0.8)
                                } else if isEditingUsername {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                } else {
                                    Image(systemName: "pencil").foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSavingUsername)
                        }
                        .padding(.horizontal)
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                        
                        Button {
                            Task { await signOut() }
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out").fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                        
                        // MARK: - Maintenance Buttons
                        VStack(spacing: 10) {
                            // Cleanup Orphaned Data (Supabase/R2)
                            Button {
                                showCleanupConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.circle")
                                    Text("Clean Up Orphaned Data").fontWeight(.semibold)
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isCleaningUp)
                            
                            if let message = cleanupMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("✅") ? .green : .red)
                                    .padding(.horizontal)
                            }
                            
                            // Purge Soft-Deleted Outfits (local Core Data)
                            Button {
                                showPurgeOutfitsConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "tshirt")
                                    Text("Purge Deleted Outfits").fontWeight(.semibold)
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPurgingOutfits)
                            
                            if let message = purgeOutfitsMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("✅") ? .green : .red)
                                    .padding(.horizontal)
                            }

                            // Purge Orphaned Wardrobes (local Core Data)
                            Button {
                                showPurgeOrphanedWardrobesConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "folder.badge.minus")
                                    Text("Purge Orphaned Wardrobes").fontWeight(.semibold)
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPurgingOrphanedWardrobes)

                            if let message = purgeOrphanedWardrobesMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("✅") ? .green : .red)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .task {
                        if supabaseService.isAuthenticated {
                            let needsUsername = currentUsername == nil
                            let needsDisplayName = currentDisplayName == nil
                            
                            if needsUsername || needsDisplayName {
                                do {
                                    _ = try await supabaseService.getUsername()
                                    try? await Task.sleep(nanoseconds: 100_000_000)
                                    viewContext.refreshAllObjects()
                                    refreshToken = UUID()
                                } catch {
                                    print("⚠️ Error loading profile from Supabase: \(error.localizedDescription)")
                                    viewContext.refreshAllObjects()
                                    refreshToken = UUID()
                                }
                            }
                        }
                    }
                    .onChange(of: userProfiles.count) { _ in refreshToken = UUID() }
                    .onChange(of: userProfile?.displayName) { _ in refreshToken = UUID() }
                    .onChange(of: userProfile?.username) { _ in refreshToken = UUID() }
                    .id(refreshToken)
                    .onChange(of: supabaseService.isAuthenticated) { _ in }
                    
                } else {
                    // Login form
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .keyboardType(.alphabet)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled(true)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .keyboardType(.alphabet)
                            .autocorrectionDisabled(true)
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Button {
                            Task { await signIn() }
                        } label: {
                            if isLoading {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign In").fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        
                        Button {
                            Task { await resetPassword() }
                        } label: {
                            Text("Forgot Password?")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal)
                }
                
                HStack {
                    Text("Don't have an account?").foregroundColor(.secondary)
                    Button {
                        showSignUp = true
                    } label: {
                        Text("Sign Up").fontWeight(.semibold).foregroundColor(.accentColor)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(supabaseService.isAuthenticated ? "Account" : "Login")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSignUp) {
                NavigationStack {
                    SignUpView()
                        .environmentObject(supabaseService)
                }
                .presentationDragIndicator(.visible)
            }
            .alert("Clean Up Orphaned Data", isPresented: $showCleanupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clean Up", role: .destructive) {
                    Task { await cleanupOrphanedData() }
                }
            } message: {
                Text("This will permanently delete orphaned data from Supabase and R2. This action cannot be undone.")
            }
            .alert("Purge Deleted Outfits", isPresented: $showPurgeOutfitsConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Purge", role: .destructive) {
                    purgeOrphanedOutfits()
                }
            } message: {
                Text("This will permanently remove all soft-deleted outfits from local storage. Outfits are already removed from Supabase when soft-deleted, so this only cleans up local tombstone records.")
            }
            .alert("Purge Orphaned Wardrobes", isPresented: $showPurgeOrphanedWardrobesConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Purge", role: .destructive) {
                    purgeOrphanedWardrobes()
                }
            } message: {
                Text("This will permanently delete all local wardrobes that are not linked to your account (userId is nil or belongs to a different user). This cannot be undone.")
            }
    }
    
    // MARK: - Purge soft-deleted outfits from local Core Data
    private func purgeOrphanedOutfits() {
        isPurgingOutfits = true
        purgeOutfitsMessage = nil

        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.predicate = NSPredicate(format: "isSoftDeleted == YES")

        do {
            let softDeleted = try viewContext.fetch(request)
            let count = softDeleted.count
            if softDeleted.isEmpty {
                purgeOutfitsMessage = "✅ No soft-deleted outfits found."
            } else {
                for outfit in softDeleted {
                    viewContext.delete(outfit)
                }
                try viewContext.save()
                purgeOutfitsMessage = "✅ Deleted \(count) soft-deleted outfit\(count == 1 ? "" : "s")."
                print("🧹 Purged \(count) soft-deleted outfit(s)")
            }
        } catch {
            purgeOutfitsMessage = "❌ Failed: \(error.localizedDescription)"
            print("❌ Failed to purge soft-deleted outfits: \(error)")
        }

        isPurgingOutfits = false
    }

    // MARK: - Purge orphaned wardrobes from local Core Data
    private func purgeOrphanedWardrobes() {
        isPurgingOrphanedWardrobes = true
        purgeOrphanedWardrobesMessage = nil

        guard let currentUserId = supabaseService.currentUser?.id.uuidString else {
            purgeOrphanedWardrobesMessage = "❌ Not signed in."
            isPurgingOrphanedWardrobes = false
            return
        }

        let request = NSFetchRequest<Wardrobe>(entityName: "Wardrobe")
        // Target:
        //  • wardrobes with no userId or the wrong userId (truly orphaned)
        //  • wardrobes that are soft-deleted (user's own but marked for removal)
        request.predicate = NSPredicate(
            format: "userId == nil OR userId != %@ OR isSoftDeleted == YES",
            currentUserId
        )

        do {
            let orphaned = try viewContext.fetch(request)
            let count = orphaned.count
            if orphaned.isEmpty {
                purgeOrphanedWardrobesMessage = "✅ No orphaned wardrobes found."
            } else {
                for wardrobe in orphaned {
                    viewContext.delete(wardrobe)
                }
                try viewContext.save()
                purgeOrphanedWardrobesMessage = "✅ Deleted \(count) orphaned wardrobe\(count == 1 ? "" : "s")."
                print("🧹 Purged \(count) orphaned wardrobe(s)")
            }
        } catch {
            purgeOrphanedWardrobesMessage = "❌ Failed: \(error.localizedDescription)"
            print("❌ Failed to purge orphaned wardrobes: \(error)")
        }

        isPurgingOrphanedWardrobes = false
    }
    
    private func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await supabaseService.signIn(email: email, password: password)
            // Success - the session is now set in SupabaseService
            // Username is automatically loaded in signIn() method
            
            // Trigger sync after successful login
            Task {
                do {
                    try await syncService.syncAllItems()
                    print("✅ Sync completed after login")
                } catch {
                    print("⚠️ Sync failed after login: \(error)")
                    print("⚠️ Error type: \(type(of: error))")
                    print("⚠️ Error description: \(error.localizedDescription)")
                    let nsError = error as NSError
                    print("⚠️ Error domain: \(nsError.domain), code: \(nsError.code)")
                    print("⚠️ User info: \(nsError.userInfo)")
                    // Don't show error to user - sync can happen in background
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func resetPassword() async {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email address first"
            return
        }
        
        do {
            try await supabaseService.resetPassword(email: email)
            errorMessage = "Password reset email sent! Check your inbox."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func signOut() async {
        do {
            try await supabaseService.signOut()
            // Clear form fields after sign out
            email = ""
            password = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func loadUsername() async {
        guard supabaseService.isAuthenticated else {
            return
        }
        
        do {
            // Only fetch if not cached (getUsername returns cached value if available)
            _ = try await supabaseService.getUsername()
        } catch {
            print("⚠️ Error loading username: \(error.localizedDescription)")
        }
    }
    
    private func startEditingUsername() {
        editedUsername = currentUsername ?? ""
        errorMessage = nil
        isEditingUsername = true
    }
    
    private func saveUsername() async {
        isSavingUsername = true
        errorMessage = nil
        
        do {
            try await supabaseService.updateUsername(editedUsername)
            // Username is automatically updated in cache and Core Data by updateUsername()
            // Wait a moment for Core Data to save, then refresh
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            viewContext.refreshAllObjects()
            refreshToken = UUID()
            isEditingUsername = false
        } catch {
            errorMessage = error.localizedDescription
            // Keep editing mode on error so user can try again
        }
        
        isSavingUsername = false
    }
    
    private func startEditingDisplayName() {
        editedDisplayName = currentDisplayName ?? ""
        isEditingDisplayName = true
    }
    
    private func saveDisplayName() async {
        isSavingDisplayName = true
        
        do {
            try await supabaseService.updateDisplayName(editedDisplayName)
            // Display name is automatically synced to Core Data by updateDisplayName()
            // Wait a moment for Core Data to save, then refresh
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            viewContext.refreshAllObjects()
            refreshToken = UUID()
            isEditingDisplayName = false
        } catch {
            errorMessage = error.localizedDescription
            // Keep editing mode on error so user can try again
        }
        
        isSavingDisplayName = false
    }
    
    private func cleanupOrphanedData() async {
        isCleaningUp = true
        cleanupMessage = nil
        
        do {
            try await syncService.cleanupOrphanedData()
            cleanupMessage = "✅ Cleanup complete! Orphaned data has been removed."
        } catch {
            cleanupMessage = "❌ Cleanup failed: \(error.localizedDescription)"
            print("❌ Cleanup error: \(error)")
        }
        
        isCleaningUp = false
    }
}
