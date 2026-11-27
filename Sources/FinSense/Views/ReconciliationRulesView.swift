import SwiftUI

public struct ReconciliationRulesView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var editingRule: ReconciliationRule? = nil
    @State private var showCreateSheet: Bool = false
    @State private var testText: String = ""

    public init(store: FinancialDataStore) {
        self.store = store
    }

    private var sortedRules: [ReconciliationRule] {
        store.reconciliationRules.sorted {
            $0.priority == $1.priority ? $0.createdAt < $1.createdAt : $0.priority < $1.priority
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Motor de Regras de Conciliação")
                        .font(.title3.bold())
                    Text("Regras determinísticas executadas em ordem de prioridade antes da IA ao importar extratos ou receber compras via Apple Pay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Nova Regra", systemImage: "plus")
                }
                .buttonStyle(BentoPrimaryButtonStyle(color: FinSenseTheme.indigo))
            }

            // Sandbox rápido de teste
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Testar descrição (ex: UBER *TRIP, IFOOD, IPIRANGA)...", text: $testText)
                    .textFieldStyle(.roundedBorder)
                if !testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let outcome = ReconciliationRulesEngine.firstMatch(
                        rules: sortedRules,
                        name: testText,
                        details: testText,
                        rawStatementLine: testText,
                        amount: 100.0
                    ) {
                        let catName = outcome.appliedCategoryId.flatMap { store.category(for: $0)?.name } ?? "Sem mudança"
                        Label("Casou: \(outcome.matchedRule.name) → \(catName)", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: "#10B981"))
                    } else {
                        Text("Nenhuma regra ativa casou (seguirá para heurística/IA)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .bentoCard(padding: 12, cornerRadius: 11)

            if sortedRules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist.unchecked")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Nenhuma regra cadastrada")
                        .font(.headline)
                    Text("Crie regras SE / ENTÃO aqui ou diretamente em qualquer transação clicando em \"Criar regra\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .bentoCard(padding: 28, cornerRadius: 14)

                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedRules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showCreateSheet) {
            ReconciliationRuleEditorSheet(store: store, existingRule: nil)
        }
        .sheet(item: $editingRule) { rule in
            ReconciliationRuleEditorSheet(store: store, existingRule: rule)
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: ReconciliationRule) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("#\(rule.priority)")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    var updated = rule
                    updated.isEnabled = enabled
                    store.updateReconciliationRule(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(rule.matchField.title) \(rule.matchOperator.title) \"\(rule.matchPattern)\"")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }

                HStack(spacing: 8) {
                    if let catId = rule.targetCategoryId, let cat = store.category(for: catId) {
                        Label(cat.name, systemImage: cat.iconSymbol)
                            .font(.caption2)
                            .foregroundStyle(Color(hex: cat.colorHex))
                    }
                    if let clean = rule.cleanName, !clean.isEmpty {
                        Text("→ \"\(clean)\"")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if rule.markReimbursable == true {
                        Text("Reembolsável (\(rule.reimbursableDebtor ?? "Terceiro"))")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "#F59E0B"))
                    }
                    if rule.markRecurring == true {
                        Text("Recorrente")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "#06B6D4"))
                    }
                }
            }

            Spacer()

            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                store.deleteReconciliationRule(rule.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .bentoCard(padding: 12, cornerRadius: 12)
        .opacity(rule.isEnabled ? 1.0 : 0.55)
    }
}

public struct ReconciliationRuleEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let existingRule: ReconciliationRule?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var priority: Int = 10
    @State private var isEnabled: Bool = true
    @State private var matchField: RuleMatchField = .nameOrDetails
    @State private var matchOperator: RuleMatchOperator = .contains
    @State private var matchPattern: String = ""
    @State private var minAmountText: String = ""
    @State private var maxAmountText: String = ""
    @State private var sourceAccountId: UUID? = nil
    @State private var sourceCreditCardId: UUID? = nil
    @State private var targetCategoryId: UUID? = nil
    @State private var cleanName: String = ""
    @State private var markRecurring: Bool = false
    @State private var markReimbursable: Bool = false
    @State private var reimbursableDebtor: String = ""
    @State private var markIgnoreInConsolidated: Bool = false

    public init(store: FinancialDataStore, existingRule: ReconciliationRule?) {
        self.store = store
        self.existingRule = existingRule
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingRule == nil ? "Nova Regra de Conciliação" : "Editar Regra")
                .font(.title2.bold())

            Form {
                Section("Condição (SE)") {
                    TextField("Nome da regra (Ex: Uber → Transporte)", text: $name)
                    Stepper("Prioridade (menor executa primeiro): \(priority)", value: $priority, in: 1...999, step: 5)
                    Picker("Campo analisado", selection: $matchField) {
                        ForEach(RuleMatchField.allCases) { f in Text(f.title).tag(f) }
                    }
                    Picker("Operador", selection: $matchOperator) {
                        ForEach(RuleMatchOperator.allCases) { op in Text(op.title).tag(op) }
                    }
                    TextField("Texto / Padrão (ou Regex)", text: $matchPattern)
                    HStack {
                        TextField("Valor mín. (opc.)", text: $minAmountText)
                        TextField("Valor máx. (opc.)", text: $maxAmountText)
                    }
                    Picker("Restringir à Conta (opc.)", selection: $sourceAccountId) {
                        Text("Qualquer conta").tag(UUID?.none)
                        ForEach(store.accounts) { acc in Text(acc.name).tag(UUID?.some(acc.id)) }
                    }
                    Picker("Restringir ao Cartão (opc.)", selection: $sourceCreditCardId) {
                        Text("Qualquer cartão").tag(UUID?.none)
                        ForEach(store.creditCards) { c in Text(c.name).tag(UUID?.some(c.id)) }
                    }
                }

                Section("Ações (ENTÃO)") {
                    Picker("Definir Categoria", selection: $targetCategoryId) {
                        Text("Manter original").tag(UUID?.none)
                        ForEach(store.categories) { cat in Text("\(cat.name) (\(cat.type.title))").tag(UUID?.some(cat.id)) }
                    }
                    TextField("Renomear / Limpar Título (opc.)", text: $cleanName)
                    Toggle("Marcar como Recorrente", isOn: $markRecurring)
                    Toggle("Marcar como Reembolsável", isOn: $markReimbursable)
                    if markReimbursable {
                        TextField("Devedor padrão (Ex: Empresa)", text: $reimbursableDebtor)
                    }
                    Toggle("Ignorar no consolidado (ex: transferência)", isOn: $markIgnoreInConsolidated)
                    Toggle("Regra ativa", isOn: $isEnabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar Regra") {
                    let trimmedPat = matchPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedPat.isEmpty else { return }
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let minA = BRLFormatters.parseAmount(minAmountText)
                    let maxA = BRLFormatters.parseAmount(maxAmountText)

                    if var existing = existingRule {
                        existing.name = trimmedName.isEmpty ? "Regra: \(trimmedPat)" : trimmedName
                        existing.priority = priority
                        existing.isEnabled = isEnabled
                        existing.matchField = matchField
                        existing.matchOperator = matchOperator
                        existing.matchPattern = trimmedPat
                        existing.minAmount = minA
                        existing.maxAmount = maxA
                        existing.sourceAccountId = sourceAccountId
                        existing.sourceCreditCardId = sourceCreditCardId
                        existing.targetCategoryId = targetCategoryId
                        existing.cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleanName
                        existing.markRecurring = markRecurring ? true : nil
                        existing.markReimbursable = markReimbursable ? true : nil
                        existing.reimbursableDebtor = markReimbursable ? reimbursableDebtor : nil
                        existing.markIgnoreInConsolidated = markIgnoreInConsolidated ? true : nil
                        store.updateReconciliationRule(existing)
                    } else {
                        let newRule = ReconciliationRule(
                            name: trimmedName.isEmpty ? "Regra: \(trimmedPat)" : trimmedName,
                            priority: priority,
                            isEnabled: isEnabled,
                            matchField: matchField,
                            matchOperator: matchOperator,
                            matchPattern: trimmedPat,
                            minAmount: minA,
                            maxAmount: maxA,
                            sourceAccountId: sourceAccountId,
                            sourceCreditCardId: sourceCreditCardId,
                            targetCategoryId: targetCategoryId,
                            cleanName: cleanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleanName,
                            markRecurring: markRecurring ? true : nil,
                            markReimbursable: markReimbursable ? true : nil,
                            reimbursableDebtor: markReimbursable ? reimbursableDebtor : nil,
                            markIgnoreInConsolidated: markIgnoreInConsolidated ? true : nil
                        )
                        store.addReconciliationRule(newRule)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 610)
        .onAppear {
            if let r = existingRule {
                name = r.name
                priority = r.priority
                isEnabled = r.isEnabled
                matchField = r.matchField
                matchOperator = r.matchOperator
                matchPattern = r.matchPattern
                if let minA = r.minAmount { minAmountText = String(format: "%.2f", minA) }
                if let maxA = r.maxAmount { maxAmountText = String(format: "%.2f", maxA) }
                sourceAccountId = r.sourceAccountId
                sourceCreditCardId = r.sourceCreditCardId
                targetCategoryId = r.targetCategoryId
                cleanName = r.cleanName ?? ""
                markRecurring = r.markRecurring ?? false
                markReimbursable = r.markReimbursable ?? false
                reimbursableDebtor = r.reimbursableDebtor ?? ""
                markIgnoreInConsolidated = r.markIgnoreInConsolidated ?? false
            }
        }
    }
}
