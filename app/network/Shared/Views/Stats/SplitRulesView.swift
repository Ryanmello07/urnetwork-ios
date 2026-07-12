//
//  SplitRulesView.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/8/26.
//

import SwiftUI
import URnetworkSdk

/**
 * Live routing decisions with the split rules pinned on top.
 *
 * Tapping a block action opens the rule editor to add the action's
 * host values as a local exception. Tapping an action whose decision
 * came from a rule edits that rule.
 */
struct SplitRulesView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var blockActionsStore: BlockActionsStore

    private struct EditorTarget: Identifiable {
        let id: String
        let candidates: [String]
        let selected: Set<String>
        let ruleId: String?
    }

    @State private var editorTarget: EditorTarget? = nil

    /**
     * The activity rows currently shown. While the list is scrolled away
     * from the top, this stays frozen so incoming items don't shift the
     * rows under the reader. New items are merged when the list returns
     * to the very top, or through the new-items chip.
     */
    @State private var displayedActions: [BlockActionItem] = []
    @State private var isAtTop: Bool = true
    @State private var topBaseline: CGFloat? = nil

    private static let topMarkerId = "split-rules-top"

    private var pendingCount: Int {
        let displayedIds = Set(displayedActions.map { $0.id })
        // live items are newest first, so the new items are the prefix
        return blockActionsStore.blockActions.prefix { !displayedIds.contains($0.id) }.count
    }

    var body: some View {

        // compute once per render rather than twice inside the chip overlay
        let pending = pendingCount

        ScrollViewReader { scrollProxy in

        List {

            /**
             * top marker, used to detect when the list is at the very top
             */
            Color.clear
                .frame(height: 0)
                .id(Self.topMarkerId)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SplitRulesTopOffsetKey.self,
                            value: geometry.frame(in: .named("splitRulesList")).minY
                        )
                    }
                )

            /**
             * Info: how exclusions work
             */
            Text("Exclusions apply to the whole co-associated network cluster, so related traffic is caught together.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.currentTheme.tintedBackgroundBase)
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            /**
             * Pinned split rules
             */
            Section(
                header: sectionHeader("Rules")
            ) {

                if blockActionsStore.splitRules.isEmpty {
                    Text("Tap traffic below to route it locally, bypassing the tunnel.")
                        .font(themeManager.currentTheme.secondaryBodyFont)
                        .foregroundColor(themeManager.currentTheme.textFaintColor)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(blockActionsStore.splitRules) { rule in
                        SplitRuleRowView(rule: rule)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorTarget = EditorTarget(
                                    id: rule.id,
                                    candidates: rule.hosts,
                                    selected: Set(rule.hosts),
                                    ruleId: rule.id
                                )
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    blockActionsStore.removeRule(id: rule.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            if index < blockActionsStore.splitRules.count {
                                blockActionsStore.removeRule(id: blockActionsStore.splitRules[index].id)
                            }
                        }
                    }
                }

            }

            /**
             * Live block actions
             */
            Section(
                header: HStack {
                    sectionHeader("Activity")
                    Spacer()
                    if 0 < blockActionsStore.allowedCount || 0 < blockActionsStore.blockedCount {
                        Text("\(blockActionsStore.allowedCount) allowed · \(blockActionsStore.blockedCount) blocked")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(themeManager.currentTheme.textFaintColor)
                            .textCase(nil)
                    }
                }
            ) {

                if displayedActions.isEmpty {
                    Text("Routing activity appears here while connected.")
                        .font(themeManager.currentTheme.secondaryBodyFont)
                        .foregroundColor(themeManager.currentTheme.textFaintColor)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedActions) { action in
                        BlockActionRowView(action: action)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openEditor(action)
                            }
                            .listRowBackground(Color.clear)
                    }
                }

            }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .coordinateSpace(name: "splitRulesList")
        .onPreferenceChange(SplitRulesTopOffsetKey.self) { minY in
            updateIsAtTop(minY)
        }
        .overlay(alignment: .top) {
            if !isAtTop && 0 < pending {
                Button(action: {
                    displayedActions = blockActionsStore.blockActions
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
        .background(themeManager.currentTheme.backgroundColor)
        .onAppear {
            displayedActions = blockActionsStore.blockActions
        }
        .onChange(of: blockActionsStore.blockActions) { blockActions in
            if isAtTop {
                displayedActions = blockActions
            }
        }
        .sheet(item: $editorTarget) { target in
            SplitRuleEditorView(
                candidates: target.candidates,
                initialSelection: target.selected,
                ruleId: target.ruleId
            )
            .environmentObject(themeManager)
            .environmentObject(blockActionsStore)
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 380)
            #endif
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
                displayedActions = blockActionsStore.blockActions
            }
        }
    }

    private func openEditor(_ action: BlockActionItem) {
        if let rule = blockActionsStore.splitRule(overrideId: action.overrideId) {
            // edit the rule that decided this action
            let candidates = orderedUnion(rule.hosts, action.hostValues)
            editorTarget = EditorTarget(
                id: action.id,
                candidates: candidates,
                selected: Set(rule.hosts),
                ruleId: rule.id
            )
        } else {
            // create a rule from the action's host values, host names pre-selected
            editorTarget = EditorTarget(
                id: action.id,
                candidates: action.hostValues,
                selected: Set(action.hosts.isEmpty ? action.ips : action.hosts),
                ruleId: nil
            )
        }
    }

    private func orderedUnion(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for value in a + b {
            if seen.insert(value).inserted {
                values.append(value)
            }
        }
        return values
    }

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(themeManager.currentTheme.secondaryBodyFont)
            .foregroundColor(themeManager.currentTheme.textMutedColor)
            .textCase(nil)
    }
}

private struct SplitRulesTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

struct SplitRuleRowView: View {

    @EnvironmentObject var themeManager: ThemeManager

    let rule: SplitRuleItem

    private var displayText: String {
        let hostNames = rule.hosts.filter { !isIpAddressValue($0) }
        let ips = rule.hosts.filter { isIpAddressValue($0) }
        return formatHostClusterText(hosts: hostNames, ips: ips)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {

            VStack(alignment: .leading, spacing: 2) {
                Text(displayText)
                    .font(themeManager.currentTheme.bodyFont)
                    .foregroundColor(themeManager.currentTheme.textColor)
                    .fixedSize(horizontal: false, vertical: true)

                // real plural rules live in Localizable.xcstrings ("%lld hosts")
                Text("\(rule.hosts.count) hosts")
                    .font(themeManager.currentTheme.secondaryBodyFont)
                    .foregroundColor(themeManager.currentTheme.textFaintColor)
            }

            Spacer()

            StateChip(text: "Local", color: .urGreen, highlighted: true)

        }
        .padding(.vertical, 2)
    }
}

struct BlockActionRowView: View {

    @EnvironmentObject var themeManager: ThemeManager

    let action: BlockActionItem

    var body: some View {
        HStack(alignment: .center, spacing: 8) {

            VStack(alignment: .leading, spacing: 2) {

                Text(action.displayText)
                    .font(themeManager.currentTheme.bodyFont)
                    .foregroundColor(themeManager.currentTheme.textColor)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(relativeTime(action.time))
                    if 0 < action.byteCount {
                        Text(formatByteCountCompact(action.byteCount))
                    }
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(themeManager.currentTheme.textFaintColor)

            }

            Spacer()

            StateChip(
                text: action.block ? "Blocked" : "Allowed",
                color: action.block ? .urCoral : themeManager.currentTheme.textMutedColor,
                highlighted: action.hasBlockOverride
            )

            StateChip(
                text: action.local ? "Local" : "Remote",
                color: action.local ? .urGreen : themeManager.currentTheme.textMutedColor,
                highlighted: action.hasRouteOverride
            )

        }
        .padding(.vertical, 2)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 {
            return "now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

struct StateChip: View {

    @EnvironmentObject var themeManager: ThemeManager

    let text: LocalizedStringKey
    let color: Color
    let highlighted: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(highlighted ? themeManager.currentTheme.inverseTextColor : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(highlighted ? color : color.opacity(0.14))
            .clipShape(Capsule())
    }
}

/**
 * Create or edit a split rule: select the host values to route locally
 */
struct SplitRuleEditorView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var blockActionsStore: BlockActionsStore
    @Environment(\.dismiss) private var dismiss

    let candidates: [String]
    let ruleId: String?

    @State private var selection: Set<String>

    init(candidates: [String], initialSelection: Set<String>, ruleId: String?) {
        self.candidates = candidates
        self.ruleId = ruleId
        _selection = State(initialValue: initialSelection)
    }

    private var isEditing: Bool {
        ruleId != nil
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            HStack {
                Text(isEditing ? "Edit split rule" : "New split rule")
                    .font(themeManager.currentTheme.toolbarTitleFont)
                    .foregroundColor(themeManager.currentTheme.textColor)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(themeManager.currentTheme.textMutedColor)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Text("Selected hosts are routed locally and bypass the tunnel.")
                .font(themeManager.currentTheme.secondaryBodyFont)
                .foregroundColor(themeManager.currentTheme.textMutedColor)
                .padding(.horizontal)

            List {
                ForEach(candidates, id: \.self) { host in
                    HStack {
                        Text(host)
                            .font(themeManager.currentTheme.bodyFont)
                            .foregroundColor(themeManager.currentTheme.textColor)

                        Spacer()

                        Image(systemName: selection.contains(host) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(
                                selection.contains(host)
                                    ? .urGreen
                                    : themeManager.currentTheme.textFaintColor
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selection.contains(host) {
                            selection.remove(host)
                        } else {
                            selection.insert(host)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(spacing: 12) {

                UrButton(
                    text: isEditing ? "Update" : "Create",
                    action: {
                        let hosts = candidates.filter { selection.contains($0) }
                        if let ruleId = ruleId {
                            blockActionsStore.updateRule(id: ruleId, hosts: hosts)
                        } else {
                            blockActionsStore.createLocalRule(hosts: hosts)
                        }
                        dismiss()
                    },
                    enabled: isEditing || !selection.isEmpty
                )

                if let ruleId = ruleId {
                    Button(action: {
                        blockActionsStore.removeRule(id: ruleId)
                        dismiss()
                    }) {
                        Text("Remove rule")
                            .font(themeManager.currentTheme.secondaryBodyFont)
                            .foregroundColor(themeManager.currentTheme.dangerColor)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding()

        }
        .background(themeManager.currentTheme.backgroundColor)
    }
}
