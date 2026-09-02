//
//  IpFamilyState.swift
//  URnetwork
//
//  The control-plane address family policy in force, and the one write path
//  that changes it.
//
//  DELIBERATELY UNLIKE LogVerbosityState, which routes everything through the
//  device and goes inert when there is none. This setting has to work with no
//  device and with the tunnel down, because those are the states a user is in
//  when the api is unreachable -- which is the whole reason to reach for it.
//  So the write is a THREE-way fallback, the same one android's
//  DeveloperViewModel uses: the device when there is one (on ios that is what
//  carries the policy into the packet tunnel extension, the process that dials
//  while the tunnel is up); else the network space (which sets this process
//  and records the choice for the next launch); else the process-global
//  SdkSetControlIpFamilyPolicy, which records nothing but at least puts the
//  choice in force for the session.
//
//  Held outside the view so an in-flight change is not abandoned by navigating
//  away mid-rpc.
//

import Foundation
import URnetworkSdk

final class IpFamilyState: ObservableObject {

    static let shared = IpFamilyState()

    /// The policy this process reports. Never a learned demotion -- that is
    /// `status` -- so the row round-trips exactly what was set and Automatic
    /// always reads back as Automatic.
    @Published private(set) var policy: Int = IpFamily.auto

    /// What the sdk has learned on its own, empty when nothing is demoted.
    /// Rendered in the detail line so Automatic does not look identical
    /// whether the heuristic has fired or not.
    @Published private(set) var status: String = ""

    /// True across a write. With a device the write is an rpc round trip into
    /// the extension, so the row is held rather than allowed to queue a second
    /// tap behind it.
    @Published private(set) var isApplying = false

    @MainActor
    func refresh(device: SdkDeviceRemote?) async {
        let read = await Task.detached(priority: .userInitiated) {
            (
                policy: device?.getControlIpFamilyPolicy() ?? Int(SdkGetControlIpFamilyPolicy()),
                status: SdkGetControlIpFamilyStatus()
            )
        }.value
        policy = IpFamily.clamp(read.policy)
        status = read.status
    }

    /**
     * Advances to the next policy and republishes what the sdk then reports.
     *
     * Three write paths, tried in order, matching android exactly:
     *
     * 1. the device, when there is one -- it sets this process, records the
     *    choice, AND carries the policy across to the extension, so it is
     *    always preferred;
     * 2. `networkSpace`, which is what makes this work signed out or with the
     *    tunnel down: it sets this process and persists the choice;
     * 3. the process-global setter, when there is neither -- nothing records
     *    it, but the session at least dials under what the row shows.
     *
     * `networkSpace` comes from `DeviceManager.networkSpace`
     * (`DeviceManager.swift:60`), which is an independent `@Published`
     * property and is NOT derived from `device`. Android's is
     * (`DeviceManager.kt:54` is `device?.networkSpace`), which is why that
     * platform fetches the space from `NetworkSpaceManagerProvider` instead.
     * The two reach the same three-way behaviour by different routes.
     */
    @MainActor
    func cycle(device: SdkDeviceRemote?, networkSpace: SdkNetworkSpace?) async {
        guard !isApplying else { return }
        let next = IpFamily.next(policy)

        isApplying = true
        await Task.detached(priority: .userInitiated) {
            if let device {
                device.setControlIpFamilyPolicy(next)
            } else if let networkSpace {
                networkSpace.setControlIpFamilyPolicy(next)
            } else {
                // no device and no space: set this process so the choice is at
                // least in force for the session, even though nothing records it
                SdkSetControlIpFamilyPolicy(next)
            }
        }.value
        isApplying = false

        await refresh(device: device)
    }
}
