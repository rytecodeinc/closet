//
//  RegisterView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI
import CoreData

struct RegisterView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @Environment(\.authFlowRouter) private var authFlowRouter
    @Environment(\.dismiss) private var dismiss

    /// 1 = email/password, 2 = display name + username, 3 = category onboarding
    @State private var currentStep: Int = 1

    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var selectedCategoryNames: Set<String> = Set(ReferenceDataBootstrap.masterCategoryNames)

    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            AuthAppIconView()
                            
                            Text("Register")
                                .font(.largeTitle)
                                .fontWeight(.bold)

                            Text(headerSubtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)

                        VStack(spacing: 16) {
                            Group {
                                if appCapabilities.requiresCategoryOnboarding {
                                    switch currentStep {
                                    case 1:
                                        stepOneContent
                                    case 2:
                                        stepTwoContent
                                    case 3:
                                        stepPreferencesContent
                                    default:
                                        EmptyView()
                                    }
                                } else {
                                    testFlightRegistrationContent
                                }

                                if let error = errorMessage {
                                    Text(error)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .disabled(isLoading)

                            stepFooterButton
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)

                        Spacer(minLength: 0)

                        HStack {
                            Text("Already have an account?")
                                .foregroundColor(.secondary)
                            if let authFlowRouter {
                                Button {
                                    authFlowRouter.showSignIn()
                                } label: {
                                    Text("Sign In")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.cayenne)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    dismiss()
                                } label: {
                                    Text("Sign In")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.cayenne)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                        .disabled(isLoading)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)

                #if DEBUG && !TESTFLIGHT
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
      /*  .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)*/
        .onChange(of: currentStep) { _, step in
            if step == 3, appCapabilities.requiresCategoryOnboarding, selectedCategoryNames.isEmpty {
                selectedCategoryNames = Set(ReferenceDataBootstrap.masterCategoryNames)
            }
        }
    }

    private var headerSubtitle: String {
        if currentStep == 3, appCapabilities.requiresCategoryOnboarding {
            return "Choose which categories belong in your closet"
        }
        return "Enter your details to create an account"
    }

    #if DEBUG && !TESTFLIGHT
    private func debugBypassAdvanceRegistration() {
        errorMessage = nil
        if !appCapabilities.requiresCategoryOnboarding {
            if displayName.isEmpty { displayName = "Debug User" }
            if appCapabilities.enablesFriendsAndSharing, username.isEmpty {
                username = "debug_\(UUID().uuidString.prefix(8).lowercased())"
            }
            if email.isEmpty { email = "debug@example.com" }
            if password.isEmpty { password = "debugpass1" }
            if confirmPassword.isEmpty { confirmPassword = password }
            Task { await registerAndMoveToPreferences() }
            return
        }
        switch currentStep {
        case 1:
            if email.isEmpty { email = "debug@example.com" }
            if password.isEmpty { password = "debugpass1" }
            if confirmPassword.isEmpty { confirmPassword = password }
            currentStep = 2
        case 2:
            if displayName.isEmpty { displayName = "Debug User" }
            if appCapabilities.enablesFriendsAndSharing, username.isEmpty {
                username = "debug_\(UUID().uuidString.prefix(8).lowercased())"
            }
            if appCapabilities.requiresCategoryOnboarding {
                selectedCategoryNames = Set(ReferenceDataBootstrap.masterCategoryNames)
                currentStep = 3
            } else {
                Task { await registerAndMoveToPreferences() }
            }
        default:
            if appCapabilities.requiresCategoryOnboarding {
                Task { await completeCategoryOnboarding() }
            }
        }
    }
    #endif

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

    /// TestFlight: single screen — profile fields, then email/password (visible labels).
    private var testFlightRegistrationContent: some View {
        VStack(spacing: 16) {
            registrationLabeledField(title: "Display Name") {
                TextField("", text: $displayName, prompt: Text("Full name"))
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)
                    .textContentType(.name)
            }

            registrationLabeledField(title: "Email Address") {
                TextField("", text: $email, prompt: Text("Enter your email address"))
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            }

            registrationLabeledField(title: "Password") {
                SecureField("", text: $password, prompt: Text("Password must be at least 6 characters"))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
            }

            registrationLabeledField(title: "Confirm Password") {
                SecureField("", text: $confirmPassword, prompt: Text("Re-enter your password"))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
            }
        }
    }

    private func registrationLabeledField<Field: View>(
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

    private var stepTwoContent: some View {
        VStack(spacing: 16) {
            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.words)
                .textContentType(.name)

            if appCapabilities.enablesFriendsAndSharing {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
                    .textContentType(.username)
            }
        }
    }

    private var stepPreferencesContent: some View {
        CategoryOnboardingView(
            selectedCategoryNames: $selectedCategoryNames,
            onError: { errorMessage = $0 }
        )
    }

    private var stepFooterButton: some View {
        AuthPrimaryButton(
            buttonTitle,
            isLoading: isLoading,
            isEnabled: !isButtonDisabled
        ) {
            Task {
                await handlePrimaryAction()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var buttonTitle: String {
        if !appCapabilities.requiresCategoryOnboarding {
            return "Create Account"
        }
        switch currentStep {
        case 1, 2:
            return "Next"
        default:
            return "Create Account"
        }
    }

    private var isButtonDisabled: Bool {
        if isLoading { return true }

        if !appCapabilities.requiresCategoryOnboarding {
            return isTestFlightRegistrationIncomplete
        }

        switch currentStep {
        case 1:
            return email.isEmpty || password.isEmpty || confirmPassword.isEmpty
        case 2:
            let displayNameMissing = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if appCapabilities.enablesFriendsAndSharing {
                return displayNameMissing
                    || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return displayNameMissing
        default:
            return selectedCategoryNames.isEmpty
        }
    }

    private var isTestFlightRegistrationIncomplete: Bool {
        let displayNameMissing = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let usernameMissing = appCapabilities.enablesFriendsAndSharing
            && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return displayNameMissing
            || usernameMissing
            || email.isEmpty
            || password.isEmpty
            || confirmPassword.isEmpty
    }

    private func handlePrimaryAction() async {
        errorMessage = nil

        if !appCapabilities.requiresCategoryOnboarding {
            await registerAndMoveToPreferences()
            return
        }

        switch currentStep {
        case 1:
            guard validateStepOne() else { return }
            currentStep = 2
        case 2:
            await registerAndMoveToPreferences()
        default:
            await completeCategoryOnboarding()
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

    private func validateRegistrationProfileFields() -> Bool {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Display name is required"
            return false
        }

        guard appCapabilities.enablesFriendsAndSharing else { return true }

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

    private func registerAndMoveToPreferences() async {
        guard validateRegistrationProfileFields() else { return }
        if !appCapabilities.requiresCategoryOnboarding {
            guard validateStepOne() else { return }
        }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        if appCapabilities.enablesFriendsAndSharing {
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
        }

        isLoading = true
        errorMessage = nil
        do {
            try await supabaseService.register(email: email, password: password)
            try? await supabaseService.updateDisplayName(trimmedDisplayName)
            if appCapabilities.enablesFriendsAndSharing {
                try? await supabaseService.updateUsername(trimmedUsername)
            }
            if appCapabilities.requiresCategoryOnboarding {
                selectedCategoryNames = Set(ReferenceDataBootstrap.masterCategoryNames)
                currentStep = 3
            } else {
                try finishRegistrationAfterAccountCreation()
                dismiss()
            }
        } catch {
            errorMessage = SupabaseService.registerErrorMessage(for: error)
        }

        isLoading = false
    }

    /// TestFlight: seed full category catalog + universal defaults, then mark onboarding complete.
    private func finishRegistrationAfterAccountCreation() throws {
        guard let userId = authSession.userId else {
            throw CategoryOnboardingError.notSignedIn
        }
        try CategoryOnboardingView.completeOnboardingWithFullCatalog(userId: userId, in: viewContext)
    }

    private func completeCategoryOnboarding() async {
        guard let userId = authSession.userId else {
            errorMessage = CategoryOnboardingError.notSignedIn.localizedDescription
            return
        }
        guard !selectedCategoryNames.isEmpty else {
            errorMessage = CategoryOnboardingError.noCategoriesSelected.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            try CategoryOnboardingView.completeOnboarding(
                selectedNames: selectedCategoryNames,
                userId: userId,
                in: viewContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

}
