//
//  LogVerbosityTests.swift
//  networkTests
//
//  Covers the vocabulary of the log-detail control: what each level is called,
//  what it promises, which levels put the destinations of real traffic into
//  the logs, and that an out-of-range level can neither be offered nor crash
//  the mapping.
//

import Testing
import Foundation
@testable import URnetwork

struct LogVerbosityTests {

    @Test func levelsAreNamedForWhatTheyBuy() {
        #expect(LogVerbosity.name(0) == "Default")
        #expect(LogVerbosity.name(1) == "Verbose")
        #expect(LogVerbosity.name(2) == "Trace")

        // the detail line has to name what is gained, not just say "more" --
        // it is what the choice is made on, before the reproduction
        #expect(LogVerbosity.detail(0).contains("contract pings"))
        #expect(LogVerbosity.detail(1).contains("Contract accounting"))
        #expect(LogVerbosity.detail(1).contains("block decisions"))
        #expect(LogVerbosity.detail(2).contains("Transport and window internals"))

        // ... and what it costs
        #expect(LogVerbosity.detail(1).contains("destination IP addresses"))
        #expect(LogVerbosity.detail(2).contains("Very large logs"))
    }

    /// The number is what the SDK reports and what a support thread compares;
    /// the name is what the row means. Both are shown.
    @Test func theValueLabelReportsTheLevelTheDeviceGave() {
        #expect(LogVerbosity.valueLabel(0) == "0 · Default")
        #expect(LogVerbosity.valueLabel(1) == "1 · Verbose")
        #expect(LogVerbosity.valueLabel(2) == "2 · Trace")

        // a level an embedder set past the range is reported as the number it
        // actually is, rather than being quietly redrawn as 2 -- the control
        // is the only place the discrepancy could show
        #expect(LogVerbosity.valueLabel(7) == "7 · Trace")
    }

    /**
     * The clamp is what keeps an out-of-range level from indexing past the
     * labels, and it mirrors the SDK's own clamp so the control never offers
     * a level that would come back changed.
     */
    @Test func levelsClampToWhatTheSdkHonors() {
        #expect(LogVerbosity.clamp(0) == 0)
        #expect(LogVerbosity.clamp(1) == 1)
        #expect(LogVerbosity.clamp(2) == 2)

        #expect(LogVerbosity.clamp(3) == 2)
        #expect(LogVerbosity.clamp(Int.max) == 2)
        #expect(LogVerbosity.clamp(-1) == 0)
        #expect(LogVerbosity.clamp(Int.min) == 0)

        // out of range must still map to a label rather than trapping
        #expect(LogVerbosity.name(-1) == "Default")
        #expect(LogVerbosity.name(9) == "Trace")

        #expect(LogVerbosity.range == 0...2)
    }

    /**
     * The privacy line. V(1) is where the per-packet block decisions and the
     * contract accounting start naming addresses, so the warning has to
     * appear at 1 -- not only at the loudest level.
     */
    @Test func raisedLevelsAreMarkedAsRevealingDestinations() {
        #expect(LogVerbosity.revealsDestinations(0) == false)
        #expect(LogVerbosity.revealsDestinations(1) == true)
        #expect(LogVerbosity.revealsDestinations(2) == true)

        // a nonsensical negative level is not a reason to warn
        #expect(LogVerbosity.revealsDestinations(-1) == false)
    }

    /// The warning has to say what is in the logs AND what to do about it:
    /// the redacted export is the whole reason a raised level is still safe
    /// to share from.
    @Test func theWarningNamesBothTheExposureAndTheWayOut() {
        let warning = LogVerbosity.destinationWarning
        #expect(warning.contains("destination addresses"))
        #expect(warning.contains("ports"))
        #expect(warning.contains("redacted"))
    }
}
