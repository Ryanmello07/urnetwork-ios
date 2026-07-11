//
//  NetworkServerUtils.swift
//  URnetwork
//
//  Swift port of Android's `NetworkServerSelector.kt` normalization helpers,
//  used by `NetworkServerSheet` to validate/derive urls for a custom network
//  server. Kept as free functions so they're trivially testable and shared
//  between iOS and macOS.
//

import Foundation

enum NetworkServerUtils {

    static func normalizeNetworkHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = value.range(of: "://") {
            value = String(value[range.upperBound...])
        }
        for separator in ["/", "?", "#"] {
            if let range = value.range(of: separator) {
                value = String(value[..<range.lowerBound])
            }
        }
        if let atRange = value.range(of: "@") {
            value = String(value[atRange.upperBound...])
        }
        // Strip a trailing :port - the network domain field is a bare host
        // used to derive api.<host>/connect.<host>; a custom port belongs in
        // the explicit API/connect URL overrides, not baked into the derived
        // subdomain (which would otherwise produce invalid hosts like
        // "api.192.168.1.5:8080").
        if let colonRange = value.range(of: ":", options: .backwards) {
            value = String(value[..<colonRange.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func explicitScheme(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = value.range(of: "://") else {
            return nil
        }
        let scheme = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return scheme.isEmpty ? nil : scheme
    }

    static func normalizeApiUrl(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.isEmpty {
            return ""
        }
        if value.contains("://") {
            return value
        }
        return "https://\(value)"
    }

    static func normalizeConnectUrl(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.isEmpty {
            return ""
        }
        if value.contains("://") {
            return value
        }
        return "wss://\(value)"
    }

    static func hasInsecureScheme(_ raw: String, secureScheme: String) -> Bool {
        guard let scheme = explicitScheme(raw) else {
            return false
        }
        return scheme != secureScheme
    }

    /// Mirrors the SDK's own `ServiceUrl` derivation (host/env -> api./connect.
    /// subdomains), so the sheet can show an accurate placeholder/preview
    /// before the user applies anything.
    static func derivedServiceUrl(
        hostName: String,
        migrationHostName: String,
        envName: String,
        scheme: String,
        service: String
    ) -> String {
        let serviceHost = migrationHostName.isEmpty ? hostName : migrationHostName
        let serviceHostName = (envName == "main" || envName.isEmpty)
            ? "\(service).\(serviceHost)"
            : "\(envName)-\(service).\(serviceHost)"
        return "\(scheme)://\(serviceHostName)"
    }
}
