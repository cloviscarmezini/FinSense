import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Native File Picker Helper (macOS NSOpenPanel)

public enum MacFilePicker {
    @MainActor
    public static func pickImageFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecionar Imagem ou Ícone do Mac"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .icns, .pdf]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickStatementFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecionar Extrato ou Relatório Financeiro (PDF, CSV, TXT)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf, .commaSeparatedText, .plainText, .text, .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickAttachmentFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Anexar Comprovante ou Documento"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item, .image, .pdf, .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func saveJSONFile(defaultFileName: String = "financial_backup_granular.json") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar Dados Financeiros (JSON Estruturado)"
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func saveDatabaseBackupFile(defaultFileName: String = "financial_backup_completo.fcbackup") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar Backup Completo da Base de Dados (Exceto Modelos de IA)"
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.data, .json]
        panel.allowsOtherFileTypes = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickJSONImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Importar Gastos / Transações (JSON)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickDatabaseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecionar Arquivo de Backup ou Importação (.fcbackup / .json)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data, .json, .item]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Bank / Custom Icon Avatar View

public struct AccountAvatarView: View {
    public let customImagePath: String?
    public let bankPresetId: String?
    public let fallbackSymbol: String
    public let colorHex: String
    public var size: CGFloat = 38

    public init(
        customImagePath: String? = nil,
        bankPresetId: String? = nil,
        fallbackSymbol: String = "building.columns.fill",
        colorHex: String = "#EC7000",
        size: CGFloat = 38
    ) {
        self.customImagePath = customImagePath
        self.bankPresetId = bankPresetId
        self.fallbackSymbol = fallbackSymbol
        self.colorHex = colorHex
        self.size = size
    }

    public init(account: BankAccount, size: CGFloat = 38) {
        self.customImagePath = account.customImagePath
        self.bankPresetId = account.bankPresetId
        self.fallbackSymbol = account.iconSymbol
        self.colorHex = account.colorHex
        self.size = size
    }

    public var body: some View {
        if let path = customImagePath,
           !path.isEmpty,
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        } else if let preset = BrazilianBanksCatalog.preset(for: bankPresetId) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: preset.primaryHex), Color(hex: preset.secondaryHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(preset.monogram)
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(3)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .shadow(color: Color(hex: preset.primaryHex).opacity(0.25), radius: 3, x: 0, y: 2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color(hex: colorHex).gradient)
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Category Icon View

public struct CategoryBadgeView: View {
    public let symbol: String
    public let colorHex: String
    public var size: CGFloat = 34

    public init(symbol: String, colorHex: String, size: CGFloat = 34) {
        self.symbol = symbol
        self.colorHex = colorHex
        self.size = size
    }

    public init(category: CategoryItem?, size: CGFloat = 34) {
        self.symbol = category?.iconSymbol ?? "tag.fill"
        self.colorHex = category?.colorHex ?? "#64748B"
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(hex: colorHex).opacity(0.16))
            Image(systemName: validSymbolName(symbol))
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
        }
        .frame(width: size, height: size)
    }

    private func validSymbolName(_ name: String) -> String {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "tag.fill"
    }
}

// MARK: - Month Navigator Bar

public struct MonthNavigatorBar: View {
    @ObservedObject public var store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button {
                store.changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Mês anterior")

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(BRLFormatters.monthYear(store.selectedMonth))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 150)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Button {
                store.changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Próximo mês")

            Menu {
                Button("Mês Atual (Hoje)") {
                    store.selectedMonth = Date()
                    store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: Date()))
                }
            } label: {
                Label("Hoje", systemImage: "calendar.badge.clock")
                    .font(.caption)
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
    }
}

// MARK: - Dashboard Period Navigator Bar (Visão Mensal vs Visão Anual)

public struct DashboardPeriodNavigatorBar: View {
    @ObservedObject public var store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $store.dashboardPeriodMode) {
                ForEach(DashboardPeriodMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 215)
            .onChange(of: store.dashboardPeriodMode) { _, newMode in
                if newMode == .annual {
                    store.ensureRecurringTransactionsMaterialized(upTo: store.endOfYear(for: store.selectedMonth))
                } else {
                    store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: store.selectedMonth))
                }
            }

            if store.dashboardPeriodMode == .monthly {
                MonthNavigatorBar(store: store)
            } else {
                HStack(spacing: 10) {
                    Button {
                        store.changeYear(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help("Ano anterior")

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text("Ano \(BRLFormatters.yearString(store.selectedMonth)) (Proj. 31/12)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(minWidth: 165)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    Button {
                        store.changeYear(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help("Próximo ano")

                    Button("Ano Atual") {
                        store.selectedMonth = Date()
                        store.ensureRecurringTransactionsMaterialized(upTo: store.endOfYear(for: Date()))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Modern KPI Summary Card

public struct MetricCardView: View {
    public static let standardCardHeight: CGFloat = 116

    public let title: String
    public let value: String
    public let subtitle: String
    public let icon: String
    public let tint: Color
    public var footnote: String?
    public var footnoteColor: Color
    public var action: (() -> Void)?
    public var actionLabel: String?
    public var actionIcon: String?
    public var subtitleHelp: String?
    public var cardHeight: CGFloat = MetricCardView.standardCardHeight

    public init(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        tint: Color,
        footnote: String? = nil,
        footnoteColor: Color = .secondary,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil,
        actionIcon: String? = nil,
        subtitleHelp: String? = nil,
        cardHeight: CGFloat = MetricCardView.standardCardHeight
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.footnote = footnote
        self.footnoteColor = footnoteColor
        self.action = action
        self.actionLabel = actionLabel
        self.actionIcon = actionIcon
        self.subtitleHelp = subtitleHelp
        self.cardHeight = cardHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 1. Linha de Cabeçalho (Topo)
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            if let actionIcon {
                                Image(systemName: actionIcon)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            if let actionLabel {
                                Text(actionLabel)
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Editar previsões e tetos deste mês")
                }

                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(minHeight: 28)

            // 2. Linha do Valor Principal (Centro) - posicionado imediatamente abaixo do cabeçalho
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()

            // 3. Linha de Subtítulo / Metadados (Base) - sem abismo vazio, espaçamento imediato
            VStack(alignment: .leading, spacing: 2) {
                if let subtitleHelp {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .help(subtitleHelp)
                } else {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(footnoteColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Native AppKit Full-Width Clickable Input with Auto-Hiding Placeholder

public final class FullWidthClickableNSTextField: NSTextField {
    public override var intrinsicContentSize: NSSize {
        let superSize = super.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: max(superSize.height, 20))
    }

    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== currentEditor() {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }
}

public final class FullWidthClickableNSSecureTextField: NSSecureTextField {
    public override var intrinsicContentSize: NSSize {
        let superSize = super.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: max(superSize.height, 20))
    }

    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== currentEditor() {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }
}

public final class ClickableFieldWrapperNSView: NSView {
    public let placeholderLabel = NSTextField(labelWithString: "")
    public let textField = FullWidthClickableNSTextField()
    public let secureField = FullWidthClickableNSSecureTextField()
    public var isSecureMode: Bool = false {
        didSet {
            textField.isHidden = isSecureMode
            secureField.isHidden = !isSecureMode
            updatePlaceholderVisibility()
        }
    }

    public var activeField: NSTextField {
        isSecureMode ? secureField : textField
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.isBordered = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.alignment = .left
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        placeholderLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        for field in [textField, secureField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.alignment = .left
            field.lineBreakMode = .byTruncatingTail
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.placeholderString = nil
            field.setContentHuggingPriority(.init(1), for: .horizontal)
            field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        }

        secureField.isHidden = true

        addSubview(placeholderLabel)
        addSubview(textField)
        addSubview(secureField)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),

            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: trailingAnchor),
            secureField.topAnchor.constraint(equalTo: topAnchor),
            secureField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    public func updatePlaceholderVisibility() {
        let current = activeField.stringValue
        placeholderLabel.isHidden = !current.isEmpty
    }

    public func focusActiveField() {
        guard let win = window else { return }
        if win.firstResponder !== activeField.currentEditor() {
            win.makeFirstResponder(activeField)
            if let editor = activeField.currentEditor() {
                let len = activeField.stringValue.utf16.count
                editor.selectedRange = NSRange(location: len, length: 0)
            }
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        return activeField
    }

    public override func mouseDown(with event: NSEvent) {
        focusActiveField()
    }
}

public struct MacFullWidthTextInput: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var font: NSFont
    public var isSecure: Bool
    public var focusTrigger: Int
    public var formatterTransform: ((String) -> String)?
    public var onFocusChange: ((Bool) -> Void)?
    public var onCommit: (() -> Void)?

    public init(
        text: Binding<String>,
        placeholder: String,
        font: NSFont = .systemFont(ofSize: 13.5),
        isSecure: Bool = false,
        focusTrigger: Int = 0,
        formatterTransform: ((String) -> String)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.font = font
        self.isSecure = isSecure
        self.focusTrigger = focusTrigger
        self.formatterTransform = formatterTransform
        self.onFocusChange = onFocusChange
        self.onCommit = onCommit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> ClickableFieldWrapperNSView {
        let wrapper = ClickableFieldWrapperNSView()
        wrapper.placeholderLabel.stringValue = placeholder
        wrapper.placeholderLabel.font = font
        wrapper.textField.font = font
        wrapper.secureField.font = font
        wrapper.textField.delegate = context.coordinator
        wrapper.secureField.delegate = context.coordinator
        wrapper.isSecureMode = isSecure
        wrapper.textField.stringValue = text
        wrapper.secureField.stringValue = text
        wrapper.updatePlaceholderVisibility()
        return wrapper
    }

    public func updateNSView(_ nsView: ClickableFieldWrapperNSView, context: Context) {
        context.coordinator.parent = self

        if nsView.placeholderLabel.stringValue != placeholder {
            nsView.placeholderLabel.stringValue = placeholder
        }
        if nsView.textField.font != font {
            nsView.placeholderLabel.font = font
            nsView.textField.font = font
            nsView.secureField.font = font
        }
        if nsView.isSecureMode != isSecure {
            nsView.isSecureMode = isSecure
        }

        let currentField = nsView.activeField
        if currentField.stringValue != text {
            nsView.textField.stringValue = text
            nsView.secureField.stringValue = text
            if let editor = currentField.currentEditor() {
                editor.string = text
                let endPos = text.utf16.count
                editor.selectedRange = NSRange(location: endPos, length: 0)
            }
        }
        nsView.updatePlaceholderVisibility()

        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                nsView.focusActiveField()
            }
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        public var parent: MacFullWidthTextInput
        public var lastFocusTrigger: Int = 0

        public init(_ parent: MacFullWidthTextInput) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField,
               let wrapper = field.superview as? ClickableFieldWrapperNSView {
                wrapper.updatePlaceholderVisibility()
            }
            parent.onFocusChange?(true)
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let rawValue = field.stringValue
            let finalValue: String
            if let transform = parent.formatterTransform {
                finalValue = transform(rawValue)
                if field.stringValue != finalValue {
                    field.stringValue = finalValue
                    if let editor = field.currentEditor() {
                        editor.string = finalValue
                        let endPos = finalValue.utf16.count
                        editor.selectedRange = NSRange(location: endPos, length: 0)
                    }
                }
            } else {
                finalValue = rawValue
            }

            if let wrapper = field.superview as? ClickableFieldWrapperNSView {
                wrapper.textField.stringValue = finalValue
                wrapper.secureField.stringValue = finalValue
                wrapper.updatePlaceholderVisibility()
            }

            if parent.text != finalValue {
                parent.text = finalValue
            }
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField,
               let wrapper = field.superview as? ClickableFieldWrapperNSView {
                wrapper.updatePlaceholderVisibility()
            }
            parent.onFocusChange?(false)
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let onCommit = parent.onCommit {
                    onCommit()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Visible Bordered Text Input, BRL Currency Masked Input & Editable Integer Stepper

public struct BorderedTextField: View {
    public let label: String?
    public let placeholder: String
    @Binding public var text: String
    public var suffix: String? = nil
    public var isSecure: Bool = false
    public var onCommit: (() -> Void)? = nil

    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String? = nil,
        placeholder: String,
        text: Binding<String>,
        suffix: String? = nil,
        isSecure: Bool = false,
        onCommit: (() -> Void)? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.suffix = suffix
        self.isSecure = isSecure
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                MacFullWidthTextInput(
                    text: $text,
                    placeholder: placeholder,
                    font: .systemFont(ofSize: 13.5),
                    isSecure: isSecure,
                    focusTrigger: focusTrigger,
                    onFocusChange: { focused in
                        isFocused = focused
                    },
                    onCommit: onCommit
                )
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)

                if let suffix, !suffix.isEmpty {
                    Text(suffix)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                        lineWidth: isFocused ? 1.6 : 1.2
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusTrigger += 1
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Input monetário com borda visível, clicável em toda a extensão, permitindo apenas números e aplicando máscara de Real (R$ 1.234,56)
public struct BRLCurrencyTextField: View {
    public let label: String
    @Binding public var text: String
    public var placeholder: String

    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String,
        text: Binding<String>,
        placeholder: String = "R$ 0,00"
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("R$")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
                    .foregroundStyle(Color.accentColor)

                MacFullWidthTextInput(
                    text: $text,
                    placeholder: placeholder,
                    font: .systemFont(ofSize: 14, weight: .semibold),
                    focusTrigger: focusTrigger,
                    formatterTransform: { raw in
                        BRLFormatters.formatCurrencyMaskedInput(raw)
                    },
                    onFocusChange: { focused in
                        isFocused = focused
                    }
                )
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                        lineWidth: isFocused ? 1.6 : 1.2
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusTrigger += 1
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Campo numérico com borda visível que permite digitar manualmente números inteiros (ex: quantidade de parcelas ou meses) + Stepper
public struct EditableIntegerStepperField: View {
    public let label: String
    @Binding public var value: Int
    public let range: ClosedRange<Int>
    public var unitSuffix: String

    @State private var textValue: String = ""
    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unitSuffix: String = "x"
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.unitSuffix = unitSuffix
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    MacFullWidthTextInput(
                        text: $textValue,
                        placeholder: "\(range.lowerBound)",
                        font: .systemFont(ofSize: 14, weight: .bold),
                        focusTrigger: focusTrigger,
                        formatterTransform: { raw in
                            BRLFormatters.formatDigitsOnly(raw, maxDigits: 4)
                        },
                        onFocusChange: { focused in
                            isFocused = focused
                            if !focused {
                                // Ao sair do foco, normaliza o texto dentro do limite permitido
                                if let parsed = Int(textValue) {
                                    let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                                    value = clamped
                                    textValue = "\(clamped)"
                                } else {
                                    textValue = "\(value)"
                                }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                    .onChange(of: textValue) { _, newValue in
                        if let parsed = Int(newValue) {
                            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                            if value != clamped {
                                value = clamped
                            }
                        }
                    }

                    if !unitSuffix.isEmpty {
                        Text(unitSuffix)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                            lineWidth: isFocused ? 1.6 : 1.2
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    focusTrigger += 1
                }

                Stepper(
                    "",
                    value: Binding(
                        get: { value },
                        set: { newVal in
                            let clamped = min(max(newVal, range.lowerBound), range.upperBound)
                            value = clamped
                            textValue = "\(clamped)"
                        }
                    ),
                    in: range
                )
                .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            textValue = "\(value)"
        }
        .onChange(of: value) { _, newVal in
            if !isFocused {
                let str = "\(newVal)"
                if textValue != str {
                    textValue = str
                }
            }
        }
    }
}

// MARK: - Native AppKit Full-Area Multiline Text Editor with Auto-Hiding Placeholder & Border

public final class ClickableMultilineScrollView: NSScrollView {
    public let placeholderLabel = NSTextField(wrappingLabelWithString: "")

    public func updatePlaceholderVisibility(currentText: String) {
        placeholderLabel.isHidden = !currentText.isEmpty
    }

    public override func mouseDown(with event: NSEvent) {
        if let docView = documentView {
            window?.makeFirstResponder(docView)
        }
        super.mouseDown(with: event)
    }
}

public struct MacMultilineTextInput: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var font: NSFont
    public var focusTrigger: Int
    public var onFocusChange: ((Bool) -> Void)?

    public init(
        text: Binding<String>,
        placeholder: String,
        font: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .regular),
        focusTrigger: Int = 0,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.font = font
        self.focusTrigger = focusTrigger
        self.onFocusChange = onFocusChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> ClickableMultilineScrollView {
        let scrollView = ClickableMultilineScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView

        let placeholderField = scrollView.placeholderLabel
        placeholderField.translatesAutoresizingMaskIntoConstraints = false
        placeholderField.isEditable = false
        placeholderField.isSelectable = false
        placeholderField.isBordered = false
        placeholderField.drawsBackground = false
        placeholderField.textColor = .placeholderTextColor
        placeholderField.font = font
        placeholderField.stringValue = placeholder
        placeholderField.maximumNumberOfLines = 6

        scrollView.addSubview(placeholderField)
        NSLayoutConstraint.activate([
            placeholderField.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            placeholderField.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            placeholderField.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 6)
        ])

        scrollView.updatePlaceholderVisibility(currentText: text)
        return scrollView
    }

    public func updateNSView(_ nsView: ClickableMultilineScrollView, context: Context) {
        context.coordinator.parent = self
        if nsView.placeholderLabel.stringValue != placeholder {
            nsView.placeholderLabel.stringValue = placeholder
        }
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
            }
            if textView.font != font {
                textView.font = font
                nsView.placeholderLabel.font = font
            }
            if context.coordinator.lastFocusTrigger != focusTrigger {
                context.coordinator.lastFocusTrigger = focusTrigger
                DispatchQueue.main.async {
                    nsView.window?.makeFirstResponder(textView)
                }
            }
        }
        nsView.updatePlaceholderVisibility(currentText: text)
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        public var parent: MacMultilineTextInput
        public var lastFocusTrigger: Int = 0

        public init(_ parent: MacMultilineTextInput) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        public func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange?(true)
        }

        public func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange?(false)
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newStr = textView.string
            if let scrollView = textView.enclosingScrollView as? ClickableMultilineScrollView {
                scrollView.updatePlaceholderVisibility(currentText: newStr)
            }
            if parent.text != newStr {
                parent.text = newStr
            }
        }
    }
}

public struct BorderedMultilineTextEditor: View {
    public let label: String
    public let placeholder: String
    @Binding public var text: String
    public var minHeight: CGFloat = 120

    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String = "",
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 120
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            MacMultilineTextInput(
                text: $text,
                placeholder: placeholder,
                focusTrigger: focusTrigger,
                onFocusChange: { focused in
                    isFocused = focused
                }
            )
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight + 40)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                        lineWidth: isFocused ? 1.6 : 1.2
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusTrigger += 1
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
