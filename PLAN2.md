
In this plan we will add transfer and contract details for client and provider traffic, dns settings, and local routing overrides ("split tunnel"). The SDK has been updated with the necessary interfaces and view controllers.

Design Goals

1. We will have a new transfer statistics component that shows egress and ingress packet counts and byte counts every second over a 60 second window. This will use the contract view controller. The lines will be smooth curves and minimally rendered using our theme green for for bytes and pink for packets. The component will be split with a horizontal line through the center, and packet count and byte count will be on parallel axes with the maximums that fit the window maximums and labeled on the top right. Egress traffic will be on top of the line, and ingress traffic will be under the line, mirrored so the line is the 0 axis. The latest data will be on the right and the data will shift left as time progresses. This is what the contract view controller should make easy.
2. In the connect drawer, there will be three sections under the connect option settings: client statistics, local statistics, and custom dns. Client statistics will have two transfer components, one for remote data, and one for blocked data. The client statistics area will be tappable to open the client contract details view. The local statistics will be tappable to open the override details view. The custom dns will be tappable to open the custom dns settings. Under the local statistics section should be a summary of the number of active override rules that the UI will call split rules ("X split rules"). Under the dns section should be a summary of whether DoH is enabled, whether unencrypted Dns is enabled, whether local DNS is enabled, and whether local DNS fallback is enabled. 
3. On the wallet screen, under the reliability curve, there will be one new section: provider statistics. The provider statistics will be tappable to open the provider contract details view. Provider statistics will have two transfer components, one for local data, and one for blocked data.
4. The contract details views will be a scrollable list that shows one row per client_id. **This design was revised during implementation** — see "Contract details view — revised design" at the end of this document. In short: the two-aggregated-circles-per-peer visualization was replaced with an un-aggregated per-contract view (each peer row is two independent newest-first stacks, send and receive, one circle per contract), plus a closing/eject lifecycle, a rows-update rate limit, and an activity-based resort. The original one-line goal below is kept for history.
   - _(original goal)_ Under each client ID should be a visualization where there are two circles representing the client and the companion with transfer lines between them. The client circle represents the client contract total transfer (with the total contract size shown) and it should have an inner circle that grows as the contract is used.
5. The split rules view should show a list of block actions and update as new block actions come in. Pinned at the top of the list should be the overrides, which show the host names and ips that are forced to be local. Tapping on a block action should open a create override view that allows selecting one or more of the host values (host name, or ip address) to add as a local exception, and a create. The pinned overrides should be able to swipe and remove in the list. Additionaly the block actions should show the block and local state, and highlight the block and local state if there was an override. Tapping the row when there is an override should open an edit override view for the matching override, and the button should be called update.
6. The DNS settings editor should show the current settings and allow changing them. There should be an update button.
7. In the available providers chooser screen, pinned at the top of the list should be a section of network peers. This should update in real time and show the peers that are connected with provide enabled. The device name should be shown as a detail label, and the device spec should be used if the name is not available.
8. Under settings the current device name and spec should be shown. The device name should be editable.

9. [ANDROID ONLY] On Android we can do split rules with app ids first and then the normal overrides second. We want to add a label above the local packet stats that says "X apps excluded" or "X apps included". If there are inclusions, they take precendent over exclusions. It's either inclusions or exclusions, not both. Tapping the "X apps excluded/included" should open the app split rules. The app split rules should load all the apps installed on the system. Local override apps should be pinned to the top with a state either included or excluded. Swipe the pinned app to reveal a remove button to remove it. Tapping an app should open a dialog that asks either to exclude or include the app, and create. Tapping a pinned app should open the dialog with the value pre-populatd and have an update option. When the android tunnel is created, if there are included apps, set those in the builder. If there are excluded apps, set those in the builder. When the excluded and included app ids change, update the tunnel to reset the settings.


Implementation Details

1. The view controllers should immediately support the UI and components. Make improvements to the view controller to simplify the usage and interfaces as needed.
2. The transfer statistics component should be reusable. Make reusable details components and sub components.
3. Follow the existing theme and style of the application with minimal lines, outlines, and an overall minimal and elegant look.
4. The details views should be real time and update with new data
5. The components should be real time and update with new data


---

# Contract details view — revised design

This supersedes Design Goal 4. The aggregated two-circles-per-peer visualization
was replaced with an **un-aggregated, per-contract** view, because a peer's send
and receive contracts are fundamentally many-to-many (renewals, companion
sessions, parallel contracts) and pairing them into a single client/companion
pair misrepresented what is actually happening. Every contract is now shown as
itself; a renewal is simply one contract leaving and another arriving.

## What the user sees

- A scrollable list, one **row per peer client id** (the full id is shown and is
  tap-to-copy).
- Each row is **two independent stacks**, laid out as four columns mirrored
  around the row center: `send stats | send circles | receive circles | receive stats`.
  Send is green (`urGreen`), receive is pink (`urPink`).
- Each **circle is one contract**. The outer ring is the contract's total size,
  area-proportional to the largest contract in that stack (`max N` label under
  the stack is the scale anchor). The inner disc is the used fraction. A contract
  currently moving bytes brightens its ring. A **stream contract** (its transfer
  path carries a stream id) is drawn as a **double concentric outer ring** — a
  second ring ~2px outside the main one, kept outside the used disc so it stays
  visible even when the contract is full — so streams read distinctly from direct
  contracts.
- Stacks are **newest contract on top** and top-anchored (headers align at the
  top of the row, piles grow downward).
- The direction header shows the direction title, an arrow, and the **summed bit
  rate** for that direction, arranged so the rate always sits over its own
  circle column (send reads `title arrow rate`; receive reads `rate arrow title`).
- Contracts animate in/out (see Closing lifecycle); rows float by activity
  (see Activity resort) when the list is at the top.

## Architecture (shared SDK + thin per-platform view)

The grouping, ordering (**including the at-top activity sort and the scrolled-away
freeze**), closing lifecycle, activity signal, and the pending "N new" count all
live in the **shared SDK**, so every platform renders identical rows. The platform
view only maps rows to native types, **reports its scroll position**, and runs the
animation. It holds no ordering state.

- `sdk/contract_details_view_controller.go`
  - `ContractDetailsViewController` is **single-feed**. The client-traffic and
    provider-traffic lists are two instances of this same controller
    (`OpenClientContractDetailsViewController` / `OpenProviderContractDetailsViewController`)
    — parallel state, identical logic; a `provider bool` picks which device feed it
    subscribes to. It runs **in-app** (created by the `viewControllerManager` with
    the app's `Device`; for `DeviceRemote` the getters are RPC pulls), so its
    `time.Now()` is the **same wall clock the app uses** — important for the
    activity window.
  - It owns the display order. App-facing surface: `GetContractRows()` returns the
    FINAL ordered rows; `SetAtTop(bool)` reports scroll; `PendingCount()` is the
    "N new" count; `AddContractRowsListener` fires on any change.
  - `contractPeerAggregator` — the grouping / newest-first ordering / closing
    lifecycle / activity tracker. `update(egress, ingress, now)` is a pure-ish
    transform producing the base rows.
  - `contractRowOrderer` — the at-top activity partition + scrolled-away freeze +
    pending count, applied on top of the base rows.
  - `ContractEntry{ContractId, UsedByteCount, TotalByteCount, BitRate, HasStream}`
    (`HasStream` = the path carries a non-zero stream id, `connect.TransferPath.IsStream()`).
  - `ContractPeerRow{ClientId, SendContracts, ReceiveContracts (newest first),
    SendBitRate, ReceiveBitRate (sums), LastActivityMillis, Closing}`.
- Bindings: gomobile auto-exports the Go surface to iOS/Android. The **react/js
  binding is hand-written** (`sdk/js/view_controllers.go`, `sdk/js/device_remote.go`)
  and the **C ABI is generated** (`sdk/cgo`, `go run ./gen`) for Windows/Linux —
  both must be updated/regenerated when the surface changes.
- iOS view: `apple/.../ViewModels/ContractDetailsStore.swift` (opens the mode's
  single-feed VC; exposes `rows` + `pendingCount`; forwards `setAtTop`) and
  `apple/.../Views/Stats/ContractDetailsView.swift` (renders `store.rows`, reports
  scroll, shows the chip — no local ordering). This is the reference for the other
  platforms.

## Peer resolution — by direction

Each contract's transfer path has a source and a destination; this device is
always one end. Resolve the **peer** (the other end) by direction:

- **Receive (ingress)** contract → the peer is the **SOURCE** (data flows peer → us).
- **Send (egress)** contract → the peer is the **DESTINATION** (data flows us → peer).

`peerClientIdFromDetails(details, receive)` implements this. Resolving by
direction is deterministic and does **not** need this device's own client id.

- Edge / history: the earlier implementation resolved the peer using this
  device's own id with a direction-blind fallback (always destination). That put
  a peer's send under the peer but its receive under this device, so a peer's
  send and receive landed in **two separate rows**. Direction resolution keeps
  them in one row. Regression: `TestContractPeerAggregatorDirectionPairing` uses
  DIFFERENT local ends for the send vs receive legs (as the provider feed can)
  and asserts they still pair.
- Edge: if the transfer path is missing the needed id, fall back to the contract
  id, then the literal `"unknown"`.

## Ordering & stacks

- Per-direction stacks are **newest contract first**, by a monotonic first-seen
  "arrival" sequence per contract id. Contracts first seen in the same recompute
  are ordered by id for determinism, then stable forever after.
- Peer rows are **newest peer first**, by a first-seen "client order" sequence.
- No cross-direction pairing or byte summing; the only derived per-row numbers
  are the two bit-rate sums for the headers.
- Arrival/order/activity state for a contract or peer is dropped when it is gone
  (ids never reopen), so the maps don't grow unbounded.

## Closing lifecycle (contracts leaving, and the "tetris" animation)

The SDK decides membership; the view animates it.

- A **Closed tombstone** (`Status == ContractStatusClosed`) is NEVER a stack
  entry — it represents a contract leaving. `collect` skips closed/absent/idless
  details.
- **One of many**: when one of a peer's several open contracts closes, it is
  simply dropped from that stack (`TestContractPeerAggregatorCloseOneOfMany`);
  the row stays active because other contracts are open. This drop is the
  departure the view animates.
- **Last contract gone**: a peer that had a row but now has no open contracts
  lingers as a **Closing row** (empty stacks, `Closing = true`) for one
  **eject window** (`contractEjectWindow = 500ms`), then is removed. A contract
  reappearing for that peer before the deadline **cancels** the removal
  (`TestContractPeerAggregatorClosing`).
- View animation (`ContractStackView.sync()`, two phases, `settling` guard):
  1. a leaver **slides off** to `removalEdge` (`.offset`/`.opacity`) while still
     holding its slot open (`slideDuration = 0.4s`);
  2. one **settle** transaction drops the leavers, admits arrivals at the top,
     the stack falls down, and everything rescales to the new stack max
     (`settleDuration = 0.5s`, spring). Value updates (used bytes, bit rate)
     apply live in any phase. `truth`/`displayed` are `@State`, seeded in `init`
     and reconciled in `.onChange(of: entries)`.
- **Edge — nothing to animate if nothing ever closes.** The view can only drop a
  circle when the SDK reports the contract Closed, which only happens when
  `connect` emits `Open=false`. See the next section — a real upstream gap made
  contracts never close on the receive side.

## Upstream dependency: receive contracts must be closed on supersede (connect)

Symptom this design exposed: contracts **accumulated open** in a peer's receive
stack (e.g. three growing circles — 16 KiB fully used, 32 MiB ~80%, 64 MiB
active) and never left.

- Root cause (`connect/transfer.go`): the **send** side closes a drained
  predecessor as soon as it is superseded (`SendSequence.ackItem`:
  `sendContract != itemSendContract && unackedByteCount == 0 → CloseContract`).
  The **receive** side (`ReceiveSequence.setContract`) made the new (larger)
  contract current and registered its stats but **never closed the superseded
  predecessor** — receive contracts only closed on the `> MaxOpenReceiveContract`
  (=4) overflow trim or at sequence end. Under continuous download the sequence
  never ends and the buffer stays ≤ 4, so up to 4 exhausted receive contracts sit
  `Open` forever. The growing sizes are the normal contract-size growth
  (`contractByteCount`: 16 KiB → ~32 MiB → ~64 MiB → … → 128 MiB).
- Fix: on supersede, close the superseded contract's **stats only**
  (`closeContractStats`) — clears the UI immediately — while leaving the contract
  in `openReceiveContracts` for the sender's resend/reorder window (that 4-slot
  buffer is deliberate; an eager wire-level `CloseContract` could reject a late
  packet). The existing overflow trim still does the real wire close later.
  Regression: `TestReceiveContractSupersedeClosesStats` (fails without the fix:
  the predecessor lingers `Open`).
- Edge / known limitation: if a stats-closed contract is genuinely reused by a
  late resend, its resent bytes won't re-appear in stats (rare, cosmetic) — vs.
  the guaranteed 4-contract pile-up before the fix.

## Performance: rows-update rate limit (throttle)

Problem: contract stats change continuously — used bytes and bit rate for every
open contract, every stats epoch (`ContractStatsEpoch`, default 1s in connect) —
and for `DeviceRemote` each `recompute()` does **four** `Get*ContractDetails()`
RPC pulls, then publishes a full row list that re-renders the whole `LazyVStack`.
Change events (egress/ingress/provider legs, per contract) spread across the
epoch are only coalesced within a tight burst, so many contracts ≈ many
recomputes/sec ⇒ RPC + re-render storm ⇒ UI hangs.

- Fix (`ContractDetailsViewController.run()`): **coalesce and rate-limit**
  recomputes to at most once per `RowsUpdateThrottle`. A `dirty` flag records
  pending change events; a `contractDeadlineTick` (100ms) poll flushes them once
  the throttle interval has elapsed. The first paint is immediate
  (`lastRecompute` zero).
- **Rate limit is a setting, not a global const**: `contractDetailsSettings.RowsUpdateThrottle`,
  `defaultContractDetailsSettings()` = **1s**. Rationale: the view animates
  smoothly between updates, so ~1/s looks identical to the user but costs a
  fraction of the CPU/RPC/renders.
- **Edge — closing stays crisp**: a still-pending eject deadline **bypasses** the
  throttle (`|| self.pendingDeadlines()`), so closing rows are serviced on the
  100ms tick and animate out on time. Closes are per-peer and infrequent, so this
  does not defeat the throttle. Idle (no changes, no closing rows) the loop does
  nothing but a cheap tick check.

## Activity resort (float active rows above idle)

Goal: when the list is at the top, rows with recent activity sort **above** idle
rows, re-evaluated at a regular cadence. "Activity" = any contract in the row
moved bytes (positive bit rate) within the **ActivityWindow** (5s). Two rows of
equal activity keep their existing (newest-first) order. **This all lives in the
view controller** — the app only reports scroll and renders the ordered rows.

- SDK signal: the aggregator keeps `lastActivity[peer]` and sets it to `now`
  whenever the row's summed bit rate is positive (any contract moved bytes),
  exposing it as `LastActivityMillis` (absolute unix-millis, 0 if never active).
  Because the VC runs in-app it judges freshness against the same wall clock the
  app uses. Idle peers keep their last-active time; it's pruned when the peer is
  fully removed.
- VC resort (`contractRowOrderer.order`): a **stable partition** of the
  newest-first base rows into `active` (now − lastActivity < ActivityWindow) then
  `idle`, preserving newest-first order within each group. Applied:
  1. on the **ResortCadence** (1s) tick in the VC run loop — so a row ages from
     active to idle on the VC's own clock even with no new contract data (the tick
     re-orders the *cached* base, no RPC recompute);
  2. immediately on an at-top change (`SetAtTop`), and after every data recompute.
  The VC notifies listeners only when the ordered row sequence or the pending count
  actually changed, so a bare resort tick that reorders nothing doesn't churn the UI.
- **Scroll gating:** resort happens **only at the top** (`atTop`). Scrolled away,
  membership and order **freeze** so rows under the reader never shift; newly
  arrived rows collect as `PendingCount`. `atTop` is seeded **true** (a fresh list
  is at the top; also the safe default for an app that never reports scroll — it
  simply never freezes).
- Edge cases:
  - `LastActivityMillis == 0` (never moved bytes) → idle → below active rows, and
    rises the moment bytes flow.
  - **Stability / no flip-flop**: partitioning the *same* newest-first base each
    tick is deterministic — equal-activity rows never swap; a row moves only when
    its activity crosses the window threshold or membership changes.
  - Throttle interaction: `lastActivity` advances at most once per
    `RowsUpdateThrottle` (1s), negligible against the 5s window.
  - Activity is byte movement, not contract open/close: a peer on a full contract
    awaiting renewal reads idle and drops, then rises on the renewal's first bytes.
  - Regressions: `TestContractPeerAggregatorLastActivity` (signal),
    `TestContractRowOrderer{AtTop,FreezeAndPending,FreezeFallback}` (ordering).

## The "N new" chip & frozen membership

- The VC's orderer holds the shown order: at the top `orderedByActivity`; scrolled
  away it is frozen (resolved to current rows, dropping any that closed, falling
  back to the live rows if every frozen row has closed so the list can't get stuck
  empty behind the chip).
- `PendingCount()` = leading run of base rows not yet shown (base is newest-first,
  so new rows are at the front). Tapping the chip reports at-top (`SetAtTop(true)`)
  — the VC merges + re-sorts — and scrolls to top. The app renders `pendingCount`
  and reports scroll; it holds no ordering state of its own.

## Constants / settings summary

| Where | Name | Value | Meaning |
|---|---|---|---|
| SDK (setting) | `RowsUpdateThrottle` | 1s | max rows recompute/publish cadence |
| SDK (setting) | `ActivityWindow` | 5s | active-vs-idle window |
| SDK (setting) | `ResortCadence` | 1s | re-order cadence (ages rows) while at top |
| SDK (const) | `contractEjectWindow` | 500ms | Closing-row linger before removal |
| SDK (const) | `contractDeadlineTick` | 100ms | eject-deadline poll / throttle flush tick |
| connect | `MaxOpenReceiveContract` | 4 | receive-contract resend buffer depth |
| connect | contract growth | 16 KiB → … → 128 MiB | `contractByteCount` lerp |

## Tests

- Aggregator (`sdk/contract_details_view_controller_test.go`): direction pairing,
  un-aggregated stacks + ordering, closing lifecycle, close-one-of-many, and the
  last-activity signal.
- connect (`connect/transfer_contract_stats_test.go`):
  `TestReceiveContractSupersedeClosesStats` — proven to fail without the receive
  supersede-close fix.
- The throttle and the Swift resort are timing/UI behaviors covered by the design
  above rather than unit tests (the resort is a pure stable partition, easy to
  reason about; the throttle is a coalescing loop with a deadline bypass).

