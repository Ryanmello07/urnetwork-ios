//
//  ProvideControlPicker.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 9/26/25.
//

import SwiftUI
import URnetworkSdk

struct ProvideControlPicker: View {
    
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var deviceManager: DeviceManager
    
    // The indicator encodes the LIVE effective provide tier:
    //   - Network provide (same-network peers; also Auto while idle): a solid
    //     green circle
    //   - Public provide: a green circle with an outer green ring (yellow
    //     dot + ring while paused — pause stops public only)
    //   - not providing: a coral circle, no ring
    // ProvideMode is a bit set: compare per-case, never with ranges.
    private var provideIndicatorDotColor: Color {
        switch deviceManager.currentProvideMode {
        case SdkProvideModePublic:
            return deviceManager.providePaused ? .urYellow : .urGreen
        case SdkProvideModeNetwork, SdkProvideModeFriendsAndFamily:
            return .urGreen
        default:
            return .urCoral
        }
    }

    private var provideIndicatorRingColor: Color? {
        guard deviceManager.currentProvideMode == SdkProvideModePublic else {
            return nil
        }
        return deviceManager.providePaused ? .urYellow : .urGreen
    }

    var body: some View {

        LabeledContent{
            Picker(
                "",
                selection: $deviceManager.provideControlMode
            ) {
                ForEach(ProvideControlMode.allCases) { mode in
                    Text(provideControlModeLabel(mode))
                        .font(themeManager.currentTheme.bodyFont)

                }
            }} label: {
                HStack {

                    // fixed slot so the label doesn't shift when the ring
                    // appears/disappears
                    ZStack {
                        if let ringColor = provideIndicatorRingColor {
                            Circle()
                                .strokeBorder(ringColor, lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                        }
                        Circle()
                            .fill(provideIndicatorDotColor)
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 14, height: 14)

                    Text("Provide mode")
                        .font(themeManager.currentTheme.bodyFont)

                    Spacer()

                }
            }

        }

}

#Preview {
    ProvideControlPicker(
//        provideEnabled: true,
//        providePaused: false
    )
}
