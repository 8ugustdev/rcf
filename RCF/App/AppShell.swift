import SwiftUI

/// RCF 2.0 app shell. Replaces the 1.x tab bar: opens into the last-active
/// zone workspace (iPhone stack / iPad sidebar+detail). Global surfaces —
/// zone switch, accounts, settings, insights — live in the toolbar/overflow.
struct AppShell: View {
    @Environment(Session.self) private var session

    static let lastZoneKey = "rcf.workspace.lastZone"

    @State private var cache: ZoneCache?
    @State private var activeZone: Zone?
    @State private var showingZonePicker = false
    @State private var showingAccounts = false
    @State private var showingSettings = false
    @State private var showingPalette = false
    @State private var purgeURLZone: Zone?
    @State private var showingInsights = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var body: some View {
        Group {
            if let cache {
                shell(cache: cache)
            } else {
                LoadingView(title: "Loading zones…")
            }
        }
        .task {
            guard cache == nil else { return }
            let newCache = ZoneCache(session: session)
            await newCache.refresh()
            cache = newCache
            restoreLastZone(in: newCache)
            // Screenshot automation: open straight into the insights hub.
            if ProcessInfo.processInfo.arguments.contains("-insightsLaunch") {
                showingInsights = true
            }
        }
        .sheet(isPresented: $showingZonePicker) {
            ZonePickerSheet(zones: cache?.zones ?? []) { zone in
                activate(zone)
            }
            .presentationBackground(.cfBackground)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationBackground(.cfBackground)
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingAccounts) {
            AccountsSheet()
                .presentationBackground(.cfBackground)
        }
        .sheet(isPresented: $showingPalette) {
            if let cache {
                PaletteView(
                    session: session,
                    zoneCache: cache,
                    activeZone: activeZone,
                    onOpenZone: { zone in activate(zone) },
                    onDismiss: { showingPalette = false },
                    onOpenWorkers: { showingServices = true },
                    onPurgeURL: { purgeURLZone = activeZone },
                    onInsights: { showingInsights = true }
                )
                .presentationBackground(.thinMaterial)
            }
        }
        .sheet(item: $purgeURLZone) { zone in
            PurgeURLSheet(zone: zone, session: session)
        }
        .sheet(isPresented: $showingServices) {
            NavigationStack { ServicesView() }
                .presentationBackground(.cfBackground)
        }
        .sheet(isPresented: $showingInsights) {
            if let cache {
                NavigationStack {
                    InsightsView(session: session, zoneCache: cache) { zone in
                        showingInsights = false
                        activate(zone)
                    }
                }
                .presentationBackground(.cfBackground)
            }
        }
        .environment(\.paletteTrigger, PaletteTrigger(open: { showingPalette = true }))
    }

    // MARK: - Shell (compact stack / regular sidebar+detail)

    @ViewBuilder
    private func shell(cache: ZoneCache) -> some View {
        if let zone = activeZone {
            NavigationStack {
                ZoneWorkspaceView(zone: zone, session: session, onSwitchZone: { showingZonePicker = true })
                    .toolbar { shellToolbar }
                    .inkNavChrome()
            }
            .id(zone.id) // fresh navigation stack per zone
        } else {
            zoneBrowser(cache: cache)
        }
    }

    /// No active zone (first launch / stale id): full zones browser.
    private func zoneBrowser(cache: ZoneCache) -> some View {
        NavigationStack {
            ZoneBrowserList { zone in
                activate(zone)
            }
            .navigationTitle("Zones")
            .toolbar { shellToolbar }
            .inkNavChrome()
        }
    }

    @State private var showingServices = false

    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingZonePicker = true
            } label: {
                Label("Switch zone", systemImage: "arrow.left.arrow.right")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingInsights = true
            } label: {
                Label("Insights", systemImage: "sparkles.rectangle.stack")
            }
            .disabled(cache?.zones.isEmpty != false)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingPalette = true
            } label: {
                Label("Command palette", systemImage: "command")
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(activeZone == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    showingAccounts = true
                } label: {
                    Label("Accounts", systemImage: "person.2")
                }
                Button {
                    showingServices = true
                } label: {
                    Label("Account Services", systemImage: "cube.box")
                }
                NavigationLink {
                    AuditLogsView()
                } label: {
                    Label("Audit Logs", systemImage: "doc.text.magnifyingglass")
                }
            } label: {
                Image(systemName: "sidebar.leading")
            }
        }
    }

    // MARK: - Zone activation

    private func restoreLastZone(in cache: ZoneCache) {
        if let id = defaults.string(forKey: Self.lastZoneKey), let zone = cache.zone(id: id) {
            activeZone = zone
        }
        // else: leave nil → zone browser until user picks one.
    }

    private func activate(_ zone: Zone) {
        activeZone = zone
        defaults.set(zone.id, forKey: Self.lastZoneKey)
        DashboardRecents.record(zone.id, defaults: defaults)
    }
}

/// MRU zone ids (command-palette ranking + workspace history). Shared store.
@MainActor
enum DashboardRecents {
    static let key = "rcf.recent.zones"

    static func ids(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ zoneId: String, defaults: UserDefaults = .standard) {
        var list = ids(defaults: defaults).filter { $0 != zoneId }
        list.insert(zoneId, at: 0)
        defaults.set(Array(list.prefix(5)), forKey: key)
    }
}
