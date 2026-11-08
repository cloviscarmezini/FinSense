import Foundation

// MARK: - RAG (Retrieval-Augmented Generation) Models & Hybrid Vector/BM25 Index

public enum RAGEntityType: String, Codable, CaseIterable, Hashable {
    case transaction = "Transação"
    case account = "Conta Bancária"
    case category = "Categoria"
    case investment = "Investimento"
    case debt = "Dívida"
    case loan = "Empréstimo"
    case financing = "Financiamento"
    case provision = "Provisão/Teto"
    case quota = "Cota Específica"
    case monthlySummary = "Resumo Mensal"
}

public struct RAGDocument: Identifiable, Hashable {
    public let id: String
    public let entityId: UUID?
    public let entityType: RAGEntityType
    public let title: String
    public let content: String
    public let normalizedText: String
    public let tokens: [String]
    public let date: Date?
    public let amount: Double?
    public let isPaid: Bool?
    public let transactionType: TransactionType?
    public let categoryId: UUID?
    public let accountId: UUID?
    public let embedding: [Double]
    public let metadata: [String: String]
}

public struct RAGSearchResult: Identifiable, Hashable {
    public var id: String { document.id }
    public let document: RAGDocument
    public let lexicalScore: Double
    public let semanticScore: Double
    public let combinedScore: Double
}

@MainActor
public final class FinancialRAGIndex {
    public private(set) var documents: [RAGDocument] = []
    private var idfByToken: [String: Double] = [:]
    private var avgDocLength: Double = 1.0

    private static let stopwords: Set<String> = [
        "o", "a", "os", "as", "um", "uma", "uns", "umas", "de", "do", "da", "dos", "das",
        "em", "no", "na", "nos", "nas", "por", "para", "com", "sem", "sob", "sobre", "e",
        "ou", "mas", "se", "que", "qual", "quais", "como", "meu", "minha", "meus", "minhas",
        "eu", "voce", "ele", "ela", "ao", "aos", "pelo", "pela", "pelos", "pelas", "este",
        "esta", "esse", "essa", "isso", "isto", "aquele", "aquela", "ser", "estar", "ter",
        "haver", "ir", "foi", "era", "sao", "estao", "terei", "tera", "tenho", "tinha"
    ]

    // Dimensões semânticas financeiras + hashing de trigramas (64 dimensões)
    private static let semanticConceptClusters: [[String]] = [
        ["ritmo", "velocidade", "continuar", "gastando", "media", "diaria", "diario", "burn", "rate", "tendencia", "mantiver", "manter"],
        ["final", "fim", "fechar", "fechamento", "sobrar", "sobra", "restar", "resta", "terei", "ficarei", "terminar", "saldo"],
        ["despesa", "despesas", "gasto", "gastos", "gastei", "saida", "saidas", "pagamento", "conta", "contas", "boleto", "custo"],
        ["receita", "receitas", "entrada", "entradas", "salario", "ganho", "ganhei", "recebi", "recebimento", "renda", "provento"],
        ["divida", "dividas", "serasa", "acordo", "negociar", "negociacao", "atraso", "inadimplencia", "pendente", "devendo", "devo"],
        ["emprestimo", "emprestimos", "consignado", "pessoal", "credito", "parcela", "parcelas", "juros", "taxa", "cet"],
        ["financiamento", "financiamentos", "imobiliario", "imobilidario", "habitacao", "imovel", "casa", "apartamento", "veiculo", "carro", "sac", "price", "amortizar", "amortizacao"],
        ["investimento", "investimentos", "cofrinho", "cofrinhos", "caixinha", "cdb", "aplicacao", "aplicacoes", "resgate", "reserva", "patrimonio", "rendimento"],
        ["provisao", "provisoes", "teto", "tetos", "envelope", "envelopes", "orcamento", "limite", "meta", "estimativa", "estimado"],
        ["cota", "cotas", "galao", "agua", "botijao", "gas", "unidades", "quantidade", "baixa", "item"],
        ["alimentacao", "delivery", "ifood", "restaurante", "lanche", "lanches", "comida", "mercado", "supermercado", "padaria", "feira"],
        ["combustivel", "gasolina", "etanol", "posto", "abastecimento", "uber", "99pop", "transporte", "mobilidade", "pedagio", "estacionamento"],
        ["moradia", "aluguel", "condominio", "luz", "energia", "agua", "internet", "iptu", "casa"],
        ["educacao", "faculdade", "mba", "fiap", "curso", "escola", "mensalidade", "estudo"],
        ["saude", "farmacia", "remedio", "medico", "plano", "consulta", "exame", "hospital", "dentista"],
        ["cartao", "fatura", "nubank", "itau", "santander", "mercado", "pago", "inter", "carrefour", "sams", "caixa", "bradesco", "bb"]
    ]

    public init(store: FinancialDataStore) {
        rebuildIndex(from: store)
    }

    public func rebuildIndex(from store: FinancialDataStore) {
        var docs: [RAGDocument] = []
        let cal = Calendar.current

        // 1. Indexa Contas Bancárias
        for acc in store.accounts {
            let curBal = store.currentBalance(forAccount: acc.id)
            let projBal = store.currentBalance(forAccount: acc.id, upTo: store.selectedMonth)
            let accTxs = store.transactions.filter { $0.accountId == acc.id && !$0.ignoreInConsolidated }
            let paidExp = accTxs.filter { $0.type == .expense && $0.isPaid }.reduce(0.0) { $0 + $1.amount }
            let paidInc = accTxs.filter { $0.type == .income && $0.isPaid }.reduce(0.0) { $0 + $1.amount }

            let text = """
            Conta Bancária: \(acc.name) (Banco: \(acc.bankPresetId ?? "Personalizado"), Agência: \(acc.agency), Conta: \(acc.accountNumber)). \
            Saldo Inicial: \(BRLFormatters.currency(acc.initialBalance)). \
            Saldo Atual Realizado: \(BRLFormatters.currency(curBal)). \
            Saldo Projetado no Mês: \(BRLFormatters.currency(projBal)). \
            Total Receitas Pagas: \(BRLFormatters.currency(paidInc)). Total Despesas Pagas: \(BRLFormatters.currency(paidExp)). \
            Quantidade de transações: \(accTxs.count).
            """
            docs.append(makeDocument(
                id: "account_\(acc.id.uuidString)",
                entityId: acc.id,
                entityType: .account,
                title: "Conta: \(acc.name)",
                content: text,
                date: acc.createdAt,
                amount: curBal,
                accountId: acc.id,
                metadata: ["name": acc.name, "balance": String(curBal)]
            ))
        }

        // 2. Indexa Categorias com gastos do mês selecionado e acumulado
        for cat in store.categories {
            let monthTxs = store.transactionsForMonth(store.selectedMonth)
                .filter { $0.categoryId == cat.id && !$0.ignoreInConsolidated }
            let monthTotal = monthTxs.reduce(0.0) { $0 + $1.amount }
            let allTxs = store.transactions.filter { $0.categoryId == cat.id && !$0.ignoreInConsolidated }
            let allTotal = allTxs.reduce(0.0) { $0 + $1.amount }
            let env = store.provisionEnvelope(forCategory: cat.id, in: store.selectedMonth)
            let envDesc = env.map {
                "Teto/Envelope no mês: \(BRLFormatters.currency($0.estimatedAmount)), Gasto: \(BRLFormatters.currency($0.realizedExpense)), Restante: \(BRLFormatters.currency($0.remainingProvision)) (\($0.status.rawValue))"
            } ?? "Sem teto/provisão configurado neste mês"

            let text = """
            Categoria de \(cat.type.title): \(cat.name). Palavras-chave: \(cat.keywords.joined(separator: ", ")). \
            Total em \(BRLFormatters.monthYear(store.selectedMonth)): \(BRLFormatters.currency(monthTotal)) (\(monthTxs.count) lançamentos). \
            Total histórico geral: \(BRLFormatters.currency(allTotal)) (\(allTxs.count) lançamentos). \
            \(envDesc).
            """
            docs.append(makeDocument(
                id: "category_\(cat.id.uuidString)",
                entityId: cat.id,
                entityType: .category,
                title: "Categoria: \(cat.name) (\(cat.type.title))",
                content: text,
                amount: monthTotal,
                transactionType: cat.type,
                categoryId: cat.id,
                metadata: ["name": cat.name, "type": cat.type.rawValue]
            ))
        }

        // 3. Indexa Investimentos e suas Movimentações
        for inv in store.investments {
            let accName = store.account(for: inv.investmentAccountId)?.name ?? "Conta"
            let movsDesc = inv.movements.prefix(8).map {
                "\($0.type.title) de \(BRLFormatters.currency($0.amount)) em \(BRLFormatters.shortDate($0.date))"
            }.joined(separator: "; ")

            let text = """
            Investimento: \(inv.name) (Grupo/Carteira: \(inv.groupName), Conta: \(accName)). \
            Saldo Investido Atual: \(BRLFormatters.currency(inv.balance)). \
            Exibido no Patrimônio Consolidado: \(inv.showInConsolidated ? "Sim" : "Não"). \
            Notas: \(inv.notes). Histórico de Movimentações (\(inv.movements.count)): \(movsDesc).
            """
            docs.append(makeDocument(
                id: "investment_\(inv.id.uuidString)",
                entityId: inv.id,
                entityType: .investment,
                title: "Investimento: \(inv.name) (\(inv.groupName))",
                content: text,
                date: inv.createdAt,
                amount: inv.balance,
                accountId: inv.investmentAccountId,
                metadata: ["name": inv.name, "group": inv.groupName, "consolidated": String(inv.showInConsolidated)]
            ))
        }

        // 4. Indexa Dívidas (Abertas e Quitadas)
        for debt in store.debts {
            let statusStr = debt.isPaid
                ? "Quitada em \(debt.paidDate.map { BRLFormatters.shortDate($0) } ?? "-") por \(BRLFormatters.currency(debt.negotiatedAmount ?? debt.originalAmount))"
                : "Em Aberto (Pendente de Quitação/Negociação)"
            let dateStr = debt.contractedDate.map { BRLFormatters.shortDate($0) } ?? "Não informada"
            let text = """
            Dívida: \(debt.name). Valor Original: \(BRLFormatters.currency(debt.originalAmount)). \
            Status: \(statusStr). Data de Contratação: \(dateStr). \
            Banco/Credor: \(debt.bankPresetId ?? "Credor"). Notas: \(debt.notes).
            """
            docs.append(makeDocument(
                id: "debt_\(debt.id.uuidString)",
                entityId: debt.id,
                entityType: .debt,
                title: "Dívida: \(debt.name)",
                content: text,
                date: debt.contractedDate ?? debt.createdAt,
                amount: debt.originalAmount,
                isPaid: debt.isPaid,
                metadata: ["name": debt.name, "isPaid": String(debt.isPaid)]
            ))
        }

        // 5. Indexa Empréstimos e Financiamentos (Contratos de Crédito)
        for contract in store.contracts {
            let remInstallments = store.remainingInstallmentsCount(for: contract)
            let paidInstallments = store.paidTransactionsCount(forContract: contract)
            let nominalRem = store.remainingNominalAmount(for: contract)
            let projectedPayoff = store.projectedPayoffAmount(for: contract)
            let outstanding = store.currentOutstandingBalance(for: contract)
            let interestDiscount = max(0.0, nominalRem - projectedPayoff)
            let accName = store.account(for: contract.accountId)?.name ?? "Conta"
            let numStr = contract.contractNumber ?? "S/N"

            let text = """
            \(contract.kind.title): \(contract.name) (Modalidade: \(contract.subtypeDisplayName), Contrato nº \(numStr), Sistema: \(contract.amortizationSystem.rawValue)). \
            Conta Debitada: \(accName). Status: \(contract.isSettled ? "Quitado" : "Ativo"). \
            Valor da Parcela Mensal: \(BRLFormatters.currency(contract.installmentAmount)) (Vencimento dia \(contract.billingDay)). \
            Parcelas: \(paidInstallments) pagas, \(remInstallments) restantes de \(contract.totalInstallments) totais. \
            Taxa de Juros: \(String(format: "%.2f", contract.monthlyInterestRate))% ao mês. \
            Valor Contratado: \(BRLFormatters.currency(contract.totalContractedAmount)). \
            Saldo Devedor Atual: \(BRLFormatters.currency(outstanding)). \
            Projeção para Quitar Hoje (Valor Presente): \(BRLFormatters.currency(projectedPayoff)). \
            Soma Nominal das Parcelas Restantes: \(BRLFormatters.currency(nominalRem)). \
            Economia Potencial de Juros na Quitação: \(BRLFormatters.currency(interestDiscount)). \
            Total Extra Amortizado: \(BRLFormatters.currency(contract.extraAmortizedTotal)) (\(contract.amortizationHistory.count) amortizações registradas). \
            Notas: \(contract.notes).
            """
            docs.append(makeDocument(
                id: "contract_\(contract.id.uuidString)",
                entityId: contract.id,
                entityType: contract.kind == .loan ? .loan : .financing,
                title: "\(contract.kind.title): \(contract.name)",
                content: text,
                date: contract.startDate ?? contract.createdAt,
                amount: projectedPayoff,
                isPaid: contract.isSettled,
                accountId: contract.accountId,
                metadata: [
                    "name": contract.name,
                    "contractNumber": numStr,
                    "kind": contract.kind.rawValue,
                    "installmentAmount": String(contract.installmentAmount),
                    "remainingInstallments": String(remInstallments)
                ]
            ))
        }

        // 6. Indexa Envelopes de Provisão (Tetos de Categoria) e Cotas Específicas do Mês Selecionado
        let monthTitle = BRLFormatters.monthYear(store.selectedMonth)
        for env in store.provisionEnvelopes(for: store.selectedMonth) {
            let text = """
            Provisão / Envelope de Teto Mensal (\(monthTitle)): Categoria \(env.category.name). \
            Teto Orçado: \(BRLFormatters.currency(env.estimatedAmount)). \
            Gasto Realizado Avulso: \(BRLFormatters.currency(env.realizedExpense)). \
            Saldo Restante no Envelope: \(BRLFormatters.currency(env.remainingProvision)). \
            Excedente Estourado: \(BRLFormatters.currency(env.exceededAmount)). \
            Progresso: \(String(format: "%.1f%%", env.rawProgressPercentage)) (Status: \(env.status.rawValue)). \
            Repete para meses futuros: \(env.repeatForFutureMonths ? "Sim" : "Não").
            """
            docs.append(makeDocument(
                id: "provision_\(env.id.uuidString)_\(monthTitle)",
                entityId: env.provisionId,
                entityType: .provision,
                title: "Envelope/Teto: \(env.category.name) (\(monthTitle))",
                content: text,
                date: store.selectedMonth,
                amount: env.estimatedAmount,
                categoryId: env.category.id,
                metadata: ["categoryName": env.category.name, "status": env.status.rawValue]
            ))
        }

        for quota in store.allQuotaEnvelopes(for: store.selectedMonth) {
            let catName = store.category(for: quota.categoryId)?.name ?? "Categoria"
            let text = """
            Cota de Item Específico (\(monthTitle)): \(quota.name) (Categoria: \(catName)). \
            Quantidade Planejada: \(quota.plannedQuantity) unidades × \(BRLFormatters.currency(quota.estimatedUnitPrice))/un. = \(BRLFormatters.currency(quota.totalEstimatedAmount)). \
            Unidades Consumidas/Baixadas: \(quota.consumedUnits). Unidades Pendentes: \(quota.pendingUnits). \
            Provisão Restante da Cota: \(BRLFormatters.currency(quota.remainingProvision)). \
            Gasto Realizado nas Baixas: \(BRLFormatters.currency(quota.realizedExpense)). Status: \(quota.status.rawValue).
            """
            docs.append(makeDocument(
                id: "quota_\(quota.id.uuidString)_\(monthTitle)",
                entityId: quota.id,
                entityType: .quota,
                title: "Cota: \(quota.name) (\(monthTitle))",
                content: text,
                date: store.selectedMonth,
                amount: quota.totalEstimatedAmount,
                categoryId: quota.categoryId,
                metadata: ["name": quota.name, "categoryName": catName]
            ))
        }

        // 7. Indexa Resumos Mensais Consolidados (para todos os meses com movimentação próxima)
        var activeMonthDates: [String: Date] = [:]
        for offset in -6...12 {
            if let m = cal.date(byAdding: .month, value: offset, to: store.selectedMonth) {
                let comps = cal.dateComponents([.year, .month], from: m)
                let key = String(format: "%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
                activeMonthDates[key] = m
            }
        }
        for (_, mDate) in activeMonthDates.sorted(by: { $0.key < $1.key }) {
            let mTxs = store.transactionsForMonth(mDate).filter { !$0.ignoreInConsolidated }
            guard !mTxs.isEmpty || store.isInMonth(mDate, monthReference: store.selectedMonth) else { continue }
            let mLabel = BRLFormatters.monthYear(mDate)
            let incTotal = store.monthlyIncome(for: mDate)
            let expTotal = store.monthlyExpense(for: mDate)
            let paidExp = store.monthlyPaidExpense(for: mDate)
            let pendExp = store.monthlyPendingExpense(for: mDate)
            let provRem = store.totalRemainingProvision(for: mDate)
            let projEnd = store.accumulatedConsolidatedBalance(throughMonth: mDate, includeProjectedUnpaid: true)

            let text = """
            Resumo Mensal Consolidado de \(mLabel): \
            Receitas Totais: \(BRLFormatters.currency(incTotal)). \
            Despesas Totais: \(BRLFormatters.currency(expTotal)) (Pagas: \(BRLFormatters.currency(paidExp)), Pendentes: \(BRLFormatters.currency(pendExp))). \
            Provisões/Tetos Restantes: \(BRLFormatters.currency(provRem)). \
            Resultado Líquido do Mês: \(BRLFormatters.currency(incTotal - expTotal)). \
            Saldo Acumulado Projetado no Fim de \(mLabel): \(BRLFormatters.currency(projEnd)). \
            Quantidade de Lançamentos: \(mTxs.count).
            """
            docs.append(makeDocument(
                id: "month_summary_\(mLabel)",
                entityId: nil,
                entityType: .monthlySummary,
                title: "Resumo de \(mLabel)",
                content: text,
                date: mDate,
                amount: projEnd,
                metadata: ["monthLabel": mLabel]
            ))
        }

        // 8. Indexa Transações (priorizando horizonte operacional completo e todas as transações únicas/atuais)
        // Para evitar indexar 500 parcelas idênticas de 2040-2055 sem necessidade, indexamos integralmente todas as transações
        // de -24 meses até +24 meses ao redor do mês selecionado + todas as transações pagas + amostra de longo prazo.
        let minHorizon = cal.date(byAdding: .month, value: -24, to: store.selectedMonth) ?? Date.distantPast
        let maxHorizon = cal.date(byAdding: .month, value: 24, to: store.selectedMonth) ?? Date.distantFuture

        for tx in store.transactions {
            if !tx.isPaid && (tx.date < minHorizon || tx.date > maxHorizon) {
                // Mantém apenas a primeira e última parcela fora do horizonte de 4 anos para referência
                if let idx = tx.installmentIndex, let tot = tx.installmentTotal, idx > 2 && idx < tot {
                    continue
                }
            }
            let catName = store.category(for: tx.categoryId)?.name ?? "Outros"
            let accName = store.account(for: tx.accountId)?.name ?? "Conta"
            let dateStr = BRLFormatters.shortDate(tx.date)
            let monthStr = BRLFormatters.monthYear(tx.date)
            let statusStr = tx.isPaid ? (tx.type == .income ? "Recebido/Pago" : "Pago") : "Pendente/A Vencer"
            let badgeStr = tx.installmentBadge.map { "Parcela \($0)" } ?? tx.recurrenceMode.title

            let text = """
            Transação (\(tx.type.title)): \(tx.name). Valor: \(BRLFormatters.currency(tx.amount)). \
            Data: \(dateStr) (\(monthStr)). Status: \(statusStr). \
            Categoria: \(catName). Conta: \(accName). Modalidade: \(badgeStr). \
            Detalhes: \(tx.details). \(tx.ignoreInConsolidated ? "(Ignorado no consolidado)" : "")
            """
            docs.append(makeDocument(
                id: "tx_\(tx.id.uuidString)",
                entityId: tx.id,
                entityType: .transaction,
                title: "\(tx.type.title): \(tx.name) (\(dateStr))",
                content: text,
                date: tx.date,
                amount: tx.amount,
                isPaid: tx.isPaid,
                transactionType: tx.type,
                categoryId: tx.categoryId,
                accountId: tx.accountId,
                metadata: [
                    "name": tx.name,
                    "category": catName,
                    "account": accName,
                    "date": dateStr,
                    "month": monthStr,
                    "recurrence": tx.recurrenceMode.rawValue
                ]
            ))
        }

        self.documents = docs
        computeCorpusStatistics()
    }

    private func makeDocument(
        id: String,
        entityId: UUID?,
        entityType: RAGEntityType,
        title: String,
        content: String,
        date: Date? = nil,
        amount: Double? = nil,
        isPaid: Bool? = nil,
        transactionType: TransactionType? = nil,
        categoryId: UUID? = nil,
        accountId: UUID? = nil,
        metadata: [String: String] = [:]
    ) -> RAGDocument {
        let combined = "\(title) \(content)"
        let norm = Self.normalizeText(combined)
        let tokens = Self.tokenize(norm)
        let emb = Self.computeEmbedding(normalizedText: norm, tokens: tokens)
        return RAGDocument(
            id: id,
            entityId: entityId,
            entityType: entityType,
            title: title,
            content: content,
            normalizedText: norm,
            tokens: tokens,
            date: date,
            amount: amount,
            isPaid: isPaid,
            transactionType: transactionType,
            categoryId: categoryId,
            accountId: accountId,
            embedding: emb,
            metadata: metadata
        )
    }

    private func computeCorpusStatistics() {
        let n = Double(max(documents.count, 1))
        var df: [String: Int] = [:]
        var totalLen = 0

        for doc in documents {
            totalLen += doc.tokens.count
            let uniqueTokens = Set(doc.tokens)
            for t in uniqueTokens {
                df[t, default: 0] += 1
            }
        }

        self.avgDocLength = Double(max(totalLen, 1)) / n
        var idf: [String: Double] = [:]
        for (term, docFreq) in df {
            let val = log(1.0 + (n - Double(docFreq) + 0.5) / (Double(docFreq) + 0.5))
            idf[term] = max(val, 0.05)
        }
        self.idfByToken = idf
    }

    public func search(
        query: String,
        topK: Int = 12,
        allowedTypes: Set<RAGEntityType>? = nil,
        monthFilter: Date? = nil,
        calendar: Calendar = .current
    ) -> [RAGSearchResult] {
        let normQuery = Self.normalizeText(query)
        let queryTokens = Self.tokenize(normQuery)
        let queryEmbedding = Self.computeEmbedding(normalizedText: normQuery, tokens: queryTokens)

        let k1 = 1.5
        let b = 0.75
        var results: [RAGSearchResult] = []
        results.reserveCapacity(documents.count)

        for doc in documents {
            if let allowedTypes, !allowedTypes.contains(doc.entityType) {
                continue
            }
            if let monthFilter, let docDate = doc.date {
                let c1 = calendar.dateComponents([.year, .month], from: docDate)
                let c2 = calendar.dateComponents([.year, .month], from: monthFilter)
                if c1.year != c2.year || c1.month != c2.month {
                    continue
                }
            }

            // 1. Score Léxico BM25 + Substring Match
            var bm25 = 0.0
            if !queryTokens.isEmpty && !doc.tokens.isEmpty {
                var tfMap: [String: Int] = [:]
                for t in doc.tokens {
                    tfMap[t, default: 0] += 1
                }
                let docLen = Double(doc.tokens.count)
                for qt in queryTokens {
                    var matchedTF = Double(tfMap[qt] ?? 0)
                    if matchedTF == 0 && qt.count >= 4 {
                        // Prefix/Stem match (ex: "aliment" casa com "alimentacao", "financi" casa com "financiamento")
                        let prefix = String(qt.prefix(max(4, qt.count - 2)))
                        for (dt, count) in tfMap where dt.hasPrefix(prefix) || qt.hasPrefix(String(dt.prefix(max(4, dt.count - 1)))) {
                            matchedTF += Double(count) * 0.65
                        }
                    }
                    if matchedTF > 0 {
                        let idf = idfByToken[qt] ?? 1.2
                        let num = matchedTF * (k1 + 1.0)
                        let den = matchedTF + k1 * (1.0 - b + b * (docLen / max(avgDocLength, 1.0)))
                        bm25 += idf * (num / den)
                    }
                }
            }

            // Boost para frase ou nome de entidade explícito
            if let entityName = doc.metadata["name"] {
                let normName = Self.normalizeText(entityName)
                if normName.count >= 3 && normQuery.contains(normName) {
                    bm25 += 4.5
                }
            }

            // 2. Score Semântico (Cosine Similarity no vetor de 64 dimensões)
            let semScore = Self.cosineSimilarity(queryEmbedding, doc.embedding)

            // 3. Combinação Híbrida (BM25 normalizado + Similaridade Semântica)
            let normalizedBM25 = min(bm25 / 8.0, 1.5)
            let combined = (normalizedBM25 * 0.65) + (semScore * 0.35)

            if combined > 0.08 {
                results.append(
                    RAGSearchResult(
                        document: doc,
                        lexicalScore: bm25,
                        semanticScore: semScore,
                        combinedScore: combined
                    )
                )
            }
        }

        return results
            .sorted { $0.combinedScore > $1.combinedScore }
            .prefix(topK)
            .map { $0 }
    }

    public static func normalizeText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let quoteChars = CharacterSet(charactersIn: "'’‘`´\"“”")
        let withoutQuotes = folded.components(separatedBy: quoteChars).joined()
        return withoutQuotes.lowercased()
    }

    public static func tokenize(_ normalizedText: String) -> [String] {
        normalizedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    private static func computeEmbedding(normalizedText: String, tokens: [String]) -> [Double] {
        var vec = Array(repeating: 0.0, count: 64)
        let tokenSet = Set(tokens)

        // Primeiras 16 dimensões: conceitos semânticos do domínio financeiro
        for (clusterIdx, keywords) in semanticConceptClusters.prefix(16).enumerated() {
            var hits = 0.0
            for kw in keywords {
                if tokenSet.contains(kw) || normalizedText.contains(kw) {
                    hits += 1.0
                }
            }
            vec[clusterIdx] = min(hits / 2.0, 1.5)
        }

        // 48 dimensões seguintes: Hashing de Trigramas de Caracteres (robusto contra erros de digitação e flexões)
        let clean = tokens.joined(separator: " ")
        let chars = Array(clean)
        if chars.count >= 3 {
            for i in 0..<(chars.count - 2) {
                let h1 = UInt32(chars[i].asciiValue ?? 97)
                let h2 = UInt32(chars[i + 1].asciiValue ?? 97)
                let h3 = UInt32(chars[i + 2].asciiValue ?? 97)
                let hash = Int((h1 &* 31 &+ h2 &* 17 &+ h3) % 48)
                vec[16 + hash] += 0.25
            }
        }

        // Normalização L2
        let norm = sqrt(vec.reduce(0.0) { $0 + $1 * $1 })
        if norm > 1e-6 {
            for i in vec.indices {
                vec[i] /= norm
            }
        }
        return vec
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
        }
        return max(0.0, dot)
    }
}

// MARK: - Conversational Session State & Multi-Turn Loop Memory

public enum AgentConversationTopic: String, Codable, Hashable {
    case spendingPaceAndMonthEnd = "Ritmo de Gastos & Projeção de Fim de Mês"
    case transactionsQuery = "Consulta de Transações e Categorias"
    case provisionsAndQuotas = "Previsões, Envelopes e Cotas"
    case debtPayoff = "Análise e Quitação de Dívidas"
    case contractActionPlan = "Empréstimos e Financiamentos"
    case periodOverdraftProjection = "Projeção de Fluxo de Caixa e Débito"
    case accountsAndInvestments = "Contas Bancárias e Investimentos"
    case whatIfSimulation = "Simulação Financeira (E se...)"
    case generalOverview = "Panorama Geral da Base"
}

public enum AgentPendingQuestionKind: String, Codable, Hashable {
    case selectContract
    case selectDebt
    case selectFollowUpActionOnPace
    case selectSimulationParameter
    case generalFollowUp
}

public struct AgentSessionMemory {
    public var activeTopic: AgentConversationTopic? = nil
    public var pendingQuestionKind: AgentPendingQuestionKind? = nil
    public var candidateContractIds: [UUID] = []
    public var candidateDebtIds: [UUID] = []
    public var lastTargetMonth: Date? = nil
    public var lastCategoryId: UUID? = nil
    public var lastAccountId: UUID? = nil
    public var lastDailyPaceAmount: Double? = nil
    public var loopTurnCount: Int = 0
    public var isConversationConcluded: Bool = false

    // Anaphoric multi-turn memory
    public var lastMentionedCategoryId: UUID? = nil
    public var lastMentionedCategoryName: String? = nil
    public var lastMentionedContractId: UUID? = nil
    public var lastMentionedContractIds: [UUID] = []
    public var lastMentionedDebtId: UUID? = nil
    public var lastMentionedMonth: Date? = nil
    public var lastMentionedYear: Int? = nil
    public var lastIntentKind: FinancialIntentKind? = nil

    public init() {}

    public mutating func resetTopicMemory() {
        activeTopic = nil
        pendingQuestionKind = nil
        candidateContractIds = []
        candidateDebtIds = []
        lastCategoryId = nil
        lastAccountId = nil
        lastDailyPaceAmount = nil
        lastMentionedCategoryId = nil
        lastMentionedCategoryName = nil
        lastMentionedContractId = nil
        lastMentionedDebtId = nil
        lastMentionedMonth = nil
        lastMentionedYear = nil
    }
}

public struct AgentExecutionOutput {
    public let responseMarkdown: String
    public let executedSteps: [String]
    public let suggestedFollowUps: [String]
    public let shouldCloseChat: Bool
    public let updatedMemory: AgentSessionMemory
}

// MARK: - Multi-Agent Architecture: Models & Briefings

public enum ExpectedResponseLength: String, Codable, Hashable {
    case concise = "Curta e Direta"
    case moderate = "Moderada / Tópicos"
    case analytical = "Analítica / Detalhada"
}

public enum FinancialIntentKind: String, Codable, Hashable {
    case latestTransaction = "Última Transação"
    case recentTransactionsList = "Lista de Transações Recentes"
    case spendingPaceAndProjection = "Ritmo de Gastos e Projeção de Fim de Mês"
    case topExpenseCategories = "Ranking e Categoria Mais Gasta"
    case upcomingContractInstallments = "Próximas Parcelas de Financiamentos e Empréstimos"
    case categoryExpenseQuery = "Despesas por Categoria"
    case pendingBillsQuery = "Contas e Despesas Pendentes"
    case currentBalanceAndLiquidity = "Saldo em Contas e Patrimônio"
    case loanOrFinancingSimulation = "Empréstimos, Financiamentos e Amortização"
    case debtPayoffPlan = "Quitação de Dívidas e Acordos"
    case envelopeBudgetQuery = "Envelopes e Tetos Orçamentários"
    case quotaBudgetQuery = "Cotas Específicas por Unidade"
    case whatIfSimulation = "Simulação de Cenários (E se...)"
    case periodOverdraftForecast = "Intervalo de Datas e Previsão de Débito"
    case generalOverview = "Panorama Geral da Base"
    case conversationClosing = "Encerramento da Conversa"
    case nonFinancial = "Fora do Escopo Financeiro"
}

public enum ConversationContextMode: Codable, Hashable {
    case newTopic(description: String)
    case followUp(topic: FinancialIntentKind, entityName: String?)
    case replyToAgentClarification(questionKind: AgentPendingQuestionKind)

    public var label: String {
        switch self {
        case .newTopic(let desc):
            return "Novo Tópico (\(desc))"
        case .followUp(let topic, let entity):
            let entityStr = entity.map { ": \($0)" } ?? ""
            return "Continuação/Follow-Up (\(topic.rawValue)\(entityStr))"
        case .replyToAgentClarification(let qKind):
            return "Resposta à Pergunta do Agente (\(qKind.rawValue))"
        }
    }
}

public struct QueryAnalysisBriefing {
    public let originalPrompt: String
    public let normalizedPrompt: String
    public let intentKind: FinancialIntentKind
    public let expectedLength: ExpectedResponseLength
    public let contextMode: ConversationContextMode
    public let previousTurnSummary: String?
    public let standardizedSearchQuery: String
    public let targetCategoryName: String?
    public let targetAccountName: String?
    public let targetDateRange: (start: Date, end: Date)?
    public let targetMonth: Date
    public let numericParameters: [Double]
    public let transactionTypeFilter: TransactionType?
    public let tone: String

    public init(
        originalPrompt: String,
        normalizedPrompt: String,
        intentKind: FinancialIntentKind,
        expectedLength: ExpectedResponseLength,
        contextMode: ConversationContextMode = .newTopic(description: "Novo tópico financeiro"),
        previousTurnSummary: String? = nil,
        standardizedSearchQuery: String,
        targetCategoryName: String? = nil,
        targetAccountName: String? = nil,
        targetDateRange: (start: Date, end: Date)? = nil,
        targetMonth: Date,
        numericParameters: [Double] = [],
        transactionTypeFilter: TransactionType? = nil,
        tone: String
    ) {
        self.originalPrompt = originalPrompt
        self.normalizedPrompt = normalizedPrompt
        self.intentKind = intentKind
        self.expectedLength = expectedLength
        self.contextMode = contextMode
        self.previousTurnSummary = previousTurnSummary
        self.standardizedSearchQuery = standardizedSearchQuery
        self.targetCategoryName = targetCategoryName
        self.targetAccountName = targetAccountName
        self.targetDateRange = targetDateRange
        self.targetMonth = targetMonth
        self.numericParameters = numericParameters
        self.transactionTypeFilter = transactionTypeFilter
        self.tone = tone
    }
}

public struct TransactionFactDetail: Hashable {
    public let id: UUID
    public let name: String
    public let details: String
    public let amount: Double
    public let date: Date
    public let formattedDateTime: String
    public let type: TransactionType
    public let isPaid: Bool
    public let categoryName: String
    public let categoryColorHex: String
    public let accountName: String
}

public struct RetrievalExecutionPayload {
    public var intentKind: FinancialIntentKind
    public var expectedLength: ExpectedResponseLength
    public var isSuccess: Bool
    public var primaryFactSummary: String
    public var transactionFacts: [TransactionFactDetail]
    public var accountFacts: [String]
    public var metricFacts: [String: String]
    public var rawResultMarkdown: String?
    public var ragHits: [RAGSearchResult]
    public var suggestedFollowUps: [String]
    public var retryCount: Int
    public var criticNotes: [String]
}

public struct CriticValidationResult {
    public let isValid: Bool
    public let feedbackForPlanner: String?
    public let approvedPayload: RetrievalExecutionPayload
}

// MARK: - Agentic Financial Engine (Multi-Agent Cooperative Pipeline + Unlimited DB + RAG)

@MainActor
public final class AgenticFinancialEngine {

    private static var sessionMemoryByStoreId: [ObjectIdentifier: AgentSessionMemory] = [:]

    public static func memory(for store: FinancialDataStore) -> AgentSessionMemory {
        if store.chatHistory.isEmpty {
            let mem = AgentSessionMemory()
            sessionMemoryByStoreId[ObjectIdentifier(store)] = mem
            return mem
        }
        let key = ObjectIdentifier(store)
        if let existing = sessionMemoryByStoreId[key] {
            return existing
        }
        let inferred = inferMemoryFromChatHistory(store: store)
        sessionMemoryByStoreId[key] = inferred
        return inferred
    }

    public static func saveMemory(_ memory: AgentSessionMemory, for store: FinancialDataStore) {
        sessionMemoryByStoreId[ObjectIdentifier(store)] = memory
    }

    public static func resetMemory(for store: FinancialDataStore) {
        sessionMemoryByStoreId[ObjectIdentifier(store)] = AgentSessionMemory()
    }

    /// Infere o contexto da conversa a partir das últimas mensagens de `store.chatHistory`
    /// caso o usuário esteja respondendo a uma pergunta anterior do agente.
    private static func inferMemoryFromChatHistory(store: FinancialDataStore) -> AgentSessionMemory {
        var mem = AgentSessionMemory()
        let assistantMessages = store.chatHistory.filter { $0.role == .assistant }
        guard let lastAssistant = assistantMessages.last else { return mem }
        let norm = FinancialRAGIndex.normalizeText(lastAssistant.content)

        if norm.contains("qual financiamento voce deseja analisar") {
            mem.activeTopic = .contractActionPlan
            mem.pendingQuestionKind = .selectContract
            mem.candidateContractIds = store.activeContracts(for: .financing).map(\.id)
        } else if norm.contains("qual emprestimo voce deseja analisar") {
            mem.activeTopic = .contractActionPlan
            mem.pendingQuestionKind = .selectContract
            mem.candidateContractIds = store.activeContracts(for: .loan).map(\.id)
        } else if norm.contains("nao identifiquei exatamente qual divida") {
            mem.activeTopic = .debtPayoff
            mem.pendingQuestionKind = .selectDebt
            mem.candidateDebtIds = store.activeDebts.map(\.id)
        } else if norm.contains("ritmo de gastos") || norm.contains("continuar gastando") {
            mem.activeTopic = .spendingPaceAndMonthEnd
            mem.pendingQuestionKind = .selectFollowUpActionOnPace
        }
        return mem
    }

    // MARK: - Multi-Agent Collaborative Architecture: Agente 1 -> Agente 2 <-> Agente 3 -> Agente 4

    public static func runAgentLoop(
        prompt: String,
        store: FinancialDataStore,
        modelLabel: String,
        onStepUpdate: ((String) -> Void)? = nil
    ) -> AgentExecutionOutput {
        var steps: [String] = []
        func recordStep(_ description: String) {
            steps.append(description)
            onStepUpdate?(description)
        }

        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normPrompt = FinancialRAGIndex.normalizeText(cleanPrompt)
        var mem = memory(for: store)
        mem.loopTurnCount += 1

        // =========================================================================
        // AGENTE 1: ANALISADOR FIXO DE INTENÇÃO, PERFIL E CONTEXTO CONVERSACIONAL
        // Avalia o tom, o contexto (novo tópico vs continuação/resposta) e determina
        // a extensão esperada (.concise vs .moderate vs .analytical) para orientar o RAG.
        // =========================================================================
        let briefing = analyzeQueryIntentAndProfile(
            prompt: cleanPrompt,
            normPrompt: normPrompt,
            store: store,
            memory: mem
        )
        recordStep("🤖 Agente 1 (Intenção & Contexto): Modo: `\(briefing.contextMode.label)` • Intenção: `\(briefing.intentKind.rawValue)` • Perfil: `\(briefing.expectedLength.rawValue)` • Tom: `\(briefing.tone)`")

        // Caso seja novo tópico, isola o contexto e reseta travas/tópicos pendentes de turnos anteriores
        if case .newTopic = briefing.contextMode {
            mem.resetTopicMemory()
        }

        // 0. Caso seja intenção explícita de encerramento do chat pelo usuário
        if briefing.intentKind == .conversationClosing {
            recordStep("🎯 Agente 1: Intenção de encerramento do diálogo confirmada")
            mem.isConversationConcluded = true
            mem.pendingQuestionKind = nil
            saveMemory(mem, for: store)

            let closingOutput = synthesizeClosingResponse(store: store, steps: steps, memory: mem)
            return closingOutput
        }

        mem.isConversationConcluded = false

        // 1. Constrói / Atualiza o Índice RAG sobre 100% da base local
        recordStep("📚 Indexando base local completa via RAG (Transações, Contas, Categorias, Investimentos, Dívidas, Contratos, Envelopes e Cotas)")
        let ragIndex = FinancialRAGIndex(store: store)
        let ragHits = ragIndex.search(query: briefing.standardizedSearchQuery, topK: 10)
        if !ragHits.isEmpty {
            let hitTypes = Array(Set(ragHits.prefix(5).map { $0.document.entityType.rawValue })).sorted().joined(separator: ", ")
            recordStep("🔍 RAG recuperou \(ragHits.count) registros relevantes (\(hitTypes))")
        }

        // =========================================================================
        // LOOP COOPERATIVO: AGENTE 2 (PLANEJADOR & BUSCA) <-> AGENTE 3 (AGENTE JUIZ)
        // O Agente 2 executa a ação/busca direcionada. O Agente Juiz (Agente 3)
        // valida se o resultado é adequado, alinhado à pergunta atual e livre de
        // vazamentos de contexto da pergunta ou turno anterior. Se inadequado, rejeita
        // e solicita correção imediata.
        // =========================================================================
        var retryCount = 0
        var criticFeedback: String? = nil
        var approvedPayload: RetrievalExecutionPayload? = nil

        let previousAssistantMessage: String? = {
            if let last = store.chatHistory.last, last.role == .user, last.content == cleanPrompt {
                return store.chatHistory.dropLast().last(where: { $0.role == .assistant })?.content
            }
            return store.chatHistory.last(where: { $0.role == .assistant })?.content
        }()

        let previousUserPrompt: String? = {
            if let last = store.chatHistory.last, last.role == .user, last.content == cleanPrompt {
                return store.chatHistory.dropLast().last(where: { $0.role == .user })?.content
            }
            return store.chatHistory.last(where: { $0.role == .user })?.content
        }()

        while retryCount < 2 && approvedPayload == nil {
            let attemptLabel = retryCount > 0 ? " [Tentativa de Correção #\(retryCount + 1)]" : ""
            recordStep("🔎 Agente 2 (Planejador & Busca RAG): Executando busca direcionada na base local para `\(briefing.intentKind.rawValue)`\(attemptLabel)...")

            let payload = executeRetrievalPlan(
                briefing: briefing,
                store: store,
                ragHits: ragHits,
                ragIndex: ragIndex,
                memory: &mem,
                modelLabel: modelLabel,
                retryCount: retryCount,
                criticFeedback: criticFeedback,
                recordStep: recordStep
            )

            recordStep("⚖️ Agente Juiz (Conformidade & Contexto): Avaliando alinhamento da resposta à pergunta atual e verificando isolamento de contexto anterior...")

            let validation = judgeRetrievalAgainstQuestionAndContext(
                briefing: briefing,
                payload: payload,
                previousUserPrompt: previousUserPrompt,
                previousAssistantResponse: previousAssistantMessage,
                store: store
            )

            if validation.isValid {
                approvedPayload = validation.approvedPayload
                recordStep("✅ Agente 3 (Agente Juiz • Conformidade & Contexto): Dados aprovados com sucesso. Resposta validada e sem vazamento de contexto.")
            } else {
                criticFeedback = validation.feedbackForPlanner
                recordStep("⚠️ Agente Juiz (Conformidade & Contexto): Rejeitado – \(criticFeedback ?? "Ajustar parâmetros de busca"). Solicitando refinamento ao Agente 2...")
                retryCount += 1
            }
        }

        let finalPayload = approvedPayload ?? executeRetrievalPlan(
            briefing: briefing,
            store: store,
            ragHits: ragHits,
            ragIndex: ragIndex,
            memory: &mem,
            modelLabel: modelLabel,
            retryCount: retryCount,
            criticFeedback: nil,
            recordStep: recordStep
        )

        // =========================================================================
        // AGENTE 4: SINTETIZADOR FINAL & FORMATADOR DE PERSONA
        // Aplica o tom, humor e tamanho ideal definidos pelo Agente 1 (curto e direto
        // para perguntas pontuais, analítico para simulações e projeções complexas).
        // =========================================================================
        recordStep("✍️ Agente 4 (Síntese & Formatação): Gerando resposta final no tom `\(briefing.tone)` com tamanho `\(briefing.expectedLength.rawValue)`...")

        let synthesized = synthesizeFinalResponse(
            briefing: briefing,
            payload: finalPayload,
            store: store,
            steps: steps,
            memory: mem
        )

        saveMemory(mem, for: store)
        return synthesized
    }

    // MARK: - Agente 1: Analisador Fixo de Intenção, Contexto e Perfil da Pergunta

    private static func analyzeQueryIntentAndProfile(
        prompt: String,
        normPrompt: String,
        store: FinancialDataStore,
        memory: AgentSessionMemory
    ) -> QueryAnalysisBriefing {
        let previousAssistantMessage: String? = {
            if let last = store.chatHistory.last, last.role == .user, last.content == prompt {
                return store.chatHistory.dropLast().last(where: { $0.role == .assistant })?.content
            }
            return store.chatHistory.last(where: { $0.role == .assistant })?.content
        }()

        let previousUserPrompt: String? = {
            if let last = store.chatHistory.last, last.role == .user, last.content == prompt {
                return store.chatHistory.dropLast().last(where: { $0.role == .user })?.content
            }
            return store.chatHistory.last(where: { $0.role == .user })?.content
        }()

        let previousTurnSummary: String? = {
            guard let userQ = previousUserPrompt, !userQ.isEmpty else { return nil }
            let shortUser = String(userQ.prefix(60))
            let assistantSnippet = (previousAssistantMessage ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(80)
            return "Turno anterior: Usuário perguntou '\(shortUser)' | Assistente respondeu: '\(assistantSnippet)...'"
        }()

        // 1. Encerramento explícito do diálogo
        if isConversationClosingIntent(normPrompt) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .conversationClosing,
                expectedLength: .concise,
                contextMode: .newTopic(description: "Encerramento do diálogo"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "encerramento",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "cordial e conclusivo"
            )
        }

        // 2. Não-financeiro (Guardrail)
        if isStrictlyNonFinancial(normPrompt) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .nonFinancial,
                expectedLength: .concise,
                contextMode: .newTopic(description: "Fora do escopo financeiro"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "guardrail",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "focado e objetivo"
            )
        }

        // 3. Intenções independentes autônomas (NOVO TÓPICO explícito)
        // Se a pergunta contiver sujeito e verbos próprios de uma intenção financeira,
        // ela é SEMPRE um novo tópico, mesmo que mencione meses relativos ou termos temporais!

        // 3.1 Próximas parcelas de financiamentos e empréstimos
        if isUpcomingContractInstallmentsQuery(normPrompt) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .upcomingContractInstallments,
                expectedLength: .moderate,
                contextMode: .newTopic(description: "Próximas Parcelas de Financiamentos e Empréstimos"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "parcelas financiamentos empréstimos contratos próximo mês vencimentos",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: .expense,
                tone: "organizado, transparente e pontual"
            )
        }

        // 3.2 Categoria em que mais gasta / Ranking de categorias
        if isTopExpenseCategoriesQuery(normPrompt) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .topExpenseCategories,
                expectedLength: .concise,
                contextMode: .newTopic(description: "Ranking e Categoria Mais Gasta"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "categoria que mais gasto maiores despesas ranking despesas",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: .expense,
                tone: "consultivo, claro e objetivo"
            )
        }

        // 3.3 Ritmo de gastos diário (burn rate) & projeção de fim de mês
        if isSpendingPaceOrEndOfMonthBalanceQuery(normPrompt) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .spendingPaceAndProjection,
                expectedLength: .analytical,
                contextMode: .newTopic(description: "Ritmo de Gastos e Projeção de Fim de Mês"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "ritmo de gastos média diária burn rate projeção fim do mês envelopes",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "consultivo e analítico"
            )
        }

        // 3.4 Última transação pontual
        if isLatestTransactionQuery(normPrompt) {
            let filter: TransactionType?
            if normPrompt.contains("gasto") || normPrompt.contains("despesa") || normPrompt.contains("compra") || normPrompt.contains("pagamento") {
                filter = .expense
            } else if normPrompt.contains("receita") || normPrompt.contains("entrada") || normPrompt.contains("salario") || normPrompt.contains("recebimento") {
                filter = .income
            } else {
                filter = nil
            }
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .latestTransaction,
                expectedLength: .concise,
                contextMode: .newTopic(description: "Última Transação"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "última transação recente lançamento",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: filter,
                tone: "direto, amigável e conciso"
            )
        }

        // 3.5 Lista de transações recentes
        if isRecentTransactionsListQuery(normPrompt) {
            let filter: TransactionType? = (normPrompt.contains("gasto") || normPrompt.contains("despesa")) ? .expense : nil
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .recentTransactionsList,
                expectedLength: .moderate,
                contextMode: .newTopic(description: "Transações Recentes"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "transações recentes extrato lançamentos",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: filter,
                tone: "direto e organizado"
            )
        }

        // 3.6 Saldo imediato / Liquidez nas contas
        if isBalanceQuery(normPrompt) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .currentBalanceAndLiquidity,
                expectedLength: .concise,
                contextMode: .newTopic(description: "Saldo e Liquidez"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "saldo contas bancárias liquidez disponível",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "direto e claro"
            )
        }

        // 3.7 Contas a pagar / Boletos pendentes
        if isPendingBillsQuery(normPrompt) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .pendingBillsQuery,
                expectedLength: .moderate,
                contextMode: .newTopic(description: "Contas e Boletos Pendentes"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "contas pendentes boletos a vencer despesas não pagas",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: .expense,
                tone: "organizado e pontual"
            )
        }

        // 3.8 Previsões, Envelopes Dinâmicos e Cotas
        if isProvisionOrQuotaIntent(prompt: prompt, normPrompt: normPrompt) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .envelopeBudgetQuery,
                expectedLength: .moderate,
                contextMode: .newTopic(description: "Envelopes e Tetos Orçamentários"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "previsões envelopes tetos de gastos cotas específicas",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: .expense,
                tone: "organizado e orientador"
            )
        }

        // 3.9 Simulador E se...
        if isWhatIfSimulationQuery(normPrompt) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .whatIfSimulation,
                expectedLength: .moderate,
                contextMode: .newTopic(description: "Simulação de Cenários (E se...)"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "simulação financeira impacto no caixa corte de gastos compras futuras",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "simulador e consultivo"
            )
        }

        // 3.10 Contratos, empréstimos e financiamentos específicos
        if isContractOrAmortizationQuery(prompt: prompt, normPrompt: normPrompt, store: store) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .loanOrFinancingSimulation,
                expectedLength: .analytical,
                contextMode: .newTopic(description: "Empréstimos e Financiamentos"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "empréstimos financiamentos contratos amortização quitação juros parcelas",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "consultivo e detalhado"
            )
        }

        // 3.11 Dívidas em aberto e acordos
        if isDebtPayoffOrNegotiationQuery(prompt: prompt, normPrompt: normPrompt, store: store) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .debtPayoffPlan,
                expectedLength: .analytical,
                contextMode: .newTopic(description: "Quitação de Dívidas"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "dívidas em aberto acordos quitação cronograma seguro intra-mês",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "estratégico e cuidadoso"
            )
        }

        // 3.12 Intervalo de datas / Débito futuro / Runway
        if isPeriodOrOverdraftQuery(prompt: prompt, normPrompt: normPrompt) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .periodOverdraftForecast,
                expectedLength: .analytical,
                contextMode: .newTopic(description: "Previsão de Período e Débito"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "período fluxo de caixa saldo futuro previsão de débito cheque especial",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: LocalLLMService.extractDateRange(from: prompt),
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "preventivo e analítico"
            )
        }

        // 4. Casos de Continuidade / Resposta à pergunta do Agente (Multi-Turn)
        // Quando a pergunta NÃO é uma intenção autônoma independente, avaliamos o contexto anterior:

        // 4.1 Resposta à escolha de contrato anterior
        if memory.pendingQuestionKind == .selectContract, !memory.candidateContractIds.isEmpty {
            let candidates = memory.candidateContractIds.compactMap { id in store.contracts.first(where: { $0.id == id }) }
            if matchCandidateContractFromReply(normPrompt: normPrompt, candidates: candidates) != nil && normPrompt.count <= 40 {
                return QueryAnalysisBriefing(
                    originalPrompt: prompt,
                    normalizedPrompt: normPrompt,
                    intentKind: .loanOrFinancingSimulation,
                    expectedLength: .analytical,
                    contextMode: .replyToAgentClarification(questionKind: .selectContract),
                    previousTurnSummary: previousTurnSummary,
                    standardizedSearchQuery: "amortização plano contrato",
                    targetCategoryName: nil,
                    targetAccountName: nil,
                    targetDateRange: nil,
                    targetMonth: store.selectedMonth,
                    numericParameters: [],
                    transactionTypeFilter: nil,
                    tone: "prestativo e conclusivo"
                )
            }
        }

        // 4.2 Resposta à escolha de dívida anterior
        if memory.pendingQuestionKind == .selectDebt, !memory.candidateDebtIds.isEmpty {
            let candidates = memory.candidateDebtIds.compactMap { id in store.debts.first(where: { $0.id == id }) }
            if matchCandidateDebtFromReply(normPrompt: normPrompt, candidates: candidates) != nil && normPrompt.count <= 40 {
                return QueryAnalysisBriefing(
                    originalPrompt: prompt,
                    normalizedPrompt: normPrompt,
                    intentKind: .debtPayoffPlan,
                    expectedLength: .analytical,
                    contextMode: .replyToAgentClarification(questionKind: .selectDebt),
                    previousTurnSummary: previousTurnSummary,
                    standardizedSearchQuery: "plano quitação dívida selecionada",
                    targetCategoryName: nil,
                    targetAccountName: nil,
                    targetDateRange: nil,
                    targetMonth: store.selectedMonth,
                    numericParameters: [],
                    transactionTypeFilter: nil,
                    tone: "prestativo e estratégico"
                )
            }
        }

        // 4.3 Resposta afirmativa após análise de ritmo de gastos ("Sim", "Mostre", "Onde cortar")
        if (memory.pendingQuestionKind == .selectFollowUpActionOnPace || memory.activeTopic == .spendingPaceAndMonthEnd) {
            let affirmativeShortReplies = [
                "sim", "quero", "pode mostrar", "mostre", "mostrar", "detalhe", "detalhar",
                "quais foram", "onde cortar", "como economizar", "simule", "simular"
            ]
            if normPrompt.count <= 38 && affirmativeShortReplies.contains(where: { normPrompt.contains($0) }) {
                return QueryAnalysisBriefing(
                    originalPrompt: prompt,
                    normalizedPrompt: normPrompt,
                    intentKind: .spendingPaceAndProjection,
                    expectedLength: .analytical,
                    contextMode: .replyToAgentClarification(questionKind: .selectFollowUpActionOnPace),
                    previousTurnSummary: previousTurnSummary,
                    standardizedSearchQuery: "detalhamento ritmo corte de despesas",
                    targetCategoryName: nil,
                    targetAccountName: nil,
                    targetDateRange: nil,
                    targetMonth: memory.lastTargetMonth ?? store.selectedMonth,
                    numericParameters: [],
                    transactionTypeFilter: nil,
                    tone: "consultivo e analítico"
                )
            }
        }

        // 4.4 Pergunta anafórica sobre contrato ("quanto falta para quitar o primeiro?", "qual o saldo devedor dele?")
        if isAnaphoricContractPayoffFollowUp(normPrompt) {
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .loanOrFinancingSimulation,
                expectedLength: .analytical,
                contextMode: .followUp(topic: .loanOrFinancingSimulation, entityName: "contrato selecionado"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "quitação contrato valor presente saldo devedor",
                targetCategoryName: nil,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: store.selectedMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "consultivo e transparente"
            )
        }

        // 4.5 Pergunta anafórica sobre categoria ("dessa categoria", "nela", "quanto gastei nela")
        if isAnaphoricCategoryFollowUp(normPrompt), (memory.lastMentionedCategoryId != nil || memory.lastCategoryId != nil) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: memory.lastTargetMonth ?? store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .categoryExpenseQuery,
                expectedLength: .moderate,
                contextMode: .followUp(topic: .categoryExpenseQuery, entityName: memory.lastMentionedCategoryName),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "despesas categoria \(memory.lastMentionedCategoryName ?? "")",
                targetCategoryName: memory.lastMentionedCategoryName,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: .expense,
                tone: "prestativo e detalhado"
            )
        }

        // 4.6 Mudança anafórica de período temporal ("e no mês passado?", "e em 2025?")
        if isAnaphoricTimeShiftFollowUp(normPrompt), let lastIntent = memory.lastIntentKind {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: memory.lastTargetMonth ?? store.selectedMonth)
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: lastIntent,
                expectedLength: .moderate,
                contextMode: .followUp(topic: lastIntent, entityName: nil),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: "continuidade período \(BRLFormatters.monthYear(targetMonth))",
                targetCategoryName: memory.lastMentionedCategoryName,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: nil,
                tone: "consultivo e direto"
            )
        }

        // 5. Despesas por categoria específicas por nome
        if isTransactionsOrCategorySpecificQuery(normPrompt, store: store) {
            let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
            let matchedCat = store.categories.first { cat in
                let norm = FinancialRAGIndex.normalizeText(cat.name)
                return norm.count >= 4 && normPrompt.contains(norm)
            }
            return QueryAnalysisBriefing(
                originalPrompt: prompt,
                normalizedPrompt: normPrompt,
                intentKind: .categoryExpenseQuery,
                expectedLength: .moderate,
                contextMode: .newTopic(description: "Despesas por Categoria"),
                previousTurnSummary: previousTurnSummary,
                standardizedSearchQuery: matchedCat != nil ? "despesas categoria \(matchedCat!.name)" : "despesas e transações",
                targetCategoryName: matchedCat?.name,
                targetAccountName: nil,
                targetDateRange: nil,
                targetMonth: targetMonth,
                numericParameters: [],
                transactionTypeFilter: .expense,
                tone: "específico e pontual"
            )
        }

        // 6. Panorama geral explícito (somente quando expressamente solicitado) ou fallback
        let isOverviewExplicit = normPrompt.contains("panorama") || normPrompt.contains("visao geral") ||
                                 normPrompt.contains("resumo geral") || normPrompt.contains("resumo completo") ||
                                 normPrompt.contains("resumo de tudo")
        return QueryAnalysisBriefing(
            originalPrompt: prompt,
            normalizedPrompt: normPrompt,
            intentKind: .generalOverview,
            expectedLength: isOverviewExplicit ? .analytical : .moderate,
            contextMode: .newTopic(description: "Visão Geral"),
            previousTurnSummary: previousTurnSummary,
            standardizedSearchQuery: "panorama financeiro completo saldo patrimônio dívidas investimentos",
            targetCategoryName: nil,
            targetAccountName: nil,
            targetDateRange: nil,
            targetMonth: store.selectedMonth,
            numericParameters: [],
            transactionTypeFilter: nil,
            tone: isOverviewExplicit ? "executivo e panorâmico" : "consultivo"
        )
    }

    // MARK: - Agente 2: Planejador e Executor de Ferramentas / Busca RAG

    private static func executeRetrievalPlan(
        briefing: QueryAnalysisBriefing,
        store: FinancialDataStore,
        ragHits: [RAGSearchResult],
        ragIndex: FinancialRAGIndex,
        memory: inout AgentSessionMemory,
        modelLabel: String,
        retryCount: Int,
        criticFeedback: String?,
        recordStep: (String) -> Void
    ) -> RetrievalExecutionPayload {
        // Se o Agente Juiz solicitou correção específica, força o redirecionamento adequado
        if let feedback = criticFeedback {
            if feedback.contains("retrieveUpcomingContractInstallments") || briefing.intentKind == .upcomingContractInstallments {
                return retrieveUpcomingContractInstallments(briefing: briefing, store: store, memory: &memory)
            }
            if feedback.contains("retrieveLatestTransaction") || briefing.intentKind == .latestTransaction {
                return retrieveLatestTransaction(briefing: briefing, store: store)
            }
            if feedback.contains("retrieveTopExpenseCategories") || briefing.intentKind == .topExpenseCategories {
                return retrieveTopExpenseCategories(briefing: briefing, store: store, memory: &memory)
            }
        }

        // Resolução para respostas de esclarecimento à pergunta do agente (Multi-Turn)
        if case .replyToAgentClarification(let qKind) = briefing.contextMode {
            switch qKind {
            case .selectContract:
                let candidates = memory.candidateContractIds.compactMap { id in store.contracts.first(where: { $0.id == id }) }
                if let selected = matchCandidateContractFromReply(normPrompt: briefing.normalizedPrompt, candidates: candidates) {
                    recordStep("🔄 Continuidade Multi-Turn: Contrato '\(selected.name)' selecionado a partir da pergunta anterior")
                    memory.pendingQuestionKind = nil
                    let plan = LocalLLMService.buildContractPayoffActionPlan(for: selected, store: store)
                    return RetrievalExecutionPayload(
                        intentKind: .loanOrFinancingSimulation,
                        expectedLength: .analytical,
                        isSuccess: true,
                        primaryFactSummary: "Plano de amortização para o contrato \(selected.name)",
                        transactionFacts: [],
                        accountFacts: [],
                        metricFacts: [:],
                        rawResultMarkdown: plan,
                        ragHits: ragHits,
                        suggestedFollowUps: [
                            "E se eu amortizar R$ 1.000 extras por mês neste contrato?",
                            "Compare este contrato com minhas outras dívidas",
                            "Obrigado, pode encerrar"
                        ],
                        retryCount: retryCount,
                        criticNotes: []
                    )
                }
            case .selectDebt:
                let candidates = memory.candidateDebtIds.compactMap { id in store.debts.first(where: { $0.id == id }) }
                if let selected = matchCandidateDebtFromReply(normPrompt: briefing.normalizedPrompt, candidates: candidates) {
                    recordStep("🔄 Continuidade Multi-Turn: Dívida '\(selected.name)' selecionada a partir da pergunta anterior")
                    memory.pendingQuestionKind = nil
                    let analysis = LocalLLMService.analyzeDebtPayoffTimeline(
                        prompt: "Em quanto tempo devo pagar a dívida \(selected.name)?",
                        normalizedPrompt: FinancialRAGIndex.normalizeText("Em quanto tempo devo pagar a dívida \(selected.name)?"),
                        store: store
                    )
                    return RetrievalExecutionPayload(
                        intentKind: .debtPayoffPlan,
                        expectedLength: .analytical,
                        isSuccess: true,
                        primaryFactSummary: "Plano para a dívida \(selected.name)",
                        transactionFacts: [],
                        accountFacts: [],
                        metricFacts: [:],
                        rawResultMarkdown: analysis,
                        ragHits: ragHits,
                        suggestedFollowUps: [
                            "Qual a melhor ordem para quitar todas as minhas dívidas?",
                            "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                            "Obrigado, pode encerrar"
                        ],
                        retryCount: retryCount,
                        criticNotes: []
                    )
                }
            case .selectFollowUpActionOnPace:
                recordStep("🔄 Continuidade Multi-Turn: Detalhando transações e metas de corte para o mês em análise")
                let targetMonth = memory.lastTargetMonth ?? store.selectedMonth
                let res = executeDetailedMonthPaceBreakdownFollowUp(targetMonth: targetMonth, store: store, memory: &memory)
                return RetrievalExecutionPayload(
                    intentKind: .spendingPaceAndProjection,
                    expectedLength: .analytical,
                    isSuccess: true,
                    primaryFactSummary: "Detalhamento de transações e corte de gastos",
                    transactionFacts: [],
                    accountFacts: [],
                    metricFacts: [:],
                    rawResultMarkdown: res.markdown,
                    ragHits: ragHits,
                    suggestedFollowUps: res.followUps,
                    retryCount: retryCount,
                    criticNotes: []
                )
            default:
                break
            }
        }

        // Resolução para perguntas anafóricas de follow-up
        if case .followUp = briefing.contextMode {
            if isAnaphoricContractPayoffFollowUp(briefing.normalizedPrompt) {
                let pool = memory.lastMentionedContractIds.compactMap { id in store.contracts.first(where: { $0.id == id }) }
                let candidates = pool.isEmpty ? (store.activeContracts(for: .loan) + store.activeContracts(for: .financing)) : pool
                if let contract = matchCandidateContractFromReply(normPrompt: briefing.normalizedPrompt, candidates: candidates) {
                    recordStep("🔄 Continuidade Multi-Turn: Contrato '\(contract.name)' selecionado para detalhamento de quitação")
                    memory.lastMentionedContractId = contract.id

                    let outstanding = store.currentOutstandingBalance(for: contract)
                    let payoff = store.projectedPayoffAmount(for: contract)
                    let remainingCount = store.remainingInstallmentsCount(for: contract)
                    let nominalRem = store.remainingNominalAmount(for: contract)
                    let interestDiscount = max(0.0, nominalRem - payoff)

                    let numStr = contract.contractNumber.map { " (Contrato nº \($0))" } ?? ""
                    let md = """
                    ### 🔍 Detalhes para Quitação: **\(contract.name)**\(numStr)
                    - **Saldo Devedor Nominal Restante:** **\(BRLFormatters.currency(nominalRem))** (\(remainingCount) parcelas restantes de \(BRLFormatters.currency(contract.installmentAmount)))
                    - **Valor Projetado para Quitação Hoje (Valor Presente):** **\(BRLFormatters.currency(payoff))**
                    - **Economia Estimada de Juros na Quitação:** **\(BRLFormatters.currency(interestDiscount))**
                    - **Saldo Devedor Contábil Atual:** **\(BRLFormatters.currency(outstanding))**
                    - **Taxa de Juros:** `\(String(format: "%.2f%%", contract.monthlyInterestRate))` ao mês

                    ---
                    💬 Deseja simular uma amortização avulsa (reduzir prazo ou parcela), analisar outro contrato ou encerrar?
                    """
                    return RetrievalExecutionPayload(
                        intentKind: .loanOrFinancingSimulation,
                        expectedLength: .analytical,
                        isSuccess: true,
                        primaryFactSummary: "Detalhes de quitação do contrato \(contract.name)",
                        transactionFacts: [],
                        accountFacts: [],
                        metricFacts: [:],
                        rawResultMarkdown: md,
                        ragHits: ragHits,
                        suggestedFollowUps: [
                            "E se eu amortizar R$ 1.000 extras neste contrato?",
                            "Quanto falta para quitar o segundo contrato?",
                            "Obrigado, pode encerrar"
                        ],
                        retryCount: retryCount,
                        criticNotes: []
                    )
                }
            }

            if isAnaphoricCategoryFollowUp(briefing.normalizedPrompt),
               let catId = memory.lastMentionedCategoryId ?? memory.lastCategoryId,
               let cat = store.category(for: catId) {
                let targetMonth = briefing.targetMonth
                let monthLabel = BRLFormatters.monthYear(targetMonth)
                recordStep("🔄 Continuidade Multi-Turn: Detalhando categoria '\(cat.name)' em \(monthLabel)")

                let monthTxs = store.transactionsForMonth(targetMonth).filter { $0.categoryId == cat.id && !$0.ignoreInConsolidated }.sorted { $0.date > $1.date }
                let catTotal = monthTxs.reduce(0.0) { $0 + $1.amount }
                let env = store.provisionEnvelope(forCategory: cat.id, in: targetMonth)

                let txLines = monthTxs.isEmpty
                    ? "• Nenhum lançamento registrado em **\(cat.name)** em \(monthLabel)."
                    : monthTxs.prefix(10).map { tx in
                        "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **\(BRLFormatters.currency(tx.amount))** (\(tx.isPaid ? "Pago" : "Pendente"))"
                    }.joined(separator: "\n")

                let envBlock = env.map { e in
                    "- **Envelope/Teto no Mês:** \(BRLFormatters.currency(e.estimatedAmount)) | **Gasto:** \(BRLFormatters.currency(e.realizedExpense)) | **Restante:** **\(BRLFormatters.currency(e.remainingProvision))** (*\(e.status.rawValue)*)"
                } ?? "- **Envelope/Teto:** Sem teto configurado para esta categoria em \(monthLabel)."

                let md = """
                ## 📂 Análise da Categoria: **\(cat.name)** (\(monthLabel))
                - **Total Movimentado no Mês:** **\(BRLFormatters.currency(catTotal))** (\(monthTxs.count) lançamentos)
                \(envBlock)

                ### Lançamentos em \(monthLabel)
                \(txLines)

                ---
                💬 Deseja definir um teto para **\(cat.name)**, verificar outra categoria ou encerrar?
                """

                return RetrievalExecutionPayload(
                    intentKind: .categoryExpenseQuery,
                    expectedLength: .moderate,
                    isSuccess: true,
                    primaryFactSummary: "Detalhamento da categoria \(cat.name) em \(monthLabel)",
                    transactionFacts: [],
                    accountFacts: [],
                    metricFacts: [:],
                    rawResultMarkdown: md,
                    ragHits: ragHits,
                    suggestedFollowUps: [
                        "Reserve R$ 500 para \(cat.name.lowercased()) este mês",
                        "Qual categoria eu mais gasto no ano todo?",
                        "Obrigado, pode encerrar"
                    ],
                    retryCount: retryCount,
                    criticNotes: []
                )
            }
        }

        switch briefing.intentKind {
        case .latestTransaction:
            return retrieveLatestTransaction(briefing: briefing, store: store)

        case .recentTransactionsList:
            return retrieveRecentTransactions(briefing: briefing, store: store, limit: 5)

        case .currentBalanceAndLiquidity:
            return retrieveBalanceAndLiquidity(store: store)

        case .pendingBillsQuery:
            return retrievePendingBills(store: store, targetMonth: briefing.targetMonth)

        case .topExpenseCategories:
            return retrieveTopExpenseCategories(briefing: briefing, store: store, memory: &memory)

        case .upcomingContractInstallments:
            return retrieveUpcomingContractInstallments(briefing: briefing, store: store, memory: &memory)

        case .spendingPaceAndProjection:
            let result = executeSpendingPaceAndEndOfMonthTool(
                prompt: briefing.originalPrompt,
                normPrompt: briefing.normalizedPrompt,
                targetMonth: briefing.targetMonth,
                store: store,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .spendingPaceAndProjection,
                expectedLength: .analytical,
                isSuccess: true,
                primaryFactSummary: "Projeção de ritmo de gastos e fechamento do mês calculada",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: result.markdown,
                ragHits: ragHits,
                suggestedFollowUps: result.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .loanOrFinancingSimulation:
            let response = LocalLLMService.analyzeLoansAndFinancingsAgentTool(
                prompt: briefing.originalPrompt,
                normalizedPrompt: briefing.normalizedPrompt,
                store: store,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .loanOrFinancingSimulation,
                expectedLength: .analytical,
                isSuccess: true,
                primaryFactSummary: "Análise de empréstimos e financiamentos",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: response.markdown,
                ragHits: ragHits,
                suggestedFollowUps: response.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .debtPayoffPlan:
            let response = LocalLLMService.analyzeDebtPayoffAgentTool(
                prompt: briefing.originalPrompt,
                normalizedPrompt: briefing.normalizedPrompt,
                store: store,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .debtPayoffPlan,
                expectedLength: .analytical,
                isSuccess: true,
                primaryFactSummary: "Plano de ação para quitação de dívidas",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: response.markdown,
                ragHits: ragHits,
                suggestedFollowUps: response.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .envelopeBudgetQuery, .quotaBudgetQuery:
            if let provOutput = LocalLLMService.handleProvisionOrQuotaAgentTool(
                prompt: briefing.originalPrompt,
                normalizedPrompt: briefing.normalizedPrompt,
                store: store,
                memory: &memory,
                recordStep: recordStep
            ) {
                return RetrievalExecutionPayload(
                    intentKind: briefing.intentKind,
                    expectedLength: .moderate,
                    isSuccess: true,
                    primaryFactSummary: "Comando ou consulta de envelope/cota processado",
                    transactionFacts: [],
                    accountFacts: [],
                    metricFacts: [:],
                    rawResultMarkdown: provOutput.markdown,
                    ragHits: ragHits,
                    suggestedFollowUps: provOutput.followUps,
                    retryCount: retryCount,
                    criticNotes: []
                )
            } else {
                let response = executeTransactionsAndCategoriesQueryTool(
                    prompt: briefing.originalPrompt,
                    normPrompt: briefing.normalizedPrompt,
                    store: store,
                    ragHits: ragHits,
                    memory: &memory
                )
                return RetrievalExecutionPayload(
                    intentKind: briefing.intentKind,
                    expectedLength: .moderate,
                    isSuccess: true,
                    primaryFactSummary: "Consulta de despesas e categorias",
                    transactionFacts: [],
                    accountFacts: [],
                    metricFacts: [:],
                    rawResultMarkdown: response.markdown,
                    ragHits: ragHits,
                    suggestedFollowUps: response.followUps,
                    retryCount: retryCount,
                    criticNotes: []
                )
            }

        case .periodOverdraftForecast:
            let response = LocalLLMService.analyzePeriodAndOverdraftAgentTool(
                prompt: briefing.originalPrompt,
                store: store,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .periodOverdraftForecast,
                expectedLength: .analytical,
                isSuccess: true,
                primaryFactSummary: "Análise de período e projeção de débito",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: response.markdown,
                ragHits: ragHits,
                suggestedFollowUps: response.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .whatIfSimulation:
            let response = executeWhatIfSimulationTool(
                prompt: briefing.originalPrompt,
                normPrompt: briefing.normalizedPrompt,
                store: store,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .whatIfSimulation,
                expectedLength: .moderate,
                isSuccess: true,
                primaryFactSummary: "Simulação de cenário e impacto no fluxo de caixa",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: response.markdown,
                ragHits: ragHits,
                suggestedFollowUps: response.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .categoryExpenseQuery:
            let response = executeTransactionsAndCategoriesQueryTool(
                prompt: briefing.originalPrompt,
                normPrompt: briefing.normalizedPrompt,
                store: store,
                ragHits: ragHits,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .categoryExpenseQuery,
                expectedLength: .moderate,
                isSuccess: true,
                primaryFactSummary: "Consulta detalhada de transações e categorias",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: response.markdown,
                ragHits: ragHits,
                suggestedFollowUps: response.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .generalOverview:
            let universal = executeUniversalRAGSynthesisTool(
                prompt: briefing.originalPrompt,
                normPrompt: briefing.normalizedPrompt,
                store: store,
                ragHits: ragHits,
                memory: &memory
            )
            return RetrievalExecutionPayload(
                intentKind: .generalOverview,
                expectedLength: .analytical,
                isSuccess: true,
                primaryFactSummary: "Panorama geral sintetizado da base local",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: universal.markdown,
                ragHits: ragHits,
                suggestedFollowUps: universal.followUps,
                retryCount: retryCount,
                criticNotes: []
            )

        case .nonFinancial:
            let nonFinMarkdown = """
            Sou um **Agente Financeiro Autônomo** conectado em tempo real a 100% da sua base de dados local (transações, contas, categorias, envelopes, cotas, investimentos, empréstimos, financiamentos e dívidas).
            Por foco e precisão, atuo exclusivamente em análises, cálculos e planejamento financeiro.

            **Como posso te ajudar agora?** Você pode perguntar coisas como:
            - *"Qual foi a minha última transação?"*
            - *"Se eu continuar gastando no ritmo que eu gastei neste mês, ao final do mês terei quanto?"*
            - *"Quais foram meus maiores gastos variáveis neste mês e onde posso economizar?"*
            - *"Quanto ainda tenho para pagar neste mês e em quais datas?"*
            """
            return RetrievalExecutionPayload(
                intentKind: .nonFinancial,
                expectedLength: .concise,
                isSuccess: true,
                primaryFactSummary: "Guardrail não-financeiro acionado",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: nonFinMarkdown,
                ragHits: [],
                suggestedFollowUps: [
                    "Qual foi a minha última transação?",
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Quais contas ainda faltam pagar neste mês?"
                ],
                retryCount: retryCount,
                criticNotes: []
            )

        case .conversationClosing:
            return RetrievalExecutionPayload(
                intentKind: .conversationClosing,
                expectedLength: .concise,
                isSuccess: true,
                primaryFactSummary: "Encerramento do diálogo",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: nil,
                ragHits: [],
                suggestedFollowUps: [],
                retryCount: retryCount,
                criticNotes: []
            )
        }
    }

    private static func retrieveLatestTransaction(
        briefing: QueryAnalysisBriefing,
        store: FinancialDataStore
    ) -> RetrievalExecutionPayload {
        var pool = store.transactions
        if let filter = briefing.transactionTypeFilter {
            let filtered = pool.filter { $0.type == filter }
            if !filtered.isEmpty { pool = filtered }
        }

        let paid = pool.filter { $0.isPaid }
        let selectedPool = paid.isEmpty ? pool : paid

        let sorted = selectedPool.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.createdAt > b.createdAt
        }

        guard let latest = sorted.first else {
            return RetrievalExecutionPayload(
                intentKind: .latestTransaction,
                expectedLength: .concise,
                isSuccess: false,
                primaryFactSummary: "Nenhuma transação cadastrada na base de dados.",
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: nil,
                ragHits: [],
                suggestedFollowUps: [
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Qual é o saldo disponível nas minhas contas?",
                    "Quais contas ainda faltam pagar neste mês?"
                ],
                retryCount: 0,
                criticNotes: []
            )
        }

        let catName = store.categories.first { $0.id == latest.categoryId }?.name ?? "Sem Categoria"
        let catColor = store.categories.first { $0.id == latest.categoryId }?.colorHex ?? "#6366F1"
        let accName = store.accounts.first { $0.id == latest.accountId }?.name ?? "Conta Principal"
        let formattedDateTime = formatTransactionDateTime(date: latest.date, createdAt: latest.createdAt)

        let fact = TransactionFactDetail(
            id: latest.id,
            name: latest.name,
            details: latest.details,
            amount: latest.amount,
            date: latest.date,
            formattedDateTime: formattedDateTime,
            type: latest.type,
            isPaid: latest.isPaid,
            categoryName: catName,
            categoryColorHex: catColor,
            accountName: accName
        )

        let summary = "Última transação: \(latest.name), \(BRLFormatters.currency(latest.amount)) em \(formattedDateTime) (\(catName))"

        return RetrievalExecutionPayload(
            intentKind: .latestTransaction,
            expectedLength: .concise,
            isSuccess: true,
            primaryFactSummary: summary,
            transactionFacts: [fact],
            accountFacts: [accName],
            metricFacts: [
                "amount": String(latest.amount),
                "formattedAmount": BRLFormatters.currency(latest.amount),
                "date": formattedDateTime,
                "category": catName,
                "account": accName,
                "type": latest.type == .expense ? "despesa" : "receita"
            ],
            rawResultMarkdown: nil,
            ragHits: [],
            suggestedFollowUps: [
                "Quanto gastei na categoria \(catName) este mês?",
                "Quais foram as minhas 3 últimas transações?",
                "Se eu continuar gastando no ritmo deste mês, ao final terei quanto?"
            ],
            retryCount: 0,
            criticNotes: []
        )
    }

    private static func retrieveRecentTransactions(
        briefing: QueryAnalysisBriefing,
        store: FinancialDataStore,
        limit: Int = 5
    ) -> RetrievalExecutionPayload {
        var pool = store.transactions
        if let filter = briefing.transactionTypeFilter {
            let filtered = pool.filter { $0.type == filter }
            if !filtered.isEmpty { pool = filtered }
        }
        let paid = pool.filter { $0.isPaid }
        let selectedPool = paid.isEmpty ? pool : paid

        let sorted = selectedPool.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.createdAt > b.createdAt
        }

        let facts = sorted.prefix(limit).map { tx -> TransactionFactDetail in
            let catName = store.categories.first { $0.id == tx.categoryId }?.name ?? "Geral"
            let catColor = store.categories.first { $0.id == tx.categoryId }?.colorHex ?? "#6366F1"
            let accName = store.accounts.first { $0.id == tx.accountId }?.name ?? "Conta"
            return TransactionFactDetail(
                id: tx.id,
                name: tx.name,
                details: tx.details,
                amount: tx.amount,
                date: tx.date,
                formattedDateTime: formatTransactionDateTime(date: tx.date, createdAt: tx.createdAt),
                type: tx.type,
                isPaid: tx.isPaid,
                categoryName: catName,
                categoryColorHex: catColor,
                accountName: accName
            )
        }

        return RetrievalExecutionPayload(
            intentKind: .recentTransactionsList,
            expectedLength: .moderate,
            isSuccess: !facts.isEmpty,
            primaryFactSummary: "\(facts.count) transações recentes recuperadas",
            transactionFacts: Array(facts),
            accountFacts: [],
            metricFacts: [:],
            rawResultMarkdown: nil,
            ragHits: [],
            suggestedFollowUps: [
                "Qual foi a minha última transação?",
                "Se eu continuar gastando no ritmo deste mês, ao final terei quanto?",
                "Quais contas ainda faltam pagar neste mês?"
            ],
            retryCount: 0,
            criticNotes: []
        )
    }

    private static func retrieveBalanceAndLiquidity(store: FinancialDataStore) -> RetrievalExecutionPayload {
        let checking = store.totalCheckingBalanceNow
        let totalInvested = store.totalInvestmentsBalance
        let patrimony = store.totalConsolidatedPatrimonyNow

        return RetrievalExecutionPayload(
            intentKind: .currentBalanceAndLiquidity,
            expectedLength: .concise,
            isSuccess: true,
            primaryFactSummary: "Saldo em contas: \(BRLFormatters.currency(checking)) | Patrimônio: \(BRLFormatters.currency(patrimony))",
            transactionFacts: [],
            accountFacts: store.accounts.map { "\($0.name): \(BRLFormatters.currency($0.initialBalance))" },
            metricFacts: [
                "checking": String(checking),
                "invested": String(totalInvested),
                "patrimony": String(patrimony)
            ],
            rawResultMarkdown: nil,
            ragHits: [],
            suggestedFollowUps: [
                "Se eu continuar no ritmo deste mês, quanto terei no final?",
                "Qual foi a minha última transação?",
                "Quais despesas tenho agendadas para este mês?"
            ],
            retryCount: 0,
            criticNotes: []
        )
    }

    private static func retrievePendingBills(store: FinancialDataStore, targetMonth: Date) -> RetrievalExecutionPayload {
        let cal = Calendar.current
        let targetComps = cal.dateComponents([.year, .month], from: targetMonth)
        let unpaid = store.transactions.filter { tx in
            guard !tx.isPaid && tx.type == .expense else { return false }
            let c = cal.dateComponents([.year, .month], from: tx.date)
            return c.year == targetComps.year && c.month == targetComps.month
        }.sorted { $0.date < $1.date }

        let totalPending = unpaid.reduce(0.0) { $0 + $1.amount }
        let monthName = BRLFormatters.monthYear(targetMonth)

        var lines: [String] = []
        if unpaid.isEmpty {
            lines.append("🎉 Nenhuma conta ou despesa pendente em **\(monthName)**. Todas as contas deste mês já estão marcadas como pagas!")
        } else {
            lines.append("### Contas e Despesas Pendentes em \(monthName):")
            lines.append("- **Total a pagar:** **\(BRLFormatters.currency(totalPending))** em **\(unpaid.count) conta(s)**\n")
            for tx in unpaid {
                let catName = store.categories.first { $0.id == tx.categoryId }?.name ?? "Geral"
                let accName = store.accounts.first { $0.id == tx.accountId }?.name ?? "Conta"
                lines.append("• **\(BRLFormatters.shortDate(tx.date))** — **\(tx.name)**: **\(BRLFormatters.currency(tx.amount))** *(\(catName) • \(accName))*")
            }
        }

        return RetrievalExecutionPayload(
            intentKind: .pendingBillsQuery,
            expectedLength: .moderate,
            isSuccess: true,
            primaryFactSummary: "Total pendente em \(monthName): \(BRLFormatters.currency(totalPending))",
            transactionFacts: unpaid.map { tx in
                let catName = store.categories.first { $0.id == tx.categoryId }?.name ?? "Geral"
                let catColor = store.categories.first { $0.id == tx.categoryId }?.colorHex ?? "#6366F1"
                let accName = store.accounts.first { $0.id == tx.accountId }?.name ?? "Conta"
                return TransactionFactDetail(
                    id: tx.id,
                    name: tx.name,
                    details: tx.details,
                    amount: tx.amount,
                    date: tx.date,
                    formattedDateTime: formatTransactionDateTime(date: tx.date, createdAt: tx.createdAt),
                    type: tx.type,
                    isPaid: tx.isPaid,
                    categoryName: catName,
                    categoryColorHex: catColor,
                    accountName: accName
                )
            },
            accountFacts: [],
            metricFacts: ["totalPending": String(totalPending)],
            rawResultMarkdown: lines.joined(separator: "\n"),
            ragHits: [],
            suggestedFollowUps: [
                "Se eu pagar essas contas e continuar no ritmo deste mês, terei quanto?",
                "Qual o panorama das minhas dívidas em aberto?",
                "Qual é o saldo disponível nas minhas contas?"
            ],
            retryCount: 0,
            criticNotes: []
        )
    }

    private static func retrieveTopExpenseCategories(
        briefing: QueryAnalysisBriefing,
        store: FinancialDataStore,
        memory: inout AgentSessionMemory
    ) -> RetrievalExecutionPayload {
        let cal = Calendar.current
        var targetYear = cal.component(.year, from: briefing.targetMonth)
        for y in [2024, 2025, 2026, 2027, 2028] {
            if briefing.normalizedPrompt.contains(String(y)) {
                targetYear = y
                break
            }
        }

        let isSpecificMonth = briefing.normalizedPrompt.contains("mes passado") ||
                              briefing.normalizedPrompt.contains("neste mes") ||
                              briefing.normalizedPrompt.contains("este mes") ||
                              briefing.normalizedPrompt.contains("mes que vem") ||
                              briefing.normalizedPrompt.contains("proximo mes") ||
                              ["janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"].contains(where: { briefing.normalizedPrompt.contains($0) })

        let targetTxs: [FinancialTransaction]
        let periodLabel: String

        if isSpecificMonth {
            let m = briefing.targetMonth
            targetTxs = store.transactionsForMonth(m).filter { $0.type == .expense && !$0.ignoreInConsolidated }
            periodLabel = BRLFormatters.monthYear(m)
        } else {
            let yearFiltered = store.transactions.filter { tx in
                guard tx.type == .expense && !tx.ignoreInConsolidated else { return false }
                return cal.component(.year, from: tx.date) == targetYear
            }
            if !yearFiltered.isEmpty {
                targetTxs = yearFiltered
                periodLabel = String(targetYear)
            } else {
                targetTxs = store.transactions.filter { $0.type == .expense && !$0.ignoreInConsolidated }
                periodLabel = "todo o histórico"
            }
        }

        let totalExpense = targetTxs.reduce(0.0) { $0 + $1.amount }

        var totalsByCategory: [UUID: Double] = [:]
        for tx in targetTxs {
            totalsByCategory[tx.categoryId, default: 0.0] += tx.amount
        }

        let sortedCategories = totalsByCategory
            .compactMap { (catId, amount) -> (category: CategoryItem, total: Double)? in
                guard let cat = store.category(for: catId) else { return nil }
                return (cat, amount)
            }
            .sorted { $0.total > $1.total }

        guard let top = sortedCategories.first else {
            let emptyMsg = "Você ainda não possui despesas registradas em \(periodLabel) para calcularmos a categoria campeã de gastos."
            return RetrievalExecutionPayload(
                intentKind: .topExpenseCategories,
                expectedLength: .concise,
                isSuccess: true,
                primaryFactSummary: emptyMsg,
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: emptyMsg,
                ragHits: [],
                suggestedFollowUps: [
                    "Qual o saldo disponível nas minhas contas?",
                    "Quais são as minhas despesas pendentes neste mês?",
                    "Obrigado, pode encerrar"
                ],
                retryCount: 0,
                criticNotes: []
            )
        }

        // Armazena contexto conversacional para perguntas anafóricas posteriores ("dessa categoria", "nela")
        memory.lastMentionedCategoryId = top.category.id
        memory.lastMentionedCategoryName = top.category.name
        memory.lastCategoryId = top.category.id
        memory.lastMentionedYear = targetYear
        memory.lastIntentKind = .topExpenseCategories
        memory.lastTargetMonth = briefing.targetMonth

        let topPct = totalExpense > 0 ? (top.total / totalExpense) * 100.0 : 0.0
        let runnerUp = sortedCategories.count > 1 ? sortedCategories[1] : nil
        let runnerUpPct = runnerUp != nil && totalExpense > 0 ? (runnerUp!.total / totalExpense) * 100.0 : 0.0

        var response = "A categoria em que você mais gastou em \(periodLabel) foi **\(top.category.name)** (**\(BRLFormatters.currency(top.total))**"
        if totalExpense > 0 {
            response += ", representando `\(String(format: "%.1f%%", topPct))` do total de despesas)."
        } else {
            response += ")."
        }

        if let second = runnerUp {
            response += "\nEm segundo lugar ficou **\(second.category.name)** com **\(BRLFormatters.currency(second.total))** (`\(String(format: "%.1f%%", runnerUpPct))`)."
        }

        response += "\n\n💬 Gostaria de saber qual a categoria que você mais gastou de um ano específico, em um determinado mês ou no histórico geral?"

        let followUps = [
            "Qual categoria mais gastei no mês passado?",
            "Qual categoria mais gastei no histórico geral?",
            "Detalhe os gastos da categoria \(top.category.name)",
            "Obrigado, pode encerrar"
        ]

        return RetrievalExecutionPayload(
            intentKind: .topExpenseCategories,
            expectedLength: .concise,
            isSuccess: true,
            primaryFactSummary: "Categoria mais gasta em \(periodLabel): \(top.category.name) (\(BRLFormatters.currency(top.total)))",
            transactionFacts: [],
            accountFacts: [],
            metricFacts: [
                "topCategory": top.category.name,
                "topAmount": String(top.total),
                "topPct": String(format: "%.1f%%", topPct),
                "period": periodLabel
            ],
            rawResultMarkdown: response,
            ragHits: [],
            suggestedFollowUps: followUps,
            retryCount: 0,
            criticNotes: []
        )
    }

    private static func retrieveUpcomingContractInstallments(
        briefing: QueryAnalysisBriefing,
        store: FinancialDataStore,
        memory: inout AgentSessionMemory
    ) -> RetrievalExecutionPayload {
        let cal = Calendar.current
        let targetMonth = briefing.targetMonth
        let monthLabel = BRLFormatters.monthYear(targetMonth)

        // Assegura que lançamentos recorrentes/parcelados estejam projetados até o fim do mês alvo
        store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: targetMonth))

        let isOnlyLoan = briefing.normalizedPrompt.contains("emprestimo") && !briefing.normalizedPrompt.contains("financiamento")
        let isOnlyFinancing = briefing.normalizedPrompt.contains("financiamento") && !briefing.normalizedPrompt.contains("emprestimo")

        let candidateContracts: [CreditContract]
        if isOnlyLoan {
            candidateContracts = store.activeContracts(for: .loan)
        } else if isOnlyFinancing {
            candidateContracts = store.activeContracts(for: .financing)
        } else {
            candidateContracts = store.activeContracts(for: .loan) + store.activeContracts(for: .financing)
        }

        guard !candidateContracts.isEmpty else {
            let msg = "Não encontrei nenhum contrato ativo de empréstimo ou financiamento cadastrado na base local para \(monthLabel)."
            return RetrievalExecutionPayload(
                intentKind: .upcomingContractInstallments,
                expectedLength: .concise,
                isSuccess: true,
                primaryFactSummary: msg,
                transactionFacts: [],
                accountFacts: [],
                metricFacts: [:],
                rawResultMarkdown: msg,
                ragHits: [],
                suggestedFollowUps: [
                    "Qual o saldo disponível nas minhas contas?",
                    "Quais são as minhas despesas pendentes neste mês?",
                    "Obrigado, pode encerrar"
                ],
                retryCount: 0,
                criticNotes: []
            )
        }

        // Armazena contratos para referência conversacional multi-turn (ex: "quanto falta para quitar o primeiro?")
        memory.lastMentionedContractIds = candidateContracts.map(\.id)
        memory.candidateContractIds = candidateContracts.map(\.id)
        memory.lastIntentKind = .upcomingContractInstallments
        memory.lastTargetMonth = targetMonth

        struct ContractInstallmentDetail {
            let contract: CreditContract
            let displayName: String
            let amount: Double
            let dueDate: Date
            let formattedDueDate: String
        }

        let targetMonthTxs = store.transactionsForMonth(targetMonth)
        var installmentDetails: [ContractInstallmentDetail] = []
        var totalInstallmentsAmount: Double = 0.0

        for contract in candidateContracts {
            // Tenta obter transação já vinculada ao contrato no mês alvo
            let linkedTx = targetMonthTxs.first { $0.linkedContractId == contract.id && $0.type == .expense }
            let amount = linkedTx?.amount ?? contract.installmentAmount

            let dueDate: Date = {
                if let tx = linkedTx { return tx.date }
                var comps = cal.dateComponents([.year, .month], from: targetMonth)
                let maxDay = cal.range(of: .day, in: .month, for: targetMonth)?.count ?? 30
                comps.day = min(max(contract.billingDay, 1), maxDay)
                comps.hour = 12
                return cal.date(from: comps) ?? targetMonth
            }()

            let numStr = contract.contractNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayName: String = {
                if !numStr.isEmpty && !contract.name.contains(numStr) {
                    return "\(contract.name) \(numStr)"
                }
                return contract.name
            }()

            installmentDetails.append(
                ContractInstallmentDetail(
                    contract: contract,
                    displayName: displayName,
                    amount: amount,
                    dueDate: dueDate,
                    formattedDueDate: BRLFormatters.shortDate(dueDate)
                )
            )
            totalInstallmentsAmount += amount
        }

        installmentDetails.sort { $0.dueDate < $1.dueDate }

        var lines: [String] = []
        lines.append("### 📋 Parcelas de Financiamentos e Empréstimos para \(monthLabel):\n")
        for item in installmentDetails {
            lines.append("• **\(item.displayName):** **\(BRLFormatters.currency(item.amount))** em **\(item.formattedDueDate)**")
        }
        lines.append("\n- **Total das Parcelas:** **\(BRLFormatters.currency(totalInstallmentsAmount))**")
        lines.append("\n---")
        lines.append("💬 Deseja simular a amortização de algum desses contratos ou saber quanto falta para quitá-los?")

        let responseMarkdown = lines.joined(separator: "\n")
        let followUps = [
            "Quanto falta para quitar o primeiro?",
            "Qual o saldo devedor de cada contrato?",
            "E se eu amortizar R$ 1.000 extras no próximo mês?",
            "Obrigado, pode encerrar"
        ]

        return RetrievalExecutionPayload(
            intentKind: .upcomingContractInstallments,
            expectedLength: .moderate,
            isSuccess: true,
            primaryFactSummary: "Total de parcelas em \(monthLabel): \(BRLFormatters.currency(totalInstallmentsAmount)) (\(installmentDetails.count) contratos)",
            transactionFacts: [],
            accountFacts: [],
            metricFacts: [
                "total": String(totalInstallmentsAmount),
                "count": String(installmentDetails.count),
                "month": monthLabel
            ],
            rawResultMarkdown: responseMarkdown,
            ragHits: [],
            suggestedFollowUps: followUps,
            retryCount: 0,
            criticNotes: []
        )
    }

    // MARK: - Agente 3: Juiz e Crítico de Conformidade Multi-Turn (Anti-Context-Bleeding & Output Validator)

    private static func judgeRetrievalAgainstQuestionAndContext(
        briefing: QueryAnalysisBriefing,
        payload: RetrievalExecutionPayload,
        previousUserPrompt: String?,
        previousAssistantResponse: String?,
        store: FinancialDataStore
    ) -> CriticValidationResult {
        // Regra 1: Isolamento de Contexto & Prevenção de Vazamento Multi-Turn
        if case .newTopic = briefing.contextMode {
            // Vazamento de Categoria Campeã em novos tópicos (ex: usuário mudou de assunto para contratos/parcelas)
            if briefing.intentKind != .topExpenseCategories {
                if let raw = payload.rawResultMarkdown,
                   raw.contains("A categoria em que você mais gastou") ||
                   raw.contains("Gostaria de saber qual a categoria que você mais gastou") {
                    return CriticValidationResult(
                        isValid: false,
                        feedbackForPlanner: "Vazamento crítico de contexto: a resposta reutilizou o ranking de categorias da pergunta anterior em vez de responder à pergunta atual sobre `\(briefing.intentKind.rawValue)`. Execute retrieveUpcomingContractInstallments.",
                        approvedPayload: payload
                    )
                }
            }

            // Vazamento de Clarificação de Contratos quando o usuário pediu parcelas do mês
            if briefing.intentKind == .upcomingContractInstallments {
                if let raw = payload.rawResultMarkdown,
                   raw.contains("Qual contrato você deseja analisar?") ||
                   raw.contains("Qual financiamento você deseja analisar?") ||
                   raw.contains("Qual empréstimo você deseja analisar?") {
                    return CriticValidationResult(
                        isValid: false,
                        feedbackForPlanner: "Vazamento de fluxo de amortização: O usuário perguntou sobre as parcelas que vencem no próximo mês ('\(briefing.originalPrompt)'), mas o payload perguntou qual contrato analisar. Execute retrieveUpcomingContractInstallments.",
                        approvedPayload: payload
                    )
                }
            }

            // Vazamento de Dívidas
            if briefing.intentKind != .debtPayoffPlan {
                if let raw = payload.rawResultMarkdown,
                   raw.contains("Não identifiquei exatamente qual dívida você deseja priorizar") {
                    return CriticValidationResult(
                        isValid: false,
                        feedbackForPlanner: "Vazamento de contexto de dívidas: a pergunta atual não é sobre quitação de dívidas. Execute o manipulador de `\(briefing.intentKind.rawValue)`.",
                        approvedPayload: payload
                    )
                }
            }
        }

        // Regra 2: Fidelidade à Intenção da Pergunta Atual
        if briefing.intentKind == .latestTransaction {
            if payload.transactionFacts.isEmpty && !store.transactions.isEmpty {
                return CriticValidationResult(
                    isValid: false,
                    feedbackForPlanner: "Existem \(store.transactions.count) transações na base local, mas nenhuma foi retornada no payload. Rebusque em store.transactions pela maior data.",
                    approvedPayload: payload
                )
            }
            if let raw = payload.rawResultMarkdown,
               raw.contains("## Panorama Completo da sua Base Financeira") ||
               raw.contains("### Resumo de Dívidas e Compromissos") {
                return CriticValidationResult(
                    isValid: false,
                    feedbackForPlanner: "O payload continha um panorama genérico do banco em vez da transação individual solicitada. Rebusque diretamente em store.transactions.",
                    approvedPayload: payload
                )
            }
            return CriticValidationResult(isValid: true, feedbackForPlanner: nil, approvedPayload: payload)
        }

        if briefing.intentKind == .upcomingContractInstallments {
            let hasContracts = !store.activeContracts(for: .loan).isEmpty || !store.activeContracts(for: .financing).isEmpty
            if hasContracts {
                if let raw = payload.rawResultMarkdown {
                    let hasInstallments = raw.contains("Parcelas de Financiamentos") || raw.contains("Total das Parcelas") || raw.contains("• **")
                    if !hasInstallments {
                        return CriticValidationResult(
                            isValid: false,
                            feedbackForPlanner: "O payload para próximas parcelas de contratos não continha os valores e datas de vencimento. Execute retrieveUpcomingContractInstallments.",
                            approvedPayload: payload
                        )
                    }
                }
            }
        }

        if briefing.intentKind == .spendingPaceAndProjection {
            if let raw = payload.rawResultMarkdown,
               !raw.contains("Cenário") && !raw.contains("Ritmo") {
                return CriticValidationResult(
                    isValid: false,
                    feedbackForPlanner: "A análise de ritmo precisa conter os cenários de fechamento e burn rate.",
                    approvedPayload: payload
                )
            }
        }

        if briefing.intentKind == .topExpenseCategories {
            if let raw = payload.rawResultMarkdown,
               raw.contains("## 🔎 Análise Inteligente na Base Local (RAG)") ||
               raw.contains("## Panorama Completo da sua Base Financeira") {
                return CriticValidationResult(
                    isValid: false,
                    feedbackForPlanner: "O payload para categoria mais gasta continha um dump bruto de RAG em vez da resposta concisa com a categoria campeã.",
                    approvedPayload: payload
                )
            }
        }

        // Regra 3: Respostas de extensão concisa (.concise) não devem conter dump panorâmico
        if briefing.expectedLength == .concise {
            if let raw = payload.rawResultMarkdown,
               raw.contains("## Panorama Completo da sua Base Financeira") {
                return CriticValidationResult(
                    isValid: false,
                    feedbackForPlanner: "A pergunta pediu resposta concisa (.concise), mas o resultado continha dados densos desnecessários de outras áreas.",
                    approvedPayload: payload
                )
            }
        }

        // Regra 4: Rejeita dumps brutos de RAG em qualquer intenção focada
        if briefing.intentKind != .generalOverview {
            if let raw = payload.rawResultMarkdown,
               raw.contains("## 🔎 Análise Inteligente na Base Local (RAG)") {
                return CriticValidationResult(
                    isValid: false,
                    feedbackForPlanner: "O payload continha debug/dump de documentos do RAG. Sintetize apenas a resposta final diretamente.",
                    approvedPayload: payload
                )
            }
        }

        return CriticValidationResult(isValid: true, feedbackForPlanner: nil, approvedPayload: payload)
    }

    private static func validateRetrievalAgainstBriefing(
        briefing: QueryAnalysisBriefing,
        payload: RetrievalExecutionPayload,
        store: FinancialDataStore
    ) -> CriticValidationResult {
        judgeRetrievalAgainstQuestionAndContext(
            briefing: briefing,
            payload: payload,
            previousUserPrompt: nil,
            previousAssistantResponse: nil,
            store: store
        )
    }

    // MARK: - Agente 4: Sintetizador Final & Formatador de Persona

    private static func synthesizeFinalResponse(
        briefing: QueryAnalysisBriefing,
        payload: RetrievalExecutionPayload,
        store: FinancialDataStore,
        steps: [String],
        memory: AgentSessionMemory
    ) -> AgentExecutionOutput {
        switch briefing.intentKind {
        case .latestTransaction:
            guard let tx = payload.transactionFacts.first else {
                return AgentExecutionOutput(
                    responseMarkdown: "Você ainda não possui nenhuma transação cadastrada na sua base de dados local. Assim que você registrar uma nova despesa ou importar um extrato, poderei te informar a qualquer momento!",
                    executedSteps: steps,
                    suggestedFollowUps: [
                        "Qual o saldo disponível nas minhas contas?",
                        "Como posso importar um extrato bancário?",
                        "Quais são as categorias cadastradas?"
                    ],
                    shouldCloseChat: false,
                    updatedMemory: memory
                )
            }

            let typeDescription = tx.type == .expense ? "uma despesa" : "uma receita"
            let cleanName = tx.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanDetails = tx.details.trimmingCharacters(in: .whitespacesAndNewlines)
            let detailNote: String
            if !cleanDetails.isEmpty && !cleanDetails.contains("[IA Local") {
                detailNote = " (\(cleanDetails))"
            } else {
                detailNote = ""
            }

            let actionVerb = tx.type == .expense ? "você comprou/pagou" : "você recebeu"
            let finalResponse = "Sua última transação foi \(typeDescription) de **\(BRLFormatters.currency(tx.amount))** no dia **\(tx.formattedDateTime)**, \(actionVerb) **\"\(cleanName)\"**\(detailNote) na categoria **\(tx.categoryName)** (\(tx.accountName))."

            return AgentExecutionOutput(
                responseMarkdown: finalResponse,
                executedSteps: steps,
                suggestedFollowUps: payload.suggestedFollowUps,
                shouldCloseChat: false,
                updatedMemory: memory
            )

        case .recentTransactionsList:
            if payload.transactionFacts.isEmpty {
                return AgentExecutionOutput(
                    responseMarkdown: "Você ainda não possui transações cadastradas na sua base de dados local.",
                    executedSteps: steps,
                    suggestedFollowUps: payload.suggestedFollowUps,
                    shouldCloseChat: false,
                    updatedMemory: memory
                )
            }
            let count = payload.transactionFacts.count
            let header = "### Suas \(count) Últimas Transações Realizadas:\n"
            let lines = payload.transactionFacts.map { tx -> String in
                let sign = tx.type == .expense ? "-" : "+"
                return "• **\(tx.formattedDateTime)** — **\(tx.name)**: `\(sign)\(BRLFormatters.currency(tx.amount))` *(\(tx.categoryName) • \(tx.accountName))*"
            }
            return AgentExecutionOutput(
                responseMarkdown: header + lines.joined(separator: "\n"),
                executedSteps: steps,
                suggestedFollowUps: payload.suggestedFollowUps,
                shouldCloseChat: false,
                updatedMemory: memory
            )

        case .topExpenseCategories, .upcomingContractInstallments:
            let resolved = payload.rawResultMarkdown ?? "Consulta financeira processada com sucesso."
            return AgentExecutionOutput(
                responseMarkdown: resolved,
                executedSteps: steps,
                suggestedFollowUps: payload.suggestedFollowUps,
                shouldCloseChat: false,
                updatedMemory: memory
            )

        case .currentBalanceAndLiquidity:
            let checking = store.totalCheckingBalanceNow
            let totalInvested = store.totalInvestmentsBalance
            let patrimony = store.totalConsolidatedPatrimonyNow

            var text = "Seu saldo disponível hoje nas contas é de **\(BRLFormatters.currency(checking))**."
            if totalInvested > 0 {
                text += "\nVocê possui **\(BRLFormatters.currency(totalInvested))** aplicados em investimentos (Patrimônio Consolidado Total: **\(BRLFormatters.currency(patrimony))**)."
            } else {
                text += " *(Patrimônio Consolidado: **\(BRLFormatters.currency(patrimony))**)*"
            }
            return AgentExecutionOutput(
                responseMarkdown: text,
                executedSteps: steps,
                suggestedFollowUps: payload.suggestedFollowUps,
                shouldCloseChat: false,
                updatedMemory: memory
            )

        default:
            let resolved = payload.rawResultMarkdown ?? LocalLLMService.generateComprehensiveDatabaseOverview(store: store)
            return AgentExecutionOutput(
                responseMarkdown: resolved,
                executedSteps: steps,
                suggestedFollowUps: payload.suggestedFollowUps,
                shouldCloseChat: false,
                updatedMemory: memory
            )
        }
    }

    private static func synthesizeClosingResponse(
        store: FinancialDataStore,
        steps: [String],
        memory: AgentSessionMemory
    ) -> AgentExecutionOutput {
        let projectedMonthEnd = store.accumulatedConsolidatedBalance(throughMonth: store.selectedMonth, includeProjectedUnpaid: true)
        let closingText = """
        Perfeito! Encerrando nossa análise por aqui. ✅

        ### Resumo Rápido Antes de Fechar
        - **Saldo Disponível Hoje:** **\(BRLFormatters.currency(store.totalCheckingBalanceNow))** *(Patrimônio Consolidado: **\(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))**)*
        - **Saldo Projetado p/ Fim de \(BRLFormatters.monthYear(store.selectedMonth)):** **\(BRLFormatters.currency(projectedMonthEnd))**

        Sempre que precisar simular novos cenários, revisar seu ritmo de gastos ou planejar quitações, estou à sua disposição!
        """
        return AgentExecutionOutput(
            responseMarkdown: closingText,
            executedSteps: steps,
            suggestedFollowUps: [
                "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                "Qual foi a minha última transação?",
                "Quais são minhas despesas pendentes neste mês?"
            ],
            shouldCloseChat: true,
            updatedMemory: memory
        )
    }

    public static func formatTransactionDateTime(date: Date, createdAt: Date) -> String {
        let cal = Calendar.current
        let timeComps = cal.dateComponents([.hour, .minute], from: date)
        let createdTimeComps = cal.dateComponents([.hour, .minute], from: createdAt)
        let dateStr = BRLFormatters.shortDate(date)

        if let h = timeComps.hour, let m = timeComps.minute, (h != 0 || m != 0) {
            return "\(dateStr) às \(String(format: "%02d:%02d", h, m))"
        }
        if cal.isDate(date, inSameDayAs: createdAt),
           let ch = createdTimeComps.hour, let cm = createdTimeComps.minute, (ch != 0 || cm != 0) {
            return "\(dateStr) às \(String(format: "%02d:%02d", ch, cm))"
        }
        return dateStr
    }

    // MARK: - Intent Classifiers & Multi-Turn Resolution

    private static func isConversationClosingIntent(_ normPrompt: String) -> Bool {
        let exactClosingPhrases = [
            "encerrar", "encerrar chat", "encerrar conversa", "pode encerrar", "pode fechar",
            "fechar chat", "fechar conversa", "so isso", "era so isso", "nao tenho mais duvidas",
            "nao preciso de mais nada", "obrigado pode fechar", "tchau", "ate mais", "finalizar chat",
            "concluir conversa"
        ]
        if exactClosingPhrases.contains(where: { normPrompt == $0 || normPrompt.hasPrefix($0) || normPrompt.hasSuffix($0) }) {
            return true
        }
        let gratitudeWords = ["obrigado", "obrigada", "valeu", "perfeito", "agradecido", "otimo", "excelente"]
        let stopWords = ["so isso", "encerrar", "fechar", "tchau", "mais nada", "por hoje", "satisfeito"]
        if gratitudeWords.contains(where: { normPrompt.contains($0) }) &&
           stopWords.contains(where: { normPrompt.contains($0) }) {
            return true
        }
        return false
    }

    private static func isStrictlyNonFinancial(_ normPrompt: String) -> Bool {
        let nonFinancialKeywords = ["receita de bolo", "receita culinaria", "futebol", "piada", "poema", "clima", "previsao do tempo", "filme", " novela "]
        let financialSignalKeywords = [
            "analis", "dado", "saldo", "despesa", "receita", "gasto", "gastar", "divida", "emprestimo",
            "financiamento", "investimento", "projecao", "debito", "futuro", "mes", "ano", "conta",
            "cartao", "mercado pago", "itau", "santander", "nubank", "categoria", "quitar", "pagar",
            "amortiza", "cofrinho", "cdb", "extrato", "pix", "boleto", "resumo", "quanto", "quando",
            "01/", "2025", "2026", "2027", "r$", "dinheiro", "patrimonio", "economia", "sobra",
            "reserv", "provis", "teto", "envelope", "orcamento", "gasolina", "combustivel", "lanche", "lazer", "ritmo"
        ]
        return nonFinancialKeywords.contains(where: { normPrompt.contains($0) }) &&
               !financialSignalKeywords.contains(where: { normPrompt.contains($0) })
    }

    private static func isSpendingPaceOrEndOfMonthBalanceQuery(_ normPrompt: String) -> Bool {
        // Detecta perguntas sobre ritmo de gastos, burn rate, continuar gastando, ou quanto terá/sobrará no final do mês
        let paceTriggers = [
            "ritmo", "continuar gastando", "continuar nesse ritmo", "nesse ritmo", "neste ritmo",
            "mantiver esse gasto", "mantiver meus gastos", "media diaria", "gasto diario",
            "gastando assim", "burn rate", "velocidade de gasto"
        ]
        if paceTriggers.contains(where: { normPrompt.contains($0) }) {
            return true
        }

        let endOfMonthPhrases = [
            "final do mes", "fim do mes", "fechar o mes", "fechamento do mes",
            "terminar o mes", "ate o fim do mes", "ate o final do mes"
        ]
        let balanceQuestionWords = [
            "terei quanto", "quanto terei", "quanto vou ter", "com quanto vou ficar",
            "quanto vai sobrar", "vai sobrar quanto", "qual sera meu saldo", "qual meu saldo",
            "quanto sobra", "vou fechar com quanto"
        ]
        if endOfMonthPhrases.contains(where: { normPrompt.contains($0) }) &&
           (balanceQuestionWords.contains(where: { normPrompt.contains($0) }) || normPrompt.contains("gast") || normPrompt.contains("saldo") || normPrompt.contains("quanto")) {
            return true
        }

        if (normPrompt.contains("quanto vai sobrar") || normPrompt.contains("quanto terei")) &&
           (normPrompt.contains("este mes") || normPrompt.contains("neste mes") || normPrompt.contains("esse mes")) {
            return true
        }

        return false
    }

    private static func isContractOrAmortizationQuery(prompt: String, normPrompt: String, store: FinancialDataStore) -> Bool {
        let contractKeywords = [
            "contrato", "contratos", "financiamento", "financiamentos",
            "imobiliario", "imobilidario", "habitacao", "imovel", "veiculo",
            "emprestimo", "emprestimos", "consignado", "amortiza", "amortizacao", "saldo devedor"
        ]
        if contractKeywords.contains(where: { normPrompt.contains($0) }) {
            return true
        }
        let allContracts = store.activeContracts(for: .loan) + store.activeContracts(for: .financing)
        return allContracts.contains { c in
            let n = FinancialRAGIndex.normalizeText(c.name)
            if !n.isEmpty && normPrompt.contains(n) { return true }
            if let num = c.contractNumber, !num.isEmpty, normPrompt.contains(FinancialRAGIndex.normalizeText(num)) { return true }
            return false
        }
    }

    private static func isDebtPayoffOrNegotiationQuery(prompt: String, normPrompt: String, store: FinancialDataStore) -> Bool {
        if normPrompt.contains("divida") || normPrompt.contains("dividas") ||
           normPrompt.contains("mercado pago") ||
           (normPrompt.contains("quanto tempo") && normPrompt.contains("pagar")) ||
           (normPrompt.contains("quitar") && !normPrompt.contains("financiamento") && !normPrompt.contains("emprestimo")) {
            return true
        }
        return store.activeDebts.contains { d in
            let n = FinancialRAGIndex.normalizeText(d.name)
            return !n.isEmpty && normPrompt.contains(n)
        }
    }

    private static func isPeriodOrOverdraftQuery(prompt: String, normPrompt: String) -> Bool {
        if LocalLLMService.extractDateRange(from: prompt) != nil {
            return true
        }
        if normPrompt.contains("entrarei em debito") || normPrompt.contains("entrar em debito") ||
           normPrompt.contains("ficar no vermelho") || normPrompt.contains("ficarei negativo") ||
           (normPrompt.contains("projecao") && (normPrompt.contains("debito") || normPrompt.contains("futuro") || normPrompt.contains("fututo") || normPrompt.contains("meses"))) {
            return true
        }
        return false
    }

    private static func isWhatIfSimulationQuery(_ normPrompt: String) -> Bool {
        let triggers = [
            "e se eu", "se eu comprar", "posso comprar", "consigo comprar",
            "se eu cortar", "se eu reduzir", "se eu economizar",
            "quanto posso gastar por dia", "meta diaria", "se eu gastar r$",
            "vale a pena parcelar", "a vista ou parcelado"
        ]
        return triggers.contains(where: { normPrompt.contains($0) })
    }

    private static func isAccountsOrInvestmentsSpecificQuery(_ normPrompt: String, store: FinancialDataStore) -> Bool {
        let invKeywords = [
            "investimento", "investimentos", "cofrinho", "cofrinhos", "caixinha",
            "cdb", "carteira de investimento", "quanto tenho investido", "onde esta meu dinheiro",
            "saldo por conta", "minhas contas bancarias", "saldo das contas"
        ]
        if invKeywords.contains(where: { normPrompt.contains($0) }) {
            return true
        }
        return false
    }

    private static func isTransactionsOrCategorySpecificQuery(_ normPrompt: String, store: FinancialDataStore) -> Bool {
        let txKeywords = [
            "quanto gastei", "quanto eu gastei", "gastos com", "despesas com",
            "maiores gastos", "maiores despesas", "transacoes", "lancamentos",
            "contas pendentes", "falta pagar", "faltam pagar", "a vencer", "nao pagas",
            "quanto recebi", "minhas receitas", "meu salario", "compras parceladas",
            "parcelamentos", "assinaturas", "recorrentes", "gastos fixos", "gastos variaveis",
            "extrato", "compare", "comparar", "mes passado", "mes anterior", "detalhe os gastos",
            "quais foram os gastos", "liste os gastos", "listar despesas", "listar transacoes"
        ]
        if txKeywords.contains(where: { normPrompt.contains($0) }) {
            return true
        }
        // Verifica se mencionou diretamente o nome de alguma categoria cadastrada
        for cat in store.categories {
            let normCat = FinancialRAGIndex.normalizeText(cat.name)
            if normCat.count >= 4 && normPrompt.contains(normCat) {
                return true
            }
        }
        return false
    }

    private static func isLatestTransactionQuery(_ normPrompt: String) -> Bool {
        let exactMatches = [
            "ultima transacao", "minha ultima transacao", "qual foi minha ultima transacao",
            "qual foi a minha ultima transacao", "qual e a minha ultima transacao",
            "qual a minha ultima transacao", "qual a ultima transacao",
            "qual foi a ultima transacao", "ultimo gasto", "meu ultimo gasto",
            "qual foi meu ultimo gasto", "qual foi o meu ultimo gasto",
            "qual foi a ultima compra", "minha ultima compra", "qual a ultima compra",
            "ultima compra", "ultima despesa", "qual foi a ultima despesa",
            "ultimo lancamento", "qual foi o ultimo lancamento", "qual o ultimo lancamento",
            "qual foi o ultimo pagamento", "ultimo pagamento", "ultima despesa paga",
            "ultima receita", "minha ultima receita", "ultima entrada", "ultimo salario",
            "ultimo recebimento", "qual o valor da ultima compra"
        ]
        if exactMatches.contains(where: { normPrompt == $0 || normPrompt.contains($0) }) {
            return true
        }

        let hasUltimo = normPrompt.contains("ultima") || normPrompt.contains("ultimo")
        let hasTxWord = normPrompt.contains("transacao") || normPrompt.contains("gasto") ||
                        normPrompt.contains("despesa") || normPrompt.contains("compra") ||
                        normPrompt.contains("lancamento") || normPrompt.contains("pagamento") ||
                        normPrompt.contains("entrada") || normPrompt.contains("receita")
        let hasPlural = normPrompt.contains("ultimas") || normPrompt.contains("ultimos") ||
                        normPrompt.contains("3 ultimas") || normPrompt.contains("3 ultimos") ||
                        normPrompt.contains("5 ultimas") || normPrompt.contains("5 ultimos")

        return hasUltimo && hasTxWord && !hasPlural
    }

    private static func isRecentTransactionsListQuery(_ normPrompt: String) -> Bool {
        let pluralMatches = [
            "ultimas transacoes", "ultimos gastos", "ultimas compras", "ultimos lancamentos",
            "ultimas despesas", "transacoes recentes", "gastos recentes", "compras recentes",
            "extrato recente", "ultimos pagamentos", "tres ultimas", "3 ultimas", "3 ultimos",
            "cinco ultimas", "5 ultimas", "5 ultimos", "dez ultimas", "10 ultimas"
        ]
        return pluralMatches.contains(where: { normPrompt.contains($0) })
    }

    private static func isBalanceQuery(_ normPrompt: String) -> Bool {
        let balancePhrases = [
            "qual meu saldo", "qual e o meu saldo", "saldo atual", "quanto tenho na conta",
            "quanto tenho em conta", "saldo das contas", "saldo total", "meu saldo",
            "saldo em conta", "saldo bancario", "quanto tenho de saldo"
        ]
        return balancePhrases.contains(where: { normPrompt == $0 || normPrompt.contains($0) })
    }

    private static func isPendingBillsQuery(_ normPrompt: String) -> Bool {
        let billPhrases = [
            "contas pendentes", "falta pagar", "faltam pagar", "a vencer",
            "boletos a pagar", "contas a pagar", "o que falta pagar",
            "despesas pendentes", "contas que faltam", "boletos pendentes"
        ]
        return billPhrases.contains(where: { normPrompt.contains($0) })
    }

    private static func isProvisionOrQuotaIntent(prompt: String, normPrompt: String) -> Bool {
        let configVerbs = [
            "reserve", "reservar", "provis", "provisione", "defina", "definir",
            "configure", "configurar", "estime", "estimar", "coloque um teto",
            "teto de", "orcamento de", "limite de", "quanto ainda posso gastar",
            "quanto posso gastar com", "quanto resta no teto", "meus envelopes",
            "minhas previsoes", "meus tetos", "cota", "cotas", "galao", "botijao"
        ]
        return configVerbs.contains(where: { normPrompt.contains($0) })
    }

    private static func isTopExpenseCategoriesQuery(_ normPrompt: String) -> Bool {
        let triggers = [
            "qual categoria eu mais gasto", "qual categoria mais gasto",
            "qual a categoria que eu mais gasto", "qual a categoria que mais gasto",
            "categoria que mais gasto", "categoria que eu mais gasto",
            "onde mais gasto", "onde eu mais gasto", "onde estou mais gastando",
            "em que mais gasto", "em que eu mais gasto", "com o que mais gasto",
            "quais categorias mais gasto", "categoria com maior gasto",
            "maior categoria de despesa", "categoria campea",
            "qual categoria gastei mais", "onde gastei mais",
            "categoria mais gasta", "categoria com mais despesas",
            "qual categoria eu mais gastei", "qual categoria mais gastei",
            "qual a categoria que mais gastei", "qual e a categoria que mais gasto",
            "qual e a categoria que eu mais gasto", "maiores categorias",
            "ranking de categorias", "ranking das categorias"
        ]
        if triggers.contains(where: { normPrompt.contains($0) }) {
            return true
        }
        if normPrompt.contains("categoria") && (normPrompt.contains("mais") || normPrompt.contains("maior")) && (normPrompt.contains("gasto") || normPrompt.contains("despesa") || normPrompt.contains("gastei")) {
            return true
        }
        return false
    }

    private static func isUpcomingContractInstallmentsQuery(_ normPrompt: String) -> Bool {
        let triggers = [
            "quanto vou pagar de parcelas", "quanto vou pagar de parcela",
            "parcelas de financiamento e emprestimos", "parcelas de financiamentos e emprestimos",
            "parcelas de emprestimo e financiamento", "parcelas de emprestimos e financiamentos",
            "parcelas de financiamento", "parcelas de emprestimo", "parcelas de emprestimos",
            "parcelas do financiamento", "parcelas do emprestimo",
            "parcelas proximo mes", "parcelas do proximo mes", "parcelas mes que vem",
            "parcelas a pagar proximo mes", "quais parcelas vencem",
            "proximas parcelas de financiamento", "proximas parcelas",
            "quanto de parcelas vou pagar", "quanto de parcela vou pagar",
            "quanto vou pagar em parcelas", "quanto vou pagar de parcelas no proximo mes",
            "soma das parcelas proximo mes", "valor das parcelas proximo mes"
        ]
        if triggers.contains(where: { normPrompt.contains($0) }) {
            return true
        }
        let hasParcela = normPrompt.contains("parcela") || normPrompt.contains("parcelas")
        let hasContract = normPrompt.contains("financiamento") || normPrompt.contains("emprestimo") || normPrompt.contains("contrato")
        let hasFutureOrAmount = normPrompt.contains("proximo mes") || normPrompt.contains("mes que vem") || normPrompt.contains("quanto vou pagar") || normPrompt.contains("quanto pagar") || normPrompt.contains("proximas")
        return hasParcela && hasContract && hasFutureOrAmount
    }

    private static func isAnaphoricCategoryFollowUp(_ normPrompt: String) -> Bool {
        let patterns = [
            "dessa categoria", "nessa categoria", "nela", "dela",
            "quanto gastei nela", "quanto gastei dela", "gastos nela",
            "transacoes nela", "lancamentos nela", "e nela", "e nessa"
        ]
        return patterns.contains(where: { normPrompt.contains($0) })
    }

    private static func isAnaphoricTimeShiftFollowUp(_ normPrompt: String) -> Bool {
        guard normPrompt.count <= 35 else { return false }
        if isUpcomingContractInstallmentsQuery(normPrompt) ||
           isSpendingPaceOrEndOfMonthBalanceQuery(normPrompt) ||
           isLatestTransactionQuery(normPrompt) {
            return false
        }
        let starters = ["e no mes passado", "e no mes anterior", "e no proximo mes", "e mes passado", "e no anterior", "e em ", "e no ", "e na "]
        if starters.contains(where: { normPrompt.hasPrefix($0) || normPrompt == $0 }) {
            return true
        }
        let clean = normPrompt.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
        let shortPhrases = ["no mes passado", "mes passado", "e no passado", "proximo mes", "e no proximo", "e em 2025", "e em 2026", "e no historico geral"]
        return shortPhrases.contains(where: { clean == $0 || clean.hasSuffix($0) })
    }

    private static func isAnaphoricContractPayoffFollowUp(_ normPrompt: String) -> Bool {
        let hasOrder = normPrompt.contains("primeiro") || normPrompt.contains("primeira") ||
                       normPrompt.contains("segundo") || normPrompt.contains("segunda") ||
                       normPrompt.contains("terceiro") || normPrompt.contains("terceira") ||
                       normPrompt.contains("opcao 1") || normPrompt.contains("opcao 2") ||
                       normPrompt.contains("o primeiro") || normPrompt.contains("o segundo") ||
                       normPrompt.contains("o caixa") || normPrompt.contains("o santander")
        let hasAction = normPrompt.contains("quitar") || normPrompt.contains("saldo devedor") ||
                        normPrompt.contains("quanto falta") || normPrompt.contains("quanto custa") ||
                        normPrompt.contains("amortizar") || normPrompt.contains("termina quando") ||
                        normPrompt.contains("valor presente")
        return hasOrder && hasAction
    }

    // MARK: - Helper Matching Functions Multi-Turn

    private static func matchCandidateContractFromReply(normPrompt: String, candidates: [CreditContract]) -> CreditContract? {
        guard !candidates.isEmpty else { return nil }
        if normPrompt == "1" || normPrompt.contains("primeiro") || normPrompt.contains("primeira") || normPrompt.contains("opcao 1") {
            return candidates[0]
        }
        if candidates.count >= 2 && (normPrompt == "2" || normPrompt.contains("segundo") || normPrompt.contains("segunda") || normPrompt.contains("opcao 2")) {
            return candidates[1]
        }
        if candidates.count >= 3 && (normPrompt == "3" || normPrompt.contains("terceiro") || normPrompt.contains("terceira") || normPrompt.contains("opcao 3")) {
            return candidates[2]
        }
        for c in candidates {
            let normName = FinancialRAGIndex.normalizeText(c.name)
            if normPrompt.contains(normName) { return c }
            if let num = c.contractNumber, !num.isEmpty, normPrompt.contains(FinancialRAGIndex.normalizeText(num)) {
                return c
            }
            let tokens = FinancialRAGIndex.tokenize(normName).filter { $0.count >= 4 && $0 != "financiamento" && $0 != "emprestimo" && $0 != "contrato" }
            if tokens.contains(where: { normPrompt.contains($0) }) {
                return c
            }
        }
        return nil
    }

    private static func matchCandidateDebtFromReply(normPrompt: String, candidates: [DebtItem]) -> DebtItem? {
        guard !candidates.isEmpty else { return nil }
        if normPrompt == "1" || normPrompt.contains("primeira") || normPrompt.contains("primeiro") {
            return candidates[0]
        }
        if candidates.count >= 2 && (normPrompt == "2" || normPrompt.contains("segunda") || normPrompt.contains("segundo")) {
            return candidates[1]
        }
        if normPrompt.contains("maior") {
            return candidates.max(by: { $0.originalAmount < $1.originalAmount })
        }
        if normPrompt.contains("menor") {
            return candidates.min(by: { $0.originalAmount < $1.originalAmount })
        }
        for d in candidates {
            let normName = FinancialRAGIndex.normalizeText(d.name)
            if normPrompt.contains(normName) { return d }
            let tokens = FinancialRAGIndex.tokenize(normName).filter { $0.count >= 3 && $0 != "cartao" && $0 != "credito" && $0 != "divida" }
            if tokens.contains(where: { normPrompt.contains($0) }) {
                return d
            }
        }
        return nil
    }

    // MARK: - Tool 1: Spending Pace (Burn Rate) & End-of-Month Balance Projection
    // Responde com precisão cirúrgica: "Se eu continuar gastando no ritmo que eu gastei neste mês, ao final do mês terei quanto?"

    private static func executeSpendingPaceAndEndOfMonthTool(
        prompt: String,
        normPrompt: String,
        targetMonth: Date,
        store: FinancialDataStore,
        memory: inout AgentSessionMemory
    ) -> (markdown: String, followUps: [String]) {
        memory.activeTopic = .spendingPaceAndMonthEnd
        memory.pendingQuestionKind = .selectFollowUpActionOnPace
        memory.lastTargetMonth = targetMonth

        let cal = Calendar.current
        let now = Date()
        let monthLabel = BRLFormatters.monthYear(targetMonth)

        // Materializa recorrências até o fim do mês consultado
        store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: targetMonth))

        let totalDaysInMonth = cal.range(of: .day, in: .month, for: targetMonth)?.count ?? 30
        let monthTxs = store.transactionsForMonth(targetMonth).filter { !$0.ignoreInConsolidated }

        // Determina quantos dias já decorreram no mês
        let daysElapsed: Int = {
            if store.isInMonth(now, monthReference: targetMonth) {
                return min(max(cal.component(.day, from: now), 1), totalDaysInMonth)
            }
            let paidDays = monthTxs.filter(\.isPaid).map { cal.component(.day, from: $0.date) }
            if let maxPaidDay = paidDays.max() {
                return min(max(maxPaidDay, 1), totalDaysInMonth)
            }
            return min(max(cal.component(.day, from: targetMonth), 1), totalDaysInMonth)
        }()
        let daysRemaining = max(totalDaysInMonth - daysElapsed, 0)

        // Saldos atuais
        let checkingNow = store.totalCheckingBalanceNow
        let consolidatedInvNow = store.consolidatedInvestmentsBalance
        let totalPatrimonyNow = store.totalConsolidatedPatrimonyNow

        // Receitas e Despesas do mês
        let receivedIncome = store.monthlyReceivedIncome(for: targetMonth)
        let pendingIncome = store.monthlyPendingIncome(for: targetMonth)
        let totalMonthIncome = receivedIncome + pendingIncome

        let paidExpenseTotal = store.monthlyPaidExpense(for: targetMonth)
        let pendingExpenseTotal = store.monthlyPendingExpense(for: targetMonth)
        let totalMonthRegisteredExpense = paidExpenseTotal + pendingExpenseTotal

        // Separa as despesas pagas em:
        // A) Aplicações/Transferências para Investimentos (que são formação de reserva, não gasto consumido)
        // B) Compromissos Fixos / Faturas / Contratos / Parcelas Mensais (ocorrem 1x no mês, não se repetem todo dia)
        // C) Gastos Variáveis / Consumo do Dia a Dia (Alimentação, Combustível, Supermercado, Lazer, Compras avulsas, etc. — estes definem o ritmo diário!)
        let paidExpensesList = monthTxs.filter { $0.type == .expense && $0.isPaid }

        var investmentTransferPaid = 0.0
        var fixedAndCommittedPaid = 0.0
        var variableDailyPaid = 0.0
        var variableTransactions: [FinancialTransaction] = []
        var fixedTransactions: [FinancialTransaction] = []

        let fixedCategoryFragments = [
            "moradia", "condominio", "aluguel", "educacao", "curso", "faculdade",
            "energia", "agua", "gas", "internet", "cartao de credito", "boletos",
            "emprestimo", "financiamento", "divida", "imposto", "seguro", "assinatura"
        ]

        for tx in paidExpensesList {
            let catNameNorm = FinancialRAGIndex.normalizeText(store.category(for: tx.categoryId)?.name ?? "")
            let txNameNorm = FinancialRAGIndex.normalizeText(tx.name)

            if tx.linkedInvestmentId != nil ||
               catNameNorm.contains("aplicac") ||
               txNameNorm.contains("aplicacao cofrinhos") ||
               txNameNorm.contains("aplicacao cdb") ||
               txNameNorm.contains("aporte:") {
                investmentTransferPaid += tx.amount
            } else if tx.linkedContractId != nil ||
                      tx.linkedDebtId != nil ||
                      tx.recurrenceMode != .single ||
                      fixedCategoryFragments.contains(where: { catNameNorm.contains($0) }) {
                fixedAndCommittedPaid += tx.amount
                fixedTransactions.append(tx)
            } else {
                variableDailyPaid += tx.amount
                variableTransactions.append(tx)
            }
        }

        // Também inclui nos gastos variáveis qualquer gasto realizado em categorias que possuam Envelope/Teto ativo no mês
        let envelopes = store.provisionEnvelopes(for: targetMonth)
        let envelopeCategoryIds = Set(envelopes.map { $0.category.id })
        let paidInEnvelopes = paidExpensesList
            .filter { envelopeCategoryIds.contains($0.categoryId) }
            .reduce(0.0) { $0 + $1.amount }

        let effectiveVariableSpentSoFar = max(variableDailyPaid, paidInEnvelopes)
        let operationalPaidExpense = max(paidExpenseTotal - investmentTransferPaid, 0.0)

        // 1. Cálculo do Ritmo Diário de Gastos Variáveis (Consumo do Dia a Dia)
        let dailyVariablePace = effectiveVariableSpentSoFar / Double(max(daysElapsed, 1))
        let projectedExtraVariableInRemainingDays = dailyVariablePace * Double(daysRemaining)
        let projectedTotalVariableAtMonthEnd = effectiveVariableSpentSoFar + projectedExtraVariableInRemainingDays
        memory.lastDailyPaceAmount = dailyVariablePace

        // Saldo base antes de novos gastos variáveis futuros = Patrimônio Consolidado Hoje + Receitas Pendentes - Despesas Agendadas Pendentes
        let baseBalanceAfterScheduledItems = totalPatrimonyNow + pendingIncome - pendingExpenseTotal
        let checkingBaseAfterScheduled = checkingNow + pendingIncome - pendingExpenseTotal

        // Cenário 1 (Principal - Ritmo Real de Consumo Diário):
        // Se continuar gastando `dailyVariablePace` por dia nos `daysRemaining` dias restantes + pagar as despesas agendadas pendentes:
        let balanceAtVariablePace = baseBalanceAfterScheduledItems - projectedExtraVariableInRemainingDays
        let checkingBalanceAtVariablePace = checkingBaseAfterScheduled - projectedExtraVariableInRemainingDays

        // Cenário 2 (Planejamento Oficial pelos Envelopes/Tetos Configurados):
        let remainingProvisions = store.totalRemainingProvision(for: targetMonth)
        let officialProjectedBalance = store.accumulatedConsolidatedBalance(throughMonth: targetMonth, includeProjectedUnpaid: true)

        // Cenário 3 (Extrapolação Linear Bruta de TODAS as Despesas Operacionais):
        let dailyTotalOperationalPace = operationalPaidExpense / Double(max(daysElapsed, 1))
        let projectedRemainingTotalLinear = dailyTotalOperationalPace * Double(daysRemaining)
        let balanceAtLinearTotalPace = totalPatrimonyNow + pendingIncome - projectedRemainingTotalLinear

        // 2. Análise de cada Envelope no Ritmo Atual
        var envelopePaceLines: [String] = []
        var totalProjectedEnvelopeOverrun = 0.0

        for env in envelopes {
            let catPacePerDay = env.realizedExpense / Double(max(daysElapsed, 1))
            let projectedCatEndOfMonth = catPacePerDay * Double(totalDaysInMonth)
            let diffFromCeiling = env.estimatedAmount - projectedCatEndOfMonth

            if diffFromCeiling >= 0 {
                envelopePaceLines.append(
                    "- **\(env.category.name):** Gasto até hoje (dia \(daysElapsed)): **\(BRLFormatters.currency(env.realizedExpense))** (`\(BRLFormatters.currency(catPacePerDay))/dia`) → Projeção p/ 30 dias neste ritmo: **\(BRLFormatters.currency(projectedCatEndOfMonth))** de \(BRLFormatters.currency(env.estimatedAmount)) (**🟢 Sobra de \(BRLFormatters.currency(diffFromCeiling)) no teto**)"
                )
            } else {
                let overrun = abs(diffFromCeiling)
                totalProjectedEnvelopeOverrun += overrun
                let dayWillBurst = catPacePerDay > 0.01 ? min(totalDaysInMonth, max(daysElapsed, Int(ceil(env.estimatedAmount / catPacePerDay)))) : totalDaysInMonth
                envelopePaceLines.append(
                    "- **\(env.category.name):** Gasto até hoje (dia \(daysElapsed)): **\(BRLFormatters.currency(env.realizedExpense))** (`\(BRLFormatters.currency(catPacePerDay))/dia`) → Projeção p/ \(totalDaysInMonth) dias neste ritmo: **\(BRLFormatters.currency(projectedCatEndOfMonth))** p/ um teto de \(BRLFormatters.currency(env.estimatedAmount)) (**🔴 Vai estourar o teto em +\(BRLFormatters.currency(overrun)) por volta do dia \(dayWillBurst)**)"
                )
            }
        }

        // Caso haja estouro projetado em algum envelope mas outro envelope esteja folgado, calcula o saldo ajustado pelos envelopes + estouros de ritmo
        let balanceWithEnvelopeOverruns = officialProjectedBalance - totalProjectedEnvelopeOverrun

        // 3. Limite Diário Seguro para os Dias Restantes
        let maxDailyToRespectEnvelopes = daysRemaining > 0 ? (remainingProvisions / Double(daysRemaining)) : 0.0
        let maxDailyToStayPositive = daysRemaining > 0 ? (max(0.0, baseBalanceAfterScheduledItems) / Double(daysRemaining)) : 0.0

        let envelopeSection: String
        if envelopePaceLines.isEmpty {
            envelopeSection = "• Você não possui tetos/envelopes configurados para \(monthLabel). Configure tetos para que eu monitore o estouro categoria por categoria."
        } else {
            envelopeSection = envelopePaceLines.joined(separator: "\n")
        }

        // Resumo das maiores categorias do mês
        let topCats = store.categoryBreakdown(for: targetMonth, type: .expense).prefix(5)
        let topCatsText = topCats.isEmpty
            ? "• Nenhuma despesa registrada no mês."
            : topCats.map { "• **\($0.category.name):** \(BRLFormatters.currency($0.total)) (`\(String(format: "%.1f", $0.percentage))%`)" }.joined(separator: "\n")

        let headlineStatusIcon = balanceAtVariablePace >= 0 ? "✅" : "⚠️"
        let paceVsEnvelopesComparison: String = {
            let diff = balanceAtVariablePace - officialProjectedBalance
            if abs(diff) < 1.0 {
                return "Seu ritmo diário atual está exatamente alinhado às suas provisões do mês."
            } else if diff > 0 {
                return "No ritmo diário atual (`\(BRLFormatters.currency(dailyVariablePace))/dia` em gastos variáveis), você está gastando **abaixo** do limite total reservado nos seus envelopes (`\(BRLFormatters.currency(remainingProvisions))` restantes), o que fará você terminar o mês com **+\(BRLFormatters.currency(diff)) a mais** do que a projeção oficial de **\(BRLFormatters.currency(officialProjectedBalance))**!"
            } else {
                return "Atenção: no ritmo diário atual (`\(BRLFormatters.currency(dailyVariablePace))/dia`), seus gastos variáveis superarão a reserva restante dos envelopes em **\(BRLFormatters.currency(abs(diff)))**, reduzindo seu saldo final de **\(BRLFormatters.currency(officialProjectedBalance))** para **\(BRLFormatters.currency(balanceAtVariablePace))**."
            }
        }()

        let markdown = """
        ## 📈 Projeção de Fim de Mês pelo Seu Ritmo de Gastos (\(monthLabel))
        *Análise calculada no **dia \(daysElapsed) de \(totalDaysInMonth)** (restam **\(daysRemaining) dias** para o fechamento do mês)*

        ### 🎯 Resposta Direta: Quanto você terá ao final do mês?
        1. **\(headlineStatusIcon) Mantendo seu Ritmo Diário de Gastos Variáveis (`\(BRLFormatters.currency(dailyVariablePace))/dia`):**
           Você terminará **\(monthLabel)** com **\(BRLFormatters.currency(balanceAtVariablePace))** de patrimônio consolidado (**\(BRLFormatters.currency(checkingBalanceAtVariablePace))** em conta corrente).
           *(Cálculo: Saldo Atual de \(BRLFormatters.currency(totalPatrimonyNow)) + Receitas Pendentes de \(BRLFormatters.currency(pendingIncome)) − Despesas Agendadas de \(BRLFormatters.currency(pendingExpenseTotal)) − Projeção de \(daysRemaining) dias × \(BRLFormatters.currency(dailyVariablePace))/dia = **\(BRLFormatters.currency(balanceAtVariablePace))**)*
        2. **🛡️ Cenário Pelos Seus Envelopes/Tetos (Com Estouro Projetado por Categoria):**
           - **Saldo Projetado Oficial (respeitando 100% dos tetos):** **\(BRLFormatters.currency(officialProjectedBalance))** *(considerando \(BRLFormatters.currency(remainingProvisions)) de provisão restante)*
           - **Saldo Ajustado pelo Ritmo de Cada Envelope:** **\(BRLFormatters.currency(balanceWithEnvelopeOverruns))** \(totalProjectedEnvelopeOverrun > 0 ? "*(descontando `-\(BRLFormatters.currency(totalProjectedEnvelopeOverrun))` de estouro projetado nos envelopes que estão acelerados)*" : "*(nenhum envelope com tendência de estouro)*")
        3. **⚠️ Cenário de Estresse (Extrapolação Linear Bruta de Todos os Gastos = `\(BRLFormatters.currency(dailyTotalOperationalPace))/dia`):**
           Se até os gastos fixos/faturas já pagos (**\(BRLFormatters.currency(operationalPaidExpense))** em \(daysElapsed) dias) se repetissem todos os dias, a projeção seria de **\(BRLFormatters.currency(balanceAtLinearTotalPace))**. *(Como faturas, moradia e cursos ocorrem apenas 1x ao mês, o **Cenário 1 (\(BRLFormatters.currency(balanceAtVariablePace)))** e o **Cenário 2 (\(BRLFormatters.currency(balanceWithEnvelopeOverruns)))** refletem seu caixa real).*

        > 💡 **Diagnóstico do Agente:** \(paceVsEnvelopesComparison)

        ---
        ### 📊 Raio-X do Seu Ritmo em \(monthLabel) (Até o Dia \(daysElapsed))
        - **Saldo Disponível Agora:** **\(BRLFormatters.currency(checkingNow))** em contas | **\(BRLFormatters.currency(consolidatedInvNow))** em investimentos consolidados *(Total: \(BRLFormatters.currency(stdTotalInvestments(store))))*
        - **Receitas de \(monthLabel):** **\(BRLFormatters.currency(receivedIncome))** já recebidas + **\(BRLFormatters.currency(pendingIncome))** pendentes a receber = **\(BRLFormatters.currency(totalMonthIncome))**
        - **Despesas Já Pagas (\(daysElapsed) dias):** **\(BRLFormatters.currency(paidExpenseTotal))**
          - *Compromissos Fixos / Boletos / Parcelas:* **\(BRLFormatters.currency(fixedAndCommittedPaid))**
          - *Aplicações / Reservas em Investimentos:* **\(BRLFormatters.currency(investmentTransferPaid))**
          - *Gastos Variáveis / Consumo do Dia a Dia:* **\(BRLFormatters.currency(effectiveVariableSpentSoFar))** → **Ritmo de `\(BRLFormatters.currency(dailyVariablePace)) / dia`** (Projeção p/ o mês: **\(BRLFormatters.currency(projectedTotalVariableAtMonthEnd))**)
        - **Despesas Agendadas Pendentes (até dia \(totalDaysInMonth)):** **\(BRLFormatters.currency(pendingExpenseTotal))** *(Total registrado no mês: \(BRLFormatters.currency(totalMonthRegisteredExpense)))*

        ### 🎯 Projeção do Ritmo nos Seus Envelopes Dinâmicos
        \(envelopeSection)

        ### 🧭 Meta Diária Segura para os Próximos \(daysRemaining) Dias
        - **Para fechar com os \(BRLFormatters.currency(officialProjectedBalance)) planejados nos envelopes:** gaste no máximo **\(BRLFormatters.currency(maxDailyToRespectEnvelopes)) / dia** nas categorias variáveis.
        - **Limite máximo absoluto para não terminar o mês no negativo:** **\(BRLFormatters.currency(maxDailyToStayPositive)) / dia**.

        ### 📂 Maiores Pesos do Mês por Categoria
        \(topCatsText)

        ---
        💬 **Quer aprofundar?** Posso **listar todas as transações** que formaram esse ritmo em \(monthLabel), **simular uma meta de economia** (ex: cortar 20% dos variáveis) ou **ajustar seus envelopes**. O que prefere fazer (ou digite *"encerrar"* se já estiver satisfeito)?
        """

        let followUps = [
            "Mostre os lançamentos que mais pesaram neste mês",
            "E se eu reduzir meus gastos variáveis em 20%?",
            "Quais despesas de R$ \(String(format: "%.2f", pendingExpenseTotal)) ainda estão pendentes neste mês?",
            "Obrigado, pode encerrar"
        ]

        return (markdown, followUps)
    }

    private static func stdTotalInvestments(_ store: FinancialDataStore) -> Double {
        store.totalInvestmentsBalance
    }

    private static func executeDetailedMonthPaceBreakdownFollowUp(
        targetMonth: Date,
        store: FinancialDataStore,
        memory: inout AgentSessionMemory
    ) -> (markdown: String, followUps: [String]) {
        memory.pendingQuestionKind = nil
        let monthLabel = BRLFormatters.monthYear(targetMonth)
        let txs = store.transactionsForMonth(targetMonth).filter { !$0.ignoreInConsolidated && $0.type == .expense }
        let paidTxs = txs.filter(\.isPaid).sorted { $0.amount > $1.amount }
        let unpaidTxs = txs.filter { !$0.isPaid }.sorted { $0.date < $1.date }

        let paidLines = paidTxs.prefix(12).map { tx in
            let cat = store.category(for: tx.categoryId)?.name ?? "Outros"
            return "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **\(BRLFormatters.currency(tx.amount))** (*\(cat)*)"
        }.joined(separator: "\n")

        let unpaidLines = unpaidTxs.isEmpty
            ? "• Nenhuma despesa pendente restante em \(monthLabel)."
            : unpaidTxs.map { tx in
                let cat = store.category(for: tx.categoryId)?.name ?? "Outros"
                return "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **\(BRLFormatters.currency(tx.amount))** (*\(cat)* • Pendente)"
            }.joined(separator: "\n")

        let markdown = """
        ## 🔍 Detalhamento das Despesas de \(monthLabel)
        Aqui estão os lançamentos reais da sua base local que compõem o ritmo deste mês:

        ### 1. Maiores Despesas Já Pagas (\(paidTxs.count) lançamentos — Total: \(BRLFormatters.currency(store.monthlyPaidExpense(for: targetMonth))))
        \(paidLines.isEmpty ? "• Nenhuma despesa paga registrada." : paidLines)

        ### 2. Despesas Pendentes Agendadas até o Fim do Mês (\(unpaidTxs.count) lançamentos — Total: \(BRLFormatters.currency(store.monthlyPendingExpense(for: targetMonth))))
        \(unpaidLines)

        ---
        💬 **Como deseja prosseguir?** Posso simular o impacto de cortar algum desses itens, reajustar o teto de alguma categoria ou encerrar por aqui.
        """

        return (
            markdown,
            [
                "Reserve R$ 400 para alimentação este mês",
                "Qual é o panorama das minhas dívidas em aberto?",
                "Obrigado, pode encerrar"
            ]
        )
    }

    // MARK: - Tool 6: What-If Financial Simulator ("E se...")

    private static func executeWhatIfSimulationTool(
        prompt: String,
        normPrompt: String,
        store: FinancialDataStore,
        memory: inout AgentSessionMemory
    ) -> (markdown: String, followUps: [String]) {
        memory.activeTopic = .whatIfSimulation
        let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
        let monthLabel = BRLFormatters.monthYear(targetMonth)

        let checkingNow = store.totalCheckingBalanceNow
        let patrimonyNow = store.totalConsolidatedPatrimonyNow
        let projectedEndOfMonth = store.accumulatedConsolidatedBalance(throughMonth: targetMonth, includeProjectedUnpaid: true)
        let extractedAmount = LocalLLMService.extractFirstCurrencyAmount(from: prompt) ?? 500.0

        // Verifica se é simulação de corte percentual (ex: "reduzir em 20%", "cortar 15%")
        if normPrompt.contains("%") || normPrompt.contains("por cento") || normPrompt.contains("reduzir") || normPrompt.contains("cortar") {
            let pct = extractPercentage(from: prompt) ?? 20.0
            let monthExp = store.monthlyExpense(for: targetMonth)
            let envelopesTotal = store.totalEstimatedProvision(for: targetMonth)
            let baseToCut = envelopesTotal > 0 ? envelopesTotal : monthExp
            let monthlySavings = baseToCut * (pct / 100.0)
            let annualSavings = monthlySavings * 12.0
            let newProjectedMonthEnd = projectedEndOfMonth + monthlySavings

            let md = """
            ## 🧪 Simulação: Redução de \(String(format: "%.0f%%", pct)) nos Gastos (\(monthLabel))
            - **Base Analisada:** \(BRLFormatters.currency(baseToCut)) \(envelopesTotal > 0 ? "(Total dos Envelopes/Gastos Variáveis)" : "(Despesas Totais do Mês)")
            - **Economia Mensal Gerada (\(String(format: "%.0f%%", pct))):** **+\(BRLFormatters.currency(monthlySavings)) / mês**
            - **Economia Acumulada em 12 Meses:** **+\(BRLFormatters.currency(annualSavings)) / ano**
            - **Saldo Projetado Atual no Fim de \(monthLabel):** \(BRLFormatters.currency(projectedEndOfMonth))
            - **🚀 Novo Saldo Projetado com a Economia:** **\(BRLFormatters.currency(newProjectedMonthEnd))**

            💬 Deseja simular outro percentual, aplicar esse novo limite nos seus envelopes ou encerrar a conversa?
            """
            return (
                md,
                [
                    "E se eu reduzir 30%?",
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Obrigado, pode encerrar"
                ]
            )
        }

        // Simulação de Compra / Novo Gasto de R$ X
        let balanceAfterPurchaseNow = checkingNow - extractedAmount
        let projectedAfterPurchase = projectedEndOfMonth - extractedAmount
        let isSafe = balanceAfterPurchaseNow >= 0 && projectedAfterPurchase >= 0

        let safetyVerdict = isSafe
            ? "✅ **Sim, é viável!** Seu caixa suporta o desembolso de **\(BRLFormatters.currency(extractedAmount))** mantendo saldo positivo hoje (**\(BRLFormatters.currency(balanceAfterPurchaseNow))**) e no fechamento projetado do mês (**\(BRLFormatters.currency(projectedAfterPurchase))**)."
            : "⚠️ **Atenção ao Risco de Caixa!** Um desembolso à vista de **\(BRLFormatters.currency(extractedAmount))** deixaria seu saldo imediato em **\(BRLFormatters.currency(balanceAfterPurchaseNow))** e o fechamento projetado de \(monthLabel) em **\(BRLFormatters.currency(projectedAfterPurchase))**."

        let installment6x = extractedAmount / 6.0
        let installment12x = extractedAmount / 12.0

        let md = """
        ## 🧪 Simulação de Impacto Financeiro: **\(BRLFormatters.currency(extractedAmount))**
        *Cruzando o valor simulado com seu saldo real e compromissos de \(monthLabel)*

        ### 1. Diagnóstico de Viabilidade
        \(safetyVerdict)

        ### 2. Comparativo de Cenários
        - **Antes da Simulação:**
          - Saldo em Conta Hoje: **\(BRLFormatters.currency(checkingNow))** *(Patrimônio Consolidado: \(BRLFormatters.currency(patrimonyNow)))*
          - Saldo Projetado Fim de \(monthLabel): **\(BRLFormatters.currency(projectedEndOfMonth))**
        - **Opção A — À Vista (`\(BRLFormatters.currency(extractedAmount))`):**
          - Saldo em Conta Imediato: **\(BRLFormatters.currency(balanceAfterPurchaseNow))**
          - Saldo Projetado Fim de \(monthLabel): **\(BRLFormatters.currency(projectedAfterPurchase))**
        - **Opção B — Parcelado em 6x (`\(BRLFormatters.currency(installment6x))/mês`):**
          - Saldo Projetado Fim de \(monthLabel): **\(BRLFormatters.currency(projectedEndOfMonth - installment6x))**
        - **Opção C — Parcelado em 12x (`\(BRLFormatters.currency(installment12x))/mês`):**
          - Saldo Projetado Fim de \(monthLabel): **\(BRLFormatters.currency(projectedEndOfMonth - installment12x))**

        ---
        💬 Deseja simular outro valor, verificar o impacto nas suas dívidas ou encerrar?
        """

        return (
            md,
            [
                "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                "Quais são minhas despesas pendentes neste mês?",
                "Obrigado, pode encerrar"
            ]
        )
    }

    // MARK: - Tool 7: Accounts & Investments Portfolio Query

    private static func executeAccountsAndInvestmentsTool(
        prompt: String,
        normPrompt: String,
        store: FinancialDataStore,
        memory: inout AgentSessionMemory
    ) -> (markdown: String, followUps: [String]) {
        memory.activeTopic = .accountsAndInvestments
        let monthLabel = BRLFormatters.monthYear(store.selectedMonth)

        let accLines = store.accounts.isEmpty
            ? "• Nenhuma conta bancária cadastrada."
            : store.accounts.map { acc in
                let cur = store.currentBalance(forAccount: acc.id)
                let proj = store.currentBalance(forAccount: acc.id, upTo: store.selectedMonth)
                return "- **\(acc.name)** (Saldo Inicial: \(BRLFormatters.currency(acc.initialBalance))): Saldo Realizado Hoje **\(BRLFormatters.currency(cur))** | Projetado em \(monthLabel): **\(BRLFormatters.currency(proj))**"
            }.joined(separator: "\n")

        let invLines = store.investments.isEmpty
            ? "• Nenhum investimento cadastrado."
            : store.investments.map { inv in
                let accName = store.account(for: inv.investmentAccountId)?.name ?? "Conta"
                let badge = inv.showInConsolidated ? "Exibido no Consolidado" : "Oculto no Consolidado"
                return "- **\(inv.name)** (*\(inv.groupName)* • \(accName)): **\(BRLFormatters.currency(inv.balance))** (*\(badge)* • \(inv.movements.count) mov.)"
            }.joined(separator: "\n")

        let md = """
        ## 🏦 Contas Bancárias, Investimentos e Patrimônio
        *Dados em tempo real da sua base local*

        ### 1. Consolidação de Liquidez
        - **Saldo Total em Contas Correntes Hoje:** **\(BRLFormatters.currency(store.totalCheckingBalanceNow))**
        - **Investimentos Exibidos no Consolidado:** **\(BRLFormatters.currency(store.consolidatedInvestmentsBalance))**
        - **Total Geral em Todos os Investimentos:** **\(BRLFormatters.currency(store.totalInvestmentsBalance))**
        - **Patrimônio Consolidado Atual:** **\(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))**
        - **Saldo Projetado p/ Fim de \(monthLabel):** **\(BRLFormatters.currency(store.accumulatedConsolidatedBalance(throughMonth: store.selectedMonth)))**

        ### 2. Saldos por Conta Bancária (\(store.accounts.count))
        \(accLines)

        ### 3. Carteiras de Investimento (\(store.investments.count))
        \(invLines)

        ---
        💬 Deseja consultar o extrato de alguma conta específica, simular o uso da reserva para abater dívidas ou encerrar?
        """

        return (
            md,
            [
                "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                "Quais foram minhas maiores despesas neste mês?",
                "Obrigado, pode encerrar"
            ]
        )
    }

    // MARK: - Tool 8: Deep Transactions, Categories, Pending Bills & Subscriptions Query

    private static func executeTransactionsAndCategoriesQueryTool(
        prompt: String,
        normPrompt: String,
        store: FinancialDataStore,
        ragHits: [RAGSearchResult],
        memory: inout AgentSessionMemory
    ) -> (markdown: String, followUps: [String]) {
        memory.activeTopic = .transactionsQuery
        let targetMonth = resolveTargetMonth(from: normPrompt, defaultDate: store.selectedMonth)
        let monthLabel = BRLFormatters.monthYear(targetMonth)
        store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: targetMonth))

        let monthTxs = store.transactionsForMonth(targetMonth).filter { !$0.ignoreInConsolidated }

        // Sub-intenção A: Contas Pendentes / O que falta pagar
        if normPrompt.contains("pendente") || normPrompt.contains("falta pagar") || normPrompt.contains("faltam pagar") || normPrompt.contains("a vencer") || normPrompt.contains("nao paga") {
            let pendingExpenses = monthTxs.filter { $0.type == .expense && !$0.isPaid }.sorted { $0.date < $1.date }
            let pendingIncomes = monthTxs.filter { $0.type == .income && !$0.isPaid }.sorted { $0.date < $1.date }
            let totalPendExp = pendingExpenses.reduce(0.0) { $0 + $1.amount }
            let totalPendInc = pendingIncomes.reduce(0.0) { $0 + $1.amount }

            let expList = pendingExpenses.isEmpty
                ? "✅ **Parabéns! Você não possui nenhuma despesa pendente em \(monthLabel).**"
                : pendingExpenses.map { tx in
                    let catName = store.category(for: tx.categoryId)?.name ?? "Outros"
                    let accName = store.account(for: tx.accountId)?.name ?? "Conta"
                    return "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **\(BRLFormatters.currency(tx.amount))** (*\(catName)* • \(accName))"
                }.joined(separator: "\n")

            let incList = pendingIncomes.isEmpty
                ? "• Nenhuma receita pendente em \(monthLabel)."
                : pendingIncomes.map { tx in
                    "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **+\(BRLFormatters.currency(tx.amount))**"
                }.joined(separator: "\n")

            let md = """
            ## 📅 Compromissos Pendentes em \(monthLabel)
            - **Total de Despesas a Pagar no Mês:** **\(BRLFormatters.currency(totalPendExp))** (\(pendingExpenses.count) lançamento(s))
            - **Total de Receitas a Receber no Mês:** **\(BRLFormatters.currency(totalPendInc))** (\(pendingIncomes.count) lançamento(s))
            - **Saldo Disponível Hoje:** **\(BRLFormatters.currency(store.totalCheckingBalanceNow))**
            - **Saldo Projetado no Fechamento de \(monthLabel):** **\(BRLFormatters.currency(store.accumulatedConsolidatedBalance(throughMonth: targetMonth)))**

            ### Despesas Pendentes por Ordem de Vencimento
            \(expList)

            ### Receitas Pendentes no Mês
            \(incList)

            ---
            💬 Deseja verificar o ritmo de gastos até o fim do mês, consultar outra categoria ou encerrar?
            """
            return (
                md,
                [
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Quais foram minhas maiores despesas pagas neste mês?",
                    "Obrigado, pode encerrar"
                ]
            )
        }

        // Sub-intenção B: Compras Parceladas / Assinaturas Recorrentes
        if normPrompt.contains("parcelad") || normPrompt.contains("parcelamento") || normPrompt.contains("recorrente") || normPrompt.contains("assinatura") {
            let installmentTxs = monthTxs.filter { $0.recurrenceMode == .installment }
            let recurringTxs = monthTxs.filter { $0.recurrenceMode == .recurring || $0.recurrenceMode == .repeated }
            let totalInst = installmentTxs.reduce(0.0) { $0 + $1.amount }
            let totalRec = recurringTxs.reduce(0.0) { $0 + $1.amount }

            let instLines = installmentTxs.isEmpty
                ? "• Nenhuma parcela ativa em \(monthLabel)."
                : installmentTxs.map { tx in
                    "- **\(tx.name):** **\(BRLFormatters.currency(tx.amount))** (Venc: \(BRLFormatters.shortDate(tx.date)) • \(tx.isPaid ? "Pago" : "Pendente"))"
                }.joined(separator: "\n")

            let recLines = recurringTxs.isEmpty
                ? "• Nenhuma recorrência ativa em \(monthLabel)."
                : recurringTxs.map { tx in
                    "- **\(tx.name) (\(tx.type.title)):** **\(BRLFormatters.currency(tx.amount))** (Data: \(BRLFormatters.shortDate(tx.date)) • \(tx.isPaid ? "Realizado" : "Pendente"))"
                }.joined(separator: "\n")

            let md = """
            ## 🔄 Parcelamentos e Recorrências em \(monthLabel)
            - **Total em Compras/Contratos Parcelados no Mês:** **\(BRLFormatters.currency(totalInst))** (\(installmentTxs.count) itens)
            - **Total em Lançamentos Recorrentes/Fixos no Mês:** **\(BRLFormatters.currency(totalRec))** (\(recurringTxs.count) itens)

            ### 1. Parcelamentos do Mês
            \(instLines)

            ### 2. Recorrências e Fixos do Mês
            \(recLines)

            ---
            💬 Quer saber quando algum parcelamento termina, simular amortização ou encerrar?
            """
            return (
                md,
                [
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Qual o panorama das minhas dívidas e empréstimos?",
                    "Obrigado, pode encerrar"
                ]
            )
        }

        // Sub-intenção C: Categoria Específica mencionada na pergunta
        if let matchedCat = matchCategoryInPrompt(normPrompt: normPrompt, store: store) {
            memory.lastCategoryId = matchedCat.id
            let catTxs = monthTxs.filter { $0.categoryId == matchedCat.id }.sorted { $0.date > $1.date }
            let catTotal = catTxs.reduce(0.0) { $0 + $1.amount }
            let env = store.provisionEnvelope(forCategory: matchedCat.id, in: targetMonth)
            let quotas = store.quotaEnvelopes(forCategory: matchedCat.id, in: targetMonth)

            let txLines = catTxs.isEmpty
                ? "• Nenhum lançamento registrado em **\(matchedCat.name)** em \(monthLabel)."
                : catTxs.prefix(15).map { tx in
                    "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **\(BRLFormatters.currency(tx.amount))** (\(tx.isPaid ? "Pago" : "Pendente"))"
                }.joined(separator: "\n")

            let envBlock = env.map { e in
                "- **Envelope/Teto Configurado:** \(BRLFormatters.currency(e.estimatedAmount)) | **Gasto Avulso:** \(BRLFormatters.currency(e.realizedExpense)) | **Restante:** **\(BRLFormatters.currency(e.remainingProvision))** (*\(e.status.rawValue)*)"
            } ?? "- **Envelope/Teto:** Sem teto configurado para esta categoria em \(monthLabel)."

            let quotaBlock = quotas.isEmpty
                ? ""
                : "\n- **Cotas Específicas da Categoria:** " + quotas.map { "\($0.name) (\($0.consumedUnits)/\($0.plannedQuantity) un. • Restam \(BRLFormatters.currency($0.remainingProvision)))" }.joined(separator: "; ")

            let md = """
            ## 📂 Análise da Categoria: **\(matchedCat.name)** (\(monthLabel))
            - **Total Movimentado no Mês:** **\(BRLFormatters.currency(catTotal))** (\(catTxs.count) lançamento(s))
            \(envBlock)\(quotaBlock)

            ### Lançamentos em \(monthLabel)
            \(txLines)

            ---
            💬 Deseja definir/alterar um teto para **\(matchedCat.name)**, analisar outra categoria ou encerrar?
            """
            return (
                md,
                [
                    "Reserve R$ 500 para \(matchedCat.name.lowercased()) este mês",
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Obrigado, pode encerrar"
                ]
            )
        }

        // Sub-intenção D: Visão Detalhada de Receitas e Despesas do Mês + Ranking de Categorias
        let breakdownExp = store.categoryBreakdown(for: targetMonth, type: .expense)
        let breakdownInc = store.categoryBreakdown(for: targetMonth, type: .income)
        let topTransactions = monthTxs.filter { $0.type == .expense }.sorted { $0.amount > $1.amount }.prefix(10)

        let catLines = breakdownExp.isEmpty
            ? "• Nenhuma despesa em \(monthLabel)."
            : breakdownExp.map {
                "- **\($0.category.name):** **\(BRLFormatters.currency($0.total))** (`\(String(format: "%.1f%%", $0.percentage))` • \($0.count) lanç.)"
            }.joined(separator: "\n")

        let incLines = breakdownInc.isEmpty
            ? "• Nenhuma receita em \(monthLabel)."
            : breakdownInc.map {
                "- **\($0.category.name):** **\(BRLFormatters.currency($0.total))** (\($0.count) lanç.)"
            }.joined(separator: "\n")

        let topTxLines = topTransactions.isEmpty
            ? "• Sem despesas registradas."
            : topTransactions.map { tx in
                let cat = store.category(for: tx.categoryId)?.name ?? "Outros"
                return "- **\(BRLFormatters.shortDate(tx.date)) — \(tx.name):** **\(BRLFormatters.currency(tx.amount))** (*\(cat)* • \(tx.isPaid ? "Pago" : "Pendente"))"
            }.joined(separator: "\n")

        let md = """
        ## 📊 Análise Completa de Transações e Categorias (\(monthLabel))
        - **Receitas Totais do Mês:** **\(BRLFormatters.currency(store.monthlyIncome(for: targetMonth)))** *(Recebidas: \(BRLFormatters.currency(store.monthlyReceivedIncome(for: targetMonth))) | Pendentes: \(BRLFormatters.currency(store.monthlyPendingIncome(for: targetMonth))))*
        - **Despesas Totais do Mês:** **\(BRLFormatters.currency(store.monthlyExpense(for: targetMonth)))** *(Pagas: \(BRLFormatters.currency(store.monthlyPaidExpense(for: targetMonth))) | Pendentes: \(BRLFormatters.currency(store.monthlyPendingExpense(for: targetMonth))))*
        - **Provisões Variáveis Restantes:** **\(BRLFormatters.currency(store.totalRemainingProvision(for: targetMonth)))**
        - **Saldo Projetado Fim de \(monthLabel):** **\(BRLFormatters.currency(store.accumulatedConsolidatedBalance(throughMonth: targetMonth)))**

        ### 1. Despesas por Categoria em \(monthLabel)
        \(catLines)

        ### 2. Top 10 Maiores Lançamentos de Despesa do Mês
        \(topTxLines)

        ### 3. Receitas por Categoria
        \(incLines)

        ---
        💬 Quer projetar com quanto você fechará o mês mantendo o ritmo atual, filtrar uma categoria específica ou encerrar?
        """

        return (
            md,
            [
                "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                "Quais contas ainda faltam pagar neste mês?",
                "Obrigado, pode encerrar"
            ]
        )
    }

    // MARK: - Tool 9: Universal RAG Cross-Database Synthesis

    private static func executeUniversalRAGSynthesisTool(
        prompt: String,
        normPrompt: String,
        store: FinancialDataStore,
        ragHits: [RAGSearchResult],
        memory: inout AgentSessionMemory
    ) -> (markdown: String, followUps: [String]) {
        memory.activeTopic = .generalOverview

        let isExplicitOverview = normPrompt.contains("panorama") || normPrompt.contains("visao geral") ||
                                 normPrompt.contains("resumo geral") || normPrompt.contains("resumo completo") ||
                                 normPrompt.contains("resumo de tudo")

        if isExplicitOverview {
            let overview = LocalLLMService.generateComprehensiveDatabaseOverview(store: store)
            return (
                overview,
                [
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Quais contas ainda faltam pagar neste mês?",
                    "Quanto vou pagar de parcelas de financiamento e empréstimos próximo mês?",
                    "Obrigado, pode encerrar"
                ]
            )
        }

        // Se o RAG encontrou transações altamente específicas para o termo pesquisado
        let highConfidenceHits = ragHits.filter { $0.combinedScore >= 0.20 }
        let txHits = highConfidenceHits.filter { $0.document.entityType == .transaction }

        if !txHits.isEmpty {
            let txSum = txHits.compactMap { $0.document.amount }.reduce(0.0, +)
            var lines: [String] = []
            lines.append("Encontrei **\(txHits.count)** lançamento(s) na sua base de dados:")
            for hit in txHits.prefix(6) {
                let dateStr = hit.document.date.map { BRLFormatters.shortDate($0) } ?? ""
                let amtStr = hit.document.amount.map { BRLFormatters.currency($0) } ?? ""
                lines.append("• **\(dateStr)** — **\(hit.document.title)**: **\(amtStr)**")
            }
            if txHits.count > 1 {
                lines.append("\n- **Soma dos lançamentos encontrados:** **\(BRLFormatters.currency(txSum))**")
            }
            lines.append("\n---")
            lines.append("💬 Deseja detalhar algum desses lançamentos, filtrar por período ou encerrar?")

            return (
                lines.joined(separator: "\n"),
                [
                    "Qual categoria eu mais gasto?",
                    "Se eu continuar gastando no ritmo deste mês, terei quanto no final?",
                    "Obrigado, pode encerrar"
                ]
            )
        }

        // Resposta focada e direta com resumo dos saldos e despesas
        let currentChecking = store.totalCheckingBalanceNow
        let currentMonthExp = store.monthlyExpense(for: store.selectedMonth)
        let currentMonthInc = store.monthlyIncome(for: store.selectedMonth)
        let monthLabel = BRLFormatters.monthYear(store.selectedMonth)

        let cleanSummary = """
        ### Resumo Financeiro Atual (\(monthLabel))
        - **Saldo Disponível em Contas:** **\(BRLFormatters.currency(currentChecking))**
        - **Receitas Registradas no Mês:** **\(BRLFormatters.currency(currentMonthInc))**
        - **Despesas Registradas no Mês:** **\(BRLFormatters.currency(currentMonthExp))**
        - **Patrimônio Consolidado Total:** **\(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))**

        💬 Como posso te orientar agora? Você pode perguntar sobre sua última transação, ritmo de gastos, parcelas de contratos ou quitação de dívidas.
        """

        return (
            cleanSummary,
            [
                "Qual foi a minha última transação?",
                "Qual categoria eu mais gasto?",
                "Quanto vou pagar de parcelas de financiamento e empréstimos próximo mês?",
                "Obrigado, pode encerrar"
            ]
        )
    }

    // MARK: - Helpers

    private static func matchCategoryInPrompt(normPrompt: String, store: FinancialDataStore) -> CategoryItem? {
        for cat in store.categories {
            let normCat = FinancialRAGIndex.normalizeText(cat.name)
            if normPrompt.contains(normCat) {
                return cat
            }
            let tokens = FinancialRAGIndex.tokenize(normCat).filter { $0.count >= 4 }
            if tokens.contains(where: { normPrompt.contains($0) }) {
                return cat
            }
        }
        return nil
    }

    private static func resolveTargetMonth(from normPrompt: String, defaultDate: Date) -> Date {
        let cal = Calendar.current
        if normPrompt.contains("proximo mes") || normPrompt.contains("mes que vem") {
            return cal.date(byAdding: .month, value: 1, to: defaultDate) ?? defaultDate
        }
        if normPrompt.contains("mes passado") || normPrompt.contains("mes anterior") {
            return cal.date(byAdding: .month, value: -1, to: defaultDate) ?? defaultDate
        }
        let monthNames: [(name: String, month: Int)] = [
            ("janeiro", 1), ("fevereiro", 2), ("marco", 3), ("abril", 4),
            ("maio", 5), ("junho", 6), ("julho", 7), ("agosto", 8),
            ("setembro", 9), ("outubro", 10), ("novembro", 11), ("dezembro", 12)
        ]
        var targetYear = cal.component(.year, from: defaultDate)
        for y in [2025, 2026, 2027, 2028] {
            if normPrompt.contains(String(y)) {
                targetYear = y
                break
            }
        }
        for item in monthNames {
            if normPrompt.contains(item.name) {
                var comps = DateComponents()
                comps.year = targetYear
                comps.month = item.month
                comps.day = 15
                if let resolved = cal.date(from: comps) {
                    return resolved
                }
            }
        }
        return defaultDate
    }

    private static func extractPercentage(from text: String) -> Double? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges >= 2 else { return nil }
        let raw = nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }
}
