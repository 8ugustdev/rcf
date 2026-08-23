import SwiftUI

/// Global command palette overlay: fuzzy search over commands + cached
/// zones/records/workers. Keyboard-driven (↑↓ ⏎ esc). All searches run
/// against in-memory data — zero API calls while typing.
struct PaletteView: View {
    let session: Session
    let zoneCache: ZoneCache
    let activeZone: Zone?
    let onOpenZone: (Zone) -> Void
    let onDismiss: () -> Void
    var onOpenDNSRecord: ((DNSRecord) -> Void)? = nil
    var onOpenWorkers: (() -> Void)? = nil
    var onPurgeURL: (() -> Void)? = nil
    var onInsights: (() -> Void)? = nil

    @Environment(ThemeManager.self) private var theme
    @Environment(AppLockManager.self) private var lock

    @State private var query = ""
    @State private var data: PaletteData?
    @State private var selection: String?
    @State private var confirmPurge = false
    @State private var resultMessage: String?
    @FocusState private var fieldFocused: Bool

    /// Ink-toned palette chrome, resolved once per presentation from the
    /// active theme.
    private let palette: Palette = ActivePalette.current

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if let data {
                resultList(data: data)
            } else {
                LoadingView(title: "Loading palette data…")
                    .frame(maxHeight: 240)
            }
        }
        .frame(maxWidth: 640)
        .background(palette.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .padding(24)
        .background(palette.canvas.opacity(0.45).ignoresSafeArea())
        .onAppear { fieldFocused = true }
        .task {
            guard data == nil else { return }
            let d = PaletteData(session: session, activeZone: activeZone)
            await d.load()
            data = d
        }
        .confirmationDialog("Purge everything for \(activeZone?.name ?? "zone")?",
                            isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Purge All", role: .destructive) { runCommand(.purgeAll) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.accent)
            TextField("Search zones, records, workers, or run a command…", text: $query)
                .focused($fieldFocused)
                .textFieldStyle(.plain)
                .onSubmit {
                    if let data { runSelection(data) }
                }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    private func resultList(data: PaletteData) -> some View {
        let sections = PaletteEngine.sections(
            query: query,
            commands: commands(data: data),
            zones: zoneItems,
            records: recordItems(data: data),
            workers: workerItems(data: data)
        )
        let flat = sections.flatMap(\.items)

        return List {
            if let message = resultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSecondary)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        row(item)
                            .listRowBackground(
                                selection == item.id
                                    ? palette.selection
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = item.id
                                run(item)
                            }
                    }
                }
            }
            if sections.isEmpty {
                Text("No matches")
                    .foregroundStyle(palette.inkTertiary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: 360)
        .onChange(of: query) { _, _ in
            selection = flat.first?.id
        }
        .onKeyPress(.downArrow) {
            moveSelection(flat, delta: 1); return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(flat, delta: -1); return .handled
        }
        .background(
            // Click-outside dismiss.
            Color.black.opacity(0.001)
                .onTapGesture(perform: onDismiss)
        )
    }

    private func row(_ item: PaletteItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(item.destructive ? palette.danger : palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(palette.ink)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.inkTertiary)
                }
            }
            Spacer()
            if item.kind == .command {
                Text("⏎")
                    .font(.caption)
                    .foregroundStyle(palette.inkTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func runSelection(_ data: PaletteData) {
        let sections = PaletteEngine.sections(
            query: query,
            commands: commands(data: data),
            zones: zoneItems,
            records: recordItems(data: data),
            workers: workerItems(data: data)
        )
        let flat = sections.flatMap(\.items)
        if let id = selection, let item = flat.first(where: { $0.id == id }) {
            run(item)
        } else if let first = flat.first {
            run(first)
        }
    }

    private func run(_ item: PaletteItem) {
        item.run()
    }

    private func moveSelection(_ flat: [PaletteItem], delta: Int) {
        guard !flat.isEmpty else { return }
        let index = flat.firstIndex(where: { $0.id == selection }) ?? 0
        let next = min(max(index + delta, 0), flat.count - 1)
        selection = flat[next].id
    }

    // MARK: - Item builders

    private var zoneItems: [PaletteItem] {
        let recents = DashboardRecents.ids()
        return zoneCache.zones
            .sorted { a, b in
                let ai = recents.firstIndex(of: a.id) ?? Int.max
                let bi = recents.firstIndex(of: b.id) ?? Int.max
                return ai < bi
            }
            .map { zone in
                PaletteItem(
                    id: "zone-\(zone.id)",
                    kind: .zone,
                    title: zone.name,
                    subtitle: "\(zone.status.capitalized) · \(zone.plan.name)",
                    icon: "globe"
                ) {
                    onDismiss()
                    onOpenZone(zone)
                }
            }
    }

    private func recordItems(data: PaletteData) -> [PaletteItem] {
        data.records.map { record in
            PaletteItem(
                id: "record-\(record.id)",
                kind: .record,
                title: record.name,
                subtitle: "\(record.type.rawValue) → \(record.content.prefix(60))",
                icon: "point.3.connected.trianglepath.dotted"
            ) {
                onDismiss()
                // DNS list of the active zone; caller pushes editor.
                onOpenDNSRecord?(record)
            }
        }
    }

    private func workerItems(data: PaletteData) -> [PaletteItem] {
        data.workers.map { script in
            PaletteItem(
                id: "worker-\(script.id)",
                kind: .worker,
                title: script.id,
                subtitle: "Worker",
                icon: "hammer"
            ) {
                onDismiss()
                onOpenWorkers?()
            }
        }
    }

    // MARK: - Commands

    private enum PaletteCommand: String, CaseIterable {
        case purgeAll, purgeURL, devMode, alwaysHTTPS, insights, theme, lock
    }

    private func commands(data: PaletteData) -> [PaletteItem] {
        var items: [PaletteItem] = []
        guard let zone = activeZone else { return items }

        items.append(PaletteItem(
            id: "cmd-purge-all", kind: .command,
            title: "Purge Everything",
            subtitle: "\(zone.name) — invalidate full cache",
            icon: "trash", destructive: true
        ) { confirmPurge = true })

        items.append(PaletteItem(
            id: "cmd-purge-url", kind: .command,
            title: "Purge URL…",
            subtitle: "Invalidate specific URLs on \(zone.name)",
            icon: "link"
        ) { onPurgeURL?() })

        items.append(PaletteItem(
            id: "cmd-dev-mode", kind: .command,
            title: "Toggle Development Mode",
            subtitle: zone.name,
            icon: "wrench.and.screwdriver"
        ) { runCommand(.devMode) })

        items.append(PaletteItem(
            id: "cmd-https", kind: .command,
            title: "Toggle Always Use HTTPS",
            subtitle: zone.name,
            icon: "lock.shield"
        ) { runCommand(.alwaysHTTPS) })

        items.append(PaletteItem(
            id: "cmd-theme", kind: .command,
            title: "Switch Theme",
            subtitle: "Light / Dark / Ink Dark",
            icon: "paintpalette"
        ) { cycleTheme() })

        items.append(PaletteItem(
            id: "cmd-lock", kind: .command,
            title: "Lock App",
            subtitle: "Require biometrics to continue",
            icon: "lock"
        ) { onDismiss(); lock.lock() })

        if let onInsights = onInsights {
            items.append(PaletteItem(
                id: "cmd-insights", kind: .command,
                title: "Open Insights",
                subtitle: "Account health, alerts, AI",
                icon: "sparkles.rectangle.stack"
            ) { onDismiss(); onInsights() })
        }
        return items
    }

    private func runCommand(_ command: PaletteCommand) {
        guard let zone = activeZone else { return }
        let zoneId = zone.id
        Task {
            do {
                switch command {
                case .purgeAll:
                    let _: CloudflareResponse<NullResult> = try await session.client.send(
                        try CloudflareEndpoint.purgeEverything(zoneId: zoneId)
                    )
                    resultMessage = "Purged everything on \(zone.name)"
                case .purgeURL:
                    break // handled via dedicated flow
                case .devMode:
                    let _: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                        try CloudflareEndpoint.updateZoneSetting(zoneId: zoneId, id: "development_mode", value: .bool(true))
                    )
                    resultMessage = "Development mode enabled on \(zone.name)"
                case .alwaysHTTPS:
                    let current: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                        CloudflareEndpoint.zoneSetting(zoneId: zoneId, id: "always_use_https")
                    )
                    let on = SSLViewModel.alwaysHTTPSIsOn(current.result?.value)
                    let _: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                        try CloudflareEndpoint.updateZoneSetting(zoneId: zoneId, id: "always_use_https", value: .string(on ? "off" : "on"))
                    )
                    resultMessage = "Always Use HTTPS \(on ? "disabled" : "enabled") on \(zone.name)"
                case .insights, .theme, .lock:
                    break // handled inline
                }
                Haptics.success()
            } catch {
                resultMessage = (error as? CloudflareError)?.userMessage ?? "Command failed"
                Haptics.error()
            }
        }
    }

    private func cycleTheme() {
        let order: [ThemePreference] = [.dark, .light]
        let next = order[(order.firstIndex(of: theme.preference) ?? 0 + 1) % order.count]
        theme.preference = next
        resultMessage = "Theme: \(next.label)"
    }

    // MARK: - External flows (set by host)

}
