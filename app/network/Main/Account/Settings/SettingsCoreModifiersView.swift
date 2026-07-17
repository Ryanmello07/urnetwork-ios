//
//  SettingsCoreModifiersView.swift
//  URnetwork
//
//  Created by Hermes on 2026/07/17.
//

import SwiftUI
import URnetworkSdk

/**
 Holds the pre-existing SettingsView modifiers (task, alert, onChange,
 delete confirmation dialog, Solana sign-in sheet, referral update sheet).
 
 Split from SettingsAuthModifiersView to keep each chain short enough
 for Swift's type-checker.
 */
struct SettingsCoreModifiersView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    @EnvironmentObject var connectWalletProviderViewModel: ConnectWalletProviderViewModel

    @ObservedObject var viewModel: SettingsView.ViewModel
    @ObservedObject var accountPreferencesViewModel: AccountPreferencesViewModel
    let api: UrApiServiceProtocol
    let clientId: SdkId?
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
    }
}
