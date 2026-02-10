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
                    
                    // Form
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
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Button {
                            Task {
                                await signUp()
                            }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign Up")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(isLoading || email.isEmpty || password.isEmpty || password != confirmPassword)
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
    
    private func signUp() async {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await supabaseService.signUp(email: email, password: password)
            // Success - dismiss the sheet
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

