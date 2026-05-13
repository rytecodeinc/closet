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
    
    /// 1 = email/password, 2 = display name + username, 3 = preferences placeholder
    @State private var currentStep: Int = 1

    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                            stepPreferencesContent
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
            .navigationTitle("Register")
            .navigationBarTitleDisplayMode(.inline)

            #if DEBUG
            Button {
                debugBypassAdvanceRegistration()
            } label: {
                Text("Next")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(16)
            #endif
        }
    }

    #if DEBUG
    /// Advances registration steps without validating; pre-fills fields so the main flow can still be exercised.
    private func debugBypassAdvanceRegistration() {
        errorMessage = nil
        switch currentStep {
        case 1:
            if email.isEmpty { email = "debug@example.com" }
            if password.isEmpty { password = "debugpass1" }
            if confirmPassword.isEmpty { confirmPassword = password }
            currentStep = 2
        case 2:
            if displayName.isEmpty { displayName = "Debug User" }
            if username.isEmpty {
                username = "debug_\(UUID().uuidString.prefix(8).lowercased())"
            }
            currentStep = 3
        default:
            dismiss()
        }
    }
    #endif
    
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

    private var stepPreferencesContent: some View {
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
        case 1, 2: return "Next"
        default: return "Create account"
        }
    }

    private var isButtonDisabled: Bool {
        if isLoading { return true }

        switch currentStep {
        case 1:
            return email.isEmpty || password.isEmpty || confirmPassword.isEmpty
        case 2:
            return displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            dismiss()
        }
    }

    /// Email + password rules only.
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

    /// Display name + username rules (before Supabase sign-up).
    private func validateStepTwo() -> Bool {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Display name is required"
            return false
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.count >= 3, trimmedUsername.count <= 30 else {
            errorMessage = "Username must be 3–30 characters"
            return false
        }

        let usernameRegex = "^[a-zA-Z0-9_]+$"
        guard trimmedUsername.range(of: usernameRegex, options: .regularExpression) != nil else {
            errorMessage = "Username can only contain letters, numbers, and underscores"
            return false
        }

        return true
    }

    private func signUpAndMoveToPreferences() async {
        guard validateStepTwo() else { return }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

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
            try? await supabaseService.updateDisplayName(trimmedDisplayName)
            try? await supabaseService.updateUsername(trimmedUsername)
            currentStep = 3
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

