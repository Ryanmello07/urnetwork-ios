# Quick Connect control — setup

These source files implement an iOS **Control Center** (and Lock Screen / Action
Button) toggle that connects and disconnects the URnetwork VPN — the counterpart
to the Android Quick Settings tile. iOS 18+.

The code is complete. What remains can only be done in Xcode + the Apple Developer
portal (a new extension target needs its own signed App ID), so it is **not wired
into `app.xcodeproj` yet** — doing that by hand risks corrupting the project file.
Follow the steps below.

## Files here

| file | target membership |
| --- | --- |
| `QuickConnectControl.swift` | control extension |
| `QuickConnectControlBundle.swift` (`@main`) | control extension |
| `ToggleVPNConnectionIntent.swift` | **both** app + control extension |
| `Assets.xcassets` (`QuickOn`, `QuickOff` from `~/Desktop/Quick*.svg`) | control extension |
| `Info.plist`, `control.entitlements` | control extension config |

`ToggleVPNConnectionIntent` runs in the **app** (`openAppWhenRun = true`) so the SDK
can refresh credentials for a correct connect and the extension never loads the Go
SDK (its memory budget is tiny). It reuses `ConnectIntent` / `DisconnectIntent`
verbatim, so it must compile in the app target — hence dual membership. (Until it
is added to the app target, SourceKit reports "Cannot find 'ConnectIntent'", which
is only a target-membership artifact.)

## Xcode steps

1. **Add the target.** File ▸ New ▸ Target ▸ **Widget Extension**. Name it
   `QuickConnectControl`, bundle id `network.ur.control`, uncheck "Include Live
   Activity", check "Include Control" if offered. Delete the stub files Xcode
   generates.
2. **Add these files to the new target** (drag `app/control/*` into it). Set
   `ToggleVPNConnectionIntent.swift` membership to **both** `URnetwork` and
   `QuickConnectControl` (File Inspector ▸ Target Membership). Point the target's
   Info.plist at `control/Info.plist` and Code Signing Entitlements at
   `control/control.entitlements`.
3. **App ID + signing.** Register the `network.ur.control` App ID in the developer
   portal with the **Network Extensions / Personal VPN** capability, matching the
   app and packet-tunnel targets' team. Without this the extension will not sign.
4. **Deployment target** ≥ iOS 18 for the control (or gate as written — the code
   already `@available(iOS 18.0, *)`-guards, so the extension can target lower and
   simply not vend the control below 18).
5. Build, run, then add the control from Control Center's edit screen.

## State-read options

The toggle reflects live state via `TunnelStatus.isActive()`, which reads
`NETunnelProviderManager.connection.status`. This needs the VPN entitlement in the
extension (step 3) and assumes the extension can see the app's tunnel config under
the shared team/provisioning.

If you would rather not give the control a VPN entitlement, use an **App Group**:
have the app observe `NEVPNStatusDidChange` and write a `Bool` into
`UserDefaults(suiteName:)`; have `TunnelStatus` read that instead. This also
removes the cross-process visibility assumption. It requires adding an App Group
to the app, the packet-tunnel extension, and this control (none exists today).

## Not verifiable in this environment

A new signed extension target cannot be provisioned or built here, so this control
has **not** been build- or device-tested. Verify on device: the toggle appears in
Control Center, reflects connect state, connects (opening the app briefly) and
disconnects.

## Possible follow-up

`openAppWhenRun = true` briefly foregrounds the app on every toggle. Disconnect
could be made silent (in-extension `stopVPNTunnel()`, no credentials needed) via a
`ForegroundContinuableIntent` that only defers to the app for connect. That needs
on-device testing of the background-execution + credential-refresh path, so it is
intentionally left out of v1.
