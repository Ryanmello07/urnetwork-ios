//
//  ToggleVPNConnectionIntent.swift
//  URnetwork Quick Connect control
//
//  The Set-Value intent behind the Control Center toggle. It reuses the proven
//  ConnectIntent / DisconnectIntent flows rather than duplicating the tunnel
//  logic.
//
//  It runs in the APP (openAppWhenRun = true), not the control extension, on
//  purpose: a correct connect needs fresh credentials (by_jwt, network space,
//  instance id) from the live SDK device — the same reason ConnectIntent builds
//  a DeviceManager. Initializing the Go SDK inside a Control Center extension
//  would also blow the extension's tight memory budget. Reading state for the
//  toggle stays SDK-free (see QuickConnectControl's provider), so only the
//  actual connect/disconnect touches the app.
//
//  Target membership: this file must belong to BOTH the app target (where it
//  executes) and the control extension target (which references the type to bind
//  the toggle). See control/README-SETUP.md.
//

import AppIntents

struct ToggleVPNConnectionIntent: SetValueIntent {

    static let title: LocalizedStringResource = "Toggle URnetwork VPN"

    // driven from the control, not surfaced as a standalone Siri phrase
    static var isDiscoverable: Bool = false

    // run in the app so the SDK can refresh credentials for a correct connect
    static var openAppWhenRun: Bool = true

    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    // the desired connected state, set by the toggle before perform()
    @Parameter(title: "Connected")
    var value: Bool

    func perform() async throws -> some IntentResult {
        if value {
            _ = try await ConnectIntent().perform()
        } else {
            _ = try await DisconnectIntent().perform()
        }
        return .result()
    }
}
