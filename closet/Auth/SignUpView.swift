//
//  SignUpView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) var dismiss
    
    // Step state
    @State private var currentStep: Int = 1
    
    // Step 2 fields
    @State private var displayName = ""
    @State private var username = ""
    
    // Step 1 fields
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.accentColor)
                        
                        Text("Create Account")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Start syncing your closet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Step content
                    VStack(spacing: 16) {
                        switch currentStep {
                        case 1:
                            stepOneContent
                        case 2:
                            stepTwoContent
                        default:
                            stepThreeContent
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        stepFooterButton
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Step Views
    
    private var stepOneContent: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
            
            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
        }
    }
    
    private var stepTwoContent: some View {
        VStack(spacing: 16) {
            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.words)
                .textContentType(.name)
            
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled(true)
                .textContentType(.username)
        }
    }
    
    private var stepThreeContent: some View {
        VStack(spacing: 16) {
            Text("Set your preferences")
                .font(.headline)
            
            Text("This is where you'll choose your default categories and other app preferences.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Footer Button
    
    private var stepFooterButton: some View {
        Button {
            Task {
                await handlePrimaryAction()
            }
        } label: {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Text(buttonTitle)
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .disabled(isButtonDisabled)
    }
    
    private var buttonTitle: String {
        switch currentStep {
        case 1: return "Next"
        case 2: return "Next"
        default: return "Create account"
        }
    }
    
    private var isButtonDisabled: Bool {
        if isLoading { return true }
        
        switch currentStep {
        case 1:
            return email.isEmpty || password.isEmpty || confirmPassword.isEmpty
        case 2:
            return displayName.trimmingCharacters(in: .whitespaces).isEmpty ||
                   username.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return false
        }
    }
    
    // MARK: - Actions
    
    private func handlePrimaryAction() async {
        errorMessage = nil
        
        switch currentStep {
        case 1:
            guard validateStepOne() else { return }
            currentStep = 2
        case 2:
            await signUpAndMoveToPreferences()
        default:
            // Preferences step completion
            dismiss()
        }
    }
    
    private func validateStepOne() -> Bool {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return false
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return false
        }
        
        return true
    }
    
    private func signUpAndMoveToPreferences() async {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Display name is required"
            return
        }
        
        guard trimmedUsername.count >= 3, trimmedUsername.count <= 30 else {
            errorMessage = "Username must be 3–30 characters"
            return
        }
        
        let usernameRegex = "^[a-zA-Z0-9_]+$"
        guard trimmedUsername.range(of: usernameRegex, options: .regularExpression) != nil else {
            errorMessage = "Username can only contain letters, numbers, and underscores"
            return
        }
        
        do {
            let available = try await supabaseService.isUsernameAvailable(trimmedUsername)
            guard available else {
                errorMessage = "Username is already taken"
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        
        isLoading = true
        errorMessage = nil
        do {
            try await supabaseService.signUp(email: email, password: password)
            // Update profile with display name and username (user is now signed in)
            try? await supabaseService.updateDisplayName(trimmedDisplayName)
            try? await supabaseService.updateUsername(trimmedUsername)
            currentStep = 3
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

