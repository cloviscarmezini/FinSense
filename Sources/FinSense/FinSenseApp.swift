import SwiftUI
import AppKit

public struct MainContentView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @ObservedObject public var syncService: CloudSyncService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("is_patrimony_hidden") private var isPatrimonyHidden: Bool = false
    @AppStorage("sidebar_decisions_expanded") private var isDecisionsExpanded: Bool = false
    @State private var hoveredDestination: SidebarDestination? = nil
    @State private var hoveredDecisionsTab: DecisionsTab? = nil

    public init(store: FinancialDataStore, llmService: LocalLLMService, syncService: CloudSyncService) {
        self.store = store
        self.llmService = llmService
        self.syncService = syncService
    }

    public var body: some View {
        NavigationSplitView {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // App Brand Header
                    HStack(spacing: 10) {
                        if let appIcon = FinSenseApp.loadAppIcon() {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "#EC7000"), Color(hex: "#6366F1")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                Image(systemName: "brazilianrealsign.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        Text("FinSense")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)

                        SyncStatusIndicatorView(syncService: syncService)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        .frame(height: 1)

                    // Redesigned Clean Sidebar Navigation (Sem poluição de sub-itens fixos)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            sidebarGroup(title: "Visão Geral & Fluxo") {
                                sidebarItem(.dashboard)
                                sidebarItem(.transactions) {
                                    store.selectedTransactionsSubmenu = .all
                                }
                                sidebarItem(.investments)
                                sidebarItem(.creditCards)
                                sidebarItem(.analytics)
                            }

                            sidebarGroup(title: "Passivos & Contratos") {
                                sidebarItem(.loans)
                                sidebarItem(.financings)
                                sidebarItem(.debts)
                            }

                            sidebarGroup(title: "Planejamento & Inteligência") {
                                sidebarItem(.netWorth)

                                // Decisões & Cenários (com expansão opcional para módulos internos)
                                HStack(spacing: 4) {
                                    sidebarItemButton(
                                        destination: .decisions,
                                        title: SidebarDestination.decisions.title,
                                        icon: SidebarDestination.decisions.icon
                                    )

                                    Button {
                                        withAnimation(.snappy(duration: 0.18)) {
                                            isDecisionsExpanded.toggle()
                                        }
                                    } label: {
                                        Image(systemName: isDecisionsExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.5) : Color.secondary)
                                            .frame(width: 22, height: 22)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(isDecisionsExpanded ? "Recolher módulos" : "Expandir módulos")
                                }

                                if isDecisionsExpanded {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(DecisionsTab.allCases) { tab in
                                            let isTabActive = store.selectedDestination == .decisions && store.selectedDecisionsTab == tab
                                            let isTabHovered = hoveredDecisionsTab == tab
                                            Button {
                                                store.selectedDestination = .decisions
                                                store.selectedDecisionsTab = tab
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: tab.icon)
                                                        .font(.system(size: 11.5))
                                                        .foregroundStyle(
                                                            isTabActive
                                                                ? FinSenseTheme.indigo
                                                                : (colorScheme == .dark ? Color.white.opacity(0.5) : Color.secondary)
                                                        )
                                                        .frame(width: 16)
                                                    Text(tab.rawValue)
                                                        .font(.system(size: 12, weight: isTabActive ? .semibold : .regular))
                                                        .foregroundStyle(
                                                            isTabActive
                                                                ? (colorScheme == .dark ? .white : .primary)
                                                                : (colorScheme == .dark ? Color.white.opacity(0.62) : Color.secondary)
                                                        )
                                                    Spacer()
                                                }
                                                .padding(.leading, 22)
                                                .padding(.trailing, 8)
                                                .padding(.vertical, 5)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                        .fill(
                                                            isTabActive
                                                                ? (colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.055))
                                                                : (isTabHovered ? (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)) : Color.clear)
                                                        )
                                                )
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .onHover { hovering in
                                                hoveredDecisionsTab = hovering ? tab : (hoveredDecisionsTab == tab ? nil : hoveredDecisionsTab)
                                            }
                                        }
                                    }
                                }

                                sidebarItem(
                                    .insights,
                                    badgeCount: store.activeUnreviewedInsightsCount
                                )
                            }

                            sidebarGroup(title: "Sistema") {
                                sidebarItem(.settings)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                    }

                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        .frame(height: 1)

                    // Rodapé Compacto: Card Saldo Consolidado (#161618) + Chat IA Local Índigo Escuro/Glass
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Saldo Consolidado")
                                    .font(.caption2)
                                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.55) : .secondary)
                                if isPatrimonyHidden {
                                    Text("Oculto")
                                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))
                                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(store.totalConsolidatedPatrimonyNow >= 0 ? FinSenseTheme.emerald : FinSenseTheme.coral)
                                        .numericCurrencyTransition(value: store.totalConsolidatedPatrimonyNow)
                                }
                            }
                            Spacer()
                            Button {
                                isPatrimonyHidden.toggle()
                            } label: {
                                Image(systemName: isPatrimonyHidden ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.55) : .secondary)
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(isPatrimonyHidden ? "Exibir valores de patrimônio" : "Ocultar valores de patrimônio (privacidade)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colorScheme == .dark ? Color(hex: "#161618") : FinSenseTheme.elevatedSurface(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06), lineWidth: 0.75)
                        )

                        Button {
                            store.openAIChat()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "sparkles.bubble.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#A5B4FC"))
                                Text("Chat IA Local")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? .white : Color(hex: "#312E81"))
                                Spacer()
                                Text("⌘K")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.55) : .secondary)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color(hex: "#4F46E5").opacity(colorScheme == .dark ? 0.24 : 0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color(hex: "#4F46E5").opacity(colorScheme == .dark ? 0.45 : 0.30), lineWidth: 0.75)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
                .background(FinSenseTheme.sidebarBackground(for: colorScheme))

                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                    .frame(width: 1)
            }
            .navigationSplitViewColumnWidth(min: 235, ideal: 250, max: 285)
        } detail: {
            Group {
                switch store.selectedDestination {
                case .dashboard:
                    DashboardView(store: store, llmService: llmService)
                case .analytics:
                    AnalyticsChartsView(store: store)
                case .transactions:
                    TransactionsView(store: store, llmService: llmService)
                case .netWorth:
                    NetWorthDashboardView(store: store)
                case .creditCards:
                    CreditCardsView(store: store, llmService: llmService)
                case .investments:
                    InvestmentsView(store: store)
                case .loans:
                    LoansAndFinancingsView(store: store, llmService: llmService, kind: .loan)
                case .financings:
                    LoansAndFinancingsView(store: store, llmService: llmService, kind: .financing)
                case .debts:
                    DebtsView(store: store, llmService: llmService)
                case .decisions:
                    DecisionsAndScenariosView(store: store)
                case .insights:
                    InsightsCenterView(store: store)
                case .settings:
                    SettingsView(store: store, llmService: llmService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FinSenseTheme.canvasBackground(for: colorScheme))
            .toolbarBackground(FinSenseTheme.windowBackground(for: colorScheme), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    AppleIntelligenceStatusDot(llmService: llmService, store: store)
                    SyncStatusIndicatorView(syncService: syncService)
                }
            }
        }
        .sheet(isPresented: $store.isAIChatPresented) {
            AIChatSheetView(store: store, llmService: llmService)
        }
        .sheet(isPresented: $store.isLLMInstallAlertPresented) {
            LLMInstallRequiredSheet(store: store, llmService: llmService)
        }
        .onAppear {
            llmService.activateBuiltInAppleIntelligenceIfNeeded(in: store)
            GlobalHotKeyManager.shared.registerQuickAddHotKeys {
                QuickAddPanelController.shared.toggle {
                    QuickAddBarView(store: store) {
                        QuickAddPanelController.shared.close()
                    }
                }
            }
            Task { await ExchangeRateService.shared.refreshRates() }
            llmService.prewarmAppleIntelligence(store: store)
            _ = store.runDailyBehavioralMLAnalysisIfNeeded(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            _ = store.runDailyBehavioralMLAnalysisIfNeeded(force: false)
        }
    }

    @ViewBuilder
    private func sidebarGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.38) : Color.secondary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            content()
        }
    }

    @ViewBuilder
    private func sidebarItem(
        _ destination: SidebarDestination,
        badgeCount: Int = 0,
        extraAction: (() -> Void)? = nil
    ) -> some View {
        sidebarItemButton(
            destination: destination,
            title: destination.title,
            icon: destination.icon,
            badgeCount: badgeCount,
            extraAction: extraAction
        )
    }

    @ViewBuilder
    private func sidebarItemButton(
        destination: SidebarDestination,
        title: String,
        icon: String,
        badgeCount: Int = 0,
        extraAction: (() -> Void)? = nil
    ) -> some View {
        let isActive = store.selectedDestination == destination
        let isHovered = hoveredDestination == destination

        Button {
            withAnimation(.snappy(duration: 0.18)) {
                store.selectedDestination = destination
                extraAction?()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(
                        isActive
                            ? FinSenseTheme.indigo
                            : (colorScheme == .dark ? Color.white.opacity(0.55) : Color.secondary)
                    )
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(
                        isActive
                            ? (colorScheme == .dark ? Color.white : Color.primary)
                            : (colorScheme == .dark ? Color.white.opacity(0.75) : Color.primary.opacity(0.8))
                    )
                    .lineLimit(1)

                Spacer(minLength: 4)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(FinSenseTheme.indigo.opacity(0.85)))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            : (isHovered ? (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive
                            ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
                            : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDestination = hovering ? destination : (hoveredDestination == destination ? nil : hoveredDestination)
        }
    }
}

// MARK: - AppKit Delegate para Prevenção de Hibernação (App Nap) e Reabertura Instantânea pelo Dock

public final class FinSenseAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var appNapActivity: NSObjectProtocol?
    private weak var mainAppWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Impede que o macOS coloque o app em estado de "hibernação" (App Nap) quando a janela é fechada ou minimizada
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Manter motor financeiro FinSense responsivo ao reabrir pelo Dock"
        )
        DispatchQueue.main.async { [weak self] in
            self?.registerMainWindows()
        }
    }

    public func registerMainWindows() {
        for window in NSApplication.shared.windows {
            guard window.sheetParent == nil, !(window is NSPanel) else { continue }
            if mainAppWindow == nil {
                mainAppWindow = window
            }
            if window.delegate !== self {
                window.delegate = self
            }
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 15.0 / 255.0, alpha: 1.0)
                    : NSColor(red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 239.0 / 255.0, alpha: 1.0)
            }
        }
    }

    /// Ao clicar no botão vermelho de fechar (✕) da janela principal, oculta a janela (`orderOut`) em vez de
    /// destruir a cena raiz do SwiftUI, garantindo que clicar no ícone do Dock reabra a janela instantaneamente.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.sheetParent == nil && !(sender is NSPanel) {
            mainAppWindow = sender
            sender.orderOut(nil)
            return false
        }
        return true
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreMainWindowIfNeeded()
        return true
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        registerMainWindows()
        let hasVisibleMain = NSApplication.shared.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.sheetParent == nil && !($0 is NSPanel)
        }
        if !hasVisibleMain {
            restoreMainWindowIfNeeded()
        }
    }

    public func restoreMainWindowIfNeeded() {
        if let window = mainAppWindow ?? NSApplication.shared.windows.first(where: { $0.sheetParent == nil && !($0 is NSPanel) }) {
            mainAppWindow = window
            window.isReleasedWhenClosed = false
            if window.delegate !== self {
                window.delegate = self
            }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
public struct FinSenseApp: App {
    @NSApplicationDelegateAdaptor(FinSenseAppDelegate.self) private var appDelegate
    @StateObject private var store: FinancialDataStore
    @StateObject private var syncService: CloudSyncService
    @StateObject private var llmService = LocalLLMService()

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
        Self.configureApplicationIcon()

        let storeInstance = FinancialDataStore()
        let syncInstance = CloudSyncService(store: storeInstance)
        storeInstance.cloudSyncService = syncInstance

        _store = StateObject(wrappedValue: storeInstance)
        _syncService = StateObject(wrappedValue: syncInstance)
    }

    public static func configureApplicationIcon() {
        if let iconImage = loadAppIcon() {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    public static func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let fallbackPath = "Sources/FinSense/Resources/AppIcon.png"
        if FileManager.default.fileExists(atPath: fallbackPath),
           let img = NSImage(contentsOfFile: fallbackPath) {
            return img
        }
        return nil
    }

    public var body: some Scene {
        WindowGroup(PersistenceEnvironment.current.isDebug ? "FinSense [DEBUG DB]" : "FinSense") {
            MainContentView(store: store, llmService: llmService, syncService: syncService)
                .frame(minWidth: 1120, minHeight: 740)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        appDelegate.registerMainWindows()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Financeiro") {
                Button("Ir para Dashboard") {
                    store.selectedDestination = .dashboard
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Ir para Transações") {
                    store.selectedDestination = .transactions
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Ir para Investimentos") {
                    store.selectedDestination = .investments
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Ir para Empréstimos") {
                    store.selectedDestination = .loans
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Ir para Financiamentos") {
                    store.selectedDestination = .financings
                }
                .keyboardShortcut("5", modifiers: [.command])

                Button("Ir para Dívidas") {
                    store.selectedDestination = .debts
                }
                .keyboardShortcut("6", modifiers: [.command])

                Divider()

                // Atalho Global no Menu Superior para Alternar entre "Com Planejamento" e "Real (Base)"
                Button(
                    store.budgetProjectionScenario == .withPlanning
                        ? "Alternar Cenário para Real (Base)"
                        : "Alternar Cenário para Com Planejamento"
                ) {
                    store.budgetProjectionScenario = store.budgetProjectionScenario == .withPlanning
                        ? .realBase
                        : .withPlanning
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button(
                    store.budgetProjectionScenario == .withPlanning
                        ? "✓ Cenário Ativo: Com Planejamento"
                        : "   Cenário: Com Planejamento"
                ) {
                    store.budgetProjectionScenario = .withPlanning
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button(
                    store.budgetProjectionScenario == .realBase
                        ? "✓ Cenário Ativo: Real (Base)"
                        : "   Cenário: Real (Base)"
                ) {
                    store.budgetProjectionScenario = .realBase
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button("Reabrir Janela Principal") {
                    appDelegate.restoreMainWindowIfNeeded()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Abrir Chat com IA Local") {
                    store.openAIChat()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Quick-Add Rápido (Spotlight)") {
                    GlobalHotKeyManager.shared.triggerWithDebounce()
                }
                .keyboardShortcut(.space, modifiers: [.control])
            }
        }

        MenuBarExtra("FinSense Quick-Add", systemImage: "dollarsign.circle.fill") {
            QuickAddBarView(store: store) {
                NSApplication.shared.keyWindow?.close()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
