//
//  WalletChain.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2025/01/09.
//

import Foundation

enum WalletChain: String {
    case sol = "SOL"
    // TAO (bittensor) wallets are recorded for future use only: they cannot
    // be the payout wallet (payouts are USDC on Solana/Polygon)
    case tao = "TAO"
    case invalid = "INVALID"
}
