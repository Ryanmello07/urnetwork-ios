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
        // Strip a trailing :port when it looks like an IPv4 host:port or a
        // bracketed IPv6 literal like [2001:db8::1]:8080. A bare IPv6
        // address (no brackets) must not be mangled — there is no
        // reliable way to distinguish its colons from a port separator.
        if let portRange = value.range(of: "]:", options: .backwards) {
            // IPv6 literal with port: "[...]:port" — strip the port but keep brackets
            value = String(value[..<portRange.lowerBound]) + "]"
        } else if !value.contains("[") && !value.contains(":") {
            // Plain hostname — no colon, nothing to strip
        } else if let colonRange = value.range(of: ":", options: .backwards),
                  !value.contains("[") {
            // IPv4 host:port — strip after the last colon
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
