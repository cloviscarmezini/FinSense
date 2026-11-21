import Foundation
import SwiftUI
import Combine

// MARK: - Persistent Snapshot

public struct FinancialDatabaseSnapshot: Codable {
    public var schemaVersion: Int?
    public var accounts: [BankAccount]
    public var categories: [CategoryItem]
    public var transactions: [FinancialTransaction]
    public var investments: [InvestmentItem]
    public var debts: [DebtItem]
    public var contracts: [CreditContract]
    public var amortizationPlans: [AmortizationPlan]?
    public var budgetProjectionScenario: BudgetProjectionScenario?
    public var provisions: [CategoryProvision]?
    public var categoryQuotas: [CategoryQuotaRule]?
    public var assets: [ExportedAssetFile]?
    public var llmConfig: LLMConfiguration
    public var chatHistory: [ChatMessage]
    public var hasSeededInitialStatement: Bool

    public init(
        schemaVersion: Int? = 2,
        accounts: [BankAccount] = [],
        categories: [CategoryItem] = [],
        transactions: [FinancialTransaction] = [],
        investments: [InvestmentItem] = [],
        debts: [DebtItem] = [],
        contracts: [CreditContract] = [],
        amortizationPlans: [AmortizationPlan]? = [],
        budgetProjectionScenario: BudgetProjectionScenario? = nil,
        provisions: [CategoryProvision]? = [],
        categoryQuotas: [CategoryQuotaRule]? = [],
        assets: [ExportedAssetFile]? = nil,
        llmConfig: LLMConfiguration = LLMConfiguration(),
        chatHistory: [ChatMessage] = [],
        hasSeededInitialStatement: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.investments = investments
        self.debts = debts
        self.contracts = contracts
        self.amortizationPlans = amortizationPlans
        self.budgetProjectionScenario = budgetProjectionScenario
        self.provisions = provisions
        self.categoryQuotas = categoryQuotas
        self.assets = assets
        self.llmConfig = llmConfig
        self.chatHistory = chatHistory
        self.hasSeededInitialStatement = hasSeededInitialStatement
    }
}

public struct ImportTargetAnalysis: Identifiable, Hashable {
    public var id: ExportDataTarget { target }
    public let target: ExportDataTarget
    public let totalCount: Int
    public let newCount: Int
    public let duplicateCount: Int

    public init(target: ExportDataTarget, totalCount: Int, newCount: Int, duplicateCount: Int) {
        self.target = target
        self.totalCount = totalCount
        self.newCount = newCount
        self.duplicateCount = duplicateCount
    }
}

public struct PreparedDatabaseImportPackage {
    public let snapshot: FinancialDatabaseSnapshot
    public let targetAnalyses: [ExportDataTarget: ImportTargetAnalysis]
    public let availableNonEmptyTargets: Set<ExportDataTarget>

    public init(
        snapshot: FinancialDatabaseSnapshot,
        targetAnalyses: [ExportDataTarget: ImportTargetAnalysis],
        availableNonEmptyTargets: Set<ExportDataTarget>
    ) {
        self.snapshot = snapshot
        self.targetAnalyses = targetAnalyses
        self.availableNonEmptyTargets = availableNonEmptyTargets
    }

    public func analysis(for target: ExportDataTarget) -> ImportTargetAnalysis {
        targetAnalyses[target] ?? ImportTargetAnalysis(target: target, totalCount: 0, newCount: 0, duplicateCount: 0)
    }

    public func totalCount(for target: ExportDataTarget) -> Int {
        analysis(for: target).totalCount
    }

    public func newCount(for target: ExportDataTarget) -> Int {
        analysis(for: target).newCount
    }

    public func duplicateCount(for target: ExportDataTarget) -> Int {
        analysis(for: target).duplicateCount
    }
}

public struct SelectiveImportExecutionResult {
    public var importedAccounts: Int = 0
    public var importedCategories: Int = 0
    public var importedTransactions: Int = 0
    public var importedInvestments: Int = 0
    public var importedLoans: Int = 0
    public var importedFinancings: Int = 0
    public var importedDebts: Int = 0
    public var importedProvisionsAndQuotas: Int = 0
    public var importedAssets: Int = 0
    public var skippedDuplicatesTotal: Int = 0
    public var autoCreatedDependenciesCount: Int = 0
    public var skippedDuplicateCounts: [ExportDataTarget: Int] = [:]

    public init() {}

    public var importedCounts: [ExportDataTarget: Int] {
        [
            .accounts: importedAccounts,
            .categories: importedCategories,
            .transactions: importedTransactions,
            .investments: importedInvestments,
            .loans: importedLoans,
            .financings: importedFinancings,
            .debts: importedDebts,
            .provisions: importedProvisionsAndQuotas,
            .assets: importedAssets
        ]
    }

    public var totalImportedItems: Int {
        importedAccounts + importedCategories + importedTransactions + importedInvestments +
        importedLoans + importedFinancings + importedDebts + importedProvisionsAndQuotas + importedAssets
    }
}

public typealias SelectiveDatabaseImportResult = SelectiveImportExecutionResult

// MARK: - Dashboard Breakdown Models

public struct CategorySpendSummary: Identifiable, Hashable {
    public var id: UUID { category.id }
    public let category: CategoryItem
    public let total: Double
    public let percentage: Double
    public let count: Int
}

public struct MonthlyCashFlowPoint: Identifiable, Hashable {
    public var id: String { label }
    public let monthDate: Date
    public let label: String
    public let income: Double
    public let expense: Double
    public let net: Double
    public let accumulatedBalance: Double
    public let remainingProvisions: Double
    public let isPastMonth: Bool

    public var totalBudgetedExpense: Double {
        expense + remainingProvisions
    }

    public init(
        monthDate: Date,
        label: String,
        income: Double,
        expense: Double,
        net: Double,
        accumulatedBalance: Double,
        remainingProvisions: Double = 0.0,
        isPastMonth: Bool = false
    ) {
        self.monthDate = monthDate
        self.label = label
        self.income = income
        self.expense = expense
        self.net = net
        self.accumulatedBalance = accumulatedBalance
        self.remainingProvisions = remainingProvisions
        self.isPastMonth = isPastMonth
    }
}

public struct DebtLineItem: Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let section: String
    public let nominalAmount: Double
    public let projectedPayoffAmount: Double
    public let iconSymbol: String
    public let colorHex: String
}

public struct ComprehensiveDebtSummary: Hashable {
    public let currentMonthUnpaidTransactions: [FinancialTransaction]
    public let futureUnpaidRegularTransactions: [FinancialTransaction]
    public let activeDebts: [DebtItem]
    public let activeLoans: [CreditContract]
    public let activeFinancings: [CreditContract]

    public let currentMonthUnpaidTotal: Double
    public let futureRegularExpensesTotal: Double
    public let unpaidDebtsTotal: Double
    public let loansRemainingNominalTotal: Double
    public let loansProjectedPayoffTotal: Double
    public let loansAmortizedInPeriodTotal: Double
    public let financingsRemainingNominalTotal: Double
    public let financingsProjectedPayoffTotal: Double
    public let financingsAmortizedInPeriodTotal: Double

    // Métricas Desacopladas de Pagamentos vs Amortização Real no Principal (Padrão SFH / Tabela Price)
    public let loansPaidInPeriodTotal: Double
    public let loansRealAmortizationInPeriodTotal: Double
    public let financingsPaidInPeriodTotal: Double
    public let financingsRealAmortizationInPeriodTotal: Double

    public let grandTotalNominal: Double
    public let grandTotalWithPayoffProjection: Double
    public let itemizedLines: [DebtLineItem]

    public init(
        currentMonthUnpaidTransactions: [FinancialTransaction],
        futureUnpaidRegularTransactions: [FinancialTransaction],
        activeDebts: [DebtItem],
        activeLoans: [CreditContract],
        activeFinancings: [CreditContract],
        currentMonthUnpaidTotal: Double,
        futureRegularExpensesTotal: Double,
        unpaidDebtsTotal: Double,
        loansRemainingNominalTotal: Double,
        loansProjectedPayoffTotal: Double,
        loansAmortizedInPeriodTotal: Double = 0.0,
        financingsRemainingNominalTotal: Double,
        financingsProjectedPayoffTotal: Double,
        financingsAmortizedInPeriodTotal: Double = 0.0,
        loansPaidInPeriodTotal: Double? = nil,
        loansRealAmortizationInPeriodTotal: Double = 0.0,
        financingsPaidInPeriodTotal: Double? = nil,
        financingsRealAmortizationInPeriodTotal: Double = 0.0,
        grandTotalNominal: Double,
        grandTotalWithPayoffProjection: Double,
        itemizedLines: [DebtLineItem]
    ) {
        self.currentMonthUnpaidTransactions = currentMonthUnpaidTransactions
        self.futureUnpaidRegularTransactions = futureUnpaidRegularTransactions
        self.activeDebts = activeDebts
        self.activeLoans = activeLoans
        self.activeFinancings = activeFinancings
        self.currentMonthUnpaidTotal = currentMonthUnpaidTotal
        self.futureRegularExpensesTotal = futureRegularExpensesTotal
        self.unpaidDebtsTotal = unpaidDebtsTotal
        self.loansRemainingNominalTotal = loansRemainingNominalTotal
        self.loansProjectedPayoffTotal = loansProjectedPayoffTotal
        self.loansAmortizedInPeriodTotal = loansAmortizedInPeriodTotal
        self.financingsRemainingNominalTotal = financingsRemainingNominalTotal
        self.financingsProjectedPayoffTotal = financingsProjectedPayoffTotal
        self.financingsAmortizedInPeriodTotal = financingsAmortizedInPeriodTotal
        self.loansPaidInPeriodTotal = loansPaidInPeriodTotal ?? loansAmortizedInPeriodTotal
        self.loansRealAmortizationInPeriodTotal = loansRealAmortizationInPeriodTotal
        self.financingsPaidInPeriodTotal = financingsPaidInPeriodTotal ?? financingsAmortizedInPeriodTotal
        self.financingsRealAmortizationInPeriodTotal = financingsRealAmortizationInPeriodTotal
        self.grandTotalNominal = grandTotalNominal
        self.grandTotalWithPayoffProjection = grandTotalWithPayoffProjection
        self.itemizedLines = itemizedLines
    }

    /// Total a Quitar Estrito do Balanço Patrimonial (Dívida Real Consolidada = Dívidas + Empréstimos PV + Financiamentos PV)
    public var totalRealLiabilities: Double {
        unpaidDebtsTotal + loansProjectedPayoffTotal + financingsProjectedPayoffTotal
    }

    /// Soma Nominal Futura Estrita dos Contratos (Dívidas + Empréstimos Nominal + Financiamentos Nominal)
    public var totalNominalLiabilities: Double {
        unpaidDebtsTotal + loansRemainingNominalTotal + financingsRemainingNominalTotal
    }
}

// MARK: - Period Debt Service Breakdown (Fluxo / DTI vs Receitas)

public struct PeriodDebtServiceBreakdown: Hashable {
    public let financingInstallments: Double
    public let loanInstallments: Double
    public let debtInstallments: Double
    public let operationalExpenses: Double
    public let totalDebtService: Double
    public let totalOutflows: Double
    public let periodIncome: Double
    public let freeMargin: Double
    public let deficit: Double
    public let debtToIncomeRatio: Double
    public let totalCommitmentRatio: Double
    public let isAnnual: Bool
    public let yearStr: String

    public init(
        financingInstallments: Double,
        loanInstallments: Double,
        debtInstallments: Double,
        operationalExpenses: Double,
        totalDebtService: Double,
        totalOutflows: Double,
        periodIncome: Double,
        freeMargin: Double,
        deficit: Double,
        debtToIncomeRatio: Double,
        totalCommitmentRatio: Double,
        isAnnual: Bool,
        yearStr: String
    ) {
        self.financingInstallments = financingInstallments
        self.loanInstallments = loanInstallments
        self.debtInstallments = debtInstallments
        self.operationalExpenses = operationalExpenses
        self.totalDebtService = totalDebtService
        self.totalOutflows = totalOutflows
        self.periodIncome = periodIncome
        self.freeMargin = freeMargin
        self.deficit = deficit
        self.debtToIncomeRatio = debtToIncomeRatio
        self.totalCommitmentRatio = totalCommitmentRatio
        self.isAnnual = isAnnual
        self.yearStr = yearStr
    }
}

// MARK: - FinancialDataStore

@MainActor
public final class FinancialDataStore: ObservableObject {
    @Published public var accounts: [BankAccount] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var categories: [CategoryItem] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var transactions: [FinancialTransaction] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var investments: [InvestmentItem] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var debts: [DebtItem] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var contracts: [CreditContract] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var amortizationPlans: [AmortizationPlan] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var budgetProjectionScenario: BudgetProjectionScenario = .withPlanning {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var provisions: [CategoryProvision] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var categoryQuotas: [CategoryQuotaRule] = [] {
        didSet { invalidateDerivedCaches() }
    }
    @Published public var llmConfig: LLMConfiguration = LLMConfiguration()
    @Published public var chatHistory: [ChatMessage] = []
    @Published public var selectedMonth: Date = Date()
    /// Contador monotônico de revisão de dados para garantir invalidação de cache O(1) e atualização real-time de listas SwiftUI.
    @Published public private(set) var dataRevision: UInt64 = 0

    /// Data simulada para testes e cenários hipotéticos de tempo. Quando `nil`, usa `Date()`.
    @Published public var simulatedCurrentDate: Date? = nil {
        didSet {
            invalidateDerivedCaches()
            validateExpiredAmortizationPlans()
        }
    }

    // MARK: - Caches Derivados O(1) em Memória (Invalidados Automaticamente a Cada Mutação)

    private var isBatchLoading: Bool = false
    private var cachedCategoriesById: [UUID: CategoryItem]? = nil
    private var cachedAccountsById: [UUID: BankAccount]? = nil
    private var cachedTransactionsByYM: [Int: [FinancialTransaction]]? = nil
    private var cachedTransactionsByYear: [Int: [FinancialTransaction]]? = nil
    private var cachedLoanProjections: [UUID: LoanProjectionResult] = [:]
    private var cachedActiveProjectionSnapshot: (shadowedTxIds: Set<UUID>, projectedInstallmentAmounts: [UUID: Double], payoffTxIds: Set<UUID>)? = nil
    private var cachedProvisionEnvelopesByYM: [Int: [CategoryProvisionEnvelope]] = [:]
    private var cachedQuotaEnvelopesByYM: [Int: [CategoryQuotaEnvelope]] = [:]
    private var cachedTotalRemainingProvisionByYM: [Int: Double] = [:]
    private var cachedAccumulatedBalanceByKey: [Int: Double] = [:]
    private var cachedKPISummaryByKey: [Int: UnifiedFinancialKPISummary] = [:]
    private var maxMaterializedRecurringDate: Date? = nil

    public func invalidateDerivedCaches() {
        cachedCategoriesById = nil
        cachedAccountsById = nil
        cachedTransactionsByYM = nil
        cachedTransactionsByYear = nil
        cachedLoanProjections.removeAll(keepingCapacity: true)
        cachedActiveProjectionSnapshot = nil
        cachedProvisionEnvelopesByYM.removeAll(keepingCapacity: true)
        cachedQuotaEnvelopesByYM.removeAll(keepingCapacity: true)
        cachedTotalRemainingProvisionByYM.removeAll(keepingCapacity: true)
        cachedAccumulatedBalanceByKey.removeAll(keepingCapacity: true)
        cachedKPISummaryByKey.removeAll(keepingCapacity: true)
        maxMaterializedRecurringDate = nil
        if !isBatchLoading {
            dataRevision &+= 1
        }
    }

    private func ensureTransactionIndexesBuilt() {
        guard cachedTransactionsByYM == nil || cachedTransactionsByYear == nil else { return }
        var byYM: [Int: [FinancialTransaction]] = [:]
        var byYear: [Int: [FinancialTransaction]] = [:]
        byYM.reserveCapacity(24)
        byYear.reserveCapacity(4)

        for tx in transactions {
            let comps = calendar.dateComponents([.year, .month], from: tx.date)
            if let y = comps.year, let m = comps.month {
                let ymKey = y * 100 + m
                byYM[ymKey, default: []].append(tx)
                byYear[y, default: []].append(tx)
            }
        }
        cachedTransactionsByYM = byYM
        cachedTransactionsByYear = byYear
    }

    /// Retorna a data corrente efetiva (real ou simulada via `simulatedCurrentDate`).
    public var effectiveCurrentDate: Date {
        simulatedCurrentDate ?? Date()
    }
    @Published public var selectedDestination: SidebarDestination = .dashboard
    @Published public var selectedTransactionsSubmenu: TransactionsSubmenu = .all
    @Published public var dashboardPeriodMode: DashboardPeriodMode = .monthly
    @Published public var selectedSettingsSection: SettingsSection = .general
    @Published public var isAIChatPresented: Bool = false
    @Published public var isLLMInstallAlertPresented: Bool = false
    @Published public var pendingAIFeatureName: String = ""

    private var cloudSyncCancellable: AnyCancellable? = nil
    public weak var cloudSyncService: CloudSyncService? {
        didSet {
            cloudSyncCancellable = cloudSyncService?.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }
    }

    public let persistenceEnvironment: PersistenceEnvironment
    public let storageDirectory: URL
    public let databaseFileURL: URL
    public let attachmentsDirectoryURL: URL
    public let modelsDirectoryURL: URL
    private let legacyReleaseDatabaseFileURL: URL?

    private var hasSeededInitialStatement: Bool = false
    public let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "pt_BR")
        return cal
    }()

    public init(
        customDirectory: URL? = nil,
        environment: PersistenceEnvironment = .current,
        baseAppSupportDirectory: URL? = nil,
        seedStatementOnFirstLaunch: Bool = false
    ) {
        self.persistenceEnvironment = environment
        if let customDirectory {
            self.storageDirectory = customDirectory
            self.databaseFileURL = customDirectory.appendingPathComponent(environment.databaseFileName)
            self.legacyReleaseDatabaseFileURL = environment == .release
                ? customDirectory.appendingPathComponent("database.json")
                : nil
        } else {
            let appSupport = baseAppSupportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            switch environment {
            case .release:
                // Produção (Release): ~/Library/Application Support/FinSense/financial_database.json
                let prodDir = appSupport.appendingPathComponent("FinSense", isDirectory: true)
                self.storageDirectory = prodDir
                self.databaseFileURL = prodDir.appendingPathComponent("financial_database.json")
                self.legacyReleaseDatabaseFileURL = prodDir.appendingPathComponent("database.json")
            case .debug:
                // Desenvolvimento (Debug): diretório e arquivo 100% isolados, sem tocar no banco de produção
                let debugDir = appSupport.appendingPathComponent("FinSense-Debug", isDirectory: true)
                self.storageDirectory = debugDir
                self.databaseFileURL = debugDir.appendingPathComponent("financial_database_debug.json")
                self.legacyReleaseDatabaseFileURL = nil
            }
        }
        self.attachmentsDirectoryURL = storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        self.modelsDirectoryURL = storageDirectory.appendingPathComponent("Models", isDirectory: true)

        createDirectoriesIfNeeded()
        loadOrInitialize(seedStatementOnFirstLaunch: seedStatementOnFirstLaunch)
    }

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    public func loadOrInitialize(seedStatementOnFirstLaunch: Bool = false) {
        let fm = FileManager.default
        let sourceURL: URL? = {
            if fm.fileExists(atPath: databaseFileURL.path) {
                return databaseFileURL
            }
            if persistenceEnvironment == .release,
               let legacyURL = legacyReleaseDatabaseFileURL,
               fm.fileExists(atPath: legacyURL.path) {
                return legacyURL
            }
            return nil
        }()

        if let url = sourceURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(FinancialDatabaseSnapshot.self, from: data),
           decoded.schemaVersion == 2 {
            self.accounts = decoded.accounts
            self.categories = decoded.categories
            self.transactions = decoded.transactions
            self.investments = decoded.investments
            self.debts = decoded.debts
            self.contracts = decoded.contracts
            self.amortizationPlans = decoded.amortizationPlans ?? []
            if let savedScenario = decoded.budgetProjectionScenario {
                self.budgetProjectionScenario = savedScenario
            }
            self.provisions = decoded.provisions ?? []
            self.categoryQuotas = decoded.categoryQuotas ?? []
            self.llmConfig = decoded.llmConfig
            self.chatHistory = decoded.chatHistory
            self.hasSeededInitialStatement = decoded.hasSeededInitialStatement

            // Migrar e garantir categoria "Aportes e investimentos" para depósitos e cotas de investimento
            let aporteCatId = self.investmentDepositCategoryId()
            var mutatedData = false
            for i in 0..<self.transactions.count {
                if self.transactions[i].transactionOrigin == .investmentDeposit && self.transactions[i].categoryId != aporteCatId {
                    self.transactions[i].categoryId = aporteCatId
                    mutatedData = true
                }
            }
            for i in 0..<self.categoryQuotas.count {
                if self.categoryQuotas[i].quotaType == .investment && self.categoryQuotas[i].categoryId != aporteCatId {
                    self.categoryQuotas[i].categoryId = aporteCatId
                    mutatedData = true
                }
            }
            if migrateExistingSantanderContractsIfNeeded() {
                mutatedData = true
            }
            if migrateExistingCaixaContractsIfNeeded() {
                mutatedData = true
            }
            for plan in self.amortizationPlans {
                syncPlannedAmortizationTransactions(for: plan.contractId, saveAfter: false)
            }
            if mutatedData || !self.amortizationPlans.isEmpty {
                save()
            }
            validateExpiredAmortizationPlans()
        } else {
            // Instalação limpa: sempre inicia zerado, apenas com as categorias padrões, sem despesas ou contas.
            self.categories = DefaultCategoriesCatalog.buildInitialCategories()
            self.accounts = []
            self.transactions = []
            self.investments = []
            self.debts = []
            self.contracts = []
            self.amortizationPlans = []
            self.provisions = []
            self.categoryQuotas = []
            self.llmConfig = LLMConfiguration()
            self.chatHistory = [
                ChatMessage(
                    role: .assistant,
                    content: "Olá! Sou seu assistente financeiro local. Tenho acesso completo às suas contas, transações, investimentos, empréstimos, financiamentos e dívidas. Você pode me pedir análises de períodos específicos, projeções de saldo futuro ou estimativas para quitação de dívidas!"
                )
            ]
            if seedStatementOnFirstLaunch {
                self.accounts = Self.buildDefaultAccounts()
                self.investments = Self.buildDefaultInvestments(accounts: self.accounts)
                self.debts = Self.buildDefaultSampleDebts()
                seedAttachedItauStatementIfNeeded()
            }
            save()
        }
    }

    public func save() {
        let snapshot = FinancialDatabaseSnapshot(
            schemaVersion: 2,
            accounts: accounts,
            categories: categories,
            transactions: transactions,
            investments: investments,
            debts: debts,
            contracts: contracts,
            amortizationPlans: amortizationPlans,
            budgetProjectionScenario: budgetProjectionScenario,
            provisions: provisions,
            categoryQuotas: categoryQuotas,
            llmConfig: llmConfig,
            chatHistory: chatHistory,
            hasSeededInitialStatement: hasSeededInitialStatement
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: databaseFileURL, options: .atomic)
        }
    }

    // MARK: - Mandatory Local LLM Installation Check & Reset from Scratch ("Recomeçar do zero")

    public var hasInstalledLLMModel: Bool {
        !llmConfig.downloadedModels.isEmpty && llmConfig.selectedModel != nil
    }

    /// Qualquer opção que use IA obrigatoriamente solicita a instalação caso o usuário tente usar sem ter instalado previamente.
    @discardableResult
    public func requireInstalledLLM(forFeature featureName: String, action: () -> Void) -> Bool {
        if hasInstalledLLMModel {
            action()
            return true
        } else {
            pendingAIFeatureName = featureName
            isLLMInstallAlertPresented = true
            return false
        }
    }

    public func openAIChat() {
        _ = requireInstalledLLM(forFeature: "Chat Financeiro com IA Local") {
            isAIChatPresented = true
        }
    }

    public func navigateToLLMInstallSettings() {
        isLLMInstallAlertPresented = false
        isAIChatPresented = false
        selectedDestination = .settings
        selectedSettingsSection = .llm
    }

    /// Recomeçar do zero: deleta da base todos os itens selecionados pelo usuário.
    public func resetSelectedData(_ targets: Set<ResetDataTarget>) {
        if targets.contains(.transactions) {
            transactions.removeAll()
            hasSeededInitialStatement = false
        }
        if targets.contains(.accounts) {
            accounts.removeAll()
        }
        if targets.contains(.categories) {
            categories.removeAll()
            provisions.removeAll()
            categoryQuotas.removeAll()
        }
        if targets.contains(.investments) {
            investments.removeAll()
            if !targets.contains(.transactions) {
                transactions.removeAll { $0.linkedInvestmentId != nil }
            }
        }
        if targets.contains(.loans) {
            let loanIds = Set(contracts.filter { $0.kind == .loan }.map(\.id))
            contracts.removeAll { $0.kind == .loan }
            amortizationPlans.removeAll { loanIds.contains($0.contractId) }
            if !targets.contains(.transactions) {
                transactions.removeAll { tx in
                    guard let cid = tx.linkedContractId else { return false }
                    return loanIds.contains(cid)
                }
            }
        }
        if targets.contains(.financings) {
            let finIds = Set(contracts.filter { $0.kind == .financing }.map(\.id))
            contracts.removeAll { $0.kind == .financing }
            amortizationPlans.removeAll { finIds.contains($0.contractId) }
            if !targets.contains(.transactions) {
                transactions.removeAll { tx in
                    guard let cid = tx.linkedContractId else { return false }
                    return finIds.contains(cid)
                }
            }
        }
        if targets.contains(.debts) {
            debts.removeAll()
            if !targets.contains(.transactions) {
                transactions.removeAll { $0.linkedDebtId != nil }
            }
        }
        if targets.contains(.aiModelsAndChat) {
            for model in llmConfig.downloadedModels {
                let fileURL = URL(fileURLWithPath: model.localPath)
                let parentDir = fileURL.deletingLastPathComponent()
                try? FileManager.default.removeItem(at: fileURL)
                if parentDir.lastPathComponent.contains("__") {
                    try? FileManager.default.removeItem(at: parentDir)
                }
            }
            llmConfig.downloadedModels.removeAll()
            llmConfig.selectedModelId = nil
            chatHistory = [
                ChatMessage(
                    role: .assistant,
                    content: "Olá! Sou seu assistente financeiro local. Tenho acesso completo às suas contas, transações, investimentos, empréstimos, financiamentos e dívidas."
                )
            ]
        }
        save()
        cloudSyncService?.resetSyncState()
    }

    // MARK: - Complete Database Export (Exceto Modelo de IA) & Fast Selective Validated Import

    private static let compressedArchiveMagicHeader = Data([0x46, 0x43, 0x42, 0x4B]) // "FCBK"

    /// Coleta todos os arquivos de assets (imagens personalizadas de contas/dívidas e comprovantes em `Attachments/`),
    /// excluindo estritamente qualquer modelo de IA (`Models/`).
    public func collectExportableAssets() -> [ExportedAssetFile] {
        let fm = FileManager.default
        let modelsDirStandardized = modelsDirectoryURL.standardizedFileURL.path
        var collectedByFileName: [String: ExportedAssetFile] = [:]

        func tryAddAsset(atPath rawPath: String) {
            guard !rawPath.isEmpty else { return }
            let url = URL(fileURLWithPath: rawPath).standardizedFileURL
            // Nunca inclui arquivos do diretório de modelos de IA
            guard !url.path.hasPrefix(modelsDirStandardized) else { return }
            let ext = url.pathExtension.lowercased()
            guard ext != "gguf" && ext != "safetensors" && ext != "bin" else { return }
            let fileName = url.lastPathComponent
            guard !fileName.isEmpty, collectedByFileName[fileName] == nil else { return }
            guard fm.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty else { return }
            collectedByFileName[fileName] = ExportedAssetFile(
                fileName: fileName,
                originalPath: rawPath,
                data: data
            )
        }

        if let attachmentURLs = try? fm.contentsOfDirectory(
            at: attachmentsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in attachmentURLs {
                tryAddAsset(atPath: fileURL.path)
            }
        }

        for acc in accounts {
            if let path = acc.customImagePath { tryAddAsset(atPath: path) }
        }
        for debt in debts {
            if let path = debt.customImagePath { tryAddAsset(atPath: path) }
        }
        for tx in transactions {
            if let path = tx.attachmentPath { tryAddAsset(atPath: path) }
        }

        return collectedByFileName.values.sorted { $0.fileName < $1.fileName }
    }

    /// Constrói o snapshot completo da base de dados exportando todas as entidades (incluindo contas, categorias e assets),
    /// exceto modelos de IA local.
    public func buildFullExportSnapshot() -> FinancialDatabaseSnapshot {
        FinancialDatabaseSnapshot(
            schemaVersion: 2,
            accounts: accounts,
            categories: categories,
            transactions: transactions,
            investments: investments,
            debts: debts,
            contracts: contracts,
            amortizationPlans: amortizationPlans,
            budgetProjectionScenario: budgetProjectionScenario,
            provisions: provisions,
            categoryQuotas: categoryQuotas,
            assets: collectExportableAssets(),
            llmConfig: LLMConfiguration(),
            chatHistory: [],
            hasSeededInitialStatement: false
        )
    }

    /// Exporta toda a base de dados (exceto modelos de IA) em formato compacto e eficiente (com compressão binária LZFSE por padrão).
    public func exportFullDatabaseArchive(compress: Bool = true) -> Data? {
        let snapshot = buildFullExportSnapshot()
        let encoder = JSONEncoder()
        // Sem prettyPrinted para máxima velocidade de serialização e menor tamanho em memória
        guard let rawJSON = try? encoder.encode(snapshot) else { return nil }
        if compress,
           let compressed = try? (rawJSON as NSData).compressed(using: .lzfse) as Data {
            var archive = Self.compressedArchiveMagicHeader
            archive.append(compressed)
            return archive
        }
        return rawJSON
    }

    /// Constrói um snapshot contendo exclusivamente as entidades selecionadas para exportação granular.
    public func buildGranularExportSnapshot(targets: Set<ExportDataTarget>) -> FinancialDatabaseSnapshot {
        let exportedContracts = contracts.filter { contract in
            switch contract.kind {
            case .loan:
                return targets.contains(.loans)
            case .financing:
                return targets.contains(.financings)
            }
        }
        let exportedContractIds = Set(exportedContracts.map(\.id))
        let exportedPlans = amortizationPlans.filter { exportedContractIds.contains($0.contractId) }

        return FinancialDatabaseSnapshot(
            schemaVersion: 2,
            accounts: targets.contains(.accounts) ? accounts : [],
            categories: targets.contains(.categories) ? categories : [],
            transactions: targets.contains(.transactions) ? transactions : [],
            investments: targets.contains(.investments) ? investments : [],
            debts: targets.contains(.debts) ? debts : [],
            contracts: exportedContracts,
            amortizationPlans: exportedPlans,
            budgetProjectionScenario: (targets.contains(.loans) || targets.contains(.financings)) ? budgetProjectionScenario : nil,
            provisions: targets.contains(.provisions) ? provisions : [],
            categoryQuotas: targets.contains(.provisions) ? categoryQuotas : [],
            assets: targets.contains(.assets) ? collectExportableAssets() : nil,
            llmConfig: LLMConfiguration(),
            chatHistory: [],
            hasSeededInitialStatement: false
        )
    }

    /// Gera os bytes JSON compactos da exportação contendo as entidades marcadas.
    public func exportGranularDatabaseJSON(targets: Set<ExportDataTarget> = Set(ExportDataTarget.allCases)) -> Data? {
        let snapshot = buildGranularExportSnapshot(targets: targets)
        let encoder = JSONEncoder()
        return try? encoder.encode(snapshot)
    }

    private static func normalizeKey(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transactionSignature(name: String, amount: Double, date: Date, type: TransactionType) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
        let cents = Int((abs(amount) * 100.0).rounded())
        return "\(type.rawValue)|\(dayKey)|\(cents)|\(Self.normalizeKey(name))"
    }

    /// Verifica se uma transação candidata já existe no banco de dados ativo (anti-duplicidade).
    public func isDuplicateTransaction(
        originalId: UUID? = nil,
        description: String,
        amount: Double,
        date: Date,
        type: TransactionType
    ) -> Bool {
        if let originalId, transactions.contains(where: { $0.id == originalId }) {
            return true
        }
        let normCandidate = Self.normalizeKey(description)
        let candidateCents = Int((abs(amount) * 100.0).rounded())

        return transactions.contains { existing in
            guard existing.type == type else { return false }
            guard Int((abs(existing.amount) * 100.0).rounded()) == candidateCents else { return false }
            guard calendar.isDate(existing.date, inSameDayAs: date) else { return false }
            return Self.normalizeKey(existing.name) == normCandidate
        }
    }

    /// Descomprime (caso seja arquivo binário `FCBK` comprimido com LZFSE) e decodifica qualquer arquivo válido de importação
    /// em um `FinancialDatabaseSnapshot` unificado.
    public func decodeImportDataToSnapshot(_ data: Data) throws -> FinancialDatabaseSnapshot {
        let payloadData: Data
        if data.count > Self.compressedArchiveMagicHeader.count,
           data.prefix(Self.compressedArchiveMagicHeader.count) == Self.compressedArchiveMagicHeader {
            let compressedBody = data.dropFirst(Self.compressedArchiveMagicHeader.count)
            if let decompressed = try? (compressedBody as NSData).decompressed(using: .lzfse) as Data {
                payloadData = decompressed
            } else {
                throw NSError(
                    domain: "FinancialDataStore.Import",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Não foi possível descomprimir o pacote de backup da base de dados."]
                )
            }
        } else {
            payloadData = data
        }

        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(FinancialDatabaseSnapshot.self, from: payloadData) {
            return snapshot
        }
        if let directTransactions = try? decoder.decode([FinancialTransaction].self, from: payloadData) {
            return FinancialDatabaseSnapshot(schemaVersion: 2, transactions: directTransactions)
        }

        // Suporte a JSON externo simplificado (array de objetos de despesas/transações)
        guard let jsonObj = try? JSONSerialization.jsonObject(with: payloadData, options: []) else {
            throw NSError(
                domain: "FinancialDataStore.Import",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Arquivo de importação inválido. Selecione um backup exportado pelo app (.fcbackup / .json) ou um JSON de transações."]
            )
        }

        let dictArray: [[String: Any]]
        if let arr = jsonObj as? [[String: Any]] {
            dictArray = arr
        } else if let root = jsonObj as? [String: Any],
                  let nested = (root["transactions"] ?? root["expenses"] ?? root["gastos"]) as? [[String: Any]] {
            dictArray = nested
        } else {
            throw NSError(
                domain: "FinancialDataStore.Import",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Formato JSON inválido. Forneça um backup da base de dados ou uma lista de transações."]
            )
        }

        var catByNormName: [String: UUID] = [:]
        for cat in categories {
            catByNormName[Self.normalizeKey(cat.name)] = cat.id
        }
        var accByNormName: [String: UUID] = [:]
        for acc in accounts {
            accByNormName[Self.normalizeKey(acc.name)] = acc.id
        }
        let defaultAccId = accounts.first?.id ?? UUID()
        let isoFormatter = ISO8601DateFormatter()
        var parsedTransactions: [FinancialTransaction] = []
        parsedTransactions.reserveCapacity(dictArray.count)

        for item in dictArray {
            let desc = (item["name"] as? String)
                ?? (item["description"] as? String)
                ?? (item["descricao"] as? String)
                ?? (item["title"] as? String)
                ?? "Gasto Importado"
            let details = (item["details"] as? String)
                ?? (item["detalhes"] as? String)
                ?? (item["notes"] as? String)
                ?? ""
            let rawAmount: Double = {
                if let d = item["amount"] as? Double { return abs(d) }
                if let d = item["valor"] as? Double { return abs(d) }
                if let i = item["amount"] as? Int { return Double(abs(i)) }
                if let i = item["valor"] as? Int { return Double(abs(i)) }
                if let s = (item["amount"] ?? item["valor"]) as? String {
                    return abs(BRLFormatters.parseCurrencyInput(s))
                }
                return 0.0
            }()
            guard rawAmount > 0 else { continue }

            let parsedDate: Date = {
                if let timeInterval = item["date"] as? TimeInterval {
                    return Date(timeIntervalSinceReferenceDate: timeInterval)
                }
                if let dateStr = (item["date"] ?? item["data"]) as? String {
                    if let d = BRLFormatters.shortDateFormatter.date(from: dateStr) {
                        return d
                    }
                    if let d = isoFormatter.date(from: dateStr) {
                        return d
                    }
                }
                return Date()
            }()

            let typeStr = ((item["type"] ?? item["tipo"]) as? String)?.lowercased() ?? "despesa"
            let txType: TransactionType = (typeStr.contains("receita") || typeStr.contains("income")) ? .income : .expense
            let isPaid = (item["isPaid"] as? Bool) ?? (item["pago"] as? Bool) ?? true

            let catId: UUID = {
                if let cidStr = (item["categoryId"] as? String), let uuid = UUID(uuidString: cidStr),
                   categories.contains(where: { $0.id == uuid }) {
                    return uuid
                }
                if let catName = (item["category"] ?? item["categoria"]) as? String,
                   let matchedId = catByNormName[Self.normalizeKey(catName)] {
                    return matchedId
                }
                return inferCategoryId(forTitle: desc, type: txType)
            }()

            let accId: UUID = {
                if let aidStr = (item["accountId"] as? String), let uuid = UUID(uuidString: aidStr),
                   accounts.contains(where: { $0.id == uuid }) {
                    return uuid
                }
                if let accName = (item["account"] ?? item["conta"]) as? String,
                   let matchedId = accByNormName[Self.normalizeKey(accName)] {
                    return matchedId
                }
                return defaultAccId
            }()

            let txId = (item["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            parsedTransactions.append(
                FinancialTransaction(
                    id: txId,
                    name: desc,
                    details: details,
                    amount: rawAmount,
                    date: parsedDate,
                    type: txType,
                    isPaid: isPaid,
                    categoryId: catId,
                    accountId: accId
                )
            )
        }

        return FinancialDatabaseSnapshot(schemaVersion: 2, transactions: parsedTransactions)
    }

    /// Prepara e analisa um arquivo de importação em tempo $O(N)$ usando tabelas hash,
    /// identificando a contagem total, novos itens e duplicatas para cada grupo selecionável pelo usuário.
    public func prepareDatabaseImportPackage(from data: Data) throws -> PreparedDatabaseImportPackage {
        let snapshot = try decodeImportDataToSnapshot(data)

        // Índices hash O(1) da base ativa atual
        let existingAccIds = Set(accounts.map(\.id))
        let existingAccKeys = Set(accounts.map { "\(Self.normalizeKey($0.name))|\($0.bankPresetId ?? "")" })

        let existingCatIds = Set(categories.map(\.id))
        let existingCatKeys = Set(categories.map { "\($0.type.rawValue)|\(Self.normalizeKey($0.name))" })

        let existingTxIds = Set(transactions.map(\.id))
        var preExistingTxSigCounts: [String: Int] = [:]
        preExistingTxSigCounts.reserveCapacity(transactions.count)
        for tx in transactions {
            let sig = transactionSignature(name: tx.name, amount: tx.amount, date: tx.date, type: tx.type)
            preExistingTxSigCounts[sig, default: 0] += 1
        }

        let existingInvIds = Set(investments.map(\.id))
        let existingInvKeys = Set(investments.map { "\(Self.normalizeKey($0.groupName))|\(Self.normalizeKey($0.name))" })

        let existingDebtIds = Set(debts.map(\.id))
        let existingDebtKeys = Set(debts.map { "\(Self.normalizeKey($0.name))|\(Int((abs($0.originalAmount) * 100).rounded()))" })

        let existingContractIds = Set(contracts.map(\.id))
        let existingContractKeys = Set(contracts.map {
            "\($0.kind.rawValue)|\(Self.normalizeKey($0.name))|\($0.contractNumber ?? "")|\(Int((abs($0.installmentAmount) * 100).rounded()))"
        })

        let existingProvIds = Set(provisions.map(\.id))
        let existingProvKeys = Set(provisions.map { "\($0.categoryId.uuidString)|\($0.yearMonthKey)" })

        let existingQuotaIds = Set(categoryQuotas.map(\.id))
        let existingQuotaKeys = Set(categoryQuotas.map { "\($0.seriesId.uuidString)|\($0.yearMonthKey)|\(Self.normalizeKey($0.name))" })

        var analyses: [ExportDataTarget: ImportTargetAnalysis] = [:]

        // 1. Contas
        let accDups = snapshot.accounts.filter {
            existingAccIds.contains($0.id) || existingAccKeys.contains("\(Self.normalizeKey($0.name))|\($0.bankPresetId ?? "")")
        }.count
        analyses[.accounts] = ImportTargetAnalysis(
            target: .accounts,
            totalCount: snapshot.accounts.count,
            newCount: max(0, snapshot.accounts.count - accDups),
            duplicateCount: accDups
        )

        // 2. Categorias
        let catDups = snapshot.categories.filter {
            existingCatIds.contains($0.id) || existingCatKeys.contains("\($0.type.rawValue)|\(Self.normalizeKey($0.name))")
        }.count
        analyses[.categories] = ImportTargetAnalysis(
            target: .categories,
            totalCount: snapshot.categories.count,
            newCount: max(0, snapshot.categories.count - catDups),
            duplicateCount: catDups
        )

        // 3. Transações
        var txDups = 0
        var remainingPreExistingTxSigCounts = preExistingTxSigCounts
        for tx in snapshot.transactions {
            let sig = transactionSignature(name: tx.name, amount: tx.amount, date: tx.date, type: tx.type)
            if existingTxIds.contains(tx.id) {
                txDups += 1
                if let count = remainingPreExistingTxSigCounts[sig], count > 0 {
                    remainingPreExistingTxSigCounts[sig] = count - 1
                }
            } else if let count = remainingPreExistingTxSigCounts[sig], count > 0 {
                remainingPreExistingTxSigCounts[sig] = count - 1
                txDups += 1
            }
        }
        analyses[.transactions] = ImportTargetAnalysis(
            target: .transactions,
            totalCount: snapshot.transactions.count,
            newCount: max(0, snapshot.transactions.count - txDups),
            duplicateCount: txDups
        )

        // 4. Investimentos
        let invDups = snapshot.investments.filter {
            existingInvIds.contains($0.id) || existingInvKeys.contains("\(Self.normalizeKey($0.groupName))|\(Self.normalizeKey($0.name))")
        }.count
        analyses[.investments] = ImportTargetAnalysis(
            target: .investments,
            totalCount: snapshot.investments.count,
            newCount: max(0, snapshot.investments.count - invDups),
            duplicateCount: invDups
        )

        // 5. Empréstimos
        let snapLoans = snapshot.contracts.filter { $0.kind == .loan }
        let loanDups = snapLoans.filter {
            existingContractIds.contains($0.id) ||
            existingContractKeys.contains("\($0.kind.rawValue)|\(Self.normalizeKey($0.name))|\($0.contractNumber ?? "")|\(Int((abs($0.installmentAmount) * 100).rounded()))")
        }.count
        analyses[.loans] = ImportTargetAnalysis(
            target: .loans,
            totalCount: snapLoans.count,
            newCount: max(0, snapLoans.count - loanDups),
            duplicateCount: loanDups
        )

        // 6. Financiamentos
        let snapFinancings = snapshot.contracts.filter { $0.kind == .financing }
        let finDups = snapFinancings.filter {
            existingContractIds.contains($0.id) ||
            existingContractKeys.contains("\($0.kind.rawValue)|\(Self.normalizeKey($0.name))|\($0.contractNumber ?? "")|\(Int((abs($0.installmentAmount) * 100).rounded()))")
        }.count
        analyses[.financings] = ImportTargetAnalysis(
            target: .financings,
            totalCount: snapFinancings.count,
            newCount: max(0, snapFinancings.count - finDups),
            duplicateCount: finDups
        )

        // 7. Dívidas
        let debtDups = snapshot.debts.filter {
            existingDebtIds.contains($0.id) ||
            existingDebtKeys.contains("\(Self.normalizeKey($0.name))|\(Int((abs($0.originalAmount) * 100).rounded()))")
        }.count
        analyses[.debts] = ImportTargetAnalysis(
            target: .debts,
            totalCount: snapshot.debts.count,
            newCount: max(0, snapshot.debts.count - debtDups),
            duplicateCount: debtDups
        )

        // 8. Previsões e Cotas
        let snapProvs = snapshot.provisions ?? []
        let snapQuotas = snapshot.categoryQuotas ?? []
        let provDups = snapProvs.filter {
            existingProvIds.contains($0.id) || existingProvKeys.contains("\($0.categoryId.uuidString)|\($0.yearMonthKey)")
        }.count
        let quotaDups = snapQuotas.filter {
            existingQuotaIds.contains($0.id) || existingQuotaKeys.contains("\($0.seriesId.uuidString)|\($0.yearMonthKey)|\(Self.normalizeKey($0.name))")
        }.count
        let totalProvsAndQuotas = snapProvs.count + snapQuotas.count
        let totalProvQuotaDups = provDups + quotaDups
        analyses[.provisions] = ImportTargetAnalysis(
            target: .provisions,
            totalCount: totalProvsAndQuotas,
            newCount: max(0, totalProvsAndQuotas - totalProvQuotaDups),
            duplicateCount: totalProvQuotaDups
        )

        // 9. Assets
        let snapAssets = snapshot.assets ?? []
        let fm = FileManager.default
        let assetDups = snapAssets.filter { asset in
            let dest = attachmentsDirectoryURL.appendingPathComponent(asset.fileName)
            return fm.fileExists(atPath: dest.path)
        }.count
        analyses[.assets] = ImportTargetAnalysis(
            target: .assets,
            totalCount: snapAssets.count,
            newCount: max(0, snapAssets.count - assetDups),
            duplicateCount: assetDups
        )

        let nonEmpty = Set(analyses.values.filter { $0.totalCount > 0 }.map(\.target))
        return PreparedDatabaseImportPackage(
            snapshot: snapshot,
            targetAnalyses: analyses,
            availableNonEmptyTargets: nonEmpty
        )
    }

    /// Executa a importação seletiva com validação de duplicidade em $O(1)$, garantia de consistência referencial
    /// (criando/mapeando contas, categorias, contratos e assets referenciados) e atualização de barra de progresso.
    @discardableResult
    public func executeSelectiveDatabaseImport(
        package: PreparedDatabaseImportPackage,
        selectedTargets: Set<ExportDataTarget>,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async -> SelectiveImportExecutionResult {
        onProgress?(0.05, "Preparando índices de validação e consistência...")
        await Task.yield()

        let result = executeSelectiveDatabaseImportCore(
            package: package,
            selectedTargets: selectedTargets,
            onProgress: { pct, msg in
                onProgress?(pct, msg)
            }
        )

        onProgress?(1.0, "Importação concluída com sucesso!")
        await Task.yield()
        return result
    }

    @discardableResult
    public func executeSelectiveDatabaseImportSync(
        package: PreparedDatabaseImportPackage,
        selectedTargets: Set<ExportDataTarget>
    ) -> SelectiveImportExecutionResult {
        executeSelectiveDatabaseImportCore(package: package, selectedTargets: selectedTargets, onProgress: nil)
    }

    private func executeSelectiveDatabaseImportCore(
        package: PreparedDatabaseImportPackage,
        selectedTargets: Set<ExportDataTarget>,
        onProgress: ((Double, String) -> Void)?
    ) -> SelectiveImportExecutionResult {
        let snapshot = package.snapshot
        var res = SelectiveImportExecutionResult()
        let fm = FileManager.default
        try? fm.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)

        // 1. Mapeamento e restauração de Assets (quando .assets está selecionado ou quando uma entidade importada referencia um asset do pacote)
        onProgress?(0.12, "Processando assets e comprovantes...")
        var assetByOriginalPath: [String: ExportedAssetFile] = [:]
        var assetByFileName: [String: ExportedAssetFile] = [:]
        for asset in (snapshot.assets ?? []) {
            assetByOriginalPath[asset.originalPath] = asset
            assetByFileName[asset.fileName] = asset
        }

        var restoredAssetPathsByFileName: [String: String] = [:]
        func restoreAssetIfAvailable(originalPath: String?) -> String? {
            guard let orig = originalPath, !orig.isEmpty else { return nil }
            let fileName = URL(fileURLWithPath: orig).lastPathComponent
            if let alreadyRestored = restoredAssetPathsByFileName[fileName] {
                return alreadyRestored
            }
            if let asset = assetByOriginalPath[orig] ?? assetByFileName[fileName] {
                let targetURL = attachmentsDirectoryURL.appendingPathComponent(asset.fileName)
                if !fm.fileExists(atPath: targetURL.path) {
                    try? asset.data.write(to: targetURL, options: .atomic)
                    res.importedAssets += 1
                } else if selectedTargets.contains(.assets) {
                    res.skippedDuplicatesTotal += 1
                }
                restoredAssetPathsByFileName[asset.fileName] = targetURL.path
                return targetURL.path
            }
            return fm.fileExists(atPath: orig) ? orig : nil
        }

        if selectedTargets.contains(.assets) {
            for asset in (snapshot.assets ?? []) {
                _ = restoreAssetIfAvailable(originalPath: asset.originalPath)
            }
        }

        // 2. Índices de Contas e Importação de Contas
        onProgress?(0.25, "Validando e importando contas bancárias...")
        let sourceAccountsById = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0) })
        var accountIdMap: [UUID: UUID] = [:]
        var existingAccById = Set(accounts.map(\.id))
        var existingAccByKey: [String: UUID] = [:]
        for acc in accounts {
            existingAccByKey["\(Self.normalizeKey(acc.name))|\(acc.bankPresetId ?? "")"] = acc.id
            existingAccByKey[Self.normalizeKey(acc.name)] = acc.id
        }

        func ensureValidAccountId(for sourceAccId: UUID) -> UUID {
            if let mapped = accountIdMap[sourceAccId] { return mapped }
            if existingAccById.contains(sourceAccId) {
                accountIdMap[sourceAccId] = sourceAccId
                return sourceAccId
            }
            if let srcAcc = sourceAccountsById[sourceAccId] {
                let exactKey = "\(Self.normalizeKey(srcAcc.name))|\(srcAcc.bankPresetId ?? "")"
                if let matchedId = existingAccByKey[exactKey] ?? existingAccByKey[Self.normalizeKey(srcAcc.name)] {
                    accountIdMap[sourceAccId] = matchedId
                    return matchedId
                }
                // Cria automaticamente a conta referenciada para manter consistência referencial!
                var newAcc = srcAcc
                newAcc.customImagePath = restoreAssetIfAvailable(originalPath: srcAcc.customImagePath)
                accounts.append(newAcc)
                existingAccById.insert(newAcc.id)
                existingAccByKey[exactKey] = newAcc.id
                existingAccByKey[Self.normalizeKey(newAcc.name)] = newAcc.id
                accountIdMap[sourceAccId] = newAcc.id
                res.autoCreatedDependenciesCount += 1
                return newAcc.id
            }
            if let firstExisting = accounts.first?.id {
                accountIdMap[sourceAccId] = firstExisting
                return firstExisting
            }
            // Se não há nenhuma conta na base e o arquivo não trouxe contas (ex: JSON avulso de gastos), cria uma conta padrão consistente
            let fallbackAcc = BankAccount(
                name: "Conta Principal",
                bankPresetId: "itau",
                iconSymbol: "building.columns.fill",
                colorHex: "#EC7000",
                initialBalance: 0.0
            )
            accounts.append(fallbackAcc)
            existingAccById.insert(fallbackAcc.id)
            existingAccByKey[Self.normalizeKey(fallbackAcc.name)] = fallbackAcc.id
            accountIdMap[sourceAccId] = fallbackAcc.id
            res.autoCreatedDependenciesCount += 1
            return fallbackAcc.id
        }

        if selectedTargets.contains(.accounts) {
            for srcAcc in snapshot.accounts {
                let exactKey = "\(Self.normalizeKey(srcAcc.name))|\(srcAcc.bankPresetId ?? "")"
                if existingAccById.contains(srcAcc.id) {
                    accountIdMap[srcAcc.id] = srcAcc.id
                    res.skippedDuplicatesTotal += 1
                } else if let matchedId = existingAccByKey[exactKey] {
                    accountIdMap[srcAcc.id] = matchedId
                    res.skippedDuplicatesTotal += 1
                } else {
                    var importedAcc = srcAcc
                    importedAcc.customImagePath = restoreAssetIfAvailable(originalPath: srcAcc.customImagePath)
                    accounts.append(importedAcc)
                    existingAccById.insert(importedAcc.id)
                    existingAccByKey[exactKey] = importedAcc.id
                    existingAccByKey[Self.normalizeKey(importedAcc.name)] = importedAcc.id
                    accountIdMap[srcAcc.id] = importedAcc.id
                    res.importedAccounts += 1
                }
            }
        }

        // 3. Índices de Categorias e Importação de Categorias
        onProgress?(0.38, "Validando e importando categorias...")
        let sourceCategoriesById = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0) })
        var categoryIdMap: [UUID: UUID] = [:]
        var existingCatById = Set(categories.map(\.id))
        var existingCatByKey: [String: UUID] = [:]
        for cat in categories {
            existingCatByKey["\(cat.type.rawValue)|\(Self.normalizeKey(cat.name))"] = cat.id
        }

        func ensureValidCategoryId(for sourceCatId: UUID, fallbackType: TransactionType, titleHint: String = "") -> UUID {
            if let mapped = categoryIdMap[sourceCatId] { return mapped }
            if existingCatById.contains(sourceCatId) {
                categoryIdMap[sourceCatId] = sourceCatId
                return sourceCatId
            }
            if let srcCat = sourceCategoriesById[sourceCatId] {
                let key = "\(srcCat.type.rawValue)|\(Self.normalizeKey(srcCat.name))"
                if let matchedId = existingCatByKey[key] {
                    categoryIdMap[sourceCatId] = matchedId
                    return matchedId
                }
                // Cria automaticamente a categoria referenciada para evitar transações/previsões órfãs!
                categories.append(srcCat)
                existingCatById.insert(srcCat.id)
                existingCatByKey[key] = srcCat.id
                categoryIdMap[sourceCatId] = srcCat.id
                res.autoCreatedDependenciesCount += 1
                return srcCat.id
            }
            let inferred = inferCategoryId(forTitle: titleHint, type: fallbackType)
            categoryIdMap[sourceCatId] = inferred
            return inferred
        }

        if selectedTargets.contains(.categories) {
            for srcCat in snapshot.categories {
                let key = "\(srcCat.type.rawValue)|\(Self.normalizeKey(srcCat.name))"
                if existingCatById.contains(srcCat.id) {
                    categoryIdMap[srcCat.id] = srcCat.id
                    res.skippedDuplicatesTotal += 1
                } else if let matchedId = existingCatByKey[key] {
                    categoryIdMap[srcCat.id] = matchedId
                    res.skippedDuplicatesTotal += 1
                } else {
                    categories.append(srcCat)
                    existingCatById.insert(srcCat.id)
                    existingCatByKey[key] = srcCat.id
                    categoryIdMap[srcCat.id] = srcCat.id
                    res.importedCategories += 1
                }
            }
        }

        // 4. Empréstimos e Financiamentos
        onProgress?(0.52, "Validando contratos de empréstimos e financiamentos...")
        var contractIdMap: [UUID: UUID] = [:]
        var newlyImportedContractIds = Set<UUID>()
        var existingContractById = Set(contracts.map(\.id))
        var existingContractByKey: [String: UUID] = [:]
        for c in contracts {
            let key = "\(c.kind.rawValue)|\(Self.normalizeKey(c.name))|\(c.contractNumber ?? "")|\(Int((abs(c.installmentAmount) * 100).rounded()))"
            existingContractByKey[key] = c.id
        }

        for srcContract in snapshot.contracts {
            let isSelectedKind = (srcContract.kind == .loan && selectedTargets.contains(.loans)) ||
                                 (srcContract.kind == .financing && selectedTargets.contains(.financings))
            let key = "\(srcContract.kind.rawValue)|\(Self.normalizeKey(srcContract.name))|\(srcContract.contractNumber ?? "")|\(Int((abs(srcContract.installmentAmount) * 100).rounded()))"

            if existingContractById.contains(srcContract.id) {
                contractIdMap[srcContract.id] = srcContract.id
                if isSelectedKind { res.skippedDuplicatesTotal += 1 }
            } else if let matchedId = existingContractByKey[key] {
                contractIdMap[srcContract.id] = matchedId
                if isSelectedKind { res.skippedDuplicatesTotal += 1 }
            } else if isSelectedKind {
                var newContract = srcContract
                newContract.accountId = ensureValidAccountId(for: srcContract.accountId)
                contracts.append(newContract)
                existingContractById.insert(newContract.id)
                existingContractByKey[key] = newContract.id
                contractIdMap[srcContract.id] = newContract.id
                newlyImportedContractIds.insert(srcContract.id)
                if srcContract.kind == .loan {
                    res.importedLoans += 1
                } else {
                    res.importedFinancings += 1
                }
            }
        }

        // 4.1 Planejamentos de Amortização vinculados aos contratos importados/selecionados
        var importedPlansCount = 0
        if selectedTargets.contains(.loans) || selectedTargets.contains(.financings) {
            var existingPlanIds = Set(amortizationPlans.map(\.id))
            var existingPlanContractIds = Set(amortizationPlans.map(\.contractId))

            for srcPlan in (snapshot.amortizationPlans ?? []) {
                let targetContractId = contractIdMap[srcPlan.contractId] ?? srcPlan.contractId
                guard let targetContract = contracts.first(where: { $0.id == targetContractId }) else { continue }
                let isSelectedKind = (targetContract.kind == .loan && selectedTargets.contains(.loans)) ||
                                     (targetContract.kind == .financing && selectedTargets.contains(.financings))
                guard isSelectedKind else { continue }
                guard !existingPlanIds.contains(srcPlan.id) && !existingPlanContractIds.contains(targetContractId) else {
                    continue
                }

                var newPlan = srcPlan
                newPlan.contractId = targetContractId
                newPlan.items = srcPlan.items.map { item in
                    var mappedItem = item
                    mappedItem.contractId = targetContractId
                    return mappedItem
                }
                amortizationPlans.append(newPlan)
                existingPlanIds.insert(newPlan.id)
                existingPlanContractIds.insert(targetContractId)
                importedPlansCount += 1
            }
        }

        // 5. Investimentos
        onProgress?(0.64, "Validando investimentos e dívidas...")
        var investmentIdMap: [UUID: UUID] = [:]
        var existingInvById = Set(investments.map(\.id))
        var existingInvByKey: [String: UUID] = [:]
        for inv in investments {
            existingInvByKey["\(Self.normalizeKey(inv.groupName))|\(Self.normalizeKey(inv.name))"] = inv.id
        }

        for srcInv in snapshot.investments {
            let key = "\(Self.normalizeKey(srcInv.groupName))|\(Self.normalizeKey(srcInv.name))"
            if existingInvById.contains(srcInv.id) {
                investmentIdMap[srcInv.id] = srcInv.id
                if selectedTargets.contains(.investments) { res.skippedDuplicatesTotal += 1 }
            } else if let matchedId = existingInvByKey[key] {
                investmentIdMap[srcInv.id] = matchedId
                if selectedTargets.contains(.investments) { res.skippedDuplicatesTotal += 1 }
            } else if selectedTargets.contains(.investments) {
                var newInv = srcInv
                newInv.investmentAccountId = ensureValidAccountId(for: srcInv.investmentAccountId)
                investments.append(newInv)
                existingInvById.insert(newInv.id)
                existingInvByKey[key] = newInv.id
                investmentIdMap[srcInv.id] = newInv.id
                res.importedInvestments += 1
            }
        }

        // 6. Dívidas
        var debtIdMap: [UUID: UUID] = [:]
        var existingDebtById = Set(debts.map(\.id))
        var existingDebtByKey: [String: UUID] = [:]
        for d in debts {
            existingDebtByKey["\(Self.normalizeKey(d.name))|\(Int((abs(d.originalAmount) * 100).rounded()))"] = d.id
        }

        for srcDebt in snapshot.debts {
            let key = "\(Self.normalizeKey(srcDebt.name))|\(Int((abs(srcDebt.originalAmount) * 100).rounded()))"
            if existingDebtById.contains(srcDebt.id) {
                debtIdMap[srcDebt.id] = srcDebt.id
                if selectedTargets.contains(.debts) { res.skippedDuplicatesTotal += 1 }
            } else if let matchedId = existingDebtByKey[key] {
                debtIdMap[srcDebt.id] = matchedId
                if selectedTargets.contains(.debts) { res.skippedDuplicatesTotal += 1 }
            } else if selectedTargets.contains(.debts) {
                var newDebt = srcDebt
                newDebt.customImagePath = restoreAssetIfAvailable(originalPath: srcDebt.customImagePath)
                if let paidAccId = srcDebt.paidFromAccountId {
                    newDebt.paidFromAccountId = ensureValidAccountId(for: paidAccId)
                }
                debts.append(newDebt)
                existingDebtById.insert(newDebt.id)
                existingDebtByKey[key] = newDebt.id
                debtIdMap[srcDebt.id] = newDebt.id
                res.importedDebts += 1
            }
        }

        // 7. Transações (ou parcelas vinculadas a contratos recém-importados para manter consistência das parcelas restantes)
        onProgress?(0.78, "Importando transações e validando vínculos (\(snapshot.transactions.count) registros)...")
        let shouldImportAllTransactions = selectedTargets.contains(.transactions)
        if shouldImportAllTransactions || !newlyImportedContractIds.isEmpty {
            let preExistingTxIds = Set(transactions.map(\.id))
            var preExistingTxSigCounts: [String: Int] = [:]
            preExistingTxSigCounts.reserveCapacity(transactions.count)
            for tx in transactions {
                let sig = transactionSignature(name: tx.name, amount: tx.amount, date: tx.date, type: tx.type)
                preExistingTxSigCounts[sig, default: 0] += 1
            }
            var currentTxIds = preExistingTxIds

            for srcTx in snapshot.transactions {
                let isLinkedToNewContract = srcTx.linkedContractId.map { newlyImportedContractIds.contains($0) } ?? false
                guard shouldImportAllTransactions || isLinkedToNewContract else { continue }

                let sig = transactionSignature(name: srcTx.name, amount: srcTx.amount, date: srcTx.date, type: srcTx.type)
                let isPreExistingDuplicate: Bool = {
                    if preExistingTxIds.contains(srcTx.id) {
                        if let count = preExistingTxSigCounts[sig], count > 0 {
                            preExistingTxSigCounts[sig] = count - 1
                        }
                        return true
                    }
                    if let count = preExistingTxSigCounts[sig], count > 0 {
                        preExistingTxSigCounts[sig] = count - 1
                        return true
                    }
                    return false
                }()

                if isPreExistingDuplicate {
                    if shouldImportAllTransactions { res.skippedDuplicatesTotal += 1 }
                    continue
                }

                var newTx = srcTx
                if currentTxIds.contains(newTx.id) {
                    newTx.id = UUID()
                }
                newTx.accountId = ensureValidAccountId(for: srcTx.accountId)
                newTx.categoryId = ensureValidCategoryId(for: srcTx.categoryId, fallbackType: srcTx.type, titleHint: srcTx.name)
                newTx.attachmentPath = restoreAssetIfAvailable(originalPath: srcTx.attachmentPath)

                // Consistência de vínculos com contratos, investimentos e dívidas
                if let oldContractId = srcTx.linkedContractId {
                    newTx.linkedContractId = contractIdMap[oldContractId] ?? (existingContractById.contains(oldContractId) ? oldContractId : nil)
                }
                if let oldInvId = srcTx.linkedInvestmentId {
                    newTx.linkedInvestmentId = investmentIdMap[oldInvId] ?? (existingInvById.contains(oldInvId) ? oldInvId : nil)
                }
                if let oldDebtId = srcTx.linkedDebtId {
                    newTx.linkedDebtId = debtIdMap[oldDebtId] ?? (existingDebtById.contains(oldDebtId) ? oldDebtId : nil)
                }

                transactions.append(newTx)
                currentTxIds.insert(newTx.id)
                res.importedTransactions += 1
            }
        }

        // 8. Previsões e Cotas
        onProgress?(0.90, "Validando previsões e cotas mensais...")
        if selectedTargets.contains(.provisions) {
            var existingProvIds = Set(provisions.map(\.id))
            var existingProvKeys = Set(provisions.map { "\($0.categoryId.uuidString)|\($0.yearMonthKey)" })

            for srcProv in (snapshot.provisions ?? []) {
                let mappedCatId = ensureValidCategoryId(for: srcProv.categoryId, fallbackType: .expense)
                let key = "\(mappedCatId.uuidString)|\(srcProv.yearMonthKey)"
                if existingProvIds.contains(srcProv.id) || existingProvKeys.contains(key) {
                    res.skippedDuplicatesTotal += 1
                    continue
                }
                var newProv = srcProv
                newProv.categoryId = mappedCatId
                provisions.append(newProv)
                existingProvIds.insert(newProv.id)
                existingProvKeys.insert(key)
                res.importedProvisionsAndQuotas += 1
            }

            var existingQuotaIds = Set(categoryQuotas.map(\.id))
            var existingQuotaKeys = Set(categoryQuotas.map { "\($0.seriesId.uuidString)|\($0.yearMonthKey)|\(Self.normalizeKey($0.name))" })

            for srcQuota in (snapshot.categoryQuotas ?? []) {
                let mappedCatId = ensureValidCategoryId(for: srcQuota.categoryId, fallbackType: .expense, titleHint: srcQuota.name)
                let key = "\(srcQuota.seriesId.uuidString)|\(srcQuota.yearMonthKey)|\(Self.normalizeKey(srcQuota.name))"
                if existingQuotaIds.contains(srcQuota.id) || existingQuotaKeys.contains(key) {
                    res.skippedDuplicatesTotal += 1
                    continue
                }
                var newQuota = srcQuota
                newQuota.categoryId = mappedCatId
                categoryQuotas.append(newQuota)
                existingQuotaIds.insert(newQuota.id)
                existingQuotaKeys.insert(key)
                res.importedProvisionsAndQuotas += 1
            }
        }

        // 9. Ordenação única e gravação atômica
        onProgress?(0.96, "Consolidando e salvando base de dados...")
        for target in ExportDataTarget.allCases {
            if selectedTargets.contains(target) {
                let totalInPkg = package.totalCount(for: target)
                let importedForTarget = res.importedCounts[target] ?? 0
                res.skippedDuplicateCounts[target] = max(0, totalInPkg - importedForTarget)
            } else {
                res.skippedDuplicateCounts[target] = 0
            }
        }
        if res.importedTransactions > 0 {
            sortTransactions()
        }
        if importedPlansCount > 0 {
            if let importedScenario = snapshot.budgetProjectionScenario {
                budgetProjectionScenario = importedScenario
            }
            for plan in amortizationPlans {
                syncPlannedAmortizationTransactions(for: plan.contractId, saveAfter: false)
            }
        }
        if res.totalImportedItems > 0 || res.autoCreatedDependenciesCount > 0 || importedPlansCount > 0 {
            save()
            cloudSyncService?.enqueueAllLocalData()
            cloudSyncService?.performSync()
        }

        return res
    }

    /// Analisa um arquivo JSON/Backup de gastos/transações em tempo $O(N)$ e retorna rascunhos para revisão.
    public func parseImportableExpensesFromJSON(data: Data) throws -> [ImportableExpenseDraft] {
        let snapshot = try decodeImportDataToSnapshot(data)
        let rawTransactions = snapshot.transactions
        var sourceCategoriesById: [UUID: String] = [:]
        for cat in snapshot.categories {
            sourceCategoriesById[cat.id] = cat.name
        }
        var sourceAccountsById: [UUID: String] = [:]
        for acc in snapshot.accounts {
            sourceAccountsById[acc.id] = acc.name
        }

        let existingCatIds = Set(categories.map(\.id))
        var localCatByNormName: [String: UUID] = [:]
        for cat in categories {
            localCatByNormName[Self.normalizeKey(cat.name)] = cat.id
        }

        let existingAccIds = Set(accounts.map(\.id))
        var localAccByNormName: [String: UUID] = [:]
        for acc in accounts {
            localAccByNormName[Self.normalizeKey(acc.name)] = acc.id
        }

        let preExistingTxIds = Set(transactions.map(\.id))
        var remainingPreExistingTxSigCounts: [String: Int] = [:]
        remainingPreExistingTxSigCounts.reserveCapacity(transactions.count)
        for tx in transactions {
            let sig = transactionSignature(name: tx.name, amount: tx.amount, date: tx.date, type: tx.type)
            remainingPreExistingTxSigCounts[sig, default: 0] += 1
        }

        let defaultAccountId = accounts.first?.id ?? UUID()

        return rawTransactions.map { tx in
            let resolvedCategoryId: UUID = {
                if existingCatIds.contains(tx.categoryId) {
                    return tx.categoryId
                }
                if let sourceCatName = sourceCategoriesById[tx.categoryId],
                   let matchedId = localCatByNormName[Self.normalizeKey(sourceCatName)] {
                    return matchedId
                }
                return inferCategoryId(forTitle: tx.name, type: tx.type)
            }()

            let resolvedAccountId: UUID = {
                if existingAccIds.contains(tx.accountId) {
                    return tx.accountId
                }
                if let sourceAccName = sourceAccountsById[tx.accountId],
                   let matchedId = localAccByNormName[Self.normalizeKey(sourceAccName)] {
                    return matchedId
                }
                return defaultAccountId
            }()

            let sig = transactionSignature(name: tx.name, amount: tx.amount, date: tx.date, type: tx.type)
            let duplicate: Bool = {
                if preExistingTxIds.contains(tx.id) {
                    if let count = remainingPreExistingTxSigCounts[sig], count > 0 {
                        remainingPreExistingTxSigCounts[sig] = count - 1
                    }
                    return true
                }
                if let count = remainingPreExistingTxSigCounts[sig], count > 0 {
                    remainingPreExistingTxSigCounts[sig] = count - 1
                    return true
                }
                return false
            }()

            return ImportableExpenseDraft(
                originalTransactionId: tx.id,
                date: tx.date,
                description: tx.name,
                details: tx.details,
                amount: tx.amount,
                type: tx.type,
                isPaid: tx.isPaid,
                categoryId: resolvedCategoryId,
                accountId: resolvedAccountId,
                isDuplicate: duplicate,
                isSelected: !duplicate
            )
        }
    }

    /// Mescla os rascunhos revisados e selecionados pelo usuário na base de dados ativa em tempo $O(N)$, evitando duplicidades.
    @discardableResult
    public func importReviewedExpenseDrafts(
        _ drafts: [ImportableExpenseDraft],
        skipDuplicates: Bool = true
    ) -> (importedCount: Int, skippedDuplicatesCount: Int) {
        var imported = 0
        var skipped = 0

        let fallbackAccId: UUID = {
            if let first = accounts.first?.id { return first }
            let defaultAcc = BankAccount(
                name: "Conta Principal",
                bankPresetId: "itau",
                iconSymbol: "building.columns.fill",
                colorHex: "#EC7000",
                initialBalance: 0.0
            )
            accounts.append(defaultAcc)
            return defaultAcc.id
        }()

        let validCatIds = Set(categories.map(\.id))
        let validAccIds = Set(accounts.map(\.id))
        let preExistingTxIds = Set(transactions.map(\.id))
        var preExistingTxSigCounts: [String: Int] = [:]
        preExistingTxSigCounts.reserveCapacity(transactions.count)
        for tx in transactions {
            let sig = transactionSignature(name: tx.name, amount: tx.amount, date: tx.date, type: tx.type)
            preExistingTxSigCounts[sig, default: 0] += 1
        }
        var currentTxIds = preExistingTxIds

        for draft in drafts where draft.isSelected {
            let cleanDesc = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanDesc.isEmpty, draft.amount > 0 else { continue }

            let sig = transactionSignature(name: cleanDesc, amount: draft.amount, date: draft.date, type: draft.type)
            let isPreExistingDuplicate: Bool = {
                if let origId = draft.originalTransactionId, preExistingTxIds.contains(origId) {
                    if let count = preExistingTxSigCounts[sig], count > 0 {
                        preExistingTxSigCounts[sig] = count - 1
                    }
                    return true
                }
                if let count = preExistingTxSigCounts[sig], count > 0 {
                    preExistingTxSigCounts[sig] = count - 1
                    return true
                }
                return false
            }()

            if skipDuplicates && isPreExistingDuplicate {
                skipped += 1
                continue
            }

            let validCategoryId = validCatIds.contains(draft.categoryId)
                ? draft.categoryId
                : inferCategoryId(forTitle: cleanDesc, type: draft.type)

            let validAccountId = validAccIds.contains(draft.accountId)
                ? draft.accountId
                : fallbackAccId

            let txId: UUID = {
                if let orig = draft.originalTransactionId, !currentTxIds.contains(orig) {
                    return orig
                }
                return UUID()
            }()

            let newTx = FinancialTransaction(
                id: txId,
                name: cleanDesc,
                details: draft.details,
                amount: abs(draft.amount),
                date: draft.date,
                type: draft.type,
                isPaid: draft.isPaid,
                categoryId: validCategoryId,
                accountId: validAccountId
            )
            transactions.append(newTx)
            currentTxIds.insert(txId)
            imported += 1
        }

        if imported > 0 {
            sortTransactions()
            save()
            cloudSyncService?.enqueueAllLocalData()
            cloudSyncService?.performSync()
        }

        return (imported, skipped)
    }

    // MARK: - Default Accounts & Investments

    public static func buildDefaultAccounts() -> [BankAccount] {
        [
            BankAccount(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                name: "Itaú Unibanco",
                bankPresetId: "itau",
                iconSymbol: "building.columns.fill",
                colorHex: "#EC7000",
                initialBalance: 450.00, // Saldo em 05/09/2026 do extrato anexado
                agency: "0731",
                accountNumber: "080047-0"
            ),
            BankAccount(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                name: "Santander",
                bankPresetId: "santander",
                iconSymbol: "flame.fill",
                colorHex: "#EC0000",
                initialBalance: 0.00,
                agency: "0001",
                accountNumber: "12345-6"
            ),
            BankAccount(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                name: "Nubank",
                bankPresetId: "nubank",
                iconSymbol: "creditcard.fill",
                colorHex: "#820AD1",
                initialBalance: 0.00,
                agency: "0001",
                accountNumber: "998877-1"
            )
        ]
    }

    public static func buildDefaultInvestments(accounts: [BankAccount]) -> [InvestmentItem] {
        let itauId = accounts.first(where: { $0.bankPresetId == "itau" })?.id ?? accounts.first!.id
        let santanderId = accounts.first(where: { $0.bankPresetId == "santander" })?.id ?? itauId
        return [
            InvestmentItem(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                name: "Cofrinhos Itaú",
                groupName: "Caixinha Itaú",
                investmentAccountId: itauId,
                balance: 2027.49,
                showInConsolidated: true,
                iconSymbol: "lock.shield.fill",
                colorHex: "#EC7000",
                notes: "Reserva de liquidez diária 100% CDI Itaú"
            ),
            InvestmentItem(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
                name: "CDB DI Liquidez Diária",
                groupName: "CDB Santander",
                investmentAccountId: santanderId,
                balance: 0.00,
                showInConsolidated: true,
                iconSymbol: "chart.line.uptrend.xyaxis",
                colorHex: "#EC0000",
                notes: "CDB pós-fixado DI"
            )
        ]
    }

    public static func buildDefaultSampleDebts() -> [DebtItem] {
        [
            DebtItem(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                name: "Cartão Mercado Pago",
                bankPresetId: "mercadopago",
                iconSymbol: "creditcard.trianglebadge.exclamationmark",
                colorHex: "#009EE3",
                originalAmount: 1850.00,
                contractedDate: BRLFormatters.shortDateFormatter.date(from: "15/06/2026"),
                notes: "Fatura em aberto aguardando proposta de desconto para quitação à vista."
            )
        ]
    }

    public func seedAttachedItauStatementIfNeeded() {
        guard !hasSeededInitialStatement else { return }
        guard let itauAccount = accounts.first(where: { $0.bankPresetId == "itau" }) ?? accounts.first else { return }

        let rawText = SampleItauStatementData.rawOCRText
        let parsed = StatementImportService.parseStatementText(
            rawText,
            categories: categories,
            filterMode: .hybrid
        )
        _ = importParsedTransactions(parsed, intoAccountId: itauAccount.id, filterMode: .hybrid)
        hasSeededInitialStatement = true

        // Set selectedMonth to November 2026 or October 2026 matching the statement
        if let nov2026 = BRLFormatters.shortDateFormatter.date(from: "05/11/2026") {
            self.selectedMonth = nov2026
        }
        save()
    }

    // MARK: - File Attachment Helper

    public func copyAttachmentToStorage(from sourceURL: URL) -> (path: String, fileName: String)? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let ext = sourceURL.pathExtension
        let safeName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destinationURL = attachmentsDirectoryURL.appendingPathComponent(ext.isEmpty ? safeName : safeName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return (destinationURL.path, sourceURL.lastPathComponent)
        } catch {
            if let data = try? Data(contentsOf: sourceURL) {
                try? data.write(to: destinationURL)
                return (destinationURL.path, sourceURL.lastPathComponent)
            }
            return nil
        }
    }

    // MARK: - Month & Year Navigation + Date Helpers

    public func changeMonth(by offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = next
            ensureRecurringTransactionsMaterialized(upTo: endOfMonth(for: next))
        }
    }

    public func changeYear(by offset: Int) {
        if let next = calendar.date(byAdding: .year, value: offset, to: selectedMonth) {
            selectedMonth = next
            ensureRecurringTransactionsMaterialized(upTo: endOfYear(for: next))
        }
    }

    public func isDateInFuture(_ date: Date, referenceNow: Date = Date()) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: referenceNow)
    }

    /// Retorna uma data padrão apontando sempre para o mês filtrado (`selectedMonth`),
    /// preservando o dia atual quando possível (ou ajustando ao último dia do mês filtrado).
    public func defaultTransactionDateForSelectedMonth(today: Date = Date()) -> Date {
        if isInMonth(today, monthReference: selectedMonth) {
            return today
        }
        let targetComps = calendar.dateComponents([.year, .month], from: selectedMonth)
        let todayDay = calendar.component(.day, from: today)
        guard let startOfTargetMonth = calendar.date(from: targetComps),
              let daysRange = calendar.range(of: .day, in: .month, for: startOfTargetMonth) else {
            return selectedMonth
        }
        var finalComps = targetComps
        finalComps.day = min(max(todayDay, daysRange.lowerBound), daysRange.upperBound - 1)
        return calendar.date(from: finalComps) ?? startOfTargetMonth
    }

    public func isInMonth(_ date: Date, monthReference: Date) -> Bool {
        let c1 = calendar.dateComponents([.year, .month], from: date)
        let c2 = calendar.dateComponents([.year, .month], from: monthReference)
        return c1.year == c2.year && c1.month == c2.month
    }

    public func isInYear(_ date: Date, yearReference: Date) -> Bool {
        let y1 = calendar.component(.year, from: date)
        let y2 = calendar.component(.year, from: yearReference)
        return y1 == y2
    }

    /// Retorna o primeiro instante do mês informado (dia 1º às 00:00:00).
    public func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Retorna se o mês informado é estritamente anterior ao mês atual (mês já fechado).
    public func isMonthPriorToCurrent(_ monthReference: Date, referenceNow: Date? = nil) -> Bool {
        let now = referenceNow ?? effectiveCurrentDate
        return startOfMonth(for: monthReference) < startOfMonth(for: now)
    }

    /// Título contextualizado para o card de saldo ao final do período:
    /// - Meses já fechados: "Resultado Consolidado"
    /// - Mês atual ou futuro: "Saldo Previsto para DD/MM" (ex: "Saldo Previsto para 31/12")
    public func monthEndBalanceCardTitle(for monthReference: Date) -> String {
        if isMonthPriorToCurrent(monthReference) {
            return "Resultado Consolidado"
        } else {
            let lastDay = endOfMonth(for: monthReference)
            return "Saldo Previsto para \(BRLFormatters.dayMonth(lastDay))"
        }
    }

    public func endOfMonth(for monthReference: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        guard let startOfMonth = calendar.date(from: comps),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth),
              let lastMoment = calendar.date(byAdding: .second, value: -1, to: nextMonth) else {
            return monthReference
        }
        return lastMoment
    }

    /// Retorna o último instante do último dia do ano (31/12 às 23:59:59) para projeções anuais
    public func endOfYear(for yearReference: Date) -> Date {
        let year = calendar.component(.year, from: yearReference)
        var comps = DateComponents()
        comps.year = year
        comps.month = 12
        comps.day = 31
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        return calendar.date(from: comps) ?? endOfMonth(for: yearReference)
    }

    // MARK: - Account Management

    public func addAccount(
        name: String,
        bankPresetId: String?,
        customImagePath: String?,
        iconSymbol: String,
        colorHex: String,
        initialBalance: Double,
        agency: String = "",
        accountNumber: String = ""
    ) {
        let account = BankAccount(
            name: name,
            bankPresetId: bankPresetId,
            customImagePath: customImagePath,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            initialBalance: initialBalance,
            agency: agency,
            accountNumber: accountNumber
        )
        accounts.append(account)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "bank_accounts", entityId: account.id, operation: .upsert, entity: account)
    }

    public func updateAccount(_ account: BankAccount) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
            save()
            cloudSyncService?.recordLocalMutation(entityName: "bank_accounts", entityId: account.id, operation: .upsert, entity: account)
        }
    }

    public func deleteAccount(_ accountId: UUID) {
        accounts.removeAll(where: { $0.id == accountId })
        save()
        cloudSyncService?.recordLocalMutation(entityName: "bank_accounts", entityId: accountId, operation: .delete)
    }

    public func account(for id: UUID) -> BankAccount? {
        if let map = cachedAccountsById {
            return map[id]
        }
        var map: [UUID: BankAccount] = [:]
        map.reserveCapacity(accounts.count)
        for acc in accounts {
            map[acc.id] = acc
        }
        cachedAccountsById = map
        return map[id]
    }

    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    public func moveAccount(draggedId: UUID, targetId: UUID) {
        guard draggedId != targetId,
              let fromIndex = accounts.firstIndex(where: { $0.id == draggedId }),
              let toIndex = accounts.firstIndex(where: { $0.id == targetId }) else { return }
        let item = accounts.remove(at: fromIndex)
        accounts.insert(item, at: toIndex)
        save()
    }

    // MARK: - Category Management

    public func categories(for type: TransactionType) -> [CategoryItem] {
        categories.filter { $0.type == type }
    }

    public func moveCategories(for type: TransactionType, fromOffsets source: IndexSet, toOffset destination: Int) {
        var typed = categories.filter { $0.type == type }
        let others = categories.filter { $0.type != type }
        typed.move(fromOffsets: source, toOffset: destination)
        categories = type == .expense ? (typed + others) : (others + typed)
        save()
    }

    public func moveCategory(draggedId: UUID, targetId: UUID) {
        guard draggedId != targetId,
              let fromIndex = categories.firstIndex(where: { $0.id == draggedId }),
              let toIndex = categories.firstIndex(where: { $0.id == targetId }),
              categories[fromIndex].type == categories[toIndex].type else { return }
        let item = categories.remove(at: fromIndex)
        categories.insert(item, at: toIndex)
        save()
    }

    public func category(for id: UUID) -> CategoryItem? {
        if let map = cachedCategoriesById {
            return map[id]
        }
        var map: [UUID: CategoryItem] = [:]
        map.reserveCapacity(categories.count)
        for cat in categories {
            map[cat.id] = cat
        }
        cachedCategoriesById = map
        return map[id]
    }

    public func investment(for id: UUID?) -> InvestmentItem? {
        guard let id = id else { return nil }
        return investments.first(where: { $0.id == id })
    }

    public var expenseCategories: [CategoryItem] {
        categories(for: .expense)
    }

    public var incomeCategories: [CategoryItem] {
        categories(for: .income)
    }

    public func fallbackCategoryId(for type: TransactionType, matchingSubstring: String? = nil) -> UUID {
        if let sub = matchingSubstring,
           let matched = categories.first(where: { $0.type == type && $0.name.localizedCaseInsensitiveContains(sub) }) {
            return matched.id
        }
        return categories(for: type).first?.id ?? categories.first?.id ?? UUID()
    }

    /// Retorna a categoria padronizada "Aportes e investimentos", migrando registros legados
    /// ou criando-a sob demanda caso ainda não exista no catálogo de categorias do usuário.
    public func investmentDepositCategoryId() -> UUID {
        // 1. Categoria exata de despesa "Aportes e investimentos"
        if let exact = categories.first(where: { $0.type == .expense && $0.name.compare("Aportes e investimentos", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact.id
        }
        // 2. Se houver legado "Aplicações & Reservas" ou "Aportes em Investimentos", atualizar nome
        if let legacyIdx = categories.firstIndex(where: { $0.type == .expense && ($0.name.compare("Aplicações & Reservas", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame || $0.name.compare("Aportes em Investimentos", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame) }) {
            categories[legacyIdx].name = "Aportes e investimentos"
            save()
            cloudSyncService?.recordLocalMutation(entityName: "categories", entityId: categories[legacyIdx].id, operation: .upsert, entity: categories[legacyIdx])
            return categories[legacyIdx].id
        }
        // 3. Qualquer categoria que contenha "aporte"
        if let aporteIdx = categories.firstIndex(where: { $0.type == .expense && $0.name.localizedCaseInsensitiveContains("aporte") }) {
            categories[aporteIdx].name = "Aportes e investimentos"
            save()
            cloudSyncService?.recordLocalMutation(entityName: "categories", entityId: categories[aporteIdx].id, operation: .upsert, entity: categories[aporteIdx])
            return categories[aporteIdx].id
        }
        // 4. Se não existir, criar a categoria "Aportes e investimentos"
        let newCat = CategoryItem(
            name: "Aportes e investimentos",
            type: .expense,
            iconSymbol: "chart.line.uptrend.xyaxis",
            colorHex: "#6366F1",
            keywords: ["APORTE", "INVESTIMENTO", "CDB", "POUPANCA", "COFRINHO"],
            isSystemDefault: true
        )
        categories.append(newCat)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "categories", entityId: newCat.id, operation: .upsert, entity: newCat)
        return newCat.id
    }

    public func inferCategoryId(forTitle title: String, type: TransactionType) -> UUID {
        let normTitle = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let candidates = categories(for: type)
        for cat in candidates {
            let normCatName = cat.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            if normTitle.contains(normCatName) {
                return cat.id
            }
            for kw in cat.keywords {
                let normKw = kw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                if normKw.count >= 3 && normTitle.contains(normKw) {
                    return cat.id
                }
            }
        }
        return fallbackCategoryId(for: type, matchingSubstring: "Outros")
    }

    public func addCategory(name: String, type: TransactionType, iconSymbol: String, colorHex: String, keywords: [String] = []) {
        let item = CategoryItem(
            name: name,
            type: type,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            keywords: keywords,
            isSystemDefault: false
        )
        categories.append(item)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "categories", entityId: item.id, operation: .upsert, entity: item)
    }

    public func updateCategory(_ category: CategoryItem) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            save()
            cloudSyncService?.recordLocalMutation(entityName: "categories", entityId: category.id, operation: .upsert, entity: category)
        }
    }

    public func deleteCategory(_ categoryId: UUID) {
        categories.removeAll(where: { $0.id == categoryId })
        provisions.removeAll(where: { $0.categoryId == categoryId })
        categoryQuotas.removeAll(where: { $0.categoryId == categoryId })
        save()
        cloudSyncService?.recordLocalMutation(entityName: "categories", entityId: categoryId, operation: .delete)
    }

    // MARK: - Transaction Creation (Single, Installment, Repeated, Recurring)

    @discardableResult
    public func createTransaction(
        name: String,
        details: String = "",
        amount: Double,
        date: Date,
        type: TransactionType,
        isPaid: Bool = true,
        categoryId: UUID,
        accountId: UUID,
        attachmentPath: String? = nil,
        attachmentName: String? = nil,
        ignoreInConsolidated: Bool = false,
        recurrenceMode: TransactionRecurrenceMode = .single,
        installmentsOrMonthsCount: Int = 1,
        recurrenceFrequency: RecurrenceFrequency = .monthly,
        referenceNow: Date = Date()
    ) -> [FinancialTransaction] {
        var created: [FinancialTransaction] = []
        let cleanAmount = abs(amount)
        var finalDate = date
        var firstOccurrencePaid = isPaid
        if isPaid && isDateInFuture(date, referenceNow: referenceNow) {
            finalDate = referenceNow
            firstOccurrencePaid = true
        }

        if recurrenceMode == .single || (recurrenceMode != .recurring && installmentsOrMonthsCount <= 1) {
            let tx = FinancialTransaction(
                name: name,
                details: details,
                amount: cleanAmount,
                date: finalDate,
                type: type,
                isPaid: firstOccurrencePaid,
                categoryId: categoryId,
                accountId: accountId,
                attachmentPath: attachmentPath,
                attachmentName: attachmentName,
                ignoreInConsolidated: ignoreInConsolidated,
                recurrenceMode: .single
            )
            transactions.append(tx)
            created.append(tx)
        } else if recurrenceMode == .installment && type == .expense {
            // Parcelada: receives total full value (`cleanAmount`) and number of installments (`count`)
            let count = max(installmentsOrMonthsCount, 2)
            let groupId = UUID()
            let baseInstallment = ((cleanAmount / Double(count)) * 100.0).rounded(.down) / 100.0
            let remainder = ((cleanAmount - (baseInstallment * Double(count))) * 100.0).rounded() / 100.0

            for index in 0..<count {
                let installmentDate = calendar.date(byAdding: .month, value: index, to: date) ?? date
                let value = index == 0 ? (baseInstallment + remainder) : baseInstallment
                let paidStatus = (index == 0 && !isDateInFuture(installmentDate, referenceNow: referenceNow)) ? firstOccurrencePaid : false
                let tx = FinancialTransaction(
                    name: "\(name) (\(index + 1)/\(count))",
                    details: details.isEmpty ? "Compra parcelada em \(count)x (Total: \(BRLFormatters.currency(cleanAmount)))" : details,
                    amount: value,
                    date: installmentDate,
                    type: .expense,
                    isPaid: paidStatus,
                    categoryId: categoryId,
                    accountId: accountId,
                    attachmentPath: attachmentPath,
                    attachmentName: attachmentName,
                    ignoreInConsolidated: ignoreInConsolidated,
                    recurrenceMode: .installment,
                    seriesGroupId: groupId,
                    installmentIndex: index + 1,
                    installmentTotal: count
                )
                transactions.append(tx)
                created.append(tx)
            }
        } else if recurrenceMode == .repeated {
            // Repetida: receives number of months (`count`) and repeats the exact same value across those months (supports both Expense and Income)
            let count = max(installmentsOrMonthsCount, 2)
            let groupId = UUID()
            for index in 0..<count {
                let occurrenceDate = calendar.date(byAdding: .month, value: index, to: date) ?? date
                let paidStatus = (index == 0 && !isDateInFuture(occurrenceDate, referenceNow: referenceNow)) ? firstOccurrencePaid : false
                let defaultDetail = type == .expense
                    ? "Despesa repetida mensal (\(index + 1)/\(count))"
                    : "Receita repetida mensal (\(index + 1)/\(count))"
                let tx = FinancialTransaction(
                    name: name,
                    details: details.isEmpty ? defaultDetail : details,
                    amount: cleanAmount,
                    date: occurrenceDate,
                    type: type,
                    isPaid: paidStatus,
                    categoryId: categoryId,
                    accountId: accountId,
                    attachmentPath: attachmentPath,
                    attachmentName: attachmentName,
                    ignoreInConsolidated: ignoreInConsolidated,
                    recurrenceMode: .repeated,
                    recurrenceFrequency: .monthly,
                    seriesGroupId: groupId,
                    installmentIndex: index + 1,
                    installmentTotal: count
                )
                transactions.append(tx)
                created.append(tx)
            }
        } else if recurrenceMode == .recurring {
            // Recorrente contínua (ex: Energia, Água, Wellhub, Netflix mensal, Prime Video anual, Salário recorrente):
            // existe continuamente enquanto não for cancelada, gerando lançamentos na frequência escolhida.
            let groupId = UUID()
            let initialCount = recurrenceFrequency.defaultInitialHorizonCount
            let defaultDetail = type == .expense
                ? "Pagamento recorrente (\(recurrenceFrequency.shortTitle))"
                : "Recebimento recorrente (\(recurrenceFrequency.shortTitle))"

            for index in 0..<initialCount {
                let occurrenceDate = recurrenceFrequency.nextDate(from: date, occurrenceIndex: index, calendar: calendar)
                let paidStatus = (index == 0 && !isDateInFuture(occurrenceDate, referenceNow: referenceNow)) ? firstOccurrencePaid : false
                let tx = FinancialTransaction(
                    name: name,
                    details: details.isEmpty ? defaultDetail : details,
                    amount: cleanAmount,
                    date: occurrenceDate,
                    type: type,
                    isPaid: paidStatus,
                    categoryId: categoryId,
                    accountId: accountId,
                    attachmentPath: attachmentPath,
                    attachmentName: attachmentName,
                    ignoreInConsolidated: ignoreInConsolidated,
                    recurrenceMode: .recurring,
                    recurrenceFrequency: recurrenceFrequency,
                    isCanceledRecurringSeries: false,
                    seriesGroupId: groupId,
                    installmentIndex: index + 1,
                    installmentTotal: nil
                )
                transactions.append(tx)
                created.append(tx)
            }
        }

        sortTransactions()
        save()
        for tx in created {
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: tx.id, operation: .upsert, entity: tx)
        }
        return created
    }

    /// Garante que contas/recebimentos recorrentes ativos tenham ocorrências geradas até a data-limite consultada (ao navegar para meses ou anos futuros)
    public func ensureRecurringTransactionsMaterialized(upTo targetDate: Date) {
        if let maxMat = maxMaterializedRecurringDate, targetDate <= maxMat {
            return
        }
        let recurringTxs = transactions.filter { $0.recurrenceMode == .recurring && $0.seriesGroupId != nil }
        guard !recurringTxs.isEmpty else {
            maxMaterializedRecurringDate = targetDate
            return
        }

        let grouped = Dictionary(grouping: recurringTxs, by: { $0.seriesGroupId! })
        var didAppend = false

        for (groupId, items) in grouped {
            guard !items.contains(where: { $0.isCanceledRecurringSeries == true }) else { continue }
            guard let lastTx = items.max(by: { $0.date < $1.date }) else { continue }
            let freq = lastTx.recurrenceFrequency ?? .monthly
            var currentLastDate = lastTx.date
            var currentIndex = (lastTx.installmentIndex ?? items.count)

            while currentLastDate < targetDate {
                let nextDate = freq.nextDate(from: currentLastDate, occurrenceIndex: 1, calendar: calendar)
                if nextDate <= currentLastDate { break }
                currentIndex += 1
                let newTx = FinancialTransaction(
                    name: lastTx.name,
                    details: lastTx.details,
                    amount: lastTx.amount,
                    date: nextDate,
                    type: lastTx.type,
                    isPaid: false,
                    categoryId: lastTx.categoryId,
                    accountId: lastTx.accountId,
                    attachmentPath: lastTx.attachmentPath,
                    attachmentName: lastTx.attachmentName,
                    ignoreInConsolidated: lastTx.ignoreInConsolidated,
                    recurrenceMode: .recurring,
                    recurrenceFrequency: freq,
                    isCanceledRecurringSeries: false,
                    seriesGroupId: groupId,
                    installmentIndex: currentIndex,
                    installmentTotal: nil
                )
                transactions.append(newTx)
                currentLastDate = nextDate
                didAppend = true
            }
        }

        if didAppend {
            sortTransactions()
            save()
        }
        maxMaterializedRecurringDate = targetDate
    }

    /// Cancela uma assinatura/conta recorrente a partir da transação informada (remove cobranças futuras em aberto e encerra a recorrência)
    public func cancelRecurringSeries(from transaction: FinancialTransaction, includeCurrent: Bool = false) {
        guard let groupId = transaction.seriesGroupId else {
            if includeCurrent {
                deleteTransaction(transaction.id)
            }
            return
        }
        let cutoffDate = calendar.startOfDay(for: transaction.date)
        transactions.removeAll { tx in
            guard tx.seriesGroupId == groupId else { return false }
            if includeCurrent && tx.id == transaction.id { return true }
            let txDay = calendar.startOfDay(for: tx.date)
            return txDay > cutoffDate && !tx.isPaid
        }
        for idx in transactions.indices where transactions[idx].seriesGroupId == groupId {
            transactions[idx].isCanceledRecurringSeries = true
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: transactions[idx].id, operation: .upsert, entity: transactions[idx])
        }
        save()
    }

    /// Atualiza uma transação única ou aplica a edição em lote conforme o `SeriesEditScope`
    /// (`.onlyThis`: somente naquela transação; `.thisAndFuture`: da transação atual e todas no futuro; `.allInSeries`: em todas as parcelas/ocorrências)
    public func updateTransaction(
        _ updated: FinancialTransaction,
        scope: SeriesEditScope = .onlyThis,
        referenceNow: Date? = nil
    ) {
        let now = referenceNow ?? effectiveCurrentDate
        guard let targetIdx = transactions.firstIndex(where: { $0.id == updated.id }) else { return }
        let originalBeforeEdit = transactions[targetIdx]
        let didUserChangeDate = !calendar.isDate(updated.date, inSameDayAs: originalBeforeEdit.date)

        var cleanUpdated = updated
        cleanUpdated.amount = abs(updated.amount)

        // Se o usuário alterou explicitamente a data da transação para uma data futura,
        // preservamos a nova data escolhida (e marcamos como não paga caso não tenha sido explicitamente confirmada como paga agora).
        if didUserChangeDate {
            if isDateInFuture(cleanUpdated.date, referenceNow: now) && originalBeforeEdit.isPaid == updated.isPaid {
                cleanUpdated.isPaid = false
            }
        } else if cleanUpdated.isPaid && !originalBeforeEdit.isPaid && isDateInFuture(cleanUpdated.date, referenceNow: now) {
            // Caso o usuário não tenha editado a data, mas tenha marcado uma transação futura como paga: move para hoje
            cleanUpdated.date = now
        }

        let baseCleanName = Self.stripInstallmentSuffix(from: cleanUpdated.name)
        let didUserChangeAmount = abs(cleanUpdated.amount - originalBeforeEdit.amount) > 0.005
        transactions[targetIdx] = cleanUpdated

        if scope != .onlyThis, let groupId = cleanUpdated.seriesGroupId {
            let referenceDate = calendar.startOfDay(for: originalBeforeEdit.date)
            let referenceInstallmentIdx = originalBeforeEdit.installmentIndex
            let newDayComponent = calendar.component(.day, from: cleanUpdated.date)

            for idx in transactions.indices {
                guard transactions[idx].id != cleanUpdated.id,
                      transactions[idx].seriesGroupId == groupId else { continue }

                let shouldApply: Bool
                switch scope {
                case .onlyThis:
                    shouldApply = false
                case .allInSeries:
                    shouldApply = true
                case .thisAndFuture:
                    if let refInst = referenceInstallmentIdx, let otherInst = transactions[idx].installmentIndex {
                        shouldApply = otherInst >= refInst
                    } else {
                        shouldApply = calendar.startOfDay(for: transactions[idx].date) >= referenceDate
                    }
                }

                if shouldApply {
                    // Se a transação pertence a um contrato com projeção crescente ou VLR. PARC individual por parcela,
                    // preserva o valor projetado individual de cada parcela futura quando o usuário não alterou o valor!
                    if transactions[idx].linkedContractId != nil && !didUserChangeAmount {
                        // Preserva o valor individual da parcela
                    } else if let projCorr = transactions[idx].projectedInstallmentCorrectionAmount,
                              projCorr > 0,
                              let newBase = cleanUpdated.baseInstallmentRegisteredAmount {
                        transactions[idx].baseInstallmentRegisteredAmount = newBase
                        transactions[idx].amount = ((newBase + projCorr) * 100.0).rounded() / 100.0
                    } else {
                        transactions[idx].amount = cleanUpdated.amount
                    }
                    transactions[idx].categoryId = cleanUpdated.categoryId
                    transactions[idx].accountId = cleanUpdated.accountId
                    transactions[idx].ignoreInConsolidated = cleanUpdated.ignoreInConsolidated
                    if transactions[idx].linkedContractId == nil {
                        transactions[idx].details = cleanUpdated.details
                    }
                    if didUserChangeDate {
                        var comps = calendar.dateComponents([.year, .month], from: transactions[idx].date)
                        if let monthStart = calendar.date(from: comps),
                           let range = calendar.range(of: .day, in: .month, for: monthStart) {
                            comps.day = min(max(newDayComponent, range.lowerBound), range.upperBound - 1)
                            if let updatedSeriesDate = calendar.date(from: comps) {
                                transactions[idx].date = updatedSeriesDate
                            }
                        }
                    }
                    if transactions[idx].recurrenceMode == .installment,
                       let instIdx = transactions[idx].installmentIndex,
                       let instTotal = transactions[idx].installmentTotal {
                        transactions[idx].name = "\(baseCleanName) (\(instIdx)/\(instTotal))"
                    } else {
                        transactions[idx].name = baseCleanName
                    }
                    if isDateInFuture(transactions[idx].date, referenceNow: now) {
                        transactions[idx].isPaid = false
                    }
                }
            }
        }

        sortTransactions()
        invalidateDerivedCaches()
        save()
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: cleanUpdated.id, operation: .upsert, entity: cleanUpdated)
        if scope != .onlyThis, let groupId = cleanUpdated.seriesGroupId {
            for tx in transactions where tx.seriesGroupId == groupId && tx.id != cleanUpdated.id {
                cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: tx.id, operation: .upsert, entity: tx)
            }
        }
    }

    private static func stripInstallmentSuffix(from title: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s*\(\d+/\d+\)\s*$"#) else { return title }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        let stripped = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Alterna o status de pago/recebido.
    /// Regra: caso o usuário pague uma transação com data no futuro, permite o pagamento e move a data da transação para a data atual (`referenceNow`).
    /// Ao desfazer o pagamento, a transação volta para não paga.
    @discardableResult
    public func toggleTransactionPaid(_ id: UUID, referenceNow: Date? = nil) -> Bool {
        let now = referenceNow ?? effectiveCurrentDate
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return false }
        if transactions[idx].transactionOrigin == .plannedAmortization && !transactions[idx].isPaid {
            let payDate = isDateInFuture(transactions[idx].date, referenceNow: now)
                ? now
                : transactions[idx].date
            return confirmPlannedAmortizationByTransactionId(id, paymentDate: payDate)
        }
        if !transactions[idx].isPaid {
            // Pagando: se a data estiver no futuro, move para a data atual
            if isDateInFuture(transactions[idx].date, referenceNow: now) {
                transactions[idx].date = now
            }
            if let baseReg = transactions[idx].baseInstallmentRegisteredAmount,
               transactions[idx].confirmedRealInterestCorrectionAmount == nil {
                transactions[idx].confirmedRealInterestCorrectionAmount = ((transactions[idx].amount - baseReg) * 100.0).rounded() / 100.0
            }
            transactions[idx].isPaid = true
        } else {
            // Desfazendo pagamento: restaura o valor projetado (base + projeção de correção) se houver
            transactions[idx].isPaid = false
            transactions[idx].confirmedRealInterestCorrectionAmount = nil
            if let baseReg = transactions[idx].baseInstallmentRegisteredAmount {
                let projCorr = transactions[idx].projectedInstallmentCorrectionAmount ?? 0.0
                transactions[idx].amount = ((baseReg + projCorr) * 100.0).rounded() / 100.0
            }
        }
        sortTransactions()
        invalidateDerivedCaches()
        save()
        if let tx = transactions.first(where: { $0.id == id }) {
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: id, operation: .upsert, entity: tx)
        }
        return true
    }

    /// Marca múltiplas transações pendentes como pagas/recebidas em massa,
    /// ignorando automaticamente transações já pagas ou suprimidas.
    @discardableResult
    public func markTransactionsPaid(_ ids: [UUID], referenceNow: Date? = nil) -> (processedCount: Int, ignoredAlreadyPaidCount: Int) {
        let now = referenceNow ?? effectiveCurrentDate
        let uniqueIds = Set(ids)
        var processedIds: [UUID] = []
        var ignoredAlreadyPaidCount = 0

        for id in uniqueIds {
            guard let idx = transactions.firstIndex(where: { $0.id == id }) else { continue }
            if transactions[idx].isPaid {
                ignoredAlreadyPaidCount += 1
                continue
            }
            if transactionProjectionStatus(for: transactions[idx]) == .shadowed {
                continue
            }
            if transactions[idx].transactionOrigin == .plannedAmortization {
                let payDate = isDateInFuture(transactions[idx].date, referenceNow: now)
                    ? now
                    : transactions[idx].date
                if confirmPlannedAmortizationByTransactionId(id, paymentDate: payDate) {
                    processedIds.append(id)
                }
                continue
            }
            if isDateInFuture(transactions[idx].date, referenceNow: now) {
                transactions[idx].date = now
            }
            if let baseReg = transactions[idx].baseInstallmentRegisteredAmount,
               transactions[idx].confirmedRealInterestCorrectionAmount == nil {
                transactions[idx].confirmedRealInterestCorrectionAmount = ((transactions[idx].amount - baseReg) * 100.0).rounded() / 100.0
            }
            transactions[idx].isPaid = true
            processedIds.append(id)
        }

        if !processedIds.isEmpty {
            sortTransactions()
            invalidateDerivedCaches()
            save()
            for id in processedIds {
                if let tx = transactions.first(where: { $0.id == id }) {
                    cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: id, operation: .upsert, entity: tx)
                }
            }
        }

        return (processedIds.count, ignoredAlreadyPaidCount)
    }

    /// Confirma o pagamento real de uma parcela de contrato (ex: Financiamento CAIXA TP com aumento projetado),
    /// gravando o valor final efetivamente pago na ocasião e os juros/correção reais efetivados,
    /// sem alterar o Saldo Devedor de quitação do financiamento.
    @discardableResult
    public func confirmContractInstallmentPayment(
        transactionId: UUID,
        realPaidAmount: Double,
        paymentDate: Date? = nil,
        referenceNow: Date? = nil
    ) -> Bool {
        let now = referenceNow ?? effectiveCurrentDate
        guard let idx = transactions.firstIndex(where: { $0.id == transactionId }) else { return false }
        let cleanPaid = abs(realPaidAmount)
        guard cleanPaid > 0 else { return false }

        let contract = transactions[idx].linkedContractId.flatMap { cid in
            contracts.first(where: { $0.id == cid })
        }
        let baseReg = transactions[idx].baseInstallmentRegisteredAmount
            ?? contract?.installmentAmount
            ?? transactions[idx].amount
        let projCorr = transactions[idx].projectedInstallmentCorrectionAmount ?? max(0.0, transactions[idx].amount - baseReg)
        let realCorrection = ((cleanPaid - baseReg) * 100.0).rounded() / 100.0

        let effectivePayDate: Date = {
            if let explicitDate = paymentDate {
                return explicitDate
            }
            return isDateInFuture(transactions[idx].date, referenceNow: now) ? now : transactions[idx].date
        }()

        transactions[idx].baseInstallmentRegisteredAmount = baseReg
        transactions[idx].projectedInstallmentCorrectionAmount = projCorr
        transactions[idx].confirmedRealInterestCorrectionAmount = realCorrection
        transactions[idx].amount = cleanPaid
        transactions[idx].date = effectivePayDate
        transactions[idx].isPaid = true

        let corrSign = realCorrection >= 0 ? "+" : ""
        if let contract {
            transactions[idx].details = "\(contract.kind.title) (\(contract.subtypeDisplayName)) • Valor cadastrado: \(BRLFormatters.currency(baseReg)) • Juros/Correção efetivada no pagamento: \(corrSign)\(BRLFormatters.currency(realCorrection)) (Projeção era +\(BRLFormatters.currency(projCorr)))"
        }

        sortTransactions()
        invalidateDerivedCaches()
        save()
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: transactionId, operation: .upsert, entity: transactions[idx])
        return true
    }

    /// Retorna a decomposição do valor cadastrado da parcela vs. aumento projetado (especulação de juros/correção)
    /// ou juros/correção efetivamente confirmados no pagamento, para exibição clara na linha da transação e no modal de pagamento.
    public func installmentCorrectionBreakdown(for tx: FinancialTransaction) -> InstallmentCorrectionBreakdown? {
        guard let contractId = tx.linkedContractId,
              tx.installmentIndex != nil,
              let contract = contracts.first(where: { $0.id == contractId }),
              contract.kind == .financing else {
            return nil
        }

        let avgGrowth = contract.averageMonthlyInstallmentGrowth ?? {
            if contract.contractNumber == "178770203328-1" || contract.name.localizedCaseInsensitiveContains("CAIXA") {
                return (2658.06 - 2613.19) / 11.0
            }
            return 0.0
        }()
        guard avgGrowth > 0.0001 || tx.projectedInstallmentCorrectionAmount != nil || tx.baseInstallmentRegisteredAmount != nil else {
            return nil
        }

        let step = max(1, (tx.installmentIndex ?? (contract.pastInstallmentsElapsedAtCreation + 1)) - contract.pastInstallmentsElapsedAtCreation)
        let baseReg = tx.baseInstallmentRegisteredAmount ?? contract.installmentAmount
        let projectedCorr: Double = {
            if let explicitProj = tx.projectedInstallmentCorrectionAmount, explicitProj > 0 {
                return explicitProj
            }
            if avgGrowth > 0.0001 {
                let dec = LoanProjectionEngine.roundCurrency(Decimal(step) * LoanProjectionEngine.toDecimal(avgGrowth))
                return LoanProjectionEngine.toDouble(dec)
            }
            return max(0.0, tx.amount - baseReg)
        }()

        let confirmedReal: Double? = tx.isPaid
            ? (tx.confirmedRealInterestCorrectionAmount ?? (((tx.amount - baseReg) * 100.0).rounded() / 100.0))
            : nil

        let effectiveTotal = tx.isPaid ? tx.amount : effectiveTransactionAmount(for: tx)

        return InstallmentCorrectionBreakdown(
            baseRegisteredAmount: baseReg,
            projectedCorrectionAmount: projectedCorr,
            confirmedRealCorrectionAmount: confirmedReal,
            effectiveTotalAmount: effectiveTotal,
            averageMonthlyGrowth: avgGrowth,
            futureMonthStep: step
        )
    }

    public func toggleTransactionIgnoreInConsolidated(_ id: UUID) {
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx].ignoreInConsolidated.toggle()
            save()
        }
    }

    public func deleteTransaction(_ id: UUID, scope: SeriesDeleteScope = .onlyThis) {
        guard let targetTx = transactions.first(where: { $0.id == id }) else { return }

        var deletedIds: [UUID] = []
        var txsToRevert: [FinancialTransaction] = []

        if scope == .onlyThis || !targetTx.isPartOfSeries || targetTx.seriesGroupId == nil {
            txsToRevert = [targetTx]
            deletedIds = [id]
            for tx in txsToRevert {
                revertLinkedEntities(for: tx)
            }
            transactions.removeAll(where: { $0.id == id })
            sortTransactions()
            save()
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: id, operation: .delete)
            return
        }

        guard let groupId = targetTx.seriesGroupId else {
            txsToRevert = [targetTx]
            deletedIds = [id]
            for tx in txsToRevert {
                revertLinkedEntities(for: tx)
            }
            transactions.removeAll(where: { $0.id == id })
            sortTransactions()
            save()
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: id, operation: .delete)
            return
        }

        switch scope {
        case .onlyThis:
            txsToRevert = [targetTx]
            deletedIds = [id]
            transactions.removeAll(where: { $0.id == id })

        case .allInSeries:
            txsToRevert = transactions.filter({ $0.seriesGroupId == groupId })
            deletedIds = txsToRevert.map(\.id)
            transactions.removeAll(where: { $0.seriesGroupId == groupId })

        case .thisAndPending:
            let referenceDate = calendar.startOfDay(for: targetTx.date)
            let referenceInstallmentIdx = targetTx.installmentIndex

            txsToRevert = transactions.filter { tx in
                guard tx.seriesGroupId == groupId else { return false }
                if tx.id == targetTx.id { return true }
                guard !tx.isPaid else { return false }

                if let refInst = referenceInstallmentIdx, let otherInst = tx.installmentIndex {
                    return otherInst >= refInst
                } else {
                    return calendar.startOfDay(for: tx.date) >= referenceDate
                }
            }
            deletedIds = txsToRevert.map(\.id)
            let removeSet = Set(deletedIds)
            transactions.removeAll { removeSet.contains($0.id) }

            // Se for uma série recorrente contínua, encerra a geração futura para que não recrie as pendentes removidas
            if targetTx.recurrenceMode == .recurring {
                for idx in transactions.indices where transactions[idx].seriesGroupId == groupId {
                    transactions[idx].isCanceledRecurringSeries = true
                }
            }
        }

        for tx in txsToRevert {
            revertLinkedEntities(for: tx)
        }

        sortTransactions()
        save()
        for delId in deletedIds {
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: delId, operation: .delete)
        }
    }

    // MARK: - Reversão de Vínculos Relacionais (Rollback ao Deletar Transação)

    /// Intercepta a exclusão de uma transação e reverte atomicamente os efeitos colaterais
    /// causados na entidade de origem (Investimento, Dívida ou Financiamento/Empréstimo).
    private func revertLinkedEntities(for tx: FinancialTransaction) {
        let origin = tx.effectiveOrigin
        let entityId = tx.effectiveLinkedEntityID

        switch origin {
        case .investmentDeposit:
            // Se deletou um aporte (Adição): localiza o investimento e subtrai o valor do saldo caso tenha sido realizado
            if let invId = entityId ?? tx.linkedInvestmentId,
               let idx = investments.firstIndex(where: { $0.id == invId }) {
                if tx.isPaid {
                    investments[idx].balance = max(0.0, investments[idx].balance - tx.amount)
                }
                investments[idx].movements.removeAll { $0.generatedTransactionId == tx.id }
                cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: invId, operation: .upsert, entity: investments[idx])
            }

        case .investmentRedemption:
            // Se deletou um resgate: devolve (soma) o valor de volta ao saldo apenas se já havia sido debitado (realizado)
            if let invId = entityId ?? tx.linkedInvestmentId,
               let idx = investments.firstIndex(where: { $0.id == invId }) {
                if tx.isPaid {
                    investments[idx].balance += tx.amount
                }
                investments[idx].movements.removeAll { $0.generatedTransactionId == tx.id }
                cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: invId, operation: .upsert, entity: investments[idx])
            }

        case .debtPayment:
            // Se deletou um pagamento de dívida: restaura o status da dívida para "Ativa" e limpa metadados
            if let dId = entityId ?? tx.linkedDebtId,
               let idx = debts.firstIndex(where: { $0.id == dId }) {
                debts[idx].isPaid = false
                debts[idx].negotiatedAmount = nil
                debts[idx].paidDate = nil
                debts[idx].paidFromAccountId = nil
                debts[idx].paymentTransactionId = nil
                cloudSyncService?.recordLocalMutation(entityName: "debt_items", entityId: dId, operation: .upsert, entity: debts[idx])
            }

        case .financingAmortization, .contractSettlement, .loanAmortization, .loanPayoff:
            // Se deletou amortização ou quitação de contrato: reverte o saldo e recalcula o motor
            if let cId = entityId ?? tx.linkedContractId,
               let idx = contracts.firstIndex(where: { $0.id == cId }) {
                revertContractAmortizationOrSettlement(contractIndex: idx, tx: tx)
            }

        case .plannedAmortization:
            // Se deletou uma amortização planejada na lista de transações: remove o item do plano (Camada 2)
            for pIdx in amortizationPlans.indices {
                amortizationPlans[pIdx].items.removeAll { item in
                    item.linkedTransactionId == tx.id || item.id == tx.linkedEntityID
                }
                amortizationPlans[pIdx].updatedAt = effectiveCurrentDate
            }

        case .standard, .quotaAllocation, .internalTransfer:
            break
        }
    }

    private func revertContractAmortizationOrSettlement(contractIndex: Int, tx: FinancialTransaction) {
        var contract = contracts[contractIndex]

        // 1. Localiza e remove o registro correspondente no histórico de amortizações
        let recordIdx = contract.amortizationHistory.firstIndex(where: { $0.transactionId == tx.id })
        let record = recordIdx.map { contract.amortizationHistory.remove(at: $0) }

        // 2. Restauração de Status (se estava marcado como quitado devido a essa transação)
        if contract.isSettled {
            contract.isSettled = false
            contract.settledAmount = nil
            contract.settledDate = nil
            contract.settledAccountId = nil
        }

        // 3. Reversão do Saldo Devedor
        let effectiveAmort = record?.effectiveAmortization ?? tx.amount
        let restoredBalance: Double
        if let prevBal = record?.previousBalance, prevBal > 0.01 {
            restoredBalance = prevBal
        } else {
            let currentBal = contract.outstandingBalance ?? (contract.kind == .loan ? (contract.loanDetails?.balance ?? 0.0) : (contract.financingDetails?.balance ?? 0.0))
            restoredBalance = currentBal + effectiveAmort
        }

        contract.outstandingBalance = restoredBalance
        if contract.kind == .financing && contract.financingDetails != nil {
            contract.financingDetails?.balance = restoredBalance
        }
        if contract.kind == .loan && contract.loanDetails != nil {
            contract.loanDetails?.balance = restoredBalance
        }
        contract.extraAmortizedTotal = max(0.0, contract.extraAmortizedTotal - effectiveAmort)

        // 4. Recálculo Inverso do Motor
        let mode = record?.mode ?? .reduceTerm
        let currentRem = record?.previousRemainingInstallments ?? remainingInstallmentsCount(for: contract)
        let currentInst = record?.previousInstallmentAmount ?? contract.installmentAmount

        let targetRemaining: Int
        let targetInstallment: Double

        if contract.kind == .loan {
            let recalc = LoanAmortizationEngine.recalculate(
                balance: restoredBalance,
                monthlyInterestRate: contract.monthlyInterestRate,
                installmentValue: currentInst,
                currentRemainingInstallments: currentRem,
                mode: mode
            )
            targetRemaining = record?.previousRemainingInstallments ?? recalc.remainingInstallments
            targetInstallment = record?.previousInstallmentAmount ?? recalc.installmentValue

            if contract.loanDetails != nil {
                contract.loanDetails?.balance = restoredBalance
                contract.loanDetails?.remainingInstallments = targetRemaining
                contract.loanDetails?.installmentValue = targetInstallment
                contract.loanDetails?.totalInstallments = max(contract.totalInstallments, contract.pastInstallmentsElapsedAtCreation + targetRemaining)
            }
        } else {
            let recalc = AmortizationEngine.recalculate(
                balance: restoredBalance,
                annualNominalRate: contract.effectiveAnnualNominalRate,
                basePriceInstallment: contract.effectiveBaseInstallmentPrice,
                totalInstallmentAmount: currentInst,
                currentRemainingInstallments: currentRem,
                mode: mode,
                amortizationSystem: contract.amortizationSystem,
                adminFee: contract.effectiveAdminFee,
                insuranceFee: contract.effectiveInsuranceFee
            )
            targetRemaining = record?.previousRemainingInstallments ?? recalc.remainingInstallments
            targetInstallment = record?.previousInstallmentAmount ?? recalc.installmentAmount

            if contract.financingDetails != nil {
                contract.financingDetails?.balance = restoredBalance
                contract.financingDetails?.remainingInstallments = targetRemaining
                contract.financingDetails?.totalInstallmentAmount = targetInstallment
                contract.financingDetails?.totalInstallments = max(contract.totalInstallments, contract.pastInstallmentsElapsedAtCreation + targetRemaining)
            }
        }

        let paidInApp = transactions.filter { $0.linkedContractId == contract.id && $0.isPaid && $0.installmentIndex != nil }.count
        let minRequiredTotal = contract.pastInstallmentsElapsedAtCreation + paidInApp + targetRemaining
        if contract.totalInstallments < minRequiredTotal {
            contract.totalInstallments = minRequiredTotal
        }

        contract.installmentAmount = targetInstallment
        contract.originalTotalInstallments = contract.effectiveOriginalTotalInstallments

        // 5. Restauração das Parcelas Futuras Removidas
        restoreMissingFutureContractTransactions(
            contract: contract,
            targetRemaining: targetRemaining,
            targetInstallment: targetInstallment
        )

        contracts[contractIndex] = contract
        cloudSyncService?.recordLocalMutation(entityName: "credit_contracts", entityId: contract.id, operation: .upsert, entity: contract)
    }

    private func restoreMissingFutureContractTransactions(
        contract: CreditContract,
        targetRemaining: Int,
        targetInstallment: Double
    ) {
        let existingUnpaid = transactions
            .filter { $0.linkedContractId == contract.id && !$0.isPaid && $0.installmentIndex != nil }
            .sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }

        // Atualiza parcelas existentes não pagas com a prestação restaurada
        let existingIds = Set(existingUnpaid.map(\.id))
        for idx in transactions.indices {
            if existingIds.contains(transactions[idx].id) {
                transactions[idx].amount = targetInstallment
                transactions[idx].installmentTotal = contract.totalInstallments
                if let instIdx = transactions[idx].installmentIndex {
                    transactions[idx].name = "\(contract.name) - Parcela \(instIdx)/\(contract.totalInstallments)"
                }
            }
        }

        let missingCount = targetRemaining - existingUnpaid.count
        guard missingCount > 0 else { return }

        let paidInApp = transactions.filter { $0.linkedContractId == contract.id && $0.isPaid && $0.installmentIndex != nil }.count
        let creditCategoryId = contract.categoryId

        let startInstallmentNumber: Int
        let baseDate: Date

        if let lastTx = existingUnpaid.last {
            startInstallmentNumber = (lastTx.installmentIndex ?? (contract.pastInstallmentsElapsedAtCreation + paidInApp + existingUnpaid.count)) + 1
            baseDate = lastTx.date
        } else {
            startInstallmentNumber = contract.pastInstallmentsElapsedAtCreation + paidInApp + 1
            let computed = computePastInstallmentsAndFirstFutureDate(
                startDate: contract.startDate,
                billingDay: contract.billingDay,
                totalInstallments: contract.totalInstallments,
                referenceDate: Date()
            )
            baseDate = computed.firstFutureBillingDate
        }

        for offset in 0..<missingCount {
            let installmentNumber = startInstallmentNumber + offset
            let dueDate: Date
            if existingUnpaid.isEmpty {
                dueDate = calendar.date(byAdding: .month, value: offset, to: baseDate) ?? baseDate
            } else {
                dueDate = calendar.date(byAdding: .month, value: offset + 1, to: baseDate) ?? baseDate
            }

            let newTx = FinancialTransaction(
                name: "\(contract.name) - Parcela \(installmentNumber)/\(contract.totalInstallments)",
                details: "\(contract.kind.title) (\(contract.subtypeDisplayName)) • Juros \(String(format: "%.2f", contract.monthlyInterestRate))% a.m.",
                amount: targetInstallment,
                date: dueDate,
                type: .expense,
                isPaid: false,
                categoryId: creditCategoryId,
                accountId: contract.accountId,
                ignoreInConsolidated: false,
                recurrenceMode: .installment,
                seriesGroupId: contract.id,
                installmentIndex: installmentNumber,
                installmentTotal: contract.totalInstallments,
                linkedContractId: contract.id,
                transactionOrigin: .standard,
                linkedEntityID: contract.id
            )
            transactions.append(newTx)
        }
    }

    private func sortTransactions() {
        transactions.sort { a, b in
            if a.date == b.date {
                return a.createdAt > b.createdAt
            }
            return a.date > b.date
        }
    }

    // MARK: - Statement Import with Deduplication

    public struct ImportSummary {
        public let totalEvaluated: Int
        public let addedCount: Int
        public let skippedDuplicatesCount: Int
        public let addedExpenses: Int
        public let addedIncomes: Int
    }

    public func transactionAlreadyExists(_ candidate: ParsedStatementTransaction, inAccountId accountId: UUID) -> Bool {
        transactions.contains { existing in
            guard existing.accountId == accountId else { return false }
            guard existing.type == candidate.type else { return false }
            guard calendar.isDate(existing.date, inSameDayAs: candidate.date) else { return false }
            guard abs(existing.amount - candidate.amount) < 0.009 else { return false }

            if let existingRaw = existing.rawStatementLine, !existingRaw.isEmpty {
                return existingRaw.caseInsensitiveCompare(candidate.rawLine) == .orderedSame &&
                       existing.statementOccurrenceIndex == candidate.occurrenceIndex
            }

            let strippedExistingName = Self.stripInstallmentSuffix(from: existing.name)
            return strippedExistingName.caseInsensitiveCompare(candidate.cleanTitle) == .orderedSame &&
                   existing.statementOccurrenceIndex == candidate.occurrenceIndex
        }
    }

    public func resolveOrCreateCategoryId(named explicitName: String, for type: TransactionType) -> UUID {
        let trimmed = explicitName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallbackCategoryId(for: type)
        }
        let foldedTarget = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()

        let sameTypeCategories = categories(for: type)
        if let direct = sameTypeCategories.first(where: { cat in
            let foldedCat = cat.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                .lowercased()
            return foldedCat.contains(foldedTarget) || foldedTarget.contains(foldedCat)
        }) {
            return direct.id
        }

        if let kwMatch = sameTypeCategories.first(where: { cat in
            cat.keywords.contains { kw in
                let foldedKw = kw
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                    .lowercased()
                return !foldedKw.isEmpty && (foldedTarget.contains(foldedKw) || foldedKw.contains(foldedTarget))
            }
        }) {
            return kwMatch.id
        }

        let iconAndColor: (icon: String, color: String) = {
            if foldedTarget.contains("cuidado") || foldedTarget.contains("beleza") || foldedTarget.contains("estetica") {
                return ("scissors", "#EC4899")
            }
            if foldedTarget.contains("educac") || foldedTarget.contains("curso") || foldedTarget.contains("faculdade") {
                return ("graduationcap.fill", "#8B5CF6")
            }
            if foldedTarget.contains("pet") {
                return ("pawprint.fill", "#84CC16")
            }
            if foldedTarget.contains("salario") || foldedTarget.contains("remunerac") {
                return ("banknote.fill", "#10B981")
            }
            return (type == .expense ? "tag.fill" : "plus.circle.fill", type == .expense ? "#6366F1" : "#10B981")
        }()

        let newCat = CategoryItem(
            name: trimmed.prefix(1).uppercased() + trimmed.dropFirst(),
            type: type,
            iconSymbol: iconAndColor.icon,
            colorHex: iconAndColor.color,
            keywords: [trimmed.uppercased()],
            isSystemDefault: false
        )
        categories.append(newCat)
        return newCat.id
    }

    public func importParsedTransactions(
        _ parsedList: [ParsedStatementTransaction],
        intoAccountId accountId: UUID,
        filterMode: StatementImportFilterMode
    ) -> ImportSummary {
        let filtered = parsedList.filter { item in
            switch filterMode {
            case .hybrid: return true
            case .expensesOnly: return item.type == .expense
            case .incomesOnly: return item.type == .income
            }
        }

        var added = 0
        var skipped = 0
        var addedExp = 0
        var addedInc = 0

        for item in filtered {
            if transactionAlreadyExists(item, inAccountId: accountId) {
                skipped += 1
                continue
            }

            let resolvedCategoryId: UUID = {
                if let explicit = item.explicitCategoryName, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return resolveOrCreateCategoryId(named: explicit, for: item.type)
                }
                if let suggested = item.suggestedCategoryId, category(for: suggested) != nil {
                    return suggested
                }
                return fallbackCategoryId(for: item.type)
            }()

            let effectiveFirstPaid = !isDateInFuture(item.date)

            if item.recurrenceMode == .installment && item.type == .expense && item.installmentsCount >= 2 {
                let totalFullAmount = item.amount * Double(item.installmentsCount)
                let createdSeries = createTransaction(
                    name: item.cleanTitle,
                    details: item.extractedDetails,
                    amount: totalFullAmount,
                    date: item.date,
                    type: .expense,
                    isPaid: effectiveFirstPaid,
                    categoryId: resolvedCategoryId,
                    accountId: accountId,
                    ignoreInConsolidated: false,
                    recurrenceMode: .installment,
                    installmentsOrMonthsCount: item.installmentsCount
                )
                if let firstId = createdSeries.first?.id,
                   let idx = transactions.firstIndex(where: { $0.id == firstId }) {
                    transactions[idx].rawStatementLine = item.rawLine
                    transactions[idx].statementOccurrenceIndex = item.occurrenceIndex
                }
                added += 1
                addedExp += 1
            } else if item.recurrenceMode == .repeated && item.installmentsCount >= 2 {
                let createdSeries = createTransaction(
                    name: item.cleanTitle,
                    details: item.extractedDetails,
                    amount: item.amount,
                    date: item.date,
                    type: item.type,
                    isPaid: effectiveFirstPaid,
                    categoryId: resolvedCategoryId,
                    accountId: accountId,
                    ignoreInConsolidated: false,
                    recurrenceMode: .repeated,
                    installmentsOrMonthsCount: item.installmentsCount
                )
                if let firstId = createdSeries.first?.id,
                   let idx = transactions.firstIndex(where: { $0.id == firstId }) {
                    transactions[idx].rawStatementLine = item.rawLine
                    transactions[idx].statementOccurrenceIndex = item.occurrenceIndex
                }
                added += 1
                if item.type == .expense { addedExp += 1 } else { addedInc += 1 }
            } else if item.recurrenceMode == .recurring {
                let createdSeries = createTransaction(
                    name: item.cleanTitle,
                    details: item.extractedDetails,
                    amount: item.amount,
                    date: item.date,
                    type: item.type,
                    isPaid: effectiveFirstPaid,
                    categoryId: resolvedCategoryId,
                    accountId: accountId,
                    ignoreInConsolidated: false,
                    recurrenceMode: .recurring,
                    recurrenceFrequency: item.recurrenceFrequency
                )
                if let firstId = createdSeries.first?.id,
                   let idx = transactions.firstIndex(where: { $0.id == firstId }) {
                    transactions[idx].rawStatementLine = item.rawLine
                    transactions[idx].statementOccurrenceIndex = item.occurrenceIndex
                }
                added += 1
                if item.type == .expense { addedExp += 1 } else { addedInc += 1 }
            } else {
                let tx = FinancialTransaction(
                    name: item.cleanTitle,
                    details: item.extractedDetails,
                    amount: item.amount,
                    date: item.date,
                    type: item.type,
                    isPaid: effectiveFirstPaid,
                    categoryId: resolvedCategoryId,
                    accountId: accountId,
                    ignoreInConsolidated: false,
                    recurrenceMode: .single,
                    rawStatementLine: item.rawLine,
                    statementOccurrenceIndex: item.occurrenceIndex
                )
                transactions.append(tx)
                added += 1
                if item.type == .expense { addedExp += 1 } else { addedInc += 1 }
            }
        }

        sortTransactions()
        save()
        return ImportSummary(
            totalEvaluated: filtered.count,
            addedCount: added,
            skippedDuplicatesCount: skipped,
            addedExpenses: addedExp,
            addedIncomes: addedInc
        )
    }

    // MARK: - Investments Management

    public var investmentGroups: [String] {
        let names = Set(investments.map(\.groupName))
        return Array(names).sorted()
    }

    public func investments(inGroup groupName: String) -> [InvestmentItem] {
        investments.filter { $0.groupName == groupName }
    }

    public func addInvestment(
        name: String,
        groupName: String,
        investmentAccountId: UUID,
        initialBalance: Double = 0.0,
        showInConsolidated: Bool = true,
        iconSymbol: String = "chart.line.uptrend.xyaxis",
        colorHex: String = "#10B981",
        notes: String = ""
    ) {
        let item = InvestmentItem(
            name: name,
            groupName: groupName,
            investmentAccountId: investmentAccountId,
            balance: max(initialBalance, 0),
            showInConsolidated: showInConsolidated,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            notes: notes
        )
        investments.append(item)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: item.id, operation: .upsert, entity: item)
    }

    public func toggleInvestmentConsolidated(_ investmentId: UUID) {
        if let idx = investments.firstIndex(where: { $0.id == investmentId }) {
            investments[idx].showInConsolidated.toggle()
            let isConsolidated = investments[idx].showInConsolidated
            let today = calendar.startOfDay(for: Date())

            // Sincroniza transações previstas de resgate futuro:
            // Se o investimento agora está no consolidado, marcação (ignoreInConsolidated = true) para evitar duplicidade.
            // Se agora não está no consolidado, passa a ser exibido nos dashboards e transações (ignoreInConsolidated = false).
            for txIdx in transactions.indices {
                if transactions[txIdx].linkedInvestmentId == investmentId,
                   transactions[txIdx].transactionOrigin == .investmentRedemption,
                   calendar.startOfDay(for: transactions[txIdx].date) > today {
                    transactions[txIdx].ignoreInConsolidated = isConsolidated
                    cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: transactions[txIdx].id, operation: .upsert, entity: transactions[txIdx])
                }
            }

            save()
            cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: investmentId, operation: .upsert, entity: investments[idx])
        }
    }

    public func deleteInvestment(_ investmentId: UUID) {
        investments.removeAll(where: { $0.id == investmentId })
        save()
        cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: investmentId, operation: .delete)
    }

    /// Investir (aportar) ou resgatar:
    /// Seleciona de qual conta quer tirar o valor (`sourceAccountId`) e em qual conta está o investimento (`investmentAccountId`),
    /// tirando o valor da conta de origem e adicionando no investimento.
    public func contributeToInvestment(
        investmentId: UUID,
        amount: Double,
        sourceAccountId: UUID,
        investmentAccountId: UUID,
        date: Date = Date(),
        movementType: InvestmentMovementType = .deposit,
        notes: String = ""
    ) {
        guard let idx = investments.firstIndex(where: { $0.id == investmentId }) else { return }
        let cleanAmount = abs(amount)
        guard cleanAmount > 0 else { return }

        investments[idx].investmentAccountId = investmentAccountId

        let investmentName = investments[idx].name
        let groupName = investments[idx].groupName
        let sourceAccountName = account(for: sourceAccountId)?.name ?? "Conta"
        let destAccountName = account(for: investmentAccountId)?.name ?? "Conta Investimento"

        let today = calendar.startOfDay(for: Date())
        let movementDay = calendar.startOfDay(for: date)
        let isFuture = movementDay > today

        let txType: TransactionType = movementType == .deposit ? .expense : .income
        let categoryId: UUID = {
            if movementType == .deposit {
                return investmentDepositCategoryId()
            } else {
                return fallbackCategoryId(for: .income, matchingSubstring: "Resgate")
            }
        }()

        let txTitle: String
        let txDetails: String
        if movementType == .deposit {
            txTitle = isFuture
                ? "Aporte Previsto: \(investmentName) (\(groupName))"
                : "Aporte: \(investmentName) (\(groupName))"
            txDetails = "Saída de \(sourceAccountName) para investimento em \(destAccountName). \(notes)"
        } else {
            txTitle = isFuture
                ? "Resgate Previsto: \(investmentName) (\(groupName))"
                : "Resgate: \(investmentName) (\(groupName))"
            txDetails = "Resgate de \(destAccountName) para \(sourceAccountName). \(notes)"
        }

        // Regra de transações para resgate futuro:
        // Se o card não estiver marcado para exibir no consolidado (!showInConsolidated),
        // o valor previsto de saque passa a ser exibido nos dashboards e transações na data marcada (ignoreInConsolidated = false).
        // Se estiver marcado no consolidado (showInConsolidated == true), aparece apenas a transação como marcação
        // (ignoreInConsolidated = true) para evitar duplicidade com o saldo do investimento.
        let ignoreInConsolidated: Bool = {
            if movementType == .withdrawal && isFuture {
                return investments[idx].showInConsolidated
            }
            return false
        }()

        let tx = FinancialTransaction(
            name: txTitle,
            details: txDetails.trimmingCharacters(in: .whitespaces),
            amount: cleanAmount,
            date: date,
            type: txType,
            isPaid: !isFuture,
            categoryId: categoryId,
            accountId: sourceAccountId,
            ignoreInConsolidated: ignoreInConsolidated,
            recurrenceMode: .single,
            linkedInvestmentId: investmentId,
            transactionOrigin: movementType == .deposit ? .investmentDeposit : .investmentRedemption,
            linkedEntityID: investmentId
        )
        transactions.append(tx)

        // No card principal segue o mesmo saldo acumulado se for previsão/futuro
        if !isFuture {
            if movementType == .deposit {
                investments[idx].balance += cleanAmount
            } else {
                investments[idx].balance = max(0, investments[idx].balance - cleanAmount)
            }
        }

        let movement = InvestmentMovement(
            type: movementType,
            amount: cleanAmount,
            date: date,
            sourceAccountId: sourceAccountId,
            investmentAccountId: investmentAccountId,
            notes: notes,
            generatedTransactionId: tx.id
        )
        investments[idx].movements.insert(movement, at: 0)

        sortTransactions()
        save()
        cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: investmentId, operation: .upsert, entity: investments[idx])
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: tx.id, operation: .upsert, entity: tx)
    }

    public func recordInvestmentMovement(
        investmentId: UUID,
        type: InvestmentMovementType,
        amount: Double,
        sourceAccountId: UUID,
        date: Date = Date(),
        notes: String = ""
    ) {
        guard let inv = investments.first(where: { $0.id == investmentId }) else { return }
        contributeToInvestment(
            investmentId: investmentId,
            amount: amount,
            sourceAccountId: sourceAccountId,
            investmentAccountId: inv.investmentAccountId,
            date: date,
            movementType: type,
            notes: notes
        )
    }

    public func investmentMovements(for investmentId: UUID) -> [InvestmentMovement] {
        guard let inv = investments.first(where: { $0.id == investmentId }) else { return [] }
        var result = inv.movements
        let knownTxIds = Set(result.compactMap(\.generatedTransactionId))

        let orphanTxs = transactions.filter { tx in
            (tx.linkedInvestmentId == investmentId || tx.linkedEntityID == investmentId) &&
            !knownTxIds.contains(tx.id)
        }
        for tx in orphanTxs {
            let isDeposit = tx.transactionOrigin == .investmentDeposit || tx.type == .expense
            let mov = InvestmentMovement(
                id: tx.id,
                type: isDeposit ? .deposit : .withdrawal,
                amount: tx.amount,
                date: tx.date,
                sourceAccountId: tx.accountId,
                investmentAccountId: inv.investmentAccountId,
                notes: tx.details.isEmpty ? tx.name : tx.details,
                generatedTransactionId: tx.id
            )
            result.append(mov)
        }
        return result.sorted(by: { $0.date > $1.date })
    }

    public func deleteInvestmentMovement(investmentId: UUID, movementId: UUID) {
        guard let invIdx = investments.firstIndex(where: { $0.id == investmentId }) else { return }
        let movement = investments[invIdx].movements.first(where: { $0.id == movementId })

        if let txId = movement?.generatedTransactionId ?? transactions.first(where: { $0.id == movementId })?.id,
           transactions.contains(where: { $0.id == txId }) {
            deleteTransaction(txId)
            if let currentIdx = investments.firstIndex(where: { $0.id == investmentId }) {
                investments[currentIdx].movements.removeAll(where: { $0.id == movementId || $0.generatedTransactionId == txId })
            }
        } else if let mov = movement {
            let today = calendar.startOfDay(for: Date())
            let isPastOrToday = calendar.startOfDay(for: mov.date) <= today
            if isPastOrToday {
                if mov.type == .deposit {
                    investments[invIdx].balance = max(0.0, investments[invIdx].balance - mov.amount)
                } else {
                    investments[invIdx].balance += mov.amount
                }
            }
            investments[invIdx].movements.removeAll(where: { $0.id == movementId })
            save()
            cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: investmentId, operation: .upsert, entity: investments[invIdx])
        }
    }

    public func investmentTimeline(
        for investmentId: UUID,
        year: Int,
        period: InvestmentPeriodFilter = .oneYear
    ) -> [InvestmentMonthlyMovementPoint] {
        guard let inv = investments.first(where: { $0.id == investmentId }) else { return [] }
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }

        let allMovs = investmentMovements(for: investmentId)

        let shortMonthDf = DateFormatter()
        shortMonthDf.locale = Locale(identifier: "pt_BR")
        shortMonthDf.dateFormat = "MMM"

        let ymDf = DateFormatter()
        ymDf.locale = Locale(identifier: "pt_BR")
        ymDf.dateFormat = "MMM/yy"

        // 1. Data em que o investimento foi iniciado/incluído
        let startRefDate = ([inv.createdAt] + allMovs.map(\.date)).min() ?? inv.createdAt
        let startYear = calendar.component(.year, from: startRefDate)
        let startMonth = calendar.component(.month, from: startRefDate)

        // 2. Saldo inicial do investimento na sua criação:
        // Estorna do saldo atual todos os aportes e resgates já realizados (data <= hoje)
        let pastRealizedDeposits = allMovs
            .filter { $0.type == .deposit && calendar.startOfDay(for: $0.date) <= today }
            .reduce(0.0) { $0 + $1.amount }
        let pastRealizedWithdrawals = allMovs
            .filter { $0.type == .withdrawal && calendar.startOfDay(for: $0.date) <= today }
            .reduce(0.0) { $0 + $1.amount }
        let initialBalanceAtStart = max(0.0, inv.balance - pastRealizedDeposits + pastRealizedWithdrawals)

        // 3. Simulação cronológica mês a mês a partir do início do investimento
        // Para qualquer mês antes de (startYear, startMonth), o saldo e movimentações são ZERO (gráfico vazio).
        var monthlyState: [String: (base: Double, dep: Double, with: Double, projDep: Double, projWith: Double, end: Double)] = [:]
        var runningBalance = initialBalanceAtStart

        let maxSimYear = max(year, currentYear)
        if startYear <= maxSimYear {
            for y in startYear...maxSimYear {
                for m in 1...12 {
                    let ymKey = String(format: "%04d-%02d", y, m)
                    guard let monthStart = calendar.date(from: DateComponents(year: y, month: m, day: 1)) else { continue }

                    // Se o mês for anterior à inclusão do investimento, tudo é 0
                    if y < startYear || (y == startYear && m < startMonth) {
                        monthlyState[ymKey] = (base: 0.0, dep: 0.0, with: 0.0, projDep: 0.0, projWith: 0.0, end: 0.0)
                        continue
                    }

                    let isPast = (y < currentYear) || (y == currentYear && m < currentMonth)
                    let isCurrent = (y == currentYear && m == currentMonth)

                    var monthDeposits: Double = 0.0
                    var monthWithdrawals: Double = 0.0
                    var monthProjDeposits: Double = 0.0
                    var monthProjWithdrawals: Double = 0.0

                    if isPast {
                        for mov in allMovs where isInMonth(mov.date, monthReference: monthStart) {
                            if mov.type == .deposit {
                                monthDeposits += mov.amount
                            } else {
                                monthWithdrawals += mov.amount
                            }
                        }
                        let base = runningBalance
                        let end = max(0.0, base + monthDeposits - monthWithdrawals)
                        runningBalance = end
                        monthlyState[ymKey] = (base: base, dep: monthDeposits, with: monthWithdrawals, projDep: 0.0, projWith: 0.0, end: end)
                    } else if isCurrent {
                        for mov in allMovs where isInMonth(mov.date, monthReference: monthStart) {
                            if calendar.startOfDay(for: mov.date) <= today {
                                if mov.type == .deposit {
                                    monthDeposits += mov.amount
                                } else {
                                    monthWithdrawals += mov.amount
                                }
                            } else {
                                // Movimentação futura dentro do mês atual
                                if mov.type == .deposit {
                                    monthProjDeposits += mov.amount
                                } else {
                                    monthProjWithdrawals += mov.amount
                                }
                            }
                        }
                        let envelopes = allQuotaEnvelopes(for: monthStart).filter {
                            $0.rule.quotaType == .investment && $0.rule.linkedInvestmentId == investmentId
                        }
                        monthProjDeposits += envelopes.reduce(0.0) { $0 + max(0.0, $1.remainingProvision) }

                        let base = runningBalance
                        let realizedEnd = max(0.0, base + monthDeposits - monthWithdrawals)
                        let end = max(0.0, realizedEnd + monthProjDeposits - monthProjWithdrawals)
                        runningBalance = end
                        monthlyState[ymKey] = (base: base, dep: monthDeposits, with: monthWithdrawals, projDep: monthProjDeposits, projWith: monthProjWithdrawals, end: end)
                    } else {
                        // Futuro
                        for mov in allMovs where isInMonth(mov.date, monthReference: monthStart) {
                            if mov.type == .deposit {
                                monthProjDeposits += mov.amount
                            } else {
                                monthProjWithdrawals += mov.amount
                            }
                        }
                        let envelopes = allQuotaEnvelopes(for: monthStart).filter {
                            $0.rule.quotaType == .investment && $0.rule.linkedInvestmentId == investmentId
                        }
                        monthProjDeposits += envelopes.reduce(0.0) { $0 + $1.totalEstimatedAmount }

                        let base = runningBalance
                        let end = max(0.0, base + monthProjDeposits - monthProjWithdrawals)
                        runningBalance = end
                        monthlyState[ymKey] = (base: base, dep: 0.0, with: 0.0, projDep: monthProjDeposits, projWith: monthProjWithdrawals, end: end)
                    }
                }
            }
        }

        var allPoints: [InvestmentMonthlyMovementPoint] = []
        for m in 1...12 {
            guard let monthStart = calendar.date(from: DateComponents(year: year, month: m, day: 1)) else { continue }
            let ymKey = String(format: "%04d-%02d", year, m)
            let shortLabel = shortMonthDf.string(from: monthStart).capitalized.replacingOccurrences(of: ".", with: "")
            let label = ymDf.string(from: monthStart).capitalized.replacingOccurrences(of: ".", with: "")

            let state = monthlyState[ymKey] ?? (base: 0.0, dep: 0.0, with: 0.0, projDep: 0.0, projWith: 0.0, end: 0.0)

            let isPast = monthStart < currentMonthStart
            let isCurrent = calendar.isDate(monthStart, equalTo: currentMonthStart, toGranularity: .month)
            let isFuture = monthStart > currentMonthStart

            allPoints.append(
                InvestmentMonthlyMovementPoint(
                    yearMonthKey: ymKey,
                    year: year,
                    month: m,
                    label: label,
                    shortLabel: shortLabel,
                    date: monthStart,
                    isPast: isPast,
                    isCurrent: isCurrent,
                    isFuture: isFuture,
                    deposits: state.dep,
                    withdrawals: state.with,
                    projectedDeposits: state.projDep,
                    projectedWithdrawals: state.projWith,
                    baseAccumulated: state.base,
                    endBalance: state.end
                )
            )
        }

        switch period {
        case .oneYear:
            return allPoints
        case .sixMonths:
            if year <= currentYear {
                return Array(allPoints.suffix(6))
            } else {
                return Array(allPoints.prefix(6))
            }
        case .threeMonths:
            if year <= currentYear {
                return Array(allPoints.suffix(3))
            } else {
                return Array(allPoints.prefix(3))
            }
        }
    }

    public func investmentMovementTimeline(
        for investmentId: UUID,
        referenceDate: Date? = nil,
        monthsBack: Int = 5,
        monthsForward: Int = 6
    ) -> [InvestmentMonthlyMovementPoint] {
        let ref = referenceDate ?? Date()
        let now = Date()
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }

        let allMovs = investmentMovements(for: investmentId)

        var points: [InvestmentMonthlyMovementPoint] = []

        let shortMonthDf = DateFormatter()
        shortMonthDf.locale = Locale(identifier: "pt_BR")
        shortMonthDf.dateFormat = "MMM"

        let ymDf = DateFormatter()
        ymDf.locale = Locale(identifier: "pt_BR")
        ymDf.dateFormat = "MMM/yy"

        for offset in (-monthsBack)...monthsForward {
            guard let targetDate = calendar.date(byAdding: .month, value: offset, to: ref),
                  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: targetDate)) else {
                continue
            }

            let year = calendar.component(.year, from: monthStart)
            let month = calendar.component(.month, from: monthStart)
            let ymKey = String(format: "%04d-%02d", year, month)
            let shortLabel = shortMonthDf.string(from: monthStart).capitalized.replacingOccurrences(of: ".", with: "")
            let label = ymDf.string(from: monthStart).capitalized.replacingOccurrences(of: ".", with: "")

            let isPast = monthStart < currentMonthStart
            let isCurrent = monthStart == currentMonthStart
            let isFuture = monthStart > currentMonthStart

            var deposits: Double = 0.0
            var withdrawals: Double = 0.0
            var projectedDeposits: Double = 0.0

            if isPast || isCurrent {
                for m in allMovs where isInMonth(m.date, monthReference: monthStart) {
                    if m.type == .deposit {
                        deposits += m.amount
                    } else {
                        withdrawals += m.amount
                    }
                }
            }

            let envelopes = allQuotaEnvelopes(for: monthStart).filter { env in
                env.rule.quotaType == .investment && env.rule.linkedInvestmentId == investmentId
            }

            if isFuture {
                projectedDeposits = envelopes.reduce(0.0) { $0 + $1.totalEstimatedAmount }
            } else if isCurrent {
                projectedDeposits = envelopes.reduce(0.0) { $0 + max(0.0, $1.remainingProvision) }
            } else {
                projectedDeposits = 0.0
            }

            points.append(
                InvestmentMonthlyMovementPoint(
                    yearMonthKey: ymKey,
                    year: year,
                    month: month,
                    label: label,
                    shortLabel: shortLabel,
                    date: monthStart,
                    isPast: isPast,
                    isCurrent: isCurrent,
                    isFuture: isFuture,
                    deposits: deposits,
                    withdrawals: withdrawals,
                    projectedDeposits: projectedDeposits
                )
            )
        }

        return points
    }

    // MARK: - Debts Management (Aba Dívidas)

    public var activeDebts: [DebtItem] {
        debts.filter { !$0.isPaid }
    }

    public var paidDebts: [DebtItem] {
        debts.filter { $0.isPaid }
    }

    public func addDebt(
        name: String,
        customImagePath: String?,
        bankPresetId: String?,
        iconSymbol: String,
        colorHex: String,
        originalAmount: Double,
        contractedDate: Date?,
        notes: String = ""
    ) {
        let debt = DebtItem(
            name: name,
            customImagePath: customImagePath,
            bankPresetId: bankPresetId,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            originalAmount: originalAmount,
            contractedDate: contractedDate,
            notes: notes
        )
        debts.append(debt)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "debt_items", entityId: debt.id, operation: .upsert, entity: debt)
    }

    public func updateDebt(_ updated: DebtItem) {
        if let idx = debts.firstIndex(where: { $0.id == updated.id }) {
            debts[idx] = updated
            save()
            cloudSyncService?.recordLocalMutation(entityName: "debt_items", entityId: updated.id, operation: .upsert, entity: updated)
        }
    }

    public func deleteDebt(_ debtId: UUID) {
        debts.removeAll(where: { $0.id == debtId })
        save()
        cloudSyncService?.recordLocalMutation(entityName: "debt_items", entityId: debtId, operation: .delete)
    }

    public struct DebtImportSummary {
        public let totalEvaluated: Int
        public let addedCount: Int
        public let skippedDuplicatesCount: Int
    }

    public func debtAlreadyExists(_ candidate: ParsedDebtImportItem) -> Bool {
        let candidateFolded = candidate.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return debts.contains { existing in
            guard !existing.isPaid else { return false }
            let existingFolded = existing.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return existingFolded == candidateFolded && abs(existing.originalAmount - candidate.originalAmount) < 0.01
        }
    }

    public func importParsedDebts(_ parsedList: [ParsedDebtImportItem]) -> DebtImportSummary {
        var added = 0
        var skipped = 0

        for item in parsedList {
            if debtAlreadyExists(item) {
                skipped += 1
                continue
            }
            let debt = DebtItem(
                name: item.name,
                customImagePath: nil,
                bankPresetId: item.bankPresetId,
                iconSymbol: item.iconSymbol,
                colorHex: item.colorHex,
                originalAmount: item.originalAmount,
                contractedDate: item.contractedDate,
                notes: item.notes
            )
            debts.append(debt)
            added += 1
        }

        save()
        return DebtImportSummary(
            totalEvaluated: parsedList.count,
            addedCount: added,
            skippedDuplicatesCount: skipped
        )
    }

    /// Pagar dívida: seleciona de qual conta vai sair o pagamento, mantém o valor original fixo e recebe o "valor da negociação".
    /// Ao confirmar, cria uma transação para esse pagamento e remove o card da listagem de dívidas ativas.
    public func payDebt(
        debtId: UUID,
        fromAccountId accountId: UUID,
        negotiatedAmount: Double,
        paymentDate: Date = Date()
    ) {
        guard let idx = debts.firstIndex(where: { $0.id == debtId }) else { return }
        let debt = debts[idx]
        let cleanNegotiated = abs(negotiatedAmount)
        let discount = debt.originalAmount - cleanNegotiated

        let debtCategoryId = fallbackCategoryId(for: .expense, matchingSubstring: "Dívidas")

        let discountText = discount > 0.01
            ? " (Desconto na negociação: \(BRLFormatters.currency(discount)) sobre valor original de \(BRLFormatters.currency(debt.originalAmount)))"
            : " (Valor original: \(BRLFormatters.currency(debt.originalAmount)))"

        let tx = FinancialTransaction(
            name: "Pagamento Dívida: \(debt.name)",
            details: "Quitação de dívida negociada\(discountText)",
            amount: cleanNegotiated,
            date: paymentDate,
            type: .expense,
            isPaid: true,
            categoryId: debtCategoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedDebtId: debt.id,
            transactionOrigin: .debtPayment,
            linkedEntityID: debt.id
        )
        transactions.append(tx)

        debts[idx].isPaid = true
        debts[idx].negotiatedAmount = cleanNegotiated
        debts[idx].paidDate = paymentDate
        debts[idx].paidFromAccountId = accountId
        debts[idx].paymentTransactionId = tx.id

        sortTransactions()
        save()
    }

    // MARK: - Loans (Empréstimos) & Financings (Financiamentos)

    public func activeContracts(for kind: CreditContractKind) -> [CreditContract] {
        contracts.filter { $0.kind == kind && !$0.isSettled }
    }

    public func settledContracts(for kind: CreditContractKind) -> [CreditContract] {
        contracts.filter { $0.kind == kind && $0.isSettled }
    }

    /// Calcula quantas parcelas ocorreram no passado caso `startDate` seja anterior a `referenceDate`,
    /// e retorna a data da próxima cobrança futura com base na data atual e no `billingDay`.
    public func computePastInstallmentsAndFirstFutureDate(
        startDate: Date?,
        billingDay: Int,
        totalInstallments: Int,
        referenceDate: Date = Date()
    ) -> (pastInstallmentsCount: Int, firstFutureBillingDate: Date) {
        let clampedDay = min(max(billingDay, 1), 28)
        let todayStart = calendar.startOfDay(for: referenceDate)

        // Determina a próxima data de cobrança a partir de hoje (inclusive hoje ou no próximo mês)
        var currentComps = calendar.dateComponents([.year, .month, .day], from: todayStart)
        currentComps.day = clampedDay
        var nextBillingDate = calendar.date(from: currentComps) ?? todayStart
        if nextBillingDate < todayStart {
            nextBillingDate = calendar.date(byAdding: .month, value: 1, to: nextBillingDate) ?? nextBillingDate
        }

        guard let startDate else {
            return (0, nextBillingDate)
        }

        let startDay = calendar.startOfDay(for: startDate)
        if startDay >= todayStart {
            // Data de início é hoje ou no futuro: nenhuma parcela ficou no passado
            var startComps = calendar.dateComponents([.year, .month], from: startDay)
            startComps.day = clampedDay
            var firstDate = calendar.date(from: startComps) ?? startDay
            if firstDate < startDay {
                firstDate = calendar.date(byAdding: .month, value: 1, to: firstDate) ?? firstDate
            }
            return (0, firstDate)
        }

        // Data de início está no passado: contamos quantas datas de cobrança no salário já ocorreram até `todayStart` (inclusive hoje)
        var firstInstallmentComps = calendar.dateComponents([.year, .month], from: startDay)
        firstInstallmentComps.day = clampedDay
        var cursorDate = calendar.date(from: firstInstallmentComps) ?? startDay
        if cursorDate < startDay {
            cursorDate = calendar.date(byAdding: .month, value: 1, to: cursorDate) ?? cursorDate
        }

        var elapsed = 0
        while cursorDate <= todayStart && elapsed < totalInstallments {
            elapsed += 1
            cursorDate = calendar.date(byAdding: .month, value: 1, to: cursorDate) ?? cursorDate
        }

        return (min(elapsed, totalInstallments), cursorDate)
    }

    /// Migra automaticamente contratos Santander DDC já existentes na base para:
    /// 1. Terem o cronograma `scheduledInstallments` com `VLR. PARC` decrescente por parcela.
    /// 2. Contabilizarem as parcelas pagas com base na data de saída do salário (`billingDay <= hoje`) e atualizarem os valores das transações futuras.
    private func migrateExistingSantanderContractsIfNeeded() -> Bool {
        var didMutate = false
        let sampleDoc = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.santanderLoanOCRText,
            expectedKind: .loan
        )
        let todayStart = calendar.startOfDay(for: effectiveCurrentDate)

        for cIdx in contracts.indices {
            var contract = contracts[cIdx]
            guard contract.kind == .loan,
                  !contract.isSettled,
                  (contract.contractNumber == "783694303" || contract.name.localizedCaseInsensitiveContains("Santander")) else {
                continue
            }

            if contract.scheduledInstallments == nil || contract.scheduledInstallments?.isEmpty == true {
                contract.scheduledInstallments = sampleDoc.scheduledInstallments
                didMutate = true
            }

            guard let schedule = contract.scheduledInstallments, !schedule.isEmpty else { continue }
            let scheduleByNumber = Dictionary(uniqueKeysWithValues: schedule.map { ($0.installmentNumber, $0) })

            // Verifica se existem parcelas não pagas cuja data de saída do salário já ocorreu (ex: Parcela 11 em 01/11/2026 <= hoje)
            let clampedBillingDay = min(max(contract.billingDay, 1), 28)
            var newlyElapsedFromSalary = 0
            var txIdsToRemoveAsAlreadyDeducted: Set<UUID> = []

            for tIdx in transactions.indices {
                guard transactions[tIdx].linkedContractId == contract.id,
                      let instNum = transactions[tIdx].installmentIndex else {
                    continue
                }
                // Atualiza o valor da parcela para o VLR. PARC decrescente do demonstrativo
                if let schedItem = scheduleByNumber[instNum],
                   abs(transactions[tIdx].amount - schedItem.amount) > 0.005 {
                    transactions[tIdx].amount = schedItem.amount
                    didMutate = true
                }

                // Se a data de saída do salário desta parcela já passou (<= todayStart) e ela ainda estava como futura não paga:
                if !transactions[tIdx].isPaid {
                    var comps = calendar.dateComponents([.year, .month], from: transactions[tIdx].date)
                    comps.day = clampedBillingDay
                    let salaryDeductionDate = calendar.date(from: comps) ?? transactions[tIdx].date
                    if calendar.startOfDay(for: salaryDeductionDate) <= todayStart && contract.amortizationHistory.isEmpty {
                        txIdsToRemoveAsAlreadyDeducted.insert(transactions[tIdx].id)
                        newlyElapsedFromSalary = max(newlyElapsedFromSalary, instNum)
                    }
                }
            }

            if !txIdsToRemoveAsAlreadyDeducted.isEmpty {
                transactions.removeAll { txIdsToRemoveAsAlreadyDeducted.contains($0.id) }
                if newlyElapsedFromSalary > contract.pastInstallmentsElapsedAtCreation {
                    contract.pastInstallmentsElapsedAtCreation = newlyElapsedFromSalary
                }
                didMutate = true
            }

            if contract.amortizationHistory.isEmpty {
                let remainingUnpaid = transactions
                    .filter { $0.linkedContractId == contract.id && $0.installmentIndex != nil && !$0.isPaid }
                    .sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }
                if !remainingUnpaid.isEmpty {
                    let remainingSum = (remainingUnpaid.reduce(0.0) { $0 + $1.amount } * 100.0).rounded() / 100.0
                    if abs((contract.outstandingBalance ?? 0.0) - remainingSum) > 0.005 {
                        contract.outstandingBalance = remainingSum
                        contract.loanDetails?.balance = remainingSum
                        didMutate = true
                    }
                    if let firstNextAmt = remainingUnpaid.first?.amount,
                       abs(contract.installmentAmount - firstNextAmt) > 0.005 {
                        contract.installmentAmount = firstNextAmt
                        contract.loanDetails?.installmentValue = firstNextAmt
                        didMutate = true
                    }
                }
            }

            contracts[cIdx] = contract
        }

        if didMutate {
            sortTransactions()
        }
        return didMutate
    }

    /// Migra automaticamente contratos CAIXA Habitação (TP) já existentes na base para atribuir
    /// o crescimento médio mensal extraído do demonstrativo de evolução (+R$ 4,08/mês) ao longo de TODAS as parcelas futuras,
    /// mantendo o valor cadastrado base da parcela (R$ 2.658,06) e o Saldo Devedor de quitação (R$ 324.737,86) intactos.
    private func migrateExistingCaixaContractsIfNeeded() -> Bool {
        var didMutate = false
        let sampleCaixaDoc = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.caixaFinancingOCRText,
            expectedKind: .financing
        )
        let baseRegisteredAmount = sampleCaixaDoc.installmentAmount // R$ 2.658,06
        let avgGrowthDouble = sampleCaixaDoc.averageMonthlyInstallmentGrowth ?? ((2658.06 - 2613.19) / 11.0)
        let avgGrowthDec = LoanProjectionEngine.toDecimal(avgGrowthDouble)
        let baseRegisteredDec = LoanProjectionEngine.toDecimal(baseRegisteredAmount)

        for cIdx in contracts.indices {
            var contract = contracts[cIdx]
            guard contract.kind == .financing,
                  !contract.isSettled,
                  (contract.contractNumber == "178770203328-1" || contract.name.localizedCaseInsensitiveContains("CAIXA")) else {
                continue
            }

            if contract.scheduledInstallments == nil || contract.scheduledInstallments?.isEmpty == true {
                contract.scheduledInstallments = sampleCaixaDoc.scheduledInstallments
                didMutate = true
            }
            if contract.averageMonthlyInstallmentGrowth == nil || abs((contract.averageMonthlyInstallmentGrowth ?? 0) - avgGrowthDouble) > 0.0001 {
                contract.averageMonthlyInstallmentGrowth = avgGrowthDouble
                didMutate = true
            }
            if contract.amortizationHistory.isEmpty && abs(contract.installmentAmount - baseRegisteredAmount) > 0.005 {
                contract.installmentAmount = baseRegisteredAmount
                contract.financingDetails?.totalInstallmentAmount = baseRegisteredAmount
                didMutate = true
            }

            // Ordena todas as parcelas futuras não pagas deste financiamento em ordem cronológica (1ª futura até a última)
            let unpaidIndices = transactions.indices
                .filter { idx in
                    transactions[idx].linkedContractId == contract.id &&
                    transactions[idx].installmentIndex != nil &&
                    !transactions[idx].isPaid
                }
                .sorted { a, b in
                    let instA = transactions[a].installmentIndex ?? 0
                    let instB = transactions[b].installmentIndex ?? 0
                    if instA != instB { return instA < instB }
                    return transactions[a].date < transactions[b].date
                }

            for (offset, tIdx) in unpaidIndices.enumerated() {
                let step = offset + 1
                let projCorrectionDec = LoanProjectionEngine.roundCurrency(Decimal(step) * avgGrowthDec)
                let projTotalDec = LoanProjectionEngine.roundCurrency(baseRegisteredDec + projCorrectionDec)
                let projCorrectionDouble = LoanProjectionEngine.toDouble(projCorrectionDec)
                let projTotalDouble = LoanProjectionEngine.toDouble(projTotalDec)

                if abs(transactions[tIdx].amount - projTotalDouble) > 0.005 ||
                   transactions[tIdx].baseInstallmentRegisteredAmount == nil ||
                   transactions[tIdx].projectedInstallmentCorrectionAmount == nil {
                    transactions[tIdx].baseInstallmentRegisteredAmount = baseRegisteredAmount
                    transactions[tIdx].projectedInstallmentCorrectionAmount = projCorrectionDouble
                    transactions[tIdx].amount = projTotalDouble
                    transactions[tIdx].details = "\(contract.kind.title) (\(contract.subtypeDisplayName)) • Valor cadastrado: \(BRLFormatters.currency(baseRegisteredAmount)) • Projeção de correção (+\(step)m): +\(BRLFormatters.currency(projCorrectionDouble)) (Média doc: +\(BRLFormatters.currency(avgGrowthDouble))/mês)"
                    didMutate = true
                }
            }

            contracts[cIdx] = contract
        }

        if didMutate {
            sortTransactions()
        }
        return didMutate
    }

    @discardableResult
    public func createCreditContract(
        kind: CreditContractKind,
        name: String,
        contractNumber: String? = nil,
        loanSubtype: LoanSubtype? = .consignado,
        financingSubtype: FinancingSubtype? = .imovel,
        amortizationSystem: AmortizationSystem = .price,
        totalContractedAmount: Double,
        outstandingBalance: Double? = nil,
        installmentAmount: Double,
        billingDay: Int,
        totalInstallments: Int,
        originalTotalInstallments: Int? = nil,
        monthlyInterestRate: Double,
        startDate: Date?,
        accountId: UUID,
        notes: String = "",
        referenceDate: Date = Date(),
        overridePastInstallmentsCount: Int? = nil,
        overrideFirstFutureBillingDate: Date? = nil,
        annualNominalInterestRate: Double? = nil,
        indexationRate: FinancingIndexation? = nil,
        adminFee: Double? = nil,
        insuranceFee: Double? = nil,
        baseInstallmentAmount: Double? = nil,
        bankDueDay: Int? = nil,
        documentReferenceDate: Date? = nil,
        maturityDate: Date? = nil,
        estimatedMonthlyTR: Double? = nil,
        lastFGTSUsageDate: Date? = nil,
        scheduledInstallments: [ContractInstallmentScheduleItem]? = nil,
        averageMonthlyInstallmentGrowth: Double? = nil
    ) -> CreditContract {
        let creditCategoryId = fallbackCategoryId(for: .expense, matchingSubstring: "Empréstimos")

        let computedSchedule = computePastInstallmentsAndFirstFutureDate(
            startDate: startDate,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            referenceDate: referenceDate
        )
        let clampedBillingDay = min(max(billingDay, 1), 28)
        let effectiveCutoff = calendar.startOfDay(for: max(referenceDate, documentReferenceDate ?? referenceDate))

        var pastCount = min(max(overridePastInstallmentsCount ?? computedSchedule.pastInstallmentsCount, 0), totalInstallments)
        let rawFirstFutureDate = overrideFirstFutureBillingDate ?? computedSchedule.firstFutureBillingDate
        var firstComps = calendar.dateComponents([.year, .month], from: rawFirstFutureDate)
        firstComps.day = clampedBillingDay
        var firstFutureDate = calendar.date(from: firstComps) ?? rawFirstFutureDate

        // Regra de Referência pelo Salário:
        // Quando o contrato já está em andamento (ou possui cronograma importado), qualquer parcela cuja data de
        // desconto no salário (`day = billingDay` no mês de competência) já ocorreu (`<= effectiveCutoff`)
        // já saiu da conta do usuário e deve ser contabilizada como paga.
        if let schedule = scheduledInstallments, !schedule.isEmpty {
            let sortedSchedule = schedule.sorted { $0.installmentNumber < $1.installmentNumber }
            let futureSchedule = sortedSchedule.filter { item in
                guard item.installmentNumber > pastCount else { return false }
                var comps = calendar.dateComponents([.year, .month], from: item.bankDueDate)
                comps.day = clampedBillingDay
                let salaryDate = calendar.date(from: comps) ?? item.bankDueDate
                return calendar.startOfDay(for: salaryDate) > effectiveCutoff
            }
            let adjustedPastCount = min(totalInstallments, max(pastCount, totalInstallments - futureSchedule.count))
            pastCount = adjustedPastCount
            if let firstFutureItem = futureSchedule.first {
                var comps = calendar.dateComponents([.year, .month], from: firstFutureItem.bankDueDate)
                comps.day = clampedBillingDay
                firstFutureDate = calendar.date(from: comps) ?? firstFutureDate
            } else {
                while calendar.startOfDay(for: firstFutureDate) <= effectiveCutoff {
                    firstFutureDate = calendar.date(byAdding: .month, value: 1, to: firstFutureDate) ?? firstFutureDate
                }
            }
        } else if (startDate != nil && calendar.startOfDay(for: startDate!) < effectiveCutoff) || overrideFirstFutureBillingDate != nil {
            while calendar.startOfDay(for: firstFutureDate) <= effectiveCutoff && pastCount < totalInstallments {
                pastCount += 1
                firstFutureDate = calendar.date(byAdding: .month, value: 1, to: firstFutureDate) ?? firstFutureDate
            }
        }

        let futureScheduledItems: [ContractInstallmentScheduleItem] = (scheduledInstallments ?? [])
            .filter { $0.installmentNumber > pastCount }
            .sorted { $0.installmentNumber < $1.installmentNumber }

        let initialLoanBalance: Double? = {
            if kind == .loan,
               !futureScheduledItems.isEmpty,
               let schedule = scheduledInstallments,
               futureScheduledItems.count < schedule.count {
                // Uma ou mais parcelas da tabela "PARCELAS A VENCER" do banco já saíram do salário (ex: Parcela 11 no 1º dia útil):
                // o saldo devedor restante para as parcelas futuras é a soma exata dos VLR. PARC (D0) das parcelas futuras (12..36).
                let remainingD0 = (futureScheduledItems.reduce(0.0) { $0 + $1.amount } * 100.0).rounded() / 100.0
                if let explicit = outstandingBalance {
                    return min(explicit, remainingD0)
                }
                return remainingD0
            }
            if let explicit = outstandingBalance { return explicit }
            guard kind == .loan else { return nil }
            if pastCount > 0 {
                let remaining = max(totalInstallments - pastCount, 0)
                return LoanModel.calculatePresentValue(installment: installmentAmount, monthlyRate: monthlyInterestRate, remaining: remaining)
            }
            return totalContractedAmount
        }()

        // Para empréstimos consignados (Santander DDC), `installmentAmount` assume o VLR. PARC da próxima parcela futura;
        // Para financiamentos (Caixa TP), `installmentAmount` preserva o valor base cadastrado da parcela atual do documento (ex: R$ 2.658,06).
        let effectiveNextInstallmentAmount = (kind == .loan)
            ? (futureScheduledItems.first?.amount ?? installmentAmount)
            : installmentAmount

        let resolvedAvgGrowth: Double? = {
            if let explicitGrowth = averageMonthlyInstallmentGrowth, explicitGrowth > 0 {
                return explicitGrowth
            }
            if kind == .financing, futureScheduledItems.count >= 2 {
                let firstAmt = futureScheduledItems[0].amount
                let lastAmt = futureScheduledItems[futureScheduledItems.count - 1].amount
                let steps = Double(futureScheduledItems.count - 1)
                if lastAmt > firstAmt && steps > 0 {
                    return (lastAmt - firstAmt) / steps
                }
            }
            return nil
        }()

        let contract = CreditContract(
            kind: kind,
            name: name,
            contractNumber: contractNumber,
            loanSubtype: kind == .loan ? (loanSubtype ?? .consignado) : nil,
            financingSubtype: kind == .financing ? (financingSubtype ?? .imovel) : nil,
            amortizationSystem: amortizationSystem,
            totalContractedAmount: totalContractedAmount,
            outstandingBalance: initialLoanBalance,
            installmentAmount: effectiveNextInstallmentAmount,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            originalTotalInstallments: originalTotalInstallments ?? totalInstallments,
            monthlyInterestRate: monthlyInterestRate,
            startDate: startDate,
            accountId: accountId,
            categoryId: creditCategoryId,
            pastInstallmentsElapsedAtCreation: pastCount,
            notes: notes,
            annualNominalInterestRate: annualNominalInterestRate,
            indexationRate: indexationRate,
            adminFee: adminFee,
            insuranceFee: insuranceFee,
            baseInstallmentAmount: baseInstallmentAmount,
            bankDueDay: bankDueDay ?? billingDay,
            referenceDate: documentReferenceDate ?? referenceDate,
            maturityDate: maturityDate,
            estimatedMonthlyTR: estimatedMonthlyTR,
            lastFGTSUsageDate: lastFGTSUsageDate,
            scheduledInstallments: scheduledInstallments,
            averageMonthlyInstallmentGrowth: resolvedAvgGrowth
        )
        contracts.append(contract)

        let scheduleByNumber: [Int: ContractInstallmentScheduleItem] = Dictionary(
            uniqueKeysWithValues: (scheduledInstallments ?? []).map { ($0.installmentNumber, $0) }
        )
        let avgGrowthDec = LoanProjectionEngine.toDecimal(resolvedAvgGrowth ?? 0.0)
        let baseRegisteredDec = LoanProjectionEngine.toDecimal(installmentAmount)

        // Gera APENAS as transações futuras a partir da data atual e dia da cobrança:
        // - Em empréstimos Santander DDC: utiliza o VLR. PARC decrescente de cada parcela.
        // - Em financiamentos Caixa TP: mantém o valor base cadastrado (`baseInstallmentRegisteredAmount`) e soma o aumento projetado acumulado (`step * média`)
        //   para garantir previsibilidade a longo prazo em todas as parcelas futuras sem alterar o Saldo Devedor de quitação.
        let remainingToCreate = max(totalInstallments - pastCount, 0)
        for offset in 0..<remainingToCreate {
            let step = offset + 1
            let installmentNumber = pastCount + step
            let dueDate = calendar.date(byAdding: .month, value: offset, to: firstFutureDate)
                ?? firstFutureDate
            let schedItem = scheduleByNumber[installmentNumber]

            let individualInstallmentAmount: Double
            let txBaseRegisteredAmount: Double?
            let txProjectedCorrectionAmount: Double?
            let extraBreakdownNote: String

            if kind == .financing && avgGrowthDec > .zero {
                let projCorrDec = LoanProjectionEngine.roundCurrency(Decimal(step) * avgGrowthDec)
                let projTotalDec = LoanProjectionEngine.roundCurrency(baseRegisteredDec + projCorrDec)
                let projCorrDouble = LoanProjectionEngine.toDouble(projCorrDec)
                let projTotalDouble = LoanProjectionEngine.toDouble(projTotalDec)

                individualInstallmentAmount = projTotalDouble
                txBaseRegisteredAmount = installmentAmount
                txProjectedCorrectionAmount = projCorrDouble
                extraBreakdownNote = " • Valor cadastrado: \(BRLFormatters.currency(installmentAmount)) • Projeção de correção (+\(step)m): +\(BRLFormatters.currency(projCorrDouble)) (Média doc: +\(BRLFormatters.currency(resolvedAvgGrowth ?? 0.0))/mês)"
            } else {
                individualInstallmentAmount = schedItem?.amount ?? installmentAmount
                txBaseRegisteredAmount = nil
                txProjectedCorrectionAmount = nil
                if let p = schedItem?.principalAmount, let j = schedItem?.interestAmount {
                    extraBreakdownNote = " • Amortização: \(BRLFormatters.currency(p)) • Juros: \(BRLFormatters.currency(j))"
                } else {
                    extraBreakdownNote = ""
                }
            }

            let tx = FinancialTransaction(
                name: "\(name) - Parcela \(installmentNumber)/\(totalInstallments)",
                details: "\(contract.kind.title) (\(contract.subtypeDisplayName)) • Juros \(String(format: "%.2f", monthlyInterestRate))% a.m.\(extraBreakdownNote)",
                amount: individualInstallmentAmount,
                date: dueDate,
                type: .expense,
                isPaid: false,
                categoryId: creditCategoryId,
                accountId: accountId,
                ignoreInConsolidated: false,
                recurrenceMode: .installment,
                seriesGroupId: contract.id,
                installmentIndex: installmentNumber,
                installmentTotal: totalInstallments,
                linkedContractId: contract.id,
                baseInstallmentRegisteredAmount: txBaseRegisteredAmount,
                projectedInstallmentCorrectionAmount: txProjectedCorrectionAmount
            )
            transactions.append(tx)
        }

        sortTransactions()
        save()
        return contract
    }

    /// Retorna o Saldo Devedor do contrato (informado/extraído do demonstrativo menos amortizações, ou calculado via Tabela Price / valor presente),
    /// projetado para a data de corte informada (`asOfCutoff`, ex: fim do mês ou 31/12 do ano).
    public func currentOutstandingBalance(for contract: CreditContract, asOf asOfCutoff: Date? = nil) -> Double {
        guard !contract.isSettled else { return 0.0 }

        let lastAmortDate = contract.amortizationHistory.first?.date

        // Para Financiamentos Imobiliários (Tabela Price CAIXA):
        if contract.kind == .financing, let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
            let basePrice = contract.effectiveBaseInstallmentPrice
            let annualRate = contract.effectiveAnnualNominalRate
            let admin = contract.effectiveAdminFee
            let insurance = contract.effectiveInsuranceFee

            let elapsedInApp: Int
            if let asOfCutoff {
                elapsedInApp = transactions.filter { tx in
                    tx.linkedContractId == contract.id &&
                    tx.installmentIndex != nil &&
                    (lastAmortDate == nil || tx.date > lastAmortDate!) &&
                    (tx.isPaid || tx.date <= asOfCutoff)
                }.count
            } else {
                elapsedInApp = transactions.filter { tx in
                    tx.linkedContractId == contract.id &&
                    tx.installmentIndex != nil &&
                    (lastAmortDate == nil || tx.date > lastAmortDate!) &&
                    tx.isPaid
                }.count
            }

            var runningBalance = explicitBalance
            if elapsedInApp > 0 {
                for idx in 1...elapsedInApp {
                    guard runningBalance > 0.01 else { break }
                    let step = AmortizationEngine.calculateNextInstallment(
                        currentBalance: runningBalance,
                        annualNominalRate: annualRate,
                        basePriceInstallment: basePrice,
                        adminFee: admin,
                        insuranceFee: insurance,
                        monthlyTR: 0.0,
                        installmentIndex: idx
                    )
                    runningBalance = step.newBalance
                }
            }
            return max(0.0, runningBalance)
        }

        // Para Empréstimos Convencionais e Consignados (Tabela Price pura ou Cronograma VLR. PARC decrescente D0):
        if contract.kind == .loan {
            let initialBalance = contract.loanDetails?.balance ?? contract.outstandingBalance ?? contract.totalContractedAmount
            guard initialBalance > 0 else { return 0.0 }

            let elapsedTransactions: [FinancialTransaction]
            if let asOfCutoff {
                elapsedTransactions = transactions.filter { tx in
                    tx.linkedContractId == contract.id &&
                    tx.installmentIndex != nil &&
                    (lastAmortDate == nil || tx.date > lastAmortDate!) &&
                    (tx.isPaid || tx.date <= asOfCutoff)
                }
            } else {
                elapsedTransactions = transactions.filter { tx in
                    tx.linkedContractId == contract.id &&
                    tx.installmentIndex != nil &&
                    (lastAmortDate == nil || tx.date > lastAmortDate!) &&
                    tx.isPaid
                }
            }

            // Se o contrato possui cronograma de VLR. PARC decrescente (onde cada parcela já está a valor presente D0),
            // cada parcela paga abate o seu próprio VLR. PARC (D0) do Saldo Devedor D0.
            if let schedule = contract.scheduledInstallments, !schedule.isEmpty {
                let paidD0Sum = elapsedTransactions.reduce(0.0) { $0 + $1.amount }
                return max(0.0, ((initialBalance - paidD0Sum) * 100.0).rounded() / 100.0)
            }

            let monthlyRate = contract.monthlyInterestRate
            let pmt = contract.installmentAmount
            let elapsedInApp = elapsedTransactions.count

            var runningBalance = initialBalance
            if elapsedInApp > 0 {
                for idx in 1...elapsedInApp {
                    guard runningBalance > 0.01 else { break }
                    let step = LoanAmortizationEngine.calculateNextInstallment(
                        currentBalance: runningBalance,
                        monthlyInterestRate: monthlyRate,
                        installmentValue: pmt,
                        installmentIndex: idx
                    )
                    runningBalance = step.newBalance
                }
            }
            return max(0.0, runningBalance)
        }

        if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
            let totalToAmortize = max(contract.totalInstallments - contract.pastInstallmentsElapsedAtCreation, 1)
            let estimatedPrincipalPerInstallment = explicitBalance / Double(totalToAmortize)
            let elapsedInApp: Int
            if let asOfCutoff {
                elapsedInApp = transactions.filter { tx in
                    tx.linkedContractId == contract.id &&
                    tx.installmentIndex != nil &&
                    (lastAmortDate == nil || tx.date > lastAmortDate!) &&
                    (tx.isPaid || tx.date <= asOfCutoff)
                }.count
            } else {
                elapsedInApp = transactions.filter { tx in
                    tx.linkedContractId == contract.id &&
                    tx.installmentIndex != nil &&
                    (lastAmortDate == nil || tx.date > lastAmortDate!) &&
                    tx.isPaid
                }.count
            }
            let reducedByInstallments = Double(elapsedInApp) * estimatedPrincipalPerInstallment
            return max(explicitBalance - reducedByInstallments, 0.0)
        }
        return projectedPayoffAmount(for: contract, asOf: asOfCutoff)
    }

    public func unpaidTransactions(forContract contractId: UUID, after asOfCutoff: Date? = nil) -> [FinancialTransaction] {
        if let asOfCutoff {
            return transactions
                .filter { $0.linkedContractId == contractId && $0.date > asOfCutoff }
                .sorted { $0.date < $1.date }
        } else {
            return transactions
                .filter { $0.linkedContractId == contractId && !$0.isPaid }
                .sorted { $0.date < $1.date }
        }
    }

    public func paidTransactionsCount(forContract contract: CreditContract) -> Int {
        let paidInApp = transactions.filter { $0.linkedContractId == contract.id && $0.isPaid && $0.installmentIndex != nil }.count
        return min(contract.pastInstallmentsElapsedAtCreation + paidInApp, contract.effectiveOriginalTotalInstallments)
    }

    /// Métricas completas de acompanhamento, régua mestra e progresso conquistado do contrato de crédito
    public func progressMetrics(for contract: CreditContract) -> ContractProgressMetrics {
        let original = contract.effectiveOriginalTotalInstallments
        let paidInFlow = paidTransactionsCount(forContract: contract)
        let remaining = contract.isSettled ? 0 : remainingInstallmentsCount(for: contract)
        return ContractProgressMetrics(
            id: contract.id,
            originalTotalInstallments: original,
            paidInFlowCount: paidInFlow,
            remainingCount: remaining,
            isSettled: contract.isSettled
        )
    }

    /// Quantidade de parcelas eliminadas antecipadamente por amortizações extraordinárias
    public func eliminatedInstallmentsCount(for contract: CreditContract) -> Int {
        progressMetrics(for: contract).eliminatedByAmortizationCount
    }

    /// Total de meses superados (pagos no fluxo + eliminados por amortização)
    public func totalOvercomeMonths(for contract: CreditContract) -> Int {
        progressMetrics(for: contract).totalOvercomeMonths
    }

    /// Percentual de conclusão global em relação ao plano original (0.0 a 1.0)
    public func globalCompletionPercentage(for contract: CreditContract) -> Double {
        progressMetrics(for: contract).globalCompletionPercentage
    }

    public func remainingInstallmentsCount(for contract: CreditContract, asOf asOfCutoff: Date? = nil) -> Int {
        guard !contract.isSettled else { return 0 }
        if let asOfCutoff {
            let remainingAfter = unpaidTransactions(forContract: contract.id, after: asOfCutoff)
            if !remainingAfter.isEmpty {
                return remainingAfter.count
            }
            let elapsed = transactions.filter { $0.linkedContractId == contract.id && $0.date <= asOfCutoff }.count
            return max(contract.totalInstallments - contract.pastInstallmentsElapsedAtCreation - elapsed, 0)
        }
        let unpaid = unpaidTransactions(forContract: contract.id).count
        if unpaid > 0 { return unpaid }
        return max(contract.totalInstallments - paidTransactionsCount(forContract: contract), 0)
    }

    public func remainingNominalAmount(for contract: CreditContract, asOf asOfCutoff: Date? = nil) -> Double {
        guard !contract.isSettled else { return 0 }
        if let asOfCutoff {
            let remainingTxs = unpaidTransactions(forContract: contract.id, after: asOfCutoff)
            if !remainingTxs.isEmpty {
                return remainingTxs.reduce(0.0) { $0 + $1.amount }
            }
            return Double(remainingInstallmentsCount(for: contract, asOf: asOfCutoff)) * contract.installmentAmount
        }
        let unpaidTxs = unpaidTransactions(forContract: contract.id)
        if !unpaidTxs.isEmpty {
            return unpaidTxs.reduce(0) { $0 + $1.amount }
        }
        return Double(remainingInstallmentsCount(for: contract)) * contract.installmentAmount
    }

    /// Calcula a "Projeção de valor para quitar" trazendo as parcelas futuras a valor presente (desconto proporcional de juros futuros)
    /// considerando o Saldo Devedor na data de corte informada (`asOfCutoff`), a taxa de juros do contrato, o sistema de amortização (PRICE ou SAC) e o tipo do contrato.
    public func projectedPayoffAmount(for contract: CreditContract, asOf asOfCutoff: Date? = nil) -> Double {
        guard !contract.isSettled else { return 0.0 }
        let n = remainingInstallmentsCount(for: contract, asOf: asOfCutoff)
        guard n > 0 else { return 0.0 }

        // Para Empréstimos Convencionais e Consignados: a quitação é rigorosamente o Saldo Devedor Atual a Valor Presente (PV)
        if contract.kind == .loan {
            let currentBal = currentOutstandingBalance(for: contract, asOf: asOfCutoff)
            if currentBal > 0.01 {
                return currentBal
            }
            return LoanAmortizationEngine.calculatePayoffAmount(
                currentBalance: currentBal,
                monthlyInterestRate: contract.monthlyInterestRate,
                installmentValue: contract.installmentAmount,
                remainingInstallments: n
            )
        }

        let nominalRemaining = remainingNominalAmount(for: contract, asOf: asOfCutoff)
        let pmt = nominalRemaining / Double(max(n, 1))
        let i = contract.monthlyInterestRate / 100.0

        // Se o contrato possui Saldo Devedor explícito (ex: extraído do demonstrativo/evolução bancária)
        // que já representa o principal a valor presente (D0, livre de juros futuros e seguros mensais),
        // a projeção para quitação imediata é o próprio Saldo Devedor atualizado, nunca superior a ele.
        if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
            let currentBal = currentOutstandingBalance(for: contract, asOf: asOfCutoff)
            if currentBal < nominalRemaining - 0.01 {
                return max(currentBal, 0.0)
            }
        }

        guard i > 0.0001 else {
            if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
                return max(min(currentOutstandingBalance(for: contract, asOf: asOfCutoff), nominalRemaining), 0.0)
            }
            return max(nominalRemaining, 0)
        }

        // Valor Presente pelo sistema PRICE: PV = PMT * (1 - (1 + i)^(-n)) / i
        let pvPrice = pmt * (1.0 - pow(1.0 + i, -Double(n))) / i

        let calculatedPayoff: Double
        switch contract.amortizationSystem {
        case .price:
            if contract.kind == .loan, let subtype = contract.loanSubtype {
                let discount = max(nominalRemaining - pvPrice, 0) * subtype.discountFactorMultiplier
                calculatedPayoff = max(nominalRemaining - discount, 0)
            } else {
                calculatedPayoff = min(pvPrice, nominalRemaining)
            }
        case .sac:
            // Em SAC, a amortização mensal de principal é constante e os juros incidem sobre o saldo devedor
            let proportionalPrincipal = contract.totalContractedAmount * (Double(n) / Double(max(contract.totalInstallments, 1)))
            let estimatedPrincipal = min(max(proportionalPrincipal - contract.extraAmortizedTotal, pvPrice * 0.92), nominalRemaining)
            calculatedPayoff = max(estimatedPrincipal, 0)
        }

        if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
            return max(min(calculatedPayoff, currentOutstandingBalance(for: contract, asOf: asOfCutoff)), 0.0)
        }
        return calculatedPayoff
    }

    /// Total amortizado/pago (fluxo de caixa desembolsado pelo usuário) no período selecionado para o contrato
    public func amortizedAmountInPeriod(for contract: CreditContract, referenceDate: Date, isAnnual: Bool) -> Double {
        transactions
            .filter { tx in
                tx.linkedContractId == contract.id &&
                (isAnnual ? isInYear(tx.date, yearReference: referenceDate) : isInMonth(tx.date, monthReference: referenceDate))
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    /// Retorna a fração de AMORTIZAÇÃO REAL que de fato abateu o principal do contrato no período selecionado (mês ou ano).
    /// Isola a fração real de amortização na Tabela Price (ex: ~R$ 240/mês), separando-a de juros, taxas e seguros.
    public func realAmortizationAmountInPeriod(for contract: CreditContract, referenceDate: Date, isAnnual: Bool) -> Double {
        let periodTransactions = transactions.filter { tx in
            tx.linkedContractId == contract.id &&
            (isAnnual ? isInYear(tx.date, yearReference: referenceDate) : isInMonth(tx.date, monthReference: referenceDate))
        }

        guard !periodTransactions.isEmpty else { return 0.0 }

        if contract.kind == .financing {
            var totalReal = 0.0
            let basePrice = contract.effectiveBaseInstallmentPrice
            let annualRate = contract.effectiveAnnualNominalRate
            let admin = contract.effectiveAdminFee
            let insurance = contract.effectiveInsuranceFee
            let currentBal = currentOutstandingBalance(for: contract)

            for tx in periodTransactions {
                if tx.installmentIndex != nil {
                    let breakdown = AmortizationEngine.calculateNextInstallment(
                        currentBalance: currentBal,
                        annualNominalRate: annualRate,
                        basePriceInstallment: basePrice,
                        adminFee: admin,
                        insuranceFee: insurance
                    )
                    totalReal += breakdown.amortizationAmount
                } else {
                    totalReal += tx.amount
                }
            }
            return totalReal
        } else {
            return periodTransactions.reduce(0.0) { $0 + $1.amount }
        }
    }

    /// Amortizar empréstimo/financiamento: registra pagamento na conta escolhida e recalcula parcelas futuras
    public func amortizeContract(
        contractId: UUID,
        amountPaid: Double,
        accountId: UUID,
        date: Date = Date(),
        mode: AmortizationRecalculationMode,
        proRataInterest: Double = 0.0,
        customNewInstallmentAmount: Double? = nil,
        customNewRemainingInstallments: Int? = nil,
        notes: String = ""
    ) {
        guard let idx = contracts.firstIndex(where: { $0.id == contractId }) else { return }
        var contract = contracts[idx]
        let isLoan = contract.kind == .loan
        let cleanPaid = abs(amountPaid)
        guard cleanPaid > 0 else { return }

        let prevRemaining = remainingInstallmentsCount(for: contract)
        let prevInstallment = contract.installmentAmount
        let currentPV = currentOutstandingBalance(for: contract)

        let isFullPayoff: Bool
        let newInstallment: Double
        let newRemaining: Int
        let effectiveAmortization: Double
        let proRataApplied: Double
        let newBalanceSimulated: Double

        if isLoan {
            let sim = LoanAmortizationEngine.simulateExtraAmortization(
                currentBalance: currentPV,
                monthlyInterestRate: contract.monthlyInterestRate,
                installmentValue: contract.installmentAmount,
                currentRemainingInstallments: prevRemaining,
                extraPayment: cleanPaid,
                proRataInterest: proRataInterest,
                mode: mode
            )
            isFullPayoff = cleanPaid >= (currentPV - 0.01) || sim.newBalance <= 0.01
            effectiveAmortization = sim.effectiveAmortization
            proRataApplied = sim.proRataInterest
            newBalanceSimulated = sim.newBalance
            if isFullPayoff {
                newInstallment = 0.0
                newRemaining = 0
            } else {
                newInstallment = customNewInstallmentAmount ?? sim.newInstallmentAmount
                newRemaining = customNewRemainingInstallments ?? sim.newRemainingInstallments
            }
        } else {
            let sim = AmortizationEngine.simulateExtraAmortization(
                currentBalance: currentPV,
                annualNominalRate: contract.effectiveAnnualNominalRate,
                basePriceInstallment: contract.effectiveBaseInstallmentPrice,
                totalInstallmentAmount: contract.installmentAmount,
                currentRemainingInstallments: prevRemaining,
                extraPayment: cleanPaid,
                proRataInterest: proRataInterest,
                mode: mode,
                adminFee: contract.effectiveAdminFee,
                insuranceFee: contract.effectiveInsuranceFee
            )
            isFullPayoff = cleanPaid >= (currentPV - 0.01) || sim.newBalance <= 0.01
            effectiveAmortization = sim.effectiveAmortization
            proRataApplied = sim.proRataInterest
            newBalanceSimulated = sim.newBalance
            if isFullPayoff {
                newInstallment = 0.0
                newRemaining = 0
            } else {
                newInstallment = customNewInstallmentAmount ?? sim.newInstallmentAmount
                newRemaining = customNewRemainingInstallments ?? sim.newRemainingInstallments
            }
        }

        // Cria transação de saída na conta selecionada
        let proRataNote = proRataApplied > 0 ? " • Juros Pró-rata: \(BRLFormatters.currency(proRataApplied))" : ""
        let payoffNote = isFullPayoff ? " • Quitação Total" : ""
        let txOrigin: TransactionOrigin
        if isLoan {
            txOrigin = isFullPayoff ? .loanPayoff : .loanAmortization
        } else {
            txOrigin = isFullPayoff ? .contractSettlement : .financingAmortization
        }

        let amortTx = FinancialTransaction(
            name: isFullPayoff ? "Quitação: \(contract.name)" : "Amortização: \(contract.name)",
            details: "Amortização extraordinária (\(mode.rawValue)). Amortização Efetiva no Saldo: \(BRLFormatters.currency(effectiveAmortization))\(proRataNote)\(payoffNote). \(notes)".trimmingCharacters(in: .whitespaces),
            amount: cleanPaid,
            date: date,
            type: .expense,
            isPaid: true,
            categoryId: contract.categoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedContractId: contract.id,
            transactionOrigin: txOrigin,
            linkedEntityID: contract.id
        )
        transactions.append(amortTx)

        // Atualiza as parcelas futuras em aberto
        let unpaidList = unpaidTransactions(forContract: contract.id)
        if isFullPayoff || newRemaining == 0 {
            let idsToRemove = Set(unpaidList.map(\.id))
            transactions.removeAll { idsToRemove.contains($0.id) }
            contract.isSettled = true
            contract.settledAmount = cleanPaid
            contract.settledDate = date
            contract.settledAccountId = accountId
            contract.outstandingBalance = 0.0
            if contract.financingDetails != nil {
                contract.financingDetails?.balance = 0.0
                contract.financingDetails?.remainingInstallments = 0
                contract.financingDetails?.totalInstallmentAmount = 0.0
            }
            if contract.loanDetails != nil {
                contract.loanDetails?.balance = 0.0
                contract.loanDetails?.remainingInstallments = 0
                contract.loanDetails?.installmentValue = 0.0
            }
        } else {
            // Se reduziu prazo, remove as últimas parcelas futuras excedentes
            if newRemaining < unpaidList.count {
                let toRemove = unpaidList.suffix(unpaidList.count - newRemaining)
                let removeIds = Set(toRemove.map(\.id))
                transactions.removeAll { removeIds.contains($0.id) }
            }
            // Atualiza o valor das parcelas futuras restantes
            let remainingUnpaidIds = Set(unpaidTransactions(forContract: contract.id).map(\.id))
            let newTotalInstallments = contract.totalInstallments - max(0, prevRemaining - newRemaining)
            contract.totalInstallments = max(newTotalInstallments, 1)
            contract.installmentAmount = newInstallment

            for tIdx in transactions.indices {
                if remainingUnpaidIds.contains(transactions[tIdx].id) {
                    transactions[tIdx].amount = newInstallment
                    transactions[tIdx].installmentTotal = contract.totalInstallments
                    if let instIdx = transactions[tIdx].installmentIndex {
                        transactions[tIdx].name = "\(contract.name) - Parcela \(instIdx)/\(contract.totalInstallments)"
                    }
                }
            }

            contract.outstandingBalance = newBalanceSimulated
            if contract.financingDetails != nil {
                contract.financingDetails?.balance = newBalanceSimulated
                contract.financingDetails?.remainingInstallments = newRemaining
                contract.financingDetails?.totalInstallmentAmount = newInstallment
            }
            if contract.loanDetails != nil {
                contract.loanDetails?.balance = newBalanceSimulated
                contract.loanDetails?.remainingInstallments = newRemaining
                contract.loanDetails?.installmentValue = newInstallment
            }
        }

        contract.extraAmortizedTotal += effectiveAmortization
        contract.originalTotalInstallments = contract.effectiveOriginalTotalInstallments
        let record = AmortizationRecord(
            date: date,
            amountPaid: cleanPaid,
            mode: mode,
            previousInstallmentAmount: prevInstallment,
            newInstallmentAmount: newInstallment,
            previousRemainingInstallments: prevRemaining,
            newRemainingInstallments: newRemaining,
            accountId: accountId,
            transactionId: amortTx.id,
            notes: notes,
            effectiveAmortization: effectiveAmortization,
            previousBalance: currentPV
        )
        contract.amortizationHistory.insert(record, at: 0)
        contracts[idx] = contract

        sortTransactions()
        save()
        cloudSyncService?.recordLocalMutation(entityName: "credit_contracts", entityId: contract.id, operation: .upsert, entity: contract)
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: amortTx.id, operation: .upsert, entity: amortTx)
    }

    /// Quitar empréstimo/financiamento: cria transação de quitação na conta selecionada e remove parcelas futuras
    public func settleContract(
        contractId: UUID,
        finalPayoffAmount: Double,
        accountId: UUID,
        date: Date = Date()
    ) {
        guard let idx = contracts.firstIndex(where: { $0.id == contractId }) else { return }
        var contract = contracts[idx]
        let isLoan = contract.kind == .loan
        let cleanFinal = abs(finalPayoffAmount)
        let nominalRemaining = remainingNominalAmount(for: contract)
        let prevRemaining = remainingInstallmentsCount(for: contract)
        let prevInstallment = contract.installmentAmount
        let currentPV = currentOutstandingBalance(for: contract)

        // Remove todas as parcelas futuras ainda não pagas
        let unpaidIds = Set(unpaidTransactions(forContract: contract.id).map(\.id))
        transactions.removeAll { unpaidIds.contains($0.id) }

        // Cria a transação de quitação na conta selecionada
        let settleTx = FinancialTransaction(
            name: "Quitação: \(contract.name)",
            details: "Quitação integral de \(contract.kind.title.lowercased()) (Saldo nominal: \(BRLFormatters.currency(nominalRemaining)), Saldo Devedor PV: \(BRLFormatters.currency(currentPV)))",
            amount: cleanFinal,
            date: date,
            type: .expense,
            isPaid: true,
            categoryId: contract.categoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedContractId: contract.id,
            transactionOrigin: isLoan ? .loanPayoff : .contractSettlement,
            linkedEntityID: contract.id
        )
        transactions.append(settleTx)

        let record = AmortizationRecord(
            date: date,
            amountPaid: cleanFinal,
            mode: .reduceTerm,
            previousInstallmentAmount: prevInstallment,
            newInstallmentAmount: 0.0,
            previousRemainingInstallments: prevRemaining,
            newRemainingInstallments: 0,
            accountId: accountId,
            transactionId: settleTx.id,
            notes: "Quitação integral",
            effectiveAmortization: currentPV,
            previousBalance: currentPV
        )
        contract.amortizationHistory.insert(record, at: 0)

        contract.isSettled = true
        contract.settledAmount = cleanFinal
        contract.settledDate = date
        contract.settledAccountId = accountId
        contract.outstandingBalance = 0.0
        if contract.financingDetails != nil {
            contract.financingDetails?.balance = 0.0
            contract.financingDetails?.remainingInstallments = 0
            contract.financingDetails?.totalInstallmentAmount = 0.0
        }
        if contract.loanDetails != nil {
            contract.loanDetails?.balance = 0.0
            contract.loanDetails?.remainingInstallments = 0
            contract.loanDetails?.installmentValue = 0.0
        }
        contract.originalTotalInstallments = contract.effectiveOriginalTotalInstallments
        contracts[idx] = contract

        sortTransactions()
        save()
        cloudSyncService?.recordLocalMutation(entityName: "credit_contracts", entityId: contract.id, operation: .upsert, entity: contract)
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: settleTx.id, operation: .upsert, entity: settleTx)
    }

    public func deleteContract(_ contractId: UUID) {
        transactions.removeAll { $0.linkedContractId == contractId || $0.seriesGroupId == contractId }
        amortizationPlans.removeAll { $0.contractId == contractId }
        contracts.removeAll { $0.id == contractId }
        save()
        cloudSyncService?.recordLocalMutation(entityName: "credit_contracts", entityId: contractId, operation: .delete)
    }

    // MARK: - Planejamento Dinâmico de Amortização (Camada 2 — Intenção & Camada 3 — Projeção em Memória)

    /// Retorna o plano de amortização vinculado ao contrato, se existir.
    public func amortizationPlan(for contractId: UUID) -> AmortizationPlan? {
        amortizationPlans.first { $0.contractId == contractId }
    }

    /// Retorna a lista de aportes planejados que expiraram (`status == .expired`) para o contrato.
    public func expiredPlannedAmortizations(for contractId: UUID) -> [PlannedAmortization] {
        guard let plan = amortizationPlan(for: contractId) else { return [] }
        return plan.items
            .filter { $0.status == .expired }
            .sorted { $0.date < $1.date }
    }

    /// Retorna todos os aportes planejados expirados de todos os contratos ativos.
    public var allExpiredPlannedAmortizations: [(contract: CreditContract, item: PlannedAmortization)] {
        var result: [(contract: CreditContract, item: PlannedAmortization)] = []
        for contract in contracts where !contract.isSettled {
            for item in expiredPlannedAmortizations(for: contract.id) {
                result.append((contract: contract, item: item))
            }
        }
        return result
    }

    /// Indica se existe algum planejamento de amortização ativo (com itens `.pending` ou `.expired`).
    public var hasAnyAmortizationPlan: Bool {
        amortizationPlans.contains { plan in
            plan.items.contains { $0.status == .pending || $0.status == .expired }
        }
    }

    /// Valida temporalmente todos os planos de amortização (`PlanExpirationValidator`),
    /// transicionando aportes `.pending` com `date < startOfToday` para `.expired` e sincronizando transações.
    public func validateExpiredAmortizationPlans(referenceNow: Date? = nil) {
        let now = referenceNow ?? effectiveCurrentDate
        let newlyExpired = PlanExpirationValidator.validateAndExpireOverdueItems(
            plans: &amortizationPlans,
            referenceNow: now,
            calendar: calendar
        )
        if !newlyExpired.isEmpty {
            for contract in contracts {
                syncPlannedAmortizationTransactions(for: contract.id, saveAfter: false)
            }
            save()
        }
    }

    /// Indica se o contrato possui um planejamento de amortização salvo com itens ativos (`.pending` ou `.expired`).
    public func hasSavedAmortizationPlan(for contractId: UUID) -> Bool {
        guard let plan = amortizationPlan(for: contractId) else { return false }
        return plan.items.contains { $0.status == .pending || $0.status == .expired }
    }

    /// Calcula em tempo real (Camada 3 — Read Model em Memória com `Decimal` estrito) a projeção completa do contrato.
    /// Combina Camada 1 (parcelas reais não pagas) + Camada 2 (apenas itens `.pending`).
    /// Utiliza memoização O(1) por revisão de dados para evitar recálculos redundantes durante renderizações.
    public func loanProjection(for contractId: UUID) -> LoanProjectionResult? {
        if let cached = cachedLoanProjections[contractId] {
            return cached
        }
        guard let contract = contracts.first(where: { $0.id == contractId }), !contract.isSettled else {
            return nil
        }
        let unpaidInstallments = transactions.filter {
            $0.linkedContractId == contractId &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        let currentRealBal = currentOutstandingBalance(for: contract)
        let plan = amortizationPlan(for: contractId)
        let result = LoanProjectionEngine.simulate(
            contract: contract,
            unpaidInstallmentTransactions: unpaidInstallments,
            currentRealBalanceDouble: currentRealBal,
            plan: plan,
            calendar: calendar
        )
        cachedLoanProjections[contractId] = result
        return result
    }

    /// Simula em memória um plano em rascunho (`draftPlan`) sem persistir nem alterar `amortizationPlans` ou `transactions`.
    public func simulateAmortizationPlanPreview(
        for contractId: UUID,
        draftPlan: AmortizationPlan?
    ) -> LoanProjectionResult? {
        guard let contract = contracts.first(where: { $0.id == contractId }), !contract.isSettled else {
            return nil
        }
        let unpaidInstallments = transactions.filter {
            $0.linkedContractId == contractId &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        let currentRealBal = currentOutstandingBalance(for: contract)
        return LoanProjectionEngine.simulate(
            contract: contract,
            unpaidInstallmentTransactions: unpaidInstallments,
            currentRealBalanceDouble: currentRealBal,
            plan: draftPlan,
            calendar: calendar
        )
    }

    /// Retorna o valor máximo permitido para amortizar o contrato na data `onDate` considerando os aportes em rascunho (`draftItems`).
    /// Se o empréstimo já estaria quitado nessa data, retorna `0.0`.
    public func maxAvailableLoanBalanceToAmortize(
        for contractId: UUID,
        draftItems: [PlannedAmortization],
        onDate: Date,
        excludingItemId: UUID? = nil,
        estimatedMonthlyTR: Decimal = .zero
    ) -> Double {
        guard let contract = contracts.first(where: { $0.id == contractId }), !contract.isSettled else {
            return 0.0
        }
        let unpaidInstallments = transactions.filter {
            $0.linkedContractId == contractId &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        let currentRealBal = currentOutstandingBalance(for: contract)
        let maxDec = LoanProjectionEngine.maxAvailableLoanBalanceToAmortize(
            contract: contract,
            unpaidInstallmentTransactions: unpaidInstallments,
            currentRealBalanceDouble: currentRealBal,
            existingItems: draftItems,
            onDate: onDate,
            excludingItemId: excludingItemId,
            estimatedMonthlyTR: estimatedMonthlyTR,
            calendar: calendar
        )
        return LoanProjectionEngine.toDouble(maxDec)
    }

    /// Calcula o Saldo Esperado para o Final do Mês (`monthDate`) no caixa do usuário considerando o rascunho atual do planejamento (`draftPlan`)
    /// e um eventual aporte adicional sendo digitado (`additionalTypingOutflow`), permitindo visibilidade instantânea enquanto o usuário ajusta valores.
    public func expectedMonthEndCashBalance(
        for monthDate: Date,
        contractId: UUID,
        draftPlan: AmortizationPlan?,
        draftProjection: LoanProjectionResult?,
        additionalTypingOutflow: Double = 0.0
    ) -> Double {
        let cutoff = endOfMonth(for: monthDate)
        let isClosed = isMonthPriorToCurrent(monthDate)
        let initialAccountsSum = accounts.reduce(0.0) { $0 + $1.initialBalance }
        let consolidatedInvestmentsSum = investments
            .filter(\.showInConsolidated)
            .reduce(0.0) { $0 + $1.balance }

        let shadowedByDraft = draftProjection?.shadowedInstallmentTransactionIds ?? []
        let projectedAmountsByDraft = draftProjection?.activeInstallmentProjectedAmounts ?? [:]

        // 1. Soma todas as transações até `cutoff`, exceto as amortizações planejadas salvas deste contrato (que serão substituídas pelo draftPlan)
        var transactionsDelta = 0.0
        for tx in transactions {
            guard !tx.ignoreInConsolidated else { continue }
            guard tx.date <= cutoff else { continue }
            if isClosed && !tx.isPaid { continue }

            if tx.linkedContractId == contractId && tx.transactionOrigin == .plannedAmortization {
                // Substituído pelos aportes do draftPlan abaixo
                continue
            }

            if tx.linkedContractId == contractId && tx.installmentIndex != nil && !tx.isPaid {
                if shadowedByDraft.contains(tx.id) {
                    continue
                }
                if let draftAmtDec = projectedAmountsByDraft[tx.id] {
                    let amt = LoanProjectionEngine.toDouble(draftAmtDec)
                    transactionsDelta += (tx.type == .income ? amt : -amt)
                    continue
                }
            }

            transactionsDelta += effectiveSignedTransactionAmount(for: tx)
        }

        // 2. Subtrai os aportes planejados pendentes do rascunho (`draftPlan`) que ocorrem até `cutoff`
        var draftAmortizationsOutflow = 0.0
        if let draftPlan {
            for item in draftPlan.items where item.status == .pending && item.date <= cutoff {
                let effectiveDec = draftProjection?.plannedItemOutcomes[item.id]?.effectiveAmortization ?? item.amount
                draftAmortizationsOutflow += LoanProjectionEngine.toDouble(effectiveDec)
            }
        }

        let remainingProvisions = isClosed ? 0.0 : accumulatedRemainingProvisions(throughMonth: monthDate)
        return initialAccountsSum + transactionsDelta + consolidatedInvestmentsSum - remainingProvisions - draftAmortizationsOutflow - max(0.0, additionalTypingOutflow)
    }

    /// Salva definitivamente um planejamento de amortização (criado ou editado na tela de planejamento),
    /// sanitizando os aportes para impedir valores acima do saldo de quitação e sincronizando as transações.
    @discardableResult
    public func saveAmortizationPlan(
        contractId: UUID,
        generationMode: AmortizationPlanGenerationMode,
        billingDay: Int,
        incomeCommitmentPercentage: Decimal,
        defaultRecalculationMode: AmortizationRecalculationMode,
        estimatedMonthlyTR: Decimal,
        draftItems: [PlannedAmortization]
    ) -> AmortizationPlan? {
        guard let contractIdx = contracts.firstIndex(where: { $0.id == contractId }),
              !contracts[contractIdx].isSettled else {
            return nil
        }
        contracts[contractIdx].estimatedMonthlyTR = LoanProjectionEngine.toDouble(estimatedMonthlyTR)
        let contract = contracts[contractIdx]
        let effectiveMode: AmortizationRecalculationMode = contract.kind == .loan ? .reduceTerm : defaultRecalculationMode

        let unpaidInstallments = transactions.filter {
            $0.linkedContractId == contractId &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        let currentRealBal = currentOutstandingBalance(for: contract)

        let sanitizedItems = LoanProjectionEngine.clampAndSanitizePlannedItems(
            draftItems,
            contract: contract,
            unpaidInstallmentTransactions: unpaidInstallments,
            currentRealBalanceDouble: currentRealBal,
            estimatedMonthlyTR: estimatedMonthlyTR,
            calendar: calendar
        )

        let existingPlan = amortizationPlan(for: contractId)
        let executedItems = existingPlan?.items.filter { $0.status == .executed } ?? []
        let pendingOrExpired = sanitizedItems.filter { $0.status != .executed }
        let mergedItems = (executedItems + pendingOrExpired).sorted { $0.date < $1.date }

        let savedPlan = AmortizationPlan(
            id: existingPlan?.id ?? UUID(),
            contractId: contractId,
            generationMode: generationMode,
            billingDay: min(max(billingDay, 1), 31),
            incomeCommitmentPercentage: min(max(incomeCommitmentPercentage, Decimal(1)), Decimal(100)),
            defaultRecalculationMode: effectiveMode,
            estimatedMonthlyTR: max(.zero, estimatedMonthlyTR),
            items: mergedItems,
            updatedAt: effectiveCurrentDate,
            createdAt: existingPlan?.createdAt ?? effectiveCurrentDate
        )

        if let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }) {
            amortizationPlans[pIdx] = savedPlan
        } else {
            amortizationPlans.append(savedPlan)
        }

        syncPlannedAmortizationTransactions(for: contractId)
        cloudSyncService?.recordLocalMutation(entityName: "amortization_plans", entityId: savedPlan.id, operation: .upsert, entity: savedPlan)
        return savedPlan
    }

    /// Retorna o snapshot consolidado em memória de todas as projeções ativas (IDs de parcelas `.shadowed` e valores reduzidos).
    /// Memoizado em O(1) por revisão de dados.
    public func activeProjectionSnapshot() -> (shadowedTxIds: Set<UUID>, projectedInstallmentAmounts: [UUID: Double]) {
        guard budgetProjectionScenario == .withPlanning else {
            return ([], [:])
        }
        if let cached = cachedActiveProjectionSnapshot {
            return (cached.shadowedTxIds, cached.projectedInstallmentAmounts)
        }
        var shadowed: Set<UUID> = []
        var projectedAmounts: [UUID: Double] = [:]
        var payoffTxs: Set<UUID> = []

        for contract in contracts where !contract.isSettled {
            guard let plan = amortizationPlan(for: contract.id),
                  plan.items.contains(where: { $0.status == .pending }) else {
                continue
            }
            if let proj = loanProjection(for: contract.id) {
                shadowed.formUnion(proj.shadowedInstallmentTransactionIds)
                for (txId, decAmt) in proj.activeInstallmentProjectedAmounts {
                    projectedAmounts[txId] = LoanProjectionEngine.toDouble(decAmt)
                }
                for item in plan.items where item.status == .pending {
                    if let outcome = proj.plannedItemOutcomes[item.id],
                       outcome.isFullPayoffStep || outcome.remainingBalanceAfter <= Decimal(string: "0.01")!,
                       let linkedTxId = item.linkedTransactionId {
                        payoffTxs.insert(linkedTxId)
                    }
                }
            }
        }
        cachedActiveProjectionSnapshot = (shadowed, projectedAmounts, payoffTxs)
        return (shadowed, projectedAmounts)
    }

    /// Indica se uma transação (amortização planejada `.plannedAmortization` OU a última parcela ativa de um contrato com plano de amortização)
    /// representa a transação final de LIQUIDAÇÃO / QUITAÇÃO TOTAL do contrato.
    public func isPlannedAmortizationFullPayoff(_ tx: FinancialTransaction) -> Bool {
        if tx.transactionOrigin == .plannedAmortization {
            _ = activeProjectionSnapshot()
            if let cached = cachedActiveProjectionSnapshot, cached.payoffTxIds.contains(tx.id) {
                return true
            }
            if let contractId = tx.linkedContractId,
               let proj = loanProjection(for: contractId),
               let itemId = tx.linkedEntityID,
               let outcome = proj.plannedItemOutcomes[itemId] {
                return outcome.isFullPayoffStep || outcome.remainingBalanceAfter <= Decimal(string: "0.01")!
            }
            return tx.name.localizedCaseInsensitiveContains("Liquidação") ||
                   tx.details.localizedCaseInsensitiveContains("Liquidação Total")
        }

        // Caso o plano seja parcial e a quitação antecipada ocorra na última parcela regular ativa antes das parcelas `.shadowed`:
        if budgetProjectionScenario == .withPlanning,
           let contractId = tx.linkedContractId,
           tx.installmentIndex != nil,
           !tx.isPaid,
           hasSavedAmortizationPlan(for: contractId),
           let proj = loanProjection(for: contractId),
           proj.monthsSaved > 0 {
            if let row = proj.timeline.first(where: { $0.linkedTransactionId == tx.id }),
               row.status == .active,
               row.finalBalance <= Decimal(string: "0.01")! {
                return true
            }
        }

        return false
    }

    /// Status de exibição projetado de uma transação na lista (`.active`, `.pendingAmortization` ou `.shadowed`).
    public func transactionProjectionStatus(for tx: FinancialTransaction) -> ProjectedInstallmentStatus {
        if tx.transactionOrigin == .plannedAmortization {
            return .pendingAmortization
        }
        guard budgetProjectionScenario == .withPlanning,
              tx.linkedContractId != nil,
              tx.installmentIndex != nil,
              !tx.isPaid else {
            return .active
        }
        let snap = activeProjectionSnapshot()
        return snap.shadowedTxIds.contains(tx.id) ? .shadowed : .active
    }

    /// Define se a transação deve ser exibida na lista de transações no cenário atual (`Real (Base)` vs `Com Planejamento`).
    /// Em `Real (Base)`, amortizações planejadas futuras (`.plannedAmortization`) são ocultadas.
    /// Em `Com Planejamento`, tanto as amortizações `.pending` quanto as parcelas `.shadowed` são exibidas.
    public func isTransactionVisibleInCurrentScenario(_ tx: FinancialTransaction) -> Bool {
        if tx.transactionOrigin == .plannedAmortization {
            guard budgetProjectionScenario == .withPlanning else { return false }
            // Apenas exibe se o item planejado correspondente estiver `.pending`
            for plan in amortizationPlans {
                if let item = plan.items.first(where: { $0.id == tx.linkedEntityID || $0.linkedTransactionId == tx.id }) {
                    return item.status == .pending
                }
            }
            return false
        }
        return true
    }

    /// Valor efetivo da transação para cálculos de Orçamento, Fluxo de Caixa, Gráficos e Dashboard.
    /// - Em `Com Planejamento`: parcelas `.shadowed` somam **R$ 0,00**, parcelas recalculadas usam o valor projetado e aportes `.pending` entram na soma.
    /// - Em `Real (Base)`: aportes `.plannedAmortization` somam **R$ 0,00** e todas as parcelas reais somam seu valor contratual original.
    public func effectiveTransactionAmount(for tx: FinancialTransaction) -> Double {
        if tx.transactionOrigin == .plannedAmortization {
            guard budgetProjectionScenario == .withPlanning else { return 0.0 }
            for plan in amortizationPlans {
                if let item = plan.items.first(where: { $0.id == tx.linkedEntityID || $0.linkedTransactionId == tx.id }) {
                    guard item.status == .pending else { return 0.0 }
                    if let proj = loanProjection(for: plan.contractId),
                       let outcome = proj.plannedItemOutcomes[item.id] {
                        return LoanProjectionEngine.toDouble(outcome.effectiveAmortization)
                    }
                    return item.amountDouble
                }
            }
            return 0.0
        }

        if budgetProjectionScenario == .withPlanning,
           tx.linkedContractId != nil,
           tx.installmentIndex != nil,
           !tx.isPaid {
            let snap = activeProjectionSnapshot()
            if snap.shadowedTxIds.contains(tx.id) {
                return 0.0
            }
            if let projAmt = snap.projectedInstallmentAmounts[tx.id] {
                return projAmt
            }
        }

        return tx.amount
    }

    /// Valor assinado efetivo (`+` para receita, `-` para despesa) respeitando o cenário ativo e supressão `.shadowed`.
    public func effectiveSignedTransactionAmount(for tx: FinancialTransaction) -> Double {
        let amt = effectiveTransactionAmount(for: tx)
        return tx.type == .income ? amt : -amt
    }

    /// Sincroniza as transações de amortização planejada (`.plannedAmortization`) com os itens `.pending` da Camada 2,
    /// sem NUNCA deletar nem modificar as transações de parcelas reais da Camada 1.
    public func syncPlannedAmortizationTransactions(for contractId: UUID, saveAfter: Bool = true) {
        guard let contract = contracts.first(where: { $0.id == contractId }) else {
            transactions.removeAll { $0.linkedContractId == contractId && $0.transactionOrigin == .plannedAmortization }
            if saveAfter { save() }
            return
        }

        guard let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }) else {
            transactions.removeAll { $0.linkedContractId == contractId && $0.transactionOrigin == .plannedAmortization }
            if saveAfter {
                sortTransactions()
                save()
            }
            return
        }

        let proj = loanProjection(for: contractId)
        var validPlannedTxIds: Set<UUID> = []

        for iIdx in amortizationPlans[pIdx].items.indices {
            let item = amortizationPlans[pIdx].items[iIdx]
            guard item.status == .pending else {
                continue
            }

            let outcome = proj?.plannedItemOutcomes[item.id]
            let effectiveAmtDecimal = outcome?.effectiveAmortization ?? item.amount
            let effectiveAmtDouble = LoanProjectionEngine.toDouble(effectiveAmtDecimal)
            guard effectiveAmtDouble > 0.001 else {
                continue
            }

            let remainingBalDouble = LoanProjectionEngine.toDouble(outcome?.remainingBalanceAfter ?? .zero)
            let isFullPayoffStep = (outcome?.isFullPayoffStep == true) || (outcome?.remainingBalanceAfter ?? Decimal(1)) <= Decimal(string: "0.01")!
            let txId = item.linkedTransactionId ?? UUID()
            amortizationPlans[pIdx].items[iIdx].linkedTransactionId = txId
            validPlannedTxIds.insert(txId)

            let txTitle: String
            let txDetails: String
            if isFullPayoffStep {
                txTitle = "Amortização Planejada — Liquidação Total (\(item.source.shortTitle)): \(contract.name)"
                txDetails = "Liquidação Total Planejada (Quitação do contrato) • Saldo devedor zerado: R$ 0,00 • \(item.mode.rawValue) \(item.notes)".trimmingCharacters(in: .whitespaces)
            } else {
                txTitle = "Amortização Planejada (\(item.source.shortTitle)): \(contract.name)"
                txDetails = "Planejamento de amortização • Saldo restante projetado: \(BRLFormatters.currency(remainingBalDouble)) • \(item.mode.rawValue) \(item.notes)".trimmingCharacters(in: .whitespaces)
            }

            if let existingTxIdx = transactions.firstIndex(where: { $0.id == txId }) {
                transactions[existingTxIdx].name = txTitle
                transactions[existingTxIdx].details = txDetails
                transactions[existingTxIdx].amount = effectiveAmtDouble
                transactions[existingTxIdx].date = item.date
                transactions[existingTxIdx].categoryId = contract.categoryId
                transactions[existingTxIdx].accountId = contract.accountId
                transactions[existingTxIdx].ignoreInConsolidated = false
            } else {
                let newTx = FinancialTransaction(
                    id: txId,
                    name: txTitle,
                    details: txDetails,
                    amount: effectiveAmtDouble,
                    date: item.date,
                    type: .expense,
                    isPaid: false,
                    categoryId: contract.categoryId,
                    accountId: contract.accountId,
                    ignoreInConsolidated: false,
                    recurrenceMode: .single,
                    linkedContractId: contract.id,
                    transactionOrigin: .plannedAmortization,
                    linkedEntityID: item.id
                )
                transactions.append(newTx)
            }
        }

        // Remove transações planejadas órfãs, expiradas, descartadas ou executadas deste contrato
        transactions.removeAll { tx in
            tx.linkedContractId == contractId &&
            tx.transactionOrigin == .plannedAmortization &&
            !validPlannedTxIds.contains(tx.id)
        }

        if saveAfter {
            sortTransactions()
            save()
        }
    }

    /// Adiciona manualmente um novo aporte ao planejamento de amortização do contrato e recalcula tudo imediatamente.
    @discardableResult
    public func addPlannedAmortization(
        contractId: UUID,
        date: Date,
        amount: Decimal,
        source: AmortizationFundingSource = .cash,
        mode: AmortizationRecalculationMode = .reduceTerm,
        notes: String = ""
    ) -> PlannedAmortization? {
        guard let contract = contracts.first(where: { $0.id == contractId }), !contract.isSettled else { return nil }
        guard amount > .zero else { return nil }

        let effectiveMode: AmortizationRecalculationMode = contract.kind == .loan ? .reduceTerm : mode
        let todayStart = calendar.startOfDay(for: effectiveCurrentDate)
        let itemDay = calendar.startOfDay(for: date)
        let initialStatus: PlannedAmortizationStatus = itemDay < todayStart ? .expired : .pending

        let newItem = PlannedAmortization(
            contractId: contractId,
            date: date,
            amount: amount,
            source: source,
            mode: effectiveMode,
            status: initialStatus,
            notes: notes
        )

        if let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }) {
            amortizationPlans[pIdx].items.append(newItem)
            amortizationPlans[pIdx].items.sort { $0.date < $1.date }
            amortizationPlans[pIdx].updatedAt = effectiveCurrentDate
        } else {
            let bestDay = contract.effectiveBankDueDay >= 28 ? 1 : (contract.effectiveBankDueDay + 1)
            let plan = AmortizationPlan(
                contractId: contractId,
                generationMode: .manual,
                billingDay: contract.kind == .loan ? bestDay : contract.billingDay,
                incomeCommitmentPercentage: Decimal(30),
                defaultRecalculationMode: effectiveMode,
                estimatedMonthlyTR: LoanProjectionEngine.toDecimal(contract.estimatedMonthlyTR ?? 0.0),
                items: [newItem],
                updatedAt: effectiveCurrentDate,
                createdAt: effectiveCurrentDate
            )
            amortizationPlans.append(plan)
        }

        syncPlannedAmortizationTransactions(for: contractId)
        return newItem
    }

    /// Atualiza qualquer campo de um aporte planejado existente (data, valor, origem, modalidade) e recalcula tudo.
    public func updatePlannedAmortization(
        contractId: UUID,
        itemId: UUID,
        date: Date,
        amount: Decimal,
        source: AmortizationFundingSource,
        mode: AmortizationRecalculationMode,
        notes: String = ""
    ) {
        guard let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }),
              let iIdx = amortizationPlans[pIdx].items.firstIndex(where: { $0.id == itemId }) else {
            return
        }
        let isLoan = contracts.first(where: { $0.id == contractId })?.kind == .loan
        let todayStart = calendar.startOfDay(for: effectiveCurrentDate)
        let itemDay = calendar.startOfDay(for: date)

        amortizationPlans[pIdx].items[iIdx].date = date
        amortizationPlans[pIdx].items[iIdx].amount = max(.zero, amount)
        amortizationPlans[pIdx].items[iIdx].source = source
        amortizationPlans[pIdx].items[iIdx].mode = isLoan ? .reduceTerm : mode
        if !notes.isEmpty {
            amortizationPlans[pIdx].items[iIdx].notes = notes
        }
        if amortizationPlans[pIdx].items[iIdx].status == .expired && itemDay >= todayStart {
            amortizationPlans[pIdx].items[iIdx].status = .pending
        } else if amortizationPlans[pIdx].items[iIdx].status == .pending && itemDay < todayStart {
            amortizationPlans[pIdx].items[iIdx].status = .expired
        }
        amortizationPlans[pIdx].items.sort { $0.date < $1.date }
        amortizationPlans[pIdx].updatedAt = effectiveCurrentDate

        syncPlannedAmortizationTransactions(for: contractId)
    }

    /// Remove um aporte planejado individual do plano e recalcula imediatamente.
    public func removePlannedAmortization(contractId: UUID, itemId: UUID) {
        guard let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }) else { return }
        amortizationPlans[pIdx].items.removeAll { $0.id == itemId }
        amortizationPlans[pIdx].updatedAt = effectiveCurrentDate
        syncPlannedAmortizationTransactions(for: contractId)
    }

    /// Exclui integralmente o planejamento de amortização de um contrato, restaurando a visão base da Camada 1.
    public func deleteAmortizationPlan(for contractId: UUID) {
        let deletedPlans = amortizationPlans.filter { $0.contractId == contractId }
        let deletedTxs = transactions.filter { $0.linkedContractId == contractId && $0.transactionOrigin == .plannedAmortization }
        amortizationPlans.removeAll { $0.contractId == contractId }
        transactions.removeAll { $0.linkedContractId == contractId && $0.transactionOrigin == .plannedAmortization }
        sortTransactions()
        save()
        for plan in deletedPlans {
            cloudSyncService?.recordLocalMutation(entityName: "amortization_plans", entityId: plan.id, operation: .delete)
        }
        for tx in deletedTxs {
            cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: tx.id, operation: .delete)
        }
    }

    /// Atualiza parâmetros globais do plano de amortização (ex: TR mensal estimada, dia de cobrança, percentual).
    public func updateAmortizationPlanParameters(
        contractId: UUID,
        generationMode: AmortizationPlanGenerationMode? = nil,
        billingDay: Int? = nil,
        incomeCommitmentPercentage: Decimal? = nil,
        defaultRecalculationMode: AmortizationRecalculationMode? = nil,
        estimatedMonthlyTR: Decimal? = nil
    ) {
        guard let contractIdx = contracts.firstIndex(where: { $0.id == contractId }) else { return }
        if let tr = estimatedMonthlyTR {
            contracts[contractIdx].estimatedMonthlyTR = LoanProjectionEngine.toDouble(tr)
        }

        if let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }) {
            if let gm = generationMode { amortizationPlans[pIdx].generationMode = gm }
            if let bd = billingDay { amortizationPlans[pIdx].billingDay = min(max(bd, 1), 31) }
            if let pct = incomeCommitmentPercentage {
                amortizationPlans[pIdx].incomeCommitmentPercentage = min(max(pct, Decimal(1)), Decimal(100))
            }
            if let mode = defaultRecalculationMode {
                amortizationPlans[pIdx].defaultRecalculationMode = contracts[contractIdx].kind == .loan ? .reduceTerm : mode
            }
            if let tr = estimatedMonthlyTR {
                amortizationPlans[pIdx].estimatedMonthlyTR = max(.zero, tr)
            }
            amortizationPlans[pIdx].updatedAt = effectiveCurrentDate
        } else {
            let contract = contracts[contractIdx]
            let plan = AmortizationPlan(
                contractId: contractId,
                generationMode: generationMode ?? .manual,
                billingDay: billingDay ?? contract.billingDay,
                incomeCommitmentPercentage: incomeCommitmentPercentage ?? Decimal(30),
                defaultRecalculationMode: defaultRecalculationMode ?? .reduceTerm,
                estimatedMonthlyTR: estimatedMonthlyTR ?? LoanProjectionEngine.toDecimal(contract.estimatedMonthlyTR ?? 0.0),
                items: [],
                updatedAt: effectiveCurrentDate,
                createdAt: effectiveCurrentDate
            )
            amortizationPlans.append(plan)
        }
        syncPlannedAmortizationTransactions(for: contractId)
    }

    /// Calcula o dinheiro previsto disponível ao final do mês (`monthReference`) para geração automática de amortizações,
    /// desconsiderando amortizações planejadas do próprio contrato para evitar dupla dedução.
    public func projectedAvailableMonthlySurplusForAmortization(
        in monthReference: Date,
        excludingContractId: UUID
    ) -> Decimal {
        let monthTxs = transactionsForMonth(monthReference).filter { tx in
            !tx.ignoreInConsolidated &&
            tx.transactionOrigin != .internalTransfer &&
            tx.isCanceledRecurringSeries != true &&
            !(tx.transactionOrigin == .plannedAmortization && tx.linkedContractId == excludingContractId)
        }

        var incomeSum = monthTxs.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        let expenseSum = monthTxs.filter { $0.type == .expense }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        let provisionsRemaining = isMonthPriorToCurrent(monthReference) ? 0.0 : totalRemainingProvision(for: monthReference)

        // Se o mês futuro ainda não tiver receitas lançadas diretamente, utiliza a receita habitual do mês corrente/selecionado como referência
        if incomeSum <= 0.01 {
            let fallbackIncome = max(
                monthlyIncome(for: selectedMonth),
                monthlyIncome(for: effectiveCurrentDate)
            )
            incomeSum = fallbackIncome
        }

        let netMonthlySurplus = incomeSum - (expenseSum + provisionsRemaining)
        if netMonthlySurplus > 0.01 {
            return LoanProjectionEngine.roundCurrency(LoanProjectionEngine.toDecimal(netMonthlySurplus))
        }

        // Caso não haja receita mensal lançada mas o usuário possua saldo previsto positivo em conta no mês atual:
        let currentKpi = buildUnifiedFinancialKPISummary(referenceDate: selectedMonth, isAnnual: false)
        if currentKpi.surplusAfterPlanning > 0.01 {
            return LoanProjectionEngine.roundCurrency(LoanProjectionEngine.toDecimal(currentKpi.surplusAfterPlanning))
        }
        if currentKpi.operationalNetBalance > 0.01 {
            return LoanProjectionEngine.roundCurrency(LoanProjectionEngine.toDecimal(currentKpi.operationalNetBalance))
        }

        return .zero
    }

    /// Gera automaticamente o planejamento de amortização mês a mês usando o dia de cobrança
    /// e a porcentagem de comprometimento do dinheiro previsto ao final do mês.
    @discardableResult
    public func generateAutomaticAmortizationPlan(
        contractId: UUID,
        billingDay: Int,
        incomeCommitmentPercentage: Decimal,
        mode: AmortizationRecalculationMode = .reduceTerm,
        estimatedMonthlyTR: Decimal? = nil,
        fallbackMonthlyBaseSurplus: Decimal? = nil
    ) -> AmortizationPlan? {
        guard let contract = contracts.first(where: { $0.id == contractId }), !contract.isSettled else {
            return nil
        }

        let unpaidInstallments = transactions.filter {
            $0.linkedContractId == contractId &&
            $0.installmentIndex != nil &&
            !$0.isPaid
        }
        let currentRealBal = currentOutstandingBalance(for: contract)
        let effectiveTR = estimatedMonthlyTR ?? amortizationPlan(for: contractId)?.estimatedMonthlyTR ?? LoanProjectionEngine.toDecimal(contract.estimatedMonthlyTR ?? 0.0)
        let effectiveMode: AmortizationRecalculationMode = contract.kind == .loan ? .reduceTerm : mode

        let generatedItems = LoanProjectionEngine.generateAutomaticPlanItems(
            contract: contract,
            unpaidInstallmentTransactions: unpaidInstallments,
            currentRealBalanceDouble: currentRealBal,
            billingDay: billingDay,
            incomeCommitmentPercentage: incomeCommitmentPercentage,
            mode: effectiveMode,
            estimatedMonthlyTR: effectiveTR,
            referenceNow: effectiveCurrentDate,
            monthlyAvailableSurplusProvider: { [weak self] targetMonth in
                guard let self else { return fallbackMonthlyBaseSurplus ?? .zero }
                let computed = self.projectedAvailableMonthlySurplusForAmortization(in: targetMonth, excludingContractId: contractId)
                if computed > .zero {
                    return computed
                }
                return fallbackMonthlyBaseSurplus ?? .zero
            },
            calendar: calendar
        )

        // Preserva itens já executados no histórico do plano
        let executedItems = amortizationPlan(for: contractId)?.items.filter { $0.status == .executed } ?? []
        let allItems = (executedItems + generatedItems).sorted { $0.date < $1.date }

        let updatedPlan = AmortizationPlan(
            id: amortizationPlan(for: contractId)?.id ?? UUID(),
            contractId: contractId,
            generationMode: .automatic,
            billingDay: billingDay,
            incomeCommitmentPercentage: incomeCommitmentPercentage,
            defaultRecalculationMode: effectiveMode,
            estimatedMonthlyTR: effectiveTR,
            items: allItems,
            updatedAt: effectiveCurrentDate,
            createdAt: amortizationPlan(for: contractId)?.createdAt ?? effectiveCurrentDate
        )

        if let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }) {
            amortizationPlans[pIdx] = updatedPlan
        } else {
            amortizationPlans.append(updatedPlan)
        }

        syncPlannedAmortizationTransactions(for: contractId)
        return updatedPlan
    }

    /// Efetivação Real ("Confirmar Pagamento" / "Confirmar que paguei"):
    /// 1. Muda o aporte para `.executed`.
    /// 2. Remove a transação provisória `.plannedAmortization`.
    /// 3. Registra a amortização real na Camada 1 (`amortizeContract`), abatendo o saldo real e recalculando ou quitando definitivamente as parcelas futuras.
    @discardableResult
    public func confirmPlannedAmortizationPayment(
        contractId: UUID,
        itemId: UUID,
        accountId: UUID? = nil,
        paymentDate: Date? = nil
    ) -> Bool {
        guard let contractIdx = contracts.firstIndex(where: { $0.id == contractId }),
              let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }),
              let iIdx = amortizationPlans[pIdx].items.firstIndex(where: { $0.id == itemId }) else {
            return false
        }

        let item = amortizationPlans[pIdx].items[iIdx]
        guard item.status == .pending || item.status == .expired else { return false }

        let contract = contracts[contractIdx]
        let proj = loanProjection(for: contractId)
        let effectiveAmountDec = proj?.plannedItemOutcomes[item.id]?.effectiveAmortization ?? item.amount
        let amountToPay = max(0.01, LoanProjectionEngine.toDouble(effectiveAmountDec > .zero ? effectiveAmountDec : item.amount))
        let targetAccountId = accountId ?? contract.accountId
        let effectiveDate = paymentDate ?? item.date

        // 1. Marca como `.executed` e atualiza data de uso do FGTS se aplicável
        amortizationPlans[pIdx].items[iIdx].status = .executed
        amortizationPlans[pIdx].items[iIdx].date = effectiveDate
        amortizationPlans[pIdx].updatedAt = effectiveCurrentDate

        if item.source == .fgts {
            contracts[contractIdx].lastFGTSUsageDate = effectiveDate
        }

        // 2. Remove a transação provisória `.plannedAmortization` deste item antes de criar a transação real paga
        if let provisionalTxId = item.linkedTransactionId {
            transactions.removeAll { $0.id == provisionalTxId }
        }
        transactions.removeAll {
            $0.transactionOrigin == .plannedAmortization && $0.linkedEntityID == item.id
        }

        // 3. Executa a amortização real definitiva na Camada 1
        let sourceTag = item.source == .fgts ? " [FGTS]" : ""
        amortizeContract(
            contractId: contractId,
            amountPaid: amountToPay,
            accountId: targetAccountId,
            date: effectiveDate,
            mode: contract.kind == .loan ? .reduceTerm : item.mode,
            proRataInterest: 0.0,
            notes: ("Amortização planejada confirmada\(sourceTag). " + item.notes).trimmingCharacters(in: .whitespaces)
        )

        // 4. Se o contrato foi integralmente quitado na Camada 1, limpa eventuais aportes futuros pendentes
        if contracts[contractIdx].isSettled {
            for idx in amortizationPlans[pIdx].items.indices where amortizationPlans[pIdx].items[idx].status == .pending {
                amortizationPlans[pIdx].items[idx].status = .skipped
            }
        }

        // 5. Re-sincroniza as transações planejadas restantes
        syncPlannedAmortizationTransactions(for: contractId)
        return true
    }

    /// Confirma o pagamento de uma amortização planejada a partir do ID da sua transação na tela de Transações.
    @discardableResult
    public func confirmPlannedAmortizationByTransactionId(_ transactionId: UUID, paymentDate: Date? = nil) -> Bool {
        for plan in amortizationPlans {
            if let item = plan.items.first(where: { $0.linkedTransactionId == transactionId }) {
                return confirmPlannedAmortizationPayment(
                    contractId: plan.contractId,
                    itemId: item.id,
                    paymentDate: paymentDate
                )
            }
        }
        if let tx = transactions.first(where: { $0.id == transactionId && $0.transactionOrigin == .plannedAmortization }),
           let contractId = tx.linkedContractId,
           let itemId = tx.linkedEntityID {
            return confirmPlannedAmortizationPayment(
                contractId: contractId,
                itemId: itemId,
                paymentDate: paymentDate
            )
        }
        return false
    }

    /// Reagenda um aporte `.expired` para uma nova data futura/atual, voltando seu status para `.pending` e recalculando o orçamento.
    public func rescheduleExpiredAmortization(contractId: UUID, itemId: UUID, newDate: Date) {
        guard let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }),
              let iIdx = amortizationPlans[pIdx].items.firstIndex(where: { $0.id == itemId }) else {
            return
        }
        let todayStart = calendar.startOfDay(for: effectiveCurrentDate)
        let targetDate = calendar.startOfDay(for: newDate) < todayStart ? effectiveCurrentDate : newDate
        amortizationPlans[pIdx].items[iIdx].date = targetDate
        amortizationPlans[pIdx].items[iIdx].status = .pending
        amortizationPlans[pIdx].items.sort { $0.date < $1.date }
        amortizationPlans[pIdx].updatedAt = effectiveCurrentDate
        syncPlannedAmortizationTransactions(for: contractId)
    }

    /// Descarta manualmente (`[Descartar]`) um aporte `.expired` ou `.pending`.
    public func skipExpiredAmortization(contractId: UUID, itemId: UUID) {
        guard let pIdx = amortizationPlans.firstIndex(where: { $0.contractId == contractId }),
              let iIdx = amortizationPlans[pIdx].items.firstIndex(where: { $0.id == itemId }) else {
            return
        }
        amortizationPlans[pIdx].items[iIdx].status = .skipped
        amortizationPlans[pIdx].updatedAt = effectiveCurrentDate
        syncPlannedAmortizationTransactions(for: contractId)
    }

    // MARK: - Balances, Monthly Summaries & Insights

    public func transactionsForMonth(_ monthReference: Date) -> [FinancialTransaction] {
        ensureTransactionIndexesBuilt()
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        guard let y = comps.year, let m = comps.month else { return [] }
        let ymKey = y * 100 + m
        return cachedTransactionsByYM?[ymKey] ?? []
    }

    public func monthlyIncome(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func monthlyReceivedIncome(for monthReference: Date) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: true)
    }

    public func monthlyPendingIncome(for monthReference: Date) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && !$0.isPaid }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func monthlyExpense(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func monthlyPaidExpense(for monthReference: Date) -> Double {
        monthlyExpense(for: monthReference, onlyPaid: true)
    }

    public func monthlyPendingExpense(for monthReference: Date) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && !$0.isPaid }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func monthlyNetBalance(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: onlyPaid) - monthlyExpense(for: monthReference, onlyPaid: onlyPaid)
    }

    /// Balanço Operacional estritamente realizado/lançado (Receitas Totais - Despesas Lançadas no mês)
    public func monthlyOperatingNet(for monthReference: Date) -> Double {
        monthlyIncome(for: monthReference) - monthlyExpense(for: monthReference)
    }

    /// Taxa de Poupança / Margem Líquida em porcentagem (% sobre a Receita do mês)
    public func monthlySavingsRate(for monthReference: Date) -> Double? {
        let income = monthlyIncome(for: monthReference)
        guard income > 0 else { return nil }
        let net = monthlyOperatingNet(for: monthReference)
        return (net / income) * 100.0
    }

    // MARK: - Category Provisions & Specific Quotas (Orçamento por Envelopes Dinâmicos)

    /// Define ou atualiza a Verba Livre (`CategoryProvision`) para uma categoria em um mês específico,
    /// suportando controle de escopo temporal (`.onlyThisMonth` vs `.thisAndFutureMonths`).
    public func setCategoryProvision(
        categoryId: UUID,
        estimatedAmount: Double,
        for monthReference: Date,
        repeatForFutureMonths: Bool = true,
        editScope: ProvisionEditScope = .thisAndFutureMonths
    ) {
        let year = calendar.component(.year, from: monthReference)
        let month = calendar.component(.month, from: monthReference)
        let targetKey = year * 100 + month
        let sanitizedAmount = max(0.0, estimatedAmount)

        if editScope == .onlyThisMonth {
            let candidates = provisions
                .enumerated()
                .filter { $0.element.categoryId == categoryId && $0.element.yearMonthKey <= targetKey }
                .sorted { a, b in
                    if a.element.yearMonthKey == b.element.yearMonthKey {
                        return a.element.createdAt < b.element.createdAt
                    }
                    return a.element.yearMonthKey < b.element.yearMonthKey
                }

            if let latest = candidates.last {
                let idx = latest.offset
                if provisions[idx].yearMonthKey == targetKey && !provisions[idx].repeatForFutureMonths {
                    if sanitizedAmount <= 0 {
                        provisions.remove(at: idx)
                    } else {
                        provisions[idx].estimatedAmount = sanitizedAmount
                    }
                } else {
                    var overrides = provisions[idx].monthlyOverrides ?? [:]
                    if sanitizedAmount <= 0 {
                        overrides.removeValue(forKey: targetKey)
                        var excluded = provisions[idx].excludedYearMonthKeys ?? []
                        excluded.insert(targetKey)
                        provisions[idx].excludedYearMonthKeys = excluded
                    } else {
                        overrides[targetKey] = sanitizedAmount
                        provisions[idx].excludedYearMonthKeys?.remove(targetKey)
                    }
                    provisions[idx].monthlyOverrides = overrides
                }
            } else if sanitizedAmount > 0 {
                let singleMonthProvision = CategoryProvision(
                    categoryId: categoryId,
                    year: year,
                    month: month,
                    estimatedAmount: sanitizedAmount,
                    repeatForFutureMonths: false
                )
                provisions.append(singleMonthProvision)
            }
            save()
            return
        }

        // Escopo: .thisAndFutureMonths (atualiza modelo base daquele mês em diante)
        provisions.removeAll { $0.categoryId == categoryId && $0.yearMonthKey > targetKey }
        for idx in provisions.indices where provisions[idx].categoryId == categoryId {
            if var overrides = provisions[idx].monthlyOverrides {
                overrides = overrides.filter { $0.key < targetKey }
                provisions[idx].monthlyOverrides = overrides.isEmpty ? nil : overrides
            }
            if var excluded = provisions[idx].excludedYearMonthKeys {
                excluded = excluded.filter { $0 < targetKey }
                provisions[idx].excludedYearMonthKeys = excluded.isEmpty ? nil : excluded
            }
        }

        if let existingIndex = provisions.firstIndex(where: {
            $0.categoryId == categoryId && $0.year == year && $0.month == month
        }) {
            if sanitizedAmount <= 0 {
                let hasPriorRecurring = provisions.contains {
                    $0.categoryId == categoryId &&
                    $0.yearMonthKey < targetKey &&
                    $0.repeatForFutureMonths &&
                    $0.estimatedAmount > 0
                }
                if hasPriorRecurring {
                    provisions[existingIndex].estimatedAmount = 0
                    provisions[existingIndex].repeatForFutureMonths = repeatForFutureMonths
                } else {
                    provisions.remove(at: existingIndex)
                }
            } else {
                provisions[existingIndex].estimatedAmount = sanitizedAmount
                provisions[existingIndex].repeatForFutureMonths = repeatForFutureMonths
            }
        } else {
            if sanitizedAmount > 0 {
                let newProvision = CategoryProvision(
                    categoryId: categoryId,
                    year: year,
                    month: month,
                    estimatedAmount: sanitizedAmount,
                    repeatForFutureMonths: repeatForFutureMonths
                )
                provisions.append(newProvision)
            } else {
                let hasPriorRecurring = provisions.contains {
                    $0.categoryId == categoryId &&
                    $0.yearMonthKey < targetKey &&
                    $0.repeatForFutureMonths &&
                    $0.estimatedAmount > 0
                }
                if hasPriorRecurring {
                    let stopper = CategoryProvision(
                        categoryId: categoryId,
                        year: year,
                        month: month,
                        estimatedAmount: 0,
                        repeatForFutureMonths: repeatForFutureMonths
                    )
                    provisions.append(stopper)
                }
            }
        }

        save()
        for prov in provisions where prov.categoryId == categoryId {
            cloudSyncService?.recordLocalMutation(entityName: "category_provisions", entityId: prov.id, operation: .upsert, entity: prov)
        }
    }

    /// Exclui a Verba Livre de uma categoria respeitando o escopo temporal:
    /// - `.onlyThisMonth`: remove apenas do mês corrente (a regra recorrente continua nos meses anteriores e reaparece nos futuros).
    /// - `.fromThisMonthOnward`: remove do mês informado em diante, mantendo o histórico dos meses passados.
    /// - `.allOccurrences`: remove o registro e interrompe a recorrência definitivamente para frente e para trás.
    public func deleteCategoryProvision(
        categoryId: UUID,
        for monthReference: Date,
        scope: ProvisionDeleteScope = .allOccurrences
    ) {
        let year = calendar.component(.year, from: monthReference)
        let month = calendar.component(.month, from: monthReference)
        let targetKey = year * 100 + month

        switch scope {
        case .allOccurrences:
            let toDelete = provisions.filter { $0.categoryId == categoryId }
            provisions.removeAll { $0.categoryId == categoryId }
            for p in toDelete {
                cloudSyncService?.recordLocalMutation(entityName: "category_provisions", entityId: p.id, operation: .delete)
            }
        case .onlyThisMonth:
            let candidates = provisions
                .enumerated()
                .filter { $0.element.categoryId == categoryId && $0.element.yearMonthKey <= targetKey }
                .sorted { a, b in
                    if a.element.yearMonthKey == b.element.yearMonthKey {
                        return a.element.createdAt < b.element.createdAt
                    }
                    return a.element.yearMonthKey < b.element.yearMonthKey
                }
            if let latest = candidates.last {
                let idx = latest.offset
                if provisions[idx].repeatForFutureMonths {
                    var excluded = provisions[idx].excludedYearMonthKeys ?? []
                    excluded.insert(targetKey)
                    provisions[idx].excludedYearMonthKeys = excluded
                    provisions[idx].monthlyOverrides?.removeValue(forKey: targetKey)
                    let prov = provisions[idx]
                    cloudSyncService?.recordLocalMutation(entityName: "category_provisions", entityId: prov.id, operation: .upsert, entity: prov)
                } else if provisions[idx].yearMonthKey == targetKey {
                    let deletedId = provisions[idx].id
                    provisions.remove(at: idx)
                    cloudSyncService?.recordLocalMutation(entityName: "category_provisions", entityId: deletedId, operation: .delete)
                }
            }
        case .fromThisMonthOnward:
            removeCategoryProvision(categoryId: categoryId, for: monthReference)
            return
        }

        save()
    }

    /// Remove ou zera a provisão de uma categoria a partir do mês informado.
    public func removeCategoryProvision(categoryId: UUID, for monthReference: Date) {
        setCategoryProvision(
            categoryId: categoryId,
            estimatedAmount: 0,
            for: monthReference,
            repeatForFutureMonths: true,
            editScope: .thisAndFutureMonths
        )
    }

    /// Retorna detalhes da Verba Livre efetiva vigente para a categoria no mês (`monthReference`).
    public func effectiveProvisionDetails(
        forCategory categoryId: UUID,
        in monthReference: Date
    ) -> (provision: CategoryProvision, isInherited: Bool, isLocalOverride: Bool)? {
        let targetYear = calendar.component(.year, from: monthReference)
        let targetMonth = calendar.component(.month, from: monthReference)
        let targetKey = targetYear * 100 + targetMonth

        let candidates = provisions
            .filter { $0.categoryId == categoryId && $0.yearMonthKey <= targetKey }
            .sorted { a, b in
                if a.yearMonthKey == b.yearMonthKey {
                    return a.createdAt < b.createdAt
                }
                return a.yearMonthKey < b.yearMonthKey
            }

        guard let latest = candidates.last else { return nil }

        if latest.excludedYearMonthKeys?.contains(targetKey) == true {
            return nil
        }

        if let overrideAmount = latest.monthlyOverrides?[targetKey] {
            guard overrideAmount > 0 else { return nil }
            var resolved = latest
            resolved.estimatedAmount = overrideAmount
            return (resolved, latest.yearMonthKey < targetKey, true)
        }

        if latest.yearMonthKey == targetKey {
            guard latest.estimatedAmount > 0 else { return nil }
            return (latest, false, false)
        } else {
            guard latest.repeatForFutureMonths && latest.estimatedAmount > 0 else { return nil }
            return (latest, true, false)
        }
    }

    /// Retorna a provisão efetiva vigente para a categoria no mês (`monthReference`),
    /// respeitando a configuração de recorrência (`repeatForFutureMonths`) e exceções mensais.
    public func effectiveProvision(
        forCategory categoryId: UUID,
        in monthReference: Date
    ) -> (provision: CategoryProvision, isInherited: Bool)? {
        guard let details = effectiveProvisionDetails(forCategory: categoryId, in: monthReference) else {
            return nil
        }
        return (details.provision, details.isInherited)
    }

    // MARK: - Specific Item Quotas CRUD & Redemption ("Cotas de Itens Específicos")

    public static func defaultIconForQuotaName(_ name: String) -> String {
        let lower = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        if lower.contains("agua") || lower.contains("galao") {
            return "drop.fill"
        } else if lower.contains("gas") || lower.contains("botijao") {
            return "flame.fill"
        } else if lower.contains("combustivel") || lower.contains("gasolina") || lower.contains("tanque") {
            return "fuelpump.fill"
        } else if lower.contains("feira") || lower.contains("mercado") || lower.contains("cesta") {
            return "cart.fill"
        } else if lower.contains("remedio") || lower.contains("farmacia") {
            return "pills.fill"
        } else if lower.contains("racao") || lower.contains("pet") {
            return "pawprint.fill"
        }
        return "shippingbox.fill"
    }

    /// Cria ou atualiza uma Cota de Item Específico (ex: "Galão de Água", 4 unidades a R$ 30,00 cada)
    /// ou um Planejamento de Investimento com suporte a escopo temporal (`.onlyThisMonth` vs `.thisAndFutureMonths`).
    @discardableResult
    public func saveCategoryQuota(
        seriesId: UUID? = nil,
        categoryId: UUID,
        name: String,
        iconSymbol: String? = nil,
        plannedQuantity: Int,
        estimatedUnitPrice: Double,
        for monthReference: Date,
        repeatForFutureMonths: Bool = true,
        editScope: ProvisionEditScope = .thisAndFutureMonths,
        quotaType: QuotaType = .expense,
        linkedInvestmentId: UUID? = nil
    ) -> CategoryQuotaRule {
        let year = calendar.component(.year, from: monthReference)
        let month = calendar.component(.month, from: monthReference)
        let targetKey = year * 100 + month
        let cleanQty = max(1, plannedQuantity)
        let cleanPrice = max(0.0, estimatedUnitPrice)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName: String = {
            if !trimmedName.isEmpty { return trimmedName }
            if quotaType == .investment, let invId = linkedInvestmentId, let inv = investments.first(where: { $0.id == invId }) {
                return "Aporte \(inv.name)"
            }
            return "Item Provisionado"
        }()
        let resolvedIcon: String = {
            if let iconSymbol = iconSymbol, !iconSymbol.isEmpty { return iconSymbol }
            if quotaType == .investment, let invId = linkedInvestmentId, let inv = investments.first(where: { $0.id == invId }) {
                return inv.iconSymbol
            }
            return Self.defaultIconForQuotaName(cleanName)
        }()

        if let existingSeriesId = seriesId,
           categoryQuotas.contains(where: { $0.seriesId == existingSeriesId }) {
            if editScope == .onlyThisMonth {
                let candidates = categoryQuotas
                    .enumerated()
                    .filter { $0.element.seriesId == existingSeriesId && $0.element.yearMonthKey <= targetKey }
                    .sorted { a, b in
                        if a.element.yearMonthKey == b.element.yearMonthKey {
                            return a.element.createdAt < b.element.createdAt
                        }
                        return a.element.yearMonthKey < b.element.yearMonthKey
                    }

                if let latest = candidates.last {
                    let idx = latest.offset
                    if categoryQuotas[idx].yearMonthKey == targetKey && !categoryQuotas[idx].repeatForFutureMonths {
                        categoryQuotas[idx].name = cleanName
                        categoryQuotas[idx].iconSymbol = resolvedIcon
                        categoryQuotas[idx].plannedQuantity = cleanQty
                        categoryQuotas[idx].estimatedUnitPrice = cleanPrice
                        categoryQuotas[idx].quotaType = quotaType
                        categoryQuotas[idx].linkedInvestmentId = linkedInvestmentId
                    } else {
                        var overrides = categoryQuotas[idx].monthlyOverrides ?? [:]
                        overrides[targetKey] = CategoryQuotaMonthlyOverride(
                            name: cleanName,
                            plannedQuantity: cleanQty,
                            estimatedUnitPrice: cleanPrice
                        )
                        categoryQuotas[idx].monthlyOverrides = overrides
                        categoryQuotas[idx].excludedYearMonthKeys?.remove(targetKey)
                    }
                    save()
                    let rule = categoryQuotas[idx]
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: rule.id, operation: .upsert, entity: rule)
                    return rule
                }
            }

            // Escopo: .thisAndFutureMonths
            let removedRules = categoryQuotas.filter { $0.seriesId == existingSeriesId && $0.yearMonthKey > targetKey }
            categoryQuotas.removeAll { $0.seriesId == existingSeriesId && $0.yearMonthKey > targetKey }
            for removed in removedRules {
                cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: removed.id, operation: .delete)
            }
            for idx in categoryQuotas.indices where categoryQuotas[idx].seriesId == existingSeriesId {
                var changed = false
                if let overrides = categoryQuotas[idx].monthlyOverrides {
                    let filtered = overrides.filter { $0.key < targetKey }
                    if filtered != overrides {
                        categoryQuotas[idx].monthlyOverrides = filtered.isEmpty ? nil : filtered
                        changed = true
                    }
                }
                if let excluded = categoryQuotas[idx].excludedYearMonthKeys {
                    let filtered = excluded.filter { $0 < targetKey }
                    if filtered != excluded {
                        categoryQuotas[idx].excludedYearMonthKeys = filtered.isEmpty ? nil : filtered
                        changed = true
                    }
                }
                if changed {
                    let rule = categoryQuotas[idx]
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: rule.id, operation: .upsert, entity: rule)
                }
            }

            if let exactIdx = categoryQuotas.firstIndex(where: {
                $0.seriesId == existingSeriesId && $0.year == year && $0.month == month
            }) {
                categoryQuotas[exactIdx].name = cleanName
                categoryQuotas[exactIdx].iconSymbol = resolvedIcon
                categoryQuotas[exactIdx].plannedQuantity = cleanQty
                categoryQuotas[exactIdx].estimatedUnitPrice = cleanPrice
                categoryQuotas[exactIdx].repeatForFutureMonths = repeatForFutureMonths
                categoryQuotas[exactIdx].quotaType = quotaType
                categoryQuotas[exactIdx].linkedInvestmentId = linkedInvestmentId
                save()
                let rule = categoryQuotas[exactIdx]
                cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: rule.id, operation: .upsert, entity: rule)
                return rule
            } else {
                let updatedFutureRule = CategoryQuotaRule(
                    seriesId: existingSeriesId,
                    categoryId: categoryId,
                    name: cleanName,
                    iconSymbol: resolvedIcon,
                    year: year,
                    month: month,
                    plannedQuantity: cleanQty,
                    estimatedUnitPrice: cleanPrice,
                    repeatForFutureMonths: repeatForFutureMonths,
                    quotaType: quotaType,
                    linkedInvestmentId: linkedInvestmentId
                )
                categoryQuotas.append(updatedFutureRule)
                save()
                cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: updatedFutureRule.id, operation: .upsert, entity: updatedFutureRule)
                return updatedFutureRule
            }
        }

        let newRule = CategoryQuotaRule(
            seriesId: seriesId,
            categoryId: categoryId,
            name: cleanName,
            iconSymbol: resolvedIcon,
            year: year,
            month: month,
            plannedQuantity: cleanQty,
            estimatedUnitPrice: cleanPrice,
            repeatForFutureMonths: repeatForFutureMonths,
            quotaType: quotaType,
            linkedInvestmentId: linkedInvestmentId
        )
        categoryQuotas.append(newRule)
        save()
        cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: newRule.id, operation: .upsert, entity: newRule)
        return newRule
    }

    /// Exclui uma Cota de Item Específico respeitando o escopo temporal:
    /// - `.onlyThisMonth`: remove do mês corrente; continua nos meses anteriores e reaparece nos futuros.
    /// - `.fromThisMonthOnward`: encerra a cota daquele mês em diante, preservando o histórico dos meses anteriores.
    /// - `.allOccurrences`: remove o registro e interrompe a recorrência definitivamente para frente e para trás.
    public func deleteCategoryQuota(
        seriesId: UUID,
        for monthReference: Date,
        scope: ProvisionDeleteScope
    ) {
        let year = calendar.component(.year, from: monthReference)
        let month = calendar.component(.month, from: monthReference)
        let targetKey = year * 100 + month

        switch scope {
        case .allOccurrences:
            let toDelete = categoryQuotas.filter { $0.seriesId == seriesId }
            categoryQuotas.removeAll { $0.seriesId == seriesId }
            for r in toDelete {
                cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: r.id, operation: .delete)
            }
        case .onlyThisMonth:
            let candidates = categoryQuotas
                .enumerated()
                .filter { $0.element.seriesId == seriesId && $0.element.yearMonthKey <= targetKey }
                .sorted { a, b in
                    if a.element.yearMonthKey == b.element.yearMonthKey {
                        return a.element.createdAt < b.element.createdAt
                    }
                    return a.element.yearMonthKey < b.element.yearMonthKey
                }
            if let latest = candidates.last {
                let idx = latest.offset
                if categoryQuotas[idx].repeatForFutureMonths {
                    var excluded = categoryQuotas[idx].excludedYearMonthKeys ?? []
                    excluded.insert(targetKey)
                    categoryQuotas[idx].excludedYearMonthKeys = excluded
                    categoryQuotas[idx].monthlyOverrides?.removeValue(forKey: targetKey)
                    let rule = categoryQuotas[idx]
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: rule.id, operation: .upsert, entity: rule)
                } else if categoryQuotas[idx].yearMonthKey == targetKey {
                    let deletedId = categoryQuotas[idx].id
                    categoryQuotas.remove(at: idx)
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: deletedId, operation: .delete)
                }
            }
        case .fromThisMonthOnward:
            let removedRules = categoryQuotas.filter { $0.seriesId == seriesId && $0.yearMonthKey > targetKey }
            categoryQuotas.removeAll { $0.seriesId == seriesId && $0.yearMonthKey > targetKey }
            for removed in removedRules {
                cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: removed.id, operation: .delete)
            }
            for idx in categoryQuotas.indices where categoryQuotas[idx].seriesId == seriesId {
                var changed = false
                if let overrides = categoryQuotas[idx].monthlyOverrides {
                    let filtered = overrides.filter { $0.key < targetKey }
                    if filtered != overrides {
                        categoryQuotas[idx].monthlyOverrides = filtered.isEmpty ? nil : filtered
                        changed = true
                    }
                }
                if let excluded = categoryQuotas[idx].excludedYearMonthKeys {
                    let filtered = excluded.filter { $0 < targetKey }
                    if filtered != excluded {
                        categoryQuotas[idx].excludedYearMonthKeys = filtered.isEmpty ? nil : filtered
                        changed = true
                    }
                }
                if changed {
                    let rule = categoryQuotas[idx]
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: rule.id, operation: .upsert, entity: rule)
                }
            }

            let hasPriorRecurring = categoryQuotas.contains {
                $0.seriesId == seriesId &&
                $0.yearMonthKey < targetKey &&
                $0.repeatForFutureMonths &&
                $0.plannedQuantity > 0 &&
                $0.estimatedUnitPrice > 0
            }

            if let exactIdx = categoryQuotas.firstIndex(where: {
                $0.seriesId == seriesId && $0.year == year && $0.month == month
            }) {
                if hasPriorRecurring {
                    categoryQuotas[exactIdx].plannedQuantity = 0
                    categoryQuotas[exactIdx].estimatedUnitPrice = 0
                    categoryQuotas[exactIdx].repeatForFutureMonths = true
                    let rule = categoryQuotas[exactIdx]
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: rule.id, operation: .upsert, entity: rule)
                } else {
                    let deletedId = categoryQuotas[exactIdx].id
                    categoryQuotas.remove(at: exactIdx)
                    cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: deletedId, operation: .delete)
                }
            } else if hasPriorRecurring {
                let template = categoryQuotas.first(where: { $0.seriesId == seriesId })
                let stopper = CategoryQuotaRule(
                    seriesId: seriesId,
                    categoryId: template?.categoryId ?? UUID(),
                    name: template?.name ?? "Cota Encerrada",
                    iconSymbol: template?.iconSymbol ?? "xmark.circle",
                    year: year,
                    month: month,
                    plannedQuantity: 0,
                    estimatedUnitPrice: 0,
                    repeatForFutureMonths: true,
                    quotaType: template?.quotaType ?? .expense,
                    linkedInvestmentId: template?.linkedInvestmentId
                )
                categoryQuotas.append(stopper)
                cloudSyncService?.recordLocalMutation(entityName: "category_quota_rules", entityId: stopper.id, operation: .upsert, entity: stopper)
            }
        }

        save()
    }

    /// Retorna os envelopes de Cotas Específicas ativas para uma categoria no mês informado.
    public func quotaEnvelopes(
        forCategory categoryId: UUID,
        in monthReference: Date
    ) -> [CategoryQuotaEnvelope] {
        let rulesForCat = categoryQuotas.filter { $0.categoryId == categoryId }
        return quotaEnvelopes(from: rulesForCat, in: monthReference)
    }

    /// Lista todas as cotas específicas ativas (despesas e planejamentos de investimento) no mês informado.
    public func allQuotaEnvelopes(for monthReference: Date) -> [CategoryQuotaEnvelope] {
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        if let y = comps.year, let m = comps.month {
            let ymKey = y * 100 + m
            if let cached = cachedQuotaEnvelopesByYM[ymKey] {
                return cached
            }
            let computed = quotaEnvelopes(from: categoryQuotas, in: monthReference)
            cachedQuotaEnvelopesByYM[ymKey] = computed
            return computed
        }
        return quotaEnvelopes(from: categoryQuotas, in: monthReference)
    }

    /// Calcula os envelopes de cotas a partir de uma coleção de regras fornecida.
    public func quotaEnvelopes(
        from rulesPool: [CategoryQuotaRule],
        in monthReference: Date
    ) -> [CategoryQuotaEnvelope] {
        let targetYear = calendar.component(.year, from: monthReference)
        let targetMonth = calendar.component(.month, from: monthReference)
        let targetKey = targetYear * 100 + targetMonth

        guard !rulesPool.isEmpty else { return [] }

        let groupedBySeries = Dictionary(grouping: rulesPool, by: \.seriesId)
        var envelopes: [CategoryQuotaEnvelope] = []

        for (seriesId, rules) in groupedBySeries {
            let candidates = rules
                .filter { $0.yearMonthKey <= targetKey }
                .sorted { a, b in
                    if a.yearMonthKey == b.yearMonthKey {
                        return a.createdAt < b.createdAt
                    }
                    return a.yearMonthKey < b.yearMonthKey
                }

            guard let latest = candidates.last else { continue }

            let isExcluded = rules.contains { $0.excludedYearMonthKeys?.contains(targetKey) == true }
            if isExcluded {
                continue
            }

            let effectiveName: String
            let effectiveQty: Int
            let effectiveUnitPrice: Double
            let isLocalOverride: Bool
            let isInherited = latest.yearMonthKey < targetKey

            if let override = latest.monthlyOverrides?[targetKey] {
                effectiveName = override.name ?? latest.name
                effectiveQty = override.plannedQuantity
                effectiveUnitPrice = override.estimatedUnitPrice
                isLocalOverride = true
            } else {
                if isInherited && !latest.repeatForFutureMonths {
                    continue
                }
                effectiveName = latest.name
                effectiveQty = latest.plannedQuantity
                effectiveUnitPrice = latest.estimatedUnitPrice
                isLocalOverride = false
            }

            guard effectiveQty > 0 && effectiveUnitPrice > 0 else { continue }

            let redemptionTxs = transactions.filter { tx in
                guard !tx.ignoreInConsolidated, tx.type == .expense else { return false }
                if tx.linkedQuotaId == seriesId {
                    if let quotaMonthKey = tx.linkedQuotaYearMonthKey {
                        return quotaMonthKey == targetKey
                    }
                    return isInMonth(tx.date, monthReference: monthReference)
                }
                if latest.quotaType == .investment, let linkedInvId = latest.linkedInvestmentId {
                    return tx.linkedInvestmentId == linkedInvId && tx.transactionOrigin == .investmentDeposit && isInMonth(tx.date, monthReference: monthReference)
                }
                return false
            }

            let consumedUnits = redemptionTxs.reduce(0) { $0 + max(1, $1.linkedQuotaUnits ?? 1) }
            let realizedSpend = redemptionTxs.reduce(0.0) { $0 + $1.amount }

            envelopes.append(
                CategoryQuotaEnvelope(
                    rule: latest,
                    name: effectiveName,
                    iconSymbol: latest.iconSymbol,
                    plannedQuantity: effectiveQty,
                    consumedUnits: consumedUnits,
                    estimatedUnitPrice: effectiveUnitPrice,
                    realizedExpense: realizedSpend,
                    repeatForFutureMonths: latest.repeatForFutureMonths,
                    isInheritedFromPreviousMonth: isInherited,
                    isLocalMonthOverride: isLocalOverride
                )
            )
        }

        return envelopes.sorted { a, b in
            if a.rule.createdAt == b.rule.createdAt {
                return a.name < b.name
            }
            return a.rule.createdAt < b.rule.createdAt
        }
    }

    /// Dá baixa em uma Cota Específica ou Planejamento de Investimento (ex: "+ Registrar Compra" / "Dar Baixa"),
    /// incrementando as unidades consumidas e inserindo automaticamente a transação real no extrato.
    /// Se for cota de investimento, credita o saldo do investimento e cria a movimentação correspondente.
    @discardableResult
    public func redeemCategoryQuota(
        seriesId: UUID,
        units: Int = 1,
        unitPriceOverride: Double? = nil,
        accountId: UUID,
        in monthReference: Date? = nil,
        transactionDate: Date = Date(),
        details: String = ""
    ) -> FinancialTransaction? {
        let targetMonth = monthReference ?? selectedMonth
        let targetYear = calendar.component(.year, from: targetMonth)
        let targetMonthNum = calendar.component(.month, from: targetMonth)
        let targetKey = targetYear * 100 + targetMonthNum

        let allActiveQuotas = allQuotaEnvelopes(for: targetMonth)
        let activeEnvelope = allActiveQuotas.first(where: { $0.seriesId == seriesId })
        let fallbackRule = categoryQuotas.first(where: { $0.seriesId == seriesId })

        let isInvestment = (activeEnvelope?.quotaType ?? fallbackRule?.quotaType) == .investment
        let linkedInvId = activeEnvelope?.linkedInvestmentId ?? fallbackRule?.linkedInvestmentId

        let finalCatId: UUID = {
            if isInvestment {
                return investmentDepositCategoryId()
            }
            if let catId = activeEnvelope?.categoryId ?? fallbackRule?.categoryId, category(for: catId) != nil {
                return catId
            }
            return fallbackCategoryId(for: .expense)
        }()

        let quotaName = activeEnvelope?.name ?? fallbackRule?.name ?? (isInvestment ? "Aporte em Investimento" : "Item de Cota")
        let defaultUnitPrice = activeEnvelope?.estimatedUnitPrice ?? fallbackRule?.estimatedUnitPrice ?? 0.0
        let cleanUnits = max(1, units)
        let actualUnitPrice = max(0.0, unitPriceOverride ?? defaultUnitPrice)
        let totalAmount = Double(cleanUnits) * actualUnitPrice

        let effectiveDate: Date = {
            if isInMonth(transactionDate, monthReference: targetMonth) {
                return transactionDate
            } else if monthReference == nil {
                return transactionDate
            } else {
                return targetMonth
            }
        }()

        let txTitle: String = {
            if isInvestment {
                return "Aporte: \(quotaName)"
            }
            return cleanUnits > 1 ? "\(quotaName) (\(cleanUnits) un.)" : quotaName
        }()

        let txDetails: String = {
            if !details.isEmpty { return details }
            if isInvestment {
                return "Aporte via planejamento de investimento: \(quotaName)"
            }
            return "Baixa de cota específica: \(cleanUnits) un. × \(BRLFormatters.currency(actualUnitPrice))"
        }()

        let txOrigin: TransactionOrigin = isInvestment ? .investmentDeposit : .standard

        let tx = FinancialTransaction(
            name: txTitle,
            details: txDetails,
            amount: totalAmount,
            date: effectiveDate,
            type: .expense,
            isPaid: true,
            categoryId: finalCatId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedInvestmentId: isInvestment ? linkedInvId : nil,
            linkedQuotaId: seriesId,
            linkedQuotaUnits: cleanUnits,
            linkedQuotaYearMonthKey: targetKey,
            transactionOrigin: txOrigin,
            linkedEntityID: isInvestment ? linkedInvId : nil
        )
        transactions.append(tx)

        if isInvestment, let invId = linkedInvId, let idx = investments.firstIndex(where: { $0.id == invId }) {
            investments[idx].balance += totalAmount
            let movement = InvestmentMovement(
                type: .deposit,
                amount: totalAmount,
                date: effectiveDate,
                sourceAccountId: accountId,
                investmentAccountId: investments[idx].investmentAccountId,
                notes: txDetails,
                generatedTransactionId: tx.id
            )
            investments[idx].movements.insert(movement, at: 0)
            cloudSyncService?.recordLocalMutation(entityName: "investment_items", entityId: invId, operation: .upsert, entity: investments[idx])
        }

        save()
        cloudSyncService?.recordLocalMutation(entityName: "financial_transactions", entityId: tx.id, operation: .upsert, entity: tx)
        return tx
    }

    /// Despesas Avulsas Realizadas: Soma das despesas reais confirmadas ou pendentes na categoria no mês
    /// que NÃO são baixas de cotas específicas (`linkedQuotaId == nil`). Consomem apenas a Verba Livre.
    public func realizedFreeBudgetExpense(forCategory categoryId: UUID, in monthReference: Date) -> Double {
        transactionsForMonth(monthReference)
            .filter {
                $0.type == .expense &&
                !$0.ignoreInConsolidated &&
                $0.categoryId == categoryId &&
                $0.linkedQuotaId == nil
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    /// Gasto Realizado Total ($G_{real}$) na categoria no mês (Despesas Avulsas + Baixas de Cotas).
    public func realizedMonthlyExpense(forCategory categoryId: UUID, in monthReference: Date) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && $0.categoryId == categoryId }
            .reduce(0.0) { $0 + $1.amount }
    }

    /// Envelope calculado exclusivamente para o Teto Geral de uma categoria no mês de referência.
    /// Categorias sem teto expressamente configurado (`estimatedAmount <= 0`) retornam `nil`
    /// e nunca exibem barras de progresso ou alertas de estouro por conta de cotas específicas ou despesas avulsas.
    public func provisionEnvelope(
        forCategory categoryId: UUID,
        in monthReference: Date
    ) -> CategoryProvisionEnvelope? {
        guard let cat = category(for: categoryId), cat.type == .expense else { return nil }
        guard let freeDetails = effectiveProvisionDetails(forCategory: categoryId, in: monthReference),
              freeDetails.provision.estimatedAmount > 0 else {
            return nil
        }

        let freeRealized = realizedFreeBudgetExpense(forCategory: categoryId, in: monthReference)

        return CategoryProvisionEnvelope(
            category: cat,
            provision: freeDetails.provision,
            isInheritedFromPreviousMonth: freeDetails.isInherited,
            estimatedAmount: freeDetails.provision.estimatedAmount,
            realizedExpense: freeRealized,
            isFreeBudgetLocalOverride: freeDetails.isLocalOverride
        )
    }

    /// Lista todos os envelopes de Teto de Categoria ativos no mês de referência (exclusivamente categorias com limite cadastrado).
    public func provisionEnvelopes(for monthReference: Date) -> [CategoryProvisionEnvelope] {
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        if let y = comps.year, let m = comps.month {
            let ymKey = y * 100 + m
            if let cached = cachedProvisionEnvelopesByYM[ymKey] {
                return cached
            }
            let computed = expenseCategories.compactMap { cat in
                provisionEnvelope(forCategory: cat.id, in: monthReference)
            }
            .sorted { a, b in
                if a.rawProgressPercentage == b.rawProgressPercentage {
                    return a.estimatedAmount > b.estimatedAmount
                }
                return a.rawProgressPercentage > b.rawProgressPercentage
            }
            cachedProvisionEnvelopesByYM[ymKey] = computed
            return computed
        }
        return expenseCategories.compactMap { cat in
            provisionEnvelope(forCategory: cat.id, in: monthReference)
        }
        .sorted { a, b in
            if a.rawProgressPercentage == b.rawProgressPercentage {
                return a.estimatedAmount > b.estimatedAmount
            }
            return a.rawProgressPercentage > b.rawProgressPercentage
        }
    }

    /// Soma dos Tetos de Categoria Restantes ($\sum \text{Tetos de Categoria Restantes}$).
    /// Para meses anteriores ao atual (mês já fechado), retorna 0.0 pois as cotas/previsões passadas não afetam o saldo projetado futuro.
    public func totalCategoryProvisionsRemaining(for monthReference: Date, referenceNow: Date? = nil) -> Double {
        if isMonthPriorToCurrent(monthReference, referenceNow: referenceNow) {
            return 0.0
        }
        return provisionEnvelopes(for: monthReference)
            .reduce(0.0) { $0 + $1.remainingProvision }
    }

    /// Soma das Cotas Específicas Restantes ($\sum \text{Cotas Restantes}$).
    /// Para meses anteriores ao atual (mês já fechado), retorna 0.0 pois as cotas/previsões passadas não afetam o saldo projetado futuro.
    public func totalQuotasRemaining(for monthReference: Date, referenceNow: Date? = nil) -> Double {
        if isMonthPriorToCurrent(monthReference, referenceNow: referenceNow) {
            return 0.0
        }
        return allQuotaEnvelopes(for: monthReference)
            .reduce(0.0) { $0 + $1.remainingProvision }
    }

    /// Soma total dos valores estimados ($\sum T_{estimado}$) configurados para o mês (Cotas Específicas + Tetos de Categoria).
    public func totalEstimatedProvision(for monthReference: Date) -> Double {
        let quotasEstimated = allQuotaEnvelopes(for: monthReference)
            .reduce(0.0) { $0 + $1.totalEstimatedAmount }
        let categoriesEstimated = provisionEnvelopes(for: monthReference)
            .reduce(0.0) { $0 + $1.estimatedAmount }
        return quotasEstimated + categoriesEstimated
    }

    /// Provisão Total Futura Consolidada no Dashboard:
    /// $\text{Provisão Total Futura} = \sum \text{Cotas Restantes} + \sum \text{Tetos de Categoria Restantes}$
    /// Para meses anteriores ao atual (mês já fechado), retorna 0.0 pois o mês já encerrou e prevalecem apenas despesas reais realizadas.
    public func totalRemainingProvision(for monthReference: Date, referenceNow: Date? = nil) -> Double {
        if isMonthPriorToCurrent(monthReference, referenceNow: referenceNow) {
            return 0.0
        }
        return totalQuotasRemaining(for: monthReference) + totalCategoryProvisionsRemaining(for: monthReference)
    }

    /// Soma das provisões de gastos variáveis e cotas restantes acumuladas a partir do mês corrente até o mês de referência (`throughMonth`).
    /// Para meses anteriores ao atual (mês já fechado), retorna 0.0 pois cotas/previsões passadas não afetam o saldo projetado futuro.
    /// Para o mês atual e meses futuros, acumula a provisão não consumida de cada mês:
    /// $\sum_{m = \text{current}}^{\text{throughMonth}} \text{totalRemainingProvision}(for: m)$
    public func accumulatedRemainingProvisions(
        throughMonth monthReference: Date,
        referenceNow: Date? = nil
    ) -> Double {
        let now = referenceNow ?? effectiveCurrentDate
        let currentMonthStart = startOfMonth(for: now)
        let targetMonthStart = startOfMonth(for: monthReference)

        // Se o mês de referência é anterior ao mês atual, o mês já fechou: desconsidera cotas e previsões
        if targetMonthStart < currentMonthStart {
            return 0.0
        }

        var total = 0.0
        var cursor = currentMonthStart

        // Itera mês a mês desde o mês atual até o mês de referência
        while cursor <= targetMonthStart {
            total += totalRemainingProvision(for: cursor, referenceNow: now)
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = nextMonth
        }

        return total
    }

    /// Retorna a soma de previsões ativas (tetos e cotas restantes) estritamente do exercício do ano selecionado:
    /// - Ano passado (< ano atual): 0.0
    /// - Ano corrente (== ano atual): soma do mês atual até dezembro
    /// - Ano futuro (> ano atual): soma de todos os 12 meses (janeiro a dezembro) daquele ano
    public func activeRemainingProvisionsForYear(_ yearReference: Date, referenceNow: Date? = nil) -> Double {
        let now = referenceNow ?? effectiveCurrentDate
        let currentYear = calendar.component(.year, from: now)
        let targetYear = calendar.component(.year, from: yearReference)

        if targetYear < currentYear {
            return 0.0
        }

        let currentMonth = calendar.component(.month, from: now)
        let startMonth = (targetYear == currentYear) ? currentMonth : 1

        var total = 0.0
        for m in startMonth...12 {
            var comps = DateComponents()
            comps.year = targetYear
            comps.month = m
            comps.day = 15
            if let mDate = calendar.date(from: comps) {
                total += totalRemainingProvision(for: mDate, referenceNow: now)
            }
        }
        return total
    }

    /// Discriminativo mês a mês das previsões ativas para o exercício (para popover / tooltip)
    public func activeRemainingProvisionsMonthlyBreakdownForYear(
        _ yearReference: Date,
        referenceNow: Date? = nil
    ) -> [(monthDate: Date, label: String, amount: Double)] {
        let now = referenceNow ?? effectiveCurrentDate
        let currentYear = calendar.component(.year, from: now)
        let targetYear = calendar.component(.year, from: yearReference)

        guard targetYear >= currentYear else { return [] }

        let currentMonth = calendar.component(.month, from: now)
        let startMonth = (targetYear == currentYear) ? currentMonth : 1

        var breakdown: [(Date, String, Double)] = []
        for m in startMonth...12 {
            var comps = DateComponents()
            comps.year = targetYear
            comps.month = m
            comps.day = 15
            if let mDate = calendar.date(from: comps) {
                let amount = totalRemainingProvision(for: mDate, referenceNow: now)
                let label = BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized
                breakdown.append((mDate, label, amount))
            }
        }
        return breakdown
    }

    /// Subtítulo dinâmico para o card de Saldo Previsto / Resultado Consolidado respeitando rigorosamente a linha do tempo:
    /// 1. Mês Encerrado (Passado): "Mês encerrado"
    /// 2. Mês Vigente (Atual): "Deduzindo R$ [X] restantes em tetos/cotas deste mês"
    /// 3. Mês Futuro: "Deduzindo R$ [X] planejados em tetos/cotas para este mês"
    /// 4. Visão Anual:
    ///    - Ano Encerrado: "Ano encerrado"
    ///    - Ano Corrente / Futuro: "Deduzindo R$ [SomaAcumuladaRestanteAtiva] acumulados em cotas"
    public func deductionSubtitleForProjectedBalance(
        periodMode: DashboardPeriodMode,
        selectedMonth: Date,
        referenceNow: Date? = nil
    ) -> String {
        let now = referenceNow ?? effectiveCurrentDate

        if periodMode == .annual {
            let currentYear = calendar.component(.year, from: now)
            let selectedYear = calendar.component(.year, from: selectedMonth)

            if selectedYear < currentYear {
                return "Ano encerrado"
            }

            let activeYearProvisions = activeRemainingProvisionsForYear(selectedMonth, referenceNow: now)
            if activeYearProvisions > 0 {
                return "Deduzindo \(BRLFormatters.currency(activeYearProvisions)) acumulados em cotas"
            } else {
                return "Projeção anual de caixa final"
            }
        } else {
            let startSelected = startOfMonth(for: selectedMonth)
            let startCurrent = startOfMonth(for: now)

            if startSelected < startCurrent {
                return "Mês encerrado"
            } else if startSelected == startCurrent {
                let remaining = totalRemainingProvision(for: selectedMonth, referenceNow: now)
                if remaining > 0 {
                    return "Deduzindo \(BRLFormatters.currency(remaining)) restantes em tetos/cotas deste mês"
                } else {
                    return "Projeção de caixa final"
                }
            } else {
                let planned = totalRemainingProvision(for: selectedMonth, referenceNow: now)
                if planned > 0 {
                    return "Deduzindo \(BRLFormatters.currency(planned)) planejados em tetos/cotas para este mês"
                } else {
                    return "Projeção de caixa final"
                }
            }
        }
    }

    /// Tooltip explicativo com detalhamento mês a mês dos tetos/cotas abatidos (para Visão Anual)
    public func deductionBreakdownTooltipForProjectedBalance(
        periodMode: DashboardPeriodMode,
        selectedMonth: Date,
        referenceNow: Date? = nil
    ) -> String? {
        guard periodMode == .annual else { return nil }
        let now = referenceNow ?? effectiveCurrentDate
        let currentYear = calendar.component(.year, from: now)
        let selectedYear = calendar.component(.year, from: selectedMonth)
        guard selectedYear >= currentYear else { return nil }

        let breakdown = activeRemainingProvisionsMonthlyBreakdownForYear(selectedMonth, referenceNow: now)
        guard !breakdown.isEmpty else { return nil }

        let total = breakdown.reduce(0.0) { $0 + $1.amount }
        guard total > 0 else { return nil }

        var lines = ["Detalhamento de tetos/cotas ativas no exercício (\(selectedYear)):"]
        for item in breakdown where item.amount > 0 {
            lines.append("• \(item.label): \(BRLFormatters.currency(item.amount))")
        }
        lines.append("Total deduzido: \(BRLFormatters.currency(total))")
        return lines.joined(separator: "\n")
    }

    /// Despesa total projetada do mês considerando despesas reais + provisões variáveis remanescentes ($\sum P_{restante}$).
    /// Para meses anteriores ao atual (mês já fechado), reflete unicamente as despesas reais registradas.
    public func projectedMonthlyExpense(for monthReference: Date) -> Double {
        monthlyExpense(for: monthReference, onlyPaid: false) + totalRemainingProvision(for: monthReference)
    }

    /// Resultado líquido projetado do mês considerando receitas - despesas reais - provisões remanescentes.
    public func projectedMonthlyNetBalance(for monthReference: Date) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: false) - projectedMonthlyExpense(for: monthReference)
    }

    // MARK: - Annual Summaries & End-of-Year Projections (31/12)

    public func transactionsForYear(_ yearReference: Date) -> [FinancialTransaction] {
        ensureTransactionIndexesBuilt()
        let y = calendar.component(.year, from: yearReference)
        return cachedTransactionsByYear?[y] ?? []
    }

    public func annualIncome(for yearReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForYear(yearReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func annualExpense(for yearReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForYear(yearReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func annualNetBalance(for yearReference: Date, onlyPaid: Bool = false) -> Double {
        annualIncome(for: yearReference, onlyPaid: onlyPaid) - annualExpense(for: yearReference, onlyPaid: onlyPaid)
    }

    public func annualOperatingNet(for yearReference: Date) -> Double {
        annualIncome(for: yearReference) - annualExpense(for: yearReference)
    }

    public func annualSavingsRate(for yearReference: Date) -> Double? {
        let income = annualIncome(for: yearReference)
        guard income > 0 else { return nil }
        let net = annualOperatingNet(for: yearReference)
        return (net / income) * 100.0
    }

    public func annualReceivedIncome(for yearReference: Date) -> Double {
        annualIncome(for: yearReference, onlyPaid: true)
    }

    public func annualPendingIncome(for yearReference: Date) -> Double {
        transactionsForYear(yearReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && !$0.isPaid }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    public func annualPaidExpense(for yearReference: Date) -> Double {
        annualExpense(for: yearReference, onlyPaid: true)
    }

    public func annualPendingExpense(for yearReference: Date) -> Double {
        transactionsForYear(yearReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && !$0.isPaid }
            .reduce(0) { $0 + effectiveTransactionAmount(for: $1) }
    }

    /// Saldo acumulado consolidado projetado até o último dia do ano (31/12 do ano de `yearReference`)
    public func accumulatedConsolidatedBalanceThroughYear(_ yearReference: Date, includeProjectedUnpaid: Bool = true) -> Double {
        let cutoff = endOfYear(for: yearReference)
        return accumulatedConsolidatedBalance(throughMonth: cutoff, includeProjectedUnpaid: includeProjectedUnpaid)
    }

    public func annualCategoryBreakdown(for yearReference: Date, type: TransactionType) -> [CategorySpendSummary] {
        let yearTxs = transactionsForYear(yearReference)
            .filter { $0.type == type && !$0.ignoreInConsolidated }
        let grandTotal = yearTxs.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        guard grandTotal > 0 else { return [] }

        var grouped: [UUID: (sum: Double, count: Int)] = [:]
        for tx in yearTxs {
            let effAmt = effectiveTransactionAmount(for: tx)
            guard effAmt > 0.001 else { continue }
            let current = grouped[tx.categoryId] ?? (0.0, 0)
            grouped[tx.categoryId] = (current.sum + effAmt, current.count + 1)
        }

        var result: [CategorySpendSummary] = []
        for (catId, info) in grouped {
            let cat = category(for: catId) ?? CategoryItem(
                id: catId,
                name: "Outros",
                type: type,
                iconSymbol: "tag.fill",
                colorHex: "#64748B"
            )
            result.append(
                CategorySpendSummary(
                    category: cat,
                    total: info.sum,
                    percentage: (info.sum / grandTotal) * 100.0,
                    count: info.count
                )
            )
        }

        return result.sorted { $0.total > $1.total }
    }

    /// Série dos 12 meses do ano selecionado (Janeiro a Dezembro) projetada até 31/12
    public func annualCashFlowSeries(for yearReference: Date) -> [MonthlyCashFlowPoint] {
        let year = calendar.component(.year, from: yearReference)
        var points: [MonthlyCashFlowPoint] = []
        for month in 1...12 {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 15
            if let mDate = calendar.date(from: comps) {
                let inc = monthlyIncome(for: mDate)
                let exp = monthlyExpense(for: mDate)
                let acc = accumulatedConsolidatedBalance(throughMonth: mDate, includeProjectedUnpaid: true)
                let remProv = isMonthPriorToCurrent(mDate) ? 0.0 : totalRemainingProvision(for: mDate)
                let isPast = isMonthPriorToCurrent(mDate)
                points.append(
                    MonthlyCashFlowPoint(
                        monthDate: mDate,
                        label: BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized,
                        income: inc,
                        expense: exp,
                        net: inc - exp,
                        accumulatedBalance: acc,
                        remainingProvisions: remProv,
                        isPastMonth: isPast
                    )
                )
            }
        }
        return points
    }

    /// Saldo atual de uma conta específica considerando saldo inicial e transações pagas (não ignoradas no consolidado)
    public func currentBalance(forAccount accountId: UUID, upTo dateLimit: Date? = nil) -> Double {
        guard let acc = account(for: accountId) else { return 0.0 }
        let limit = dateLimit.map { endOfMonth(for: $0) }
        let delta = transactions
            .filter { tx in
                guard tx.accountId == accountId else { return false }
                guard !tx.ignoreInConsolidated else { return false }
                if let limit {
                    return tx.date <= limit && (tx.isPaid || tx.date <= limit)
                } else {
                    return tx.isPaid
                }
            }
            .reduce(0.0) { $0 + $1.signedAmount }
        return acc.initialBalance + delta
    }

    /// Saldo acumulado consolidado até o fim do mês informado (`monthReference`),
    /// incluindo saldo inicial das contas + movimentações até aquele mês + investimentos marcados com "Exibir no consolidado"
    /// menos as provisões de gastos variáveis e cotas restantes acumuladas a partir do mês atual quando `includeProjectedUnpaid == true`.
    /// Para meses anteriores ao atual (mês já fechado), as cotas/previsões são desconsideradas.
    public func accumulatedConsolidatedBalance(throughMonth monthReference: Date, includeProjectedUnpaid: Bool = true) -> Double {
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        let cacheKey: Int? = {
            if let y = comps.year, let m = comps.month {
                return (y * 100 + m) * 2 + (includeProjectedUnpaid ? 1 : 0)
            }
            return nil
        }()
        if let key = cacheKey, let cached = cachedAccumulatedBalanceByKey[key] {
            return cached
        }

        let cutoff = endOfMonth(for: monthReference)
        let initialAccountsSum = accounts.reduce(0.0) { $0 + $1.initialBalance }
        let transactionsDelta = transactions
            .filter { tx in
                guard !tx.ignoreInConsolidated else { return false }
                guard tx.date <= cutoff else { return false }
                return includeProjectedUnpaid ? true : tx.isPaid
            }
            .reduce(0.0) { $0 + effectiveSignedTransactionAmount(for: $1) }

        let consolidatedInvestmentsSum = investments
            .filter(\.showInConsolidated)
            .reduce(0.0) { $0 + $1.balance }

        let remainingProvisions = includeProjectedUnpaid ? accumulatedRemainingProvisions(throughMonth: monthReference) : 0.0

        let result = initialAccountsSum + transactionsDelta + consolidatedInvestmentsSum - remainingProvisions
        if let key = cacheKey {
            cachedAccumulatedBalanceByKey[key] = result
        }
        return result
    }

    public var totalCheckingBalanceNow: Double {
        accounts.reduce(0.0) { $0 + currentBalance(forAccount: $1.id) }
    }

    public var totalInvestmentsBalance: Double {
        investments.reduce(0.0) { $0 + $1.balance }
    }

    public var consolidatedInvestmentsBalance: Double {
        investments.filter(\.showInConsolidated).reduce(0.0) { $0 + $1.balance }
    }

    public var totalConsolidatedPatrimonyNow: Double {
        totalCheckingBalanceNow + consolidatedInvestmentsBalance
    }

    // MARK: - Category Breakdown for Charts

    public func categoryBreakdown(for monthReference: Date, type: TransactionType) -> [CategorySpendSummary] {
        let monthTxs = transactionsForMonth(monthReference)
            .filter { $0.type == type && !$0.ignoreInConsolidated }
        let grandTotal = monthTxs.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        guard grandTotal > 0 else { return [] }

        var grouped: [UUID: (sum: Double, count: Int)] = [:]
        for tx in monthTxs {
            let effAmt = effectiveTransactionAmount(for: tx)
            guard effAmt > 0.001 else { continue }
            let current = grouped[tx.categoryId] ?? (0.0, 0)
            grouped[tx.categoryId] = (current.sum + effAmt, current.count + 1)
        }

        var result: [CategorySpendSummary] = []
        for (catId, info) in grouped {
            let cat = category(for: catId) ?? CategoryItem(
                id: catId,
                name: "Outros",
                type: type,
                iconSymbol: "tag.fill",
                colorHex: "#64748B"
            )
            result.append(
                CategorySpendSummary(
                    category: cat,
                    total: info.sum,
                    percentage: (info.sum / grandTotal) * 100.0,
                    count: info.count
                )
            )
        }

        return result.sorted { $0.total > $1.total }
    }

    public func cashFlowSeries(around centerMonth: Date, monthsBack: Int = 3, monthsForward: Int = 4) -> [MonthlyCashFlowPoint] {
        var points: [MonthlyCashFlowPoint] = []
        for offset in (-monthsBack)...monthsForward {
            if let mDate = calendar.date(byAdding: .month, value: offset, to: centerMonth) {
                let inc = monthlyIncome(for: mDate)
                let exp = monthlyExpense(for: mDate)
                let acc = accumulatedConsolidatedBalance(throughMonth: mDate, includeProjectedUnpaid: true)
                let remProv = isMonthPriorToCurrent(mDate) ? 0.0 : totalRemainingProvision(for: mDate)
                let isPast = isMonthPriorToCurrent(mDate)
                points.append(
                    MonthlyCashFlowPoint(
                        monthDate: mDate,
                        label: BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized,
                        income: inc,
                        expense: exp,
                        net: inc - exp,
                        accumulatedBalance: acc,
                        remainingProvisions: remProv,
                        isPastMonth: isPast
                    )
                )
            }
        }
        return points
    }

    // MARK: - Comprehensive Dashboard Debt Breakdown

    public func buildComprehensiveDebtSummary(referenceDate: Date = Date(), isAnnual: Bool = false) -> ComprehensiveDebtSummary {
        let currentPeriodUnpaid = transactions.filter { tx in
            tx.type == .expense &&
            !tx.isPaid &&
            !tx.ignoreInConsolidated &&
            (isAnnual ? isInYear(tx.date, yearReference: referenceDate) : isInMonth(tx.date, monthReference: referenceDate))
        }

        let endOfCurrentPeriod = isAnnual ? endOfYear(for: referenceDate) : endOfMonth(for: referenceDate)
        let futureRegularUnpaid = transactions.filter { tx in
            tx.type == .expense &&
            !tx.isPaid &&
            !tx.ignoreInConsolidated &&
            tx.date > endOfCurrentPeriod &&
            tx.linkedContractId == nil
        }

        let openDebts = activeDebts
        let openLoans = activeContracts(for: .loan)
        let openFinancings = activeContracts(for: .financing)

        let currentMonthUnpaidSum = currentPeriodUnpaid.reduce(0.0) { $0 + $1.amount }
        let futureRegularSum = futureRegularUnpaid.reduce(0.0) { $0 + $1.amount }
        let debtsSum = openDebts.reduce(0.0) { $0 + $1.originalAmount }

        let loansNominalSum = openLoans.reduce(0.0) { $0 + remainingNominalAmount(for: $1, asOf: endOfCurrentPeriod) }
        let loansProjectedSum = openLoans.reduce(0.0) { $0 + projectedPayoffAmount(for: $1, asOf: endOfCurrentPeriod) }
        let loansPaidTotal = openLoans.reduce(0.0) { $0 + amortizedAmountInPeriod(for: $1, referenceDate: referenceDate, isAnnual: isAnnual) }
        let loansRealAmortizationTotal = openLoans.reduce(0.0) { $0 + realAmortizationAmountInPeriod(for: $1, referenceDate: referenceDate, isAnnual: isAnnual) }

        let financingsNominalSum = openFinancings.reduce(0.0) { $0 + remainingNominalAmount(for: $1, asOf: endOfCurrentPeriod) }
        let financingsProjectedSum = openFinancings.reduce(0.0) { $0 + projectedPayoffAmount(for: $1, asOf: endOfCurrentPeriod) }
        let financingsPaidTotal = openFinancings.reduce(0.0) { $0 + amortizedAmountInPeriod(for: $1, referenceDate: referenceDate, isAnnual: isAnnual) }
        let financingsRealAmortizationTotal = openFinancings.reduce(0.0) { $0 + realAmortizationAmountInPeriod(for: $1, referenceDate: referenceDate, isAnnual: isAnnual) }

        var items: [DebtLineItem] = []

        for tx in currentPeriodUnpaid {
            items.append(
                DebtLineItem(
                    id: tx.id,
                    title: tx.name,
                    subtitle: "Transação pendente do mês atual (\(BRLFormatters.shortDate(tx.date)))",
                    section: "Transações Atuais",
                    nominalAmount: tx.amount,
                    projectedPayoffAmount: tx.amount,
                    iconSymbol: "calendar.badge.exclamationmark",
                    colorHex: "#F59E0B"
                )
            )
        }

        for tx in futureRegularUnpaid {
            items.append(
                DebtLineItem(
                    id: tx.id,
                    title: tx.name,
                    subtitle: "Despesa futura agendada para \(BRLFormatters.shortDate(tx.date))",
                    section: "Transações Futuras",
                    nominalAmount: tx.amount,
                    projectedPayoffAmount: tx.amount,
                    iconSymbol: "clock.arrow.circlepath",
                    colorHex: "#3B82F6"
                )
            )
        }

        for debt in openDebts {
            let dateInfo = debt.contractedDate.map { "Contraída em \(BRLFormatters.shortDate($0))" } ?? "Dívida em aberto para negociação"
            items.append(
                DebtLineItem(
                    id: debt.id,
                    title: debt.name,
                    subtitle: dateInfo,
                    section: "Dívidas (Serasa / Acordos)",
                    nominalAmount: debt.originalAmount,
                    projectedPayoffAmount: debt.originalAmount,
                    iconSymbol: debt.iconSymbol,
                    colorHex: debt.colorHex
                )
            )
        }

        for loan in openLoans {
            let remCount = remainingInstallmentsCount(for: loan, asOf: endOfCurrentPeriod)
            let nom = remainingNominalAmount(for: loan, asOf: endOfCurrentPeriod)
            let proj = projectedPayoffAmount(for: loan, asOf: endOfCurrentPeriod)
            let paid = amortizedAmountInPeriod(for: loan, referenceDate: referenceDate, isAnnual: isAnnual)
            let paidStr = paid > 0 ? " • Pagamentos: \(BRLFormatters.currency(paid))" : ""
            items.append(
                DebtLineItem(
                    id: loan.id,
                    title: "\(loan.name) (\(loan.subtypeDisplayName))",
                    subtitle: "\(remCount)x restantes de \(BRLFormatters.currency(loan.installmentAmount))\(paidStr) • Juros \(String(format: "%.2f", loan.monthlyInterestRate))% a.m.",
                    section: "Empréstimos",
                    nominalAmount: nom,
                    projectedPayoffAmount: proj,
                    iconSymbol: loan.iconSymbol,
                    colorHex: "#D97706"
                )
            )
        }

        for fin in openFinancings {
            let remCount = remainingInstallmentsCount(for: fin, asOf: endOfCurrentPeriod)
            let nom = remainingNominalAmount(for: fin, asOf: endOfCurrentPeriod)
            let proj = projectedPayoffAmount(for: fin, asOf: endOfCurrentPeriod)
            let paid = amortizedAmountInPeriod(for: fin, referenceDate: referenceDate, isAnnual: isAnnual)
            let realAmort = realAmortizationAmountInPeriod(for: fin, referenceDate: referenceDate, isAnnual: isAnnual)
            var metricsStr = ""
            if paid > 0 {
                metricsStr += " • Pagamentos: \(BRLFormatters.currency(paid))"
            }
            if realAmort > 0 {
                metricsStr += " • Amortização Real: \(BRLFormatters.currency(realAmort))"
            }
            items.append(
                DebtLineItem(
                    id: fin.id,
                    title: "\(fin.name) (\(fin.subtypeDisplayName))",
                    subtitle: "\(remCount)x restantes de \(BRLFormatters.currency(fin.installmentAmount))\(metricsStr) • Juros \(String(format: "%.2f", fin.effectiveAnnualNominalRate))% a.a.",
                    section: "Financiamentos",
                    nominalAmount: nom,
                    projectedPayoffAmount: proj,
                    iconSymbol: fin.iconSymbol,
                    colorHex: "#8B5CF6"
                )
            )
        }

        let grandNominal = currentMonthUnpaidSum + futureRegularSum + debtsSum + loansNominalSum + financingsNominalSum
        let grandProjected = currentMonthUnpaidSum + futureRegularSum + debtsSum + loansProjectedSum + financingsProjectedSum

        return ComprehensiveDebtSummary(
            currentMonthUnpaidTransactions: currentPeriodUnpaid,
            futureUnpaidRegularTransactions: futureRegularUnpaid,
            activeDebts: openDebts,
            activeLoans: openLoans,
            activeFinancings: openFinancings,
            currentMonthUnpaidTotal: currentMonthUnpaidSum,
            futureRegularExpensesTotal: futureRegularSum,
            unpaidDebtsTotal: debtsSum,
            loansRemainingNominalTotal: loansNominalSum,
            loansProjectedPayoffTotal: loansProjectedSum,
            loansAmortizedInPeriodTotal: loansPaidTotal,
            financingsRemainingNominalTotal: financingsNominalSum,
            financingsProjectedPayoffTotal: financingsProjectedSum,
            financingsAmortizedInPeriodTotal: financingsPaidTotal,
            loansPaidInPeriodTotal: loansPaidTotal,
            loansRealAmortizationInPeriodTotal: loansRealAmortizationTotal,
            financingsPaidInPeriodTotal: financingsPaidTotal,
            financingsRealAmortizationInPeriodTotal: financingsRealAmortizationTotal,
            grandTotalNominal: grandNominal,
            grandTotalWithPayoffProjection: grandProjected,
            itemizedLines: items
        )
    }

    // MARK: - Period Debt Service & Cash Flow Breakdown (DTI vs Receitas)

    public func buildPeriodDebtServiceBreakdown(
        referenceDate: Date = Date(),
        isAnnual: Bool = false
    ) -> PeriodDebtServiceBreakdown {
        let income = isAnnual ? annualIncome(for: referenceDate) : monthlyIncome(for: referenceDate)
        let totalExpense = isAnnual ? annualExpense(for: referenceDate) : monthlyExpense(for: referenceDate)
        let periodTxs = isAnnual ? transactionsForYear(referenceDate) : transactionsForMonth(referenceDate)
        let expenseTxs = periodTxs.filter { $0.type == .expense && !$0.ignoreInConsolidated }

        let openLoans = activeContracts(for: .loan)
        let openFinancings = activeContracts(for: .financing)
        let loanIds = Set(openLoans.map(\.id))
        let financingIds = Set(openFinancings.map(\.id))
        let debtIds = Set(debts.map(\.id))

        let endOfPeriod = isAnnual ? endOfYear(for: referenceDate) : endOfMonth(for: referenceDate)

        // 1. Financiamentos no Período (Parcelas)
        let finTxSum = expenseTxs.filter { tx in
            (tx.linkedContractId.map { financingIds.contains($0) } ?? false) ||
            (tx.seriesGroupId.map { financingIds.contains($0) } ?? false)
        }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }

        let financingInstallments: Double
        if finTxSum > 0.001 {
            financingInstallments = finTxSum
        } else {
            financingInstallments = openFinancings.reduce(0.0) { sum, fin in
                let rem = remainingInstallmentsCount(for: fin, asOf: endOfPeriod)
                guard rem > 0 else { return sum }
                let countInPeriod = isAnnual ? min(rem, 12) : 1
                return sum + (Double(countInPeriod) * fin.installmentAmount)
            }
        }

        // 2. Empréstimos no Período (Parcelas)
        let loanTxSum = expenseTxs.filter { tx in
            (tx.linkedContractId.map { loanIds.contains($0) } ?? false) ||
            (tx.seriesGroupId.map { loanIds.contains($0) } ?? false)
        }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }

        let loanInstallments: Double
        if loanTxSum > 0.001 {
            loanInstallments = loanTxSum
        } else {
            loanInstallments = openLoans.reduce(0.0) { sum, loan in
                let rem = remainingInstallmentsCount(for: loan, asOf: endOfPeriod)
                guard rem > 0 else { return sum }
                let countInPeriod = isAnnual ? min(rem, 12) : 1
                return sum + (Double(countInPeriod) * loan.installmentAmount)
            }
        }

        // 3. Acordos e Dívidas no Período
        let debtInstallments = expenseTxs.filter { tx in
            (tx.linkedDebtId != nil) ||
            (tx.transactionOrigin == .debtPayment) ||
            (tx.linkedContractId.map { debtIds.contains($0) } ?? false)
        }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }

        let totalDebtService = financingInstallments + loanInstallments + debtInstallments

        // 4. Custo de Vida / Despesas Operacionais (exclusivas, sem duplicidade com parcelas de crédito/dívidas)
        let nonDebtExpenseTxs = expenseTxs.filter { tx in
            let isFin = (tx.linkedContractId.map { financingIds.contains($0) } ?? false) ||
                        (tx.seriesGroupId.map { financingIds.contains($0) } ?? false)
            let isLoan = (tx.linkedContractId.map { loanIds.contains($0) } ?? false) ||
                         (tx.seriesGroupId.map { loanIds.contains($0) } ?? false)
            let isDebt = (tx.linkedDebtId != nil) ||
                         (tx.transactionOrigin == .debtPayment) ||
                         (tx.linkedContractId.map { debtIds.contains($0) } ?? false)
            return !isFin && !isLoan && !isDebt
        }
        let operationalTxsSum = nonDebtExpenseTxs.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        let operationalExpenses = max(operationalTxsSum, max(0.0, totalExpense - (finTxSum + loanTxSum + debtInstallments)))

        // 5. Total de Saídas & Margens
        let totalOutflows = operationalExpenses + totalDebtService
        let freeMargin = max(0.0, income - totalOutflows)
        let deficit = max(0.0, totalOutflows - income)

        let dtiRatio = income > 0 ? (totalDebtService / income) * 100.0 : 0.0
        let commitmentRatio = income > 0 ? (totalOutflows / income) * 100.0 : (totalOutflows > 0 ? 100.0 : 0.0)

        let cal = Calendar.current
        let yearNumber = cal.component(.year, from: referenceDate)

        return PeriodDebtServiceBreakdown(
            financingInstallments: financingInstallments,
            loanInstallments: loanInstallments,
            debtInstallments: debtInstallments,
            operationalExpenses: operationalExpenses,
            totalDebtService: totalDebtService,
            totalOutflows: totalOutflows,
            periodIncome: income,
            freeMargin: freeMargin,
            deficit: deficit,
            debtToIncomeRatio: dtiRatio,
            totalCommitmentRatio: commitmentRatio,
            isAnnual: isAnnual,
            yearStr: String(yearNumber)
        )
    }

    // MARK: - Centralized Unified Financial KPI Engine

    /// Constrói e retorna o sumário analítico financeiro unificado (KPIs) para o período e granularidade especificados.
    /// Esta é a ÚNICA FONTE DE VERDADE para os cards analíticos das 4 telas:
    /// Dashboard, Transações, Despesas e Receitas.
    public func buildUnifiedFinancialKPISummary(
        referenceDate: Date,
        isAnnual: Bool,
        referenceNow: Date? = nil
    ) -> UnifiedFinancialKPISummary {
        let now = referenceNow ?? effectiveCurrentDate
        let nowYear = calendar.component(.year, from: now)
        let nowMonth = calendar.component(.month, from: now)
        let refYear = calendar.component(.year, from: referenceDate)
        let refMonth = calendar.component(.month, from: referenceDate)

        let cacheKey: Int? = {
            guard referenceNow == nil else { return nil }
            return isAnnual ? (1_000_000 + refYear) : (refYear * 100 + refMonth)
        }()
        if let key = cacheKey, let cached = cachedKPISummaryByKey[key] {
            return cached
        }

        // 1. Identificação estrita do contexto temporal (6 modalidades)
        let temporalContext: FinancialTemporalContext = {
            if isAnnual {
                if refYear < nowYear { return .pastYear }
                if refYear == nowYear { return .currentYear }
                return .futureYear
            } else {
                if refYear < nowYear || (refYear == nowYear && refMonth < nowMonth) {
                    return .pastMonth
                } else if refYear == nowYear && refMonth == nowMonth {
                    return .currentMonth
                } else {
                    return .futureMonth
                }
            }
        }()

        let isClosed = temporalContext.isClosed

        // 2. Extração de transações do período
        let rawPeriodTxs = isAnnual ? transactionsForYear(referenceDate) : transactionsForMonth(referenceDate)
        // Filtra apenas transações ativas consolidadas (ignora transferências internas e canceladas)
        let periodTxs = rawPeriodTxs.filter { tx in
            !tx.ignoreInConsolidated &&
            tx.transactionOrigin != .internalTransfer &&
            tx.isCanceledRecurringSeries != true
        }

        let incomeTxs = periodTxs.filter { $0.type == .income }
        let expenseTxs = periodTxs.filter { $0.type == .expense }

        // 3. Receitas: Recebidas, Pendentes (no prazo vs em atraso), Extraordinárias vs Habituais
        let receivedIncome = incomeTxs.filter(\.isPaid).reduce(0.0) { $0 + $1.amount }
        let pendingIncomeTxs = incomeTxs.filter { !$0.isPaid }
        let pendingIncome = pendingIncomeTxs.reduce(0.0) { $0 + $1.amount }

        let todayStart = calendar.startOfDay(for: now)
        let pendingIncomeOverdue = pendingIncomeTxs.filter { calendar.startOfDay(for: $0.date) < todayStart }.reduce(0.0) { $0 + $1.amount }
        let pendingIncomeOnTime = pendingIncomeTxs.filter { calendar.startOfDay(for: $0.date) >= todayStart }.reduce(0.0) { $0 + $1.amount }

        // Receitas esperadas sem lançamento cadastrado (atualmente 0,00 documentado formalmente como limitação de modelo)
        let unrecordedExpectedIncome = 0.0

        let projectedIncome: Double = {
            if isClosed {
                // Período fechado: considera estritamente o histórico realizado
                return receivedIncome
            } else if temporalContext == .currentYear {
                // Ano em andamento: consolida realizados dos meses passados + (realizados + pendentes) do mês atual e futuros
                var sum = 0.0
                for m in 1...12 {
                    if let mDate = calendar.date(from: DateComponents(year: refYear, month: m, day: 1)) {
                        if m < nowMonth {
                            sum += monthlyIncome(for: mDate, onlyPaid: true)
                        } else {
                            sum += monthlyIncome(for: mDate, onlyPaid: false)
                        }
                    }
                }
                return sum + unrecordedExpectedIncome
            } else {
                return receivedIncome + pendingIncome + unrecordedExpectedIncome
            }
        }()

        let habitualIncome = incomeTxs.filter { !$0.isExtraordinaryIncome && (isClosed ? $0.isPaid : true) }.reduce(0.0) { $0 + $1.amount }
        let extraordinaryIncome = incomeTxs.filter { $0.isExtraordinaryIncome && (isClosed ? $0.isPaid : true) }.reduce(0.0) { $0 + $1.amount }

        // Principal fonte de receita
        var incomeByCategory: [UUID: Double] = [:]
        for tx in incomeTxs where (isClosed ? tx.isPaid : true) {
            incomeByCategory[tx.categoryId, default: 0.0] += tx.amount
        }
        let topCategoryEntry = incomeByCategory.max(by: { $0.value < $1.value })
        let topIncomeSourceName = topCategoryEntry.flatMap { category(for: $0.key)?.name }
        let topIncomeSourceAmount = topCategoryEntry?.value ?? 0.0
        let effectiveIncomeForRatio = isClosed ? receivedIncome : (receivedIncome + pendingIncome)
        let topIncomeSourcePercentage = effectiveIncomeForRatio > 0 ? (topIncomeSourceAmount / effectiveIncomeForRatio) * 100.0 : 0.0

        // 4. Despesas: Pagas, Pendentes (no prazo vs vencidas em atraso), Fixas vs Variáveis
        let paidExpense = expenseTxs.filter(\.isPaid).reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        let pendingExpenseTxs = expenseTxs.filter { !$0.isPaid }
        let pendingExpense = pendingExpenseTxs.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }

        let overdueExpenses = pendingExpenseTxs.filter { calendar.startOfDay(for: $0.date) < todayStart }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        let onTimePendingExpenses = pendingExpenseTxs.filter { calendar.startOfDay(for: $0.date) >= todayStart }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }

        let recordedExpense: Double = {
            if isClosed {
                return paidExpense
            } else if temporalContext == .currentYear {
                var sum = 0.0
                for m in 1...12 {
                    if let mDate = calendar.date(from: DateComponents(year: refYear, month: m, day: 1)) {
                        if m < nowMonth {
                            sum += monthlyExpense(for: mDate, onlyPaid: true)
                        } else {
                            sum += monthlyExpense(for: mDate, onlyPaid: false)
                        }
                    }
                }
                return sum
            } else {
                return paidExpense + pendingExpense
            }
        }()

        let fixedExpenses = expenseTxs.filter { $0.isFixedExpense && (isClosed ? $0.isPaid : true) }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        let variableExpenses = expenseTxs.filter { $0.isVariableExpense && (isClosed ? $0.isPaid : true) }.reduce(0.0) { $0 + effectiveTransactionAmount(for: $1) }
        let totalClassifiedExp = fixedExpenses + variableExpenses
        let fixedExpensesPercentage = totalClassifiedExp > 0 ? (fixedExpenses / totalClassifiedExp) * 100.0 : 0.0
        let variableExpensesPercentage = totalClassifiedExp > 0 ? (variableExpenses / totalClassifiedExp) * 100.0 : 0.0

        // 5. Orçamentos e Cotas Restantes & Excedentes
        let categoryCeilingsRemaining: Double
        let specificQuotasRemaining: Double
        let remainingBudgetsAndQuotas: Double
        let totalBudgetsOverrun: Double

        if isClosed {
            categoryCeilingsRemaining = 0.0
            specificQuotasRemaining = 0.0
            remainingBudgetsAndQuotas = 0.0
            totalBudgetsOverrun = provisionEnvelopes(for: referenceDate).reduce(0.0) { $0 + $1.exceededAmount }
        } else if isAnnual {
            if temporalContext == .currentYear {
                var catRem = 0.0
                var quotRem = 0.0
                var overrun = 0.0
                for m in nowMonth...12 {
                    if let mDate = calendar.date(from: DateComponents(year: refYear, month: m, day: 1)) {
                        catRem += totalCategoryProvisionsRemaining(for: mDate, referenceNow: now)
                        quotRem += totalQuotasRemaining(for: mDate)
                        overrun += provisionEnvelopes(for: mDate).reduce(0.0) { $0 + $1.exceededAmount }
                    }
                }
                categoryCeilingsRemaining = catRem
                specificQuotasRemaining = quotRem
                remainingBudgetsAndQuotas = catRem + quotRem
                totalBudgetsOverrun = overrun
            } else {
                // Ano futuro (12 meses projetados)
                var catRem = 0.0
                var quotRem = 0.0
                var overrun = 0.0
                for m in 1...12 {
                    if let mDate = calendar.date(from: DateComponents(year: refYear, month: m, day: 1)) {
                        catRem += totalCategoryProvisionsRemaining(for: mDate, referenceNow: now)
                        quotRem += totalQuotasRemaining(for: mDate)
                        overrun += provisionEnvelopes(for: mDate).reduce(0.0) { $0 + $1.exceededAmount }
                    }
                }
                categoryCeilingsRemaining = catRem
                specificQuotasRemaining = quotRem
                remainingBudgetsAndQuotas = catRem + quotRem
                totalBudgetsOverrun = overrun
            }
        } else {
            categoryCeilingsRemaining = totalCategoryProvisionsRemaining(for: referenceDate, referenceNow: now)
            specificQuotasRemaining = totalQuotasRemaining(for: referenceDate)
            remainingBudgetsAndQuotas = totalRemainingProvision(for: referenceDate, referenceNow: now)
            totalBudgetsOverrun = provisionEnvelopes(for: referenceDate).reduce(0.0) { $0 + $1.exceededAmount }
        }

        let hasBudgetOverrun = totalBudgetsOverrun > 0.001

        // 6. Gastos Planejados e Sobra Após Planejamento
        let totalPlannedExpenses = recordedExpense + remainingBudgetsAndQuotas
        let surplusAfterPlanning = projectedIncome - totalPlannedExpenses
        let operationalNetBalance = projectedIncome - recordedExpense

        // 7. Saldo Bancário em Contas e Saldo se Utilizar Todo o Orçamento
        let currentAccountBalanceNow = totalCheckingBalanceNow

        let cutoffDate: Date = isAnnual ? endOfYear(for: referenceDate) : endOfMonth(for: referenceDate)
        let initialAccountsSum = accounts.reduce(0.0) { $0 + $1.initialBalance }
        let transactionsDelta = transactions
            .filter { tx in
                guard !tx.ignoreInConsolidated else { return false }
                guard tx.date <= cutoffDate else { return false }
                return isClosed ? tx.isPaid : true
            }
            .reduce(0.0) { $0 + effectiveSignedTransactionAmount(for: $1) }
        let consolidatedInvestmentsSum = investments
            .filter(\.showInConsolidated)
            .reduce(0.0) { $0 + $1.balance }

        let projectedAccountBalance = initialAccountsSum + transactionsDelta + consolidatedInvestmentsSum
        let balanceIfAllBudgetsConsumed = isClosed
            ? projectedAccountBalance
            : (projectedAccountBalance - (isAnnual ? remainingBudgetsAndQuotas : accumulatedRemainingProvisions(throughMonth: referenceDate, referenceNow: now)))

        let projectedAccountBalanceTitle: String = {
            if isAnnual {
                return isClosed
                    ? "Resultado Consolidado"
                    : "Saldo Previsto para 31/12/\(BRLFormatters.yearString(referenceDate))"
            } else {
                return isClosed
                    ? "Saldo Final Realizado"
                    : monthEndBalanceCardTitle(for: referenceDate)
            }
        }()

        // 8. Estatísticas Operacionais da Tela de Transações
        let consolidatedEntries: Double = isClosed ? receivedIncome : (receivedIncome + pendingIncome)
        let consolidatedExits: Double = isClosed ? paidExpense : (paidExpense + pendingExpense)
        let transactionsNetBalance = consolidatedEntries - consolidatedExits
        let totalPendingVolume = pendingIncome + pendingExpense
        let paidTransactionsCount = periodTxs.filter(\.isPaid).count
        let pendingTransactionsCount = periodTxs.filter { !$0.isPaid }.count
        let validTransactionsCount = periodTxs.count

        let summary = UnifiedFinancialKPISummary(
            referenceDate: referenceDate,
            referenceNow: now,
            isAnnual: isAnnual,
            temporalContext: temporalContext,
            receivedIncome: receivedIncome,
            pendingIncome: pendingIncome,
            pendingIncomeOverdue: pendingIncomeOverdue,
            pendingIncomeOnTime: pendingIncomeOnTime,
            unrecordedExpectedIncome: unrecordedExpectedIncome,
            projectedIncome: projectedIncome,
            habitualIncome: habitualIncome,
            extraordinaryIncome: extraordinaryIncome,
            topIncomeSourceName: topIncomeSourceName,
            topIncomeSourceAmount: topIncomeSourceAmount,
            topIncomeSourcePercentage: topIncomeSourcePercentage,
            paidExpense: paidExpense,
            pendingExpense: pendingExpense,
            recordedExpense: recordedExpense,
            overdueExpenses: overdueExpenses,
            onTimePendingExpenses: onTimePendingExpenses,
            fixedExpenses: fixedExpenses,
            fixedExpensesPercentage: fixedExpensesPercentage,
            variableExpenses: variableExpenses,
            variableExpensesPercentage: variableExpensesPercentage,
            categoryCeilingsRemaining: categoryCeilingsRemaining,
            specificQuotasRemaining: specificQuotasRemaining,
            remainingBudgetsAndQuotas: remainingBudgetsAndQuotas,
            totalBudgetsOverrun: totalBudgetsOverrun,
            hasBudgetOverrun: hasBudgetOverrun,
            totalPlannedExpenses: totalPlannedExpenses,
            surplusAfterPlanning: surplusAfterPlanning,
            operationalNetBalance: operationalNetBalance,
            currentAccountBalanceNow: currentAccountBalanceNow,
            projectedAccountBalance: projectedAccountBalance,
            balanceIfAllBudgetsConsumed: balanceIfAllBudgetsConsumed,
            projectedAccountBalanceTitle: projectedAccountBalanceTitle,
            consolidatedEntries: consolidatedEntries,
            consolidatedExits: consolidatedExits,
            transactionsNetBalance: transactionsNetBalance,
            totalPendingVolume: totalPendingVolume,
            paidTransactionsCount: paidTransactionsCount,
            pendingTransactionsCount: pendingTransactionsCount,
            validTransactionsCount: validTransactionsCount
        )
        if let key = cacheKey {
            cachedKPISummaryByKey[key] = summary
        }
        return summary
    }
}
