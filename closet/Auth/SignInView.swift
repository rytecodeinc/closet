//
//  SignInView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI
import CoreData

struct SignInView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var authSession: AuthSession
    @EnvironmentObject var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.authFlowRouter) private var authFlowRouter
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
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
        guard let userId = authSession.userId?.uuidString else {
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    AuthAppIconView()
                    
                    Text(authSession.isAuthenticated ? "Hello, \(authSession.userEmail ?? "User")!" : "Sign In")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Sign in to your closet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom)
                
                if authSession.isAuthenticated {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.green)
                        
                        Text("Successfully Signed In")
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
                        if authSession.isAuthenticated {
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
                    .onChange(of: authSession.isAuthenticated) { _ in }
                    
                } else {
                    // Sign-in form
                    VStack(spacing: 16) {
                        Group {
                            signInLabeledField(title: "Email Address") {
                                TextField("", text: $email, prompt: Text("Enter your email address"))
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .autocorrectionDisabled(true)
                            }

                            signInLabeledField(title: "Password") {
                                SecureField("", text: $password, prompt: Text("Enter your password"))
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.password)
                                    .autocorrectionDisabled(true)
                            }

                            NavigationLink {
                                ForgotPasswordView(initialEmail: email)
                            } label: {
                                Text("Forgot Password?")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .disabled(isLoading)

                        AuthPrimaryButton(
                            "Sign In",
                            isLoading: isLoading,
                            isEnabled: !email.isEmpty && !password.isEmpty
                        ) {
                            Task { await signIn() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 0)
                }
                
                HStack {
                    Text("Don't have an account?").foregroundColor(.secondary)
                    if let authFlowRouter {
                        Button {
                            authFlowRouter.showRegisterFromSignIn()
                        } label: {
                            Text("Register").fontWeight(.semibold).foregroundColor(.teal)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            RegisterView()
                        } label: {
                            Text("Register").fontWeight(.semibold).foregroundColor(.teal)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .disabled(isLoading)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
           /* .navigationTitle(authSession.isAuthenticated ? "Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)*/
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
    
    private func signInLabeledField<Field: View>(
        title: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            field()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

        guard let currentUserId = authSession.userId?.uuidString else {
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
            
            // Trigger sync after successful sign-in
            Task {
                do {
                    try await syncService.syncAllItems()
                    print("✅ Sync completed after sign-in")
                } catch {
                    print("⚠️ Sync failed after sign-in: \(error)")
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
        guard authSession.isAuthenticated else {
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
