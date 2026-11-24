import Foundation

public struct FIREBaselineMetrics: Sendable {
    public let averageMonthlyCostOfLivingBRL: Double
    public let currentLiquidAndInvestedBRL: Double
    public let realEstateAndFGTSBRL: Double
    public let currentMonthlySurplusBRL: Double
    public let activeMonthlyDebtInstallmentsBRL: Double
    public let projectedPostDebtMonthlyContributionBRL: Double
    public let estimatedDebtPayoffYears: Double
}

public struct FIREYearlyProjectionPoint: Identifiable, Hashable, Sendable {
    public var id: Int { yearIndex }
    public let yearIndex: Int
    public let yearNumber: Int
    public let label: String
    public let baselinePatrimonyBRL: Double
    public let acceleratedPostDebtPatrimonyBRL: Double
    public let fireTargetBRL: Double
    public let monthlyPassiveIncomeBaselineBRL: Double
    public let monthlyPassiveIncomeAcceleratedBRL: Double
}

public struct FIRESimulationResult: Sendable {
    public let scenario: FIREPlanScenario
    public let annualRealReturnRate: Double
    public let fireTargetNumberBRL: Double
    public let yearsToFIREBaseline: Int?
    public let yearsToFIREPostDebt: Int?
    public let estimatedFIREDateBaseline: Date?
    public let estimatedFIREDatePostDebt: Date?
    public let yearsAcceleratedByDebtPayoff: Int
    public let projectionPoints: [FIREYearlyProjectionPoint]
}

/// Motor matemático somente-leitura para simulação de Independência Financeira (FIRE).
public enum FIRESimulatorEngine {
    /// Calcula taxa real anual usando equação de Fisher: `(1 + nominal) / (1 + inflacao) - 1`.
    public static func realAnnualReturn(nominalPercent: Double, inflationPercent: Double) -> Double {
        let nom = nominalPercent / 100.0
        let inf = inflationPercent / 100.0
        return ((1.0 + nom) / max(0.01, 1.0 + inf)) - 1.0
    }

    @MainActor
    public static func computeBaselineFromStore(
        store: FinancialDataStore,
        fxRateProvider: ((String) -> Double)? = nil
    ) -> FIREBaselineMetrics {
        let now = store.effectiveCurrentDate
        let cal = Calendar.current
        let overview = NetWorthEngine.calculateOverview(store: store, fxRateProvider: fxRateProvider)

        // Custo de vida real: média dos últimos 6 meses com transações de despesa (excluindo amortizações extraordinárias e transferências)
        var monthlyTotals: [Double] = []
        for offset in 0..<6 {
            guard let mDate = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let mTxs = store.transactionsForMonth(mDate).filter { tx in
                guard tx.type == .expense else { return false }
                guard !tx.ignoreInConsolidated else { return false }
                guard !tx.isCreditCardInvoicePayment else { return false }
                let orig = tx.effectiveOrigin
                guard orig != .internalTransfer &&
                      orig != .investmentDeposit &&
                      orig != .financingAmortization &&
                      orig != .loanAmortization &&
                      orig != .loanPayoff &&
                      orig != .contractSettlement else {
                    return false
                }
                return true
            }
            let sum = mTxs.reduce(0.0) { $0 + store.effectiveExpenseAmountForBudgetAndCharts(for: $1) }
            if sum > 0.01 {
                monthlyTotals.append(sum)
            }
        }
        let avgCostOfLiving = monthlyTotals.isEmpty
            ? 5000.0
            : (monthlyTotals.reduce(0.0, +) / Double(monthlyTotals.count))

        let monthlyExpectedIncome = overview.incomeSummary.totalMonthlyExpectedIncomeBRL > 0
            ? overview.incomeSummary.totalMonthlyExpectedIncomeBRL
            : max(avgCostOfLiving, store.monthlyIncome(for: now))

        let currentSurplus = max(0.0, monthlyExpectedIncome - avgCostOfLiving)

        let activeContracts = store.contracts.filter { !$0.isSettled }
        let monthlyDebtService = activeContracts.reduce(0.0) { $0 + max(0.0, $1.installmentAmount) }
        let maxRemainingMonths = activeContracts.reduce(0) { maxRem, contract in
            let remainingCount: Int
            if let proj = store.loanProjection(for: contract.id) {
                remainingCount = proj.projectedActiveMonths
            } else {
                remainingCount = max(0, contract.totalInstallments - contract.pastInstallmentsElapsedAtCreation)
            }
            return max(maxRem, remainingCount)
        }

        return FIREBaselineMetrics(
            averageMonthlyCostOfLivingBRL: avgCostOfLiving,
            currentLiquidAndInvestedBRL: max(0.0, overview.liquidAssetsBRL + overview.investmentsBRL),
            realEstateAndFGTSBRL: max(0.0, overview.realEstateGrossBRL + overview.fgtsAndOtherBRL),
            currentMonthlySurplusBRL: currentSurplus,
            activeMonthlyDebtInstallmentsBRL: monthlyDebtService,
            projectedPostDebtMonthlyContributionBRL: currentSurplus + monthlyDebtService,
            estimatedDebtPayoffYears: Double(maxRemainingMonths) / 12.0
        )
    }

    public static func simulate(
        scenario: FIREPlanScenario,
        additionalDebtFreedMonthlyContributionBRL: Double = 0.0,
        debtPayoffYearOffset: Int = 2,
        horizonYears: Int = 40,
        referenceDate: Date = Date()
    ) -> FIRESimulationResult {
        let cal = Calendar.current
        let baseYear = cal.component(.year, from: referenceDate)

        let realAnnualRate = realAnnualReturn(
            nominalPercent: scenario.expectedAnnualNominalReturnPercent,
            inflationPercent: scenario.expectedAnnualInflationPercent
        )
        let monthlyRealRate = pow(max(0.001, 1.0 + realAnnualRate), 1.0 / 12.0) - 1.0

        let swrRate = max(0.01, scenario.safeWithdrawalRatePercent / 100.0)
        let fireTarget = (scenario.monthlyCostOfLivingBRL * 12.0) / swrRate

        var patBase = max(0.0, scenario.currentInvestedPatrimonyBRL)
        var patAccel = patBase

        var yearsToBaseline: Int? = patBase >= fireTarget ? 0 : nil
        var yearsToPostDebt: Int? = patAccel >= fireTarget ? 0 : nil

        var points: [FIREYearlyProjectionPoint] = [
            FIREYearlyProjectionPoint(
                yearIndex: 0,
                yearNumber: baseYear,
                label: "\(baseYear)",
                baselinePatrimonyBRL: patBase,
                acceleratedPostDebtPatrimonyBRL: patAccel,
                fireTargetBRL: fireTarget,
                monthlyPassiveIncomeBaselineBRL: (patBase * swrRate) / 12.0,
                monthlyPassiveIncomeAcceleratedBRL: (patAccel * swrRate) / 12.0
            )
        ]

        let totalHorizon = max(5, min(60, horizonYears))
        let payoffMonthThreshold = max(0, debtPayoffYearOffset * 12)
        var totalMonthsElapsed = 0

        for yearOffset in 1...totalHorizon {
            for _ in 1...12 {
                totalMonthsElapsed += 1
                patBase = patBase * (1.0 + monthlyRealRate) + scenario.monthlyContributionBRL

                let accelContrib = totalMonthsElapsed > payoffMonthThreshold
                    ? (scenario.monthlyContributionBRL + max(0.0, additionalDebtFreedMonthlyContributionBRL))
                    : scenario.monthlyContributionBRL
                patAccel = patAccel * (1.0 + monthlyRealRate) + accelContrib
            }

            if yearsToBaseline == nil && patBase >= fireTarget {
                yearsToBaseline = yearOffset
            }
            if yearsToPostDebt == nil && patAccel >= fireTarget {
                yearsToPostDebt = yearOffset
            }

            let yNum = baseYear + yearOffset
            points.append(
                FIREYearlyProjectionPoint(
                    yearIndex: yearOffset,
                    yearNumber: yNum,
                    label: "\(yNum)",
                    baselinePatrimonyBRL: patBase,
                    acceleratedPostDebtPatrimonyBRL: patAccel,
                    fireTargetBRL: fireTarget,
                    monthlyPassiveIncomeBaselineBRL: (patBase * swrRate) / 12.0,
                    monthlyPassiveIncomeAcceleratedBRL: (patAccel * swrRate) / 12.0
                )
            )
        }

        let dateBaseline = yearsToBaseline.flatMap { cal.date(byAdding: .year, value: $0, to: referenceDate) }
        let dateAccel = yearsToPostDebt.flatMap { cal.date(byAdding: .year, value: $0, to: referenceDate) }
        let accelGain: Int = {
            if let baseY = yearsToBaseline, let accY = yearsToPostDebt {
                return max(0, baseY - accY)
            }
            return 0
        }()

        return FIRESimulationResult(
            scenario: scenario,
            annualRealReturnRate: realAnnualRate,
            fireTargetNumberBRL: fireTarget,
            yearsToFIREBaseline: yearsToBaseline,
            yearsToFIREPostDebt: yearsToPostDebt,
            estimatedFIREDateBaseline: dateBaseline,
            estimatedFIREDatePostDebt: dateAccel,
            yearsAcceleratedByDebtPayoff: accelGain,
            projectionPoints: points
        )
    }
}
