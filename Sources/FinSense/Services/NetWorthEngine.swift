import Foundation

public struct NetWorthClassSlice: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let amountBRL: Double
    public let percentage: Double
    public let colorHex: String
    public let isLiquid: Bool
}

public struct AssetEquitySummary: Identifiable, Hashable, Sendable {
    public var id: UUID { asset.id }
    public let asset: AssetItem
    public let marketValueBRL: Double
    public let linkedDebtBRL: Double
    public let equityBRL: Double
}

public struct IncomeProfileSummary: Hashable, Sendable {
    public let fixedMonthlyNetBRL: Double
    public let variableAnnualEquivMonthlyBRL: Double
    public let passiveMonthlyNetBRL: Double
    public let totalMonthlyExpectedIncomeBRL: Double
    public let estimatedSavingsRatePercent: Double
}

public struct NetWorthOverviewSummary: Hashable, Sendable {
    public let liquidAssetsBRL: Double
    public let investmentsBRL: Double
    public let realEstateGrossBRL: Double
    public let vehiclesGrossBRL: Double
    public let fgtsAndOtherBRL: Double
    public let totalAssetsBRL: Double

    public let loansAndFinancingsDebtBRL: Double
    public let creditCardOpenInvoicesBRL: Double
    public let openDebtsBRL: Double
    public let totalLiabilitiesBRL: Double

    public let netWorthBRL: Double
    public let immediateLiquidityRatioPercent: Double
    public let immobilizedAssetsBRL: Double

    public let assetSlices: [NetWorthClassSlice]
    public let assetEquities: [AssetEquitySummary]
    public let incomeSummary: IncomeProfileSummary
}

/// Motor puro para cálculo consolidado de Patrimônio Líquido (Net Worth), Equity Imobiliário/Veicular
/// e Taxa de Poupança a partir das Fontes de Renda.
public enum NetWorthEngine {
    @MainActor
    public static func calculateOverview(
        store: FinancialDataStore,
        fxRateProvider: ((String) -> Double)? = nil
    ) -> NetWorthOverviewSummary {
        let rateFor: (String) -> Double = fxRateProvider ?? { ExchangeRateService.shared.rateToBRL(for: $0) }
        let now = store.effectiveCurrentDate

        // 1. Liquidez em contas bancárias (convertida para BRL)
        let liquidAssetsBRL = store.accounts.reduce(0.0) { accSum, acc in
            let nativeBalance = store.currentBalance(forAccount: acc.id)
            return accSum + nativeBalance * rateFor(acc.currencyCode)
        }

        // 2. Total de Investimentos (convertido para BRL — Net Worth inclui investimentos consolidados e reservados)
        let investmentsBRL = store.investments.reduce(0.0) { invSum, inv in
            invSum + inv.balance * rateFor(inv.currencyCode)
        }

        // 3. Bens Não-Bancários (Imóveis, Veículos, FGTS, Previdência, Outros)
        var realEstateGrossBRL = 0.0
        var vehiclesGrossBRL = 0.0
        var fgtsAndOtherBRL = 0.0
        var equities: [AssetEquitySummary] = []

        for asset in store.assets {
            let marketBRL = asset.currentMarketValue * rateFor(asset.currencyCode)
            switch asset.assetClass {
            case .realEstate:
                realEstateGrossBRL += marketBRL
            case .vehicle:
                vehiclesGrossBRL += marketBRL
            case .fgts, .privatePension, .equity, .other:
                fgtsAndOtherBRL += marketBRL
            }

            let linkedDebtBRL: Double = {
                guard let cid = asset.linkedFinancingContractId,
                      let contract = store.contracts.first(where: { $0.id == cid }),
                      !contract.isSettled else {
                    return 0.0
                }
                return max(0.0, store.currentOutstandingBalance(for: contract))
            }()

            equities.append(
                AssetEquitySummary(
                    asset: asset,
                    marketValueBRL: marketBRL,
                    linkedDebtBRL: linkedDebtBRL,
                    equityBRL: marketBRL - linkedDebtBRL
                )
            )
        }

        let totalAssetsBRL = liquidAssetsBRL + investmentsBRL + realEstateGrossBRL + vehiclesGrossBRL + fgtsAndOtherBRL

        // 4. Passivos (Empréstimos/Financiamentos + Faturas de Cartão não pagas + Dívidas em aberto)
        let loansAndFinancingsDebtBRL = store.contracts
            .filter { !$0.isSettled }
            .reduce(0.0) { $0 + max(0.0, store.currentOutstandingBalance(for: $1)) }

        let creditCardOpenInvoicesBRL = store.creditCards.reduce(0.0) { sum, card in
            sum + max(0.0, store.usedLimit(for: card.id))
        }

        let openDebtsBRL = store.debts
            .filter { !$0.isPaid }
            .reduce(0.0) { $0 + max(0.0, $1.originalAmount) }

        let totalLiabilitiesBRL = loansAndFinancingsDebtBRL + creditCardOpenInvoicesBRL + openDebtsBRL
        let netWorthBRL = totalAssetsBRL - totalLiabilitiesBRL

        let immobilizedAssetsBRL = realEstateGrossBRL + vehiclesGrossBRL
        let immediateLiquidityRatioPercent = totalAssetsBRL > 0.01 ? (liquidAssetsBRL / totalAssetsBRL) * 100.0 : 0.0

        let sliceCandidates: [(String, Double, String, Bool)] = [
            ("Liquidez (Contas)", max(0.0, liquidAssetsBRL), "#10B981", true),
            ("Investimentos", max(0.0, investmentsBRL), "#3B82F6", true),
            ("Imóveis", max(0.0, realEstateGrossBRL), "#6366F1", false),
            ("Veículos", max(0.0, vehiclesGrossBRL), "#0EA5E9", false),
            ("FGTS & Outros", max(0.0, fgtsAndOtherBRL), "#8B5CF6", false)
        ]
        let sliceTotal = sliceCandidates.reduce(0.0) { $0 + $1.1 }
        let assetSlices = sliceCandidates
            .filter { $0.1 > 0.001 }
            .map { item in
                NetWorthClassSlice(
                    label: item.0,
                    amountBRL: item.1,
                    percentage: sliceTotal > 0 ? (item.1 / sliceTotal) * 100.0 : 0.0,
                    colorHex: item.2,
                    isLiquid: item.3
                )
            }

        // 5. Fontes de Renda & Taxa de Poupança (Savings Rate)
        let fixedMonthlyNet = store.incomeSources
            .filter { $0.isActive && $0.kind == .fixedSalary }
            .reduce(0.0) { $0 + $1.monthlyEquivalentNetAmount * rateFor($1.currencyCode) }
        let variableMonthlyNet = store.incomeSources
            .filter { $0.isActive && $0.kind == .variableSeasonal }
            .reduce(0.0) { $0 + $1.monthlyEquivalentNetAmount * rateFor($1.currencyCode) }
        let passiveMonthlyNet = store.incomeSources
            .filter { $0.isActive && $0.kind == .passiveIncome }
            .reduce(0.0) { $0 + $1.monthlyEquivalentNetAmount * rateFor($1.currencyCode) }

        let totalExpectedIncome = fixedMonthlyNet + variableMonthlyNet + passiveMonthlyNet
        let fallbackMonthlyIncome = totalExpectedIncome > 0 ? totalExpectedIncome : store.monthlyIncome(for: now)
        let currentMonthExp = store.monthlyExpense(for: now)
        let savingsRate = fallbackMonthlyIncome > 0.01
            ? max(-100.0, min(100.0, ((fallbackMonthlyIncome - currentMonthExp) / fallbackMonthlyIncome) * 100.0))
            : 0.0

        return NetWorthOverviewSummary(
            liquidAssetsBRL: liquidAssetsBRL,
            investmentsBRL: investmentsBRL,
            realEstateGrossBRL: realEstateGrossBRL,
            vehiclesGrossBRL: vehiclesGrossBRL,
            fgtsAndOtherBRL: fgtsAndOtherBRL,
            totalAssetsBRL: totalAssetsBRL,
            loansAndFinancingsDebtBRL: loansAndFinancingsDebtBRL,
            creditCardOpenInvoicesBRL: creditCardOpenInvoicesBRL,
            openDebtsBRL: openDebtsBRL,
            totalLiabilitiesBRL: totalLiabilitiesBRL,
            netWorthBRL: netWorthBRL,
            immediateLiquidityRatioPercent: immediateLiquidityRatioPercent,
            immobilizedAssetsBRL: immobilizedAssetsBRL,
            assetSlices: assetSlices,
            assetEquities: equities,
            incomeSummary: IncomeProfileSummary(
                fixedMonthlyNetBRL: fixedMonthlyNet,
                variableAnnualEquivMonthlyBRL: variableMonthlyNet,
                passiveMonthlyNetBRL: passiveMonthlyNet,
                totalMonthlyExpectedIncomeBRL: totalExpectedIncome,
                estimatedSavingsRatePercent: savingsRate
            )
        )
    }

    @MainActor
    public static func buildCurrentMonthSnapshot(
        store: FinancialDataStore,
        referenceDate: Date? = nil,
        fxRateProvider: ((String) -> Double)? = nil
    ) -> NetWorthSnapshot {
        let overview = calculateOverview(store: store, fxRateProvider: fxRateProvider)
        let ref = referenceDate ?? store.effectiveCurrentDate
        let comps = Calendar.current.dateComponents([.year, .month], from: ref)
        let ymKey = (comps.year ?? 2026) * 100 + (comps.month ?? 1)
        return NetWorthSnapshot(
            yearMonthKey: ymKey,
            snapshotDate: ref,
            liquidAssetsBRL: overview.liquidAssetsBRL,
            investmentsAssetsBRL: overview.investmentsBRL,
            realEstateAssetsBRL: overview.realEstateGrossBRL,
            vehicleAssetsBRL: overview.vehiclesGrossBRL,
            fgtsAndOtherAssetsBRL: overview.fgtsAndOtherBRL,
            totalAssetsBRL: overview.totalAssetsBRL,
            loansAndFinancingsLiabilitiesBRL: overview.loansAndFinancingsDebtBRL,
            creditCardsLiabilitiesBRL: overview.creditCardOpenInvoicesBRL,
            debtsLiabilitiesBRL: overview.openDebtsBRL,
            totalLiabilitiesBRL: overview.totalLiabilitiesBRL,
            netWorthBRL: overview.netWorthBRL
        )
    }
}
