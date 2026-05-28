//
//  PayoutWalletViewModel.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/18.
//

import Foundation
import URnetworkSdk

private class FetchPayoutWalletCallback: SdkCallback<SdkGetPayoutWalletIdResult, SdkGetPayoutWalletCallbackProtocol>, SdkGetPayoutWalletCallbackProtocol {
    func result(_ result: SdkGetPayoutWalletIdResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

private class UpdatePayoutWalletCallback: SdkCallback<SdkSetPayoutWalletResult, SdkSetPayoutWalletCallbackProtocol>, SdkSetPayoutWalletCallbackProtocol {
    func result(_ result: SdkSetPayoutWalletResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

enum UpdatePayoutWalletError: Error {
    case isLoading
}


@MainActor
class PayoutWalletViewModel: ObservableObject {
    
    var api: SdkApi?
    let domain = "[PayoutWalletViewModel]"
    
    @Published private(set) var payoutWalletId: SdkId?
    @Published private(set) var isFetchingPayoutWallet: Bool = false
    @Published private(set) var isUpdatingPayoutWallet: Bool = false
    
    init(api: SdkApi?) {
        self.api = api
        self.initPayoutWallet()
    }
    
    private func initPayoutWallet() {
        Task {
            await fetchPayoutWallet()
        }
    }
    
    func fetchPayoutWallet() async {
        
        if isFetchingPayoutWallet {
            return
        }
        
        isFetchingPayoutWallet = true
        
        do {
            
            let result: SdkGetPayoutWalletIdResult = try await withCheckedThrowingContinuation { continuation in

                let callback = FetchPayoutWalletCallback { result, err in

                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[PayoutWalletViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "FetchPayoutWalletCallback result is nil"]))
                        return
                    }
                    
                    continuation.resume(returning: result)
                    
                }
                
                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[PayoutWalletViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.getPayoutWallet(callback)

            }
            
            self.payoutWalletId = result.walletId
            
            isFetchingPayoutWallet = false
            
        } catch(let error) {
            print("\(domain) Error fetching payout wallet: \(error)")
            isFetchingPayoutWallet = false
        }
        
    }
    
    func updatePayoutWallet(_ walletId: SdkId) async -> Result<Void, Error> {
        
        if isUpdatingPayoutWallet {
            return .failure(UpdatePayoutWalletError.isLoading)
        }
        
        isUpdatingPayoutWallet = true
        
        do {
            
            let _: SdkSetPayoutWalletResult = try await withCheckedThrowingContinuation { continuation in

                let callback = UpdatePayoutWalletCallback { result, err in

                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[PayoutWalletViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "UpdatePayoutWalletCallback result is nil"]))
                        return
                    }
                    
                    continuation.resume(returning: result)
                    
                }
                
                let args = SdkSetPayoutWalletArgs()
                args.walletId = walletId
                
                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[PayoutWalletViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.setPayoutWallet(args, callback: callback)
            }
            
            isUpdatingPayoutWallet = false
            payoutWalletId = walletId
            
            return .success(())
            
        } catch(let error) {
            
            isUpdatingPayoutWallet = false
            return .failure(error)
        }
        
    }
    
}
