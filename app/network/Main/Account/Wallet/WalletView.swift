//
//  WalletView.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/15.
//

import SwiftUI
import URnetworkSdk

struct WalletView: View {
    
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var payoutWalletViewModel: PayoutWalletViewModel
    @EnvironmentObject var snackbarManager: UrSnackbarManager
    
    var wallet: SdkAccountWallet
    var navigate: (AccountNavigationPath) -> Void
    let isPayoutWallet: Bool
    let payments: [SdkAccountPayment]
    let promptRemoveWallet: (SdkId) -> Void
    let fetchPayments: () async -> Void
    
    var walletName: String {

        if wallet.blockchain == "SOL" {
            return "Solana"
        }

        if wallet.blockchain == "TAO" {
            return "Bittensor"
        }

        // otherwise, POLY
        return "Polygon"

    }
    
    init(
        wallet: SdkAccountWallet,
        navigate: @escaping (AccountNavigationPath) -> Void,
        payoutWalletId: SdkId?,
        payments: [SdkAccountPayment],
        promptRemoveWallet: @escaping (SdkId) -> Void,
        fetchPayments: @escaping () async -> Void
    ) {
        self.wallet = wallet
        self.isPayoutWallet = payoutWalletId?.cmp(wallet.walletId) == 0
        self.payments = payments
        self.promptRemoveWallet = promptRemoveWallet
        self.fetchPayments = fetchPayments
        self.navigate = navigate
    }
    
    var body: some View {
        ScrollView {
         
            VStack {
                
                HStack {
                    
                    VStack(alignment: .leading) {
                        WalletIcon(
                            blockchain: wallet.blockchain
                        )
                    }
                    
                    Spacer().frame(width: 16)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        
                        Text("\(walletName) wallet")
                            .font(themeManager.currentTheme.secondaryTitleFont)
                            .foregroundColor(themeManager.currentTheme.textColor)
                        
                        HStack {
                            
                            Text("***\(String(wallet.walletAddress.suffix(6)))")
                                .font(themeManager.currentTheme.toolbarTitleFont)
                                .foregroundColor(themeManager.currentTheme.textColor)
                            
                            Spacer()

                            PayoutWalletTag(isPayoutWallet: isPayoutWallet)
                            
                        }
                        
                    }
                    
                    Spacer()
                    
                }
                
                Spacer().frame(height: 16)
                
                /**
                 * Actions
                 */
                VStack {

                    /**
                     * bittensor wallets are recorded for future use only and
                     * cannot be the payout wallet
                     */
                    if wallet.blockchain == "TAO" {

                        Text("Bittensor wallets are stored for future use and can't receive payouts yet.")
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(themeManager.currentTheme.textMutedColor)
                            .multilineTextAlignment(.center)

                        Spacer().frame(height: 8)

                    } else if !isPayoutWallet {

                        UrButton(text: "Make default", action: {
                            makeDefaultWallet()
                        })

                        Spacer().frame(height: 8)

                    }
                        
                    UrButton(
                        text: "Remove wallet",
                        action: {
                            
                            guard let walletId = wallet.walletId else {
                                
                                // TODO: snackbar error
                                
                                return
                            }
                            
                            promptRemoveWallet(walletId)
                        },
                        style: .outlineSecondary
                    )
                        
                }
                    
                Spacer().frame(height: 32)
                
                /**
                 * Payouts list
                 */
                PaymentsList(
                    payments: payments,
                    navigate: navigate
                )
                
                Spacer()
                
            }
            .padding()
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            
        }
        .refreshable {
            await fetchPayments()
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        await fetchPayments()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        #endif
    }
    
    private func makeDefaultWallet() {
        
        guard let walletId = wallet.walletId else {
            snackbarManager.showSnackbar(message: String(localized: "Error setting default wallet"))

            return
        }

        Task {
            switch await payoutWalletViewModel.updatePayoutWallet(walletId) {
            case .success:
                snackbarManager.showSnackbar(message: String(localized: "Payout wallet updated"))
            case .failure(let error):
                snackbarManager.showSnackbar(message: String(localized: "Error setting default wallet: \(error.localizedDescription)"))
            }
        }
    }
}

#Preview {
    WalletView(
        wallet: SdkAccountWallet(),
        navigate: {_ in},
        payoutWalletId: nil,
        payments: [],
        promptRemoveWallet: {_ in},
        fetchPayments: {}
    )
}
