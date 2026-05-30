//
//  ForgotPasswordView.swift
//  closet
//
//  Request a password reset email (styled like SignInView).
//

import SwiftUI
import CoreData

struct ForgotPasswordView: View {
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.authFlowRouter) private var authFlowRouter
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isLoading = false

    init(initialEmail: String = "") {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        AuthAppIconView()

                        Text("Reset Password")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("We'll email you a link to reset your password")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    .padding(.horizontal)
                    .padding(.bottom)

                    VStack(spacing: 16) {
                        authLabeledField(title: "Email Address") {
                            TextField("", text: $email, prompt: Text("Enter your email address"))
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled(true)
                        }

                        if let successMessage {
                            Text(successMessage)
                                .foregroundColor(.green)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await sendResetEmail() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Send Reset Link")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.white)
                                        .background(Color.cayenne.gradient)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom)


                    Button {
                        dismiss()
                    } label: {
                        Text("Back to Sign In")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
                    Spacer(minLength: 0)
                    
                    HStack {
                        Text("Don't have an account?")
                            .foregroundColor(.secondary)
                        if let authFlowRouter {
                            Button {
                                authFlowRouter.showRegisterFromSignIn()
                            } label: {
                                Text("Register")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.cayenne)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                RegisterView()
                            } label: {
                                Text("Register")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func authLabeledField<Field: View>(
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

    private func sendResetEmail() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your email address"
            successMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            try await supabaseService.resetPassword(email: trimmed)
            successMessage = "Password reset email sent! Check your inbox."
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
