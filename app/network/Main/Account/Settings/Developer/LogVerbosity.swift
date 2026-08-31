//
//  LogVerbosity.swift
//  URnetwork
//
//  What each glog verbosity level buys, and what it costs.
//
//  The `connect` package gates most of what it has to say behind V(1) and
//  V(2) -- contract accounting, transport internals, window diagnostics -- and
//  every process starts at 0, where none of it is written. A bundle exported
//  from a live session therefore contains the rpc chatter and nothing about
//  the contracts or the transport, which is the part a connection report needs.
//  This is the vocabulary for the control that raises it.
//
//  Pure so it can be tested without a device: the level-to-label mapping and
//  the clamp are the whole of the logic, and both are load-bearing -- one
//  names what the user is turning on, the other keeps an out-of-range value
//  from indexing past the labels.
//

import Foundation

enum LogVerbosity {

    /// The range the SDK honors. `connect` only ever asks for V(1) and V(2),
    /// so anything above 2 is volume with nothing to show for it, and the SDK
    /// clamps to this range on its own -- mirrored here so the control never
    /// offers a level that would come back changed.
    static let minimum = 0
    static let maximum = 2

    static var range: ClosedRange<Int> { minimum...maximum }

    static func clamp(_ level: Int) -> Int {
        min(max(level, minimum), maximum)
    }

    /**
     * The user-facing name of a level.
     *
     * NOTE these are NOT the SDK's constant names. `SdkLogVerbosityTrace` is
     * 1 and `SdkLogVerbosityDetail` is 2; here 1 is "Verbose" and 2 is
     * "Trace", because "detail" says nothing about the volume and "trace" is
     * what a user expects the loudest setting to be called. Read the number,
     * not the word, when comparing against the SDK.
     */
    static func name(_ level: Int) -> String {
        switch clamp(level) {
        case minimum: return "Default"
        case 1: return "Verbose"
        default: return "Trace"
        }
    }

    /**
     * What that level actually buys, and what it costs -- named concretely
     * rather than as "more logging", so the choice can be made before the
     * reproduction rather than discovered in the bundle afterwards.
     */
    static func detail(_ level: Int) -> String {
        switch clamp(level) {
        case minimum:
            return "Connection errors and contract pings."
        case 1:
            return "Contract accounting and per-packet block decisions."
                + " Includes destination IP addresses."
        default:
            return "Transport and window internals. Very large logs."
        }
    }

    /// Number and name together: the number is what the SDK reports and what
    /// a support thread can compare, the name is what the row means.
    static func valueLabel(_ level: Int) -> String {
        "\(level) · \(name(level))"
    }

    /**
     * Whether logs written at this level carry the destinations of real
     * traffic. True from V(1) up: that is where the per-packet block
     * decisions and the contract accounting start naming addresses.
     *
     * Written against the level rather than a stored flag so a level restored
     * from a previous run, or one an embedder set some other way, warns the
     * same as one just chosen here.
     */
    static func revealsDestinations(_ level: Int) -> Bool {
        minimum < level
    }

    /// Shown for as long as the level is raised, not once when it is changed:
    /// the user raises it, reproduces for an hour, and exports -- and by then
    /// a toast is long gone.
    static let destinationWarning =
        "Logs now record the destination addresses and ports of your real traffic."
        + " Send the redacted export, not the raw one."
}
