//
//  DiagnosticsLogLocation.swift
//  URnetwork
//
//  Where each process writes its logs.
//
//  The app and the packet tunnel extension are separate processes with
//  separate containers, and the real DeviceLocal runs in the extension. An App
//  Group container is the only way the app can read what the extension wrote,
//  and it is the right way rather than shipping the files over the device rpc:
//  the extension runs on a 20MB device memory target, and log files are up to
//  16MB each.
//

import Foundation
import URnetworkSdk

enum DiagnosticsLogLocation {

    static let appGroupIdentifier = "group.network.ur"

    static let appProcessName = "app"
    static let extensionProcessName = "extension"

    /// The log root, and whether it is the shared container.
    ///
    /// `isShared == false` means this build cannot see the other process's
    /// logs -- normally a provisioning profile without the App Group. The
    /// export reports that as a missing source rather than failing.
    static func logRoot(containerURL: URL?, fallbackURL: URL) -> (url: URL, isShared: Bool) {
        if let containerURL {
            return (containerURL.appendingPathComponent("Logs"), true)
        }
        return (fallbackURL.appendingPathComponent("Logs"), false)
    }

    /// Whether the shared container was reached, recorded by `configure`.
    ///
    /// Read this from the ui rather than calling `configure` again: configure
    /// re-points glog and must run exactly once per process, at startup.
    private(set) static var isSharedContainerAvailable = false

    /// Points this process's glog at its own subdirectory of the log root.
    /// Call once per process, at startup. Returns whether the shared container
    /// was reached.
    @discardableResult
    static func configure(processName: String) -> Bool {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let location = logRoot(containerURL: container, fallbackURL: fallback)

        try? FileManager.default.createDirectory(at: location.url, withIntermediateDirectories: true)

        var err: NSError?
        SdkSetLogDirForProcess(location.url.path, processName, &err)

        isSharedContainerAvailable = location.isShared
        return location.isShared
    }
}
