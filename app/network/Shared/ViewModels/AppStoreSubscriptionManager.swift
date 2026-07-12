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

    /**
     * StoreKit ACCEPTED the purchase but it is not complete: it needs approval
     * (Ask to Buy) or another auth step (SCA). No transaction arrives now -- it lands
     * later on `Transaction.updates`.
     *
     * This used to be swallowed: `case .pending` only printed, so the sheet's spinner
     * simply stopped and dropped the user back on the product list with no
     * explanation. They reasonably conclude the purchase failed -- and try to buy
     * again.
     */
    @Published private(set) var purchasePending: Bool = false
    
    private var networkId: SdkId?
    var onPurchaseSuccess: (() -> Void)?

    /**
     * Bumped for every transaction StoreKit hands us on `Transaction.updates` — an
     * Ask to Buy approval that came through later, a purchase made on another device, a
     * renewal, anything that completed while the app was closed.
     *
     * This exists because `onPurchaseSuccess` is only assigned inside `purchase()`, while
     * the transaction listener starts at `init`. So on a FRESH LAUNCH the callback is nil:
     * StoreKit would deliver the transaction, we would dutifully `finish()` it, and then
     * do nothing at all. The user's purchase completed and the app never noticed — no
     * poll, no refresh, no Pro.
     *
     * A published counter cannot be nil, and the view observes it, so the wiring cannot
     * be forgotten the way an optional callback can.
     */
    @Published private(set) var transactionUpdateSequence: Int = 0
    
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

        /**
         * A new attempt starts clean.
         *
         * Without this, `purchaseSuccess` from an EARLIER attempt survives: the
         * manager is a @StateObject on MainView, so it lives for the whole session and
         * nothing ever set the flag back to false. Reopening the upgrade sheet then
         * renders PurchaseSuccessView immediately -- "You're premium." -- to a user
         * whose purchase never actually completed.
         */
        setPurchaseSuccess(false)
        setPurchasePending(false)

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
                /**
                 * Ask to Buy (a child needing a parent's approval) or an SCA step. The
                 * purchase is NOT done and no transaction arrives now -- it lands later
                 * on Transaction.updates. Surface it, so the sheet can tell the user
                 * their purchase is awaiting approval instead of silently returning
                 * them to the product list as if nothing happened.
                 */
                print("Purchase pending approval")
                setPurchasePending(true)

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

    @MainActor
    func setPurchasePending(_ pending: Bool) {
        self.purchasePending = pending
    }

    /**
     * Clear the terminal states so the upgrade sheet opens fresh. Called when the
     * sheet is dismissed: the flags describe ONE attempt, and letting them leak into
     * the next presentation is what showed "You're premium." to a user who was not.
     */
    @MainActor
    func resetPurchaseState() {
        self.purchaseSuccess = false
        self.purchasePending = false
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
                            // The in-flight purchase callback, when there IS one.
                            self.onPurchaseSuccess?()

                            // ...and the signal that always fires. On a fresh launch the
                            // callback above is nil (it is only set inside purchase()), so
                            // without this an Ask-to-Buy approval or a cross-device
                            // purchase would be silently swallowed.
                            self.transactionUpdateSequence += 1
                        }
                    }

                case .unverified(_, let error):
                    print("Unverified transaction: \(error.localizedDescription)")
                }
            }
        }
    }
}
