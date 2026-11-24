import SwiftUI
import AppKit

public struct MainContentView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @ObservedObject public var syncService: CloudSyncService
    @AppStorage("is_patrimony_hidden") private var isPatrimonyHidden: Bool = false

    public init(store: FinancialDataStore, llmService: LocalLLMService, syncService: CloudSyncService) {
        self.store = store
        self.llmService = llmService
        self.syncService = syncService
    }

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // App Brand Header
                HStack(spacing: 10) {
                    if let appIcon = FinSenseApp.loadAppIcon() {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#EC7000"), Color(hex: "#6366F1")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "brazilianrealsign.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("FinSense")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            if store.persistenceEnvironment.isDebug {
                                Text(store.persistenceEnvironment.badgeTitle)
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color(hex: "#F59E0B").opacity(0.18)))
                                    .foregroundStyle(Color(hex: "#F59E0B"))
                                    .help("Ambiente de Desenvolvimento isolado: \(store.databaseFileURL.path)")
                            }
                            SyncStatusIndicatorView(syncService: syncService)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // Sidebar Menu Items
                List(selection: $store.selectedDestination) {
                    Section("Visão Geral & Fluxo") {
                        sidebarRow(.dashboard)

                        Button {
                            store.selectedDestination = .transactions
                            store.selectedTransactionsSubmenu = .all
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: SidebarDestination.transactions.icon)
                                    .foregroundStyle(
                                        store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == .all
                                            ? Color.accentColor
                                            : .primary
                                    )
                                Text(SidebarDestination.transactions.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(SidebarDestination.transactions)

                        ForEach([TransactionsSubmenu.expenses, TransactionsSubmenu.incomes, TransactionsSubmenu.receivables]) { sub in
                            Button {
                                store.selectedDestination = .transactions
                                store.selectedTransactionsSubmenu = sub
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: sub.icon)
                                        .font(.caption)
                                        .foregroundStyle(
                                            store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == sub
                                                ? (sub == .expenses ? Color(hex: "#EF4444") : (sub == .receivables ? Color(hex: "#F59E0B") : Color(hex: "#10B981")))
                                                : .secondary
                                        )
                                        .frame(width: 18)
                                    Text(sub.title)
                                        .font(.caption)
                                        .fontWeight(
                                            store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == sub
                                                ? .semibold
                                                : .regular
                                        )
                                        .foregroundStyle(
                                            store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == sub
                                                ? Color.primary
                                                : .secondary
                                        )
                                    Spacer()
                                }
                                .padding(.leading, 18)
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        sidebarRow(.investments)
                        sidebarRow(.creditCards)
                    }

                    Section("Passivos & Contratos") {
                        sidebarRow(.loans)
                        sidebarRow(.financings)
                        sidebarRow(.debts)
                    }

                    Section("Planejamento & Inteligência") {
                        sidebarRow(.netWorth)
                        sidebarRow(.decisions)

                        NavigationLink(value: SidebarDestination.insights) {
                            HStack {
                                Label {
                                    Text(SidebarDestination.insights.title)
                                        .font(.system(size: 13.5, weight: .medium))
                                } icon: {
                                    Image(systemName: SidebarDestination.insights.icon)
                                }
                                Spacer()
                                if store.activeUnreviewedInsightsCount > 0 {
                                    Text("\(store.activeUnreviewedInsightsCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(Color(hex: "#6366F1")))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }

                    Section("Configurações") {
                        sidebarRow(.settings)

                        ForEach(SettingsSection.allCases) { sec in
                            Button {
                                store.selectedDestination = .settings
                                store.selectedSettingsSection = sec
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: sec.icon)
                                        .font(.caption)
                                        .foregroundStyle(
                                            store.selectedDestination == .settings && store.selectedSettingsSection == sec
                                                ? Color.accentColor
                                                : .secondary
                                        )
                                        .frame(width: 18)
                                    Text(sec.title)
                                        .font(.caption)
                                        .foregroundStyle(
                                            store.selectedDestination == .settings && store.selectedSettingsSection == sec
                                                ? Color.primary
                                                : .secondary
                                        )
                                    Spacer()
                                }
                                .padding(.leading, 18)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Bottom Consolidated Status & Quick AI Chat Button
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saldo Consolidado")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if isPatrimonyHidden {
                                Text("Oculto")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(store.totalConsolidatedPatrimonyNow >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        Button {
                            isPatrimonyHidden.toggle()
                        } label: {
                            Image(systemName: isPatrimonyHidden ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isPatrimonyHidden ? "Exibir valores de patrimônio" : "Ocultar valores de patrimônio (privacidade)")
                    }

                    Button {
                        store.openAIChat()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles.bubble.fill")
                            Text("Abrir Chat IA Local")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if store.persistenceEnvironment.isDebug {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 9))
                            Text("\(store.persistenceEnvironment.badgeTitle) • \(store.databaseFileURL.lastPathComponent)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(hex: "#F59E0B"))
                        .help("Banco de desenvolvimento isolado em: \(store.databaseFileURL.path)")
                    }
                }
                .padding(14)
            }
            .navigationSplitViewColumnWidth(min: 235, ideal: 250, max: 290)
        } detail: {
            Group {
                switch store.selectedDestination {
                case .dashboard:
                    DashboardView(store: store, llmService: llmService)
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
    private func sidebarRow(_ destination: SidebarDestination) -> some View {
        NavigationLink(value: destination) {
            Label {
                Text(destination.title)
                    .font(.system(size: 13.5, weight: .medium))
            } icon: {
                Image(systemName: destination.icon)
            }
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
                    QuickAddPanelController.shared.toggle {
                        QuickAddBarView(store: store) {
                            QuickAddPanelController.shared.close()
                        }
                    }
                }
                .keyboardShortcut("$", modifiers: [.command, .shift])
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
