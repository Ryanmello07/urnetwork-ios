//
//  HostFormatUtils.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/9/26.
//

import Foundation
import Network
import URnetworkSdk

/**
 * Compact rendering for a cluster's host values.
 *
 * Host names with more than 10 entries collapse to their base names
 * ("*.<base>"). The base names and ips form one combined list; when it
 * has more than 20 entries, at most 21 are shown as the first, middle,
 * and last 7 in alphanumeric order with the omitted count.
 */
func formatHostClusterText(hosts: [String], ips: [String]) -> String {

    // host names collapse to base names when there are more than 10
    var displayHosts = hosts
    if hosts.count > 10 {
        var seen = Set<String>()
        var collapsed: [String] = []
        for host in hosts {
            let display = "*.\(hostBaseName(host))"
            if seen.insert(display).inserted {
                collapsed.append(display)
            }
        }
        displayHosts = collapsed
    }

    let items = displayHosts + ips
    if items.isEmpty {
        return String(localized: "unknown")
    }

    return compactValueList(items)
}

/**
 * Shows all values when there are 20 or fewer, else the first, middle,
 * and last 7 in alphanumeric order (21 max) with the omitted count
 */
private func compactValueList(_ values: [String]) -> String {

    if values.count <= 20 {
        return values.joined(separator: ", ")
    }

    let sorted = values.sorted()
    let n = sorted.count
    let middleStart = (n - 7) / 2
    let first = sorted[0..<7]
    let middle = sorted[middleStart..<(middleStart + 7)]
    let last = sorted[(n - 7)..<n]
    let omitted = n - 21

    var text = first.joined(separator: ", ")
        + ", …, " + middle.joined(separator: ", ")
        + ", …, " + last.joined(separator: ", ")
    if 0 < omitted {
        // plural rules live in Localizable.xcstrings ("+ %lld more")
        text += " " + String(localized: "+ \(omitted) more")
    }
    return text
}

/**
 * The base name of a host: one label plus the public suffix
 * ("cdn.a.example.com" -> "example.com",
 * "cdn.a.example.co.uk" -> "example.co.uk").
 * Uses the sdk's public-suffix-aware implementation, shared
 * across platforms.
 */
func hostBaseName(_ host: String) -> String {
    return SdkHostBaseName(host)
}

/**
 * Whether the value parses as an ipv4 or ipv6 address
 */
func isIpAddressValue(_ value: String) -> Bool {
    return IPv4Address(value) != nil || IPv6Address(value) != nil
}
