//
//  SettingsAuthModifiersView.swift
//  URnetwork
//
//  Created by Hermes on 2026/07/17.
//

import SwiftUI
import URnetworkSdk

/**
 Aggregates all sheet/dialog/onOpenURL modifiers for SettingsView.
 
 This separate struct keeps each modifier chain short enough for Swift's
 type-checker. SettingsView.body itself holds only a trivial ZStack with
 two subviews (the form + this), while all 10+ modifiers live here on a
 single Color.clear base that is independently type-checked.
 */
struct SettingsAuthModifiersView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    @EnvironmentObject var connectWalletProviderViewModel: ConnectWalletProviderViewModel

    @ObservedObject var viewModel: SettingsView.ViewModel
    @ObservedObject var accountPreferencesViewModel: AccountPreferencesViewModel
    let api: UrApiServiceProtocol
    let clientId: SdkId?
    let handleWalletDeepLink: (URL) -> Void

    let onSaveDeviceName: () async -> Void
    let onHandleDeleteResult: (Result<Void, Error>) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                await viewModel.fetchDeviceInfo(clientId)
            }
            .alert("Device name", isPresented: $viewModel.isPresentedRenameDevice) {
                TextField("Device name", text: $viewModel.editingDeviceName)
                Button("Save") {
                    Task {
                        await onSaveDeviceName()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: accountPreferencesViewModel.saveErrorMessage) { newValue in
                if let newValue {
                    snackbarManager.showSnackbar(message: newValue)
                    accountPreferencesViewModel.clearSaveErrorMessage()
                }
            }
            .confirmationDialog(
                "Are you sure you want to delete your account?",
                isPresented: $viewModel.isPresentedDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task {
                        let result = await viewModel.deleteAccount()
                        onHandleDeleteResult(result)
                    }
                }
            }
            .sheet(isPresented: $viewModel.presentSigninWithSolanaSheet) {
                SolanaSignMessageSheet(
                    isSigningMessage: viewModel.isSigningMessage,
                    setIsSigningMessage: viewModel.setIsSigningMessage,
                    signButtonText: "Confirm Seeker Token",
                    signButtonLabelText: "Claim multiplier",
                    message: connectWalletProviderViewModel.claimSeekerTokenMessage,
                    dismiss: {
                        viewModel.presentSigninWithSolanaSheet = false
                    }
                )
                .environmentObject(themeManager)
                .environmentObject(connectWalletProviderViewModel)
                .presentationDetents([.height(148)])
            }
            .sheet(isPresented: $viewModel.presentUpdateReferralNetworkSheet) {
                UpdateReferralNetworkSheet(
                    api: api,
                    onSuccess: {
                        Task {
                            await viewModel.fetchReferralNetwork()
                        }
                        viewModel.presentUpdateReferralNetworkSheet = false
                    },
                    dismiss: {
                        viewModel.presentUpdateReferralNetworkSheet = false
                    },
                    referralNetwork: viewModel.referralNetwork
                )
                .environmentObject(themeManager)
                .presentationDetents([.height(268)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.presentSeedphraseSheet) {
                SeedphraseDisplayView(
                    seedphrase: viewModel.generatedSeedphrase,
                    onConfirmed: { _ in
                        viewModel.dismissSeedphraseSheet()
                    }
                )
                .environmentObject(themeManager)
            }
            .confirmationDialog(
                "Generate a recovery seedphrase?",
                isPresented: $viewModel.presentSeedphraseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Generate") {
                    Task {
                        await viewModel.executePendingSeedphraseAction()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A seedphrase lets you recover your account if you lose access. Store it safely.")
            }
            .confirmationDialog(
                "Remove this sign-in method?",
                isPresented: $viewModel.presentRemoveAuthConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        await viewModel.executeRemoveAuth()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let authType = viewModel.authTypeToRemove {
                    Text("Are you sure you want to remove \(authType) as a sign-in method?")
                }
            }
            .sheet(isPresented: $viewModel.presentAddAuthSheet) {
                AddAuthSheet(api: api)
                    .environmentObject(themeManager)
                    .environmentObject(snackbarManager)
                    .environmentObject(connectWalletProviderViewModel)
            }
            .onOpenURL { url in
                handleWalletDeepLink(url)
            }
    }
}
