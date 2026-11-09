import XCTest
@testable import FinSense

@MainActor
final class FinSenseTests: XCTestCase {

    private func makeIsolatedStore(seedStatement: Bool = false) -> FinancialDataStore {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FinSenseTests_\(UUID().uuidString)")
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
        // A projeção para quitar nunca pode ultrapassar o Saldo Devedor atual (R$ 324.737,86)
        XCTAssertEqual(store.projectedPayoffAmount(for: contract), 324737.86, accuracy: 0.01)
        XCTAssertLessThanOrEqual(store.projectedPayoffAmount(for: contract), store.currentOutstandingBalance(for: contract))

        let futureTxs = store.unpaidTransactions(forContract: contract.id)
        XCTAssertEqual(futureTxs.count, 332)
        XCTAssertEqual(BRLFormatters.shortDate(futureTxs.first!.date), "05/12/2026")
    }

    func testMultipleLoanImportsTotalizersAndCompleteTransactionRemovalOnDelete() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Santander", bankPresetId: "santander", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC0000", initialBalance: 10000.0)
        let acc = store.accounts.first!

        // 1. Importa o primeiro empréstimo (Santander Contrato 783694303: 26x R$ 4.509,81 = R$ 117.255,06, Saldo Devedor R$ 91.039,22)
        let parsed1 = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.santanderLoanOCRText,
            expectedKind: .loan
        )
        let loan1 = store.createCreditContract(
            kind: .loan,
            name: parsed1.name,
            contractNumber: parsed1.contractNumber,
            loanSubtype: parsed1.loanSubtype,
            amortizationSystem: parsed1.amortizationSystem,
            totalContractedAmount: parsed1.totalContractedAmount,
            outstandingBalance: parsed1.outstandingBalance,
            installmentAmount: parsed1.installmentAmount,
            billingDay: parsed1.billingDay,
            totalInstallments: parsed1.totalInstallments,
            monthlyInterestRate: parsed1.monthlyInterestRate,
            startDate: parsed1.startDate,
            accountId: acc.id,
            overridePastInstallmentsCount: parsed1.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsed1.firstFutureBillingDate
        )

        // 2. Importa um segundo empréstimo com valores distintos no formato DDC Santander
        let secondLoanOCR = """
        Santander DOCUMENTO DESCRITIVO DE CRÉDITO
        Data de Emissão: 05/11/2026
        Produto: CREDITO CONSIGNADO Número do Contrato: 998877665
        Data de Início da Operação: 15/05/2026 Quantidade Total de Parcelas: 24
        Valor Solicitado: R$ 20.000,00 Valor Total Financiado: R$ 21.500,00
        Taxa Efetiva Mensal: 1,50% Taxa Efetiva Anual: 19,56%
        Dívida para Liquidação: R$ 16.200,00
        01 15/06/2026 Paga 1.050,00 1.050,00
        02 15/07/2026 Paga 1.050,00 1.050,00
        03 15/08/2026 Paga 1.050,00 1.050,00
        04 15/09/2026 Paga 1.050,00 1.050,00
        05 15/10/2026 Paga 1.050,00 1.050,00
        06 15/11/2026 A Vencer 1.050,00 0,00
        Soma Vlr. Parcelas: (19.950,00) Soma Saldo Devedor D0: (16.200,00)
        """
        let parsed2 = ContractDocumentImportService.parseContractDocumentText(
            secondLoanOCR,
            expectedKind: .loan
        )
        XCTAssertEqual(parsed2.contractNumber, "998877665")
        XCTAssertEqual(parsed2.totalInstallments, 24)
        XCTAssertEqual(parsed2.paidInstallmentsCount, 5)
        XCTAssertEqual(parsed2.remainingInstallmentsCount, 19)
        XCTAssertEqual(parsed2.installmentAmount, 1050.0, accuracy: 0.01)
        XCTAssertEqual(parsed2.outstandingBalance, 16200.0, accuracy: 0.01)

        let loan2 = store.createCreditContract(
            kind: .loan,
            name: parsed2.name,
            contractNumber: parsed2.contractNumber,
            loanSubtype: parsed2.loanSubtype,
            amortizationSystem: parsed2.amortizationSystem,
            totalContractedAmount: parsed2.totalContractedAmount,
            outstandingBalance: parsed2.outstandingBalance,
            installmentAmount: parsed2.installmentAmount,
            billingDay: parsed2.billingDay,
            totalInstallments: parsed2.totalInstallments,
            monthlyInterestRate: parsed2.monthlyInterestRate,
            startDate: parsed2.startDate,
            accountId: acc.id,
            overridePastInstallmentsCount: parsed2.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsed2.firstFutureBillingDate
        )

        // Verifica que cada empréstimo tem seu próprio cálculo isolado
        XCTAssertEqual(store.remainingNominalAmount(for: loan1), 117255.06, accuracy: 0.01)
        XCTAssertEqual(store.projectedPayoffAmount(for: loan1), 91039.22, accuracy: 0.01)

        XCTAssertEqual(store.remainingNominalAmount(for: loan2), 19950.00, accuracy: 0.01)
        XCTAssertEqual(store.projectedPayoffAmount(for: loan2), 16200.00, accuracy: 0.01)

        // Marca uma parcela do primeiro empréstimo como paga (na data da cobrança) para garantir que até transações pagas do empréstimo sejam removidas ao excluir o empréstimo
        if let firstTxLoan1 = store.transactions.first(where: { $0.linkedContractId == loan1.id }) {
            _ = store.toggleTransactionPaid(firstTxLoan1.id, referenceNow: firstTxLoan1.date)
        }

        // 3. Deleta o primeiro empréstimo
        store.deleteContract(loan1.id)

        // Todas as transações do primeiro empréstimo (pagas ou não) devem ter sido removidas
        XCTAssertTrue(store.transactions.filter { $0.linkedContractId == loan1.id }.isEmpty)
        XCTAssertEqual(store.activeContracts(for: .loan).count, 1)

        // Os totalizadores (Soma Nominal, Projeção para Quitar Hoje e Economia) devem refletir exclusivamente o segundo empréstimo
        let activeLoans = store.activeContracts(for: .loan)
        let totalNominal = activeLoans.reduce(0.0) { $0 + store.remainingNominalAmount(for: $1) }
        let totalProjected = activeLoans.reduce(0.0) { $0 + store.projectedPayoffAmount(for: $1) }
        let totalSavings = max(totalNominal - totalProjected, 0)

        XCTAssertEqual(totalNominal, 19950.00, accuracy: 0.01)
        XCTAssertEqual(totalProjected, 16200.00, accuracy: 0.01)
        XCTAssertEqual(totalSavings, 3750.00, accuracy: 0.01)
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

    func testRecurringExpensesAndIncomesSeriesEditScopesFuturePayBlockAndAnnualProjection() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Itaú", bankPresetId: "itau", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC7000", initialBalance: 1000.0)
        store.addAccount(name: "Nubank", bankPresetId: "nubank", customImagePath: nil, iconSymbol: "creditcard.fill", colorHex: "#820AD1", initialBalance: 500.0)
        let acc1 = store.accounts[0]
        let acc2 = store.accounts[1]
        let expCat = store.fallbackCategoryId(for: .expense)
        let incCat = store.fallbackCategoryId(for: .income)

        let refToday = BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!

        // 1. Verifica que a data padrão para nova transação aponta sempre para o mês filtrado
        let march2027 = BRLFormatters.shortDateFormatter.date(from: "01/03/2027")!
        store.selectedMonth = march2027
        let defaultDateInFilteredMonth = store.defaultTransactionDateForSelectedMonth(today: refToday)
        XCTAssertTrue(store.isInMonth(defaultDateInFilteredMonth, monthReference: march2027))
        XCTAssertEqual(BRLFormatters.shortDate(defaultDateInFilteredMonth), "06/03/2027")

        // 2. Pagar uma conta com data no futuro é permitido, mas a transação é movida para a data atual
        let futureTxCreated = store.createTransaction(
            name: "Conta no Futuro",
            amount: 250.0,
            date: defaultDateInFilteredMonth,
            type: .expense,
            isPaid: false,
            categoryId: expCat,
            accountId: acc1.id,
            recurrenceMode: .single,
            referenceNow: refToday
        ).first!
        XCTAssertFalse(futureTxCreated.isPaid)
        XCTAssertEqual(BRLFormatters.shortDate(futureTxCreated.date), "06/03/2027")

        XCTAssertTrue(store.toggleTransactionPaid(futureTxCreated.id, referenceNow: refToday))
        let paidNow = store.transactions.first(where: { $0.id == futureTxCreated.id })!
        XCTAssertTrue(paidNow.isPaid)
        XCTAssertEqual(BRLFormatters.shortDate(paidNow.date), "06/11/2026", "Ao pagar no futuro, a transação deve ser movida para hoje")

        // Desfazer pagamento volta para não paga (mantendo a data atual)
        XCTAssertTrue(store.toggleTransactionPaid(futureTxCreated.id, referenceNow: refToday))
        XCTAssertFalse(store.transactions.first(where: { $0.id == futureTxCreated.id })!.isPaid)

        // Criar já marcada como paga com data futura também move para hoje
        let createdPaidFuture = store.createTransaction(
            name: "Conta Paga Antecipada",
            amount: 80.0,
            date: defaultDateInFilteredMonth,
            type: .expense,
            isPaid: true,
            categoryId: expCat,
            accountId: acc1.id,
            recurrenceMode: .single,
            referenceNow: refToday
        ).first!
        XCTAssertTrue(createdPaidFuture.isPaid)
        XCTAssertEqual(BRLFormatters.shortDate(createdPaidFuture.date), "06/11/2026")

        // Remove os lançamentos auxiliares para não interferir nas projeções abaixo
        store.deleteTransaction(futureTxCreated.id)
        store.deleteTransaction(createdPaidFuture.id)

        // 3. Cria pagamento recorrente mensal (Netflix) e anual (Prime Video) + recebimento recorrente mensal (Salário)
        let netflixSeries = store.createTransaction(
            name: "Netflix",
            amount: 55.90,
            date: refToday,
            type: .expense,
            isPaid: true,
            categoryId: expCat,
            accountId: acc1.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .monthly,
            referenceNow: refToday
        )
        XCTAssertGreaterThanOrEqual(netflixSeries.count, 12)
        XCTAssertTrue(netflixSeries.first!.isPaid)
        XCTAssertFalse(netflixSeries[1].isPaid)

        let primeSeries = store.createTransaction(
            name: "Prime Video",
            amount: 166.80,
            date: refToday,
            type: .expense,
            isPaid: true,
            categoryId: expCat,
            accountId: acc1.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .annual,
            referenceNow: refToday
        )
        XCTAssertGreaterThanOrEqual(primeSeries.count, 5)

        let salarySeries = store.createTransaction(
            name: "Salário Recorrente",
            amount: 5000.0,
            date: refToday,
            type: .income,
            isPaid: true,
            categoryId: incCat,
            accountId: acc1.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .monthly,
            referenceNow: refToday
        )
        XCTAssertGreaterThanOrEqual(salarySeries.count, 12)

        // 4. Testa os 3 escopos de edição de valor para séries (somente naquela, da atual e futuras, em todas)
        // 4a. Somente naquela transação (.onlyThis)
        var thirdNetflix = store.transactions
            .filter { $0.seriesGroupId == netflixSeries.first!.seriesGroupId }
            .sorted { $0.date < $1.date }[2]
        thirdNetflix.amount = 65.90
        store.updateTransaction(thirdNetflix, scope: .onlyThis, referenceNow: refToday)

        let afterOnlyThis = store.transactions
            .filter { $0.seriesGroupId == netflixSeries.first!.seriesGroupId }
            .sorted { $0.date < $1.date }
        XCTAssertEqual(afterOnlyThis[0].amount, 55.90, accuracy: 0.01)
        XCTAssertEqual(afterOnlyThis[1].amount, 55.90, accuracy: 0.01)
        XCTAssertEqual(afterOnlyThis[2].amount, 65.90, accuracy: 0.01)
        XCTAssertEqual(afterOnlyThis[3].amount, 55.90, accuracy: 0.01)

        // 4b. Da transação atual e todas no futuro (.thisAndFuture)
        var fourthNetflix = afterOnlyThis[3]
        fourthNetflix.amount = 79.90
        store.updateTransaction(fourthNetflix, scope: .thisAndFuture, referenceNow: refToday)

        let afterThisAndFuture = store.transactions
            .filter { $0.seriesGroupId == netflixSeries.first!.seriesGroupId }
            .sorted { $0.date < $1.date }
        XCTAssertEqual(afterThisAndFuture[0].amount, 55.90, accuracy: 0.01)
        XCTAssertEqual(afterThisAndFuture[2].amount, 65.90, accuracy: 0.01)
        XCTAssertEqual(afterThisAndFuture[3].amount, 79.90, accuracy: 0.01)
        XCTAssertEqual(afterThisAndFuture[4].amount, 79.90, accuracy: 0.01)

        // 4c. Alterar em todas as parcelas/ocorrências (.allInSeries) — inclusive para Recebimento Recorrente
        var secondSalary = store.transactions
            .filter { $0.seriesGroupId == salarySeries.first!.seriesGroupId }
            .sorted { $0.date < $1.date }[1]
        secondSalary.amount = 5500.0
        store.updateTransaction(secondSalary, scope: .allInSeries, referenceNow: refToday)

        let allSalaries = store.transactions.filter { $0.seriesGroupId == salarySeries.first!.seriesGroupId }
        XCTAssertTrue(allSalaries.allSatisfy { abs($0.amount - 5500.0) < 0.01 })

        // 5. Reordenação de Contas e Categorias (Drag and Drop)
        XCTAssertEqual(store.accounts.map(\.id), [acc1.id, acc2.id])
        store.moveAccount(draggedId: acc2.id, targetId: acc1.id)
        XCTAssertEqual(store.accounts.map(\.id), [acc2.id, acc1.id])

        let expCatsBefore = store.categories(for: .expense)
        if expCatsBefore.count >= 2 {
            let firstCatId = expCatsBefore[0].id
            let secondCatId = expCatsBefore[1].id
            store.moveCategory(draggedId: secondCatId, targetId: firstCatId)
            let expCatsAfter = store.categories(for: .expense)
            XCTAssertEqual(expCatsAfter[0].id, secondCatId)
            XCTAssertEqual(expCatsAfter[1].id, firstCatId)
        }

        // 6. Visão Anual no Dashboard: projeção até o último dia do ano (31/12/2026)
        let annualInc2026 = store.annualIncome(for: refToday)
        let annualExp2026 = store.annualExpense(for: refToday)
        let projectedEnd2026 = store.accumulatedConsolidatedBalanceThroughYear(refToday)
        // Em Nov e Dez de 2026 há 2 meses de Salário (2 * 5500 = 11000)
        XCTAssertEqual(annualInc2026, 11000.0, accuracy: 0.01)
        // Em Nov e Dez de 2026 há 2 meses de Netflix (55.90 + 55.90) + 1 Prime Video anual (166.80) = 278.60
        XCTAssertEqual(annualExp2026, 278.60, accuracy: 0.01)
        XCTAssertEqual(projectedEnd2026, 1500.0 + 11000.0 - 278.60, accuracy: 0.01)
    }

    func testIntelligentTransactionsAndDebtsImportWithStrictSeparation() {
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
        let refDate = BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!

        let combinedSampleText = """
        Dívidas:
        Cartão de crédito Carrefour: 6196
        Cartão de crédito inter - 6220
        Cartão de crédito Sam’s - 1681
        Cartão de crédito Nubank - 7242
        Cartão de crédito Mercado pago - 5951
        Cartão de crédito Santander - 29414,8


        Despesas
        Faculdade FIAP - dia 05 - 996 - 7 parcelas - a partir de dezembro (Educação)
        MBA FIAP - dia 05 - 840 - 22 parcelas a partir de dezembro (Educação)
        Cabeleleiro - dia 15 - 190 - fixo a partir de dezembro (Cuidado pessoal)
        Ração de cachorro - dia 25 - 260 - fixo a partir de dezembro (Pets)


        Receitas
        Salario Vivo - dia 2 - 14.400,00 - fixo a partir de dezembro (salario)
        """

        let debtsOnlySampleText = """
        Cartão de crédito Carrefour: 6196
        Cartão de crédito inter - 6220
        Cartão de crédito Sam’s - 1681
        Cartão de crédito Nubank - 7242
        Cartão de crédito Mercado pago - 5951
        Cartão de crédito Santander - 29414,8
        """

        // 1. A importação em transações e dashboard deve aceitar APENAS transações (ignorando a seção Dívidas)
        let parsedTransactionsFromCombined = StatementImportService.parseStatementText(
            combinedSampleText,
            categories: store.categories,
            filterMode: .hybrid,
            referenceDate: refDate
        )
        XCTAssertEqual(parsedTransactionsFromCombined.count, 5)
        XCTAssertFalse(parsedTransactionsFromCombined.contains(where: { $0.cleanTitle.localizedCaseInsensitiveContains("Carrefour") }))
        XCTAssertFalse(parsedTransactionsFromCombined.contains(where: { $0.cleanTitle.localizedCaseInsensitiveContains("Santander") }))

        // E se tentar importar um arquivo contendo APENAS dívidas na tela de Transações/Dashboard, deve retornar 0 transações
        let parsedTransactionsFromDebtsOnly = StatementImportService.parseStatementText(
            debtsOnlySampleText,
            categories: store.categories,
            filterMode: .hybrid,
            referenceDate: refDate
        )
        XCTAssertTrue(parsedTransactionsFromDebtsOnly.isEmpty)

        // Verifica detalhes extraídos de cada uma das 5 transações (Faculdade FIAP, MBA FIAP, Cabeleleiro, Ração de cachorro, Salario Vivo)
        let fiap = parsedTransactionsFromCombined.first(where: { $0.cleanTitle == "Faculdade FIAP" })!
        XCTAssertEqual(fiap.amount, 996.0, accuracy: 0.01)
        XCTAssertEqual(fiap.recurrenceMode, .installment)
        XCTAssertEqual(fiap.installmentsCount, 7)
        XCTAssertEqual(BRLFormatters.shortDate(fiap.date), "05/12/2026")
        XCTAssertEqual(fiap.type, .expense)

        let mba = parsedTransactionsFromCombined.first(where: { $0.cleanTitle == "MBA FIAP" })!
        XCTAssertEqual(mba.amount, 840.0, accuracy: 0.01)
        XCTAssertEqual(mba.recurrenceMode, .installment)
        XCTAssertEqual(mba.installmentsCount, 22)
        XCTAssertEqual(BRLFormatters.shortDate(mba.date), "05/12/2026")
        XCTAssertEqual(mba.type, .expense)

        let cabeleleiro = parsedTransactionsFromCombined.first(where: { $0.cleanTitle == "Cabeleleiro" })!
        XCTAssertEqual(cabeleleiro.amount, 190.0, accuracy: 0.01)
        XCTAssertEqual(cabeleleiro.recurrenceMode, .recurring)
        XCTAssertEqual(BRLFormatters.shortDate(cabeleleiro.date), "15/12/2026")

        let racao = parsedTransactionsFromCombined.first(where: { $0.cleanTitle == "Ração de cachorro" })!
        XCTAssertEqual(racao.amount, 260.0, accuracy: 0.01)
        XCTAssertEqual(racao.recurrenceMode, .recurring)
        XCTAssertEqual(BRLFormatters.shortDate(racao.date), "25/12/2026")

        let salario = parsedTransactionsFromCombined.first(where: { $0.cleanTitle == "Salario Vivo" })!
        XCTAssertEqual(salario.amount, 14400.0, accuracy: 0.01)
        XCTAssertEqual(salario.recurrenceMode, .recurring)
        XCTAssertEqual(BRLFormatters.shortDate(salario.date), "02/12/2026")
        XCTAssertEqual(salario.type, .income)

        // Confirma a importação das transações no store e valida a geração das parcelas e séries recorrentes em Dezembro/2026
        let txImportSummary = store.importParsedTransactions(
            parsedTransactionsFromCombined,
            intoAccountId: itauAccount.id,
            filterMode: .hybrid
        )
        XCTAssertEqual(txImportSummary.addedCount, 5)
        XCTAssertEqual(txImportSummary.addedExpenses, 4)
        XCTAssertEqual(txImportSummary.addedIncomes, 1)

        let fiapInstallmentsInStore = store.transactions.filter { $0.name.hasPrefix("Faculdade FIAP (") }
        XCTAssertEqual(fiapInstallmentsInStore.count, 7)
        XCTAssertTrue(fiapInstallmentsInStore.allSatisfy { abs($0.amount - 996.0) < 0.01 })

        let mbaInstallmentsInStore = store.transactions.filter { $0.name.hasPrefix("MBA FIAP (") }
        XCTAssertEqual(mbaInstallmentsInStore.count, 22)
        XCTAssertTrue(mbaInstallmentsInStore.allSatisfy { abs($0.amount - 840.0) < 0.01 })

        let dec2026Date = BRLFormatters.shortDateFormatter.date(from: "15/12/2026")!
        let dec2026Transactions = store.transactionsForMonth(dec2026Date)
        XCTAssertEqual(dec2026Transactions.count, 5)
        XCTAssertEqual(store.monthlyIncome(for: dec2026Date), 14400.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyExpense(for: dec2026Date), 996.0 + 840.0 + 190.0 + 260.0, accuracy: 0.01)

        // Deduplicação ao importar novamente o mesmo arquivo de transações
        let duplicateTxSummary = store.importParsedTransactions(
            parsedTransactionsFromCombined,
            intoAccountId: itauAccount.id,
            filterMode: .hybrid
        )
        XCTAssertEqual(duplicateTxSummary.addedCount, 0)
        XCTAssertEqual(duplicateTxSummary.skippedDuplicatesCount, 5)

        // 2. A importação em Dívidas deve aceitar APENAS dívidas (ignorando Despesas e Receitas)
        let parsedDebtsFromCombined = DebtImportService.parseDebtsText(combinedSampleText)
        XCTAssertEqual(parsedDebtsFromCombined.count, 6)

        let parsedDebtsFromPureDebts = DebtImportService.parseDebtsText(debtsOnlySampleText)
        XCTAssertEqual(parsedDebtsFromPureDebts.count, 6)

        XCTAssertEqual(parsedDebtsFromPureDebts[0].name, "Cartão de crédito Carrefour")
        XCTAssertEqual(parsedDebtsFromPureDebts[0].originalAmount, 6196.0, accuracy: 0.01)

        XCTAssertEqual(parsedDebtsFromPureDebts[1].name, "Cartão de crédito inter")
        XCTAssertEqual(parsedDebtsFromPureDebts[1].originalAmount, 6220.0, accuracy: 0.01)
        XCTAssertEqual(parsedDebtsFromPureDebts[1].bankPresetId, "inter")

        XCTAssertEqual(parsedDebtsFromPureDebts[2].name, "Cartão de crédito Sam’s")
        XCTAssertEqual(parsedDebtsFromPureDebts[2].originalAmount, 1681.0, accuracy: 0.01)

        XCTAssertEqual(parsedDebtsFromPureDebts[3].name, "Cartão de crédito Nubank")
        XCTAssertEqual(parsedDebtsFromPureDebts[3].originalAmount, 7242.0, accuracy: 0.01)
        XCTAssertEqual(parsedDebtsFromPureDebts[3].bankPresetId, "nubank")

        XCTAssertEqual(parsedDebtsFromPureDebts[4].name, "Cartão de crédito Mercado pago")
        XCTAssertEqual(parsedDebtsFromPureDebts[4].originalAmount, 5951.0, accuracy: 0.01)
        XCTAssertEqual(parsedDebtsFromPureDebts[4].bankPresetId, "mercadopago")

        XCTAssertEqual(parsedDebtsFromPureDebts[5].name, "Cartão de crédito Santander")
        XCTAssertEqual(parsedDebtsFromPureDebts[5].originalAmount, 29414.80, accuracy: 0.01)
        XCTAssertEqual(parsedDebtsFromPureDebts[5].bankPresetId, "santander")

        let debtImportSummary = store.importParsedDebts(parsedDebtsFromPureDebts)
        XCTAssertEqual(debtImportSummary.addedCount, 6)
        XCTAssertEqual(debtImportSummary.skippedDuplicatesCount, 0)
        XCTAssertEqual(store.activeDebts.count, 6)

        let totalImportedDebts = store.activeDebts.reduce(0.0) { $0 + $1.originalAmount }
        XCTAssertEqual(totalImportedDebts, 6196.0 + 6220.0 + 1681.0 + 7242.0 + 5951.0 + 29414.80, accuracy: 0.01)

        // Deduplicação ao importar novamente as mesmas dívidas
        let secondDebtImportSummary = store.importParsedDebts(parsedDebtsFromCombined)
        XCTAssertEqual(secondDebtImportSummary.addedCount, 0)
        XCTAssertEqual(secondDebtImportSummary.skippedDuplicatesCount, 6)
    }

    func testSeriesDeleteScopesForInstallmentRepeatedAndRecurring() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Itaú",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 0.0
        )
        let acc = store.accounts.first!
        let expCat = store.fallbackCategoryId(for: .expense)
        let refNow = BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!

        // 1. Parcelado (6 parcelas): testa "Remover somente esta", "Remover esta e as pendentes" e "Remover todas"
        let installments = store.createTransaction(
            name: "Curso Especialização",
            amount: 6000.0,
            date: refNow,
            type: .expense,
            isPaid: true,
            categoryId: expCat,
            accountId: acc.id,
            recurrenceMode: .installment,
            installmentsOrMonthsCount: 6,
            referenceNow: refNow
        )
        XCTAssertEqual(installments.count, 6)
        let instGroupId = installments.first!.seriesGroupId!

        // 1a. "Remover somente esta" na parcela 2/6
        let secondInst = installments[1]
        store.deleteTransaction(secondInst.id, scope: .onlyThis)
        let remainingAfterOnlyThis = store.transactions
            .filter { $0.seriesGroupId == instGroupId }
            .sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }
        XCTAssertEqual(remainingAfterOnlyThis.map { $0.installmentIndex ?? 0 }, [1, 3, 4, 5, 6])

        // 1b. "Remover esta e as pendentes" na parcela 4/6 -> remove 4, 5 e 6, mantendo 1 (paga) e 3 (anterior a 4)
        let fourthInst = remainingAfterOnlyThis.first(where: { $0.installmentIndex == 4 })!
        store.deleteTransaction(fourthInst.id, scope: .thisAndPending)
        let remainingAfterThisAndPending = store.transactions
            .filter { $0.seriesGroupId == instGroupId }
            .sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }
        XCTAssertEqual(remainingAfterThisAndPending.map { $0.installmentIndex ?? 0 }, [1, 3])

        // 1c. "Remover todas" -> remove todas as parcelas restantes da série
        let firstInst = remainingAfterThisAndPending.first!
        store.deleteTransaction(firstInst.id, scope: .allInSeries)
        XCTAssertTrue(store.transactions.filter { $0.seriesGroupId == instGroupId }.isEmpty)

        // 2. Recorrente: "Remover esta e as pendentes" remove a selecionada + futuras pendentes e encerra a recorrência
        let recurringSeries = store.createTransaction(
            name: "Wellhub Mensal",
            amount: 129.90,
            date: refNow,
            type: .expense,
            isPaid: true,
            categoryId: expCat,
            accountId: acc.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .monthly,
            referenceNow: refNow
        )
        let recGroupId = recurringSeries.first!.seriesGroupId!
        let sortedRecurring = store.transactions
            .filter { $0.seriesGroupId == recGroupId }
            .sorted { $0.date < $1.date }
        XCTAssertGreaterThanOrEqual(sortedRecurring.count, 12)

        // Deleta a partir da 3ª ocorrência com "Remover esta e as pendentes"
        store.deleteTransaction(sortedRecurring[2].id, scope: .thisAndPending)
        let recRemaining = store.transactions
            .filter { $0.seriesGroupId == recGroupId }
            .sorted { $0.date < $1.date }
        XCTAssertEqual(recRemaining.count, 2)
        XCTAssertTrue(recRemaining.allSatisfy { $0.isCanceledRecurringSeries == true })

        // Navegar para anos futuros não deve recriar a série recorrente encerrada
        store.changeYear(by: 2)
        XCTAssertEqual(store.transactions.filter { $0.seriesGroupId == recGroupId }.count, 2)
    }

    func testTransactionSortOrdersAndEditedImportItems() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(name: "Itaú", bankPresetId: "itau", customImagePath: nil, iconSymbol: "building.columns.fill", colorHex: "#EC7000", initialBalance: 0.0)
        let acc = store.accounts.first!
        let expCat = store.fallbackCategoryId(for: .expense)
        let refNow = BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!

        let a = store.createTransaction(name: "A", amount: 300, date: BRLFormatters.shortDateFormatter.date(from: "01/11/2026")!, type: .expense, isPaid: true, categoryId: expCat, accountId: acc.id, referenceNow: refNow).first!
        let b = store.createTransaction(name: "B", amount: 100, date: BRLFormatters.shortDateFormatter.date(from: "03/11/2026")!, type: .expense, isPaid: true, categoryId: expCat, accountId: acc.id, referenceNow: refNow).first!
        let c = store.createTransaction(name: "C", amount: 200, date: BRLFormatters.shortDateFormatter.date(from: "02/11/2026")!, type: .expense, isPaid: true, categoryId: expCat, accountId: acc.id, referenceNow: refNow).first!
        let all = store.transactions

        XCTAssertEqual(TransactionSortOrder.dateAscending.sort(all).map(\.id), [a.id, c.id, b.id])
        XCTAssertEqual(TransactionSortOrder.dateDescending.sort(all).map(\.id), [b.id, c.id, a.id])
        XCTAssertEqual(TransactionSortOrder.amountAscending.sort(all).map(\.id), [b.id, c.id, a.id])
        XCTAssertEqual(TransactionSortOrder.amountDescending.sort(all).map(\.id), [a.id, c.id, b.id])

        // Item editado antes da importação: categoria manual prevalece sobre a categoria explícita do texto
        var parsed = StatementImportService.parseStatementText(
            "Despesas\nCabeleleiro - dia 15 - 190 - fixo a partir de dezembro (Cuidado pessoal)",
            categories: store.categories,
            filterMode: .hybrid,
            referenceDate: refNow
        )
        XCTAssertEqual(parsed.count, 1)
        let healthCat = store.fallbackCategoryId(for: .expense, matchingSubstring: "Saúde")
        parsed[0].cleanTitle = "Barbearia"
        parsed[0].amount = 210
        parsed[0].suggestedCategoryId = healthCat
        parsed[0].explicitCategoryName = nil
        parsed[0].recurrenceMode = .single

        let summary = store.importParsedTransactions(parsed, intoAccountId: acc.id, filterMode: .hybrid)
        XCTAssertEqual(summary.addedCount, 1)
        let imported = store.transactions.first(where: { $0.name == "Barbearia" })!
        XCTAssertEqual(imported.amount, 210, accuracy: 0.01)
        XCTAssertEqual(imported.categoryId, healthCat)
        XCTAssertEqual(imported.recurrenceMode, .single)
    }

    func testPreferencesStorageKeysForGroupByDayAndShowTextInputBox() {
        let defaults = UserDefaults.standard
        let groupByKey = "transactions_group_by_day"
        let importTextBoxKey = "import_show_text_input_box"

        let prevGroupByDay = defaults.object(forKey: groupByKey)
        let prevImportBox = defaults.object(forKey: importTextBoxKey)

        defer {
            if let prevGroupByDay = prevGroupByDay {
                defaults.set(prevGroupByDay, forKey: groupByKey)
            } else {
                defaults.removeObject(forKey: groupByKey)
            }
            if let prevImportBox = prevImportBox {
                defaults.set(prevImportBox, forKey: importTextBoxKey)
            } else {
                defaults.removeObject(forKey: importTextBoxKey)
            }
        }

        // Sem valor prévio gravado, o bool(forKey:) do UserDefaults retorna false por padrão
        defaults.removeObject(forKey: groupByKey)
        defaults.removeObject(forKey: importTextBoxKey)
        XCTAssertFalse(defaults.bool(forKey: groupByKey))
        XCTAssertFalse(defaults.bool(forKey: importTextBoxKey))

        // Gravando a última escolha do usuário
        defaults.set(true, forKey: groupByKey)
        defaults.set(true, forKey: importTextBoxKey)
        XCTAssertTrue(defaults.bool(forKey: groupByKey))
        XCTAssertTrue(defaults.bool(forKey: importTextBoxKey))

        defaults.set(false, forKey: importTextBoxKey)
        XCTAssertFalse(defaults.bool(forKey: importTextBoxKey))
    }

    func testDynamicCategoryProvisionsAcceptanceCriteriaAndLLMCommands() {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Itaú Principal",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 1000.0
        )
        let acc = store.accounts.first!
        let nov2026 = BRLFormatters.shortDateFormatter.date(from: "10/11/2026")!
        let dec2026 = BRLFormatters.shortDateFormatter.date(from: "10/12/2026")!
        store.selectedMonth = nov2026

        let foodCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Alimentação") })!
        let fuelCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Combustível") })!

        // Critério 1: A criação de uma estimativa não altera o saldo operacional atual nem cria registros em "Todas as Transações"
        store.setCategoryProvision(
            categoryId: foodCat.id,
            estimatedAmount: 300.0,
            for: nov2026,
            repeatForFutureMonths: true
        )
        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertEqual(store.totalCheckingBalanceNow, 1000.0, accuracy: 0.01)
        XCTAssertEqual(store.totalConsolidatedPatrimonyNow, 1000.0, accuracy: 0.01)
        XCTAssertEqual(store.totalRemainingProvision(for: nov2026), 300.0, accuracy: 0.01)
        // Saldo Projetado de fim de mês considera a provisão restante (1000 - 300 = 700)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: nov2026, includeProjectedUnpaid: true), 700.0, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: nov2026, includeProjectedUnpaid: false), 1000.0, accuracy: 0.01)

        // Critério 2: Ao adicionar uma nova despesa real de R$ 50 em uma categoria provisionada de R$ 300,
        // a provisão restante do Dashboard cai imediatamente para R$ 250 e não há duplicação no saldo projetado.
        _ = store.createTransaction(
            name: "Lanche iFood",
            amount: 50.0,
            date: nov2026,
            type: .expense,
            isPaid: true,
            categoryId: foodCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false
        )
        let envAfter50 = store.provisionEnvelope(forCategory: foodCat.id, in: nov2026)!
        XCTAssertEqual(envAfter50.realizedExpense, 50.0, accuracy: 0.01)
        XCTAssertEqual(envAfter50.remainingProvision, 250.0, accuracy: 0.01)
        XCTAssertEqual(envAfter50.status, .normal)
        XCTAssertEqual(store.totalRemainingProvision(for: nov2026), 250.0, accuracy: 0.01)
        // Saldo operacional atual caiu para 950, mas o Saldo Projetado continua 700 (950 - 250 = 700, sem duplicar!)
        XCTAssertEqual(store.totalCheckingBalanceNow, 950.0, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: nov2026, includeProjectedUnpaid: true), 700.0, accuracy: 0.01)

        // Faixa de Alerta (entre 80% e 100%): adicionando mais R$ 200 (Total G_real = R$ 250 de R$ 300 -> 83.33%)
        _ = store.createTransaction(
            name: "Restaurante Domingo",
            amount: 200.0,
            date: nov2026,
            type: .expense,
            isPaid: false, // despesa pendente também abate a provisão!
            categoryId: foodCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false
        )
        let envWarning = store.provisionEnvelope(forCategory: foodCat.id, in: nov2026)!
        XCTAssertEqual(envWarning.realizedExpense, 250.0, accuracy: 0.01)
        XCTAssertEqual(envWarning.remainingProvision, 50.0, accuracy: 0.01)
        XCTAssertEqual(envWarning.status, .warning)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: nov2026, includeProjectedUnpaid: true), 700.0, accuracy: 0.01)

        // Critério 3: Ao atingir ou estourar a estimativa, a provisão remanescente torna-se zero
        // e o saldo projetado reflete apenas os gastos reais que constam no extrato.
        _ = store.createTransaction(
            name: "Jantar Especial",
            amount: 90.0,
            date: nov2026,
            type: .expense,
            isPaid: true,
            categoryId: foodCat.id,
            accountId: acc.id,
            ignoreInConsolidated: false
        )
        let envExceeded = store.provisionEnvelope(forCategory: foodCat.id, in: nov2026)!
        XCTAssertEqual(envExceeded.realizedExpense, 340.0, accuracy: 0.01)
        XCTAssertEqual(envExceeded.remainingProvision, 0.0, accuracy: 0.01)
        XCTAssertEqual(envExceeded.exceededAmount, 40.0, accuracy: 0.01)
        XCTAssertEqual(envExceeded.clampedProgressPercentage, 100.0, accuracy: 0.01)
        XCTAssertEqual(envExceeded.status, .exceeded)
        // Saldo projetado reflete apenas os R$ 340 reais: 1000 - 340 = 660
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: nov2026, includeProjectedUnpaid: true), 660.0, accuracy: 0.01)

        // Critério 4: Mudanças de mês respeitam as configurações de recorrência automática das previsões
        store.setCategoryProvision(
            categoryId: fuelCat.id,
            estimatedAmount: 400.0,
            for: nov2026,
            repeatForFutureMonths: false // Não repetir para dezembro
        )
        let decFoodEnv = store.provisionEnvelope(forCategory: foodCat.id, in: dec2026)
        let decFuelEnv = store.provisionEnvelope(forCategory: fuelCat.id, in: dec2026)
        XCTAssertNotNil(decFoodEnv)
        XCTAssertEqual(decFoodEnv?.estimatedAmount ?? 0, 300.0, accuracy: 0.01)
        XCTAssertEqual(decFoodEnv?.remainingProvision ?? 0, 300.0, accuracy: 0.01)
        XCTAssertNil(decFuelEnv)

        // Integração com IA Local (Chat): configurar e consultar previsões em linguagem natural
        let setReply = LocalLLMService.generateFinancialResponse(
            for: "Reserve R$ 500 para gasolina este mês",
            store: store,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(setReply.localizedCaseInsensitiveContains("Combustível"))
        XCTAssertEqual(store.provisionEnvelope(forCategory: fuelCat.id, in: nov2026)?.estimatedAmount ?? 0, 500.0, accuracy: 0.01)

        let queryReply = LocalLLMService.generateFinancialResponse(
            for: "Quanto ainda posso gastar com lanches em novembro?",
            store: store,
            modelLabel: "TestModel"
        )
        XCTAssertTrue(queryReply.localizedCaseInsensitiveContains("Alimentação"))
        XCTAssertTrue(queryReply.localizedCaseInsensitiveContains("Estourado"))
    }

    func testAdvancedCategoryQuotasLifecycleScopesAndEnvironmentIsolation() throws {
        // 1. Isolamento de Ambientes (Debug vs. Release)
        let tempAppSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinSenseEnvTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempAppSupport, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempAppSupport) }

        let releaseStore = FinancialDataStore(
            environment: .release,
            baseAppSupportDirectory: tempAppSupport,
            seedStatementOnFirstLaunch: false
        )
        releaseStore.addAccount(
            name: "Conta Produção",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 5000.0
        )

        let debugStore = FinancialDataStore(
            environment: .debug,
            baseAppSupportDirectory: tempAppSupport,
            seedStatementOnFirstLaunch: false
        )

        // Verifica que os diretórios e arquivos de banco são estritamente separados
        XCTAssertEqual(releaseStore.storageDirectory.lastPathComponent, "FinSense")
        XCTAssertEqual(releaseStore.databaseFileURL.lastPathComponent, "financial_database.json")
        XCTAssertEqual(debugStore.storageDirectory.lastPathComponent, "FinSense-Debug")
        XCTAssertEqual(debugStore.databaseFileURL.lastPathComponent, "financial_database_debug.json")
        XCTAssertNotEqual(releaseStore.databaseFileURL, debugStore.databaseFileURL)
        // Debug inicia limpo sem ler nem modificar os dados de produção
        XCTAssertEqual(releaseStore.accounts.count, 1)
        XCTAssertTrue(debugStore.accounts.isEmpty)

        // 2. Coexistência de Verba Livre + Cotas de Itens Específicos na mesma categoria
        debugStore.addAccount(
            name: "Conta Debug",
            bankPresetId: "nubank",
            customImagePath: nil,
            iconSymbol: "creditcard.fill",
            colorHex: "#820AD1",
            initialBalance: 1000.0
        )
        let debugAcc = debugStore.accounts.first!
        let housingCat = debugStore.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Moradia") })!
        let oct2026 = BRLFormatters.shortDateFormatter.date(from: "10/10/2026")!
        let nov2026 = BRLFormatters.shortDateFormatter.date(from: "10/11/2026")!
        let dec2026 = BRLFormatters.shortDateFormatter.date(from: "10/12/2026")!
        debugStore.selectedMonth = oct2026
        debugStore.simulatedCurrentDate = oct2026

        // Cadastra cota específica ("Galão de Água", 4 un. × R$ 30,00 = R$ 120,00) SEM teto de categoria inicialmente
        let waterQuota = debugStore.saveCategoryQuota(
            categoryId: housingCat.id,
            name: "Galão de Água",
            iconSymbol: "drop.fill",
            plannedQuantity: 4,
            estimatedUnitPrice: 30.0,
            for: oct2026,
            repeatForFutureMonths: true
        )
        // Sem teto de categoria configurado, Moradia NÃO possui CategoryProvisionEnvelope (desacoplamento total!)
        XCTAssertNil(debugStore.provisionEnvelope(forCategory: housingCat.id, in: oct2026))
        XCTAssertEqual(debugStore.totalQuotasRemaining(for: oct2026), 120.0, accuracy: 0.01)
        XCTAssertEqual(debugStore.totalCategoryProvisionsRemaining(for: oct2026), 0.0, accuracy: 0.01)
        XCTAssertEqual(debugStore.totalRemainingProvision(for: oct2026), 120.0, accuracy: 0.01)
        XCTAssertEqual(debugStore.accumulatedConsolidatedBalance(throughMonth: oct2026, includeProjectedUnpaid: true), 880.0, accuracy: 0.01)

        // Agora adiciona Teto Mensal (Verba Livre) de R$ 200,00 na categoria Moradia
        debugStore.setCategoryProvision(
            categoryId: housingCat.id,
            estimatedAmount: 200.0,
            for: oct2026,
            repeatForFutureMonths: true
        )
        let octEnvBoth = debugStore.provisionEnvelope(forCategory: housingCat.id, in: oct2026)!
        XCTAssertEqual(octEnvBoth.estimatedAmount, 200.0, accuracy: 0.01)
        XCTAssertEqual(octEnvBoth.remainingProvision, 200.0, accuracy: 0.01)
        XCTAssertEqual(debugStore.totalQuotasRemaining(for: oct2026), 120.0, accuracy: 0.01)
        // Provisão Total Futura = Soma Cotas Restantes (120) + Soma Tetos de Categoria Restantes (200) = 320
        XCTAssertEqual(debugStore.totalRemainingProvision(for: oct2026), 320.0, accuracy: 0.01)
        // Saldo Projetado = 1000 - 320 = 680
        XCTAssertEqual(debugStore.accumulatedConsolidatedBalance(throughMonth: oct2026, includeProjectedUnpaid: true), 680.0, accuracy: 0.01)

        // 3. Dar baixa em 1 unidade da cota (com ajuste real para R$ 32,00):
        // Deve gerar despesa real no extrato, deduzir 1 unidade pendente (restam 3 × R$ 30 = R$ 90) e NÃO subtrair do Teto da Categoria (continua R$ 200)!
        let redeemedTx = debugStore.redeemCategoryQuota(
            seriesId: waterQuota.seriesId,
            units: 1,
            unitPriceOverride: 32.0,
            accountId: debugAcc.id,
            in: oct2026,
            transactionDate: oct2026
        )
        XCTAssertNotNil(redeemedTx)
        XCTAssertEqual(debugStore.transactions.count, 1)
        XCTAssertEqual(debugStore.totalCheckingBalanceNow, 968.0, accuracy: 0.01)

        let octEnvAfterRedeem = debugStore.provisionEnvelope(forCategory: housingCat.id, in: oct2026)!
        XCTAssertEqual(octEnvAfterRedeem.realizedExpense, 0.0, accuracy: 0.01)
        XCTAssertEqual(octEnvAfterRedeem.remainingProvision, 200.0, accuracy: 0.01) // Teto da categoria intacto!
        let octQuotaAfterRedeem = debugStore.quotaEnvelopes(forCategory: housingCat.id, in: oct2026).first!
        XCTAssertEqual(octQuotaAfterRedeem.consumedUnits, 1)
        XCTAssertEqual(octQuotaAfterRedeem.pendingUnits, 3)
        XCTAssertEqual(octQuotaAfterRedeem.remainingProvision, 90.0, accuracy: 0.01)
        XCTAssertEqual(debugStore.totalRemainingProvision(for: oct2026), 290.0, accuracy: 0.01)
        // Saldo Projetado = 968 (saldo atual) - 290 (provisão restante) = 678
        XCTAssertEqual(debugStore.accumulatedConsolidatedBalance(throughMonth: oct2026, includeProjectedUnpaid: true), 678.0, accuracy: 0.01)

        // 4. Despesa avulsa normal lançada na categoria consome APENAS o Teto da Categoria, sem alterar as cotas pendentes
        _ = debugStore.createTransaction(
            name: "Lâmpada LED",
            amount: 50.0,
            date: oct2026,
            type: .expense,
            isPaid: true,
            categoryId: housingCat.id,
            accountId: debugAcc.id,
            ignoreInConsolidated: false
        )
        let octEnvAfterAvulsa = debugStore.provisionEnvelope(forCategory: housingCat.id, in: oct2026)!
        XCTAssertEqual(octEnvAfterAvulsa.realizedExpense, 50.0, accuracy: 0.01)
        XCTAssertEqual(octEnvAfterAvulsa.remainingProvision, 150.0, accuracy: 0.01)
        let octQuotaAfterAvulsa = debugStore.quotaEnvelopes(forCategory: housingCat.id, in: oct2026).first!
        XCTAssertEqual(octQuotaAfterAvulsa.pendingUnits, 3)
        XCTAssertEqual(octQuotaAfterAvulsa.remainingProvision, 90.0, accuracy: 0.01)
        XCTAssertEqual(debugStore.totalRemainingProvision(for: oct2026), 240.0, accuracy: 0.01)

        // 5. O encerramento do mês sem consumo total de uma cota não gera resíduos ou transações forçadas no extrato
        XCTAssertEqual(debugStore.transactions.count, 2)
        let novQuotaInitial = debugStore.quotaEnvelopes(forCategory: housingCat.id, in: nov2026).first!
        XCTAssertEqual(novQuotaInitial.consumedUnits, 0)
        XCTAssertEqual(novQuotaInitial.pendingUnits, 4)
        XCTAssertEqual(novQuotaInitial.remainingProvision, 120.0, accuracy: 0.01)

        // 6. Edição de item recorrente com escopo .onlyThisMonth vs .thisAndFutureMonths
        // Em Nov/2026, altera a cota para 5 galões APENAS para Nov/2026 (.onlyThisMonth)
        debugStore.saveCategoryQuota(
            seriesId: waterQuota.seriesId,
            categoryId: housingCat.id,
            name: "Galão de Água",
            iconSymbol: "drop.fill",
            plannedQuantity: 5,
            estimatedUnitPrice: 30.0,
            for: nov2026,
            repeatForFutureMonths: true,
            editScope: .onlyThisMonth
        )
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: oct2026).first?.plannedQuantity, 4)
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: nov2026).first?.plannedQuantity, 5)
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: dec2026).first?.plannedQuantity, 4) // Dezembro continua herdando 4!

        // Agora altera em Nov/2026 para 6 galões aplicando a TODOS os meses futuros (.thisAndFutureMonths)
        debugStore.saveCategoryQuota(
            seriesId: waterQuota.seriesId,
            categoryId: housingCat.id,
            name: "Galão de Água",
            iconSymbol: "drop.fill",
            plannedQuantity: 6,
            estimatedUnitPrice: 30.0,
            for: nov2026,
            repeatForFutureMonths: true,
            editScope: .thisAndFutureMonths
        )
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: oct2026).first?.plannedQuantity, 4) // Passado preservado
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: nov2026).first?.plannedQuantity, 6)
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: dec2026).first?.plannedQuantity, 6) // Futuro atualizado

        // 7. Exclusão de item recorrente com escopo .onlyThisMonth vs .allOccurrences
        // Excluir somente de Nov/2026 (.onlyThisMonth): continua em Out/2026 e reaparece em Dez/2026!
        debugStore.deleteCategoryQuota(
            seriesId: waterQuota.seriesId,
            for: nov2026,
            scope: .onlyThisMonth
        )
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: oct2026).count, 1)
        XCTAssertTrue(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: nov2026).isEmpty)
        XCTAssertEqual(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: dec2026).count, 1)

        // Excluir todas as ocorrências (.allOccurrences): remove definitivamente para trás e para frente
        debugStore.deleteCategoryQuota(
            seriesId: waterQuota.seriesId,
            for: dec2026,
            scope: .allOccurrences
        )
        XCTAssertTrue(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: oct2026).isEmpty)
        XCTAssertTrue(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: nov2026).isEmpty)
        XCTAssertTrue(debugStore.quotaEnvelopes(forCategory: housingCat.id, in: dec2026).isEmpty)
    }

    func testDecoupledQuotasCategoryCeilingsGranularExportAndExpenseImport() throws {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Itaú Principal",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 3000.0
        )
        let account = store.accounts.first!
        let housingCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Moradia") })!
        let fuelCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Combustível") })!
        let nov2026 = BRLFormatters.shortDateFormatter.date(from: "10/11/2026")!
        store.selectedMonth = nov2026

        // 1. Critério de Aceite 1 & 2:
        // Cadastra cota "Galão de Água" (7 un. × R$ 13,00 = R$ 91,00) vinculada a Moradia, SEM teto geral em Moradia.
        // Lança despesa genérica de Aluguel de R$ 886,00 em Moradia.
        // A cota "Galão de Água" NUNCA entra em estado "Estourado" por conta do aluguel, e Moradia não exibe barra de teto!
        let waterQuota = store.saveCategoryQuota(
            categoryId: housingCat.id,
            name: "Galão de Água",
            iconSymbol: "drop.fill",
            plannedQuantity: 7,
            estimatedUnitPrice: 13.0,
            for: nov2026,
            repeatForFutureMonths: true
        )
        _ = store.createTransaction(
            name: "Aluguel Apartamento",
            amount: 886.0,
            date: nov2026,
            type: .expense,
            isPaid: true,
            categoryId: housingCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )

        // Moradia não tem teto configurado -> provisionEnvelope deve ser nil
        XCTAssertNil(store.provisionEnvelope(forCategory: housingCat.id, in: nov2026))
        XCTAssertTrue(store.provisionEnvelopes(for: nov2026).isEmpty)

        // Cota de água continua intacta: 0 de 7 consumidos • R$ 91,00 restantes • status .normal
        let activeWaterQuota = store.allQuotaEnvelopes(for: nov2026).first!
        XCTAssertEqual(activeWaterQuota.consumedUnits, 0)
        XCTAssertEqual(activeWaterQuota.plannedQuantity, 7)
        XCTAssertEqual(activeWaterQuota.remainingProvision, 91.0, accuracy: 0.01)
        XCTAssertEqual(activeWaterQuota.status, .normal)

        // Configura Teto Geral de R$ 1.000,00 para Combustível
        store.setCategoryProvision(
            categoryId: fuelCat.id,
            estimatedAmount: 1000.0,
            for: nov2026,
            repeatForFutureMonths: true
        )
        _ = store.createTransaction(
            name: "Abastecimento Posto",
            amount: 300.0,
            date: nov2026,
            type: .expense,
            isPaid: true,
            categoryId: fuelCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        // Provisão Total Futura = Cota Restante (91) + Teto Combustível Restante (700) = 791
        XCTAssertEqual(store.totalQuotasRemaining(for: nov2026), 91.0, accuracy: 0.01)
        XCTAssertEqual(store.totalCategoryProvisionsRemaining(for: nov2026), 700.0, accuracy: 0.01)
        XCTAssertEqual(store.totalRemainingProvision(for: nov2026), 791.0, accuracy: 0.01)

        // Cota só entra em .exceeded se as unidades baixadas superarem o planejado (ex: 8 de 7)
        _ = store.redeemCategoryQuota(
            seriesId: waterQuota.seriesId,
            units: 8,
            unitPriceOverride: 13.0,
            accountId: account.id,
            in: nov2026,
            transactionDate: nov2026
        )
        let exceededWaterQuota = store.allQuotaEnvelopes(for: nov2026).first!
        XCTAssertEqual(exceededWaterQuota.consumedUnits, 8)
        XCTAssertEqual(exceededWaterQuota.plannedQuantity, 7)
        XCTAssertEqual(exceededWaterQuota.remainingProvision, 0.0, accuracy: 0.01)
        XCTAssertEqual(exceededWaterQuota.status, .exceeded)

        // 2. Critério de Aceite 4: Exportação Granular da Base de Dados
        store.addDebt(
            name: "Cartão Antigo",
            customImagePath: nil,
            bankPresetId: nil,
            iconSymbol: "creditcard.fill",
            colorHex: "#EF4444",
            originalAmount: 500.0,
            contractedDate: nov2026
        )
        // Exporta APENAS Transações ePrevisões (sem contas, sem dívidas, sem categorias)
        let granularData = try XCTUnwrap(store.exportGranularDatabaseJSON(targets: [.transactions, .provisions]))
        let decodedGranular = try JSONDecoder().decode(FinancialDatabaseSnapshot.self, from: granularData)
        XCTAssertEqual(decodedGranular.transactions.count, 3)
        XCTAssertEqual(decodedGranular.provisions?.count, 1)
        XCTAssertEqual(decodedGranular.categoryQuotas?.count, 1)
        XCTAssertTrue(decodedGranular.accounts.isEmpty)
        XCTAssertTrue(decodedGranular.categories.isEmpty)
        XCTAssertTrue(decodedGranular.debts.isEmpty)

        // 3. Critério de Aceite 5: Importação de Gastos / Transações com Revisão e Anti-Duplicidade
        let externalJSON = """
        [
          {
            "date": "10/11/2026",
            "description": "Abastecimento Posto",
            "amount": 300.00,
            "type": "Despesa",
            "category": "Combustível"
          },
          {
            "date": "15/11/2026",
            "description": "Manutenção Filtro de Água",
            "amount": 65.50,
            "type": "Despesa",
            "category": "Moradia"
          }
        ]
        """.data(using: .utf8)!

        let parsedDrafts = try store.parseImportableExpensesFromJSON(data: externalJSON)
        XCTAssertEqual(parsedDrafts.count, 2)
        // O primeiro item ("Abastecimento Posto", 300.00 em 10/11/2026) deve ser detectado como duplicado!
        XCTAssertTrue(parsedDrafts[0].isDuplicate)
        XCTAssertFalse(parsedDrafts[0].isSelected)
        // O segundo item ("Manutenção Filtro de Água", 65.50) é novo e vem selecionado para importação
        XCTAssertFalse(parsedDrafts[1].isDuplicate)
        XCTAssertTrue(parsedDrafts[1].isSelected)

        let txCountBeforeImport = store.transactions.count
        let importSummary = store.importReviewedExpenseDrafts(parsedDrafts, skipDuplicates: true)
        XCTAssertEqual(importSummary.importedCount, 1)
        XCTAssertEqual(store.transactions.count, txCountBeforeImport + 1)
        XCTAssertTrue(store.transactions.contains(where: { $0.name == "Manutenção Filtro de Água" && abs($0.amount - 65.50) < 0.01 }))
    }

    func testLocalLLMDebtPayoffUsesDilutedMonthlyCashFlowAndCurrentMonthBalance() throws {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Mercado Pago",
            bankPresetId: "mercadopago",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#009EE3",
            initialBalance: 0.0
        )
        let account = store.accounts.first!
        let nov2026 = BRLFormatters.shortDateFormatter.date(from: "07/11/2026")!
        let dec2026 = BRLFormatters.shortDateFormatter.date(from: "05/12/2026")!
        store.selectedMonth = nov2026

        let salaryCat = store.incomeCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Salário") }) ?? store.incomeCategories.first!
        let housingCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Moradia") }) ?? store.expenseCategories.first!
        let loanCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Empréstimo") }) ?? store.expenseCategories.first!

        // 1. Movimentações de Outubro/2026 (Saldo fechado de Outubro: R$ 802,84)
        let oct2026 = BRLFormatters.shortDateFormatter.date(from: "10/10/2026")!
        _ = store.createTransaction(
            name: "Receitas Outubro",
            amount: 13932.72,
            date: oct2026,
            type: .income,
            isPaid: true,
            categoryId: salaryCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        _ = store.createTransaction(
            name: "Despesas Outubro",
            amount: 13129.88,
            date: oct2026,
            type: .expense,
            isPaid: true,
            categoryId: housingCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )

        // 2. Movimentações de Novembro/2026 (Mês Atual):
        // Pagos até 07/11: Receita R$ 9.717,18 e Despesa R$ 9.339,09 -> Saldo realizado hoje = 802,84 + 378,09 = R$ 1.180,93
        // Pendentes até o fim de Novembro: Receita R$ 2.690,00 e Despesa R$ 300,02 -> Saldo projetado fim de Novembro = R$ 3.570,91
        _ = store.createTransaction(
            name: "Salário Recebido Novembro",
            amount: 9717.18,
            date: BRLFormatters.shortDateFormatter.date(from: "05/11/2026")!,
            type: .income,
            isPaid: true,
            categoryId: salaryCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        _ = store.createTransaction(
            name: "Contas Pagas Novembro",
            amount: 9339.09,
            date: BRLFormatters.shortDateFormatter.date(from: "06/11/2026")!,
            type: .expense,
            isPaid: true,
            categoryId: housingCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        _ = store.createTransaction(
            name: "Salário + Vale JSL Pendente Novembro",
            amount: 2690.00,
            date: BRLFormatters.shortDateFormatter.date(from: "15/11/2026")!,
            type: .income,
            isPaid: false,
            categoryId: salaryCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        _ = store.createTransaction(
            name: "Seguro Carro Pendente Novembro",
            amount: 300.02,
            date: BRLFormatters.shortDateFormatter.date(from: "22/11/2026")!,
            type: .expense,
            isPaid: false,
            categoryId: housingCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )

        XCTAssertEqual(store.totalCheckingBalanceNow, 1180.93, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: nov2026, includeProjectedUnpaid: true), 3570.91, accuracy: 0.01)

        // 3. Receitas recorrentes a partir de Dezembro/2026 (R$ 17.255,00/mês)
        _ = store.createTransaction(
            name: "Salario Vivo",
            amount: 14655.00,
            date: dec2026,
            type: .income,
            isPaid: false,
            categoryId: salaryCat.id,
            accountId: account.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .monthly,
            referenceNow: nov2026
        )
        _ = store.createTransaction(
            name: "Salário + Vale JSL",
            amount: 2600.00,
            date: dec2026,
            type: .income,
            isPaid: false,
            categoryId: salaryCat.id,
            accountId: account.id,
            recurrenceMode: .recurring,
            recurrenceFrequency: .monthly,
            referenceNow: nov2026
        )

        // 4. Financiamento imobiliário de longo prazo (332 parcelas até 2054!) + Empréstimos Santander (26 parcelas)
        // Verifica que as 332 parcelas futuras NÃO distorcem a média mensal dividindo por 336 meses!
        let parsedCaixa = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.caixaFinancingOCRText,
            expectedKind: .financing
        )
        _ = store.createCreditContract(
            kind: .financing,
            name: parsedCaixa.name,
            contractNumber: parsedCaixa.contractNumber,
            loanSubtype: parsedCaixa.loanSubtype,
            financingSubtype: parsedCaixa.financingSubtype,
            amortizationSystem: parsedCaixa.amortizationSystem,
            totalContractedAmount: parsedCaixa.totalContractedAmount,
            outstandingBalance: parsedCaixa.outstandingBalance,
            installmentAmount: parsedCaixa.installmentAmount,
            billingDay: parsedCaixa.billingDay,
            totalInstallments: parsedCaixa.totalInstallments,
            monthlyInterestRate: parsedCaixa.monthlyInterestRate,
            startDate: parsedCaixa.startDate,
            accountId: account.id,
            overridePastInstallmentsCount: parsedCaixa.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsedCaixa.firstFutureBillingDate
        )

        _ = store.createTransaction(
            name: "Empréstimo Santander",
            amount: 4509.81 * 26.0,
            date: BRLFormatters.shortDateFormatter.date(from: "07/12/2026")!,
            type: .expense,
            isPaid: false,
            categoryId: loanCat.id,
            accountId: account.id,
            recurrenceMode: .installment,
            installmentsOrMonthsCount: 26,
            referenceNow: nov2026
        )

        // 5. Cadastra múltiplas dívidas em aberto (incluindo "Cartão de crédito Sam’s" com apóstrofo curvo e outra dívida alta)
        store.addDebt(
            name: "Cartão de crédito Sam’s",
            customImagePath: nil,
            bankPresetId: nil,
            iconSymbol: "creditcard.fill",
            colorHex: "#009EE3",
            originalAmount: 1681.00,
            contractedDate: nil
        )
        store.addDebt(
            name: "Cartão de crédito Santander",
            customImagePath: nil,
            bankPresetId: "santander",
            iconSymbol: "creditcard.fill",
            colorHex: "#EC0000",
            originalAmount: 29414.80,
            contractedDate: nil
        )

        // 6. Pergunta exatamente como o usuário digitou (com apóstrofo reto ' em "Cartão de crédito Sam's")
        let samsResponse = LocalLLMService.generateFinancialResponse(
            for: "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida \"Cartão de crédito Sam's\"?",
            store: store,
            modelLabel: "Qwen2.5"
        )

        // Deve encontrar "Cartão de crédito Sam’s" (R$ 1.681,00)
        XCTAssertTrue(samsResponse.contains("Cartão de crédito Sam’s"))
        XCTAssertTrue(samsResponse.contains("1.681,00"))
        // NÃO deve gerar falso alerta de déficit mensal nem dividir receitas de 5 anos por 336 meses
        XCTAssertFalse(samsResponse.contains("Alerta de Fluxo de Caixa para Quitação"))
        XCTAssertFalse(samsResponse.contains("-R$ 486,87"))
        // Deve concluir que já é possível quitar ao fim do mês atual (Novembro de 2026), com saldo projetado de R$ 3.570,91 e sobra de R$ 1.889,91
        XCTAssertTrue(samsResponse.localizedCaseInsensitiveContains("Quitação já ao Fim do Mês Atual"))
        XCTAssertTrue(samsResponse.contains("3.570,91"))
        XCTAssertTrue(samsResponse.contains("1.889,91"))
        // Também deve identificar a data exata segura dentro do mês (15/11/2026, após o recebimento de R$ 2.690,00) e listar o cronograma de datas
        XCTAssertTrue(samsResponse.contains("15/11/2026"))
        XCTAssertTrue(samsResponse.localizedCaseInsensitiveContains("Cronograma de Datas de Caixa"))
    }

    func testLocalLLMContractActionPlanAndIntraMonthChronologicalSafety() throws {
        let store = makeIsolatedStore(seedStatement: false)
        store.addAccount(
            name: "Conta Principal",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 2000.00
        )
        let account = store.accounts.first!
        let nov2026 = BRLFormatters.shortDateFormatter.date(from: "02/11/2026")!
        store.selectedMonth = nov2026

        let salaryCat = store.incomeCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Salário") }) ?? store.incomeCategories.first!
        let housingCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Moradia") }) ?? store.expenseCategories.first!

        // 1. Teste de proteção de fluxo de caixa intra-mês:
        // No dia 02/11 o usuário tem R$ 2.000,00 em conta (que seria > R$ 1.681,00 da dívida Sam's).
        // PORÉM, no dia 10/11 vence o Aluguel de R$ 1.500,00, e o Salário de R$ 5.000,00 só cai no dia 25/11!
        // Se ele pagasse R$ 1.681,00 no começo do mês (02/11), sobrariam apenas R$ 319,00 e faltaria dinheiro para o Aluguel no dia 10/11!
        // A IA DEVE alertar para NÃO pagar no começo do mês e indicar 25/11/2026 como a data segura.
        _ = store.createTransaction(
            name: "Aluguel Vencimento Dia 10",
            amount: 1500.00,
            date: BRLFormatters.shortDateFormatter.date(from: "10/11/2026")!,
            type: .expense,
            isPaid: false,
            categoryId: housingCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        _ = store.createTransaction(
            name: "Salário Final do Mês",
            amount: 5000.00,
            date: BRLFormatters.shortDateFormatter.date(from: "25/11/2026")!,
            type: .income,
            isPaid: false,
            categoryId: salaryCat.id,
            accountId: account.id,
            referenceNow: nov2026
        )
        store.addDebt(
            name: "Cartão de crédito Sam's",
            customImagePath: nil,
            bankPresetId: nil,
            iconSymbol: "creditcard.fill",
            colorHex: "#009EE3",
            originalAmount: 1681.00,
            contractedDate: nil
        )

        let intraMonthResponse = LocalLLMService.generateFinancialResponse(
            for: "Usando como referência o meu modo de gastar e receitas, em quanto tempo devo pagar a dívida \"Cartão de crédito Sam's\"?",
            store: store,
            modelLabel: "Qwen2.5"
        )
        XCTAssertTrue(intraMonthResponse.contains("25/11/2026"))
        XCTAssertTrue(intraMonthResponse.localizedCaseInsensitiveContains("não é recomendável quitar no início/meio do mês antes de 25/11/2026"))

        // 2. Teste de Plano de Ação para Financiamento Imobiliário vs Múltiplos Empréstimos:
        // Cadastra 2 Empréstimos Santander e APENAS 1 Financiamento (Financiamento Habitação CAIXA)
        let parsedSantander1 = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.santanderLoanOCRText,
            expectedKind: .loan
        )
        _ = store.createCreditContract(
            kind: .loan,
            name: parsedSantander1.name,
            contractNumber: parsedSantander1.contractNumber,
            loanSubtype: parsedSantander1.loanSubtype,
            financingSubtype: parsedSantander1.financingSubtype,
            amortizationSystem: parsedSantander1.amortizationSystem,
            totalContractedAmount: parsedSantander1.totalContractedAmount,
            outstandingBalance: parsedSantander1.outstandingBalance,
            installmentAmount: parsedSantander1.installmentAmount,
            billingDay: parsedSantander1.billingDay,
            totalInstallments: parsedSantander1.totalInstallments,
            monthlyInterestRate: parsedSantander1.monthlyInterestRate,
            startDate: parsedSantander1.startDate,
            accountId: account.id,
            overridePastInstallmentsCount: parsedSantander1.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsedSantander1.firstFutureBillingDate
        )

        _ = store.createCreditContract(
            kind: .loan,
            name: "Crédito Consignado Santander (Contrato 783847703)",
            contractNumber: "783847703",
            loanSubtype: .consignado,
            financingSubtype: nil,
            amortizationSystem: .price,
            totalContractedAmount: 10000.0,
            outstandingBalance: 7213.02,
            installmentAmount: 357.31,
            billingDay: 25,
            totalInstallments: 36,
            monthlyInterestRate: 2.01,
            startDate: parsedSantander1.startDate,
            accountId: account.id,
            overridePastInstallmentsCount: 10,
            overrideFirstFutureBillingDate: parsedSantander1.firstFutureBillingDate
        )

        let parsedCaixa = ContractDocumentImportService.parseContractDocumentText(
            SampleContractDocumentsData.caixaFinancingOCRText,
            expectedKind: .financing
        )
        _ = store.createCreditContract(
            kind: .financing,
            name: parsedCaixa.name,
            contractNumber: parsedCaixa.contractNumber,
            loanSubtype: parsedCaixa.loanSubtype,
            financingSubtype: parsedCaixa.financingSubtype,
            amortizationSystem: parsedCaixa.amortizationSystem,
            totalContractedAmount: parsedCaixa.totalContractedAmount,
            outstandingBalance: parsedCaixa.outstandingBalance,
            installmentAmount: parsedCaixa.installmentAmount,
            billingDay: parsedCaixa.billingDay,
            totalInstallments: parsedCaixa.totalInstallments,
            monthlyInterestRate: parsedCaixa.monthlyInterestRate,
            startDate: parsedCaixa.startDate,
            accountId: account.id,
            overridePastInstallmentsCount: parsedCaixa.paidInstallmentsCount,
            overrideFirstFutureBillingDate: parsedCaixa.firstFutureBillingDate
        )

        // Quando o usuário pergunta "Monte um plano de ação para eu quitar meu financiamento imobilidario no menor prazo possível",
        // como há APENAS 1 financiamento cadastrado, a IA deve selecioná-lo automaticamente e montar o Plano de Ação completo!
        let singleFinancingPlan = LocalLLMService.generateFinancialResponse(
            for: "Monte um plano de ação para eu quitar meu financiamento imobilidario no menor prazo possível",
            store: store,
            modelLabel: "Qwen2.5"
        )
        XCTAssertTrue(singleFinancingPlan.contains("Plano de Ação para Quitação no Menor Prazo"))
        XCTAssertTrue(singleFinancingPlan.contains("Financiamento Habitação CAIXA"))
        XCTAssertTrue(singleFinancingPlan.contains("Simulação de Prazo e Economia de Juros"))
        XCTAssertTrue(singleFinancingPlan.contains("Efeito Bola de Neve"))

        // Quando o usuário pergunta sobre "meu empréstimo" sem especificar qual (e existem 2 empréstimos Santander),
        // a IA deve perguntar a qual deles o usuário está se referindo, exibindo a lista!
        let ambiguousLoanQuery = LocalLLMService.generateFinancialResponse(
            for: "Monte um plano de ação para eu quitar meu empréstimo no menor prazo possível",
            store: store,
            modelLabel: "Qwen2.5"
        )
        XCTAssertTrue(ambiguousLoanQuery.localizedCaseInsensitiveContains("Qual empréstimo você deseja analisar"))
        XCTAssertTrue(ambiguousLoanQuery.contains("783847703"))
        XCTAssertTrue(ambiguousLoanQuery.contains("783694303"))

        // E se cadastrarmos um segundo financiamento, perguntar sobre "meu financiamento" sem especificar também passa a perguntar qual dos 2!
        _ = store.createCreditContract(
            kind: .financing,
            name: "Financiamento Veículo Itaú",
            contractNumber: "99887766",
            loanSubtype: nil,
            financingSubtype: .imovel,
            amortizationSystem: .price,
            totalContractedAmount: 60000.0,
            outstandingBalance: 45000.0,
            installmentAmount: 1450.0,
            billingDay: 15,
            totalInstallments: 48,
            monthlyInterestRate: 1.29,
            startDate: nov2026,
            accountId: account.id
        )
        let ambiguousFinancingQuery = LocalLLMService.generateFinancialResponse(
            for: "Monte um plano de ação para eu quitar meu financiamento no menor prazo possível",
            store: store,
            modelLabel: "Qwen2.5"
        )
        XCTAssertTrue(ambiguousFinancingQuery.localizedCaseInsensitiveContains("Qual financiamento você deseja analisar"))
        XCTAssertTrue(ambiguousFinancingQuery.contains("Financiamento Habitação CAIXA"))
        XCTAssertTrue(ambiguousFinancingQuery.contains("Financiamento Veículo Itaú"))
    }

    func testFullCompressedBackupExportAndSelectiveValidatedImport() throws {
        let sourceStore = makeIsolatedStore(seedStatement: false)
        let nov2026 = BRLFormatters.shortDateFormatter.date(from: "10/11/2026")!
        sourceStore.selectedMonth = nov2026

        // Cria um arquivo de asset de teste na pasta Attachments do sourceStore
        let sourceAttachmentsDir = sourceStore.storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceAttachmentsDir, withIntermediateDirectories: true)
        let dummyAssetURL = sourceAttachmentsDir.appendingPathComponent("comprovante_teste.pdf")
        let dummyAssetBytes = Data("PDF-COMPROVANTE-TESTE-123".utf8)
        try dummyAssetBytes.write(to: dummyAssetURL)

        sourceStore.addAccount(
            name: "Conta Backup",
            bankPresetId: "nubank",
            customImagePath: dummyAssetURL.path,
            iconSymbol: "creditcard.fill",
            colorHex: "#820AD1",
            initialBalance: 4200.0
        )
        let sourceAcc = sourceStore.accounts.first!
        let foodCat = sourceStore.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Alimentação") }) ?? sourceStore.expenseCategories.first!

        _ = sourceStore.createTransaction(
            name: "Compra Supermercado Backup",
            amount: 450.0,
            date: nov2026,
            type: .expense,
            isPaid: true,
            categoryId: foodCat.id,
            accountId: sourceAcc.id,
            attachmentPath: dummyAssetURL.path,
            attachmentName: "comprovante_teste.pdf",
            referenceNow: nov2026
        )
        sourceStore.addDebt(
            name: "Dívida Teste Backup",
            customImagePath: nil,
            bankPresetId: nil,
            iconSymbol: "exclamationmark.shield.fill",
            colorHex: "#EF4444",
            originalAmount: 900.0,
            contractedDate: nov2026
        )
        sourceStore.setCategoryProvision(
            categoryId: foodCat.id,
            estimatedAmount: 800.0,
            for: nov2026,
            repeatForFutureMonths: true
        )

        // Simula modelo de IA baixado no sourceStore para garantir que NÃO é exportado no backup
        sourceStore.llmConfig.downloadedModels = [
            LocalLLMModelInfo(
                id: "Qwen/Qwen2.5-3B-Instruct-GGUF",
                displayName: "Qwen 2.5 3B",
                fileName: "qwen2.5-3b.gguf",
                localPath: "/tmp/fake_model.gguf",
                sizeBytes: 2_000_000_000,
                downloadedAt: nov2026
            )
        ]

        // 1. Exporta o arquivo completo comprimido (FCBK + LZFSE)
        let compressedArchive = try XCTUnwrap(sourceStore.exportFullDatabaseArchive(compress: true))
        XCTAssertTrue(compressedArchive.starts(with: Data("FCBK".utf8)))

        // 2. Prepara pacote de importação em um segundo store totalmente vazio (sem categorias/contas)
        let destStore = makeIsolatedStore(seedStatement: false)
        destStore.resetSelectedData(Set(ResetDataTarget.allCases))
        XCTAssertTrue(destStore.accounts.isEmpty)
        XCTAssertTrue(destStore.categories.isEmpty)
        XCTAssertTrue(destStore.transactions.isEmpty)

        let preparedPkg = try destStore.prepareDatabaseImportPackage(from: compressedArchive)
        // Modelos de IA nunca são exportados
        XCTAssertTrue(preparedPkg.snapshot.llmConfig.downloadedModels.isEmpty)
        // Assets estão incluídos
        XCTAssertEqual(preparedPkg.totalCount(for: .assets), 1)
        XCTAssertEqual(preparedPkg.totalCount(for: .transactions), 1)
        XCTAssertEqual(preparedPkg.newCount(for: .transactions), 1)

        // 3. Importa SELETIVAMENTE apenas [.transactions, .assets] (sem marcar .accounts nem .categories!)
        // O validador de consistência referencial deve criar automaticamente a conta e a categoria referenciadas pela transação!
        let firstImportResult = destStore.executeSelectiveDatabaseImportSync(
            package: preparedPkg,
            selectedTargets: [.transactions, .assets]
        )
        XCTAssertEqual(firstImportResult.importedCounts[.transactions], 1)
        XCTAssertEqual(firstImportResult.importedCounts[.assets], 1)
        XCTAssertGreaterThanOrEqual(firstImportResult.autoCreatedDependenciesCount, 2) // Conta + Categoria criadas por consistência!
        XCTAssertEqual(destStore.transactions.count, 1)
        XCTAssertEqual(destStore.accounts.count, 1)
        XCTAssertEqual(destStore.categories.count, 1)
        // Dívidas não foram marcadas, logo continuam 0
        XCTAssertEqual(destStore.debts.count, 0)

        // Verifica que o asset físico foi restaurado no diretório do destStore
        let restoredAssetURL = destStore.storageDirectory.appendingPathComponent("Attachments/comprovante_teste.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredAssetURL.path))

        // 4. Re-analisa e re-importa o mesmo pacote: deve detectar duplicidade em O(1) e não duplicar nada!
        let secondPkg = try destStore.prepareDatabaseImportPackage(from: compressedArchive)
        XCTAssertEqual(secondPkg.newCount(for: .transactions), 0)
        XCTAssertEqual(secondPkg.duplicateCount(for: .transactions), 1)

        let secondImportResult = destStore.executeSelectiveDatabaseImportSync(
            package: secondPkg,
            selectedTargets: Set(ExportDataTarget.allCases)
        )
        XCTAssertEqual(secondImportResult.importedCounts[.transactions] ?? 0, 0)
        XCTAssertEqual(secondImportResult.skippedDuplicateCounts[.transactions] ?? 0, 1)
        // Agora que Dívidas e Previsões foram marcadas, elas entram sem duplicar Transações/Contas
        XCTAssertEqual(secondImportResult.importedCounts[.debts], 1)
        XCTAssertEqual(destStore.transactions.count, 1)
        XCTAssertEqual(destStore.debts.count, 1)
    }

    func testExportAndImportIdenticalTransactionsPreserved() throws {
        let calendar = Calendar(identifier: .gregorian)
        var dateComps = DateComponents()
        dateComps.year = 2026
        dateComps.month = 11
        dateComps.day = 8
        dateComps.hour = 12
        let fixedDate = calendar.date(from: dateComps)!

        // 1. Cria store de origem com 2 transações manuais exatamente idênticas (mesmo nome, valor, data e tipo)
        let sourceStore = makeIsolatedStore(seedStatement: false)
        sourceStore.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Conta Corrente", bankPresetId: "itau", initialBalance: 1000.0)
        sourceStore.accounts = [acc]
        let cat = CategoryItem(name: "Alimentação", type: .expense, iconSymbol: "cart.fill", colorHex: "#EF4444")
        sourceStore.categories = [cat]

        let tx1List = sourceStore.createTransaction(
            name: "Café e Pão de Queijo",
            amount: 15.50,
            date: fixedDate,
            type: .expense,
            isPaid: true,
            categoryId: cat.id,
            accountId: acc.id,
            recurrenceMode: .single,
            referenceNow: fixedDate
        )
        let tx2List = sourceStore.createTransaction(
            name: "Café e Pão de Queijo",
            amount: 15.50,
            date: fixedDate,
            type: .expense,
            isPaid: true,
            categoryId: cat.id,
            accountId: acc.id,
            recurrenceMode: .single,
            referenceNow: fixedDate
        )
        XCTAssertEqual(sourceStore.transactions.count, 2)
        XCTAssertNotEqual(tx1List.first!.id, tx2List.first!.id)

        // 2. Exporta o banco de dados completo (export deve manter todos os registros, inclusive duplicados)
        let archiveData = try XCTUnwrap(sourceStore.exportFullDatabaseArchive(compress: true))

        // 3. Prepara a importação em uma base de dados zerada (sem transações)
        let destStore = makeIsolatedStore(seedStatement: false)
        destStore.resetSelectedData(Set(ResetDataTarget.allCases))
        XCTAssertTrue(destStore.transactions.isEmpty)

        let pkg = try destStore.prepareDatabaseImportPackage(from: archiveData)
        XCTAssertEqual(pkg.totalCount(for: .transactions), 2)
        XCTAssertEqual(pkg.newCount(for: .transactions), 2)
        XCTAssertEqual(pkg.duplicateCount(for: .transactions), 0)

        // 4. Importa na base zerada: ambas as transações idênticas do arquivo devem ser cadastradas normalmente!
        let importResult = destStore.executeSelectiveDatabaseImportSync(
            package: pkg,
            selectedTargets: Set(ExportDataTarget.allCases)
        )
        XCTAssertEqual(importResult.importedCounts[.transactions], 2)
        XCTAssertEqual(importResult.skippedDuplicateCounts[.transactions] ?? 0, 0)
        XCTAssertEqual(destStore.transactions.count, 2)

        // 5. Re-importa o mesmo arquivo na base que agora JÁ possui as duas transações:
        // Agora sim a importação deve ignorar ambas como duplicadas porque já existem previamente na base local!
        let reimportPkg = try destStore.prepareDatabaseImportPackage(from: archiveData)
        XCTAssertEqual(reimportPkg.totalCount(for: .transactions), 2)
        XCTAssertEqual(reimportPkg.newCount(for: .transactions), 0)
        XCTAssertEqual(reimportPkg.duplicateCount(for: .transactions), 2)

        let reimportResult = destStore.executeSelectiveDatabaseImportSync(
            package: reimportPkg,
            selectedTargets: Set(ExportDataTarget.allCases)
        )
        XCTAssertEqual(reimportResult.importedCounts[.transactions] ?? 0, 0)
        XCTAssertEqual(reimportResult.skippedDuplicateCounts[.transactions] ?? 0, 2)
        XCTAssertEqual(destStore.transactions.count, 2)

        // 6. Testa também importação de JSON externo com gastos idênticos no mesmo arquivo
        let rawJSON = """
        [
          {"name": "Almoço Executivo", "amount": 35.0, "date": "08/11/2026", "type": "despesa"},
          {"name": "Almoço Executivo", "amount": 35.0, "date": "08/11/2026", "type": "despesa"}
        ]
        """.data(using: .utf8)!

        let jsonStore = makeIsolatedStore(seedStatement: false)
        jsonStore.resetSelectedData(Set(ResetDataTarget.allCases))
        jsonStore.accounts = [acc]
        jsonStore.categories = [cat]

        let drafts = try jsonStore.parseImportableExpensesFromJSON(data: rawJSON)
        XCTAssertEqual(drafts.count, 2)
        // Como a base local estava zerada, nenhuma das duas é duplicada em relação à base local
        XCTAssertFalse(drafts[0].isDuplicate)
        XCTAssertTrue(drafts[0].isSelected)
        XCTAssertFalse(drafts[1].isDuplicate)
        XCTAssertTrue(drafts[1].isSelected)

        let (draftsImported, draftsSkipped) = jsonStore.importReviewedExpenseDrafts(drafts, skipDuplicates: true)
        XCTAssertEqual(draftsImported, 2)
        XCTAssertEqual(draftsSkipped, 0)
        XCTAssertEqual(jsonStore.transactions.count, 2)

        // Agora que a base já tem os 2 almoços, re-analisar o JSON deve marcar ambas como duplicadas da base local
        let drafts2 = try jsonStore.parseImportableExpensesFromJSON(data: rawJSON)
        XCTAssertEqual(drafts2.count, 2)
        XCTAssertTrue(drafts2[0].isDuplicate)
        XCTAssertTrue(drafts2[1].isDuplicate)

        // Forçando seleção mas mantendo skipDuplicates = true, deve ignorar ambas
        var drafts2Forced = drafts2
        drafts2Forced[0].isSelected = true
        drafts2Forced[1].isSelected = true
        let (reImported, reSkipped) = jsonStore.importReviewedExpenseDrafts(drafts2Forced, skipDuplicates: true)
        XCTAssertEqual(reImported, 0)
        XCTAssertEqual(reSkipped, 2)
        XCTAssertEqual(jsonStore.transactions.count, 2)
    }

    // MARK: - Testes do Motor Agêntico e RAG Financeiro

    func testAgenticSpendingPaceAndMonthEndProjection() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Conta Corrente Principal", initialBalance: 3500.0)
        let catAlim = CategoryItem(name: "Alimentação & Delivery", type: .expense, iconSymbol: "fork.knife", colorHex: "#FF5722")
        let catComb = CategoryItem(name: "Combustível", type: .expense, iconSymbol: "car.fill", colorHex: "#4CAF50")
        let catRent = CategoryItem(name: "Moradia & Aluguel", type: .expense, iconSymbol: "house.fill", colorHex: "#2196F3")
        let catInv = CategoryItem(name: "Aplicações & Reservas", type: .expense, iconSymbol: "chart.line.uptrend.xyaxis", colorHex: "#9C27B0")

        store.accounts = [acc]
        store.categories = [catAlim, catComb, catRent, catInv]

        let cal = Calendar.current
        let now = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!

        // Gasto diário variável pago (Alimentação R$ 300)
        let t1 = FinancialTransaction(
            name: "Supermercado Semanal",
            amount: 300.0,
            date: startOfMonth,
            type: .expense,
            isPaid: true,
            categoryId: catAlim.id,
            accountId: acc.id
        )
        // Gasto diário variável pago (Combustível R$ 200)
        let t2 = FinancialTransaction(
            name: "Gasolina Posto Shell",
            amount: 200.0,
            date: startOfMonth,
            type: .expense,
            isPaid: true,
            categoryId: catComb.id,
            accountId: acc.id
        )
        // Aplicação em investimento (reserva de capital, não é queima/consumo diário)
        let t3 = FinancialTransaction(
            name: "Aporte Tesouro Direto Selic",
            amount: 800.0,
            date: startOfMonth,
            type: .expense,
            isPaid: true,
            categoryId: catInv.id,
            accountId: acc.id
        )
        // Despesa fixa agendada pendente para o final do mês (Aluguel R$ 1.200)
        let t4 = FinancialTransaction(
            name: "Aluguel Mensal",
            amount: 1200.0,
            date: cal.date(byAdding: .day, value: 20, to: startOfMonth)!,
            type: .expense,
            isPaid: false,
            categoryId: catRent.id,
            accountId: acc.id
        )

        store.transactions = [t1, t2, t3, t4]

        // Cria provisão dinâmica (envelope) para alimentação
        let comps = cal.dateComponents([.year, .month], from: startOfMonth)
        let provision = CategoryProvision(
            categoryId: catAlim.id,
            year: comps.year ?? 2026,
            month: comps.month ?? 11,
            estimatedAmount: 500.0
        )
        store.provisions = [provision]

        // Pergunta exata do usuário
        let prompt = "Se eu continuar gastando no ritmo que eu gastei neste mês, ao final do mês terei quanto?"
        let output = AgenticFinancialEngine.runAgentLoop(prompt: prompt, store: store, modelLabel: "Qwen2.5-3B-Local")

        // Validações
        XCTAssertFalse(output.responseMarkdown.contains("## Panorama Completo da sua Base Financeira"), "Não deve retornar o overview genérico anterior")
        XCTAssertTrue(output.responseMarkdown.contains("Projeção de Ritmo de Gastos e Fechamento do Mês") || output.responseMarkdown.contains("Ritmo Diário"), "Deve conter o relatório especializado de ritmo e burn rate")
        XCTAssertTrue(output.responseMarkdown.contains("Cenário 1") || output.responseMarkdown.contains("Ritmo"), "Deve apresentar cenários de fechamento")
        XCTAssertFalse(output.executedSteps.isEmpty, "Deve registrar as etapas de raciocínio e execução de ferramentas do agente")
        XCTAssertNotNil(output.suggestedFollowUps, "Deve fornecer perguntas e sugestões para continuidade do diálogo")
        XCTAssertFalse(output.suggestedFollowUps.isEmpty)
        XCTAssertFalse(output.shouldCloseChat, "Não deve encerrar a sessão em pergunta de análise")
    }

    func testAgenticMultiTurnLoopAndContractClarification() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Conta Principal", initialBalance: 10000.0)
        store.accounts = [acc]

        _ = store.createCreditContract(
            kind: .financing,
            name: "Financiamento Imobiliário Caixa",
            financingSubtype: .imovel,
            amortizationSystem: .sac,
            totalContractedAmount: 350000.0,
            outstandingBalance: 320000.0,
            installmentAmount: 2800.0,
            billingDay: 10,
            totalInstallments: 360,
            monthlyInterestRate: 0.75,
            startDate: Date(),
            accountId: acc.id
        )

        _ = store.createCreditContract(
            kind: .loan,
            name: "Empréstimo Santander",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 50000.0,
            outstandingBalance: 38000.0,
            installmentAmount: 1650.0,
            billingDay: 15,
            totalInstallments: 48,
            monthlyInterestRate: 1.9,
            startDate: Date(),
            accountId: acc.id
        )

        AgenticFinancialEngine.resetMemory(for: store)

        // Turno 1: Usuário pergunta sobre contrato genericamente
        let turn1 = AgenticFinancialEngine.runAgentLoop(
            prompt: "Em quanto tempo consigo quitar meu contrato?",
            store: store,
            modelLabel: "Qwen2.5-3B-Local"
        )

        XCTAssertTrue(turn1.responseMarkdown.contains("2 empréstimos e financiamentos ativos") || turn1.responseMarkdown.contains("Qual contrato"), "Agente deve notar a ambiguidade e pedir esclarecimento")
        let memAfterTurn1 = AgenticFinancialEngine.memory(for: store)
        XCTAssertEqual(memAfterTurn1.pendingQuestionKind, .selectContract)

        // Turno 2: Usuário responde especificando o Santander
        let turn2 = AgenticFinancialEngine.runAgentLoop(
            prompt: "O empréstimo Santander",
            store: store,
            modelLabel: "Qwen2.5-3B-Local"
        )

        XCTAssertTrue(turn2.responseMarkdown.contains("Santander") || turn2.responseMarkdown.contains("Plano de Ação"), "Agente deve resolver a continuidade multi-turn e analisar o contrato Santander")
        let memAfterTurn2 = AgenticFinancialEngine.memory(for: store)
        XCTAssertNil(memAfterTurn2.pendingQuestionKind, "A pendência de esclarecimento deve ter sido resolvida")
    }

    func testAgenticConversationClosingIntent() {
        let store = makeIsolatedStore(seedStatement: false)
        AgenticFinancialEngine.resetMemory(for: store)

        let output = AgenticFinancialEngine.runAgentLoop(
            prompt: "Muito obrigado pelas projeções, era só isso, pode encerrar o chat por hoje!",
            store: store,
            modelLabel: "Qwen2.5-3B-Local"
        )

        XCTAssertTrue(output.shouldCloseChat, "Deve sinalizar fechamento do chat")
        XCTAssertTrue(output.responseMarkdown.contains("Encerrando") || output.responseMarkdown.contains("concluído") || output.responseMarkdown.contains("Fechar") || output.responseMarkdown.contains("disposição"), "Deve conter mensagem de despedida cordial")
    }

    func testFinancialRAGHybridIndexingAndRetrieval() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Banco Nubank Principal", initialBalance: 2500.0)
        let cat = CategoryItem(name: "Combustível e Posto", type: .expense, iconSymbol: "fuelpump.fill", colorHex: "#FF9800")
        store.accounts = [acc]
        store.categories = [cat]

        let t = FinancialTransaction(
            name: "Abastecimento Posto Ipiranga",
            amount: 185.50,
            date: Date(),
            type: .expense,
            isPaid: true,
            categoryId: cat.id,
            accountId: acc.id
        )
        store.transactions = [t]

        let debt = DebtItem(
            name: "Dívida Cartão Mercado Pago",
            originalAmount: 3200.0
        )
        store.debts = [debt]

        let rag = FinancialRAGIndex(store: store)
        rag.rebuildIndex(from: store)

        XCTAssertFalse(rag.documents.isEmpty, "O índice RAG deve indexar contas, categorias, transações e dívidas")

        let searchPosto = rag.search(query: "abastecimento no posto combustível", topK: 3)
        XCTAssertFalse(searchPosto.isEmpty)
        XCTAssertTrue(searchPosto.first?.document.title.contains("Abastecimento") == true || searchPosto.first?.document.title.contains("Combustível") == true)

        let searchDivida = rag.search(query: "quitar mercado pago pendente", topK: 3)
        XCTAssertFalse(searchDivida.isEmpty)
        XCTAssertTrue(searchDivida.first?.document.title.contains("Mercado Pago") == true)
    }

    func testAgenticLatestTransactionQueryConciseResponse() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Conta Corrente", initialBalance: 1142.83)
        let catAlim = CategoryItem(name: "Alimentação", type: .expense, iconSymbol: "fork.knife", colorHex: "#FF5722")
        store.accounts = [acc]
        store.categories = [catAlim]

        let cal = Calendar.current
        var dateComps = DateComponents()
        dateComps.year = 2026
        dateComps.month = 10
        dateComps.day = 13
        dateComps.hour = 10
        dateComps.minute = 0
        let specificDate = cal.date(from: dateComps)!

        let t1 = FinancialTransaction(
            name: "caixa de chocolate",
            amount: 98.0,
            date: specificDate,
            type: .expense,
            isPaid: true,
            categoryId: catAlim.id,
            accountId: acc.id
        )
        store.transactions = [t1]

        let prompt = "qual foi a minha ultima transação?"
        let output = AgenticFinancialEngine.runAgentLoop(prompt: prompt, store: store, modelLabel: "Qwen2.5-3B-Local")

        // 1. NÃO deve conter o dump genérico anterior da base
        XCTAssertFalse(output.responseMarkdown.contains("## Panorama Completo da sua Base Financeira"), "Não deve retornar o panorama completo genérico")
        XCTAssertFalse(output.responseMarkdown.contains("### Resumo de Dívidas e Compromissos"))

        // 2. Resposta deve ser concisa e responder diretamente com dados da transação
        XCTAssertTrue(output.responseMarkdown.contains("98,00") || output.responseMarkdown.contains("98"))
        XCTAssertTrue(output.responseMarkdown.contains("caixa de chocolate"))
        XCTAssertTrue(output.responseMarkdown.contains("Alimentação"))
        XCTAssertTrue(output.responseMarkdown.contains("13/10/2026"))

        // 3. Etapas colaborativas dos 4 agentes
        XCTAssertTrue(output.executedSteps.contains { $0.contains("Agente 1") && $0.contains("Última Transação") && $0.contains("Curta e Direta") })
        XCTAssertTrue(output.executedSteps.contains { $0.contains("Agente 2") })
        XCTAssertTrue(output.executedSteps.contains { $0.contains("Agente 3") && $0.contains("aprovados") })
        XCTAssertTrue(output.executedSteps.contains { $0.contains("Agente 4") })
    }

    func testAgenticRecentTransactionsList() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Conta Principal", initialBalance: 5000.0)
        let cat = CategoryItem(name: "Alimentação", type: .expense, iconSymbol: "fork.knife", colorHex: "#FF5722")
        store.accounts = [acc]
        store.categories = [cat]

        let cal = Calendar.current
        let now = Date()
        let t1 = FinancialTransaction(name: "Almoço", amount: 45.0, date: now, type: .expense, isPaid: true, categoryId: cat.id, accountId: acc.id)
        let t2 = FinancialTransaction(name: "Jantar", amount: 90.0, date: cal.date(byAdding: .day, value: -1, to: now)!, type: .expense, isPaid: true, categoryId: cat.id, accountId: acc.id)
        store.transactions = [t1, t2]

        let prompt = "quais foram as minhas ultimas transacoes?"
        let output = AgenticFinancialEngine.runAgentLoop(prompt: prompt, store: store, modelLabel: "Qwen2.5-3B-Local")

        XCTAssertFalse(output.responseMarkdown.contains("## Panorama Completo da sua Base Financeira"))
        XCTAssertTrue(output.responseMarkdown.contains("Almoço"))
        XCTAssertTrue(output.responseMarkdown.contains("Jantar"))
        XCTAssertTrue(output.executedSteps.contains { $0.contains("Agente 1") && $0.contains("Lista de Transações Recentes") })
    }

    func testAgenticTopExpenseCategoriesQueryAndFollowUpPrompt() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Conta Corrente", initialBalance: 10000.0)
        let catFin = CategoryItem(name: "Financiamento", type: .expense, iconSymbol: "house.fill", colorHex: "#4F46E5")
        let catAlim = CategoryItem(name: "Alimentação", type: .expense, iconSymbol: "fork.knife", colorHex: "#FF5722")
        let catLaz = CategoryItem(name: "Lazer", type: .expense, iconSymbol: "gamecontroller.fill", colorHex: "#10B981")

        store.accounts = [acc]
        store.categories = [catFin, catAlim, catLaz]

        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 10
        let date2026 = cal.date(from: comps)!
        store.selectedMonth = date2026

        let t1 = FinancialTransaction(name: "Parcela Imóvel", amount: 4500.0, date: date2026, type: .expense, isPaid: true, categoryId: catFin.id, accountId: acc.id)
        let t2 = FinancialTransaction(name: "Supermercado", amount: 800.0, date: date2026, type: .expense, isPaid: true, categoryId: catAlim.id, accountId: acc.id)
        let t3 = FinancialTransaction(name: "Cinema", amount: 300.0, date: date2026, type: .expense, isPaid: true, categoryId: catLaz.id, accountId: acc.id)

        store.transactions = [t1, t2, t3]

        let prompt = "qual categoria eu mais gasto?"
        let output = AgenticFinancialEngine.runAgentLoop(prompt: prompt, store: store, modelLabel: "Qwen2.5-3B-Local")

        // 1. Não deve conter dump bruto do RAG nem visão geral não solicitada
        XCTAssertFalse(output.responseMarkdown.contains("## 🔎 Análise Inteligente na Base Local (RAG)"))
        XCTAssertFalse(output.responseMarkdown.contains("## Panorama Completo da sua Base Financeira"))

        // 2. Resposta deve destacar a categoria Financiamento e seu valor
        XCTAssertTrue(output.responseMarkdown.contains("Financiamento"), "Deve apontar Financiamento como top categoria")
        XCTAssertTrue(output.responseMarkdown.contains("4.500,00"), "Deve incluir o valor gasto")

        // 3. Deve convidar para detalhamento de período ou histórico geral
        XCTAssertTrue(output.responseMarkdown.contains("Gostaria de saber") || output.responseMarkdown.contains("ano específico"), "Deve oferecer continuidade elegante")

        // 4. Agente 1 deve ter identificado a intenção topExpenseCategories
        XCTAssertTrue(output.executedSteps.contains { $0.contains("Agente 1") && $0.contains("Ranking e Categoria Mais Gasta") })
    }

    func testAgenticUpcomingContractInstallmentsDueNextMonth() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        let acc = BankAccount(name: "Santander CC", initialBalance: 12000.0)
        let cat = CategoryItem(name: "Contratos de Crédito", type: .expense, iconSymbol: "doc.text.fill", colorHex: "#4F46E5")
        store.accounts = [acc]
        store.categories = [cat]

        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 15
        let nov2026 = cal.date(from: comps)!
        store.selectedMonth = nov2026

        // 3 Contratos: Santander 783847703, Santander 783694303, Financiamento Habitação CAIXA
        let c1 = CreditContract(
            kind: .loan,
            name: "Santander",
            contractNumber: "783847703",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 10000.0,
            installmentAmount: 357.31,
            billingDay: 4,
            totalInstallments: 36,
            monthlyInterestRate: 1.85,
            startDate: nov2026,
            accountId: acc.id,
            categoryId: cat.id
        )

        let c2 = CreditContract(
            kind: .loan,
            name: "Santander",
            contractNumber: "783694303",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 120000.0,
            installmentAmount: 4509.81,
            billingDay: 4,
            totalInstallments: 48,
            monthlyInterestRate: 1.65,
            startDate: nov2026,
            accountId: acc.id,
            categoryId: cat.id
        )

        let c3 = CreditContract(
            kind: .financing,
            name: "Financiamento Habitação CAIXA",
            contractNumber: nil,
            financingSubtype: .imovel,
            amortizationSystem: .sac,
            totalContractedAmount: 400000.0,
            installmentAmount: 2658.04,
            billingDay: 4,
            totalInstallments: 360,
            monthlyInterestRate: 0.85,
            startDate: nov2026,
            accountId: acc.id,
            categoryId: cat.id
        )

        store.contracts = [c1, c2, c3]

        let prompt = "Quanto vou pagar de parcelas de financiamento e emprestimos próximo mês?"
        let output = AgenticFinancialEngine.runAgentLoop(prompt: prompt, store: store, modelLabel: "Qwen2.5-3B-Local")

        // 1. NÃO deve pedir para escolher um contrato nem perguntar qual amortizar
        XCTAssertFalse(output.responseMarkdown.contains("Qual contrato você deseja analisar?"), "Não deve perguntar qual contrato analisar quando a dúvida é sobre parcelas do mês")
        XCTAssertFalse(output.responseMarkdown.contains("Qual financiamento você deseja analisar?"))

        // 2. Deve listar os 3 contratos com seus valores e dia 04/12/2026
        XCTAssertTrue(output.responseMarkdown.contains("357,31"), "Deve conter parcela de 357,31")
        XCTAssertTrue(output.responseMarkdown.contains("4.509,81"), "Deve conter parcela de 4.509,81")
        XCTAssertTrue(output.responseMarkdown.contains("2.658,04"), "Deve conter parcela de 2.658,04")
        XCTAssertTrue(output.responseMarkdown.contains("04/12/2026"), "Deve conter a data de vencimento formatada no próximo mês")

        // 3. Deve totalizar R$ 7.525,16
        XCTAssertTrue(output.responseMarkdown.contains("7.525,16"), "Deve totalizar R$ 7.525,16")
    }

    func testAgenticMultiTurnAnaphoricCategoryAndContractPayoff() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))
        AgenticFinancialEngine.resetMemory(for: store)

        let acc = BankAccount(name: "Conta Principal", initialBalance: 20000.0)
        let catMoradia = CategoryItem(name: "Moradia", type: .expense, iconSymbol: "house.fill", colorHex: "#4F46E5")
        let catAlim = CategoryItem(name: "Alimentação", type: .expense, iconSymbol: "fork.knife", colorHex: "#FF5722")
        store.accounts = [acc]
        store.categories = [catMoradia, catAlim]

        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 10
        let refDate = cal.date(from: comps)!
        store.selectedMonth = refDate

        let t1 = FinancialTransaction(name: "Aluguel", amount: 3000.0, date: refDate, type: .expense, isPaid: true, categoryId: catMoradia.id, accountId: acc.id)
        let t2 = FinancialTransaction(name: "Supermercado", amount: 1000.0, date: refDate, type: .expense, isPaid: true, categoryId: catAlim.id, accountId: acc.id)
        store.transactions = [t1, t2]

        let c1 = CreditContract(
            kind: .loan,
            name: "Santander",
            contractNumber: "783847703",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 10000.0,
            outstandingBalance: 8000.0,
            installmentAmount: 357.31,
            billingDay: 4,
            totalInstallments: 36,
            monthlyInterestRate: 1.85,
            startDate: refDate,
            accountId: acc.id,
            categoryId: catMoradia.id
        )
        store.contracts = [c1]

        // Turno 1: Qual categoria eu mais gasto?
        let out1 = AgenticFinancialEngine.runAgentLoop(prompt: "qual categoria eu mais gasto?", store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertTrue(out1.responseMarkdown.contains("Moradia"))

        // Turno 2: Anáfora "quanto gastei nela?" -> resolve automaticamente para "Moradia"
        let out2 = AgenticFinancialEngine.runAgentLoop(prompt: "quanto gastei nela?", store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertTrue(out2.responseMarkdown.contains("Moradia"), "Deve resolver 'nela' para a categoria Moradia")
        XCTAssertTrue(out2.responseMarkdown.contains("3.000,00"), "Deve buscar valor fresco no banco de dados local")

        // Turno 3: Pergunta de parcelas
        let out3 = AgenticFinancialEngine.runAgentLoop(prompt: "Quanto vou pagar de parcelas de financiamento e emprestimos próximo mês?", store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertTrue(out3.responseMarkdown.contains("357,31"))

        // Turno 4: Anáfora "quanto falta para quitar o primeiro?"
        let out4 = AgenticFinancialEngine.runAgentLoop(prompt: "quanto falta para quitar o primeiro?", store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertTrue(out4.responseMarkdown.contains("Santander"), "Deve resolver 'o primeiro' para o contrato Santander")
        XCTAssertTrue(out4.responseMarkdown.contains("Valor Projetado para Quitação") || out4.responseMarkdown.contains("Saldo Devedor"))
    }

    func testAgenticMultiTurnContextIsolationAndAntiDrift() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))
        AgenticFinancialEngine.resetMemory(for: store)

        let acc = BankAccount(name: "Santander CC", initialBalance: 25000.0)
        let catInvest = CategoryItem(name: "Aplicações & Reservas", type: .expense, iconSymbol: "chart.line.uptrend.xyaxis", colorHex: "#10B981")
        let catEdu = CategoryItem(name: "Educação & Cursos", type: .expense, iconSymbol: "book.fill", colorHex: "#3B82F6")
        let catCred = CategoryItem(name: "Contratos de Crédito", type: .expense, iconSymbol: "doc.text.fill", colorHex: "#6366F1")
        store.accounts = [acc]
        store.categories = [catInvest, catEdu, catCred]

        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11 // Novembro de 2026 como mês corrente
        comps.day = 10
        let nov2026 = cal.date(from: comps)!
        store.selectedMonth = nov2026

        // Despesas em Outubro de 2026 (Mês Passado)
        var octComps = DateComponents()
        octComps.year = 2026
        octComps.month = 10
        octComps.day = 15
        let oct2026 = cal.date(from: octComps)!

        let tOct1 = FinancialTransaction(name: "Aplicação CDB DI", amount: 6092.0, date: oct2026, type: .expense, isPaid: true, categoryId: catInvest.id, accountId: acc.id)
        let tOct2 = FinancialTransaction(name: "Curso Inglês", amount: 1397.38, date: oct2026, type: .expense, isPaid: true, categoryId: catEdu.id, accountId: acc.id)
        store.transactions = [tOct1, tOct2]

        // 3 Contratos com parcelas ativas
        let c1 = CreditContract(
            kind: .loan,
            name: "Santander",
            contractNumber: "783847703",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 10000.0,
            installmentAmount: 357.31,
            billingDay: 4,
            totalInstallments: 36,
            monthlyInterestRate: 1.85,
            startDate: nov2026,
            accountId: acc.id,
            categoryId: catCred.id
        )

        let c2 = CreditContract(
            kind: .loan,
            name: "Santander",
            contractNumber: "783694303",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 120000.0,
            installmentAmount: 4509.81,
            billingDay: 4,
            totalInstallments: 48,
            monthlyInterestRate: 1.65,
            startDate: nov2026,
            accountId: acc.id,
            categoryId: catCred.id
        )

        let c3 = CreditContract(
            kind: .financing,
            name: "Financiamento Habitação CAIXA",
            contractNumber: nil,
            financingSubtype: .imovel,
            amortizationSystem: .sac,
            totalContractedAmount: 400000.0,
            installmentAmount: 2658.04,
            billingDay: 4,
            totalInstallments: 360,
            monthlyInterestRate: 0.85,
            startDate: nov2026,
            accountId: acc.id,
            categoryId: catCred.id
        )
        store.contracts = [c1, c2, c3]

        // Turno 1: "Qual categoria mais gastei no mês passado?"
        let q1 = "Qual categoria mais gastei no mês passado?"
        let out1 = AgenticFinancialEngine.runAgentLoop(prompt: q1, store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertTrue(out1.responseMarkdown.contains("Aplicações & Reservas"), "Deve identificar Aplicações & Reservas em Outubro de 2026")
        XCTAssertTrue(out1.responseMarkdown.contains("6.092,00"))

        // Turno 2: "Quanto vou pagar de parcelas de financiamento e emprestimos próximo mês?"
        // Deve identificar Novo Tópico, NÃO vazar o texto de categoria campeã, e responder parcelas de Dezembro de 2026
        let q2 = "Quanto vou pagar de parcelas de financiamento e emprestimos próximo mês?"
        let out2 = AgenticFinancialEngine.runAgentLoop(prompt: q2, store: store, modelLabel: "Qwen2.5-3B-Local")

        XCTAssertFalse(out2.responseMarkdown.contains("A categoria em que você mais gastou"), "Não deve haver vazamento de contexto da categoria campeã")
        XCTAssertFalse(out2.responseMarkdown.contains("Gostaria de saber qual a categoria"), "Não deve sugerir follow-ups de categoria no tópico de parcelas")
        XCTAssertTrue(out2.responseMarkdown.contains("Dezembro De 2026") || out2.responseMarkdown.contains("Dezembro de 2026"), "Próximo mês a partir de Novembro/2026 deve ser Dezembro/2026")
        XCTAssertTrue(out2.responseMarkdown.contains("357,31"))
        XCTAssertTrue(out2.responseMarkdown.contains("4.509,81"))
        XCTAssertTrue(out2.responseMarkdown.contains("2.658,04"))
        XCTAssertTrue(out2.responseMarkdown.contains("7.525,16"))
        XCTAssertTrue(out2.executedSteps.contains { $0.contains("Agente Juiz") && $0.contains("sem vazamento de contexto") })

        // Turno 3: Repetição imediata da mesma pergunta ("Quanto vou pagar de parcelas de financiamento e emprestimos próximo mês?")
        // Anti-Deriva: NÃO deve avançar para Janeiro de 2027! Deve continuar exatamente em Dezembro de 2026!
        let out3 = AgenticFinancialEngine.runAgentLoop(prompt: q2, store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertFalse(out3.responseMarkdown.contains("Janeiro De 2027"), "Repetição da pergunta não deve sofrer deriva temporal para Janeiro de 2027")
        XCTAssertTrue(out3.responseMarkdown.contains("Dezembro De 2026") || out3.responseMarkdown.contains("Dezembro de 2026"))
        XCTAssertTrue(out3.responseMarkdown.contains("7.525,16"))

        // Turno 4: Repetição pela terceira vez
        // Permanece estável em Dezembro de 2026
        let out4 = AgenticFinancialEngine.runAgentLoop(prompt: q2, store: store, modelLabel: "Qwen2.5-3B-Local")
        XCTAssertFalse(out4.responseMarkdown.contains("Fevereiro De 2027"))
        XCTAssertTrue(out4.responseMarkdown.contains("Dezembro De 2026") || out4.responseMarkdown.contains("Dezembro de 2026"))
        XCTAssertTrue(out4.responseMarkdown.contains("7.525,16"))
    }

    func testRefactoredAIChatArchitectureAndMultiTurnContinuity() {
        let store = makeIsolatedStore(seedStatement: false)
        store.resetSelectedData(Set(ResetDataTarget.allCases))
        AgenticFinancialEngine.resetMemory(for: store)

        // 1. Validação do System Prompt Mandatório (Passo 1)
        XCTAssertTrue(LocalLLMService.systemPrompt.contains("Você é um Agente Financeiro Pessoal de Inteligência Artificial"))
        XCTAssertTrue(LocalLLMService.systemPrompt.contains("CONTINUIDADE (MULTI-TURN)"))
        XCTAssertTrue(LocalLLMService.systemPrompt.contains("RESET DE CONTEXTO EXPLÍCITO"))
        XCTAssertTrue(LocalLLMService.systemPrompt.contains("ANÁLISE DE CAIXA REAL"))
        XCTAssertTrue(LocalLLMService.systemPrompt.contains("ALERTA DE RUNWAY / QUEIMA DE CAIXA"))

        LocalLLMService.ensureSystemPromptInjected(store: store)
        XCTAssertEqual(store.chatHistory.first?.role, .system)
        XCTAssertEqual(store.chatHistory.first?.content, LocalLLMService.systemPrompt)

        // 2. Validação da Injeção de Contexto RAG (Passo 3)
        let acc = BankAccount(name: "Conta Corrente Itaú", initialBalance: 8500.0)
        let catHab = CategoryItem(name: "Habitação", type: .expense, iconSymbol: "house.fill", colorHex: "#4F46E5")
        store.accounts = [acc]
        store.categories = [catHab]

        _ = store.createCreditContract(
            kind: .financing,
            name: "Financiamento Habitação CAIXA",
            contractNumber: "12345678",
            loanSubtype: nil,
            financingSubtype: .imovel,
            amortizationSystem: .sac,
            totalContractedAmount: 200000.0,
            outstandingBalance: 180000.0,
            installmentAmount: 1850.0,
            billingDay: 10,
            totalInstallments: 360,
            monthlyInterestRate: 0.85,
            startDate: Date(),
            accountId: acc.id
        )

        let enrichedPrompt = AgenticFinancialEngine.buildEnrichedUserPrompt(
            originalPrompt: "Monte um plano de ação para eu quitar meu financiamento no menor prazo possível",
            store: store,
            rawFacts: "- Contrato: Financiamento Habitação CAIXA"
        )
        XCTAssertTrue(enrichedPrompt.contains("[CONTEXTO DO BANCO DE DADOS ATUALIZADO]"))
        XCTAssertTrue(enrichedPrompt.contains("- Saldo Disponível Hoje:"))
        XCTAssertTrue(enrichedPrompt.contains("- Sobra Líquida Real (Receitas - Despesas):"))
        XCTAssertTrue(enrichedPrompt.contains("- Entidades relevantes encontradas:"))
        XCTAssertTrue(enrichedPrompt.contains("[FIM DO CONTEXTO]"))
        XCTAssertTrue(enrichedPrompt.contains("Mensagem do usuário:"))

        // 3. Turno 1: Geração de Plano de Ação em Markdown pelo Agente Sintetizador (Passos 1 e 2)
        let out1 = AgenticFinancialEngine.runAgentLoop(
            prompt: "Monte um plano de ação para eu quitar meu financiamento no menor prazo possível",
            store: store,
            modelLabel: "Qwen2.5-3B-Local"
        )
        XCTAssertTrue(out1.responseMarkdown.contains("Plano de Ação para Quitação no Menor Prazo"))
        XCTAssertTrue(out1.responseMarkdown.contains("Financiamento Habitação CAIXA"))
        XCTAssertTrue(out1.responseMarkdown.contains("Simulação de Prazo e Economia de Juros"))
        XCTAssertTrue(out1.responseMarkdown.contains("Cenário 1"))
        XCTAssertTrue(out1.responseMarkdown.contains("Cenário 2"))
        XCTAssertTrue(out1.responseMarkdown.contains("Cenário 3"))
        XCTAssertTrue(out1.responseMarkdown.contains("Efeito Bola de Neve"))

        // 4. Turno 2: Pergunta de Seguimento Multi-Turn "E no Cenário 3?" (Passo 5)
        let out2 = AgenticFinancialEngine.runAgentLoop(
            prompt: "E no Cenário 3?",
            store: store,
            modelLabel: "Qwen2.5-3B-Local"
        )
        XCTAssertTrue(out2.responseMarkdown.contains("Cenário 3"))
        XCTAssertTrue(out2.responseMarkdown.contains("Financiamento Habitação CAIXA") || out2.responseMarkdown.contains("Amortização Extra"))
        XCTAssertFalse(out2.responseMarkdown.contains("Não sei a qual cenário você se refere"))

        // 5. Turno 3: Reset Explícito de Contexto com [NOVA SIMULAÇÃO DO SISTEMA] (Passo 4)
        let out3 = AgenticFinancialEngine.runAgentLoop(
            prompt: "[NOVA SIMULAÇÃO DO SISTEMA] qual o meu saldo disponível nas contas?",
            store: store,
            modelLabel: "Qwen2.5-3B-Local"
        )
        XCTAssertTrue(out3.responseMarkdown.contains("8.500,00"))
        XCTAssertFalse(out3.responseMarkdown.contains("Plano de Ação"))
        XCTAssertFalse(out3.responseMarkdown.contains("Cenário 3"))
        XCTAssertTrue(out3.executedSteps.contains { $0.contains("Reset de Contexto") })
    }

    func testRecurringQuotasAndProvisionsMonthByMonthAccumulationAndPastClosedMonthsIgnored() {
        let store = makeIsolatedStore(seedStatement: false)
        let cal = Calendar(identifier: .gregorian)

        store.addAccount(
            name: "Conta Principal",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "building.columns.fill",
            colorHex: "#EC7000",
            initialBalance: 0.0
        )
        let acc = store.accounts.first!
        let salaryCat = store.incomeCategories.first!
        let foodCat = store.expenseCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Aliment") })!
        let otherExpenseCat = store.expenseCategories.first(where: { $0.id != foodCat.id }) ?? store.expenseCategories.first!

        let janComps = DateComponents(year: 2026, month: 1, day: 10)
        let febComps = DateComponents(year: 2026, month: 2, day: 10)
        let marComps = DateComponents(year: 2026, month: 3, day: 10)
        let decPrevComps = DateComponents(year: 2025, month: 12, day: 10)

        let jan2026 = cal.date(from: janComps)!
        let feb2026 = cal.date(from: febComps)!
        let mar2026 = cal.date(from: marComps)!
        let dec2025 = cal.date(from: decPrevComps)!

        // Cria ganhos fixos de 1000 e despesas fixas de 800 em Jan, Fev e Mar
        for mDate in [jan2026, feb2026, mar2026] {
            _ = store.createTransaction(
                name: "Salário Fixo",
                amount: 1000.0,
                date: mDate,
                type: .income,
                isPaid: false,
                categoryId: salaryCat.id,
                accountId: acc.id
            )
            _ = store.createTransaction(
                name: "Despesa Fixa",
                amount: 800.0,
                date: mDate,
                type: .expense,
                isPaid: false,
                categoryId: otherExpenseCat.id,
                accountId: acc.id
            )
        }

        // Simula que o mês corrente é Janeiro de 2026
        store.simulatedCurrentDate = jan2026

        // Sem cotas: Janeiro = 200, Fevereiro = 400 (200 + 200), Março = 600
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: jan2026, includeProjectedUnpaid: true), 200.0, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: feb2026, includeProjectedUnpaid: true), 400.0, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: mar2026, includeProjectedUnpaid: true), 600.0, accuracy: 0.01)

        // Adiciona orçamento/previsão de 100 para alimentos em Janeiro e marca para repetir para os próximos meses
        store.setCategoryProvision(
            categoryId: foodCat.id,
            estimatedAmount: 100.0,
            for: jan2026,
            repeatForFutureMonths: true
        )

        // Com a provisão de 100 repetida:
        // Janeiro: 200 - 100 = 100
        // Fevereiro: 400 - (100 Jan + 100 Fev) = 200
        // Março: 600 - (100 Jan + 100 Fev + 100 Mar) = 300
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: jan2026, includeProjectedUnpaid: true), 100.0, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: feb2026, includeProjectedUnpaid: true), 200.0, accuracy: 0.01)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: mar2026, includeProjectedUnpaid: true), 300.0, accuracy: 0.01)

        // Para um mês anterior ao atual (ex: Dezembro de 2025), o mês já fechou: cotas/previsões são desconsideradas
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: dec2025, includeProjectedUnpaid: true), 0.0, accuracy: 0.01)
        XCTAssertEqual(store.totalRemainingProvision(for: dec2025), 0.0, accuracy: 0.01)

        // Agora simula o avanço do tempo: o mês atual passa a ser Fevereiro de 2026
        store.simulatedCurrentDate = feb2026

        // Janeiro agora é mês anterior (já fechou): a provisão de Janeiro não afeta mais o futuro
        XCTAssertEqual(store.totalRemainingProvision(for: jan2026), 0.0, accuracy: 0.01)
        // Saldo ao final do mês de Janeiro reflete o fechamento real (200)
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: jan2026, includeProjectedUnpaid: true), 200.0, accuracy: 0.01)

        // Em Fevereiro (mês atual): 400 - 100 (Fev) = 300
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: feb2026, includeProjectedUnpaid: true), 300.0, accuracy: 0.01)
        // Em Março (mês futuro): 600 - (100 Fev + 100 Mar) = 400
        XCTAssertEqual(store.accumulatedConsolidatedBalance(throughMonth: mar2026, includeProjectedUnpaid: true), 400.0, accuracy: 0.01)
    }

    func testMonthEndBalanceCardTitlesForClosedAndFutureMonths() {
        let store = makeIsolatedStore(seedStatement: false)
        let cal = Calendar(identifier: .gregorian)

        let oct2026 = cal.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let nov2026 = cal.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let dec2026 = cal.date(from: DateComponents(year: 2026, month: 12, day: 20))!

        // Fixa a data atual como 09/11/2026
        store.simulatedCurrentDate = nov2026

        // Outubro/2026 é mês anterior (fechado): "Resultado Consolidado"
        XCTAssertEqual(store.monthEndBalanceCardTitle(for: oct2026), "Resultado Consolidado")

        // Novembro/2026 é o mês atual em andamento (termina em 30/11)
        XCTAssertEqual(store.monthEndBalanceCardTitle(for: nov2026), "Saldo Previsto para 30/11")

        // Dezembro/2026 é mês futuro (termina em 31/12)
        XCTAssertEqual(store.monthEndBalanceCardTitle(for: dec2026), "Saldo Previsto para 31/12")
    }

    func testDecoupledCashRealizedVsPredictiveMetricsAndCashFlowSeries() throws {
        let store = makeIsolatedStore(seedStatement: false)
        let cal = Calendar(identifier: .gregorian)

        let acc = BankAccount(name: "Conta Corrente", bankPresetId: "itau", initialBalance: 1000.0)
        store.accounts = [acc]
        let catIncome = store.categories.first { $0.type == .income }!
        let catExpense = store.categories.first { $0.type == .expense }!

        let novDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        store.simulatedCurrentDate = novDate

        // Receita: 5000 (3000 paga, 2000 pendente)
        _ = store.createTransaction(
            name: "Salário Recebido",
            amount: 3000.0,
            date: novDate,
            type: .income,
            isPaid: true,
            categoryId: catIncome.id,
            accountId: acc.id,
            referenceNow: novDate
        )
        _ = store.createTransaction(
            name: "Freelance a Receber",
            amount: 2000.0,
            date: novDate,
            type: .income,
            isPaid: false,
            categoryId: catIncome.id,
            accountId: acc.id,
            referenceNow: novDate
        )

        // Despesa: 2000 (1200 paga, 800 pendente)
        _ = store.createTransaction(
            name: "Aluguel Pago",
            amount: 1200.0,
            date: novDate,
            type: .expense,
            isPaid: true,
            categoryId: catExpense.id,
            accountId: acc.id,
            referenceNow: novDate
        )
        _ = store.createTransaction(
            name: "Internet a Pagar",
            amount: 800.0,
            date: novDate,
            type: .expense,
            isPaid: false,
            categoryId: catExpense.id,
            accountId: acc.id,
            referenceNow: novDate
        )

        // Previsão/Teto restante: 1000 (Teto de 3000 para categoria com 2000 de gastos -> 1000 restante)
        store.setCategoryProvision(
            categoryId: catExpense.id,
            estimatedAmount: 3000.0,
            for: novDate,
            repeatForFutureMonths: false,
            editScope: .onlyThisMonth
        )

        // Verificações rigorosas de desacoplamento:
        // 1. Receitas
        XCTAssertEqual(store.monthlyIncome(for: novDate), 5000.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyReceivedIncome(for: novDate), 3000.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyPendingIncome(for: novDate), 2000.0, accuracy: 0.01)

        // 2. Despesas lançadas (NUNCA deve somar os 1000 de teto!)
        XCTAssertEqual(store.monthlyExpense(for: novDate), 2000.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyPaidExpense(for: novDate), 1200.0, accuracy: 0.01)
        XCTAssertEqual(store.monthlyPendingExpense(for: novDate), 800.0, accuracy: 0.01)

        // 3. Balanço Operacional (5000 - 2000 = 3000) e Taxa de Poupança (3000/5000 = 60%)
        XCTAssertEqual(store.monthlyOperatingNet(for: novDate), 3000.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(store.monthlySavingsRate(for: novDate)), 60.0, accuracy: 0.01)

        // 4. Previsões restantes
        XCTAssertEqual(store.totalRemainingProvision(for: novDate), 1000.0, accuracy: 0.01)

        // 5. Série do gráfico de fluxo de caixa empilhado
        let series = store.cashFlowSeries(around: novDate, monthsBack: 1, monthsForward: 1)
        let novPoint = try XCTUnwrap(series.first { cal.component(.month, from: $0.monthDate) == 11 })
        XCTAssertEqual(novPoint.expense, 2000.0, accuracy: 0.01)
        XCTAssertEqual(novPoint.remainingProvisions, 1000.0, accuracy: 0.01)
        XCTAssertEqual(novPoint.totalBudgetedExpense, 3000.0, accuracy: 0.01)
        XCTAssertFalse(novPoint.isPastMonth)

        let octPoint = try XCTUnwrap(series.first { cal.component(.month, from: $0.monthDate) == 10 })
        XCTAssertTrue(octPoint.isPastMonth)
        XCTAssertEqual(octPoint.remainingProvisions, 0.0, accuracy: 0.01)
    }

    func testProjectedBalanceDynamicSubtitleAndBreakdownTooltipAcrossTimeline() throws {
        let store = makeIsolatedStore(seedStatement: false)
        let cal = Calendar.current
        let referenceNow = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let octDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let novDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        let decDate = cal.date(from: DateComponents(year: 2026, month: 12, day: 10))!
        let year2025Date = cal.date(from: DateComponents(year: 2025, month: 6, day: 15))!

        let cat = store.categories.first!

        // Provisão em Outubro (Mês passado fechado): R$ 500
        store.setCategoryProvision(categoryId: cat.id, estimatedAmount: 500.0, for: octDate, repeatForFutureMonths: false, editScope: .onlyThisMonth)
        // Provisão em Novembro (Mês atual): R$ 1.000
        store.setCategoryProvision(categoryId: cat.id, estimatedAmount: 1000.0, for: novDate, repeatForFutureMonths: false, editScope: .onlyThisMonth)
        // Provisão em Dezembro (Mês futuro): R$ 800
        store.setCategoryProvision(categoryId: cat.id, estimatedAmount: 800.0, for: decDate, repeatForFutureMonths: false, editScope: .onlyThisMonth)

        // 1. Visão Mensal - Mês passado encerrado
        let pastSubtitle = store.deductionSubtitleForProjectedBalance(periodMode: .monthly, selectedMonth: octDate, referenceNow: referenceNow)
        XCTAssertEqual(pastSubtitle, "Mês encerrado")
        let pastTooltip = store.deductionBreakdownTooltipForProjectedBalance(periodMode: .monthly, selectedMonth: octDate, referenceNow: referenceNow)
        XCTAssertNil(pastTooltip)

        // 2. Visão Mensal - Mês atual
        let currentSubtitle = store.deductionSubtitleForProjectedBalance(periodMode: .monthly, selectedMonth: novDate, referenceNow: referenceNow)
        XCTAssertTrue(currentSubtitle.contains("restantes em tetos/cotas deste mês"))
        XCTAssertTrue(currentSubtitle.contains("1.000"))

        // 3. Visão Mensal - Mês futuro
        let futureSubtitle = store.deductionSubtitleForProjectedBalance(periodMode: .monthly, selectedMonth: decDate, referenceNow: referenceNow)
        XCTAssertTrue(futureSubtitle.contains("planejados em tetos/cotas para este mês"))
        XCTAssertTrue(futureSubtitle.contains("800"))

        // 4. Visão Anual - Exercício 2026 (Novembro + Dezembro = R$ 1.800 ativos, desconsiderando Outubro que já encerrou)
        let annual2026Subtitle = store.deductionSubtitleForProjectedBalance(periodMode: .annual, selectedMonth: novDate, referenceNow: referenceNow)
        XCTAssertTrue(annual2026Subtitle.contains("acumulados em cotas"))
        XCTAssertTrue(annual2026Subtitle.contains("1.800"))

        let annual2026Tooltip = try XCTUnwrap(store.deductionBreakdownTooltipForProjectedBalance(periodMode: .annual, selectedMonth: novDate, referenceNow: referenceNow))
        XCTAssertTrue(annual2026Tooltip.contains("Nov"))
        XCTAssertTrue(annual2026Tooltip.contains("Dez"))
        XCTAssertFalse(annual2026Tooltip.contains("Out"))

        // 5. Visão Anual - Exercício passado 2025 encerrado
        let annual2025Subtitle = store.deductionSubtitleForProjectedBalance(periodMode: .annual, selectedMonth: year2025Date, referenceNow: referenceNow)
        XCTAssertEqual(annual2025Subtitle, "Ano encerrado")
    }

    func testTemporalDebtAmortizationAndCutoffDynamics() throws {
        let store = makeIsolatedStore(seedStatement: false)
        let cal = Calendar.current
        let referenceNow = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!

        store.addAccount(
            name: "Conta Corrente Teste",
            bankPresetId: "itau",
            customImagePath: nil,
            iconSymbol: "banknote",
            colorHex: "#10B981",
            initialBalance: 20000.0
        )
        let acc = store.accounts.first!

        let startDate = cal.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        // Criar empréstimo com 24 parcelas de R$ 500 começando em Agosto de 2026
        let contract = store.createCreditContract(
            kind: .loan,
            name: "Empréstimo Expansão",
            loanSubtype: .pessoal,
            amortizationSystem: .price,
            totalContractedAmount: 12000.0,
            installmentAmount: 500.0,
            billingDay: 10,
            totalInstallments: 24,
            monthlyInterestRate: 1.5,
            startDate: startDate,
            accountId: acc.id,
            referenceDate: startDate
        )

        // 1. Corte Mensal em Novembro/2026: 4 parcelas decorridas (Ago, Set, Out, Nov). Restam 20 parcelas = R$ 10.000
        let novSummary = store.buildComprehensiveDebtSummary(referenceDate: referenceNow, isAnnual: false)
        XCTAssertEqual(novSummary.loansRemainingNominalTotal, 10000.0, accuracy: 0.01)
        XCTAssertEqual(novSummary.loansAmortizedInPeriodTotal, 500.0, accuracy: 0.01) // Apenas a parcela de Novembro no mês

        // 2. Corte Anual para 31/12/2026: 5 parcelas em 2026 (Ago..Dez). Restam 19 parcelas = R$ 9.500
        let annual2026Summary = store.buildComprehensiveDebtSummary(referenceDate: referenceNow, isAnnual: true)
        XCTAssertEqual(annual2026Summary.loansRemainingNominalTotal, 9500.0, accuracy: 0.01)
        XCTAssertEqual(annual2026Summary.loansAmortizedInPeriodTotal, 2500.0, accuracy: 0.01) // 5 x 500 em 2026

        // 3. Corte Anual para 31/12/2027: mais 12 parcelas pagas em 2027. Restam 7 parcelas = R$ 3.500
        let date2027 = cal.date(from: DateComponents(year: 2027, month: 6, day: 15))!
        let annual2027Summary = store.buildComprehensiveDebtSummary(referenceDate: date2027, isAnnual: true)
        XCTAssertEqual(annual2027Summary.loansRemainingNominalTotal, 3500.0, accuracy: 0.01)
        XCTAssertEqual(annual2027Summary.loansAmortizedInPeriodTotal, 6000.0, accuracy: 0.01) // 12 x 500 em 2027

        // O saldo residual do passivo reduziu rigorosamente no tempo de 2026 (R$ 9.500) para 2027 (R$ 3.500)
        XCTAssertLessThan(annual2027Summary.loansRemainingNominalTotal, annual2026Summary.loansRemainingNominalTotal)

        // 4. Testar sincronismo atômico ao aplicar amortização extraordinária
        let prevRemaining = store.remainingNominalAmount(for: contract, asOf: store.endOfYear(for: referenceNow))
        XCTAssertEqual(prevRemaining, 9500.0, accuracy: 0.01)

        store.amortizeContract(
            contractId: contract.id,
            amountPaid: 1000.0,
            accountId: acc.id,
            date: referenceNow,
            mode: .reduceTerm
        )

        let postSummary = store.buildComprehensiveDebtSummary(referenceDate: referenceNow, isAnnual: true)
        XCTAssertEqual(postSummary.loansAmortizedInPeriodTotal, 3500.0, accuracy: 0.01) // 2500 parcelas normais + 1000 amortização
    }
}
