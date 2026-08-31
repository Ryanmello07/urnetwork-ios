//
//  DiagnosticsLogLocationTests.swift
//  networkTests
//
//  Covers where each process writes its logs. The app and the extension are
//  separate processes with separate containers; only an App Group lets the app
//  read what the extension wrote. When the container is unavailable -- a build
//  whose provisioning profile predates the group -- each process must fall
//  back to its own directory rather than failing, so an export still produces
//  the logs it can reach.
//

import Testing
import Foundation
@testable import URnetwork

struct DiagnosticsLogLocationTests {

    @Test func fallsBackToALocalRootWhenTheContainerIsUnavailable() {
        let location = DiagnosticsLogLocation.logRoot(
            containerURL: nil,
            fallbackURL: URL(fileURLWithPath: "/tmp/urnetwork-test")
        )
        #expect(location.isShared == false)
        #expect(location.url.path == "/tmp/urnetwork-test/Logs")
    }

    @Test func usesTheSharedContainerWhenAvailable() {
        let location = DiagnosticsLogLocation.logRoot(
            containerURL: URL(fileURLWithPath: "/private/group/network.ur"),
            fallbackURL: URL(fileURLWithPath: "/tmp/urnetwork-test")
        )
        #expect(location.isShared == true)
        #expect(location.url.path == "/private/group/network.ur/Logs")
    }

    @Test func processNamesAreDistinctSoRetentionDoesNotCollide() {
        #expect(DiagnosticsLogLocation.appProcessName != DiagnosticsLogLocation.extensionProcessName)
    }
}
