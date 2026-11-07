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
}
