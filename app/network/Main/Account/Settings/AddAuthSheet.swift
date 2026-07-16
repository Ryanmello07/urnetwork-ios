//
//  AddAuthSheet.swift
//  URnetwork
//

import SwiftUI
import URnetworkSdk

struct AddAuthSheet: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    
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
                        Text("Seedphrase").tag("seedphrase")
                    }
                    .pickerStyle(.segmented)
                    
                    if selectedMethod == "email" {
                        UrTextField(
                            text: $email,
                            label: "Email",
                            placeholder: "your@email.com",
                            keyboardType: .emailAddress,
                            autocapitalization: .never
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
                    } else {
                        Text("A new seedphrase will be generated for this account.")
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(themeManager.currentTheme.textMutedColor)
                    }
                    
                    if let error = addError {
                        Text(error)
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(.urRed)
                    }
                    
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
        if selectedMethod == "email" {
            return !email.isEmpty && password.count >= 12
        }
        return true
    }
    
    private func addAuth() async {
        isAdding = true
        addError = nil
        
        do {
            let args = SdkAddAuthArgs()
            
            if selectedMethod == "email" {
                args.userAuth = email
                args.password = password
            }
            // seedphrase is generated server-side, no args needed
            
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

//#Preview {
//    AddAuthSheet(api: MockUrApiService())
//        .environmentObject(ThemeManager.shared)
//}
