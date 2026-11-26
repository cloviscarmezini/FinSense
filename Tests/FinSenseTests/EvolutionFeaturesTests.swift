import XCTest
@testable import FinSense

@MainActor
final class EvolutionFeaturesTests: XCTestCase {

    private func makeIsolatedStore() -> FinancialDataStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinSenseEvolutionTests_\(UUID().uuidString)")
        return FinancialDataStore(customDirectory: tempDir, seedStatementOnFirstLaunch: false)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return Calendar.current.date(from: comps) ?? Date()
    }

    // MARK: - Feature 2: Quick-Add Natural Language Parser

    func testQuickAddNaturalLanguageParsing() {
        let store = makeIsolatedStore()
        let nubankAcc = BankAccount(name: "Nubank", initialBalance: 2000)
        let cardMom = CreditCard(name: "Cartão da Mãe", totalLimit: 5000, closingDay: 25, dueDay: 5, defaultPaymentAccountId: nubankAcc.id)
        store.accounts = [nubankAcc]
        store.creditCards = [cardMom]

        let d1 = QuickAddParserService.parse("185 mercado nubank", store: store)
        XCTAssertEqual(d1.amount, 185.0, accuracy: 0.01)
        XCTAssertEqual(d1.targetAccountId, nubankAcc.id)
        XCTAssertEqual(d1.currencyCode, "BRL")
        XCTAssertTrue(d1.cleanTitle.localizedCaseInsensitiveContains("Mercado"))

        let d2 = QuickAddParserService.parse("1200 em 3x tênis cartão da mãe", store: store)
        XCTAssertEqual(d2.amount, 1200.0, accuracy: 0.01)
        XCTAssertEqual(d2.installmentsCount, 3)
        XCTAssertEqual(d2.recurrenceMode, .installment)
        XCTAssertEqual(d2.targetCreditCardId, cardMom.id)

        let d3 = QuickAddParserService.parse("250 combustível reembolsável empresa", store: store)
        XCTAssertEqual(d3.amount, 250.0, accuracy: 0.01)
        XCTAssertTrue(d3.isReimbursable)
        XCTAssertEqual(d3.reimbursableDebtor, "Empresa")

        let d4 = QuickAddParserService.parse("US$ 45 cursor dev", store: store)
        XCTAssertEqual(d4.amount, 45.0, accuracy: 0.01)
        XCTAssertEqual(d4.currencyCode, "USD")
    }

    // MARK: - Feature 1 & 3: Reconciliation Rules & Apple Pay Review

    func testReconciliationRulesPriorityAndApplePayReview() {
        let store = makeIsolatedStore()
        let transportCat = store.fallbackCategoryId(for: .expense, matchingSubstring: "Transporte")
        let foodCat = store.fallbackCategoryId(for: .expense, matchingSubstring: "Alimentação")

        let lowPriorityRule = ReconciliationRule(
            name: "Catch-all Uber Comida",
            priority: 20,
            matchOperator: .contains,
            matchPattern: "UBER",
            targetCategoryId: foodCat,
            cleanName: "Uber Genérico"
        )
        let highPriorityRule = ReconciliationRule(
            name: "Uber Corrida",
            priority: 5,
            matchOperator: .regex,
            matchPattern: #"UBER\s*\*?TRIP"#,
            minAmount: 10.0,
            maxAmount: 200.0,
            targetCategoryId: transportCat,
            cleanName: "Uber",
            markReimbursable: true,
            reimbursableDebtor: "Empresa"
        )
        store.addReconciliationRule(lowPriorityRule)
        store.addReconciliationRule(highPriorityRule)

        var tx = FinancialTransaction(
            name: "UBER *TRIP HELP.UBER.COM",
            amount: 42.50,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: store.fallbackCategoryId(for: .expense),
            accountId: UUID(),
            needsReview: true,
            sourceApp: "apple_pay"
        )

        let matched = store.applyReconciliationRulesIfNeeded(to: &tx)
        XCTAssertTrue(matched)
        XCTAssertEqual(tx.categoryId, transportCat)
        XCTAssertEqual(tx.name, "Uber")
        XCTAssertEqual(tx.isReimbursable, true)
        XCTAssertEqual(tx.reimbursableDebtor, "Empresa")

        // Statement import runs rules deterministically too
        let parsed = StatementImportService.parseStatementText(
            "20/11/2026 UBER *TRIP HELP -55,00",
            categories: store.categories,
            reconciliationRules: store.reconciliationRules
        )
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.cleanTitle, "Uber")
        XCTAssertEqual(parsed.first?.matchedRuleName, "Uber Corrida")
        XCTAssertEqual(parsed.first?.suggestedCategoryId, transportCat)

        // Review approval
        store.transactions = [tx]
        XCTAssertEqual(store.pendingReviewCount, 1)
        store.approveTransactionReview(tx.id)
        XCTAssertEqual(store.pendingReviewCount, 0)
        XCTAssertEqual(store.transactions.first?.needsReview, false)
    }

    // MARK: - Feature 4: Net Worth & Income Sources

    func testNetWorthAssetsEquityLiabilitiesAndSnapshots() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 15)
        store.simulatedCurrentDate = refNow

        let acc = BankAccount(name: "Conta", initialBalance: 20_000)
        store.accounts = [acc]
        let inv = InvestmentItem(name: "Tesouro", groupName: "Renda Fixa", investmentAccountId: acc.id, balance: 80_000)
        store.investments = [inv]

        let expCat = store.fallbackCategoryId(for: .expense)
        let financing = CreditContract(
            kind: .financing,
            name: "Financiamento Apto",
            amortizationSystem: .sac,
            totalContractedAmount: 200_000,
            outstandingBalance: 150_000,
            installmentAmount: 2500,
            billingDay: 10,
            totalInstallments: 120,
            monthlyInterestRate: 0.008,
            startDate: date(year: 2025, month: 1, day: 10),
            accountId: acc.id,
            categoryId: expCat
        )
        store.contracts = [financing]

        let apartment = AssetItem(
            name: "Apartamento",
            assetClass: .realEstate,
            purchaseValue: 350_000,
            currentMarketValue: 400_000,
            linkedFinancingContractId: financing.id
        )
        let fgts = AssetItem(name: "FGTS", assetClass: .fgts, purchaseValue: 30_000, currentMarketValue: 30_000)
        store.addAssetItem(apartment)
        store.addAssetItem(fgts)

        let debt = DebtItem(name: "IPVA Antigo", originalAmount: 5_000)
        store.debts = [debt]

        store.addIncomeSource(IncomeSource(name: "Salário", kind: .fixedSalary, grossAmount: 18_000, netAmount: 14_000))

        let overview = store.netWorthOverview()
        // Total Assets = 20k + 80k + 400k + 30k = 530k
        XCTAssertEqual(overview.totalAssetsBRL, 530_000, accuracy: 0.01)
        // Equity Apto = 400k - 150k = 250k
        let aptoEq = overview.assetEquities.first { $0.asset.id == apartment.id }
        XCTAssertEqual(aptoEq?.equityBRL ?? 0, 250_000, accuracy: 0.01)
        // Net Worth = 530k - (150k + 5k) = 375k
        XCTAssertEqual(overview.netWorthBRL, 375_000, accuracy: 0.01)
        XCTAssertEqual(overview.incomeSummary.totalMonthlyExpectedIncomeBRL, 14_000, accuracy: 0.01)

        let snap = store.captureNetWorthSnapshot(for: refNow)
        XCTAssertEqual(snap.netWorthBRL, 375_000, accuracy: 0.01)
        XCTAssertEqual(store.netWorthSnapshots.count, 1)
    }

    // MARK: - Feature 5: FIRE Simulator

    func testFIRESimulatorMathAndDebtAcceleration() {
        let real = FIRESimulatorEngine.realAnnualReturn(nominalPercent: 11.25, inflationPercent: 4.5)
        // (1.1125 / 1.045) - 1 = 0.0645933...
        XCTAssertEqual(real, (1.1125 / 1.045) - 1.0, accuracy: 0.0001)

        let scenario = FIREPlanScenario(
            monthlyCostOfLivingBRL: 4000,
            currentInvestedPatrimonyBRL: 100_000,
            monthlyContributionBRL: 2000,
            safeWithdrawalRatePercent: 4.0,
            expectedAnnualNominalReturnPercent: 11.25,
            expectedAnnualInflationPercent: 4.5
        )
        let res = FIRESimulatorEngine.simulate(
            scenario: scenario,
            additionalDebtFreedMonthlyContributionBRL: 3000,
            debtPayoffYearOffset: 2
        )
        // 4000 * 12 / 0.04 = 1,200,000
        XCTAssertEqual(res.fireTargetNumberBRL, 1_200_000, accuracy: 1.0)
        XCTAssertNotNil(res.yearsToFIREBaseline)
        XCTAssertNotNil(res.yearsToFIREPostDebt)
        XCTAssertLessThan(res.yearsToFIREPostDebt ?? 99, res.yearsToFIREBaseline ?? 0)
    }

    // MARK: - Feature 6: Reimbursements Accounting Split & Partial/Full Settlement

    func testReimbursementsBudgetSplitAndSettlement() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 10)
        store.simulatedCurrentDate = refNow

        let acc = BankAccount(name: "Itaú", initialBalance: 5000)
        store.accounts = [acc]
        let card = CreditCard(name: "Visa", totalLimit: 10_000, closingDay: 25, dueDay: 5, defaultPaymentAccountId: acc.id)
        store.creditCards = [card]

        let foodCat = store.fallbackCategoryId(for: .expense, matchingSubstring: "Alimentação")
        // Despesa de R$ 1.000 no cartão, onde R$ 600 serão reembolsados pela Empresa
        let created = store.createExtendedTransaction(
            name: "Jantar Corporativo",
            amount: 1000.0,
            date: refNow,
            type: .expense,
            isPaid: true,
            categoryId: foodCat,
            accountId: card.id,
            creditCardId: card.id,
            isReimbursable: true,
            reimbursableAmount: 600.0,
            reimbursableDebtor: "Empresa"
        )
        XCTAssertEqual(created.count, 1)
        let tx = created[0]

        // Regra de ouro: Cartão cobra 1.000 integrais; orçamento/despesa conta só os 400 pessoais
        XCTAssertEqual(store.usedLimit(for: card.id), 1000.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyExpense(for: refNow), 400.0, accuracy: 0.01)
        XCTAssertEqual(store.realizedMonthlyExpense(forCategory: foodCat, in: refNow), 400.0, accuracy: 0.01)
        XCTAssertEqual(store.totalPendingReceivablesBRL, 600.0, accuracy: 0.01)

        // Pagamento parcial R$ 300 -> credita conta (+300) sem inflar receita nos gráficos
        let r1 = store.registerReimbursementSettlement(forTransactionId: tx.id, receivedAmount: 300.0, accountId: acc.id, date: refNow)
        XCTAssertNotNil(r1)
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), 5300.0, accuracy: 0.01)
        XCTAssertEqual(store.totalPendingReceivablesBRL, 300.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyIncome(for: refNow), 0.0, accuracy: 0.01)
        XCTAssertTrue(store.categoryBreakdown(for: refNow, type: .income).isEmpty)

        // Liquidação do saldo restante R$ 300
        _ = store.registerReimbursementSettlement(forTransactionId: tx.id, receivedAmount: 300.0, accountId: acc.id, date: refNow)
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), 5600.0, accuracy: 0.01)
        XCTAssertEqual(store.totalPendingReceivablesBRL, 0.0, accuracy: 0.01)
        XCTAssertEqual(store.openReimbursableTransactions.count, 0)

        // Cenário B: Receber valor MENOR e finalizar (diferença fica como gasto próprio do usuário)
        let txLess = store.createExtendedTransaction(
            name: "Almoço Equipe",
            amount: 500.0,
            date: refNow,
            type: .expense,
            isPaid: true,
            categoryId: foodCat,
            accountId: card.id,
            creditCardId: card.id,
            isReimbursable: true,
            reimbursableAmount: 500.0,
            reimbursableDebtor: "Equipe"
        )[0]
        _ = store.registerReimbursementSettlement(
            forTransactionId: txLess.id,
            receivedAmount: 350.0,
            accountId: acc.id,
            date: refNow,
            finalizeReimbursement: true
        )
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), 5950.0, accuracy: 0.01)
        XCTAssertEqual(store.totalPendingReceivablesBRL, 0.0, accuracy: 0.01)
        // Diferença não recebida (R$ 150) soma ao gasto próprio (R$ 400 + R$ 150 = R$ 550)
        XCTAssertEqual(store.monthlyExpense(for: refNow), 550.0, accuracy: 0.01)

        // Cenário C: Receber valor MAIOR que o previsto e finalizar
        let txMore = store.createExtendedTransaction(
            name: "Corrida Uber Cliente",
            amount: 100.0,
            date: refNow,
            type: .expense,
            isPaid: true,
            categoryId: foodCat,
            accountId: card.id,
            creditCardId: card.id,
            isReimbursable: true,
            reimbursableAmount: 100.0,
            reimbursableDebtor: "Cliente"
        )[0]
        _ = store.registerReimbursementSettlement(
            forTransactionId: txMore.id,
            receivedAmount: 130.0,
            accountId: acc.id,
            date: refNow,
            finalizeReimbursement: true
        )
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), 6080.0, accuracy: 0.01)
        let updatedMore = try? XCTUnwrap(store.transactions.first(where: { $0.id == txMore.id }))
        XCTAssertEqual(updatedMore?.isReimbursementSettled, true)
        XCTAssertEqual(updatedMore?.reimbursementReceivedAmount ?? 0, 130.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyExpense(for: refNow), 550.0, accuracy: 0.01)
    }

    // MARK: - Credit Card Custom Invoice Allocation & Default Next Unpaid Invoice

    func testCreditCardCustomInvoiceSelectionAndDefaultNextInvoice() {
        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 10)
        store.simulatedCurrentDate = refNow

        let acc = BankAccount(name: "Conta", initialBalance: 5000)
        store.accounts = [acc]
        let card = CreditCard(name: "Inter", totalLimit: 8000, closingDay: 25, bestPurchaseDay: 26, dueDay: 5, defaultPaymentAccountId: acc.id)
        store.creditCards = [card]

        // Compra em 10/11 cai por padrão na fatura 202612 (Dez/2026)
        XCTAssertEqual(store.defaultCreditCardInvoiceKey(forPurchaseDate: refNow, card: card), 202612)

        // Se a fatura 202612 já estiver paga, o padrão avança automaticamente para 202701
        let decDates = CreditCardEngine.closingAndDueDates(forInvoiceYear: 2026, month: 12, card: card)
        store.creditCardInvoices = [
            CreditCardInvoice(
                creditCardId: card.id,
                year: 2026,
                month: 12,
                closingDate: decDates.closingDate,
                dueDate: decDates.dueDate,
                isPaid: true,
                paidAmount: 0,
                paidDate: refNow,
                paidFromAccountId: acc.id
            )
        ]
        XCTAssertEqual(store.defaultCreditCardInvoiceKey(forPurchaseDate: refNow, card: card), 202701)

        // Lançamento parcelado em 2x direcionado explicitamente para a fatura 202702 -> cai em 202702 e 202703
        let catId = store.fallbackCategoryId(for: .expense)
        let created = store.createTransaction(
            name: "Hotel",
            amount: 1000.0,
            date: refNow,
            type: .expense,
            categoryId: catId,
            accountId: card.id,
            recurrenceMode: .installment,
            installmentsOrMonthsCount: 2,
            creditCardId: card.id,
            creditCardInvoiceYearMonthKey: 202702
        )
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created[0].creditCardInvoiceYearMonthKey, 202702)
        XCTAssertEqual(created[1].creditCardInvoiceYearMonthKey, 202703)
    }

    // MARK: - Custom Account Image High-Quality Retina Downsampling

    func testAccountAvatarHighQualityDownsampling() throws {
        // Cria uma imagem PNG de alta resolução (512x512) em diretório temporário e valida reamostragem nítida para 36pt
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test_avatar_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let size = 512
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Falha ao criar contexto CG")
            return
        }
        ctx.setFillColor(red: 0.92, green: 0.44, blue: 0.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let cg = ctx.makeImage() else {
            XCTFail("Falha ao gerar CGImage")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: fileURL)

        let downsampled = AccountAvatarImageCache.shared.crispImage(forFilePath: fileURL.path, pointSize: 36)
        XCTAssertNotNil(downsampled)
        XCTAssertEqual(downsampled?.size.width ?? 0, 36, accuracy: 0.1)
        let outCG = downsampled?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertNotNil(outCG)
        // Deve possuir pixels >= 72x72 (Retina / oversampling >= 2x para 36pt)
        XCTAssertGreaterThanOrEqual(outCG?.width ?? 0, 72)
    }

    // MARK: - Feature 7: Multi-Currency Conversion

    func testMultiCurrencyConsolidatedBalancesAndNativeAccountPreservation() {
        ExchangeRateService.shared.setManualOverride(rate: 5.50, for: "USD")
        ExchangeRateService.shared.setManualOverride(rate: 6.00, for: "EUR")
        defer {
            ExchangeRateService.shared.setManualOverride(rate: nil, for: "USD")
            ExchangeRateService.shared.setManualOverride(rate: nil, for: "EUR")
        }

        let store = makeIsolatedStore()
        let refNow = date(year: 2026, month: 11, day: 10)
        store.simulatedCurrentDate = refNow

        let brAcc = BankAccount(name: "Itaú BR", initialBalance: 1000, currencyCode: "BRL")
        let usdAcc = BankAccount(name: "Wise USD", initialBalance: 1000, currencyCode: "USD")
        store.accounts = [brAcc, usdAcc]

        let eurInv = InvestmentItem(name: "ETF Europe", groupName: "Exterior", investmentAccountId: usdAcc.id, balance: 500, currencyCode: "EUR")
        store.investments = [eurInv]

        // Conta USD preserva saldo nativo $1000
        XCTAssertEqual(store.currentBalance(forAccount: usdAcc.id), 1000.0, accuracy: 0.01)
        // Consolidado converte para BRL: 1000 + (1000 * 5.50) = 6500; Inv = 500 * 6.00 = 3000
        XCTAssertEqual(store.totalCheckingBalanceNow, 6500.0, accuracy: 0.01)
        XCTAssertEqual(store.totalInvestmentsBalance, 3000.0, accuracy: 0.01)
        XCTAssertEqual(store.totalConsolidatedPatrimonyNow, 9500.0, accuracy: 0.01)
    }

    // MARK: - Export / Import Backwards Compatibility & Sync DTO Snake Case

    func testLegacySnapshotImportAndSyncSnakeCaseRoundtrip() async throws {
        // 1. Snapshot legado sem os novos arrays
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "accounts": [],
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
        let decodedLegacy = try JSONDecoder().decode(FinancialDatabaseSnapshot.self, from: legacyJSON)
        XCTAssertNil(decodedLegacy.reconciliationRules)
        XCTAssertNil(decodedLegacy.assetItems)

        // 2. Roundtrip completo de Export/Import seletivo
        let srcStore = makeIsolatedStore()
        srcStore.addReconciliationRule(ReconciliationRule(name: "Rule Test", matchPattern: "TEST"))
        srcStore.addAssetItem(AssetItem(name: "Carro", assetClass: .vehicle, currentMarketValue: 75_000))
        srcStore.addIncomeSource(IncomeSource(name: "Freela", kind: .variableSeasonal, grossAmount: 3000, netAmount: 2500))
        srcStore.saveFIREScenario(FIREPlanScenario(name: "Cenário Conservador", monthlyCostOfLivingBRL: 5000))
        _ = srcStore.captureNetWorthSnapshot()

        let exportedData = try XCTUnwrap(srcStore.exportFullDatabaseArchive(compress: true))
        let dstStore = makeIsolatedStore()
        let pkg = try dstStore.prepareDatabaseImportPackage(from: exportedData)
        XCTAssertTrue(pkg.availableNonEmptyTargets.contains(.reconciliationRules))
        XCTAssertTrue(pkg.availableNonEmptyTargets.contains(.netWorthAndAssets))
        XCTAssertTrue(pkg.availableNonEmptyTargets.contains(.incomeSources))
        XCTAssertTrue(pkg.availableNonEmptyTargets.contains(.fireScenarios))

        let res = await dstStore.executeSelectiveDatabaseImport(
            package: pkg,
            selectedTargets: pkg.availableNonEmptyTargets
        )
        XCTAssertEqual(res.importedReconciliationRules, 1)
        XCTAssertEqual(res.importedNetWorthAssets, 2) // 1 asset + 1 snapshot
        XCTAssertEqual(res.importedIncomeSources, 1)
        XCTAssertEqual(res.importedFIREScenarios, 1)

        // 3. Snake_case encode/decode Sync DTO para Transaction com exchangeRateToBRL + NetWorthSnapshot
        let tx = FinancialTransaction(
            name: "SaaS USD",
            amount: 20,
            date: Date(),
            type: .expense,
            categoryId: UUID(),
            accountId: UUID(),
            currencyCode: "USD",
            exchangeRateToBRL: 5.82
        )
        let snap = NetWorthSnapshot(
            yearMonthKey: 202611,
            liquidAssetsBRL: 1000,
            investmentsAssetsBRL: 2000,
            realEstateAssetsBRL: 0,
            vehicleAssetsBRL: 0,
            fgtsAndOtherAssetsBRL: 0,
            totalAssetsBRL: 3000,
            loansAndFinancingsLiabilitiesBRL: 500,
            creditCardsLiabilitiesBRL: 0,
            debtsLiabilitiesBRL: 0,
            totalLiabilitiesBRL: 500,
            netWorthBRL: 2500
        )
        let deltas = SyncDeltasContainerDTO(
            financialTransactions: [tx],
            reconciliationRules: srcStore.reconciliationRules,
            assetItems: srcStore.assets,
            incomeSources: srcStore.incomeSources,
            netWorthSnapshots: [snap],
            fireScenarios: srcStore.fireScenarios
        )
        let snakeEncoder = JSONEncoder()
        snakeEncoder.keyEncodingStrategy = .convertToSnakeCase
        snakeEncoder.dateEncodingStrategy = .iso8601
        let data = try snakeEncoder.encode(deltas)
        let decodedDeltas = try BackendAPIClient.makeFlexibleDateDecoder().decode(SyncDeltasContainerDTO.self, from: data)
        XCTAssertEqual(decodedDeltas.financialTransactions?.first?.exchangeRateToBRL ?? 0, 5.82, accuracy: 0.001)
        XCTAssertEqual(decodedDeltas.netWorthSnapshots?.first?.netWorthBRL ?? 0, 2500, accuracy: 0.01)
        XCTAssertEqual(decodedDeltas.reconciliationRules?.count, 1)
        XCTAssertEqual(decodedDeltas.fireScenarios?.count, 1)
    }
}
