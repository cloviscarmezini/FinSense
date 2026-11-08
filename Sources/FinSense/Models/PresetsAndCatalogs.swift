import Foundation
import SwiftUI
import AppKit

// MARK: - Major Brazilian Banks Catalog

public enum BrazilianBanksCatalog {
    public static let presets: [BankPreset] = [
        BankPreset(
            id: "itau",
            name: "Itaú Unibanco",
            shortCode: "341",
            monogram: "itaú",
            primaryHex: "#EC7000",
            secondaryHex: "#003399",
            symbolName: "building.columns.fill"
        ),
        BankPreset(
            id: "nubank",
            name: "Nubank",
            shortCode: "260",
            monogram: "nu",
            primaryHex: "#820AD1",
            secondaryHex: "#4B0082",
            symbolName: "creditcard.fill"
        ),
        BankPreset(
            id: "santander",
            name: "Santander",
            shortCode: "033",
            monogram: "SAN",
            primaryHex: "#EC0000",
            secondaryHex: "#990000",
            symbolName: "flame.fill"
        ),
        BankPreset(
            id: "bradesco",
            name: "Bradesco",
            shortCode: "237",
            monogram: "BRA",
            primaryHex: "#CC092F",
            secondaryHex: "#8A0620",
            symbolName: "building.2.fill"
        ),
        BankPreset(
            id: "bb",
            name: "Banco do Brasil",
            shortCode: "001",
            monogram: "BB",
            primaryHex: "#F8D117",
            secondaryHex: "#0038A8",
            symbolName: "banknote.fill"
        ),
        BankPreset(
            id: "caixa",
            name: "Caixa Econômica",
            shortCode: "104",
            monogram: "CEF",
            primaryHex: "#005CA9",
            secondaryHex: "#F39200",
            symbolName: "xmark.square.fill"
        ),
        BankPreset(
            id: "inter",
            name: "Banco Inter",
            shortCode: "077",
            monogram: "inter",
            primaryHex: "#FF7A00",
            secondaryHex: "#CC6200",
            symbolName: "globe.americas.fill"
        ),
        BankPreset(
            id: "c6",
            name: "C6 Bank",
            shortCode: "336",
            monogram: "C6",
            primaryHex: "#242424",
            secondaryHex: "#555555",
            symbolName: "circle.hexagongrid.fill"
        ),
        BankPreset(
            id: "btg",
            name: "BTG Pactual",
            shortCode: "208",
            monogram: "BTG",
            primaryHex: "#001E62",
            secondaryHex: "#0047BB",
            symbolName: "chart.bar.xaxis"
        ),
        BankPreset(
            id: "mercadopago",
            name: "Mercado Pago",
            shortCode: "323",
            monogram: "MP",
            primaryHex: "#009EE3",
            secondaryHex: "#005E8A",
            symbolName: "hands.sparkles.fill"
        ),
        BankPreset(
            id: "picpay",
            name: "PicPay",
            shortCode: "380",
            monogram: "Pic",
            primaryHex: "#11C76F",
            secondaryHex: "#0B8449",
            symbolName: "qrcode.viewfinder"
        ),
        BankPreset(
            id: "xp",
            name: "XP Investimentos",
            shortCode: "348",
            monogram: "XP",
            primaryHex: "#1C1C1E",
            secondaryHex: "#EAB308",
            symbolName: "chart.line.uptrend.xyaxis"
        ),
        BankPreset(
            id: "sicredi",
            name: "Sicredi",
            shortCode: "748",
            monogram: "SIC",
            primaryHex: "#3FA110",
            secondaryHex: "#266309",
            symbolName: "leaf.fill"
        ),
        BankPreset(
            id: "sicoob",
            name: "Sicoob",
            shortCode: "756",
            monogram: "SCB",
            primaryHex: "#003641",
            secondaryHex: "#00AE9D",
            symbolName: "triangle.fill"
        ),
        BankPreset(
            id: "safra",
            name: "Banco Safra",
            shortCode: "422",
            monogram: "SAF",
            primaryHex: "#1B2432",
            secondaryHex: "#C5A059",
            symbolName: "shield.fill"
        ),
        BankPreset(
            id: "neon",
            name: "Neon",
            shortCode: "735",
            monogram: "NEON",
            primaryHex: "#00E5FF",
            secondaryHex: "#0077FF",
            symbolName: "sparkles"
        ),
        BankPreset(
            id: "carteira",
            name: "Carteira Física / Espécie",
            shortCode: "000",
            monogram: "R$",
            primaryHex: "#10B981",
            secondaryHex: "#047857",
            symbolName: "wallet.pass.fill"
        )
    ]

    public static func preset(for id: String?) -> BankPreset? {
        guard let id else { return nil }
        return presets.first(where: { $0.id == id })
    }
}

// MARK: - Default Categories

public enum DefaultCategoriesCatalog {
    public static func buildInitialCategories() -> [CategoryItem] {
        [
            // DESPESAS
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                name: "Supermercado & Atacado",
                type: .expense,
                iconSymbol: "cart.fill",
                colorHex: "#F97316",
                keywords: ["DELTA", "SAMS", "ATACADAO", "ASSAI", "CARREFOUR", "PAO DE ACUCAR", "MERCADO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                name: "Alimentação & Delivery",
                type: .expense,
                iconSymbol: "fork.knife",
                colorHex: "#EF4444",
                keywords: ["99 FOOD", "IFOOD", "KFC", "PIZZI", "DOCER", "ACAIF", "CACAU", "BACIO", "FRANG", "MACAR", "CEVAD", "SOPHI", "WANDO", "MR MI", "KCOWO", "MAJO", "CAPPT", "RESTAURANTE", "LANCHONETE", "PADARIA", "LANCHE", "LANCHES", "HAMBURGUER"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                name: "Moradia & Condomínio",
                type: .expense,
                iconSymbol: "house.fill",
                colorHex: "#6366F1",
                keywords: ["CONDOMI", "BBZ ADMINISTRACAO", "ALUGUEL", "IPTU", "CASA", "OBRAM", "REFORMA"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                name: "Energia, Água & Gás",
                type: .expense,
                iconSymbol: "bolt.fill",
                colorHex: "#EAB308",
                keywords: ["CPFL", "COMGAS", "S.PIRACICAB", "SABESP", "ENEL", "LUZ", "AGUA", "GAS"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
                name: "Telefonia & Internet",
                type: .expense,
                iconSymbol: "wifi",
                colorHex: "#06B6D4",
                keywords: ["VIVO", "CLARO", "TELEFONICA", "TIM", "INTERNET", "CELULAR"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
                name: "Transporte & Mobilidade",
                type: .expense,
                iconSymbol: "bus.fill",
                colorHex: "#3B82F6",
                keywords: ["UBER", "99POP", "MOBIFACIL", "PEDAGIO", "PASSAGEM", "METRO", "ONIBUS"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
                name: "Combustível & Automóvel",
                type: .expense,
                iconSymbol: "fuelpump.fill",
                colorHex: "#0EA5E9",
                keywords: ["AUTO", "AUTOZ", "POSTO", "IPIRANGA", "SHELL", "ESTACIONAMENTO", "OFICINA", "IPVA", "GASOLINA", "COMBUSTIVEL", "ETANOL", "ABASTECIMENTO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000019")!,
                name: "Lazer & Entretenimento",
                type: .expense,
                iconSymbol: "gamecontroller.fill",
                colorHex: "#A855F7",
                keywords: ["LAZER", "CINEMA", "TEATRO", "SHOW", "PASSEIO", "PARQUE", "VIAGEM", "INGRESSO", "JOGOS", "ENTRETENIMENTO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!,
                name: "Compras & E-Commerce",
                type: .expense,
                iconSymbol: "bag.fill",
                colorHex: "#EC4899",
                keywords: ["MARKETP", "AMAZON", "HAVAN", "PAGAR ME", "LOJAS", "VOLLU", "L4U", "MP R", "SHOPEE", "MERCADO LIVRE"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000009")!,
                name: "Pets & Veterinário",
                type: .expense,
                iconSymbol: "pawprint.fill",
                colorHex: "#84CC16",
                keywords: ["COBAS", "PETZ", "AGROM", "VETERINAR", "PET"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000010")!,
                name: "Educação & Cursos",
                type: .expense,
                iconSymbol: "graduationcap.fill",
                colorHex: "#8B5CF6",
                keywords: ["VSTP EDUCAC", "ESCOLA", "FACULDADE", "CURSO", "LIVRO", "EDUCAC"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000011")!,
                name: "Saúde & Farmácia",
                type: .expense,
                iconSymbol: "cross.case.fill",
                colorHex: "#14B8A6",
                keywords: ["DROGASIL", "DROGA", "RAIA", "FARMACIA", "MEDICO", "UNIMED", "HOSPITAL", "EVO V"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000018")!,
                name: "Cuidado Pessoal & Estética",
                type: .expense,
                iconSymbol: "scissors",
                colorHex: "#EC4899",
                keywords: ["CABELELEIRO", "CABELEIREIRO", "BARBEARIA", "SALAO", "ESTETICA", "CUIDADO PESSOAL", "BELEZA", "MANICURE", "COSMETICO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000012")!,
                name: "Cartão de Crédito & Boletos",
                type: .expense,
                iconSymbol: "creditcard.fill",
                colorHex: "#F43F5E",
                keywords: ["BRADESCARD", "FATURA", "PAG BOLETO", "CARTAO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000013")!,
                name: "Aplicações & Reservas",
                type: .expense,
                iconSymbol: "Safe",
                colorHex: "#10B981",
                keywords: ["APLICACAO COFRINHOS", "APLICACAO CDB", "APLICACAO", "INVESTIMENTO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000014")!,
                name: "Transferências & PIX Enviado",
                type: .expense,
                iconSymbol: "paperplane.fill",
                colorHex: "#64748B",
                keywords: ["PIX TRANSF", "TED", "DOC", "JEFFERS", "MICHEL", "MIGUEL", "BRENDA", "FABIO", "ELAIN", "JIM C", "MIKA"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000015")!,
                name: "Empréstimos & Financiamentos",
                type: .expense,
                iconSymbol: "building.columns.circle.fill",
                colorHex: "#D97706",
                keywords: ["EMPRESTIMO", "CONSIGNADO", "FINANCIAMENTO", "PARCELA", "QUITACAO", "AMORTIZACAO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000016")!,
                name: "Quitação de Dívidas",
                type: .expense,
                iconSymbol: "checkmark.shield.fill",
                colorHex: "#DC2626",
                keywords: ["DIVIDA", "ACORDO", "SERASA", "NEGOCIACAO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000017")!,
                name: "Outras Despesas",
                type: .expense,
                iconSymbol: "ellipsis.circle.fill",
                colorHex: "#94A3B8",
                keywords: [],
                isSystemDefault: true
            ),

            // RECEITAS
            CategoryItem(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                name: "Salário & Remuneração",
                type: .income,
                iconSymbol: "banknote.fill",
                colorHex: "#10B981",
                keywords: ["SALARIO", "REMUNERACAO", "PRO-LABORE", "PAGTO SALARIO", "5.237", "3.900"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                name: "PIX Recebido & Transferências",
                type: .income,
                iconSymbol: "arrow.down.left.circle.fill",
                colorHex: "#22C55E",
                keywords: ["PIX TRANSF", "RECEBIDO", "CLOVIS", "BRENDA", "DANIELE"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
                name: "Resgate de Investimentos & Cofrinhos",
                type: .income,
                iconSymbol: "arrow.uturn.backward.circle.fill",
                colorHex: "#06B6D4",
                keywords: ["RESGATE COFRINHOS", "RESGATE CDB", "RESGATE"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
                name: "Rendimentos & Dividendos",
                type: .income,
                iconSymbol: "chart.line.uptrend.xyaxis",
                colorHex: "#14B8A6",
                keywords: ["REND PAGO", "RENDIMENTO", "DIVIDENDO", "JUROS"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000005")!,
                name: "Reembolso & Estorno",
                type: .income,
                iconSymbol: "arrow.counterclockwise.circle.fill",
                colorHex: "#3B82F6",
                keywords: ["DEV PIX", "ESTORNO", "REEMBOLSO", "DEVOLUCAO"],
                isSystemDefault: true
            ),
            CategoryItem(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000006")!,
                name: "Outras Receitas",
                type: .income,
                iconSymbol: "plus.circle.fill",
                colorHex: "#84CC16",
                keywords: [],
                isSystemDefault: true
            )
        ]
    }
}

// MARK: - Complete macOS SF Symbols Catalog for Category Selection

public struct MacSymbolGroup: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let symbols: [MacSymbolItem]
}

public struct MacSymbolItem: Identifiable, Hashable {
    public var id: String { symbol }
    public let symbol: String
    public let label: String
    public let tags: [String]
}

public enum MacIconCatalog {
    public static let groups: [MacSymbolGroup] = [
        MacSymbolGroup(
            id: "finance",
            title: "Finanças, Bancos & Pagamentos",
            symbols: [
                MacSymbolItem(symbol: "banknote.fill", label: "Cédula / Dinheiro", tags: ["dinheiro", "salario", "nota", "pagamento"]),
                MacSymbolItem(symbol: "creditcard.fill", label: "Cartão de Crédito", tags: ["cartao", "credito", "debito", "fatura"]),
                MacSymbolItem(symbol: "building.columns.fill", label: "Banco / Instituição", tags: ["banco", "instituicao", "agencia"]),
                MacSymbolItem(symbol: "wallet.pass.fill", label: "Carteira", tags: ["carteira", "bolso", "especie"]),
                MacSymbolItem(symbol: "dollarsign.circle.fill", label: "Cifrão / Moeda", tags: ["moeda", "cifrao", "real", "dolar"]),
                MacSymbolItem(symbol: "brazilianrealsign.circle.fill", label: "Real Brasileiro (R$)", tags: ["real", "brl", "moeda"]),
                MacSymbolItem(symbol: "chart.line.uptrend.xyaxis", label: "Investimento / Alta", tags: ["investimento", "acao", "rendimento", "bolsa"]),
                MacSymbolItem(symbol: "chart.pie.fill", label: "Gráfico de Pizza", tags: ["grafico", "relatorio", "divisao"]),
                MacSymbolItem(symbol: "chart.bar.fill", label: "Gráfico de Barras", tags: ["grafico", "estatistica", "metas"]),
                MacSymbolItem(symbol: "percent", label: "Juros / Taxa (%)", tags: ["juros", "taxa", "porcentagem", "imposto"]),
                MacSymbolItem(symbol: "qrcode", label: "QR Code / PIX", tags: ["pix", "qrcode", "pagamento"]),
                MacSymbolItem(symbol: "barcode.viewfinder", label: "Boleto Bancário", tags: ["boleto", "conta", "codigo"]),
                MacSymbolItem(symbol: "arrow.left.arrow.right.circle.fill", label: "Transferência", tags: ["transferencia", "ted", "pix"]),
                MacSymbolItem(symbol: "arrow.down.left.circle.fill", label: "Recebimento", tags: ["receita", "entrada", "deposito"]),
                MacSymbolItem(symbol: "arrow.up.right.circle.fill", label: "Saída / Pagamento", tags: ["despesa", "saida", "envio"]),
                MacSymbolItem(symbol: "arrow.counterclockwise.circle.fill", label: "Estorno / Reembolso", tags: ["estorno", "devolucao", "reembolso"]),
                MacSymbolItem(symbol: "lock.shield.fill", label: "Reserva / Seguro", tags: ["seguro", "reserva", "cofrinho"]),
                MacSymbolItem(symbol: "exclamationmark.shield.fill", label: "Dívida / Alerta", tags: ["divida", "atraso", "serasa"]),
                MacSymbolItem(symbol: "checkmark.seal.fill", label: "Quitado / Garantia", tags: ["quitado", "acordo", "pago"]),
                MacSymbolItem(symbol: "signature", label: "Contrato / Empréstimo", tags: ["contrato", "emprestimo", "consignado"])
            ]
        ),
        MacSymbolGroup(
            id: "food_shopping",
            title: "Alimentação, Mercado & Compras",
            symbols: [
                MacSymbolItem(symbol: "cart.fill", label: "Carrinho de Supermercado", tags: ["mercado", "supermercado", "compras", "atacado"]),
                MacSymbolItem(symbol: "basket.fill", label: "Cesta de Compras", tags: ["cesta", "feira", "hortifruti"]),
                MacSymbolItem(symbol: "fork.knife", label: "Restaurante & Refeição", tags: ["restaurante", "comida", "almoco", "jantar", "ifood"]),
                MacSymbolItem(symbol: "cup.and.saucer.fill", label: "Café & Padaria", tags: ["cafe", "padaria", "lanche"]),
                MacSymbolItem(symbol: "wineglass.fill", label: "Bebidas & Bar", tags: ["bar", "bebida", "vinho", "cerveja"]),
                MacSymbolItem(symbol: "birthday.cake.fill", label: "Doces & Confeitaria", tags: ["doce", "bolo", "festa", "cacau"]),
                MacSymbolItem(symbol: "takeoutbag.and.cup.and.straw.fill", label: "Delivery & Fast Food", tags: ["delivery", "fastfood", "99food", "ifood"]),
                MacSymbolItem(symbol: "bag.fill", label: "Sacola de Compras", tags: ["shopping", "loja", "roupa", "presente"]),
                MacSymbolItem(symbol: "shippingbox.fill", label: "Encomenda / E-commerce", tags: ["amazon", "mercadolivre", "entrega", "correios"]),
                MacSymbolItem(symbol: "tshirt.fill", label: "Vestuário & Moda", tags: ["roupa", "camisa", "moda", "calcado"]),
                MacSymbolItem(symbol: "gift.fill", label: "Presentes & Mimos", tags: ["presente", "aniversario", "doacao"]),
                MacSymbolItem(symbol: "tag.fill", label: "Oferta / Etiqueta", tags: ["promocao", "desconto", "venda"])
            ]
        ),
        MacSymbolGroup(
            id: "home_utilities",
            title: "Moradia, Contas & Utilidades",
            symbols: [
                MacSymbolItem(symbol: "house.fill", label: "Casa / Aluguel / Condomínio", tags: ["casa", "moradia", "condominio", "aluguel"]),
                MacSymbolItem(symbol: "building.2.fill", label: "Apartamento / Prédio", tags: ["apartamento", "predio", "imovel"]),
                MacSymbolItem(symbol: "bolt.fill", label: "Energia Elétrica", tags: ["luz", "energia", "cpfl", "enel"]),
                MacSymbolItem(symbol: "drop.fill", label: "Água & Saneamento", tags: ["agua", "sabesp", "esgoto"]),
                MacSymbolItem(symbol: "flame.fill", label: "Gás Encanado / Botijão", tags: ["gas", "comgas", "cozinha"]),
                MacSymbolItem(symbol: "wifi", label: "Internet & Banda Larga", tags: ["internet", "wifi", "fibra", "vivo", "claro"]),
                MacSymbolItem(symbol: "iphone", label: "Celular & Telefonia", tags: ["celular", "telefone", "tim", "vivo"]),
                MacSymbolItem(symbol: "tv.fill", label: "TV & Streaming", tags: ["tv", "netflix", "streaming", "assinatura"]),
                MacSymbolItem(symbol: "hammer.fill", label: "Reforma & Manutenção", tags: ["obra", "reforma", "conserto", "ferramenta"]),
                MacSymbolItem(symbol: "sofa.fill", label: "Móveis & Decoração", tags: ["moveis", "decoracao", "casa"]),
                MacSymbolItem(symbol: "washer.fill", label: "Eletrodomésticos", tags: ["eletrodomestico", "lavanderia"]),
                MacSymbolItem(symbol: "key.fill", label: "Chaves / Financiamento Imob.", tags: ["chave", "imovel", "financiamento"])
            ]
        ),
        MacSymbolGroup(
            id: "transport_travel",
            title: "Transporte, Veículos & Viagens",
            symbols: [
                MacSymbolItem(symbol: "car.fill", label: "Carro / Automóvel", tags: ["carro", "veiculo", "financiamento", "auto"]),
                MacSymbolItem(symbol: "fuelpump.fill", label: "Posto de Combustível", tags: ["gasolina", "etanol", "diesel", "posto"]),
                MacSymbolItem(symbol: "bus.fill", label: "Ônibus & Transporte Público", tags: ["onibus", "mobifacil", "passagem"]),
                MacSymbolItem(symbol: "tram.fill", label: "Metrô & Trem", tags: ["metro", "trem", "bilhete"]),
                MacSymbolItem(symbol: "bicycle", label: "Bicicleta / Micromobilidade", tags: ["bike", "bicicleta"]),
                MacSymbolItem(symbol: "airplane", label: "Viagem & Passagem Aérea", tags: ["aviao", "viagem", "ferias", "voo"]),
                MacSymbolItem(symbol: "suitcase.rolling.fill", label: "Hospedagem & Turismo", tags: ["hotel", "mala", "turismo", "airbnb"]),
                MacSymbolItem(symbol: "wrench.and.screwdriver.fill", label: "Oficina & Mecânico", tags: ["oficina", "mecanico", "revisao", "pneu"]),
                MacSymbolItem(symbol: "parkingsign.circle.fill", label: "Estacionamento & Pedágio", tags: ["estacionamento", "semparar", "pedagio"]),
                MacSymbolItem(symbol: "location.fill", label: "App de Corrida (Uber/99)", tags: ["uber", "99", "corrida", "taxi"])
            ]
        ),
        MacSymbolGroup(
            id: "health_education_family",
            title: "Saúde, Educação, Família & Pets",
            symbols: [
                MacSymbolItem(symbol: "cross.case.fill", label: "Saúde & Hospital", tags: ["saude", "medico", "consulta", "hospital"]),
                MacSymbolItem(symbol: "pills.fill", label: "Farmácia & Medicamentos", tags: ["farmacia", "remedio", "drogaria"]),
                MacSymbolItem(symbol: "heart.fill", label: "Plano de Saúde & Bem-estar", tags: ["plano", "unimed", "vida", "coracao"]),
                MacSymbolItem(symbol: "dumbbell.fill", label: "Academia & Esportes", tags: ["academia", "treino", "esporte", "fitness"]),
                MacSymbolItem(symbol: "graduationcap.fill", label: "Educação, Faculdade & Escola", tags: ["educacao", "faculdade", "escola", "curso"]),
                MacSymbolItem(symbol: "book.fill", label: "Livros & Material Escolar", tags: ["livro", "leitura", "apostila"]),
                MacSymbolItem(symbol: "pawprint.fill", label: "Pet Shop & Veterinário", tags: ["pet", "cachorro", "gato", "cobasi", "racao"]),
                MacSymbolItem(symbol: "figure.2.and.child.holdinghands", label: "Família & Filhos", tags: ["familia", "filhos", "crianca"]),
                MacSymbolItem(symbol: "scissors", label: "Barbearia, Salão & Estética", tags: ["cabelo", "barbearia", "salao", "beleza"])
            ]
        ),
        MacSymbolGroup(
            id: "leisure_tech_work",
            title: "Lazer, Tecnologia & Trabalho",
            symbols: [
                MacSymbolItem(symbol: "gamecontroller.fill", label: "Games & Entretenimento", tags: ["jogo", "game", "playstation", "steam"]),
                MacSymbolItem(symbol: "ticket.fill", label: "Cinema, Shows & Eventos", tags: ["cinema", "ingresso", "show", "teatro"]),
                MacSymbolItem(symbol: "music.note", label: "Música & Áudio (Spotify)", tags: ["musica", "spotify", "show"]),
                MacSymbolItem(symbol: "laptopcomputer", label: "Computador & Tecnologia", tags: ["macbook", "notebook", "software", "tech"]),
                MacSymbolItem(symbol: "icloud.fill", label: "Nuvem & SaaS", tags: ["icloud", "google", "assinatura", "nuvem"]),
                MacSymbolItem(symbol: "briefcase.fill", label: "Trabalho & Negócios", tags: ["trabalho", "empresa", "escritorio", "freela"]),
                MacSymbolItem(symbol: "doc.text.fill", label: "Impostos, Taxas & Documentos", tags: ["imposto", "darf", "contabilidade", "taxa"]),
                MacSymbolItem(symbol: "person.2.fill", label: "Pessoas & Amigos", tags: ["amigos", "divisao", "transferencia"]),
                MacSymbolItem(symbol: "sparkles", label: "Outros / Especial", tags: ["extra", "bonus", "outros"]),
                MacSymbolItem(symbol: "ellipsis.circle.fill", label: "Geral / Diversos", tags: ["geral", "outros", "diversos"])
            ]
        )
    ]

    public static var allSymbols: [MacSymbolItem] {
        groups.flatMap(\.symbols)
    }

    public static func search(_ query: String) -> [MacSymbolGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return groups }

        var matchedGroups: [MacSymbolGroup] = []
        for group in groups {
            let filtered = group.symbols.filter { item in
                item.label.lowercased().contains(trimmed) ||
                item.symbol.lowercased().contains(trimmed) ||
                item.tags.contains(where: { $0.lowercased().contains(trimmed) })
            }
            if !filtered.isEmpty {
                matchedGroups.append(MacSymbolGroup(id: group.id, title: group.title, symbols: filtered))
            }
        }

        // Also allow typing any native macOS SF Symbol name directly!
        if NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
            let alreadyExists = matchedGroups.flatMap(\.symbols).contains(where: { $0.symbol == trimmed })
            if !alreadyExists {
                matchedGroups.insert(
                    MacSymbolGroup(
                        id: "custom_sf",
                        title: "Símbolo Nativo do macOS Encontrado",
                        symbols: [MacSymbolItem(symbol: trimmed, label: trimmed, tags: [trimmed])]
                    ),
                    at: 0
                )
            }
        }

        return matchedGroups
    }
}

// MARK: - Formatting & Color Extensions

public enum BRLFormatters {
    public static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.currencySymbol = "R$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    public static let monthYearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = "MMMM 'de' yyyy"
        return df
    }()

    public static let shortMonthYearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = "MMM/yy"
        return df
    }()

    public static let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = "EEEE"
        return df
    }()

    public static func currency(_ value: Double) -> String {
        let raw = currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "R$ %.2f", value)
        return raw.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    public static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public static func dayGroupHeader(_ date: Date) -> String {
        let datePart = shortDateFormatter.string(from: date)
        let weekdayPart = weekdayFormatter.string(from: date).capitalized
        return "\(datePart) • \(weekdayPart)"
    }

    public static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date).capitalized
    }

    public static func yearString(_ date: Date) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return String(year)
    }

    public static func parseAmount(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }

        // If contains both '.' and ',', assume pt_BR format: 1.234,56
        if cleaned.contains(",") && cleaned.contains(".") {
            let normalized = cleaned
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        } else if cleaned.contains(",") {
            let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        } else if cleaned.range(of: #"^-?\d{1,3}(?:\.\d{3})+$"#, options: .regularExpression) != nil {
            let normalized = cleaned.replacingOccurrences(of: ".", with: "")
            return Double(normalized)
        } else {
            return Double(cleaned)
        }
    }

    public static func parseCurrencyInput(_ text: String) -> Double {
        parseAmount(text) ?? 0.0
    }

    /// Formata qualquer entrada digitada mantendo apenas números e aplicando máscara de moeda Real (Ex: "450981" -> "R$ 4.509,81")
    public static func formatCurrencyMaskedInput(_ rawText: String) -> String {
        let digitsOnly = rawText.filter { $0.isNumber }
        guard !digitsOnly.isEmpty else { return "" }
        // Remove zeros à esquerda em excesso; se restar vazio (ex: usuário apagou até R$ 0,0), retorna "" para exibir o placeholder
        let trimmedDigits = String(digitsOnly.drop(while: { $0 == "0" }))
        if trimmedDigits.isEmpty {
            return ""
        }
        // Limita a 14 dígitos para evitar overflow (até R$ 999.999.999.999,99)
        let safeDigits = String(trimmedDigits.prefix(14))
        guard let cents = UInt64(safeDigits) else { return "" }
        let value = Double(cents) / 100.0
        return currency(value)
    }

    /// Filtra apenas dígitos inteiros para campos de quantidade de parcelas / meses
    public static func formatDigitsOnly(_ rawText: String, maxDigits: Int = 4) -> String {
        let digits = rawText.filter { $0.isNumber }
        return String(digits.prefix(maxDigits))
    }
}

extension Color {
    public init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 59, 130, 246)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
