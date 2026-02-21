//
//  LoginView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI

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
        NavigationStack {
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
                    
                    // Show logged in status if authenticated
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
                                        Task {
                                            await saveDisplayName()
                                        }
                                    } else {
                                        startEditingDisplayName()
                                    }
                                } label: {
                                    if isSavingDisplayName {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.8)
                                    } else if isEditingDisplayName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.accentColor)
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
                                        Task {
                                            await saveUsername()
                                        }
                                    } else {
                                        startEditingUsername()
                                    }
                                } label: {
                                    if isSavingUsername {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.8)
                                    } else if isEditingUsername {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isSavingUsername)
                            }
                            .padding(.horizontal)
                            
                            Button {
                                Task {
                                    await signOut()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Sign Out")
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                            
                            // Cleanup Orphaned Data Button
                            Button {
                                showCleanupConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.circle")
                                    Text("Clean Up Orphaned Data")
                                        .fontWeight(.semibold)
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
                        }
                        .padding(.vertical, 20)
                        .task {
                            // Check Core Data first - if data exists, use it
                            // Only fetch from Supabase if data is missing
                            if supabaseService.isAuthenticated {
                                let needsUsername = currentUsername == nil
                                let needsDisplayName = currentDisplayName == nil
                                
                                if needsUsername || needsDisplayName {
                                    do {
                                        // getUsername() loads both username and displayName and syncs to Core Data
                                        _ = try await supabaseService.getUsername()
                                        // Refresh after loading
                                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                        viewContext.refreshAllObjects()
                                        refreshToken = UUID()
                                    } catch {
                                        // If Supabase fetch fails, data might already be in Core Data
                                        // Don't show error - just use what's in Core Data
                                        print("⚠️ Error loading profile from Supabase (may already be in Core Data): \(error.localizedDescription)")
                                        viewContext.refreshAllObjects()
                                        refreshToken = UUID()
                                    }
                                }
                            }
                        }
                        .onChange(of: userProfiles.count) { _ in
                            // Refresh when user profile changes
                            refreshToken = UUID()
                        }
                        .onChange(of: userProfile?.displayName) { _ in
                            // Refresh when displayName changes
                            refreshToken = UUID()
                        }
                        .onChange(of: userProfile?.username) { _ in
                            // Refresh when username changes
                            refreshToken = UUID()
                        }
                        .id(refreshToken) // Force refresh when token changes
                        .onChange(of: supabaseService.isAuthenticated) { isAuthenticated in
                            // Username is automatically cleared in SupabaseService.signOut()
                            // No local state to clear
                        }
                    } else {
                        // Form
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
                            Task {
                                await signIn()
                            }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        
                        Button {
                            Task {
                                await resetPassword()
                            }
                        } label: {
                            Text("Forgot Password?")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Sign Up Link
                    HStack {
                        Text("Don't have an account?")
                            .foregroundColor(.secondary)
                        Button {
                            showSignUp = true
                        } label: {
                            Text("Sign Up")
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.bottom, 20)
                
                
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSignUp) {
                SignUpView()
                    .environmentObject(supabaseService)
            }
            .alert("Clean Up Orphaned Data", isPresented: $showCleanupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clean Up", role: .destructive) {
                    Task {
                        await cleanupOrphanedData()
                    }
                }
            } message: {
                Text("This will permanently delete orphaned data from Supabase and R2. Orphaned data includes items, photos, and relationships that exist in Supabase but not in your local Core Data. This action cannot be undone.")
            }
        }
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
        isEditingUsername = true
    }
    
    private func saveUsername() async {
        isSavingUsername = true
        
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
