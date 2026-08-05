# iOS reliability port — plan

2026-08-04. Ports the Android reliability release (the checkpoint PR stack:
urnetwork/connect#190, urnetwork/sdk#134, urnetwork/android#468) to iOS/macOS.
connect and sdk are shared with Android, so the Go reliability stack — the
flows-are-sacred verdict layer, prober, churn compensation, site affinity,
`[rel]` observability — is already in the app the moment the xcframework is
rebuilt. What iOS lacks is (a) an RPC bridge for the reliability surface and
(b) all of the UI.

## The one architecture fact that shapes everything

On Android, `MainService` runs the sdk device **in the app process**: the
developer screen calls `DeviceLocal` methods directly. On iOS the device runs
in the **packet tunnel extension** (`app/extension/PacketTunnelProvider.swift`
holds `SdkDeviceLocal`), and the app process holds `SdkDeviceRemote`
(`app/network/Shared/ViewModels/DeviceManager.swift`), an RPC client that
talks to the extension over `DeviceLocalRpc` (gob payloads, `sdk/device_rpc.go`,
~179 bridged methods today).

**None of the reliability surface is bridged.** `grep -E
'func \(self \*DeviceRemote\)' sdk/device_rpc.go` matches zero of:
reliability settings/metrics, exits readout, migrate/probe actions,
destination exits. Every UI work package therefore depends on WP1 (the
bridge), and WP1's API contract is FROZEN in this document so UI agents can
build against it in parallel before WP1 lands.

## Scope

**In:** developer screen (reliability controls, per-exit rows, actions,
metrics panel), destination→exit attribution in the stats/contract views,
site-rule pinning (EXCLUDED / PINNED / INCLUDED for sites), log-friendly
`[rel]` observability (free — extension logs already export via
`Shared/Views/ExportLogsButton`), build branch + CI for a testable IPA.

**Out (and why):**
- **App pinning / per-app split tunneling.** iOS has no
  `getConnectionOwnerUid` equivalent for app-scoped flow attribution, and
  per-app VPN is MDM/supervised-device machinery. `FlowOwnerLookup` stays
  un-bridged; the `app:` affinity-group path stays dormant on iOS. SITE
  pinning does not need any of that (route overrides are Go-side state) and
  IS in scope.
- Anything Android-platform-specific (package broadcasts, VpnService.Builder
  membership logic).

## Base and branches

- iOS repo `Ryanmello07/urnetwork-ios` (upstream `urnetwork/apple`).
- PR branch: `feat/reliability-checkpoint-upstream` cut from `upstream/main`
  (9cf8d5b), matching the checkpoint stack convention. The iOS PR joins the
  stack as its 4th member; merge order connect → sdk → apple.
- sdk bridge work (WP1) lands on the EXISTING sdk checkpoint branch
  (`Ryanmello07/urnetwork-sdk` `feat/reliability-checkpoint-upstream`) so
  sdk#134 carries it; cgo artifacts regenerated (`cd cgo && go run ./gen`).
- Build-only branch: `build/checkpoint-live-test` on the ios repo (this
  document lives there; it is never part of the PR), with
  `.github/workflows/beta-build.yml` pointed at the checkpoint branches of
  connect and sdk — mirror the android build branch changes, including the
  goidenticons `RenderPngV2` echo-shim. Runner is `macos-latest`; output is
  an unsigned IPA artifact.

## Verification constraints (read before writing code)

- **No Swift compiles locally** — the dev host is Windows. Swift work is
  verified by pushing to the build branch and letting the macOS CI compile
  (`xcodebuild archive -scheme URnetwork`). Budget for compile-fix
  round-trips through CI; keep Swift changes in small pushable increments.
- Go work verifies locally: connect/sdk build + `go vet` + sdk `cgo` build.
  The sdk test binary does not build on Windows (pre-existing Unix-only test
  file); rpc tests run in sdk CI on Linux.
- The connect suite is NOT touched by this work; do not run its 8-minute
  splits unless connect files change (they should not).
- Kotlin sources in `claude_sandbox_android` are the porting REFERENCE ONLY.

## WP1 — sdk: bridge the reliability surface over DeviceLocalRpc

**Repo:** `C:\Users\ryanm\Downloads\claude_sandbox_dashboard\sdk`, branch
`feat/reliability-checkpoint-upstream`. Reference implementations:
`device_local.go` (the DeviceLocal reliability methods), `device_rpc.go`
(bridge patterns — copy the shape of an existing get/set pair such as
`GetBlockActions` / the DnsSettings methods, including their
`DeviceRemote*Rpc` gob payload types and `rpcCallNoArg`/`rpcCall` plumbing,
sync-state re-apply on reconnect, and the local-fallback-when-unbridged
convention used by offline getters).

**Bridge exactly this contract (names are frozen; UI codes against them):**

| DeviceRemote method | semantics |
| --- | --- |
| `GetReliabilitySettings() *ReliabilitySettings` | effective config from the extension device. **AMENDED: returns nil when nothing is in force** (no multi client / no rpc service). The original zeros-degradation manufactured the plan's own zero-value-off trap on iOS, where `DeviceRemote` exists from login and outlives every tunnel session — unlike android, where `device` IS the `DeviceLocal` and is nil unless connected, which is the only reason android never hit it. Settings only; metrics and the two lists still degrade to zeros/empty, which are honest answers and avoid a nil crossing gomobile. |
| `SetReliabilitySettings(*ReliabilitySettings)` | runtime override, no reconnect |
| `ResetReliabilitySettings()` | clear override |
| `GetReliabilityMetrics() *ReliabilityMetrics` | counters snapshot |
| `ResetReliabilityMetrics()` | zero counters |
| `GetExits() *ExitList` | per-exit readout rows (id, tier, effective tier, flows, proven, quarantined, warning, warning cause, age) |
| `MigrateExit(exitClientId string)` | drain-style hand-off of one exit |
| ~~`ProbeExit(exitClientId string)`~~ | **DROPPED (contract error).** No per-exit probe seam exists in connect — only `ProbeAllExits`; the per-client pass, the window client enumeration, and the qualification table are all unexported. The android screen has no per-row probe either, so parity never needed it, and widening the connect API inside a PR already under upstream review is not worth one dev-screen button. The iOS per-row Probe button was removed (ios `0cc4d25`); `MigrateExit` is the only per-row action. |
| `ProbeAllExits()` | full sweep |
| `SimulateNetworkChange()` | the dev action |
| `GetDestinationExits() *DestinationExitList` | destination→exit attribution rows |

Rules:
- Gob payload structs use the `DeviceRemote<Name>Rpc` naming; the cgo export
  validator already allowlists `[A-Za-z]Rpc`.
- `SetReliabilitySettings` must participate in the remote **sync state**
  (re-applied when the extension restarts / rpc reconnects), the same way the
  existing setters do — a dev override that silently vanishes on extension
  restart is the "mechanism with no field-observable signal" failure class.
- Settings structs are already gomobile-safe (int64 millis, int32) — do not
  redesign them; wrap for gob only where gob requires it.
- Site-pin rules: verify the EXISTING block-action override bridge passes the
  `Pin` route override mode end to end (`RouteOverride` values cross in
  `device_rpc.go` today because BlockActionsStore works on iOS). If the mode
  enum is filtered anywhere in the bridge, widen it; otherwise this is a
  verification note in the WP report, not code.
- Regenerate cgo (`go run ./gen`) and commit artifacts.
- Tests: extend the existing device_rpc test pattern with round-trip tests
  for settings (set→get across the bridge), metrics, exits (empty +
  populated), and one action (assert the DeviceLocal side was invoked).
  Windows cannot run them; mark clearly in the WP report that CI must.

**Acceptance:** sdk builds + vets on Windows; cgo regenerates clean; new
tests compile (build-tag-free); sdk#134 diff shows only bridge + artifacts.

## WP2 — iOS: developer screen

**Repo:** ios, PR branch. Reference: android
`ui/settings/DeveloperScreen.kt` + `DeveloperViewModel.kt` (sections:
Detection / Placement / Recovery / Probing / Observability; per-exit rows
tier/flows/warning-cause/"benched"; row actions probe + migrate; global
actions ProbeAllExits + SimulateNetworkChange; metrics panel: blast radius,
recovery, never-came-back, held verdicts, probes, removals; settings shown as
live controls writing runtime overrides).

Build:
- `Shared/ViewModels/ReliabilityStore.swift` following the
  `DnsSettingsStore` / `BlockActionsStore` conventions (ObservableObject,
  polls `DeviceManager.device` — 5s while visible; all DeviceRemote calls off
  the main thread; nil-device tolerant).
- `Main/Account/Settings/Developer/DeveloperView.swift` (+ iOS/macOS form
  variants ONLY if the surrounding Settings screens split that way — follow
  `SettingsForm-iOS.swift` / `SettingsForm-macOS.swift` precedent).
- Entry point: a Developer row in `SettingsView.swift`, placed like the
  existing rows around it (follow the DePinHub row precedent for a
  conditional row). Keep it visible (the android dev screen ships visible in
  beta builds).
- Numeric settings edit as text fields with millis/int semantics identical to
  the android dev menu; toggles for the bool knobs; every mutation calls
  `SetReliabilitySettings` with the FULL struct (read-modify-write from the
  latest `GetReliabilitySettings` — never from a stale cached struct: the
  zero-value-off trap).
- Exit rows must render `WarningCause` verbatim (new causes such as "silent"
  must appear without an app update).

**Acceptance:** compiles in CI for iOS AND macOS destinations; screen renders
with the tunnel down (all-nil path) and up; every control round-trips
(toggle → re-read shows the new effective value).

## WP3 — iOS: exit attribution + site pin rules

**Repo:** ios, PR branch. References: android `ui/stats/BlockActionsViewModel.kt`
(the `exitsByIp` join + 5s re-poll + open/close job lifecycle) and
`ui/stats/SplitRulesScreen.kt` / `AppSplitRulesScreen.kt` (rule modes).

- In `Shared/ViewModels/BlockActionsStore.swift`: join
  `GetDestinationExits()` onto each block-action row's ips → `exits:
  [String]` per row; refresh on the store's existing update path plus a 5s
  tick while the view is visible; cancel the tick when not.
- In `Shared/Views/Stats/` (`ContractDetailsView.swift` or the block-action
  row view it hosts): render "via <exit-prefix>" chips; two chips on one row
  is the split-egress observation, styled distinctly.
- `SplitRulesView.swift`: extend the site-rule editor to three states —
  EXCLUDED / PINNED / INCLUDED — writing the same `RouteOverride` values the
  android dialog writes (Pin for sites only; no app rules on iOS). Handle the
  read side rendering pre-existing Pin rules.

**Acceptance:** compiles both destinations; rows show chips within ~5s of a
flow moving.

**AMENDED — what a site pin actually does, and its live-test signal.** The
original acceptance criterion ("`[rel] event=pin_lookup`-class placement
behavior") was wrong twice over. `pin_lookup` is emitted only by
`SetFlowOwnerLookup`, the per-app wiring iOS deliberately does not bridge —
so that line can never appear on iOS. And more importantly, `RouteOverride.Pin`
means two different things by rule type: for an APP rule every flow the app
owns joins one app-scoped affinity group (one egress ip for the whole app —
the DoorDash fix); for a HOST rule the flows keep their ordinary domain
grouping and gain only a longer tolerance for a quarantined exit. In connect,
only `pin.appId != ""` replaces the affinity paths
(`ip_remote_multi_client.go:2970-2971, 3124-3125`); `site: true` merely makes
`pinned()` true, which widens the follow window via `pinnedFollowWindow`. So
**iOS site pinning buys fewer mid-session exit changes for that site, NOT a
shared egress ip across its subdomains** — multi-subdomain consolidation comes
from the CDN-constellation alias table, which works everywhere. The app copy
was corrected to say this (ios `7a9fcc8`). Live-test signal: a pinned site's
flows stay on their exit across a quarantine episode that would otherwise
re-race them — observable as `event=quarantine` on an exit that keeps
carrying that site's flows, not as a new log line.

## WP4 — build branch + CI for a testable IPA

**Repo:** ios, `build/checkpoint-live-test` branch (already cut). Mirror the
android build-branch changes onto the ios workflow copied from
`origin/beta/custom-server:.github/workflows/beta-build.yml`:
- sdk checkout ref + connect clone branch → `feat/reliability-checkpoint-upstream`.
- goidenticons clone + the two-line `RenderPngV2` echo shim (upstream sdk
  references it; the published goidenticons lacks it).
- No NDK on iOS; do not cargo-cult the android NDK step.
- Confirm the sdk build step invokes the ios/xcframework make target (the
  fork workflow already does; keep its BRINGYOUR_HOME shape — the ios repo
  consumes the framework from where `app.xcodeproj` expects it, NOT the
  android monorepo path; verify against the project file before changing
  anything).
- Merge the PR branch into the build branch whenever WPs land; the IPA
  artifact from `macos-latest` is the live-test deliverable.

**Acceptance:** green run producing `URnetwork-beta.ipa` with WP1-3 content.

## Execution protocol (multi-agent)

- **Order:** WP1 and WP4 start immediately in parallel. WP2 and WP3 start
  immediately as well, coding against the frozen WP1 contract; they merge
  only after WP1's reviewer passes. WP2 and WP3 touch disjoint files except
  `SettingsView.swift` (WP2 only) — no shared-file conflicts by
  construction; BlockActionsStore belongs to WP3 alone.
- **Per-WP reviewer:** each implementation agent's work is reviewed by a
  separate reviewer agent before its commits are accepted onto the PR
  branch. Reviewer charter: correctness against the reference Kotlin (missed
  accounting, inverted flags), the RPC re-apply/sync-state trap (WP1), the
  read-modify-write settings trap (WP2), lifecycle leaks of polling tasks
  (WP2/WP3), and gomobile/gob constraint violations (WP1). Reviewers report
  findings; the implementer fixes; the manager (top-level session) applies
  judgment on disputes.
- **Final pass:** after all WPs merge, one integration review agent walks the
  full ios+sdk diff vs upstream (the android checkpoint-review charter,
  adapted: merge-side inversions n/a, but check for smuggled non-reliability
  changes, dropped upstream code, api-contract drift between WP1 and WP2/3),
  then one auditor agent verifies process: every plan item shipped or
  explicitly descoped, every reviewer finding closed, CI green, PR bodies
  accurate.
- **Manager cross-checks** (the top-level session): WP1 contract compliance
  before WP2/3 merge, no plan/doc files on the PR branch, android parity
  spot-checks against the reference screens, final live-test IPA handoff.

## Known risks

- **CI-only Swift verification** is the schedule risk: each WP2/WP3 compile
  error costs a CI round trip (~15 min). Mitigation: reviewers lint Swift by
  eye against neighboring files' idioms before any push; batch pushes.
- The `DeviceRemote` sync-state machinery is subtle (reconnect re-apply,
  service generation); WP1's reviewer must trace one existing setter's full
  lifecycle and diff the new ones against it line by line.
- macOS target: the app builds for macOS too (`mac0S/` sources, menu-bar
  assets). Every new view must compile under both; forms split per platform
  only where the neighbors do.
- The extension process restarts independently of the app; every store must
  tolerate `device == nil` and a fresh device object identity mid-flight.
