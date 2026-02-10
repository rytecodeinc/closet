//
//  LoginView.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSignUp = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.accentColor)
                    
                    Text("Welcome Back")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Sign in to sync your closet")
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
                        .textContentType(.password)
                    
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
                
                Spacer()
                
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
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSignUp) {
                SignUpView()
                    .environmentObject(supabaseService)
            }
        }
    }
    
    private func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await supabaseService.signIn(email: email, password: password)
            // Success - the session is now set in SupabaseService
            // The view will automatically update via @Published properties
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
}

