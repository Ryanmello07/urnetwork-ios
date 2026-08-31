//
//  DiagnosticExportService.swift
//  URnetwork
//
//  Builds a diagnostic bundle in the app process. The app holds the
//  increased-memory-limit entitlement; the extension does not, which is why
//  the zip is assembled here from files in the shared container rather than
//  inside the extension or over the device rpc.
//

import Foundation
import URnetworkSdk

enum DiagnosticExportService {

    /// Bundles are written into their own subdirectory of tmp so a new export
    /// can clear the previous one: iOS purges tmp only under storage pressure
    /// or on an OS upgrade, and each bundle can hold up to 4x16MB of logs per
    /// process, so without this a handful of exports sit on hundreds of MB
    /// forever. Clearing the whole directory also collects the partial zip a
    /// failed export leaves behind -- the SDK creates the destination before
    /// it can discover that it cannot finish.
    static var bundleDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics", isDirectory: true)
    }

    static func bundleFileName(date: Date, redacted: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let suffix = redacted ? "-redacted" : ""
        return "urnetwork-diagnostics-\(formatter.string(from: date))\(suffix).zip"
    }

    /// The written bundle and a one-line summary of what it contains, including
    /// any source that could not be read.
    struct Export {
        let url: URL
        let summary: String
    }

    /// Writes a bundle into the temporary directory and returns it.
    ///
    /// `sharedRootUnavailableReason` is non-nil when this process is not
    /// logging into the App Group container, so the extension's logs cannot be
    /// present -- recorded in the bundle rather than treated as a failure.
    static func export(
        redacted: Bool,
        selectedNames: [String],
        device: SdkDeviceRemote?,
        sharedRootUnavailableReason: String?,
        date: Date = Date()
    ) throws -> Export {
        let directory = bundleDirectory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory
            .appendingPathComponent(bundleFileName(date: date, redacted: redacted))

        guard let options = SdkNewExportOptions() else {
            throw NSError(domain: "network.ur.diagnostics", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not create export options"])
        }
        options.redact = redacted
        options.includeManifest = true
        for name in selectedNames {
            options.selectedNames?.add(name)
        }
        if let device {
            options.setManifestJson(device.diagnosticManifestJson())
        }
        if let reason = missingExtensionReason(
            sharedRootUnavailableReason: sharedRootUnavailableReason,
            inventorySources: sources(of: inventory())
        ) {
            options.missingSourceReason(
                DiagnosticsLogLocation.extensionProcessName,
                reason: reason
            )
        }

        var err: NSError?
        let result = SdkExportDiagnosticBundle(destination.path, options, &err)
        if let err {
            // the SDK creates destPath before it can discover it cannot
            // finish, so a failed export otherwise orphans a partial zip that
            // nothing ever points at and nothing ever deletes
            try? FileManager.default.removeItem(at: destination)
            throw err
        }

        var summary = ""
        if let result {
            summary = "Exported \(result.fileCount) log files (\(sizeLabel(result.byteCount)))"
            if let missing = result.missingSources {
                for i in 0..<missing.len() {
                    summary += "\nNot included: \(missing.get(i))"
                }
            }
        }
        return Export(url: destination, summary: summary)
    }

    /// Why the extension's logs are not in this bundle, or nil when they are.
    ///
    /// The entitlement being absent is only one of the ways this source goes
    /// missing, and it was the only one being reported. In the ordinary cases
    /// -- the tunnel has never run on this install, the extension's own
    /// profile lacks the group, the extension's own SetLogDirForProcess fell
    /// back -- the container resolves for the app and `logs/extension/` simply
    /// does not exist, and the bundle used to ship with nothing anywhere
    /// saying so. Support then reads that as "the extension had no logs".
    /// Spec goal 5: an unreachable source is recorded as missing.
    static func missingExtensionReason(
        sharedRootUnavailableReason: String?,
        inventorySources: Set<String>
    ) -> String? {
        if let sharedRootUnavailableReason {
            return sharedRootUnavailableReason
        }
        if inventorySources.contains(DiagnosticsLogLocation.extensionProcessName) {
            return nil
        }
        return "no logs from the extension process in the shared log root"
            + " -- the tunnel has not run on this install, or the extension could not write there"
    }

    /// Sub-KiB files render as "<1 KiB" rather than "0 KiB", which reads as
    /// empty for a file that has just rotated.
    static func sizeLabel(_ byteCount: Int64) -> String {
        if 0 < byteCount && byteCount < 1024 {
            return "<1 KiB"
        }
        return "\(byteCount / 1024) KiB"
    }

    /// A picker row: source, severity, size and modified time, as the spec's
    /// UI section requires. The time is what tells the user which file is the
    /// live one and which is a rotation from last week, and it is UTC for the
    /// same reason the bundle name is -- a support thread compares stamps from
    /// devices in several timezones.
    static func rowLabel(
        source: String, severity: String, byteCount: Int64, modifiedMillis: Int64 = 0
    ) -> String {
        let label = "\(source) · \(severity) · \(sizeLabel(byteCount))"
        guard 0 < modifiedMillis else { return label }
        return "\(label) · \(modifiedLabel(modifiedMillis))"
    }

    static func modifiedLabel(_ modifiedMillis: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date(timeIntervalSince1970: Double(modifiedMillis) / 1000))
    }

    /// What the export would contain, shown before the user commits to it.
    /// The spec's UI section requires the total size up front: a bundle is up
    /// to 4x16MB per process, which is not a thing to discover afterwards.
    static func inventoryLabel(fileCount: Int, byteCount: Int64) -> String {
        if fileCount == 0 {
            return "No log files on disk"
        }
        return "\(fileCount) log file\(fileCount == 1 ? "" : "s") on disk · \(sizeLabel(byteCount))"
    }

    /// "Export selected" must never silently fall back to exporting every
    /// log: underneath, `SdkExportOptions.selectedNames` empty means "no
    /// filter" to the SDK ("Empty means every file", per its header
    /// comment), the same as the raw "Export all logs" action. So the picker
    /// action is a no-op until at least one row is checked -- not a smaller
    /// version of "export all".
    static func canExportSelection(_ selectedNames: Set<String>) -> Bool {
        !selectedNames.isEmpty
    }

    static func inventory() -> [SdkLogFileInfo] {
        guard let list = SdkLogInventory() else { return [] }
        var infos: [SdkLogFileInfo] = []
        infos.reserveCapacity(list.len())
        for i in 0..<list.len() {
            if let info = list.get(i) {
                infos.append(info)
            }
        }
        return infos
    }

    static func sources(of inventory: [SdkLogFileInfo]) -> Set<String> {
        Set(inventory.map { $0.source })
    }

    static func totalByteCount(of inventory: [SdkLogFileInfo]) -> Int64 {
        inventory.reduce(Int64(0)) { $0 + $1.byteCount }
    }
}

extension SdkLogFileInfo {
    /// Identity for a picker row.
    ///
    /// `name` alone is what the SDK's own selection filter matches on, and its
    /// doc comment calls it unique within an export -- but nothing enforces
    /// that across the per-process directories, and two rows with the same
    /// SwiftUI id is a diffing hazard rather than a cosmetic one. Source plus
    /// name is unique by construction, since a source IS a directory.
    var pickerRowId: String { "\(source)/\(name)" }
}
