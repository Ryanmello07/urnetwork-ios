
This document records the clarifications and amendments made to PLAN2.md during implementation and the first rounds of testing feedback. PLAN2.md remains the base plan; the items here refine or override it.

Design Clarifications

1. Provider statistics (wallet screen, under the reliability curve) has two transfer components: one for local data and one for blocked data. This mirrors the client statistics section, which has remote data and blocked data. Provider traffic populates the local and block series of the provider packet stats.
2. The local statistics section in the connect drawer has one transfer component for the local (split tunnel) series, with the "X split rules" summary under it.
3. The contract details views show one merged list with one row per peer client_id, aggregating that client's egress and ingress contract pairs (summed used/total bytes and bit rates). Rows keep first-seen order so the list doesn't jump while live.
4. In the contract details visualization, the client contract (egress) is green and the companion contract (ingress) is pink, matching the overall egress/ingress color theme. The transfer statistics components keep green for byte counts and pink for packet counts.
5. The split rule create/edit views are local-route only: selecting host values creates an override with RouteOverride{local: true}. Block overrides are not editable in this version, but the block and local state chips still highlight when any override determined the decision.
6. The DNS settings editor exposes the five resolver toggles plus all eight server lists as editable rows (add/remove with URL/IP validation), applied together with the Update button.
7. Network peers use the interface correctly with no polling: one initial GetNetworkPeers plus the NetworkPeersChangeListener. The pinned section stays hidden while empty and lights up when the connect-side peer tracking lands (a later step). Tapping a peer connects directly to that device via a ConnectLocation built from the peer's client id.
8. Device rename persists server side: the SDK api gained device_id and device_name on NetworkClientInfo and a DeviceSetName binding for POST /device/set-name. Settings shows the device name (editable) and the device spec from the network client record.

Feedback Amendments

1. Transfer statistics labels: the top right shows two stat rows — egress (up arrow) with its window-max byte rate and packet rate, and ingress (down arrow) under it. The mirrored plot keeps a shared symmetric scale per metric.
2. The transfer statistics series is densely sampled at one point per second, enforced in the contract view controller: missed ticks and ticks with no stats are zero-held, and a delta that spans a gap rebases with a zero instead of drawing a spike. The chart also assumes a prior zero just before the first sample so a young series closes back to the axis on the left instead of hanging open.
3. Blocked traffic uses brand colors: byte count coral (#FF6C58, UrCoral) and packet count maroon (#421006, UrMaroon) in the blocked transfer components, and the Blocked chip is coral.
4. The split rules must never capture the DNS resolver endpoints. The multi client gained an ignore hosts/ips setting (SetBlockActionIgnoreHosts): matching destinations are excluded from the activity association (ip_assoc), from override matching, and from surfaced block actions, while the default security/routing decisions and packet stats still apply. DeviceLocal feeds the DNS resolver host values (DoH URL hosts plus DNS server ips) into it whenever the DNS settings are updated and when a multi client is created.
5. The split rules activity list holds its scroll position: while scrolled away from the top the shown rows freeze and new items collect behind an "N new" chip that jumps back to the top; only at the very top do new items shift the view down.
6. Split rule and activity rows render all host names in the cluster ("A, B, C + X IPs") or all the ips when there are no host names, wrapping across lines. When there are more than 10 host names they collapse to their base names shown as "*.basename"; if more than 20 remain, the first, middle, and last 7 in alphanumeric order are shown with "+ X hosts" for the omitted count. Base names are public-suffix aware via the SDK's HostBaseName (shared across platforms), using a small embedded subset of the public suffix list so "cdn.a.example.co.uk" collapses to "example.co.uk".
7. Suggested remote DNS servers: the regional DNS list moved from a switch into an exported table in connect (RegionalDnsServers, associated to country codes; RegionalDnsResolverSettings derives from it) and is exposed through the SDK. The DNS editor lists them as toggles, off by default; toggling one on adds its ip to the remote DNS servers and enables unencrypted remote DNS. When connected to a matching country, the suggestion shows that country's color circle and sorts first.

Connect Drawer Interaction

1. When the drawer is expanded, its content scrolls; the scroll defers to the sheet drag so that a downward drag with the content at its top drags the drawer closed instead of rubber-banding. The drag handle region always drags the drawer, and while collapsed any vertical drag does.
2. When the drawer closes, the content scrolls back to the top.
3. Tapping the Connect tab while already on the connect screen closes the drawer.

SDK and Connect Surface Changes

1. ThroughputPoint was restructured into per-route samples — Remote, Local, Block — each a ThroughputSample with egress/ingress byte counts, packet counts, and bit rates per interval. This is a breaking change for the previous flat Android-facing field names.
2. ContractViewController samples the provider packet stats in the same tick and exposes GetProviderThroughputPoints (and GetProviderPacketStats), giving the provider parallel insight deferred by the SDK plan.
3. New in connect: RemoteUserNatMultiClient.SetBlockActionIgnoreHosts (see Feedback 4) and the RegionalDnsServers table. New in sdk: DeviceLocal DNS-ignore wiring, GetRegionalDnsServers, HostBaseName, DeviceSetName + NetworkClientInfo device fields.
4. Tests cover the throughput restructure and dense sampling, the ignore behavior end to end in the multi client, the DNS ignore host extraction, and the public-suffix base names.
