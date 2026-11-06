import Foundation
import SwiftUI

// MARK: - Navigation

public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case transactions
    case investments
    case loans
    case financings
    case debts
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .transactions: return "Transações"
        case .investments: return "Investimentos"
        case .loans: return "Empréstimos"
        case .financings: return "Financiamentos"
        case .debts: return "Dívidas"
        case .settings: return "Configurações"
        }
    }

    public var subtitle: String {
        switch self {
        case .dashboard: return "Insights, gráficos e visão consolidada"
        case .transactions: return "Receitas e despesas por mês"
        case .investments: return "Carteiras, aportes e resgates"
        case .loans: return "Consignados, pessoais e amortização"
        case .financings: return "Financiamentos de imóvel e carro"
        case .debts: return "Controle e negociação de dívidas em aberto"
        case .settings: return "LLM local, contas e categorias"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .transactions: return "arrow.left.arrow.right.circle.fill"
        case .investments: return "chart.line.uptrend.xyaxis.circle.fill"
        case .loans: return "banknote.fill"
        case .financings: return "house.and.flag.fill"
        case .debts: return "exclamationmark.shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general = "general"
    case llm = "llm"
    case accounts = "accounts"
    case categories = "categories"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "Gerais"
        case .llm: return "Configuração da LLM"
        case .accounts: return "Contas"
        case .categories: return "Categorias"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .llm: return "cpu.fill"
        case .accounts: return "building.columns.fill"
        case .categories: return "square.grid.2x2.fill"
        }
    }
}

public enum ResetDataTarget: String, CaseIterable, Identifiable, Hashable {
    case transactions
    case accounts
    case categories
    case investments
    case loans
    case financings
    case debts
    case aiModelsAndChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .transactions: return "Transações (Despesas e Receitas)"
        case .accounts: return "Contas Bancárias"
        case .categories: return "Categorias"
        case .investments: return "Investimentos"
        case .loans: return "Empréstimos"
        case .financings: return "Financiamentos"
        case .debts: return "Dívidas"
        case .aiModelsAndChat: return "Modelos Locais e Histórico da IA"
        }
    }

    public var subtitle: String {
        switch self {
        case .transactions: return "Remove todos os lançamentos passados, atuais e futuros"
        case .accounts: return "Remove todas as contas cadastradas"
        case .categories: return "Remove as categorias atuais da base"
        case .investments: return "Remove todos os grupos e saldos de investimentos"
        case .loans: return "Remove todos os contratos de empréstimos"
        case .financings: return "Remove todos os financiamentos de imóvel e carro"
        case .debts: return "Remove todos os cards de dívidas abertas e quitadas"
        case .aiModelsAndChat: return "Remove modelos baixados e histórico de conversas do chat"
        }
    }

    public var icon: String {
        switch self {
        case .transactions: return "arrow.left.arrow.right.circle.fill"
        case .accounts: return "building.columns.fill"
        case .categories: return "square.grid.2x2.fill"
        case .investments: return "chart.line.uptrend.xyaxis.circle.fill"
        case .loans: return "banknote.fill"
        case .financings: return "house.and.flag.fill"
        case .debts: return "exclamationmark.shield.fill"
        case .aiModelsAndChat: return "cpu.fill"
        }
    }
}

// MARK: - Transaction Types & Recurrence

public enum TransactionType: String, Codable, CaseIterable, Identifiable, Hashable {
    case expense
    case income

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: return "Despesa"
        case .income: return "Receita"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .expense: return "Despesas"
        case .income: return "Receitas"
        }
    }
}

public enum TransactionRecurrenceMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case single
    case installment
    case repeated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single: return "Única"
        case .installment: return "Parcelada"
        case .repeated: return "Repetida (Mensal)"
        }
    }
}

public enum StatementImportFilterMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case hybrid
    case expensesOnly
    case incomesOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hybrid: return "Híbrido (Receitas e Despesas)"
        case .expensesOnly: return "Apenas Despesas"
        case .incomesOnly: return "Apenas Receitas"
        }
    }
}

// MARK: - Bank Account & Presets

public struct BankPreset: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let shortCode: String
    public let monogram: String
    public let primaryHex: String
    public let secondaryHex: String
    public let symbolName: String

    public init(
        id: String,
        name: String,
        shortCode: String,
        monogram: String,
        primaryHex: String,
        secondaryHex: String,
        symbolName: String
    ) {
        self.id = id
        self.name = name
        self.shortCode = shortCode
        self.monogram = monogram
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.symbolName = symbolName
    }
}

public struct BankAccount: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var bankPresetId: String?
    public var customImagePath: String?
    public var iconSymbol: String
    public var colorHex: String
    public var initialBalance: Double
    public var agency: String
    public var accountNumber: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        bankPresetId: String? = nil,
        customImagePath: String? = nil,
        iconSymbol: String = "building.columns.fill",
        colorHex: String = "#EC7000",
        initialBalance: Double = 0.0,
        agency: String = "",
        accountNumber: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bankPresetId = bankPresetId
        self.customImagePath = customImagePath
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.initialBalance = initialBalance
        self.agency = agency
        self.accountNumber = accountNumber
        self.createdAt = createdAt
    }
}

// MARK: - Category

public struct CategoryItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var type: TransactionType
    public var iconSymbol: String
    public var colorHex: String
    public var keywords: [String]
    public var isSystemDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        type: TransactionType,
        iconSymbol: String,
        colorHex: String,
        keywords: [String] = [],
        isSystemDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.keywords = keywords
        self.isSystemDefault = isSystemDefault
    }
}

// MARK: - Financial Transaction

public struct FinancialTransaction: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var details: String
    public var amount: Double
    public var date: Date
    public var type: TransactionType
    public var isPaid: Bool
    public var categoryId: UUID
    public var accountId: UUID
    public var attachmentPath: String?
    public var attachmentName: String?
    public var ignoreInConsolidated: Bool
    public var recurrenceMode: TransactionRecurrenceMode
    public var seriesGroupId: UUID?
    public var installmentIndex: Int?
    public var installmentTotal: Int?
    public var rawStatementLine: String?
    public var statementOccurrenceIndex: Int
    public var linkedContractId: UUID?
    public var linkedInvestmentId: UUID?
    public var linkedDebtId: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
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
        seriesGroupId: UUID? = nil,
        installmentIndex: Int? = nil,
        installmentTotal: Int? = nil,
        rawStatementLine: String? = nil,
        statementOccurrenceIndex: Int = 1,
        linkedContractId: UUID? = nil,
        linkedInvestmentId: UUID? = nil,
        linkedDebtId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.amount = abs(amount)
        self.date = date
        self.type = type
        self.isPaid = isPaid
        self.categoryId = categoryId
        self.accountId = accountId
        self.attachmentPath = attachmentPath
        self.attachmentName = attachmentName
        self.ignoreInConsolidated = ignoreInConsolidated
        self.recurrenceMode = recurrenceMode
        self.seriesGroupId = seriesGroupId
        self.installmentIndex = installmentIndex
        self.installmentTotal = installmentTotal
        self.rawStatementLine = rawStatementLine
        self.statementOccurrenceIndex = statementOccurrenceIndex
        self.linkedContractId = linkedContractId
        self.linkedInvestmentId = linkedInvestmentId
        self.linkedDebtId = linkedDebtId
        self.createdAt = createdAt
    }

    public var signedAmount: Double {
        type == .income ? amount : -amount
    }

    public var installmentBadge: String? {
        if let idx = installmentIndex, let total = installmentTotal, total > 1 {
            return "\(idx)/\(total)"
        }
        return nil
    }
}

// MARK: - Investments

public enum InvestmentMovementType: String, Codable, CaseIterable, Identifiable, Hashable {
    case deposit
    case withdrawal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deposit: return "Aporte"
        case .withdrawal: return "Resgate"
        }
    }
}

public struct InvestmentMovement: Identifiable, Codable, Hashable {
    public var id: UUID
    public var type: InvestmentMovementType
    public var amount: Double
    public var date: Date
    public var sourceAccountId: UUID
    public var investmentAccountId: UUID
    public var notes: String
    public var generatedTransactionId: UUID?

    public init(
        id: UUID = UUID(),
        type: InvestmentMovementType = .deposit,
        amount: Double,
        date: Date = Date(),
        sourceAccountId: UUID,
        investmentAccountId: UUID,
        notes: String = "",
        generatedTransactionId: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = abs(amount)
        self.date = date
        self.sourceAccountId = sourceAccountId
        self.investmentAccountId = investmentAccountId
        self.notes = notes
        self.generatedTransactionId = generatedTransactionId
    }
}

public struct InvestmentItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var groupName: String
    public var investmentAccountId: UUID
    public var balance: Double
    public var showInConsolidated: Bool
    public var iconSymbol: String
    public var colorHex: String
    public var notes: String
    public var movements: [InvestmentMovement]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        groupName: String,
        investmentAccountId: UUID,
        balance: Double = 0.0,
        showInConsolidated: Bool = true,
        iconSymbol: String = "chart.line.uptrend.xyaxis",
        colorHex: String = "#10B981",
        notes: String = "",
        movements: [InvestmentMovement] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.investmentAccountId = investmentAccountId
        self.balance = balance
        self.showInConsolidated = showInConsolidated
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.notes = notes
        self.movements = movements
        self.createdAt = createdAt
    }
}

// MARK: - Debts (Dívidas em Aberto / Negociação)

public struct DebtItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var customImagePath: String?
    public var bankPresetId: String?
    public var iconSymbol: String
    public var colorHex: String
    public var originalAmount: Double
    public var contractedDate: Date?
    public var notes: String
    public var isPaid: Bool
    public var negotiatedAmount: Double?
    public var paidDate: Date?
    public var paidFromAccountId: UUID?
    public var paymentTransactionId: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        customImagePath: String? = nil,
        bankPresetId: String? = nil,
        iconSymbol: String = "creditcard.trianglebadge.exclamationmark",
        colorHex: String = "#EF4444",
        originalAmount: Double,
        contractedDate: Date? = nil,
        notes: String = "",
        isPaid: Bool = false,
        negotiatedAmount: Double? = nil,
        paidDate: Date? = nil,
        paidFromAccountId: UUID? = nil,
        paymentTransactionId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.customImagePath = customImagePath
        self.bankPresetId = bankPresetId
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.originalAmount = abs(originalAmount)
        self.contractedDate = contractedDate
        self.notes = notes
        self.isPaid = isPaid
        self.negotiatedAmount = negotiatedAmount
        self.paidDate = paidDate
        self.paidFromAccountId = paidFromAccountId
        self.paymentTransactionId = paymentTransactionId
        self.createdAt = createdAt
    }
}

// MARK: - Loans (Empréstimos) & Financings (Financiamentos)

public enum CreditContractKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case loan
    case financing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .loan: return "Empréstimo"
        case .financing: return "Financiamento"
        }
    }
}

public enum LoanSubtype: String, Codable, CaseIterable, Identifiable, Hashable {
    case consignado = "Consignado"
    case pessoal = "Pessoal"
    case fgts = "Antecipação FGTS"
    case empresarial = "Empresarial"
    case refinanciamento = "Refinanciamento"
    case outros = "Outros"

    public var id: String { rawValue }

    public var discountFactorMultiplier: Double {
        // Consignado e FGTS possuem taxas reguladas e desconto integral dos juros futuros (CDC Art. 52 §2º)
        switch self {
        case .consignado, .fgts:
            return 1.0
        case .pessoal, .refinanciamento:
            return 0.98
        case .empresarial, .outros:
            return 0.95
        }
    }
}

public enum FinancingSubtype: String, Codable, CaseIterable, Identifiable, Hashable {
    case imovel = "Imóvel"
    case carro = "Carro"

    public var id: String { rawValue }

    public var iconSymbol: String {
        switch self {
        case .imovel: return "house.fill"
        case .carro: return "car.fill"
        }
    }
}

public enum AmortizationSystem: String, Codable, CaseIterable, Identifiable, Hashable {
    case price = "PRICE (Parcelas Fixas)"
    case sac = "SAC (Amortização Constante)"

    public var id: String { rawValue }
}

public enum AmortizationRecalculationMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case reduceTerm = "Reduzir Prazo (Quantidade de Parcelas)"
    case reduceInstallment = "Reduzir Valor da Parcela"

    public var id: String { rawValue }
}

public struct AmortizationRecord: Identifiable, Codable, Hashable {
    public var id: UUID
    public var date: Date
    public var amountPaid: Double
    public var mode: AmortizationRecalculationMode
    public var previousInstallmentAmount: Double
    public var newInstallmentAmount: Double
    public var previousRemainingInstallments: Int
    public var newRemainingInstallments: Int
    public var accountId: UUID
    public var transactionId: UUID?
    public var notes: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        amountPaid: Double,
        mode: AmortizationRecalculationMode,
        previousInstallmentAmount: Double,
        newInstallmentAmount: Double,
        previousRemainingInstallments: Int,
        newRemainingInstallments: Int,
        accountId: UUID,
        transactionId: UUID? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.amountPaid = amountPaid
        self.mode = mode
        self.previousInstallmentAmount = previousInstallmentAmount
        self.newInstallmentAmount = newInstallmentAmount
        self.previousRemainingInstallments = previousRemainingInstallments
        self.newRemainingInstallments = newRemainingInstallments
        self.accountId = accountId
        self.transactionId = transactionId
        self.notes = notes
    }
}

public struct CreditContract: Identifiable, Codable, Hashable {
    public var id: UUID
    public var kind: CreditContractKind
    public var name: String
    public var contractNumber: String?
    public var loanSubtype: LoanSubtype?
    public var financingSubtype: FinancingSubtype?
    public var amortizationSystem: AmortizationSystem
    public var totalContractedAmount: Double
    public var outstandingBalance: Double?
    public var installmentAmount: Double
    public var billingDay: Int
    public var totalInstallments: Int
    public var monthlyInterestRate: Double // percentage, e.g., 1.65 means 1.65% a.m.
    public var startDate: Date?
    public var accountId: UUID
    public var categoryId: UUID
    public var pastInstallmentsElapsedAtCreation: Int
    public var extraAmortizedTotal: Double
    public var amortizationHistory: [AmortizationRecord]
    public var isSettled: Bool
    public var settledAmount: Double?
    public var settledDate: Date?
    public var settledAccountId: UUID?
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: CreditContractKind,
        name: String,
        contractNumber: String? = nil,
        loanSubtype: LoanSubtype? = .consignado,
        financingSubtype: FinancingSubtype? = nil,
        amortizationSystem: AmortizationSystem = .price,
        totalContractedAmount: Double,
        outstandingBalance: Double? = nil,
        installmentAmount: Double,
        billingDay: Int,
        totalInstallments: Int,
        monthlyInterestRate: Double,
        startDate: Date? = nil,
        accountId: UUID,
        categoryId: UUID,
        pastInstallmentsElapsedAtCreation: Int = 0,
        extraAmortizedTotal: Double = 0.0,
        amortizationHistory: [AmortizationRecord] = [],
        isSettled: Bool = false,
        settledAmount: Double? = nil,
        settledDate: Date? = nil,
        settledAccountId: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.contractNumber = contractNumber
        self.loanSubtype = loanSubtype
        self.financingSubtype = financingSubtype
        self.amortizationSystem = amortizationSystem
        self.totalContractedAmount = abs(totalContractedAmount)
        self.outstandingBalance = outstandingBalance.map { abs($0) }
        self.installmentAmount = abs(installmentAmount)
        self.billingDay = min(max(billingDay, 1), 31)
        self.totalInstallments = max(totalInstallments, 1)
        self.monthlyInterestRate = max(monthlyInterestRate, 0.0)
        self.startDate = startDate
        self.accountId = accountId
        self.categoryId = categoryId
        self.pastInstallmentsElapsedAtCreation = max(pastInstallmentsElapsedAtCreation, 0)
        self.extraAmortizedTotal = extraAmortizedTotal
        self.amortizationHistory = amortizationHistory
        self.isSettled = isSettled
        self.settledAmount = settledAmount
        self.settledDate = settledDate
        self.settledAccountId = settledAccountId
        self.notes = notes
        self.createdAt = createdAt
    }

    public var subtypeDisplayName: String {
        switch kind {
        case .loan:
            return loanSubtype?.rawValue ?? "Consignado"
        case .financing:
            return financingSubtype?.rawValue ?? "Imóvel"
        }
    }

    public var iconSymbol: String {
        switch kind {
        case .loan:
            switch loanSubtype ?? .consignado {
            case .consignado: return "person.badge.shield.checkmark.fill"
            case .pessoal: return "banknote.fill"
            case .fgts: return "building.2.crop.circle.fill"
            case .empresarial: return "briefcase.fill"
            case .refinanciamento: return "arrow.triangle.2.circlepath.circle.fill"
            case .outros: return "doc.text.fill"
            }
        case .financing:
            return (financingSubtype ?? .imovel).iconSymbol
        }
    }
}

// MARK: - Local LLM Configuration & Chat

public struct LocalLLMModelInfo: Identifiable, Codable, Hashable {
    public var id: String // e.g., "Qwen/Qwen2.5-3B-Instruct-GGUF"
    public var displayName: String
    public var fileName: String
    public var localPath: String
    public var sizeBytes: Int64
    public var downloadedAt: Date
    public var quantization: String

    public init(
        id: String,
        displayName: String,
        fileName: String,
        localPath: String,
        sizeBytes: Int64,
        downloadedAt: Date = Date(),
        quantization: String = "Q4_K_M / 4-bit"
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.downloadedAt = downloadedAt
        self.quantization = quantization
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct LLMConfiguration: Codable, Hashable {
    public var huggingFaceToken: String
    public var selectedModelId: String?
    public var downloadedModels: [LocalLLMModelInfo]
    public var localEndpointURL: String

    public init(
        huggingFaceToken: String = "",
        selectedModelId: String? = nil,
        downloadedModels: [LocalLLMModelInfo] = [],
        localEndpointURL: String = ""
    ) {
        self.huggingFaceToken = huggingFaceToken
        self.selectedModelId = selectedModelId
        self.downloadedModels = downloadedModels
        self.localEndpointURL = localEndpointURL
    }

    public var selectedModel: LocalLLMModelInfo? {
        guard let selectedModelId else { return downloadedModels.first }
        return downloadedModels.first(where: { $0.id == selectedModelId }) ?? downloadedModels.first
    }
}

public enum ChatMessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Codable, Hashable {
    public var id: UUID
    public var role: ChatMessageRole
    public var content: String
    public var timestamp: Date
    public var modelUsed: String?

    public init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        content: String,
        timestamp: Date = Date(),
        modelUsed: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelUsed = modelUsed
    }
}
