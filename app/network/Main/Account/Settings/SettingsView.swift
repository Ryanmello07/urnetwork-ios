//
//  SettingsView.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/10.
//

import SwiftUI
import URnetworkSdk
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    
    @StateObject private var viewModel: ViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var connectWalletProviderViewModel: ConnectWalletProviderViewModel
    
    var clientId: SdkId?
    @ObservedObject var accountPreferencesViewModel: AccountPreferencesViewModel
    @ObservedObject var referralLinkViewModel: ReferralLinkViewModel
    @ObservedObject var accountWalletsViewModel: AccountWalletsViewModel
    
    let api: UrApiServiceProtocol
    let navigate: (AccountNavigationPath) -> Void
    let providerCountries: [SdkConnectLocation]
    let networkUserViewModel: NetworkUserViewModel?
    
    init(
        api: UrApiServiceProtocol,
        clientId: SdkId?,
        accountPreferencesViewModel: AccountPreferencesViewModel,
        referralLinkViewModel: ReferralLinkViewModel,
        accountWalletsViewModel: AccountWalletsViewModel,
        navigate: @escaping (AccountNavigationPath) -> Void,
        providerCountries: [SdkConnectLocation],
        networkUserViewModel: NetworkUserViewModel? = nil
    ) {
        _viewModel = StateObject(wrappedValue: ViewModel(api: api))
        self.clientId = clientId
        self.accountPreferencesViewModel = accountPreferencesViewModel
        self.referralLinkViewModel = referralLinkViewModel
        self.accountWalletsViewModel = accountWalletsViewModel
        self.navigate = navigate
        self.providerCountries = providerCountries
        self.api = api
        self.networkUserViewModel = networkUserViewModel
    }
    
    var body: some View {

        #if os(iOS)
            SettingsForm_iOS(
                urApiService: api,
                clientId: clientId,
                referralCode: referralLinkViewModel.referralCode,
                totalReferrals: referralLinkViewModel.totalReferrals,
                referralNetworkName: viewModel.referralNetwork?.name,
                version: viewModel.version,
                isUpdatingAccountPreferences: accountPreferencesViewModel.isUpdatingAccountPreferences,
                isSeekerOrSagaHolder: accountWalletsViewModel.isSeekerOrSagaHolder,
                copyToPasteboard: copyToPasteboard,
                presentUpdateReferralNetworkSheet: {
                    viewModel.presentUpdateReferralNetworkSheet = true
                },
                presentSigninWithSolanaSheet: {
                    viewModel.presentSigninWithSolanaSheet = true
                },
                presentDeleteAccountConfirmation: {
                    viewModel.isPresentedDeleteAccountConfirmation = true
                },
                navigate: navigate,
                provideEnabled: deviceManager.provideEnabled,
                providePaused: deviceManager.providePaused,
                deviceName: viewModel.deviceName,
                deviceSpec: viewModel.deviceSpec,
                presentRenameDevice: viewModel.presentRenameDevice,
                canReceiveNotifications: $viewModel.canReceiveNotifications,
                canReceiveProductUpdates: $accountPreferencesViewModel.canReceiveProductUpdates,
                networkUserViewModel: networkUserViewModel,
                viewModel: viewModel,
            )
            .background(themeManager.currentTheme.backgroundColor)
            .task {
                await viewModel.fetchDeviceInfo(clientId)
            }
            .alert("Device name", isPresented: $viewModel.isPresentedRenameDevice) {
                TextField("Device name", text: $viewModel.editingDeviceName)
                Button("Save") {
                    Task {
                        await saveDeviceName()
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
                        self.handleResult(result)
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
            .onOpenURL { url in
                connectWalletProviderViewModel
                    .handleDeepLink(
                        url,
                        onSignature: { signature in
                            
                            guard let pk = connectWalletProviderViewModel.connectedPublicKey else {
                                viewModel.setIsSigningMessage(false)
                                snackbarManager.showSnackbar(message: String(localized: "Couldn't parse public key, please try again later."))
                                return
                            }
                            
                            Task {
                                await handleSolanaWalletSignature(
                                    message: connectWalletProviderViewModel.claimSeekerTokenMessage,
                                    signature: signature,
                                    publicKey: pk
                                )
                            }
                            
                        },
                        onError: { _ in
                            viewModel.setIsSigningMessage(false)
                            snackbarManager.showSnackbar(message: String(localized: "Sorry, there was an error claiming multiplier."))
                        }
                    )
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

        #elseif os(macOS)
            SettingsForm_macOS(
                urApiService: api,
                clientId: clientId,
                referralCode: referralLinkViewModel.referralCode,
                totalReferrals: referralLinkViewModel.totalReferrals,
                referralNetworkName: viewModel.referralNetwork?.name,
                version: viewModel.version,
                isUpdatingAccountPreferences: accountPreferencesViewModel.isUpdatingAccountPreferences,
                isSeekerOrSagaHolder: accountWalletsViewModel.isSeekerOrSagaHolder,
                copyToPasteboard: copyToPasteboard,
                presentUpdateReferralNetworkSheet: {
                    viewModel.presentUpdateReferralNetworkSheet = true
                },
                presentSigninWithSolanaSheet: {
                    viewModel.presentSigninWithSolanaSheet = true
                },
                presentDeleteAccountConfirmation: {
                    viewModel.isPresentedDeleteAccountConfirmation = true
                },
                navigate: navigate,
                provideEnabled: deviceManager.provideEnabled,
                providePaused: deviceManager.providePaused,
                deviceName: viewModel.deviceName,
                deviceSpec: viewModel.deviceSpec,
                presentRenameDevice: viewModel.presentRenameDevice,
                canReceiveNotifications: $viewModel.canReceiveNotifications,
                canReceiveProductUpdates: $accountPreferencesViewModel.canReceiveProductUpdates,
                launchAtStartupEnabled: $viewModel.launchAtStartupEnabled,
                networkUserViewModel: networkUserViewModel,
                viewModel: viewModel
            )
            .task {
                await viewModel.fetchDeviceInfo(clientId)
            }
            .alert("Device name", isPresented: $viewModel.isPresentedRenameDevice) {
                TextField("Device name", text: $viewModel.editingDeviceName)
                Button("Save") {
                    Task {
                        await saveDeviceName()
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
                        self.handleResult(result)
                    }
                    
                }
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
        
        #endif
        
    }
    
    private func handleSolanaWalletSignature(message: String, signature: String, publicKey: String) async {
        defer {
            viewModel.setIsSigningMessage(false)
        }
        
        let result = await accountWalletsViewModel.verifySeekerOrSagaOwnership(
            publicKey: publicKey,
            message: message,
            signature: signature
        )
        
        switch result {
        case .success(true):
            snackbarManager.showSnackbar(message: String(localized: "Successfully claimed multiplier!"))
            viewModel.presentSigninWithSolanaSheet = false
        case .success(false):
            snackbarManager.showSnackbar(message: String(localized: "Sorry, there was an error claiming multiplier."))
        case .failure(let error):
            snackbarManager.showSnackbar(message: String(localized: "Sorry, there was an error claiming multiplier: \(error.localizedDescription)"))
        }
        
    }
    
    private func saveDeviceName() async {
        let result = await viewModel.updateDeviceName()
        switch result {
        case .success:
            snackbarManager.showSnackbar(message: String(localized: "Device name updated"))
        case .failure(let error):
            print("Error updating device name: \(error)")
            snackbarManager.showSnackbar(message: String(localized: "There was an error updating the device name."))
        }
    }

    private func handleResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            deviceManager.logout()
            break
        case .failure(let error):
            print("Error deleting account: \(error)")
            snackbarManager.showSnackbar(message: String(localized: "Sorry, there was an error deleting your account."))
        }
    }
    
    private func copyToPasteboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
    }
}
