//
//  WalletsViewModel.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/15.
//

import Foundation
import URnetworkSdk

private class TransferStatsCallback: SdkCallback<SdkTransferStatsResult, SdkGetTransferStatsCallbackProtocol>, SdkGetTransferStatsCallbackProtocol {
    func result(_ result: SdkTransferStatsResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

private class GetAccountWalletsCallback: SdkCallback<SdkGetAccountWalletsResult, SdkGetAccountWalletsCallbackProtocol>, SdkGetAccountWalletsCallbackProtocol {
    func result(_ result: SdkGetAccountWalletsResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

private class RemoveWalletCallback: SdkCallback<SdkRemoveWalletResult, SdkRemoveWalletCallbackProtocol>, SdkRemoveWalletCallbackProtocol {
    func result(_ result: SdkRemoveWalletResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

enum RemoveWalletError: Error {
    case isLoading
    case noWalletId
}

@MainActor
class AccountWalletsViewModel: ObservableObject {

    let domain = "[AccountWalletsViewModel]"
    @Published private(set) var wallets: [SdkAccountWallet] = []
    @Published private(set) var isLoadingTransferStats: Bool = false
    @Published private(set) var isLoadingAccountWallets: Bool = false
    @Published private(set) var isCreatingExternalWallet: Bool = false
    @Published private(set) var isRemovingWallet: Bool = false

    /**
     * For removing wallet
     */
    @Published var isPresentingRemoveWalletSheet: Bool = false
    @Published var queuedToRemove: SdkId?

    @Published private(set) var unpaidDataFormatted: String = ""

    /**
     * For connecting a new wallet
     */
    @Published var isCreatingWallet: Bool = false

    /**
     * Saga / Seeker token holder
     */
    @Published private(set) var isSeekerOrSagaHolder: Bool = false

    var api: SdkApi?

    init(api: SdkApi?) {
        self.api = api
        self.initAccountWallets()
        self.initTransferStats()
    }

    func initAccountWallets() {
        Task {
            await fetchAccountWallets()
        }
    }

    func fetchAccountWallets() async {

        if isLoadingAccountWallets {
            return
        }

        isLoadingAccountWallets = true

        do {
            let result: SdkGetAccountWalletsResult = try await withCheckedThrowingContinuation { continuation in

                let callback = GetAccountWalletsCallback { result, err in

                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "SdkGetAccountWalletsResult result is nil"]))
                        return
                    }

                    continuation.resume(returning: result)

                }

                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.getAccountWallets(callback)
            }

            wallets = handleAccountWalletsList(result)
            isLoadingAccountWallets = false

        } catch(let error) {
            print("\(domain) Error fetching account wallets: \(error)")
            isLoadingAccountWallets = false
        }

    }

    private func handleAccountWalletsList(_ result: SdkGetAccountWalletsResult) -> [SdkAccountWallet] {

        guard let walletsList = result.wallets else { return [] }

        var accountWallets: [SdkAccountWallet] = []
        var hasSeekerToken = false
        let n = walletsList.len()

        for i in 0..<n {
            let wallet = walletsList.get(i)

            if let wallet = wallet {
                accountWallets.append(wallet)

                if wallet.hasSeekerToken {
                    hasSeekerToken = true
                }
            }
        }

        self.isSeekerOrSagaHolder = hasSeekerToken

        return accountWallets

    }

    func initTransferStats() {
        Task {
            await fetchTransferStats()
        }
    }

    /**
     * Fetch unpaid bytes provided
     */
    func fetchTransferStats() async {

        if isLoadingTransferStats {
            return
        }

        isLoadingTransferStats = true

        do {

            let result: SdkTransferStatsResult = try await withCheckedThrowingContinuation { continuation in

                let callback = TransferStatsCallback { result, err in

                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "TransferStatsCallback result is nil"]))
                        return
                    }

                    continuation.resume(returning: result)
                }

                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.getTransferStats(callback)

            }

            let unpaidBytes = result.unpaidBytesProvided


            if unpaidBytes >= 1_000_000_000 {
                let unpaidGigaBytes = Double(unpaidBytes) / 1_000_000_000.0
                unpaidDataFormatted = String(format: "%.2f GB", unpaidGigaBytes)
            } else {
                let unpaidMegaBytesValue = Double(unpaidBytes) / 1_000_000.0
                unpaidDataFormatted = String(format: "%.2f MB", unpaidMegaBytesValue)
            }

            isLoadingTransferStats = false

        } catch(let error) {
            print("\(domain) Error fetching transfer stats: \(error)")
            isLoadingTransferStats = false
        }

    }

}

// MARK: remove wallet
extension AccountWalletsViewModel {

    func promptRemoveWallet(_ walletId: SdkId) {
        isPresentingRemoveWalletSheet = true
        queuedToRemove = walletId
    }

    func removeWallet() async -> Result<Void, Error> {

        if isRemovingWallet {
            return .failure(RemoveWalletError.isLoading)
        }

        guard let walletId = queuedToRemove else {
            return .failure(RemoveWalletError.noWalletId)
        }

        isRemovingWallet = true

        do {
            let result: SdkRemoveWalletResult = try await withCheckedThrowingContinuation { continuation in

                let callback = RemoveWalletCallback { result, err in

                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "SdkRemoveWalletResult result is nil"]))
                        return
                    }

                    continuation.resume(returning: result)
                }

                let args = SdkRemoveWalletArgs()
                args.walletId = walletId.idStr

                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.removeWallet(args, callback: callback)

            }

            if let resultError = result.error {
                throw NSError(domain: domain, code: -1, userInfo: [NSLocalizedDescriptionKey: resultError.message])
            }

            guard result.success else {
                throw NSError(domain: domain, code: -1, userInfo: [NSLocalizedDescriptionKey: "Remove wallet failed"])
            }

            await fetchAccountWallets()
            isRemovingWallet = false

            return .success(())
        } catch(let error) {
            isRemovingWallet = false
            print("\(domain) error removing wallet: \(error)")
            return .failure(error)
        }

    }
}


// MARK: connect wallet
extension AccountWalletsViewModel {

    func connectWallet(walletAddress: String, chain: WalletChain) async -> Result<Void, Error> {

        if isCreatingWallet {
            return .failure(CreateWalletError.isLoading)
        }

        if chain == .invalid {
            return .failure(CreateWalletError.invalidChain)
        }

        isCreatingWallet = true

        do {

            let result: SdkCreateAccountWalletResult = try await withCheckedThrowingContinuation { continuation in

                let callback = CreateAccountWalletCallback { result, err in

                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "SdkCreateAccountWalletResult result is nil"]))
                        return
                    }

                    continuation.resume(returning: result)
                }

                let args = SdkCreateAccountWalletArgs()
                args.blockchain = chain.rawValue
                args.walletAddress = walletAddress

                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[AccountWalletsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.createAccountWallet(args, callback: callback)
            }

            guard result.walletId != nil else {
                throw CreateWalletError.invalidResult
            }

            isCreatingWallet = false
            await self.fetchAccountWallets()
            return .success(())

        } catch(let error) {
            isCreatingWallet = false
            return .failure(error)
        }

    }

}

private class CreateAccountWalletCallback: SdkCallback<SdkCreateAccountWalletResult, SdkCreateAccountWalletCallbackProtocol>, SdkCreateAccountWalletCallbackProtocol {
    func result(_ result: SdkCreateAccountWalletResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

private class ValidateAddressCallback: SdkCallback<SdkWalletValidateAddressResult, SdkWalletValidateAddressCallbackProtocol>, SdkWalletValidateAddressCallbackProtocol {
    func result(_ result: SdkWalletValidateAddressResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

enum CreateWalletError: Error {
    case isLoading
    case invalidResult
    case invalidChain
    case invalidAddress
}

