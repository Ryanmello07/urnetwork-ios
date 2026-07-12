//
//  WalletIcon.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/19.
//

import SwiftUI

struct WalletIcon: View {
    var blockchain: String
    
    var backgroundGradient: Gradient {

        if blockchain == "SOL" {
            return Gradient(colors: [Color(hex: "#9945FF"), Color(hex: "#14F195")])
        }

        if blockchain == "TAO" {
            return Gradient(colors: [Color(hex: "#1C1C1C"), Color(hex: "#3A3A3A")])
        }

        // otherwise, POLY
        return Gradient(colors: [Color(hex: "#8A46FF"), Color(hex: "#6E38CC")])
    }

    var logoPath: String {

        if blockchain == "SOL" {
            return "solana.logo"
        }

        // otherwise, POLY
        return "polygon.logo"

    }

    var logoWidth: CGFloat {

        if blockchain == "SOL" {
            return 24
        }

        // otherwise, POLY
        return 48

    }

    var body: some View {

        ZStack {
            LinearGradient(gradient: backgroundGradient, startPoint: .top, endPoint: .bottom)
                .clipShape(
                    Circle()
                )

            if blockchain == "TAO" {
                // the bittensor tau mark
                Text("τ")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Image(logoPath)
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoWidth, height: logoWidth)
            }
        }
        .frame(width: 48, height: 48)

    }
}

#Preview {
    WalletIcon(
        blockchain: "SOL"
    )
}
