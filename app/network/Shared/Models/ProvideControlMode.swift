//
//  ProvideControlMode.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 7/18/25.
//

import Foundation
import SwiftUI

enum ProvideControlMode: String, CaseIterable, Identifiable {
    case Auto = "auto"
    case Always = "always"
    // the private provider: always on, but provides only to same-network peers
    case Network = "network"
    case Never = "never"

    var id: Self { self }
}

func provideControlModeLabel(_ mode: ProvideControlMode?) -> LocalizedStringKey {
    switch mode {
        case .Auto:
        return "Auto"
    case .Always:
        return "Always"
    case .Network:
        return "Network"
    case .Never:
        return "Never"
    default:
        return "Auto"
    }
}
