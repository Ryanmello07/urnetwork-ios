//
//  ContractDetailsView.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/8/26.
//

import SwiftUI
import URnetworkSdk

/**
 * Live contract details: a scrollable list with one row per peer client.
 * Each row visualizes the client contract (egress, green) and the
 * companion contract (ingress, pink) as two circles with transfer lines
 * between them. The inner disc of each circle grows as the contract
 * is used.
 */
struct ContractDetailsView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var deviceManager: DeviceManager

    @StateObject private var store: ContractDetailsStore

    init(mode: ContractDetailsMode) {
        _store = StateObject(wrappedValue: ContractDetailsStore(mode: mode))
    }

    /**
     * The rows currently shown. While the list is scrolled away from the top
     * this membership stays frozen so newly prepended contracts don't shift
     * the rows under the reader (their data still updates live). New rows are
     * merged when the list returns to the top, or through the new-items chip.
     */
    @State private var displayedIds: [String] = []
    @State private var isAtTop: Bool = true
    @State private var topBaseline: CGFloat? = nil

    private static let topMarkerId = "contract-details-top"

    // the frozen membership resolved to the current live rows
    private var displayedRows: [ContractClientRow] {
        if displayedIds.isEmpty {
            return store.rows
        }
        let byId = Dictionary(store.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resolved = displayedIds.compactMap { byId[$0] }
        // if every frozen row has closed, fall back to the live rows so the
        // list can't get stuck empty behind the chip
        return resolved.isEmpty ? store.rows : resolved
    }

    // rows are newest first, so new rows are the leading run not yet shown
    private var pendingCount: Int {
        let displayedSet = Set(displayedIds)
        return store.rows.prefix { !displayedSet.contains($0.id) }.count
    }

    var body: some View {

        // resolve the derived values once per render rather than recomputing the
        // dictionary/set in the view builder and twice inside the chip overlay
        let currentIds = store.rows.map { $0.id }
        let rows = displayedRows
        let pending = pendingCount

        Group {
            if store.rows.isEmpty {

                VStack(spacing: 8) {
                    Spacer()
                    Text("No open contracts")
                        .font(themeManager.currentTheme.bodyFont)
                        .foregroundColor(themeManager.currentTheme.textMutedColor)
                    Text(store.mode == .client
                         ? "Contracts appear here while connected."
                         : "Contracts appear here while providing.")
                        .font(themeManager.currentTheme.secondaryBodyFont)
                        .foregroundColor(themeManager.currentTheme.textFaintColor)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {

                            // top marker, used to detect when the list is at the very top
                            Color.clear
                                .frame(height: 0)
                                .id(Self.topMarkerId)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ContractTopOffsetKey.self,
                                            value: geometry.frame(in: .named("contractList")).minY
                                        )
                                    }
                                )

                            ForEach(rows) { row in
                                VStack(spacing: 0) {
                                    ContractClientRowView(row: row)
                                    Divider()
                                }
                                // new/closed client rows fade; the per-circle swap
                                // handles a contract being replaced within a row
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal)
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                    }
                    .coordinateSpace(name: "contractList")
                    .onPreferenceChange(ContractTopOffsetKey.self) { minY in
                        updateIsAtTop(minY)
                    }
                    .overlay(alignment: .top) {
                        if !isAtTop && 0 < pending {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    displayedIds = currentIds
                                }
                                withAnimation(.spring(duration: 0.3)) {
                                    scrollProxy.scrollTo(Self.topMarkerId, anchor: .top)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 10, weight: .semibold))
                                    // real plural rules live in Localizable.xcstrings ("%lld new")
                                    Text("\(pending) new")
                                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                                }
                                .foregroundColor(themeManager.currentTheme.inverseTextColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(themeManager.currentTheme.accentColor)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                }

            }
        }
        .onAppear {
            if let device = deviceManager.device {
                store.setup(device)
            }
            displayedIds = store.rows.map { $0.id }
        }
        .onDisappear {
            store.reset()
        }
        .onChange(of: currentIds) { ids in
            // only merge live while the list is at the top; otherwise the new
            // ids collect behind the chip
            if isAtTop {
                // animate the new contract in as it prepends to the top
                withAnimation(.easeInOut(duration: 0.5)) {
                    displayedIds = ids
                }
            }
        }
    }

    /**
     * At the very top the marker rests at its baseline offset. Scrolling
     * away moves it up (or unloads it, reporting nil).
     */
    private func updateIsAtTop(_ minY: CGFloat?) {
        guard let minY = minY else {
            if isAtTop {
                isAtTop = false
            }
            return
        }
        if topBaseline == nil {
            topBaseline = minY
        }
        let atTop = (topBaseline ?? 0) - 4 <= minY
        if atTop != isAtTop {
            isAtTop = atTop
            if atTop {
                displayedIds = store.rows.map { $0.id }
            }
        }
    }
}

private struct ContractTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

struct ContractClientRowView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var snackbarManager: UrSnackbarManager

    let row: ContractClientRow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(alignment: .top) {
                // the full client id, tappable to copy
                Text(row.clientId)
                    .font(.system(size: 13, weight: .medium).monospaced())
                    .foregroundColor(themeManager.currentTheme.textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyClientId()
                    }

                if 1 < row.pairCount {
                    // real plural rules live in Localizable.xcstrings ("%lld contracts")
                    Text("\(row.pairCount) contracts")
                        .font(themeManager.currentTheme.secondaryBodyFont)
                        .foregroundColor(themeManager.currentTheme.textMutedColor)
                        .layoutPriority(1)
                }
            }

            ContractPairViz(row: row)

        }
        .padding(.vertical, 16)
        .contextMenu {
            Button {
                copyClientId()
            } label: {
                Label("Copy client ID", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyClientId() {
        #if os(iOS)
        UIPasteboard.general.string = row.clientId
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(row.clientId, forType: .string)
        #endif
        snackbarManager.showSnackbar(message: String(localized: "Client ID copied"))
    }
}

/**
 * Two circles representing the client contract and the companion
 * contract, with directional transfer lines between them
 */
struct ContractPairViz: View {

    @EnvironmentObject var themeManager: ThemeManager

    let row: ContractClientRow

    private let circleSize: CGFloat = 56
    private let contractColor = Color.urGreen
    private let companionColor = Color.urPink

    var body: some View {
        HStack(alignment: .top, spacing: 16) {

            // a replaced contract (new id) slides its outer ring out to the side
            // and fades while the new ring fades into the same fixed slot; the
            // inner disc persists across the swap and just resizes. the fixed
            // slot keeps the row from jumping (parity with Android's
            // AnimatedContent).
            contractCircle(
                contractId: row.contractId,
                used: row.contractUsedByteCount,
                total: row.contractByteCount,
                color: contractColor,
                label: "Contract",
                removalEdge: .leading
            )

            VStack(spacing: 12) {
                Spacer().frame(height: 2)
                transferLine(
                    bitRate: row.contractBitRate,
                    color: contractColor,
                    pointsRight: true
                )
                transferLine(
                    bitRate: row.companionContractBitRate,
                    color: companionColor,
                    pointsRight: false
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: circleSize)

            contractCircle(
                contractId: row.companionContractId,
                used: row.companionContractUsedByteCount,
                total: row.companionContractByteCount,
                color: companionColor,
                label: "Companion",
                removalEdge: .trailing
            )

        }
    }

    private func contractCircle(
        contractId: String,
        used: Int64,
        total: Int64,
        color: Color,
        label: LocalizedStringKey,
        removalEdge: Edge
    ) -> some View {

        // area-proportional inner disc, with a minimum visible size
        let fraction = 0 < total ? min(1, Double(used) / Double(total)) : 0
        let innerSize = 0 < fraction ? max(6, circleSize * sqrt(fraction)) : 0

        return VStack(spacing: 8) {

            ZStack {

                // the outer ring carries the contract identity. On a replacement
                // the old ring is ejected -- it slides out toward removalEdge and
                // fades on its own fixed schedule, never reversing, and the new
                // ring fades into the slot only once every ejecting ring has left.
                // ContractRing supports multiple concurrent ejections (see it).
                ContractRing(
                    contractId: contractId,
                    color: color,
                    removalEdge: removalEdge,
                    circleSize: circleSize,
                    // a closing row (its last contract closed) ejects its ring and
                    // shows nothing after — the "eject" for a client leaving
                    visible: !row.closing
                )

                // the inner disc is a sibling with no id, so it persists across
                // a contract swap and simply resizes -- morphing to the new
                // level rather than popping. framing to zero when empty animates
                // the grow-in / drain instead of an insert/remove pop.
                Circle()
                    .fill(color.opacity(0.3))
                    .overlay(
                        Circle().stroke(color.opacity(0.6), lineWidth: 0.5)
                    )
                    .frame(width: innerSize, height: innerSize)
                    .animation(.easeOut(duration: 0.5), value: innerSize)
            }
            .frame(width: circleSize, height: circleSize)

            VStack(spacing: 2) {
                Text("\(formatByteCountCompact(used))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(themeManager.currentTheme.textColor)
                Text("of \(formatByteCountCompact(total))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(themeManager.currentTheme.textMutedColor)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.currentTheme.textFaintColor)
            }

        }
        .frame(width: 92)
    }

    private func transferLine(bitRate: Int, color: Color, pointsRight: Bool) -> some View {
        let active = 0 < bitRate
        return VStack(spacing: 3) {

            Text(active ? formatBitRate(bitRate) : " ")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundColor(color)
                .opacity(active ? 1 : 0)

            HStack(spacing: 0) {
                if !pointsRight {
                    Image(systemName: "arrowtriangle.left.fill")
                        .font(.system(size: 6))
                        .foregroundColor(color)
                        // pull the head onto the line so there is no gap
                        .padding(.trailing, -1)
                }
                Rectangle()
                    .fill(color)
                    .frame(height: 1)
                if pointsRight {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 6))
                        .foregroundColor(color)
                        .padding(.leading, -1)
                }
            }
            .opacity(active ? 0.9 : 0.25)

        }
    }
}

/**
 * The outer identity ring of a contract circle.
 *
 * When the contract id changes, the ring on screen is *ejected*: it slides out
 * toward `removalEdge` and fades on its own fixed schedule and is never reversed,
 * even if further contracts change while it is still leaving. Each ejection is an
 * independent instance, so multiple rings can be leaving at once and are all
 * rendered; the incoming ring fades into the slot only once the LAST ejecting
 * ring has finished leaving. This is the "eject one contract per change" analogy,
 * replacing the single interruptible `.id()` cross-fade that slid a ring back in
 * then out again when another change landed mid-slide.
 *
 * iOS 16 has no `withAnimation` completion handler, so each ejection's removal is
 * timed to the slide duration.
 */
private struct ContractRing: View {

    let contractId: String
    let color: Color
    let removalEdge: Edge
    let circleSize: CGFloat
    // whether a ring should occupy the slot. When it goes false (the client's
    // last contract closed) the on-screen ring ejects and nothing takes its place.
    var visible: Bool = true

    private static let slideDuration: Double = 0.5
    private static let fadeInDuration: Double = 0.35

    // one in-flight ejection: an independent slide-out + fade that runs once
    private struct Ejection: Identifiable {
        let id = UUID()
        var offset: CGFloat = 0
        var faded: Bool = false
    }

    // the ring currently occupying the slot (the latest contract id)
    @State private var currentId: String
    // whether the current ring has faded in — false while ejections are leaving,
    // so a not-yet-shown ring is never itself ejected (nothing to slide off)
    @State private var currentVisible: Bool
    // mirrors `visible` in state so the async ejection completion reads the live
    // intent (a plain input would be captured stale)
    @State private var present: Bool
    @State private var ejections: [Ejection] = []

    init(contractId: String, color: Color, removalEdge: Edge, circleSize: CGFloat, visible: Bool = true) {
        self.contractId = contractId
        self.color = color
        self.removalEdge = removalEdge
        self.circleSize = circleSize
        self.visible = visible
        // the first ring occupies the slot immediately if wanted — no ejection
        _currentId = State(initialValue: contractId)
        _currentVisible = State(initialValue: visible)
        _present = State(initialValue: visible)
    }

    // slide fully clear of the circle's slot
    private var offscreenOffset: CGFloat {
        let distance = circleSize * 3
        return removalEdge == .leading ? -distance : distance
    }

    private var ring: some View {
        Circle()
            .stroke(color.opacity(0.8), lineWidth: 1)
            .frame(width: circleSize, height: circleSize)
    }

    var body: some View {
        ZStack {
            // ejecting rings, each leaving on its own schedule
            ForEach(ejections) { ejection in
                ring
                    .offset(x: ejection.offset)
                    .opacity(ejection.faded ? 0 : 1)
            }

            // the incoming/settled ring; hidden until every ejection has left
            ring
                .opacity(currentVisible ? 1 : 0)
        }
        .frame(width: circleSize, height: circleSize)
        .onChange(of: contractId) { newId in
            guard newId != currentId else { return }
            // eject the on-screen ring (if any), then admit the new id
            if currentVisible {
                ejectCurrentRing()
            }
            currentId = newId
            currentVisible = false
            // nothing leaving -> the new ring can fade in right away
            if present && ejections.isEmpty {
                fadeInCurrent()
            }
        }
        .onChange(of: visible) { nowVisible in
            present = nowVisible
            if nowVisible {
                if !currentVisible && ejections.isEmpty {
                    fadeInCurrent()
                }
            } else if currentVisible {
                // the client is leaving: eject the ring and show nothing after
                ejectCurrentRing()
                currentVisible = false
            }
        }
    }

    private func fadeInCurrent() {
        withAnimation(.easeInOut(duration: Self.fadeInDuration)) {
            currentVisible = true
        }
    }

    // spawn an independent slide-out of the on-screen ring; once started it always
    // runs to completion (never reverses), even if more changes land meanwhile
    private func ejectCurrentRing() {
        let ejection = Ejection()
        let key = ejection.id
        ejections.append(ejection)

        withAnimation(.easeInOut(duration: Self.slideDuration)) {
            if let i = ejections.firstIndex(where: { $0.id == key }) {
                ejections[i].offset = offscreenOffset
                ejections[i].faded = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideDuration) {
            ejections.removeAll { $0.id == key }
            // admit the waiting ring only once the last one has left and if a ring
            // is still wanted in the slot
            if ejections.isEmpty && present && !currentVisible {
                fadeInCurrent()
            }
        }
    }
}

#Preview {

    var rowA = ContractClientRow(clientId: "0199a2b4c6d8e0f2a4b6c8d0e2f4a6b8")
    rowA.contractUsedByteCount = 12 * 1024 * 1024
    rowA.contractByteCount = 32 * 1024 * 1024
    rowA.contractBitRate = 1_200_000
    rowA.companionContractUsedByteCount = 3 * 1024 * 1024
    rowA.companionContractByteCount = 32 * 1024 * 1024
    rowA.companionContractBitRate = 240_000
    rowA.pairCount = 2

    var rowB = ContractClientRow(clientId: "44f1a2b4c6d8e0f2a4b6c8d0e2f4a6b8")
    rowB.contractUsedByteCount = 30 * 1024 * 1024
    rowB.contractByteCount = 32 * 1024 * 1024
    rowB.pairCount = 1

    return ScrollView {
        VStack(spacing: 0) {
            ContractClientRowView(row: rowA)
            Divider()
            ContractClientRowView(row: rowB)
        }
        .padding(.horizontal)
    }
    .environmentObject(ThemeManager.shared)
    .background(ThemeManager.shared.currentTheme.backgroundColor)
}
