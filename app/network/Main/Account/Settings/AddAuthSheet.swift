//
//  AddAuthSheet.swift
//  URnetwork
//

import SwiftUI
import URnetworkSdk

struct AddAuthSheet: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    @EnvironmentObject var connectWalletProviderViewModel: ConnectWalletProviderViewModel
    
    let api: UrApiServiceProtocol
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isAdding: Bool = false
    @State private var selectedMethod: String = "email"
    @State private var addError: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    Text("Add a sign-in method")
                        .font(themeManager.currentTheme.titleFont)
                        .foregroundColor(themeManager.currentTheme.textColor)
                    
                    Text("Link another way to sign in to your account.")
                        .font(themeManager.currentTheme.secondaryBodyFont)
                        .foregroundColor(themeManager.currentTheme.textMutedColor)
                    
                    Spacer().frame(height: 16)
                    
                    Picker("Method", selection: $selectedMethod) {
                        Text("Email").tag("email")
                        Text("Apple").tag("apple")
                        Text("Google").tag("google")
                        Text("Wallet").tag("wallet")
                        Text("Seedphrase").tag("seedphrase")
                    }
                    .pickerStyle(.menu)
                    
                    if selectedMethod == "email" {
                        emailFields
                    } else if selectedMethod == "apple" {
                        appleSignInView
                    } else if selectedMethod == "google" {
                        googleSignInView
                    } else if selectedMethod == "wallet" {
                        walletSignInView
                    } else if selectedMethod == "seedphrase" {
                        seedphraseView
                    }
                    
                    if let error = addError {
                        Text(error)
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(.red)
                    }
                    
                    if selectedMethod != "apple" && selectedMethod != "google" && selectedMethod != "wallet" {
                        Spacer().frame(height: 16)
                        
                        UrButton(
                            text: "Add Sign-In Method",
                            action: {
                                Task {
                                    await addAuth()
                                }
                            },
                            enabled: !isAdding && formValid,
                            isProcessing: isAdding
                        )
                    }
                }
                .padding()
            }
            .background(themeManager.currentTheme.backgroundColor.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private var formValid: Bool {
        switch selectedMethod {
        case "email":
            return !email.isEmpty && password.count >= 12
        default:
            return true
        }
    }
    
    // MARK: - Email Fields
    
    private var emailFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            UrTextField(
                text: $email,
                label: "Email",
                placeholder: "your@email.com",
                disableCapitalization: true
            )
            
            UrTextField(
                text: $password,
                label: "Password",
                placeholder: "Enter a password",
                isSecure: true
            )
            
            Text("Password must be at least 12 characters")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
        }
    }
    
    // MARK: - Apple Sign-In
    
    private var appleSignInView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with your Apple ID to add it as a sign-in method.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
            
            Text("Apple Sign-In is available from the authentication flow.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
        }
    }
    
    // MARK: - Google Sign-In
    
    private var googleSignInView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with your Google account to add it as a sign-in method.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
            
            Text("Google Sign-In is available from the authentication flow.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
        }
    }
    
    // MARK: - Wallet Sign-In
    
    private var walletSignInView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect a Solana wallet (Phantom or Solflare) to add it as a sign-in method.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
        }
    }
    
    // MARK: - Seedphrase
    
    private var seedphraseView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A new seedphrase will be generated and linked to your account.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
        }
    }
    
    // MARK: - Actions
    
    private func addAuth() async {
        isAdding = true
        addError = nil
        
        do {
            switch selectedMethod {
            case "email":
                let args = SdkAddAuthArgs()
                args.userAuth = email
                args.password = password
                let _ = try await api.addAuth(args)
                
            case "seedphrase":
                // Generate a new seedphrase and link it to the account
                let _ = try await api.generateSeedphrase()
                
            default:
                // Apple/Google/Wallet are handled in their own flows
                break
            }
            
            isAdding = false
            snackbarManager.showSnackbar(message: String(localized: "Sign-in method added successfully"))
            dismiss()
        } catch(let error) {
            isAdding = false
            addError = error.localizedDescription
        }
    }
}
