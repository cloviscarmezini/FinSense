import XCTest
@testable import FinSense

@MainActor
final class PlanningInsightsAndIntraMonthTests: XCTestCase {

    private func makeIsolatedStore() -> FinancialDataStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinSensePlanningTests_\(UUID().uuidString)")
        return FinancialDataStore(customDirectory: tempDir, seedStatementOnFirstLaunch: false)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    // MARK: - 1. Vale de Caixa Intramês (Cutoff, Recovery e Ignorar Compras no Cartão)

    func testIntraMonthCashTroughCutoffAndRecovery() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 1)
        store.simulatedCurrentDate = refNow

        let acc = BankAccount(name: "Conta Principal", initialBalance: 500.0)
        store.accounts = [acc]

        let card = CreditCard(name: "Nubank", totalLimit: 5000, closingDay: 25, dueDay: 5, defaultPaymentAccountId: acc.id)
        store.creditCards = [card]

        let expCat = store.categories.first(where: { $0.type == .expense })!
        let incCat = store.categories.first(where: { $0.type == .income })!

        let txRent = FinancialTransaction(
            name: "Aluguel",
            amount: 2000.0,
            date: date(year: 2026, month: 11, day: 10),
            type: .expense,
            isPaid: false,
            categoryId: expCat.id,
            accountId: acc.id
        )
        let txCardPurchase = FinancialTransaction(
            name: "Compra Cartão",
            amount: 900.0,
            date: date(year: 2026, month: 11, day: 12),
            type: .expense,
            isPaid: false,
            categoryId: expCat.id,
            accountId: card.id,
            creditCardId: card.id,
            creditCardInvoiceYearMonthKey: 202612
        )
        let txInternet = FinancialTransaction(
            name: "Internet",
            amount: 300.0,
            date: date(year: 2026, month: 11, day: 15),
            type: .expense,
            isPaid: false,
            categoryId: expCat.id,
            accountId: acc.id
        )
        let txSalary = FinancialTransaction(
            name: "Salário",
            amount: 4000.0,
            date: date(year: 2026, month: 11, day: 25),
            type: .income,
            isPaid: false,
            categoryId: incCat.id,
            accountId: acc.id
        )

        store.transactions = [txRent, txCardPurchase, txInternet, txSalary]

        let analysis = store.buildIntraMonthCashFlowAnalysis(for: refNow)

        XCTAssertEqual(analysis.openingBalance, 500.0, accuracy: 0.01)
        XCTAssertEqual(analysis.closingBalance, 2200.0, accuracy: 0.01) // 500 - 2000 - 300 + 4000 (cartão não abate caixa diretamente)
        XCTAssertTrue(analysis.hasIntraMonthDeficit)
        XCTAssertTrue(analysis.isTemporaryTrough)
        XCTAssertEqual(analysis.minimumBalance, -1800.0, accuracy: 0.01)
        XCTAssertEqual(analysis.shortfallAmount, 1800.0, accuracy: 0.01)
        XCTAssertEqual(analysis.riskStartDay, 10)
        XCTAssertEqual(analysis.riskEndDay, 25)
        XCTAssertEqual(analysis.cutoffTransactionId, txRent.id)
        XCTAssertEqual(analysis.recoveryTransactionId, txSalary.id)
        XCTAssertTrue(analysis.deficitZoneTransactionIds.contains(txRent.id))
        XCTAssertTrue(analysis.deficitZoneTransactionIds.contains(txInternet.id))
        XCTAssertNil(analysis.runningBalanceByTransactionId[txCardPurchase.id])
        XCTAssertEqual(analysis.runningBalanceByTransactionId[txRent.id] ?? 0, -1500.0, accuracy: 0.01)
        XCTAssertEqual(analysis.runningBalanceByTransactionId[txInternet.id] ?? 0, -1800.0, accuracy: 0.01)
        XCTAssertEqual(analysis.runningBalanceByTransactionId[txSalary.id] ?? 0, 2200.0, accuracy: 0.01)
    }

    // MARK: - 2. Sinking Funds (Divisão Proporcional e Integração ao Orçamento)

    func testSinkingFundsProportionalSplitAndBudgetIntegration() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 15)
        store.simulatedCurrentDate = refNow

        let baseProvision = store.totalRemainingProvision(for: refNow, referenceNow: refNow)
        XCTAssertEqual(baseProvision, 0.0, accuracy: 0.01)

        let ipvaFund = SinkingFund(
            name: "IPVA Anual",
            targetAmount: 3600.0,
            recurrenceMonths: 12,
            dueMonth: 1,
            dueYear: 2027
        )
        let seguroFund = SinkingFund(
            name: "Seguro Semestral",
            targetAmount: 1200.0,
            recurrenceMonths: 6,
            dueMonth: 5,
            dueYear: 2027
        )

        store.addSinkingFund(ipvaFund)
        store.addSinkingFund(seguroFund)

        XCTAssertEqual(ipvaFund.monthlyContribution, 300.0, accuracy: 0.01)
        XCTAssertEqual(seguroFund.monthlyContribution, 200.0, accuracy: 0.01)
        XCTAssertEqual(store.totalMonthlySinkingFundContribution, 500.0, accuracy: 0.01)
        XCTAssertEqual(store.totalRemainingProvision(for: refNow, referenceNow: refNow), 500.0, accuracy: 0.01)

        // Desabilitar uma caixinha remove sua parcela da provisão mensal
        var disabledSeguro = seguroFund
        disabledSeguro.isEnabled = false
        store.updateSinkingFund(disabledSeguro)
        XCTAssertEqual(store.totalRemainingProvision(for: refNow, referenceNow: refNow), 300.0, accuracy: 0.01)
    }

    // MARK: - 3. Simulações Read-Only (Amortizar vs Investir & Stress Test)

    func testSimulationsNeverMutateRealStoreData() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 5)
        store.simulatedCurrentDate = refNow

        let acc = BankAccount(name: "Conta Corrente", initialBalance: 2000.0)
        store.accounts = [acc]

        let expCat = store.categories.first(where: { $0.type == .expense })!
        let incCat = store.categories.first(where: { $0.type == .income })!

        let salary = FinancialTransaction(
            name: "Salário",
            amount: 6000.0,
            date: date(year: 2026, month: 11, day: 5),
            type: .income,
            isPaid: true,
            categoryId: incCat.id,
            accountId: acc.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .monthly
        )
        let bonus = FinancialTransaction(
            name: "Bônus Anual",
            amount: 10000.0,
            date: date(year: 2026, month: 12, day: 15),
            type: .income,
            isPaid: false,
            categoryId: incCat.id,
            accountId: acc.id,
            recurrenceMode: .single
        )
        store.transactions = [salary, bonus]

        let contract = CreditContract(
            kind: .loan,
            name: "Consignado Banco",
            loanSubtype: .consignado,
            amortizationSystem: .price,
            totalContractedAmount: 50000.0,
            outstandingBalance: 40000.0,
            installmentAmount: 2200.0,
            billingDay: 10,
            totalInstallments: 24,
            monthlyInterestRate: 2.0,
            accountId: acc.id,
            categoryId: expCat.id
        )
        store.contracts = [contract]

        let plan = AmortizationPlan(
            contractId: contract.id,
            items: [
                PlannedAmortization(contractId: contract.id, date: date(year: 2026, month: 12, day: 20), amount: Decimal(5000))
            ]
        )
        store.amortizationPlans = [plan]

        let initialTxCount = store.transactions.count
        let initialBalance = store.currentOutstandingBalance(for: contract)
        let initialPlanCount = store.amortizationPlans.count

        // 1. Comparador: Dívida 2.0% a.m. (~26.8% a.a.) vs Selic 11.25% a.a. -> Deve recomendar Amortizar
        let cmpHighDebt = DecisionAndScenarioEngine.compareAmortizeVsInvest(
            contract: contract,
            outstandingBalance: 40000.0,
            remainingMonths: 24,
            extraAmount: 5000.0,
            benchmarkGrossAnnualRatePercent: 11.25,
            taxRatePercent: 15.0
        )
        XCTAssertEqual(cmpHighDebt.recommendation, .amortize)
        XCTAssertGreaterThan(cmpHighDebt.amortizeInterestSaved, cmpHighDebt.investProjectedNetGain)

        // 2. Stress Test: Queda de 80% no bônus + imprevisto de R$ 12.000 no próximo mês
        let scenario = WhatIfScenario(
            name: "Crise Severa",
            variableIncomeReductionPercent: 80.0,
            unexpectedExpenseAmount: 12000.0,
            unexpectedExpenseMonthOffset: 1
        )
        let stress = DecisionAndScenarioEngine.runStressTest(
            store: store,
            scenario: scenario,
            horizonMonths: 6,
            startMonth: refNow
        )

        XCTAssertFalse(stress.negativeMonthKeys.isEmpty)
        XCTAssertFalse(stress.suggestedMitigations.isEmpty)

        // Garantia absoluta de que nenhuma simulação mutou os dados reais do usuário
        XCTAssertEqual(store.transactions.count, initialTxCount)
        XCTAssertEqual(store.currentOutstandingBalance(for: contract), initialBalance, accuracy: 0.001)
        XCTAssertEqual(store.amortizationPlans.count, initialPlanCount)
    }

    // MARK: - 4. Motor ML Comportamental (Detectores & Retroalimentação)

    func testBehavioralMLDetectorsAndFeedbackLoop() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 20)
        store.simulatedCurrentDate = refNow

        let acc = BankAccount(name: "Itaú", initialBalance: 10000.0)
        store.accounts = [acc]

        let foodCat = store.categories.first(where: { $0.name.localizedCaseInsensitiveContains("aliment") || $0.type == .expense })!
        let subsCat = store.categories.last(where: { $0.type == .expense }) ?? foodCat

        var txs: [FinancialTransaction] = []

        // Meses anteriores (-5 e -4 = Junho e Julho): Supermercado ~ R$ 400
        txs.append(FinancialTransaction(name: "Supermercado", amount: 400, date: date(year: 2026, month: 6, day: 10), type: .expense, isPaid: true, categoryId: foodCat.id, accountId: acc.id))
        txs.append(FinancialTransaction(name: "Supermercado", amount: 420, date: date(year: 2026, month: 7, day: 10), type: .expense, isPaid: true, categoryId: foodCat.id, accountId: acc.id))

        // Últimos 3 meses fechados (Ago, Set, Out): Inflação forte para R$ 900
        txs.append(FinancialTransaction(name: "Supermercado", amount: 880, date: date(year: 2026, month: 8, day: 10), type: .expense, isPaid: true, categoryId: foodCat.id, accountId: acc.id))
        txs.append(FinancialTransaction(name: "Supermercado", amount: 910, date: date(year: 2026, month: 9, day: 10), type: .expense, isPaid: true, categoryId: foodCat.id, accountId: acc.id))
        txs.append(FinancialTransaction(name: "Supermercado", amount: 920, date: date(year: 2026, month: 10, day: 10), type: .expense, isPaid: true, categoryId: foodCat.id, accountId: acc.id))

        // Amostras regulares menores em subsCat para formar mediana ~ R$ 50 e detectar anomalia no mês atual
        for m in 6...10 {
            txs.append(FinancialTransaction(name: "Streaming Plus", amount: 40.0, date: date(year: 2026, month: m, day: 5), type: .expense, isPaid: true, categoryId: subsCat.id, accountId: acc.id, recurrenceMode: .recurring, recurrenceFrequency: .monthly))
        }
        // Reajuste silencioso da assinatura no mês atual (de R$ 40 para R$ 65)
        txs.append(FinancialTransaction(name: "Streaming Plus", amount: 65.0, date: date(year: 2026, month: 11, day: 5), type: .expense, isPaid: true, categoryId: subsCat.id, accountId: acc.id, recurrenceMode: .recurring, recurrenceFrequency: .monthly))

        // Gasto anômalo fora da curva em subsCat no mês atual
        txs.append(FinancialTransaction(name: "Compra Extraordinária", amount: 2500.0, date: date(year: 2026, month: 11, day: 12), type: .expense, isPaid: true, categoryId: subsCat.id, accountId: acc.id))

        store.transactions = txs

        let generated = store.runDailyBehavioralMLAnalysisIfNeeded(force: false, referenceDate: refNow)
        XCTAssertFalse(generated.isEmpty)
        XCTAssertTrue(generated.contains(where: { $0.kind == .personalInflation }))
        XCTAssertTrue(generated.contains(where: { $0.kind == .subscriptionDriftOrForgotten }))
        XCTAssertTrue(generated.contains(where: { $0.kind == .consumptionAnomaly }))
        XCTAssertNotNil(store.monthlyReviews.first(where: { $0.yearMonthKey == 202610 }))

        // Execução no mesmo dia sem force não deve duplicar ou retreinar
        let secondRunSameDay = store.runDailyBehavioralMLAnalysisIfNeeded(force: false, referenceDate: refNow)
        XCTAssertTrue(secondRunSameDay.isEmpty)

        // Feedback deve retroalimentar o perfil ML
        let epochBeforeFeedback = store.mlBehavioralProfile.usefulFeedbackCount
        if let firstInsight = store.insights.first {
            store.submitInsightFeedback(.useful, forInsightId: firstInsight.id)
            XCTAssertEqual(store.mlBehavioralProfile.usefulFeedbackCount, epochBeforeFeedback + 1)
            XCTAssertEqual(store.insights.first(where: { $0.id == firstInsight.id })?.feedback, .useful)
        }
    }

    // MARK: - 5. Export / Import Completo + Compatibilidade Retroativa com Backups Legados

    func testExportImportAndLegacyBackwardsCompatibility() throws {
        let sourceStore = makeIsolatedStore()
        let acc = BankAccount(name: "Conta Export", initialBalance: 1500.0)
        sourceStore.accounts = [acc]

        let sf = SinkingFund(name: "IPTU", targetAmount: 2400.0, recurrenceMonths: 12)
        let sc = WhatIfScenario(name: "Queda Bonus", variableIncomeReductionPercent: 35.0, unexpectedExpenseAmount: 3000.0, unexpectedExpenseMonthOffset: 2)
        let ins = FinancialInsight(fingerprint: "test_fp", kind: .personalInflation, severity: .warning, title: "Teste Insight", message: "Msg", recommendation: "Rec", impactAmount: 200, yearMonthKey: 202611, feedback: .useful)
        let rev = MonthlyReviewRecord(year: 2026, month: 10, plannedIncome: 5000, realizedIncome: 5000, plannedExpense: 3000, realizedExpense: 3200, plannedEndBalance: 3500, realizedEndBalance: 3300, previousMonthEndBalance: 1500, pendingAmortizationsCount: 0, pendingAmortizationsAmount: 0, deviationHighlights: ["Desvio teste"], isCompleted: true)

        sourceStore.addSinkingFund(sf)
        sourceStore.saveWhatIfScenario(sc)
        sourceStore.insights = [ins]
        sourceStore.monthlyReviews = [rev]
        sourceStore.mlBehavioralProfile.usefulFeedbackCount = 3

        guard let archiveData = sourceStore.exportFullDatabaseArchive(compress: true) else {
            return XCTFail("Falha ao gerar arquivo de backup completo")
        }

        let targetStore = makeIsolatedStore()
        let pkg = try targetStore.prepareDatabaseImportPackage(from: archiveData)
        XCTAssertEqual(pkg.totalCount(for: .sinkingFunds), 1)
        XCTAssertEqual(pkg.totalCount(for: .decisionsAndScenarios), 1)
        XCTAssertGreaterThanOrEqual(pkg.totalCount(for: .insightsAndML), 2)

        let res = targetStore.executeSelectiveDatabaseImportSync(
            package: pkg,
            selectedTargets: Set(ExportDataTarget.allCases)
        )
        XCTAssertEqual(res.importedSinkingFunds, 1)
        XCTAssertEqual(res.importedWhatIfScenarios, 1)
        XCTAssertEqual(targetStore.sinkingFunds.first?.name, "IPTU")
        XCTAssertEqual(targetStore.whatIfScenarios.first?.name, "Queda Bonus")
        XCTAssertEqual(targetStore.insights.first?.feedback, .useful)
        XCTAssertEqual(targetStore.monthlyReviews.first?.isCompleted, true)
        XCTAssertEqual(targetStore.mlBehavioralProfile.usefulFeedbackCount, 3)

        // Teste de compatibilidade retroativa com JSON legado (sem os campos das novas features)
        let legacyJSON = """
        {
          "schemaVersion": 2,
          "accounts": [
            {
              "id": "\(UUID().uuidString)",
              "name": "Conta Legada",
              "iconSymbol": "building.columns.fill",
              "colorHex": "#EC7000",
              "initialBalance": 950.0,
              "agency": "",
              "accountNumber": "",
              "createdAt": 780000000
            }
          ],
          "categories": [],
          "transactions": [],
          "investments": [],
          "debts": [],
          "contracts": [],
          "llmConfig": {},
          "chatHistory": [],
          "hasSeededInitialStatement": false
        }
        """.data(using: .utf8)!

        let legacyStore = makeIsolatedStore()
        let legacyPkg = try legacyStore.prepareDatabaseImportPackage(from: legacyJSON)
        XCTAssertEqual(legacyPkg.totalCount(for: .accounts), 1)
        XCTAssertEqual(legacyPkg.totalCount(for: .sinkingFunds), 0)

        let legacyRes = legacyStore.executeSelectiveDatabaseImportSync(package: legacyPkg, selectedTargets: [.accounts])
        XCTAssertEqual(legacyRes.importedAccounts, 1)
        XCTAssertTrue(legacyStore.accounts.contains(where: { $0.name == "Conta Legada" }))
    }

    // MARK: - 6. CloudSync Deltas DTO Decoding para Novas Entidades

    func testCloudSyncDeltasDecodeNewPlanningAndInsightsEntities() throws {
        let sfId = UUID()
        let scId = UUID()
        let insId = UUID()
        let revId = UUID()
        let profId = UUID()

        let json = """
        {
            "sinking_funds": [
                {
                    "id": "\(sfId.uuidString)",
                    "name": "IPVA Teste Sync",
                    "target_amount": 3600.0,
                    "recurrence_months": 12,
                    "due_month": 1,
                    "due_year": 2027,
                    "accumulated_reserve": 600.0,
                    "is_enabled": true
                }
            ],
            "what_if_scenarios": [
                {
                    "id": "\(scId.uuidString)",
                    "name": "Cenário Sync",
                    "variable_income_reduction_percent": 25.0,
                    "unexpected_expense_amount": 2000.0,
                    "unexpected_expense_month_offset": 1
                }
            ],
            "financial_insights": [
                {
                    "id": "\(insId.uuidString)",
                    "fingerprint": "fp_sync_1",
                    "kind": "Inflação Pessoal",
                    "severity": "warning",
                    "title": "Alerta Sync",
                    "message": "Mensagem",
                    "recommendation": "Rec",
                    "impact_amount": 150.0,
                    "year_month_key": 202611,
                    "feedback": "useful"
                }
            ],
            "monthly_reviews": [
                {
                    "id": "\(revId.uuidString)",
                    "year": 2026,
                    "month": 10,
                    "planned_income": 5000.0,
                    "realized_income": 5000.0,
                    "planned_expense": 3000.0,
                    "realized_expense": 2900.0,
                    "is_completed": true
                }
            ],
            "ml_behavioral_profiles": [
                {
                    "id": "\(profId.uuidString)",
                    "training_epoch_count": 4,
                    "analyzed_transactions_count": 120,
                    "inflation_sensitivity": 1.15,
                    "anomaly_z_threshold": 2.1,
                    "useful_feedback_count": 5
                }
            ]
        }
        """.data(using: .utf8)!

        let deltas = try JSONDecoder().decode(SyncDeltasContainerDTO.self, from: json)
        XCTAssertEqual(deltas.sinkingFunds?.first?.id, sfId)
        XCTAssertEqual(deltas.sinkingFunds?.first?.monthlyContribution ?? 0, 300.0, accuracy: 0.01)
        XCTAssertEqual(deltas.whatIfScenarios?.first?.id, scId)
        XCTAssertEqual(deltas.financialInsights?.first?.feedback, .useful)
        XCTAssertEqual(deltas.monthlyReviews?.first?.isCompleted, true)
        XCTAssertEqual(deltas.mlBehavioralProfiles?.first?.trainingEpochCount, 4)
    }
}
