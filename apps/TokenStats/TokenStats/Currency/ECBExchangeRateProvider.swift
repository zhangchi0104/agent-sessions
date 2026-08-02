//
//  ECBExchangeRateProvider.swift
//  TokenStats
//
//  Adapter for the ECB's versioned data-only daily reference-rate CSV.
//

import Foundation

nonisolated struct ECBExchangeRateProvider: ExchangeRateProviding {
    static let endpoint = ExchangeRateProviderID.ecb.descriptor.defaultEndpoint
    static let accept = "application/vnd.ecb.data+csv;version=1.0.0"

    private static let descriptiveHeader = [
        "Key", "Frequency", "Currency", "Currency denominator",
        "Exchange rate type", "Series variation - EXR context",
        "Time period or range", "Observation value",
    ]
    private static let compactHeader = [
        "KEY", "FREQ", "CURRENCY", "CURRENCY_DENOM",
        "EXR_TYPE", "EXR_SUFFIX", "TIME_PERIOD", "OBS_VALUE",
    ]

    var session: URLSession = .shared

    func fetchRates(from source: ExchangeRateSource) async throws -> [ExchangeRateQuote] {
        let providerID = ExchangeRateProviderID.ecb
        let request = try ExchangeRateProviderSupport.request(
            for: source,
            expectedProviderID: providerID,
            accept: Self.accept
        )
        let data = try await ExchangeRateProviderSupport.responseData(
            for: request,
            providerID: providerID,
            session: session
        )

        let records: [[String]]
        do {
            records = try StrictCSVParser.parse(data)
        } catch {
            throw ExchangeRateProviderError.invalidResponse(providerID)
        }
        guard let header = records.first else {
            throw ExchangeRateProviderError.emptyTable(providerID)
        }
        let rowFormat: RowFormat
        if header == Self.descriptiveHeader {
            rowFormat = .descriptive
        } else if header == Self.compactHeader {
            rowFormat = .compact
        } else {
            throw ExchangeRateProviderError.invalidResponse(providerID)
        }
        guard records.count > 1 else {
            throw ExchangeRateProviderError.emptyTable(providerID)
        }

        var seen = Set<String>()
        var rows: [ValidatedRow] = []
        rows.reserveCapacity(records.count - 1)

        for fields in records.dropFirst() {
            guard fields.count == Self.descriptiveHeader.count else {
                throw ExchangeRateProviderError.invalidResponse(providerID)
            }
            let row = CSVRow(fields: fields)
            let normalized = try currencyCode(from: row.currency, providerID: providerID)
            guard row.key == "EXR.D.\(normalized).EUR.SP00.A",
                  rowFormat.matches(row)
            else {
                throw ExchangeRateProviderError.invalidResponse(providerID)
            }
            guard seen.insert(normalized).inserted else {
                throw ExchangeRateProviderError.duplicateQuote(providerID, normalized)
            }

            let date = try ExchangeRateProviderSupport.rateDate(
                row.timePeriod,
                providerID: providerID
            )
            guard let rate = Decimal(
                string: row.observationValue,
                locale: Locale(identifier: "en_US_POSIX")
            ), rate > 0 else {
                throw ExchangeRateProviderError.invalidRate(providerID, normalized)
            }
            let code = try ExchangeRateProviderSupport.currencyCode(
                normalized,
                providerID: providerID
            )
            rows.append(ValidatedRow(
                normalizedCode: normalized,
                code: code,
                quotePerEUR: rate,
                date: date
            ))
        }

        guard let usdRow = rows.first(where: {
            $0.normalizedCode == CurrencyCode.usd.rawValue
        }) else {
            throw ExchangeRateProviderError.invalidBase(providerID, "missing USD/EUR cross-rate")
        }
        guard let latestObservationDate = rows.map(\.date).max(),
              usdRow.date == latestObservationDate
        else {
            throw ExchangeRateProviderError.invalidBase(
                providerID,
                "USD/EUR cross-rate is not from the latest observation date"
            )
        }

        // The wildcard ECB query can include discontinued currencies whose
        // latest observation is old. The response's latest date, anchored by
        // USD, defines the one coherent daily table; older rows are valid source
        // history but not current rates.
        let currentRows = rows.filter { $0.date == latestObservationDate }
        var quotes: [ExchangeRateQuote] = []
        quotes.reserveCapacity(currentRows.count)

        for row in currentRows {
            if row.normalizedCode == CurrencyCode.usd.rawValue { continue }
            if row.normalizedCode == "EUR" {
                guard row.quotePerEUR == 1 else {
                    throw ExchangeRateProviderError.invalidRate(providerID, "EUR")
                }
                continue
            }
            guard let code = row.code else { continue }
            let usdRate = row.quotePerEUR / usdRow.quotePerEUR
            guard usdRate > 0 else {
                throw ExchangeRateProviderError.invalidRate(providerID, row.normalizedCode)
            }
            quotes.append(ExchangeRateQuote(
                quoteCode: code,
                rate: usdRate,
                rateDate: latestObservationDate
            ))
        }

        guard let eur = CurrencyCode("EUR") else {
            throw ExchangeRateProviderError.invalidQuote(providerID, "EUR")
        }
        quotes.append(ExchangeRateQuote(
            quoteCode: eur,
            rate: 1 / usdRow.quotePerEUR,
            rateDate: latestObservationDate
        ))

        return try ExchangeRateProviderSupport.validatedCompleteTable(
            quotes,
            providerID: providerID
        )
    }

    private func currencyCode(
        from describedCurrency: String,
        providerID: ExchangeRateProviderID
    ) throws -> String {
        guard describedCurrency.count >= 3 else {
            throw ExchangeRateProviderError.invalidQuote(providerID, describedCurrency)
        }
        let prefix = String(describedCurrency.prefix(3))
        let suffix = describedCurrency.dropFirst(3)
        guard suffix.isEmpty || (
            suffix.first == " "
                && suffix.dropFirst().first == "("
                && suffix.last == ")"
                && suffix.count > 3
        ) else {
            throw ExchangeRateProviderError.invalidQuote(providerID, describedCurrency)
        }
        return try ExchangeRateProviderSupport.normalizedCurrencyCode(
            prefix,
            providerID: providerID
        )
    }

    private struct CSVRow {
        let key: String
        let frequency: String
        let currency: String
        let currencyDenominator: String
        let exchangeRateType: String
        let seriesVariation: String
        let timePeriod: String
        let observationValue: String

        init(fields: [String]) {
            key = fields[0]
            frequency = fields[1]
            currency = fields[2]
            currencyDenominator = fields[3]
            exchangeRateType = fields[4]
            seriesVariation = fields[5]
            timePeriod = fields[6]
            observationValue = fields[7]
        }
    }

    private enum RowFormat {
        case descriptive
        case compact

        func matches(_ row: CSVRow) -> Bool {
            switch self {
            case .descriptive:
                return row.frequency == "D (Daily)"
                    && row.currencyDenominator == "EUR (Euro)"
                    && row.exchangeRateType == "SP00 (Spot)"
                    && row.seriesVariation == "A (Average)"
            case .compact:
                return row.frequency == "D"
                    && row.currency.count == 3
                    && row.currencyDenominator == "EUR"
                    && row.exchangeRateType == "SP00"
                    && row.seriesVariation == "A"
            }
        }
    }

    private struct ValidatedRow {
        let normalizedCode: String
        let code: CurrencyCode?
        let quotePerEUR: Decimal
        let date: Date
    }
}

nonisolated private enum StrictCSVParser {
    private enum CSVError: Error {
        case malformed
        case invalidEncoding
    }

    static func parse(_ data: Data) throws -> [[String]] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CSVError.invalidEncoding
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return try lines.map(parseLine)
    }

    private static func parseLine(_ line: String) throws -> [String] {
        let characters = Array(line)
        var fields: [String] = []
        var field = ""
        var index = 0
        var inQuotes = false
        var closedQuote = false

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    closedQuote = true
                } else {
                    field.append(character)
                }
                index += 1
                continue
            }

            if closedQuote {
                if character == "," {
                    fields.append(field)
                    field = ""
                    closedQuote = false
                } else {
                    throw CSVError.malformed
                }
                index += 1
                continue
            }

            switch character {
            case "\"":
                guard field.isEmpty else { throw CSVError.malformed }
                inQuotes = true
            case ",":
                fields.append(field)
                field = ""
            default:
                field.append(character)
            }
            index += 1
        }

        guard !inQuotes else { throw CSVError.malformed }
        fields.append(field)
        return fields
    }
}
