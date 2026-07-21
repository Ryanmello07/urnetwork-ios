//
//  QuickConnectControl.swift
//  URnetwork Quick Connect control
//
//  A Control Center (and Lock Screen / Action Button) toggle that connects and
//  disconnects the URnetwork VPN — the iOS parallel to the Android Quick
//  Settings tile. iOS 18+.
//
//  Toggle state is read WITHOUT the SDK: NETunnelProviderManager.connection
//  reports the live NEVPNStatus cross-process, so the extension needs only the
//  VPN entitlement, not the Go SDK. The toggle action (ToggleVPNConnectionIntent)
//  hands off to the app for the actual connect/disconnect.
//

import AppIntents
import NetworkExtension
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct QuickConnectControl: ControlWidget {

    static let kind = "network.ur.control.quickconnect"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isConnected in
            ControlWidgetToggle(
                "URnetwork",
                isOn: isConnected,
                action: ToggleVPNConnectionIntent()
            ) { isOn in
                Label {
                    Text(isOn ? "Connected" : "Disconnected")
                } icon: {
                    // QuickOn / QuickOff live in the extension's asset catalog as
                    // template images (the connector mark, filled vs outline)
                    Image(isOn ? "QuickOn" : "QuickOff")
                        .renderingMode(.template)
                }
            }
            .tint(.green)
        }
        .displayName("URnetwork VPN")
        .description("Connect or disconnect the URnetwork VPN.")
    }
}

@available(iOS 18.0, *)
extension QuickConnectControl {

    struct Provider: ControlValueProvider {

        // shown in the gallery / while the real value loads
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            await TunnelStatus.isActive()
        }
    }
}

/// Reads the URnetwork tunnel's live status without the SDK. `loadAllFromPreferences`
/// surfaces the same NETunnelProviderManager the app configures; its connection
/// status is authoritative and available cross-process.
enum TunnelStatus {

    static func isActive() async -> Bool {
        await withCheckedContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let active = managers?.contains { manager in
                    switch manager.connection.status {
                    case .connected, .connecting, .reasserting:
                        return true
                    default:
                        return false
                    }
                } ?? false
                continuation.resume(returning: active)
            }
        }
    }
}
