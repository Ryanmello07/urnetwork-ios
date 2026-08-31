//
//  DiagnosticExportServiceTests.swift
//  networkTests
//
//  Covers the exported bundle's file name: sortable, and honest about whether
//  it was redacted, so a redacted bundle is never mistaken for a complete one.
//

import Testing
import Foundation
@testable import URnetwork

struct DiagnosticExportServiceTests {

    @Test func bundleNameIsSortableAndCarriesTheMode() {
        let date = Date(timeIntervalSince1970: 1767225600)
        let raw = DiagnosticExportService.bundleFileName(date: date, redacted: false)
        let redacted = DiagnosticExportService.bundleFileName(date: date, redacted: true)

        #expect(raw.hasSuffix(".zip"))
        #expect(redacted.contains("redacted"))
        #expect(!raw.contains("redacted"))

        let earlier = DiagnosticExportService.bundleFileName(
            date: Date(timeIntervalSince1970: 1767225500), redacted: false)
        #expect(earlier < raw)
    }

    @Test func rowLabelNamesTheSourceSeverityAndSize() {
        let label = DiagnosticExportService.rowLabel(source: "extension", severity: "ERROR", byteCount: 2048)
        #expect(label.contains("extension"))
        #expect(label.contains("ERROR"))
        #expect(label.contains("2 KiB"))
    }
}
