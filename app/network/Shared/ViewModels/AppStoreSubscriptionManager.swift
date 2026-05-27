//
//  SubscriptionManager.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/31.
//

import Foundation
import StoreKit
import URnetworkSdk

/**
 * For creating a subscription with the App Store
 */
@MainActor
class AppStoreSubscriptionManager: ObservableObject {
    // @Published var products: [Product] = []
    
    @Published var monthlySubscription: Product?
    @Published var yearlySubscription: Product?
    
    @Published var isPurchasing: Bool = false
    @Published private(set) var purchaseSuccess: Bool = false
    
    private var networkId: SdkId?
    var onPurchaseSuccess: (() -> Void)?
    
    private var updateListenerTask: Task<Void, Error>?
    
    init(networkId: SdkId?) {
        self.networkId = networkId
        
        updateListenerTask = listenForTransactions()
        
        Task {
            await fetchProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func fetchProducts() async {
        do {
            let productIdentifiers = ["supporter_monthly_26", "supporter_yearly_26"]
            
            let storeProducts = try await Product.products(for: productIdentifiers)
            
            if let monthlySub = storeProducts.first(where: { $0.id == "supporter_monthly_26" }) {
                self.monthlySubscription = monthlySub
            }
            
            if let yearlySub = storeProducts.first(where: { $0.id == "supporter_yearly_26" }) {
                self.yearlySubscription = yearlySub
            }
            
            print("Retrieved products: \(storeProducts.count)")
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    @MainActor
    private func setIsPurchasing(_ isPurchasing: Bool) async {
        self.isPurchasing = isPurchasing
    }
    
    func purchase(product: Product, onSuccess: @escaping (() -> Void)) async throws {
        guard !isPurchasing else { return }

        await setIsPurchasing(true)

        self.onPurchaseSuccess = onSuccess
        let callback = onSuccess
        
        do {
            var purchaseOptions: Set<Product.PurchaseOption> = []
            
            guard let networkId = self.networkId else {
                await setIsPurchasing(false)
                return
            }

            if let networkUUID = UUID(uuidString: networkId.idStr) {
                purchaseOptions.insert(.appAccountToken(networkUUID))
            } else {
                await setIsPurchasing(false)
                return
            }
            
            let result = try await product.purchase(options: purchaseOptions)
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("✅ Purchase verified: \(transaction.id)")
                    
                    logTransactionDetails(transaction)
                    
                    await transaction.finish()

                    callback()
                    setPurchaseSuccess(true)
                    
                case .unverified( _, let error):
                    print("Purchase unverified: \(error)")
                    throw error
                }
                
            case .userCancelled:
                print("Purchase cancelled by user")
                throw SKError(.paymentCancelled)
                
            case .pending:
                print("Purchase pending approval")
                
            @unknown default:
                print("Unknown purchase result")
            }
        } catch {
            print("Purchase failed: \(error)")
            await setIsPurchasing(false)
            throw error
        }
        
        await setIsPurchasing(false)
    }
    
    @MainActor
    func setPurchaseSuccess(_ success: Bool) {
        self.purchaseSuccess = success
    }

    private func logTransactionDetails(_ transaction: Transaction) {
        print("Transaction ID: \(transaction.id)")
        print("Product ID: \(transaction.productID)")
        print("Purchase Date: \(transaction.purchaseDate)")
        
        if let appAccountToken = transaction.appAccountToken {
            print("App Account Token: \(appAccountToken)")
        }
    }
    
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                switch result {
                case .verified(let transaction):
                    await self.logTransactionDetails(transaction)
                    await transaction.finish()

                    if transaction.revocationDate == nil {
                        await MainActor.run {
                            self.onPurchaseSuccess?()
                        }
                    }

                case .unverified(_, let error):
                    print("Unverified transaction: \(error.localizedDescription)")
                }
            }
        }
    }
}
