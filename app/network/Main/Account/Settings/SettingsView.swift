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
        ZStack {
            SettingsForm_iOS(
                urApiService: api,
                clientId: clientId,
                referralCode: referralLinkViewModel.referralCode,
                totalReferrals: referralLinkViewModel.totalReferrals,
                referralNetworkName: viewModel.referralNetwork?.name,
                version: viewModel.version,
                isUpdatingAccountPreferences: accountPreferencesViewModel.isUpdatingAccountPreferences,
                copyToPasteboard: copyToPasteboard,
                presentUpdateReferralNetworkSheet: {
                    viewModel.presentUpdateReferralNetworkSheet = true
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
            
            SettingsCoreModifiersView(
                viewModel: viewModel,
                accountPreferencesViewModel: accountPreferencesViewModel,
                api: api,
                clientId: clientId,
                onSaveDeviceName: { await self.saveDeviceName() },
                onHandleDeleteResult: { self.handleResult($0) }
            )
            .environmentObject(themeManager)
            .environmentObject(snackbarManager)
            .environmentObject(connectWalletProviderViewModel)
            
            SettingsAuthModifiersView(
                viewModel: viewModel,
                api: api,
                handleWalletDeepLink: handleWalletDeepLink
            )
            .environmentObject(themeManager)
            .environmentObject(snackbarManager)
            .environmentObject(connectWalletProviderViewModel)
        }
        
        #elseif os(macOS)
        ZStack {
            SettingsForm_macOS(
                urApiService: api,
                clientId: clientId,
                referralCode: referralLinkViewModel.referralCode,
                totalReferrals: referralLinkViewModel.totalReferrals,
                referralNetworkName: viewModel.referralNetwork?.name,
                version: viewModel.version,
                isUpdatingAccountPreferences: accountPreferencesViewModel.isUpdatingAccountPreferences,
                copyToPasteboard: copyToPasteboard,
                presentUpdateReferralNetworkSheet: {
                    viewModel.presentUpdateReferralNetworkSheet = true
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
            
            SettingsCoreModifiersView(
                viewModel: viewModel,
                accountPreferencesViewModel: accountPreferencesViewModel,
                api: api,
                clientId: clientId,
                onSaveDeviceName: { await self.saveDeviceName() },
                onHandleDeleteResult: { self.handleResult($0) }
            )
            .environmentObject(themeManager)
            .environmentObject(snackbarManager)
            .environmentObject(connectWalletProviderViewModel)
            
            SettingsAuthModifiersView(
                viewModel: viewModel,
                api: api,
                handleWalletDeepLink: handleWalletDeepLink
            )
            .environmentObject(themeManager)
            .environmentObject(snackbarManager)
            .environmentObject(connectWalletProviderViewModel)
        }
        #endif
        
    }
    
    private func handleWalletDeepLink(_ url: URL) {
        let vm = connectWalletProviderViewModel
        if vm.pendingAddAuthSignatureHandler != nil,
           let pk = vm.connectedPublicKey {
            vm.handleDeepLink(
                url,
                onSignature: { signature in
                    if let handler = vm.pendingAddAuthSignatureHandler {
                        Task {
                            await handler(pk, signature)
                        }
                    }
                },
                onError: { _ in }
            )
        } else {
            vm.handleDeepLink(url)
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
