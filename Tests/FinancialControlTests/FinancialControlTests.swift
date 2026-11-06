import XCTest
@testable import FinancialControl

@MainActor
final class FinancialControlTests: XCTestCase {

    private func makeIsolatedStore(seedStatement: Bool = false) -> FinancialDataStore {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FinancialControlTests_\(UUID().uuidString)")
        return FinancialDataStore(customDirectory: tempDir, seedStatementOnFirstLaunch: seedStatement)
    }

    func testCleanInstallStartsWithOnlyDefaultCategoriesAndZeroAccountsOrExpenses() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CleanInstallTest_\(UUID().uuidString)")
        let store = FinancialDataStore(customDirectory: tempDir)

        // O app deve ser instalado zerado, apenas com as categorias padrões, sem despesas ou contas
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertTrue(store.investments.isEmpty)
        XCTAssertTrue(store.debts.isEmpty)
        XCTAssertTrue(store.contracts.isEmpty)
        XCTAssertFalse(store.categories.isEmpty)
        XCTAssertFalse(store.hasInstalledLLMModel)
    }

    func testMandatoryLLMInstallationCheck() {
        let store = makeIsolatedStore(seedStatement: false)
        var actionExecuted = false

        // Sem modelo instalado, qualquer recurso de IA deve solicitar a instalação e bloquear a ação imediata
        let allowedWithoutModel = store.requireInstalledLLM(forFeature: "Chat IA Local") {
            actionExecuted = true
        }
        XCTAssertFalse(allowedWithoutModel)
        XCTAssertFalse(actionExecuted)
        XCTAssertTrue(store.isLLMInstallAlertPresented)
        XCTAssertEqual(store.pendingAIFeatureName, "Chat IA Local")

        // Após instalar um modelo local, a ação é permitida
        let installedModel = LocalLLMModelInfo(
            id: "Qwen/Qwen2.5-3B-Instruct-GGUF",
            displayName: "Qwen2.5-3B",
            fileName: "model.gguf",
            localPath: "/tmp/model.gguf",
            sizeBytes: 1_900_000_000
        )
        store.llmConfig.downloadedModels = [installedModel]
        store.llmConfig.selectedModelId = installedModel.id

        let allowedWithModel = store.requireInstalledLLM(forFeature: "Chat IA Local") {
            actionExecuted = true
        }
        XCTAssertTrue(allowedWithModel)
        XCTAssertTrue(actionExecuted)
    }

    func testResetFromScratchSelectiveAndComplete() {
        let store = makeIsolatedStore(seedStatement: true)
        XCTAssertFalse(store.accounts.isEmpty)
        XCTAssertFalse(store.transactions.isEmpty)
        XCTAssertFalse(store.debts.isEmpty)
        XCTAssertFalse(store.categories.isEmpty)

        // 1. Deleta apenas dívidas e transações manualmente
        store.resetSelectedData([.debts, .transactions])
        XCTAssertTrue(store.debts.isEmpty)
        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertFalse(store.accounts.isEmpty)
        XCTAssertFalse(store.categories.isEmpty)

        // 2. Deleta todos os itens (padrão quando todos estão selecionados)
        store.resetSelectedData(Set(ResetDataTarget.allCases))
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertTrue(store.categories.isEmpty)
        XCTAssertTrue(store.investments.isEmpty)
        XCTAssertTrue(store.contracts.isEmpty)
    }

    func testItauStatementParsingAndDeduplication() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Itaú Unibanco",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 0.0
        )
        let itauAccount = store.accounts.first!

        // 1. Testa filtro Apenas Despesas
        let expensesOnly = StatementImportService.parseStatementText(
            SampleItauStatementData.rawOCRText,
            categories: store.categories,
            filterMode: .expensesOnly
        )
        XCTAssertFalse(expensesOnly.isEmpty)
        XCTAssertTrue(expensesOnly.allSatisfy { $0.type == .expense })

        // 2. Testa filtro Apenas Receitas
        let incomesOnly = StatementImportService.parseStatementText(
            SampleItauStatementData.rawOCRText,
            categories: store.categories,
            filterMode: .incomesOnly
        )
        XCTAssertFalse(incomesOnly.isEmpty)
        XCTAssertTrue(incomesOnly.allSatisfy { $0.type == .income })

        // 3. Testa modo Híbrido e deduplicação
        let hybrid = StatementImportService.parseStatementText(
            SampleItauStatementData.rawOCRText,
            categories: store.categories,
            filterMode: .hybrid
        )
        XCTAssertEqual(hybrid.count, expensesOnly.count + incomesOnly.count)

        let firstImport = store.importParsedTransactions(hybrid, intoAccountId: itauAccount.id, filterMode: .hybrid)
        XCTAssertEqual(firstImport.addedCount, hybrid.count)
        XCTAssertEqual(firstImport.skippedDuplicatesCount, 0)

        // Importar novamente o mesmo relatório não deve duplicar nenhuma transação
        let secondImport = store.importParsedTransactions(hybrid, intoAccountId: itauAccount.id, filterMode: .hybrid)
        XCTAssertEqual(secondImport.addedCount, 0)
        XCTAssertEqual(secondImport.skippedDuplicatesCount, hybrid.count)
    }

    func testInstallmentRepeatedAndIgnoreInConsolidatedTransactions() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Itaú",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 1000.0
        )
        let acc = store.accounts.first!
        let expCat = store.categories(for: .expense).first!

        let initialAccountBal = store.currentBalance(forAccount: acc.id)

        // 1. Transação ignorada no consolidado não altera o saldo
        store.createTransaction(
            name: "Registro Informativo",
            amount: 500.0,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: expCat.id,
            accountId: acc.id,
            ignoreInConsolidated: true
        )
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), initialAccountBal, accuracy: 0.01)

        // 2. Despesa parcelada (valor cheio de R$ 1.200 em 4x = 4 parcelas de R$ 300)
        let installments = store.createTransaction(
            name: "Notebook",
            amount: 1200.0,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: expCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false,
            recurrenceMode: .installment,
            installmentsOrMonthsCount: 4
        )
        XCTAssertEqual(installments.count, 4)
        let sumInstallments = installments.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(sumInstallments, 1200.0, accuracy: 0.01)

        // 3. Despesa repetida (mesmo valor de R$ 150 repetido em 3 meses)
        let repeated = store.createTransaction(
            name: "Academia",
            amount: 150.0,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: expCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false,
            recurrenceMode: .repeated,
            installmentsOrMonthsCount: 3
        )
        XCTAssertEqual(repeated.count, 3)
        XCTAssertTrue(repeated.allSatisfy { abs($0.amount - 150.0) < 0.01 })
    }

    func testInvestmentsContributionAndConsolidatedToggle() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Itaú", bankPresetId: "itau", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC7000", initialBalance: 500.0)
        store.addAccount(name: "Santander", bankPresetId: "santander", customImagePath: nil, iconSymbol: "flame.fill", colorHex: "#EC0000", initialBalance: 0.0)
        let itau = store.accounts[0]
        let santander = store.accounts[1]

        store.addInvestment(
            name: "CDB Especial",
            groupName: "CDB Santander",
            investmentAccountId: santander.id,
            initialBalance: 0.0,
            showInConsolidated: true
        )
        let inv = store.investments.last!
        let beforeAccountBal = store.currentBalance(forAccount: itau.id)

        store.contributeToInvestment(
            investmentId: inv.id,
            amount: 200.0,
            sourceAccountId: itau.id,
            investmentAccountId: santander.id
        )

        // Tirou da conta de origem e adicionou no investimento
        XCTAssertEqual(store.currentBalance(forAccount: itau.id), beforeAccountBal - 200.0, accuracy: 0.01)
        let updatedInv = store.investments.first(where: { $0.id == inv.id })!
        XCTAssertEqual(updatedInv.balance, 200.0, accuracy: 0.01)

        let consolidatedWithInv = store.totalConsolidatedPatrimonyNow
        store.toggleInvestmentConsolidated(inv.id)
        let consolidatedWithoutInv = store.totalConsolidatedPatrimonyNow
        XCTAssertEqual(consolidatedWithInv - consolidatedWithoutInv, 200.0, accuracy: 0.01)
    }

    func testDebtNegotiationPaymentRemovesCardAndCreatesTransaction() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Itaú", bankPresetId: "itau", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC7000", initialBalance: 2000.0)
        store.addDebt(
            name: "Cartão Mercado Pago",
            customImagePath: nil,
            bankPresetId: "mercadopago",
            iconSymbol: "creditcard",
            colorHex: "#009EE3",
            originalAmount: 1850.0,
            contractedDate: nil
        )
        let acc = store.accounts.first!
        let debt = store.activeDebts.first!
        let originalCount = store.activeDebts.count
        let beforeBal = store.currentBalance(forAccount: acc.id)

        store.payDebt(
            debtId: debt.id,
            fromAccountId: acc.id,
            negotiatedAmount: 1200.0
        )

        XCTAssertEqual(store.activeDebts.count, originalCount - 1)
        XCTAssertEqual(store.currentBalance(forAccount: acc.id), beforeBal - 1200.0, accuracy: 0.01)
    }

    func testLoanWithPastStartDateCreatesOnlyFutureTransactionsAndCalculatesPayoff() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Itaú", bankPresetId: "itau", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC7000", initialBalance: 0.0)
        let acc = store.accounts.first!
        let cal = Calendar.current
        let now = BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!
        let startSixMonthsAgo = cal.date(byAdding: .month, value: -6, to: now)!

        let contract = store.createCreditContract(
            kind: .loan,
            name: "Consignado Teste",
            loanSubtype: .consignado,
            amortizationSystem: .price,
            totalContractedAmount: 12000.0,
            installmentAmount: 600.0,
            billingDay: 15,
            totalInstallments: 24,
            monthlyInterestRate: 1.80,
            startDate: startSixMonthsAgo,
            accountId: acc.id,
            referenceDate: now
        )

        XCTAssertEqual(contract.pastInstallmentsElapsedAtCreation, 6)
        let generatedFutureTxs = store.unpaidTransactions(forContract: contract.id)
        XCTAssertEqual(generatedFutureTxs.count, 18)
        XCTAssertTrue(generatedFutureTxs.allSatisfy { $0.date >= cal.startOfDay(for: now) })

        let nominal = store.remainingNominalAmount(for: contract)
        let projectedPayoff = store.projectedPayoffAmount(for: contract)
        XCTAssertEqual(nominal, 18.0 * 600.0, accuracy: 0.01)
        XCTAssertLessThan(projectedPayoff, nominal)
        XCTAssertGreaterThan(projectedPayoff, 0)
    }

    func testAIChatProjectionsAndInsufficientDataHandling() {
        // Caso 1: Sem transações -> deve informar que não tem dados suficientes
        let emptyStore = makeIsolatedStore(seedStatement: false)
        let noDataReply = LocalLLMService.generateFinancialResponse(
            for: "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida Cartão Mercado Pago?",
            store: emptyStore,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(noDataReply.localizedCaseInsensitiveContains("Não há dados suficientes"))

        // Caso 2: Com extrato Itaú carregado -> analisa dívida e analisa projeção de período
        let populatedStore = makeIsolatedStore(seedStatement: true)
        let debtReply = LocalLLMService.generateFinancialResponse(
            for: "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida Cartão Mercado Pago?",
            store: populatedStore,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(debtReply.localizedCaseInsensitiveContains("Cartão Mercado Pago"))

        let projectionReply = LocalLLMService.generateFinancialResponse(
            for: "Analise os dados de 01/01/2026 até 01/12/2026, faça uma projeção de quando entrarei em débito no futuro",
            store: populatedStore,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(projectionReply.localizedCaseInsensitiveContains("01/01/2026"))
        XCTAssertTrue(projectionReply.localizedCaseInsensitiveContains("01/12/2026"))
    }

    func testSantanderLoanDocumentImportAndOutstandingBalance() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Santander", bankPresetId: "santander", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC0000", initialBalance: 0.0)
        let acc = store.accounts.first!

        let parsed = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.santanderLoanOCRText,
            expectedKind: .loan
        )

        XCTAssertEqual(parsed.kind, .loan)
        XCTAssertEqual(parsed.contractNumber, "783694303")
        XCTAssertEqual(parsed.loanSubtype, .consignado)
        XCTAssertEqual(parsed.totalContractedAmount, 110108.13, accuracy: 0.01)
        XCTAssertEqual(parsed.outstandingBalance, 91039.22, accuracy: 0.01)
        XCTAssertEqual(parsed.installmentAmount, 4509.81, accuracy: 0.01)
        XCTAssertEqual(parsed.billingDay, 25)
        XCTAssertEqual(parsed.totalInstallments, 36)
        XCTAssertEqual(parsed.paidInstallmentsCount, 10)
        XCTAssertEqual(parsed.remainingInstallmentsCount, 26)
        XCTAssertEqual(parsed.monthlyInterestRate, 2.0087, accuracy: 0.001)
        XCTAssertEqual(BRLFormatters.shortDate(parsed.startDate), "30/10/2025")
        XCTAssertEqual(BRLFormatters.shortDate(parsed.firstFutureBillingDate), "25/11/2026")

        let contract = store.createCreditContract(
            kind: .loan,
            name: parsed.name,
            contractNumber: parsed.contractNumber,
            loanSubtype: parsed.loanSubtype,
            financingSubtype: parsed.financingSubtype,
            amortizationSystem: parsed.amortizationSystem,
            totalContractedAmount: parsed.totalContractedAmount,
            outstandingBalance: parsed.outstandingBalance,
            installmentAmount: parsed.installmentAmount,
            billingDay: parsed.billingDay,
            totalInstallments: parsed.totalInstallments,
            monthlyInterestRate: parsed.monthlyInterestRate,
            startDate: parsed.startDate,
            accountId: acc.id,
            overridePastInstallmentsCount: parsed.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsed.firstFutureBillingDate
        )

        XCTAssertEqual(contract.contractNumber, "783694303")
        XCTAssertEqual(contract.pastInstallmentsElapsedAtCreation, 10)
        XCTAssertEqual(store.currentOutstandingBalance(for: contract), 91039.22, accuracy: 0.01)

        let futureTxs = store.unpaidTransactions(forContract: contract.id)
        XCTAssertEqual(futureTxs.count, 26)
        XCTAssertEqual(BRLFormatters.shortDate(futureTxs.first!.date), "25/11/2026")
        XCTAssertEqual(BRLFormatters.shortDate(futureTxs.last!.date), "25/12/2028")
    }

    func testCaixaFinancingDocumentImportAndOutstandingBalance() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "CAIXA", bankPresetId: "caixa", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#005CA9", initialBalance: 0.0)
        let acc = store.accounts.first!

        let parsed = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.caixaFinancingOCRText,
            expectedKind: .financing
        )

        XCTAssertEqual(parsed.kind, .financing)
        XCTAssertEqual(parsed.contractNumber, "178770203328-1")
        XCTAssertEqual(parsed.financingSubtype, .imovel)
        XCTAssertEqual(parsed.amortizationSystem, .price)
        XCTAssertEqual(parsed.outstandingBalance, 324737.86, accuracy: 0.01)
        XCTAssertEqual(parsed.installmentAmount, 2658.04, accuracy: 0.01)
        XCTAssertEqual(parsed.billingDay, 5)
        XCTAssertEqual(parsed.totalInstallments, 360)
        XCTAssertEqual(parsed.paidInstallmentsCount, 28)
        XCTAssertEqual(parsed.remainingInstallmentsCount, 332)
        XCTAssertEqual(BRLFormatters.shortDate(parsed.startDate), "05/07/2024")
        XCTAssertEqual(BRLFormatters.shortDate(parsed.firstFutureBillingDate), "05/12/2026")

        let contract = store.createCreditContract(
            kind: .financing,
            name: parsed.name,
            contractNumber: parsed.contractNumber,
            loanSubtype: parsed.loanSubtype,
            financingSubtype: parsed.financingSubtype,
            amortizationSystem: parsed.amortizationSystem,
            totalContractedAmount: parsed.totalContractedAmount,
            outstandingBalance: parsed.outstandingBalance,
            installmentAmount: parsed.installmentAmount,
            billingDay: parsed.billingDay,
            totalInstallments: parsed.totalInstallments,
            monthlyInterestRate: parsed.monthlyInterestRate,
            startDate: parsed.startDate,
            accountId: acc.id,
            overridePastInstallmentsCount: parsed.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsed.firstFutureBillingDate
        )

        XCTAssertEqual(contract.contractNumber, "178770203328-1")
        XCTAssertEqual(contract.pastInstallmentsElapsedAtCreation, 28)
        XCTAssertEqual(store.currentOutstandingBalance(for: contract), 324737.86, accuracy: 0.01)

        let futureTxs = store.unpaidTransactions(forContract: contract.id)
        XCTAssertEqual(futureTxs.count, 332)
        XCTAssertEqual(BRLFormatters.shortDate(futureTxs.first!.date), "05/12/2026")
    }

    func testBRLCurrencyMaskAndDigitsOnlyFormatter() {
        XCTAssertEqual(BRLFormatters.formatCurrencyMaskedInput("450981"), "R$ 4.509,81")
        XCTAssertEqual(BRLFormatters.formatCurrencyMaskedInput("abc1250xyz!"), "R$ 12,50")
        XCTAssertEqual(BRLFormatters.formatCurrencyMaskedInput("R$ 91.039,22"), "R$ 91.039,22")
        XCTAssertEqual(BRLFormatters.formatCurrencyMaskedInput("00"), "")
        XCTAssertEqual(BRLFormatters.parseAmount("R$ 91.039,22") ?? 0, 91039.22, accuracy: 0.001)
        XCTAssertEqual(BRLFormatters.formatDigitsOnly("36x meses"), "36")

        // Verifica que o input nativo é clicável em toda a sua extensão (esquerda, centro, direita)
        // e que o placeholder some imediatamente quando um valor é inserido
        let wrapper = ClickableFieldWrapperNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        wrapper.placeholderLabel.stringValue = "R$ 0,00"
        wrapper.textField.stringValue = ""
        wrapper.updatePlaceholderVisibility()
        XCTAssertFalse(wrapper.placeholderLabel.isHidden, "Placeholder deve aparecer quando vazio")

        // HitTest na esquerda, meio e direita deve retornar sempre o campo editável ativo
        XCTAssertTrue(wrapper.hitTest(NSPoint(x: 4, y: 14)) === wrapper.textField)
        XCTAssertTrue(wrapper.hitTest(NSPoint(x: 160, y: 14)) === wrapper.textField)
        XCTAssertTrue(wrapper.hitTest(NSPoint(x: 315, y: 14)) === wrapper.textField)

        // Ao inserir qualquer valor, o placeholder deve sumir imediatamente
        wrapper.textField.stringValue = "R$ 10,00"
        wrapper.updatePlaceholderVisibility()
        XCTAssertTrue(wrapper.placeholderLabel.isHidden, "Placeholder deve sumir assim que um valor for inserido")
    }
}
