//
//  UrGoogleSignInButton.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/06.
//

import SwiftUI

struct UrGoogleSignInButton: View {
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var action: () async -> Void
    var enabled: Bool = true
    var isProcessing: Bool = false
    
    var body: some View {
        
        #if os(iOS)
        Button(action: {
            Task {
                await action()
            }
        }) {
            ZStack {
                HStack(alignment: .center) {
                    
                    Image("GoogleIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    
                    Text("Sign in with Google")
                        .foregroundColor(themeManager.currentTheme.inverseTextColor)
                        .font(
                            Font.system(size: 19, weight: .medium)
                        )
                    
                }
                
                if isProcessing {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.urBlack)
                            .controlSize(.small)
                            .padding(.trailing, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 48)
        .background(.white)
        .clipShape(Capsule())
        .opacity(enabled || isProcessing ? 1 : 0.3)
        .disabled(!enabled || isProcessing)
        
        #elseif os(macOS)
        Button(action: {
            Task {
                await action()
            }
        }) {
            ZStack {
                HStack(alignment: .center) {
                    
                    Image("GoogleIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                    
                    Text("Sign in with Google")
                        .foregroundColor(themeManager.currentTheme.inverseTextColor)
                        .font(
                            Font.system(size: 12, weight: .medium)
                        )
                    
                }
                
                if isProcessing {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.urBlack)
                            .controlSize(.small)
                            .padding(.trailing, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 30)
        .background(.white)
        .cornerRadius(6)
        // .clipShape(Capsule())
        .opacity(enabled || isProcessing ? 1 : 0.3)
        .disabled(!enabled || isProcessing)
        
        #endif
        
    }
    
}
