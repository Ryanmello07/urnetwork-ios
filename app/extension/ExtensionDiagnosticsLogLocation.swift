//
//  ExtensionDiagnosticsLogLocation.swift
//  network (packet tunnel extension)
//
//  Where the extension process writes its logs.
//
//  This duplicates app/network/Shared/DiagnosticsLogLocation.swift rather than
//  being shared with it: the app target binds URnetworkSdk and this extension
//  target binds URnetworkExtensionSdk -- two separately named xcframeworks
//  generated from the same Go package, so a single Swift file cannot import
//  the correct module for both targets. The app-group identifier and the
//  "Logs/<processName>" subdirectory layout are the contract between the two
//  copies -- keep them in sync by hand if either changes.
//

import Foundation
import URnetworkExtensionSdk

enum ExtensionDiagnosticsLogLocation {

    static let appGroupIdentifier = "group.network.ur"

    static let processName = "extension"

    /// Points this process's glog at its own subdirectory of the shared log
    /// root (or a local fallback when the App Group container is
    /// unreachable). Call once per process, at startup.
    static func configure() {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let root = (container ?? fallback).appendingPathComponent("Logs")

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var err: NSError?
        SdkSetLogDirForProcess(root.path, processName, &err)
    }
}
