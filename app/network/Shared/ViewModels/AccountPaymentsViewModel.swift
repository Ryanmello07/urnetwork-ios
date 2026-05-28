//
//  AccountPaymentsViewModel.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/17.
//

import Foundation
import URnetworkSdk

private class GetAccountPaymentsCallback: SdkCallback<SdkGetNetworkAccountPaymentsResult, SdkGetAccountPaymentsCallbackProtocol>, SdkGetAccountPaymentsCallbackProtocol {
    func result(_ result: SdkGetNetworkAccountPaymentsResult?, err: Error?) {
        handleResult(result, err: err)
    }
}

@MainActor
class AccountPaymentsViewModel: ObservableObject {
    
    let domain = "[AccountPaymentsViewModel]"
    @Published private(set) var isLoadingPayments: Bool = false
    @Published private(set) var totalPayoutsUsdc: Double = 0.0
    @Published private(set) var payments: [SdkAccountPayment] = []
    
    var api: SdkApi?
    
    init(api: SdkApi?) {
        self.api = api
        self.initPayments()
    }
    
    func initPayments() {
        Task {
            await fetchPayments()
        }
    }
    
    func fetchPayments() async {
        
        if isLoadingPayments { return }
        
        isLoadingPayments = true
        
        do {
            
            let result: SdkGetNetworkAccountPaymentsResult = try await withCheckedThrowingContinuation { continuation in
                
                let callback = GetAccountPaymentsCallback { result, err in
                    
                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }
                    
                    guard let result = result else {
                        continuation.resume(throwing: NSError(domain: "[AccountPaymentsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "GetAccountPaymentsCallback result is nil"]))
                        return
                    }
                    
                    continuation.resume(returning: result)
                    
                }
                
                guard let api = self.api else {
                    continuation.resume(throwing: NSError(domain: "[AccountPaymentsViewModel]", code: 0, userInfo: [NSLocalizedDescriptionKey: "API not available"]))
                    return
                }
                api.getAccountPayments(callback)
            }
            
            if let resultError = result.error {
                throw NSError(domain: domain, code: -1, userInfo: [NSLocalizedDescriptionKey: resultError.message])
            }

            handlePayoutResult(result)
            self.isLoadingPayments = false
            
        } catch(let error) {
            print("\(domain) error fetching payouts \(error)")
            self.isLoadingPayments = false
        }
        
    }
    
    private func handlePayoutResult(_ result: SdkGetNetworkAccountPaymentsResult) {
        
        guard let accountPaymentList = result.accountPayments else {
            self.totalPayoutsUsdc = 0
            self.payments = []
            return
        }
        
        let len = accountPaymentList.len()
        var payouts: [SdkAccountPayment] = []
        var totalPayments: Double = 0
        
        self.totalPayoutsUsdc = 0
        
        if len > 0 {
            
            for i in 0..<len {
                
                if let payout = accountPaymentList.get(i) {
                    payouts.append(payout)
                    totalPayments += payout.tokenAmount
                }
            }
        }
        
        self.totalPayoutsUsdc = totalPayments
        
        self.payments = payouts
        
    }
    
    func filterPaymentsByWalletId(_ walletId: SdkId?) -> [SdkAccountPayment] {
        return payments.filter { $0.walletId?.cmp(walletId) == 0 }
    }
    
    func totalPaymentsByWalletId(_ walletId: SdkId?) -> Double {
        let walletPayments = filterPaymentsByWalletId(walletId)
        
        var totalWalletPayments = Double(0)
        
        for payment in walletPayments {
            totalWalletPayments += payment.tokenAmount
        }
        
        return totalWalletPayments
        
    }
    
}
