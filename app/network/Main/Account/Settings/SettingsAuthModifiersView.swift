//
//  SettingsAuthModifiersView.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/10.
//

import SwiftUI
import URnetworkSdk

/**
 Separate view holding the seedphrase and sign-in-method sheet/dialog modifiers.

 This exists solely to keep the modifier chains short enough for Swift's
 type-checker: SettingsView.body stays at 8 modifiers (its original length),
 and the 4 auth-specific modifiers live here on a trivial Color.clear base,
 each in its own independently-type-checked struct.
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
