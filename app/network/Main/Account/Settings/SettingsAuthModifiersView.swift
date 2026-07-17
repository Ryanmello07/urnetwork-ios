//
//  SettingsAuthModifiersView.swift
//  URnetwork
//
//  Created by Hermes on 2026/07/17.
//

import SwiftUI
import URnetworkSdk

/**
 Holds the seedphrase + sign-in method sheet/dialog/onOpenURL modifiers.
 
 Split from SettingsCoreModifiersView to keep each modifier chain short
 enough for Swift's type-checker.
 */
struct SettingsAuthModifiersView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    @EnvironmentObject var connectWalletProviderViewModel: ConnectWalletProviderViewModel

    @ObservedObject var viewModel: SettingsView.ViewModel
    let api: UrApiServiceProtocol
    let handleWalletDeepLink: (URL) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
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
