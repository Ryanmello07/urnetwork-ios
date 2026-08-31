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

    static func bundleFileName(date: Date, redacted: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let suffix = redacted ? "-redacted" : ""
        return "urnetwork-diagnostics-\(formatter.string(from: date))\(suffix).zip"
    }

    /// Writes a bundle into the temporary directory and returns it.
    ///
    /// `isShared` false means this build could not reach the App Group
    /// container, so the extension's logs are not present -- recorded in the
    /// bundle rather than treated as a failure.
    /// The written bundle and a one-line summary of what it contains, including
    /// any source that could not be read.
    struct Export {
        let url: URL
        let summary: String
    }

    static func export(
        redacted: Bool,
        selectedNames: [String],
        device: SdkDeviceRemote?,
        isShared: Bool,
        date: Date = Date()
    ) throws -> Export {
        let destination = FileManager.default.temporaryDirectory
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
        if !isShared {
            options.missingSourceReason(
                DiagnosticsLogLocation.extensionProcessName,
                reason: "app group container unavailable in this build"
            )
        }

        var err: NSError?
        let result = SdkExportDiagnosticBundle(destination.path, options, &err)
        if let err {
            throw err
        }

        var summary = ""
        if let result {
            summary = "Exported \(result.fileCount) log files (\(result.byteCount / 1024) KiB)"
            if let missing = result.missingSources {
                for i in 0..<missing.len() {
                    summary += "\nNot included: \(missing.get(i))"
                }
            }
        }
        return Export(url: destination, summary: summary)
    }

    static func rowLabel(source: String, severity: String, byteCount: Int64) -> String {
        "\(source) · \(severity) · \(byteCount / 1024) KiB"
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
}
