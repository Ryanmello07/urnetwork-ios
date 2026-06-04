//
//  ByteFormatUtils.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 7/5/25.
//

import Foundation

func formatMiB(mib: Float) -> String {

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2

    let pib: Float = 1024 * 1024 * 1024
    let tib: Float = 1024 * 1024
    let gib: Float = 1024

    if mib >= pib {
        let pib = mib / pib
        let formatted =
            formatter.string(from: NSNumber(value: pib)) ?? String(format: "%.2f", pib)
        return "\(formatted) PiB"
    } else if mib >= tib {
        let tib = mib / tib
        let formatted =
            formatter.string(from: NSNumber(value: tib)) ?? String(format: "%.2f", tib)
        return "\(formatted) TiB"
    } else if mib >= gib {
        let gib = mib / gib
        let formatted =
            formatter.string(from: NSNumber(value: gib)) ?? String(format: "%.2f", gib)
        return "\(formatted) GiB"
    } else {
        let formatted =
            formatter.string(from: NSNumber(value: mib)) ?? String(format: "%.2f", mib)
        return "\(formatted) MiB"
    }
}

private let balanceBytesFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    return formatter
}()

func formatBalanceBytes(_ bytes: Int) -> String {
    let oneTiB = 1024 * 1024 * 1024 * 1024
    let oneGiB = 1024 * 1024 * 1024
    let oneMiB = 1024 * 1024
    let doubleBytes = Double(bytes)
    if bytes >= oneTiB {
        let value = doubleBytes / Double(oneTiB)
        return "\(balanceBytesFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) TiB"
    } else if bytes >= oneGiB {
        let value = doubleBytes / Double(oneGiB)
        return "\(balanceBytesFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) GiB"
    } else {
        let value = doubleBytes / Double(oneMiB)
        return "\(balanceBytesFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) MiB"
    }
}
