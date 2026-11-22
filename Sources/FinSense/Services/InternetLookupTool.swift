import Foundation

/// Serviço de consultas somente-leitura à internet pública (cotações, índices BCB e conceitos financeiros).
/// NUNCA envia nenhum dado pessoal, saldo, contrato ou transação do usuário para fora do Mac.
public enum InternetLookupService {

    public struct FXRateInfo: Sendable {
        public let pair: String
        public let code: String
        public let name: String
        public let bid: Double
        public let ask: Double
        public let pctChange: Double
        public let dateString: String
        public let source: String
    }

    public struct WebSearchSnippet: Sendable {
        public let title: String
        public let summary: String
        public let urlString: String
        public let source: String
    }

    /// Remove valores em reais, UUIDs e sequências numéricas extensas antes de montar qualquer requisição pública.
    public static func sanitizePublicQuery(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "r\\$\\s*[0-9][0-9\\.,]*",
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            "\\b\\d{5,}\\b"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: nsRange, withTemplate: "")
            }
        }
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchJSON(from urlString: String, timeout: TimeInterval = 8.0) async throws -> Any {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "InternetLookup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL inválida"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("FinSense-macOS/1.0 (ReadOnly)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "InternetLookup", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    /// Consulta cotações de câmbio (USD-BRL, EUR-BRL, BTC-BRL, GBP-BRL, etc.) em APIs públicas somente leitura.
    public static func fetchExchangeRates(requestedCodes: [String]) async -> [FXRateInfo] {
        let codes = requestedCodes.isEmpty ? ["USD", "EUR", "BTC"] : requestedCodes
        let pairsParam = codes.map { "\($0.uppercased())-BRL" }.joined(separator: ",")
        let primaryURL = "https://economia.awesomeapi.com.br/json/last/\(pairsParam)"

        if let json = try? await fetchJSON(from: primaryURL) as? [String: Any] {
            var parsed: [FXRateInfo] = []
            for code in codes {
                let key = "\(code.uppercased())BRL"
                if let entry = json[key] as? [String: Any],
                   let bidStr = entry["bid"] as? String,
                   let bid = Double(bidStr) {
                    let ask = (entry["ask"] as? String).flatMap(Double.init) ?? bid
                    let pct = (entry["pctChange"] as? String).flatMap(Double.init) ?? 0.0
                    let name = (entry["name"] as? String) ?? "\(code.uppercased())/BRL"
                    let createDate = (entry["create_date"] as? String) ?? BRLFormatters.shortDate(Date())
                    parsed.append(
                        FXRateInfo(
                            pair: "\(code.uppercased())-BRL",
                            code: code.uppercased(),
                            name: name,
                            bid: bid,
                            ask: ask,
                            pctChange: pct,
                            dateString: createDate,
                            source: "AwesomeAPI Economia"
                        )
                    )
                }
            }
            if !parsed.isEmpty { return parsed }
        }

        // Fallback público aberto: Open Exchange Rates (v6)
        if let json = try? await fetchJSON(from: "https://open.er-api.com/v6/latest/USD") as? [String: Any],
           let rates = json["rates"] as? [String: Any],
           let usdToBrl = (rates["BRL"] as? Double) ?? (rates["BRL"] as? NSNumber)?.doubleValue,
           usdToBrl > 0 {
            let updateStr = (json["time_last_update_utc"] as? String) ?? BRLFormatters.shortDate(Date())
            var fallbackList: [FXRateInfo] = []
            for code in codes {
                let upper = code.uppercased()
                if upper == "USD" {
                    fallbackList.append(
                        FXRateInfo(
                            pair: "USD-BRL",
                            code: "USD",
                            name: "Dólar Americano/Real Brasileiro",
                            bid: usdToBrl,
                            ask: usdToBrl,
                            pctChange: 0.0,
                            dateString: updateStr,
                            source: "Open ER API"
                        )
                    )
                } else if let perUsd = (rates[upper] as? Double) ?? (rates[upper] as? NSNumber)?.doubleValue, perUsd > 0 {
                    let rateBrl = usdToBrl / perUsd
                    fallbackList.append(
                        FXRateInfo(
                            pair: "\(upper)-BRL",
                            code: upper,
                            name: "\(upper)/Real Brasileiro",
                            bid: rateBrl,
                            ask: rateBrl,
                            pctChange: 0.0,
                            dateString: updateStr,
                            source: "Open ER API"
                        )
                    )
                }
            }
            return fallbackList
        }

        return []
    }

    /// Consulta taxas oficiais do Banco Central do Brasil (Selic Meta, CDI e IPCA 12 meses).
    public static func fetchBCBIndicators() async -> [String: Any] {
        async let selicRaw = try? fetchJSON(from: "https://api.bcb.gov.br/dados/serie/bcdata.sgs.432/dados/ultimos/1?formato=json")
        async let cdiRaw = try? fetchJSON(from: "https://api.bcb.gov.br/dados/serie/bcdata.sgs.4389/dados/ultimos/1?formato=json")
        async let ipcaRaw = try? fetchJSON(from: "https://api.bcb.gov.br/dados/serie/bcdata.sgs.433/dados/ultimos/12?formato=json")

        let (selicRes, cdiRes, ipcaRes) = await (selicRaw, cdiRaw, ipcaRaw)
        var out: [String: Any] = ["source": "Banco Central do Brasil (SGS Dados Abertos)"]

        if let arr = selicRes as? [[String: Any]], let last = arr.last,
           let valStr = last["valor"] as? String, let val = Double(valStr) {
            out["selicMetaAnualPercent"] = val
            out["selicData"] = last["data"] ?? ""
        }

        if let arr = cdiRes as? [[String: Any]], let last = arr.last,
           let valStr = last["valor"] as? String, let val = Double(valStr) {
            out["cdiAnualizadoPercent"] = val
            out["cdiData"] = last["data"] ?? ""
        }

        if let arr = ipcaRes as? [[String: Any]], !arr.isEmpty {
            var factor = 1.0
            for item in arr {
                if let valStr = item["valor"] as? String, let monthlyPct = Double(valStr) {
                    factor *= (1.0 + monthlyPct / 100.0)
                }
            }
            let ipca12m = ((factor - 1.0) * 100.0 * 100.0).rounded() / 100.0
            out["ipcaAcumulado12MesesPercent"] = ipca12m
            out["ipcaUltimoMesData"] = arr.last?["data"] ?? ""
        }

        return out
    }

    /// Pesquisa conhecimento financeiro/público (Wikipedia PT + DuckDuckGo Instant Answer) sem enviar dados do usuário.
    public static func fetchPublicSnippets(query: String) async -> [WebSearchSnippet] {
        let clean = sanitizePublicQuery(query)
        guard !clean.isEmpty,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        var snippets: [WebSearchSnippet] = []

        // 1. DuckDuckGo Instant Answer (PT-BR / EN)
        let ddgURL = "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1&kl=br-pt"
        if let json = try? await fetchJSON(from: ddgURL) as? [String: Any] {
            if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
                snippets.append(
                    WebSearchSnippet(
                        title: (json["Heading"] as? String) ?? clean,
                        summary: String(abstract.prefix(550)),
                        urlString: (json["AbstractURL"] as? String) ?? "https://duckduckgo.com",
                        source: (json["AbstractSource"] as? String) ?? "DuckDuckGo"
                    )
                )
            }
        }

        // 2. Wikipedia PT Search + REST Summary
        let wikiSearchURL = "https://pt.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&utf8=&format=json&srlimit=2"
        if let json = try? await fetchJSON(from: wikiSearchURL) as? [String: Any],
           let queryObj = json["query"] as? [String: Any],
           let results = queryObj["search"] as? [[String: Any]] {
            for item in results.prefix(2) {
                if let title = item["title"] as? String,
                   let encodedTitle = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                   let summaryJson = try? await fetchJSON(from: "https://pt.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") as? [String: Any],
                   let extract = summaryJson["extract"] as? String,
                   !extract.isEmpty {
                    let pageUrl = ((summaryJson["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
                    snippets.append(
                        WebSearchSnippet(
                            title: title,
                            summary: String(extract.prefix(550)),
                            urlString: pageUrl ?? "https://pt.wikipedia.org",
                            source: "Wikipedia PT"
                        )
                    )
                }
            }
        }

        return snippets
    }

    public static func detectCurrencyCodes(in normalizedText: String) -> [String] {
        var found: [String] = []
        if normalizedText.contains("dolar") || normalizedText.contains("usd") { found.append("USD") }
        if normalizedText.contains("euro") || normalizedText.contains("eur") { found.append("EUR") }
        if normalizedText.contains("bitcoin") || normalizedText.contains("btc") { found.append("BTC") }
        if normalizedText.contains("libra") || normalizedText.contains("gbp") { found.append("GBP") }
        if normalizedText.contains("iene") || normalizedText.contains("jpy") { found.append("JPY") }
        if normalizedText.contains("canadense") || normalizedText.contains("cad") { found.append("CAD") }
        if normalizedText.contains("peso") || normalizedText.contains("ars") { found.append("ARS") }
        return found.isEmpty ? ["USD", "EUR"] : found
    }

    public static func isCurrencyQuery(_ normalizedText: String) -> Bool {
        let cues = ["dolar", "usd", "euro", "eur", "bitcoin", "btc", "libra", "gbp", "cambio", "cotacao", "moeda", "iene"]
        return cues.contains { normalizedText.contains($0) }
    }

    public static func isMacroRateQuery(_ normalizedText: String) -> Bool {
        let cues = ["selic", "cdi", "ipca", "inflacao", "juros basicos", "taxa basica", "tesouro", "cdb", "lci", "lca", "renda fixa", "investir", "investimento"]
        return cues.contains { normalizedText.contains($0) }
    }
}

/// Ferramenta somente-leitura conectada à internet para cotações, índices BCB e conhecimento público externo.
@MainActor
public struct InternetLookupTool: AIToolProtocol {
    public let name: String = "internet_lookup"
    public let description: String = "Consulta somente leitura na internet pública para cotações atuais (Dólar, Euro, Libra, Bitcoin), taxas econômicas oficiais (Selic, CDI, IPCA do BCB) e informações públicas de investimentos quando não constam no banco local. Nunca envia dados financeiros ou pessoais do usuário."

    public let parametersSchema: [String: Any] = [
        "type": "object",
        "required": ["query"],
        "properties": [
            "query": [
                "type": "string",
                "description": "Termo público de busca (ex: 'dolar hoje', 'selic cdi ipca', 'cdb vs tesouro selic'). Nunca inclua saldos ou dados pessoais."
            ],
            "topic": [
                "type": "string",
                "enum": ["currency", "economic_rates", "investment_info", "general"],
                "description": "Categoria da consulta pública: currency, economic_rates, investment_info ou general"
            ]
        ]
    ]

    private let store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        guard store.llmConfig.isInternetAccessEnabled else {
            return [
                "status": "disabled",
                "message": "As consultas à internet estão desativadas nas Configurações da IA (Ajustes -> Apple Intelligence). Habilite 'Consultas na Internet (Apenas Leitura)' caso queira buscar cotações ou dados externos."
            ]
        }

        let rawQuery = (parameters["query"] as? String) ?? ""
        let safeQuery = InternetLookupService.sanitizePublicQuery(rawQuery)
        let norm = safeQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let topic = ((parameters["topic"] as? String) ?? "").lowercased()

        var payload: [String: Any] = [
            "status": "success",
            "readOnly": true,
            "privacyGuarantee": "Nenhum dado financeiro ou pessoal local foi transmitido na consulta.",
            "sanitizedQuery": safeQuery
        ]

        let wantsFX = topic == "currency" || InternetLookupService.isCurrencyQuery(norm)
        let wantsRates = topic == "economic_rates" || topic == "investment_info" || InternetLookupService.isMacroRateQuery(norm)
        let wantsGeneral = topic == "general" || topic == "investment_info" || (!wantsFX && !wantsRates)

        if wantsFX {
            let codes = InternetLookupService.detectCurrencyCodes(in: norm)
            let rates = await InternetLookupService.fetchExchangeRates(requestedCodes: codes)
            if !rates.isEmpty {
                payload["exchangeRates"] = rates.map { r in
                    [
                        "pair": r.pair,
                        "code": r.code,
                        "name": r.name,
                        "bidBRL": r.bid,
                        "bidFormatted": String(format: "R$ %.4f", r.bid),
                        "askBRL": r.ask,
                        "pctChange": r.pctChange,
                        "updatedAt": r.dateString,
                        "source": r.source
                    ] as [String: Any]
                }

                // Conversão estritamente LOCAL do patrimônio e contas (jamais enviada externamente!)
                let checkingBRL = store.totalCheckingBalanceNow
                let investmentsBRL = store.consolidatedInvestmentsBalance
                let patrimonyBRL = checkingBRL + investmentsBRL
                if let primaryRate = rates.first, primaryRate.bid > 0 {
                    let convertedPatrimony = patrimonyBRL / primaryRate.bid
                    let convertedChecking = checkingBRL / primaryRate.bid
                    let convertedInvestments = investmentsBRL / primaryRate.bid
                    payload["localPatrimonyConversionOnlyLocalMath"] = [
                        "currencyCode": primaryRate.code,
                        "exchangeRateUsed": primaryRate.bid,
                        "patrimonyBRL": BRLFormatters.currency(patrimonyBRL),
                        "checkingBRL": BRLFormatters.currency(checkingBRL),
                        "consolidatedInvestmentsBRL": BRLFormatters.currency(investmentsBRL),
                        "patrimonyConverted": String(format: "%.2f %@", convertedPatrimony, primaryRate.code),
                        "checkingConverted": String(format: "%.2f %@", convertedChecking, primaryRate.code),
                        "investmentsConverted": String(format: "%.2f %@", convertedInvestments, primaryRate.code)
                    ]
                }
            }
        }

        if wantsRates {
            let indicators = await InternetLookupService.fetchBCBIndicators()
            if indicators.count > 1 {
                payload["brazilianMacroIndicators"] = indicators
            }
        }

        if wantsGeneral || (payload["exchangeRates"] == nil && payload["brazilianMacroIndicators"] == nil) {
            let effectiveSearch = safeQuery.isEmpty ? "educacao financeira investimentos brasil" : safeQuery
            let snippets = await InternetLookupService.fetchPublicSnippets(query: effectiveSearch)
            if !snippets.isEmpty {
                payload["publicWebReferences"] = snippets.map { s in
                    [
                        "title": s.title,
                        "summary": s.summary,
                        "source": s.source,
                        "url": s.urlString
                    ]
                }
            }
        }

        if payload["exchangeRates"] == nil && payload["brazilianMacroIndicators"] == nil && payload["publicWebReferences"] == nil {
            payload["status"] = "unreachable_or_no_results"
            payload["message"] = "Não foi possível obter resposta das fontes públicas externas no momento (verifique a conexão com a internet ou tente outro termo)."
        }

        return payload
    }
}
