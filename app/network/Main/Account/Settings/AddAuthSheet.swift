//
//  AddAuthSheet.swift
//  URnetwork
//

import SwiftUI
import URnetworkSdk

#if os(iOS)
import AuthenticationServices
#endif

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
                        Text("Apple").tag("apple")
                        Text("Google").tag("google")
                        Text("Wallet").tag("wallet")
                        Text("Email").tag("email")
                        Text("Seedphrase").tag("seedphrase")
                    }
                    .pickerStyle(.menu)
                    
                    if selectedMethod == "apple" {
                        appleSignInView
                    } else if selectedMethod == "google" {
                        googleSignInView
                    } else if selectedMethod == "wallet" {
                        walletSignInView
                    } else if selectedMethod == "email" {
                        emailFields
                    } else if selectedMethod == "seedphrase" {
                        Text("A new seedphrase will be generated and linked to your account.")
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(themeManager.currentTheme.textMutedColor)
                    }
                    
                    if let error = addError {
                        Text(error)
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(.red)
                    }
                    
                    if selectedMethod == "email" || selectedMethod == "seedphrase" {
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
    
    // MARK: - Apple Sign-In
    
    private var appleSignInView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with your Apple ID to add it as a sign-in method.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
            
            #if os(iOS)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                Task {
                    await handleAppleResult(result)
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .cornerRadius(8)
            #else
            Text("Apple Sign-In is available on iOS.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
            #endif
        }
    }
    
    // MARK: - Google Sign-In
    
    private var googleSignInView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with Google to add it as a sign-in method.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
            
            UrGoogleSignInButton(
                action: {
                    await handleGoogleSignIn()
                }
            )
        }
    }
    
    // MARK: - Wallet Sign-In
    
    private var walletSignInView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect a Solana wallet (Phantom or Solflare) to add it as a sign-in method.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
            
            Button(action: {
                Task {
                    await handleWalletAuth()
                }
            }) {
                HStack {
                    Image(systemName: "wallet.pass")
                    Text("Connect Solana Wallet")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(themeManager.currentTheme.tintedBackgroundBase)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
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
    
    // MARK: - Actions
    
    private func handleAppleResult(_ result: Result<ASAuthorization, any Error>) async {
        isAdding = true
        addError = nil
        
        do {
            let authResult = try result.get()
            guard let credential = authResult.credential as? ASAuthorizationAppleIDCredential,
                  let idToken = credential.identityToken,
                  let idTokenString = String(data: idToken, encoding: .utf8) else {
                addError = "Could not read Apple ID token"
                isAdding = false
                return
            }
            
            let args = SdkAddAuthArgs()
            args.authJwt = idTokenString
            args.authJwtType = "apple"
            
            let _ = try await api.addAuth(args)
            isAdding = false
            snackbarManager.showSnackbar(message: String(localized: "Apple sign-in method added"))
            dismiss()
        } catch(let error) {
            isAdding = false
            addError = error.localizedDescription
        }
    }
    
    private func handleGoogleSignIn() async {
        isAdding = true
        addError = nil
        
        do {
            #if os(iOS)
            guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.keyWindow?
                .rootViewController else {
                addError = "Could not get root view controller"
                isAdding = false
                return
            }
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            #elseif os(macOS)
            guard let presentingWindow = NSApplication.shared.windows.first else {
                addError = "Could not get presenting window"
                isAdding = false
                return
            }
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow)
            #endif
            
            guard let idTokenString = signInResult.user.idToken?.tokenString else {
                addError = "Could not get Google ID token"
                isAdding = false
                return
            }
            
            let args = SdkAddAuthArgs()
            args.authJwt = idTokenString
            args.authJwtType = "google"
            
            let _ = try await api.addAuth(args)
            isAdding = false
            snackbarManager.showSnackbar(message: String(localized: "Google sign-in method added"))
            dismiss()
        } catch(let error) {
            isAdding = false
            addError = error.localizedDescription
        }
    }
    
    private func handleWalletAuth() async {
        isAdding = true
        addError = nil
        
        // Use the existing wallet provider to get a challenge and prompt signing
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.keyWindow?
            .rootViewController else {
            addError = "Could not get root view controller"
            isAdding = false
            return
        }
        
        // For wallet auth linking, the user needs to sign a challenge message
        // The existing flow in LoginInitialView uses deep links with phantom/solflare
        // For now, guide users to use the Settings → Wallet connection flow
        addError = "Please connect your wallet from the main authentication flow, then add it as a sign-in method here."
        isAdding = false
    }
    
    private func addAuth() async {
        isAdding = true
        addError = nil
        
        do {
            let args = SdkAddAuthArgs()
            
            switch selectedMethod {
            case "email":
                args.userAuth = email
                args.password = password
            case "seedphrase":
                // Seedphrase is generated server-side when no auth fields are set
                // Just call addAuth with empty args to trigger seedphrase linking
                break
            default:
                break
            }
            
            let _ = try await api.addAuth(args)
            isAdding = false
            snackbarManager.showSnackbar(message: String(localized: "Sign-in method added successfully"))
            dismiss()
        } catch(let error) {
            isAdding = false
            addError = error.localizedDescription
        }
    }
}
