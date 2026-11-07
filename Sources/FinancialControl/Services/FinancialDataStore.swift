import Foundation
import SwiftUI

// MARK: - Persistent Snapshot

public struct FinancialDatabaseSnapshot: Codable {
    public var schemaVersion: Int?
    public var accounts: [BankAccount]
    public var categories: [CategoryItem]
    public var transactions: [FinancialTransaction]
    public var investments: [InvestmentItem]
    public var debts: [DebtItem]
    public var contracts: [CreditContract]
    public var provisions: [CategoryProvision]?
    public var categoryQuotas: [CategoryQuotaRule]?
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
        provisions: [CategoryProvision]? = [],
        categoryQuotas: [CategoryQuotaRule]? = [],
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
        self.provisions = provisions
        self.categoryQuotas = categoryQuotas
        self.llmConfig = llmConfig
        self.chatHistory = chatHistory
        self.hasSeededInitialStatement = hasSeededInitialStatement
    }
}

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
    public let financingsRemainingNominalTotal: Double
    public let financingsProjectedPayoffTotal: Double

    public let grandTotalNominal: Double
    public let grandTotalWithPayoffProjection: Double
    public let itemizedLines: [DebtLineItem]
}

// MARK: - FinancialDataStore

@MainActor
public final class FinancialDataStore: ObservableObject {
    @Published public var accounts: [BankAccount] = []
    @Published public var categories: [CategoryItem] = []
    @Published public var transactions: [FinancialTransaction] = []
    @Published public var investments: [InvestmentItem] = []
    @Published public var debts: [DebtItem] = []
    @Published public var contracts: [CreditContract] = []
    @Published public var provisions: [CategoryProvision] = []
    @Published public var categoryQuotas: [CategoryQuotaRule] = []
    @Published public var llmConfig: LLMConfiguration = LLMConfiguration()
    @Published public var chatHistory: [ChatMessage] = []
    @Published public var selectedMonth: Date = Date()
    @Published public var selectedDestination: SidebarDestination = .dashboard
    @Published public var selectedTransactionsSubmenu: TransactionsSubmenu = .all
    @Published public var dashboardPeriodMode: DashboardPeriodMode = .monthly
    @Published public var selectedSettingsSection: SettingsSection = .general
    @Published public var isAIChatPresented: Bool = false
    @Published public var isLLMInstallAlertPresented: Bool = false
    @Published public var pendingAIFeatureName: String = ""

    public let persistenceEnvironment: PersistenceEnvironment
    public let storageDirectory: URL
    public let databaseFileURL: URL
    public let attachmentsDirectoryURL: URL
    public let modelsDirectoryURL: URL
    private let legacyReleaseDatabaseFileURL: URL?

    private var hasSeededInitialStatement: Bool = false
    private let calendar: Calendar = {
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
                // Produção (Release): mantém exatamente ~/Library/Application Support/FinancialControl/financial_database.json
                let prodDir = appSupport.appendingPathComponent("FinancialControl", isDirectory: true)
                self.storageDirectory = prodDir
                self.databaseFileURL = prodDir.appendingPathComponent("financial_database.json")
                self.legacyReleaseDatabaseFileURL = prodDir.appendingPathComponent("database.json")
            case .debug:
                // Desenvolvimento (Debug): diretório e arquivo 100% isolados, sem tocar no banco de produção
                let debugDir = appSupport.appendingPathComponent("FinancialControl-Debug", isDirectory: true)
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
            self.provisions = decoded.provisions ?? []
            self.categoryQuotas = decoded.categoryQuotas ?? []
            self.llmConfig = decoded.llmConfig
            self.chatHistory = decoded.chatHistory
            self.hasSeededInitialStatement = decoded.hasSeededInitialStatement
        } else {
            // Instalação limpa: sempre inicia zerado, apenas com as categorias padrões, sem despesas ou contas.
            self.categories = DefaultCategoriesCatalog.buildInitialCategories()
            self.accounts = []
            self.transactions = []
            self.investments = []
            self.debts = []
            self.contracts = []
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
    }

    public func updateAccount(_ account: BankAccount) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
            save()
        }
    }

    public func deleteAccount(_ accountId: UUID) {
        accounts.removeAll(where: { $0.id == accountId })
        save()
    }

    public func account(for id: UUID) -> BankAccount? {
        accounts.first(where: { $0.id == id })
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
        categories.first(where: { $0.id == id })
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
    }

    public func updateCategory(_ category: CategoryItem) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            save()
        }
    }

    public func deleteCategory(_ categoryId: UUID) {
        categories.removeAll(where: { $0.id == categoryId })
        provisions.removeAll(where: { $0.categoryId == categoryId })
        categoryQuotas.removeAll(where: { $0.categoryId == categoryId })
        save()
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
        return created
    }

    /// Garante que contas/recebimentos recorrentes ativos tenham ocorrências geradas até a data-limite consultada (ao navegar para meses ou anos futuros)
    public func ensureRecurringTransactionsMaterialized(upTo targetDate: Date) {
        let recurringTxs = transactions.filter { $0.recurrenceMode == .recurring && $0.seriesGroupId != nil }
        guard !recurringTxs.isEmpty else { return }

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
        }
        save()
    }

    /// Atualiza uma transação única ou aplica a edição em lote conforme o `SeriesEditScope`
    /// (`.onlyThis`: somente naquela transação; `.thisAndFuture`: da transação atual e todas no futuro; `.allInSeries`: em todas as parcelas/ocorrências)
    public func updateTransaction(
        _ updated: FinancialTransaction,
        scope: SeriesEditScope = .onlyThis,
        referenceNow: Date = Date()
    ) {
        guard let targetIdx = transactions.firstIndex(where: { $0.id == updated.id }) else { return }
        let originalBeforeEdit = transactions[targetIdx]

        var cleanUpdated = updated
        cleanUpdated.amount = abs(updated.amount)
        if cleanUpdated.isPaid && isDateInFuture(cleanUpdated.date, referenceNow: referenceNow) {
            cleanUpdated.date = referenceNow
        }

        let baseCleanName = Self.stripInstallmentSuffix(from: cleanUpdated.name)
        transactions[targetIdx] = cleanUpdated

        if scope != .onlyThis, let groupId = cleanUpdated.seriesGroupId {
            let referenceDate = calendar.startOfDay(for: originalBeforeEdit.date)
            let referenceInstallmentIdx = originalBeforeEdit.installmentIndex

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
                    transactions[idx].amount = cleanUpdated.amount
                    transactions[idx].categoryId = cleanUpdated.categoryId
                    transactions[idx].accountId = cleanUpdated.accountId
                    transactions[idx].ignoreInConsolidated = cleanUpdated.ignoreInConsolidated
                    transactions[idx].details = cleanUpdated.details
                    if transactions[idx].recurrenceMode == .installment,
                       let instIdx = transactions[idx].installmentIndex,
                       let instTotal = transactions[idx].installmentTotal {
                        transactions[idx].name = "\(baseCleanName) (\(instIdx)/\(instTotal))"
                    } else {
                        transactions[idx].name = baseCleanName
                    }
                    if isDateInFuture(transactions[idx].date, referenceNow: referenceNow) {
                        transactions[idx].isPaid = false
                    }
                }
            }
        }

        sortTransactions()
        save()
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
    public func toggleTransactionPaid(_ id: UUID, referenceNow: Date = Date()) -> Bool {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return false }
        if !transactions[idx].isPaid {
            // Pagando: se a data estiver no futuro, move para a data atual
            if isDateInFuture(transactions[idx].date, referenceNow: referenceNow) {
                transactions[idx].date = referenceNow
            }
            transactions[idx].isPaid = true
        } else {
            // Desfazendo pagamento
            transactions[idx].isPaid = false
        }
        sortTransactions()
        save()
        return true
    }

    public func toggleTransactionIgnoreInConsolidated(_ id: UUID) {
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx].ignoreInConsolidated.toggle()
            save()
        }
    }

    public func deleteTransaction(_ id: UUID, scope: SeriesDeleteScope = .onlyThis) {
        guard let targetTx = transactions.first(where: { $0.id == id }) else { return }

        if scope == .onlyThis || !targetTx.isPartOfSeries || targetTx.seriesGroupId == nil {
            transactions.removeAll(where: { $0.id == id })
            save()
            return
        }

        guard let groupId = targetTx.seriesGroupId else {
            transactions.removeAll(where: { $0.id == id })
            save()
            return
        }

        switch scope {
        case .onlyThis:
            transactions.removeAll(where: { $0.id == id })

        case .allInSeries:
            transactions.removeAll(where: { $0.seriesGroupId == groupId })

        case .thisAndPending:
            let referenceDate = calendar.startOfDay(for: targetTx.date)
            let referenceInstallmentIdx = targetTx.installmentIndex

            transactions.removeAll { tx in
                guard tx.seriesGroupId == groupId else { return false }
                if tx.id == targetTx.id { return true }
                guard !tx.isPaid else { return false }

                if let refInst = referenceInstallmentIdx, let otherInst = tx.installmentIndex {
                    return otherInst >= refInst
                } else {
                    return calendar.startOfDay(for: tx.date) >= referenceDate
                }
            }

            // Se for uma série recorrente contínua, encerra a geração futura para que não recrie as pendentes removidas
            if targetTx.recurrenceMode == .recurring {
                for idx in transactions.indices where transactions[idx].seriesGroupId == groupId {
                    transactions[idx].isCanceledRecurringSeries = true
                }
            }
        }

        save()
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
    }

    public func toggleInvestmentConsolidated(_ investmentId: UUID) {
        if let idx = investments.firstIndex(where: { $0.id == investmentId }) {
            investments[idx].showInConsolidated.toggle()
            save()
        }
    }

    public func deleteInvestment(_ investmentId: UUID) {
        investments.removeAll(where: { $0.id == investmentId })
        save()
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

        let txType: TransactionType = movementType == .deposit ? .expense : .income
        let categoryId: UUID = {
            if movementType == .deposit {
                return fallbackCategoryId(for: .expense, matchingSubstring: "Aplicações")
            } else {
                return fallbackCategoryId(for: .income, matchingSubstring: "Resgate")
            }
        }()

        let txTitle = movementType == .deposit
            ? "Aporte: \(investmentName) (\(groupName))"
            : "Resgate: \(investmentName) (\(groupName))"
        let txDetails = movementType == .deposit
            ? "Saída de \(sourceAccountName) para investimento em \(destAccountName). \(notes)"
            : "Resgate de \(destAccountName) para \(sourceAccountName). \(notes)"

        let tx = FinancialTransaction(
            name: txTitle,
            details: txDetails.trimmingCharacters(in: .whitespaces),
            amount: cleanAmount,
            date: date,
            type: txType,
            isPaid: true,
            categoryId: categoryId,
            accountId: sourceAccountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedInvestmentId: investmentId
        )
        transactions.append(tx)

        if movementType == .deposit {
            investments[idx].balance += cleanAmount
        } else {
            investments[idx].balance = max(0, investments[idx].balance - cleanAmount)
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
    }

    public func updateDebt(_ updated: DebtItem) {
        if let idx = debts.firstIndex(where: { $0.id == updated.id }) {
            debts[idx] = updated
            save()
        }
    }

    public func deleteDebt(_ debtId: UUID) {
        debts.removeAll(where: { $0.id == debtId })
        save()
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
            linkedDebtId: debt.id
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

        // Data de início está no passado: contamos quantas datas de cobrança já passaram estritamente antes de `todayStart`
        var firstInstallmentComps = calendar.dateComponents([.year, .month], from: startDay)
        firstInstallmentComps.day = clampedDay
        var cursorDate = calendar.date(from: firstInstallmentComps) ?? startDay
        if cursorDate < startDay {
            cursorDate = calendar.date(byAdding: .month, value: 1, to: cursorDate) ?? cursorDate
        }

        var elapsed = 0
        while cursorDate < todayStart && elapsed < totalInstallments {
            elapsed += 1
            cursorDate = calendar.date(byAdding: .month, value: 1, to: cursorDate) ?? cursorDate
        }

        return (min(elapsed, totalInstallments), cursorDate)
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
        monthlyInterestRate: Double,
        startDate: Date?,
        accountId: UUID,
        notes: String = "",
        referenceDate: Date = Date(),
        overridePastInstallmentsCount: Int? = nil,
        overrideFirstFutureBillingDate: Date? = nil
    ) -> CreditContract {
        let creditCategoryId = fallbackCategoryId(for: .expense, matchingSubstring: "Empréstimos")

        let computedSchedule = computePastInstallmentsAndFirstFutureDate(
            startDate: startDate,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            referenceDate: referenceDate
        )
        let pastCount = min(max(overridePastInstallmentsCount ?? computedSchedule.pastInstallmentsCount, 0), totalInstallments)
        let firstFutureDate = overrideFirstFutureBillingDate ?? computedSchedule.firstFutureBillingDate

        let contract = CreditContract(
            kind: kind,
            name: name,
            contractNumber: contractNumber,
            loanSubtype: kind == .loan ? (loanSubtype ?? .consignado) : nil,
            financingSubtype: kind == .financing ? (financingSubtype ?? .imovel) : nil,
            amortizationSystem: amortizationSystem,
            totalContractedAmount: totalContractedAmount,
            outstandingBalance: outstandingBalance,
            installmentAmount: installmentAmount,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            monthlyInterestRate: monthlyInterestRate,
            startDate: startDate,
            accountId: accountId,
            categoryId: creditCategoryId,
            pastInstallmentsElapsedAtCreation: pastCount,
            notes: notes
        )
        contracts.append(contract)

        // Gera APENAS as transações futuras a partir da data atual e dia da cobrança
        let remainingToCreate = max(totalInstallments - pastCount, 0)
        for offset in 0..<remainingToCreate {
            let installmentNumber = pastCount + offset + 1
            let dueDate = calendar.date(byAdding: .month, value: offset, to: firstFutureDate)
                ?? firstFutureDate
            let tx = FinancialTransaction(
                name: "\(name) - Parcela \(installmentNumber)/\(totalInstallments)",
                details: "\(contract.kind.title) (\(contract.subtypeDisplayName)) • Juros \(String(format: "%.2f", monthlyInterestRate))% a.m.",
                amount: installmentAmount,
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
                linkedContractId: contract.id
            )
            transactions.append(tx)
        }

        sortTransactions()
        save()
        return contract
    }

    /// Retorna o Saldo Devedor atual do contrato (informado/extraído do documento menos amortizações extras, ou calculado a valor presente)
    public func currentOutstandingBalance(for contract: CreditContract) -> Double {
        guard !contract.isSettled else { return 0.0 }
        if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
            let paidInApp = transactions.filter { $0.linkedContractId == contract.id && $0.isPaid && $0.installmentIndex != nil }.count
            let estimatedPrincipalPerInstallment = explicitBalance / Double(max(contract.totalInstallments - contract.pastInstallmentsElapsedAtCreation, 1))
            let reducedByPaidInstallments = Double(paidInApp) * estimatedPrincipalPerInstallment
            return max(explicitBalance - contract.extraAmortizedTotal - reducedByPaidInstallments, 0.0)
        }
        return projectedPayoffAmount(for: contract)
    }

    public func unpaidTransactions(forContract contractId: UUID) -> [FinancialTransaction] {
        transactions
            .filter { $0.linkedContractId == contractId && !$0.isPaid }
            .sorted { $0.date < $1.date }
    }

    public func paidTransactionsCount(forContract contract: CreditContract) -> Int {
        let paidInApp = transactions.filter { $0.linkedContractId == contract.id && $0.isPaid && $0.installmentIndex != nil }.count
        return min(contract.pastInstallmentsElapsedAtCreation + paidInApp, contract.totalInstallments)
    }

    public func remainingInstallmentsCount(for contract: CreditContract) -> Int {
        guard !contract.isSettled else { return 0 }
        let unpaid = unpaidTransactions(forContract: contract.id).count
        if unpaid > 0 { return unpaid }
        return max(contract.totalInstallments - paidTransactionsCount(forContract: contract), 0)
    }

    public func remainingNominalAmount(for contract: CreditContract) -> Double {
        guard !contract.isSettled else { return 0 }
        let unpaidTxs = unpaidTransactions(forContract: contract.id)
        if !unpaidTxs.isEmpty {
            return unpaidTxs.reduce(0) { $0 + $1.amount }
        }
        return Double(remainingInstallmentsCount(for: contract)) * contract.installmentAmount
    }

    /// Calcula a "Projeção de valor para quitar" trazendo as parcelas futuras a valor presente (desconto proporcional de juros futuros)
    /// considerando o Saldo Devedor atual (quando informado/importado), a taxa de juros do contrato, o sistema de amortização (PRICE ou SAC) e o tipo do contrato.
    public func projectedPayoffAmount(for contract: CreditContract) -> Double {
        guard !contract.isSettled else { return 0.0 }
        let n = remainingInstallmentsCount(for: contract)
        guard n > 0 else { return 0.0 }

        let nominalRemaining = remainingNominalAmount(for: contract)
        let pmt = nominalRemaining / Double(max(n, 1))
        let i = contract.monthlyInterestRate / 100.0

        // Se o contrato possui Saldo Devedor explícito (ex: extraído do demonstrativo/evolução bancária)
        // que já representa o principal a valor presente (D0, livre de juros futuros e seguros mensais),
        // a projeção para quitação imediata é o próprio Saldo Devedor atualizado, nunca superior a ele.
        if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
            let currentBal = currentOutstandingBalance(for: contract)
            if currentBal < nominalRemaining - 0.01 {
                return max(currentBal, 0.0)
            }
        }

        guard i > 0.0001 else {
            if let explicitBalance = contract.outstandingBalance, explicitBalance > 0 {
                return max(min(currentOutstandingBalance(for: contract), nominalRemaining), 0.0)
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
            return max(min(calculatedPayoff, currentOutstandingBalance(for: contract)), 0.0)
        }
        return calculatedPayoff
    }

    /// Amortizar empréstimo/financiamento: registra pagamento na conta escolhida e recalcula parcelas futuras
    public func amortizeContract(
        contractId: UUID,
        amountPaid: Double,
        accountId: UUID,
        date: Date = Date(),
        mode: AmortizationRecalculationMode,
        customNewInstallmentAmount: Double? = nil,
        customNewRemainingInstallments: Int? = nil,
        notes: String = ""
    ) {
        guard let idx = contracts.firstIndex(where: { $0.id == contractId }) else { return }
        var contract = contracts[idx]
        let cleanPaid = abs(amountPaid)
        guard cleanPaid > 0 else { return }

        let prevRemaining = remainingInstallmentsCount(for: contract)
        let prevInstallment = contract.installmentAmount
        let currentPV = max(projectedPayoffAmount(for: contract), cleanPaid)
        let newPV = max(currentPV - cleanPaid, 0)
        let i = contract.monthlyInterestRate / 100.0

        var newInstallment = prevInstallment
        var newRemaining = prevRemaining

        if newPV <= 0.01 {
            newRemaining = 0
            newInstallment = 0
        } else {
            switch mode {
            case .reduceTerm:
                if let customCount = customNewRemainingInstallments, customCount > 0 {
                    newRemaining = min(customCount, prevRemaining)
                } else if i > 0.0001 && prevInstallment > newPV * i {
                    // n = -ln(1 - (PV * i) / PMT) / ln(1 + i)
                    let ratio = 1.0 - (newPV * i) / prevInstallment
                    let calcN = Int(ceil(-log(max(ratio, 0.0001)) / log(1.0 + i)))
                    newRemaining = max(1, min(calcN, prevRemaining))
                } else {
                    newRemaining = max(1, Int(ceil(newPV / max(prevInstallment, 1))))
                }
                if let customInst = customNewInstallmentAmount, customInst > 0 {
                    newInstallment = customInst
                }
            case .reduceInstallment:
                if let customInst = customNewInstallmentAmount, customInst > 0 {
                    newInstallment = customInst
                } else if i > 0.0001 && prevRemaining > 0 {
                    // PMT = PV * i / (1 - (1 + i)^(-n))
                    newInstallment = newPV * i / (1.0 - pow(1.0 + i, -Double(prevRemaining)))
                } else if prevRemaining > 0 {
                    newInstallment = newPV / Double(prevRemaining)
                }
                if let customCount = customNewRemainingInstallments, customCount > 0 {
                    newRemaining = customCount
                }
            }
        }

        // Cria transação de saída na conta selecionada
        let amortTx = FinancialTransaction(
            name: "Amortização: \(contract.name)",
            details: "Amortização extraordinária (\(mode.rawValue)). \(notes)".trimmingCharacters(in: .whitespaces),
            amount: cleanPaid,
            date: date,
            type: .expense,
            isPaid: true,
            categoryId: contract.categoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedContractId: contract.id
        )
        transactions.append(amortTx)

        // Atualiza as parcelas futuras em aberto
        let unpaidList = unpaidTransactions(forContract: contract.id)
        if newRemaining == 0 {
            let idsToRemove = Set(unpaidList.map(\.id))
            transactions.removeAll { idsToRemove.contains($0.id) }
            contract.isSettled = true
            contract.settledAmount = cleanPaid
            contract.settledDate = date
            contract.settledAccountId = accountId
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
        }

        contract.extraAmortizedTotal += cleanPaid
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
            notes: notes
        )
        contract.amortizationHistory.insert(record, at: 0)
        contracts[idx] = contract

        sortTransactions()
        save()
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
        let cleanFinal = abs(finalPayoffAmount)
        let originalProjected = projectedPayoffAmount(for: contract)
        let nominalRemaining = remainingNominalAmount(for: contract)

        // Remove todas as parcelas futuras ainda não pagas
        let unpaidIds = Set(unpaidTransactions(forContract: contract.id).map(\.id))
        transactions.removeAll { unpaidIds.contains($0.id) }

        // Cria a transação de quitação na conta selecionada
        let settleTx = FinancialTransaction(
            name: "Quitação: \(contract.name)",
            details: "Quitação integral de \(contract.kind.title.lowercased()) (Saldo nominal: \(BRLFormatters.currency(nominalRemaining)), Projetado: \(BRLFormatters.currency(originalProjected)))",
            amount: cleanFinal,
            date: date,
            type: .expense,
            isPaid: true,
            categoryId: contract.categoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedContractId: contract.id
        )
        transactions.append(settleTx)

        contract.isSettled = true
        contract.settledAmount = cleanFinal
        contract.settledDate = date
        contract.settledAccountId = accountId
        contracts[idx] = contract

        sortTransactions()
        save()
    }

    public func deleteContract(_ contractId: UUID) {
        transactions.removeAll { $0.linkedContractId == contractId || $0.seriesGroupId == contractId }
        contracts.removeAll { $0.id == contractId }
        save()
    }

    // MARK: - Balances, Monthly Summaries & Insights

    public func transactionsForMonth(_ monthReference: Date) -> [FinancialTransaction] {
        transactions
            .filter { isInMonth($0.date, monthReference: monthReference) }
            .sorted { a, b in
                if a.date == b.date { return a.createdAt > b.createdAt }
                return a.date > b.date
            }
    }

    public func monthlyIncome(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthlyReceivedIncome(for monthReference: Date) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: true)
    }

    public func monthlyPendingIncome(for monthReference: Date) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && !$0.isPaid }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthlyExpense(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthlyPaidExpense(for monthReference: Date) -> Double {
        monthlyExpense(for: monthReference, onlyPaid: true)
    }

    public func monthlyPendingExpense(for monthReference: Date) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && !$0.isPaid }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthlyNetBalance(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: onlyPaid) - monthlyExpense(for: monthReference, onlyPaid: onlyPaid)
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
    }

    /// Exclui a Verba Livre de uma categoria respeitando o escopo temporal:
    /// - `.onlyThisMonth`: remove apenas do mês corrente (a regra recorrente continua nos meses anteriores e reaparece nos futuros).
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
            provisions.removeAll { $0.categoryId == categoryId }
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
                } else if provisions[idx].yearMonthKey == targetKey {
                    provisions.remove(at: idx)
                }
            }
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
    /// com suporte a escopo temporal (`.onlyThisMonth` vs `.thisAndFutureMonths`).
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
        editScope: ProvisionEditScope = .thisAndFutureMonths
    ) -> CategoryQuotaRule {
        let year = calendar.component(.year, from: monthReference)
        let month = calendar.component(.month, from: monthReference)
        let targetKey = year * 100 + month
        let cleanQty = max(1, plannedQuantity)
        let cleanPrice = max(0.0, estimatedUnitPrice)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = trimmedName.isEmpty ? "Item Provisionado" : trimmedName
        let resolvedIcon = iconSymbol ?? Self.defaultIconForQuotaName(cleanName)

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
                    return categoryQuotas[idx]
                }
            }

            // Escopo: .thisAndFutureMonths
            categoryQuotas.removeAll { $0.seriesId == existingSeriesId && $0.yearMonthKey > targetKey }
            for idx in categoryQuotas.indices where categoryQuotas[idx].seriesId == existingSeriesId {
                if var overrides = categoryQuotas[idx].monthlyOverrides {
                    overrides = overrides.filter { $0.key < targetKey }
                    categoryQuotas[idx].monthlyOverrides = overrides.isEmpty ? nil : overrides
                }
                if var excluded = categoryQuotas[idx].excludedYearMonthKeys {
                    excluded = excluded.filter { $0 < targetKey }
                    categoryQuotas[idx].excludedYearMonthKeys = excluded.isEmpty ? nil : excluded
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
                save()
                return categoryQuotas[exactIdx]
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
                    repeatForFutureMonths: repeatForFutureMonths
                )
                categoryQuotas.append(updatedFutureRule)
                save()
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
            repeatForFutureMonths: repeatForFutureMonths
        )
        categoryQuotas.append(newRule)
        save()
        return newRule
    }

    /// Exclui uma Cota de Item Específico respeitando o escopo temporal:
    /// - `.onlyThisMonth`: remove do mês corrente; continua nos meses anteriores e reaparece nos futuros.
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
            categoryQuotas.removeAll { $0.seriesId == seriesId }
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
                } else if categoryQuotas[idx].yearMonthKey == targetKey {
                    categoryQuotas.remove(at: idx)
                }
            }
        }

        save()
    }

    /// Retorna os envelopes de Cotas Específicas ativas para uma categoria no mês informado.
    public func quotaEnvelopes(
        forCategory categoryId: UUID,
        in monthReference: Date
    ) -> [CategoryQuotaEnvelope] {
        let targetYear = calendar.component(.year, from: monthReference)
        let targetMonth = calendar.component(.month, from: monthReference)
        let targetKey = targetYear * 100 + targetMonth

        let rulesForCat = categoryQuotas.filter { $0.categoryId == categoryId }
        guard !rulesForCat.isEmpty else { return [] }

        let groupedBySeries = Dictionary(grouping: rulesForCat, by: \.seriesId)
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
                guard tx.linkedQuotaId == seriesId else { return false }
                if let quotaMonthKey = tx.linkedQuotaYearMonthKey {
                    return quotaMonthKey == targetKey
                }
                return isInMonth(tx.date, monthReference: monthReference)
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

    /// Lista todas as cotas específicas ativas em todas as categorias de despesa no mês informado.
    public func allQuotaEnvelopes(for monthReference: Date) -> [CategoryQuotaEnvelope] {
        expenseCategories.flatMap { cat in
            quotaEnvelopes(forCategory: cat.id, in: monthReference)
        }
    }

    /// Dá baixa em uma Cota Específica (ex: "+ Registrar Compra" / "Dar Baixa"),
    /// incrementando as unidades consumidas e inserindo automaticamente a transação real no extrato
    /// sem abater da Verba Livre da categoria.
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

        guard let catId = activeEnvelope?.categoryId ?? fallbackRule?.categoryId else {
            return nil
        }

        let quotaName = activeEnvelope?.name ?? fallbackRule?.name ?? "Item de Cota"
        let defaultUnitPrice = activeEnvelope?.estimatedUnitPrice ?? fallbackRule?.estimatedUnitPrice ?? 0.0
        let cleanUnits = max(1, units)
        let actualUnitPrice = max(0.0, unitPriceOverride ?? defaultUnitPrice)
        let totalAmount = Double(cleanUnits) * actualUnitPrice

        // Se a data da transação pertence ao mês de referência (ou se monthReference não foi fixado em outro mês),
        // usa a data atual (`transactionDate`); caso contrário, alinha ao mês de referência para manter consistência no extrato mensal.
        let effectiveDate: Date = {
            if isInMonth(transactionDate, monthReference: targetMonth) {
                return transactionDate
            } else if monthReference == nil {
                return transactionDate
            } else {
                return targetMonth
            }
        }()

        let txTitle = cleanUnits > 1 ? "\(quotaName) (\(cleanUnits) un.)" : quotaName
        let txDetails = details.isEmpty
            ? "Baixa de cota específica: \(cleanUnits) un. × \(BRLFormatters.currency(actualUnitPrice))"
            : details

        let tx = FinancialTransaction(
            name: txTitle,
            details: txDetails,
            amount: totalAmount,
            date: effectiveDate,
            type: .expense,
            isPaid: true,
            categoryId: catId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedQuotaId: seriesId,
            linkedQuotaUnits: cleanUnits,
            linkedQuotaYearMonthKey: targetKey
        )
        transactions.append(tx)
        save()
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

    /// Envelope calculado para uma categoria específica no mês de referência,
    /// coexistindo Verba Livre + Cotas de Itens Específicos.
    public func provisionEnvelope(
        forCategory categoryId: UUID,
        in monthReference: Date
    ) -> CategoryProvisionEnvelope? {
        guard let cat = category(for: categoryId), cat.type == .expense else { return nil }
        let freeDetails = effectiveProvisionDetails(forCategory: categoryId, in: monthReference)
        let activeQuotas = quotaEnvelopes(forCategory: categoryId, in: monthReference)

        if freeDetails == nil && activeQuotas.isEmpty {
            return nil
        }

        let year = calendar.component(.year, from: monthReference)
        let month = calendar.component(.month, from: monthReference)
        let resolvedProvision = freeDetails?.provision ?? CategoryProvision(
            categoryId: categoryId,
            year: year,
            month: month,
            estimatedAmount: 0.0,
            repeatForFutureMonths: activeQuotas.first?.repeatForFutureMonths ?? true
        )

        let freeRealized = realizedFreeBudgetExpense(forCategory: categoryId, in: monthReference)

        return CategoryProvisionEnvelope(
            category: cat,
            provision: resolvedProvision,
            isInheritedFromPreviousMonth: freeDetails?.isInherited ?? (activeQuotas.first?.isInheritedFromPreviousMonth ?? false),
            estimatedAmount: resolvedProvision.estimatedAmount,
            realizedExpense: freeRealized,
            quotaEnvelopes: activeQuotas,
            isFreeBudgetLocalOverride: freeDetails?.isLocalOverride ?? false
        )
    }

    /// Lista todos os envelopes de provisão ativos no mês de referência.
    public func provisionEnvelopes(for monthReference: Date) -> [CategoryProvisionEnvelope] {
        expenseCategories.compactMap { cat in
            provisionEnvelope(forCategory: cat.id, in: monthReference)
        }
        .sorted { a, b in
            if a.rawProgressPercentage == b.rawProgressPercentage {
                return a.estimatedAmount > b.estimatedAmount
            }
            return a.rawProgressPercentage > b.rawProgressPercentage
        }
    }

    /// Soma total dos tetos estimados ($\sum T_{estimado}$) configurados para o mês (Verba Livre + Cotas).
    public func totalEstimatedProvision(for monthReference: Date) -> Double {
        provisionEnvelopes(for: monthReference)
            .reduce(0.0) { $0 + $1.estimatedAmount }
    }

    /// Soma total do saldo estimado remanescente ($\sum P_{restante}$) no mês (Verba Livre restante + Cotas restantes).
    public func totalRemainingProvision(for monthReference: Date) -> Double {
        provisionEnvelopes(for: monthReference)
            .reduce(0.0) { $0 + $1.remainingProvision }
    }

    /// Despesa total projetada do mês considerando despesas reais + provisões variáveis remanescentes ($\sum P_{restante}$).
    public func projectedMonthlyExpense(for monthReference: Date) -> Double {
        monthlyExpense(for: monthReference, onlyPaid: false) + totalRemainingProvision(for: monthReference)
    }

    /// Resultado líquido projetado do mês considerando receitas - despesas reais - provisões remanescentes.
    public func projectedMonthlyNetBalance(for monthReference: Date) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: false) - projectedMonthlyExpense(for: monthReference)
    }

    // MARK: - Annual Summaries & End-of-Year Projections (31/12)

    public func transactionsForYear(_ yearReference: Date) -> [FinancialTransaction] {
        transactions
            .filter { isInYear($0.date, yearReference: yearReference) }
            .sorted { a, b in
                if a.date == b.date { return a.createdAt > b.createdAt }
                return a.date > b.date
            }
    }

    public func annualIncome(for yearReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForYear(yearReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + $1.amount }
    }

    public func annualExpense(for yearReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForYear(yearReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + $1.amount }
    }

    public func annualNetBalance(for yearReference: Date, onlyPaid: Bool = false) -> Double {
        annualIncome(for: yearReference, onlyPaid: onlyPaid) - annualExpense(for: yearReference, onlyPaid: onlyPaid)
    }

    /// Saldo acumulado consolidado projetado até o último dia do ano (31/12 do ano de `yearReference`)
    public func accumulatedConsolidatedBalanceThroughYear(_ yearReference: Date, includeProjectedUnpaid: Bool = true) -> Double {
        let cutoff = endOfYear(for: yearReference)
        let initialAccountsSum = accounts.reduce(0.0) { $0 + $1.initialBalance }
        let transactionsDelta = transactions
            .filter { tx in
                guard !tx.ignoreInConsolidated else { return false }
                guard tx.date <= cutoff else { return false }
                return includeProjectedUnpaid ? true : tx.isPaid
            }
            .reduce(0.0) { $0 + $1.signedAmount }

        let consolidatedInvestmentsSum = investments
            .filter(\.showInConsolidated)
            .reduce(0.0) { $0 + $1.balance }

        return initialAccountsSum + transactionsDelta + consolidatedInvestmentsSum
    }

    public func annualCategoryBreakdown(for yearReference: Date, type: TransactionType) -> [CategorySpendSummary] {
        let yearTxs = transactionsForYear(yearReference)
            .filter { $0.type == type && !$0.ignoreInConsolidated }
        let grandTotal = yearTxs.reduce(0.0) { $0 + $1.amount }
        guard grandTotal > 0 else { return [] }

        var grouped: [UUID: (sum: Double, count: Int)] = [:]
        for tx in yearTxs {
            let current = grouped[tx.categoryId] ?? (0.0, 0)
            grouped[tx.categoryId] = (current.sum + tx.amount, current.count + 1)
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
                points.append(
                    MonthlyCashFlowPoint(
                        monthDate: mDate,
                        label: BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized,
                        income: inc,
                        expense: exp,
                        net: inc - exp,
                        accumulatedBalance: acc
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
    /// menos a provisão de gastos variáveis remanescentes ($\sum P_{restante}$) quando `includeProjectedUnpaid == true`.
    public func accumulatedConsolidatedBalance(throughMonth monthReference: Date, includeProjectedUnpaid: Bool = true) -> Double {
        let cutoff = endOfMonth(for: monthReference)
        let initialAccountsSum = accounts.reduce(0.0) { $0 + $1.initialBalance }
        let transactionsDelta = transactions
            .filter { tx in
                guard !tx.ignoreInConsolidated else { return false }
                guard tx.date <= cutoff else { return false }
                return includeProjectedUnpaid ? true : tx.isPaid
            }
            .reduce(0.0) { $0 + $1.signedAmount }

        let consolidatedInvestmentsSum = investments
            .filter(\.showInConsolidated)
            .reduce(0.0) { $0 + $1.balance }

        let remainingProvisions = includeProjectedUnpaid ? totalRemainingProvision(for: monthReference) : 0.0

        return initialAccountsSum + transactionsDelta + consolidatedInvestmentsSum - remainingProvisions
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
        let grandTotal = monthTxs.reduce(0.0) { $0 + $1.amount }
        guard grandTotal > 0 else { return [] }

        var grouped: [UUID: (sum: Double, count: Int)] = [:]
        for tx in monthTxs {
            let current = grouped[tx.categoryId] ?? (0.0, 0)
            grouped[tx.categoryId] = (current.sum + tx.amount, current.count + 1)
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
                points.append(
                    MonthlyCashFlowPoint(
                        monthDate: mDate,
                        label: BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized,
                        income: inc,
                        expense: exp,
                        net: inc - exp,
                        accumulatedBalance: acc
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

        let loansNominalSum = openLoans.reduce(0.0) { $0 + remainingNominalAmount(for: $1) }
        let loansProjectedSum = openLoans.reduce(0.0) { $0 + projectedPayoffAmount(for: $1) }

        let financingsNominalSum = openFinancings.reduce(0.0) { $0 + remainingNominalAmount(for: $1) }
        let financingsProjectedSum = openFinancings.reduce(0.0) { $0 + projectedPayoffAmount(for: $1) }

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
            let remCount = remainingInstallmentsCount(for: loan)
            let nom = remainingNominalAmount(for: loan)
            let proj = projectedPayoffAmount(for: loan)
            items.append(
                DebtLineItem(
                    id: loan.id,
                    title: "\(loan.name) (\(loan.subtypeDisplayName))",
                    subtitle: "\(remCount)x restantes de \(BRLFormatters.currency(loan.installmentAmount)) • Juros \(String(format: "%.2f", loan.monthlyInterestRate))% a.m.",
                    section: "Empréstimos",
                    nominalAmount: nom,
                    projectedPayoffAmount: proj,
                    iconSymbol: loan.iconSymbol,
                    colorHex: "#D97706"
                )
            )
        }

        for fin in openFinancings {
            let remCount = remainingInstallmentsCount(for: fin)
            let nom = remainingNominalAmount(for: fin)
            let proj = projectedPayoffAmount(for: fin)
            items.append(
                DebtLineItem(
                    id: fin.id,
                    title: "\(fin.name) (\(fin.subtypeDisplayName))",
                    subtitle: "\(remCount)x restantes de \(BRLFormatters.currency(fin.installmentAmount)) • Juros \(String(format: "%.2f", fin.monthlyInterestRate))% a.m.",
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
            financingsRemainingNominalTotal: financingsNominalSum,
            financingsProjectedPayoffTotal: financingsProjectedSum,
            grandTotalNominal: grandNominal,
            grandTotalWithPayoffProjection: grandProjected,
            itemizedLines: items
        )
    }
}
