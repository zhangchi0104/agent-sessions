//
//  ExchangeRateAPIProvider.swift
//  TokenStats
//
//  Adapter for ExchangeRate-API's keyless Open Access USD table.
//

import Foundation

nonisolated struct ExchangeRateAPIProvider: ExchangeRateProviding {
    static let endpoint = ExchangeRateProviderID.exchangeRateAPI.descriptor.defaultEndpoint

    var session: URLSession = .shared

    func fetchRates(from source: ExchangeRateSource) async throws -> [ExchangeRateQuote] {
        let providerID = ExchangeRateProviderID.exchangeRateAPI
        let request = try ExchangeRateProviderSupport.request(
            for: source,
            expectedProviderID: providerID,
            accept: "application/json"
        )
        let data = try await ExchangeRateProviderSupport.responseData(
            for: request,
            providerID: providerID,
            session: session
        )

        do {
            if let duplicate = try JSONDuplicateKeyDetector.firstDuplicate(in: data) {
                if duplicate.objectPath == ["rates"] {
                    let normalized = try ExchangeRateProviderSupport.normalizedCurrencyCode(
                        duplicate.key,
                        providerID: providerID
                    )
                    throw ExchangeRateProviderError.duplicateQuote(providerID, normalized)
                }
                throw ExchangeRateProviderError.invalidResponse(providerID)
            }
        } catch let error as ExchangeRateProviderError {
            throw error
        } catch {
            throw ExchangeRateProviderError.invalidResponse(providerID)
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ExchangeRateProviderError.invalidResponse(providerID)
        }
        guard response.result == "success" else {
            throw ExchangeRateProviderError.invalidResponse(providerID)
        }

        let base = try ExchangeRateProviderSupport.normalizedCurrencyCode(
            response.baseCode,
            providerID: providerID
        )
        guard base == CurrencyCode.usd.rawValue else {
            throw ExchangeRateProviderError.invalidBase(providerID, response.baseCode)
        }
        let rateDate = try validatedRateDate(response, providerID: providerID)
        guard !response.rates.isEmpty else {
            throw ExchangeRateProviderError.emptyTable(providerID)
        }

        var seen = Set<String>()
        var sawUSDIdentity = false
        var quotes: [ExchangeRateQuote] = []
        quotes.reserveCapacity(response.rates.count)

        for (rawCode, rate) in response.rates {
            let normalized = try ExchangeRateProviderSupport.normalizedCurrencyCode(
                rawCode,
                providerID: providerID
            )
            guard seen.insert(normalized).inserted else {
                throw ExchangeRateProviderError.duplicateQuote(providerID, normalized)
            }
            guard rate > 0 else {
                throw ExchangeRateProviderError.invalidRate(providerID, normalized)
            }

            if normalized == CurrencyCode.usd.rawValue {
                guard rate == 1 else {
                    throw ExchangeRateProviderError.invalidRate(providerID, normalized)
                }
                sawUSDIdentity = true
                continue
            }

            guard let quoteCode = try ExchangeRateProviderSupport.currencyCode(
                normalized,
                providerID: providerID
            ) else { continue }
            quotes.append(ExchangeRateQuote(
                quoteCode: quoteCode,
                rate: rate,
                rateDate: rateDate
            ))
        }

        guard sawUSDIdentity else {
            throw ExchangeRateProviderError.invalidBase(providerID, "missing USD identity rate")
        }
        return try ExchangeRateProviderSupport.validatedCompleteTable(
            quotes,
            providerID: providerID
        )
    }

    private func validatedRateDate(
        _ response: Response,
        providerID: ExchangeRateProviderID
    ) throws -> Date {
        let last = response.timeLastUpdateUnix
        let next = response.timeNextUpdateUnix
        let endOfLife = response.timeEOLUnix
        guard last > 0,
              next > last,
              endOfLife >= 0,
              (endOfLife == 0 || endOfLife >= last)
        else {
            throw ExchangeRateProviderError.invalidDate(
                providerID,
                "\(last)/\(next)/\(endOfLife)"
            )
        }
        return Date(timeIntervalSince1970: TimeInterval(last))
    }

    private struct Response: Decodable {
        let result: String
        let timeLastUpdateUnix: Int64
        let timeNextUpdateUnix: Int64
        let timeEOLUnix: Int64
        let baseCode: String
        let rates: [String: Decimal]

        private enum CodingKeys: String, CodingKey {
            case result
            case timeLastUpdateUnix = "time_last_update_unix"
            case timeNextUpdateUnix = "time_next_update_unix"
            case timeEOLUnix = "time_eol_unix"
            case baseCode = "base_code"
            case rates
        }
    }
}

/// JSONDecoder intentionally follows JSON's common last-key-wins behavior.
/// A rates table must instead reject duplicate currency members, so scan the
/// JSON grammar first and report the first duplicate object key with its path.
nonisolated private struct JSONDuplicateKeyDetector {
    struct Duplicate {
        let objectPath: [String]
        let key: String
    }

    private enum ScanError: Error {
        case malformed
    }

    private let bytes: [UInt8]
    private var index = 0
    private var duplicate: Duplicate?

    static func firstDuplicate(in data: Data) throws -> Duplicate? {
        var detector = JSONDuplicateKeyDetector(bytes: Array(data))
        try detector.parseValue(path: [])
        detector.skipWhitespace()
        guard detector.index == detector.bytes.count else {
            throw ScanError.malformed
        }
        return detector.duplicate
    }

    private mutating func parseValue(path: [String]) throws {
        skipWhitespace()
        guard index < bytes.count else { throw ScanError.malformed }
        switch bytes[index] {
        case 0x7B: // {
            try parseObject(path: path)
        case 0x5B: // [
            try parseArray(path: path)
        case 0x22: // "
            _ = try parseString()
        default:
            try parsePrimitive()
        }
    }

    private mutating func parseObject(path: [String]) throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }

        var keys = Set<String>()
        while true {
            skipWhitespace()
            let key = try parseString()
            if !keys.insert(key).inserted, duplicate == nil {
                duplicate = Duplicate(objectPath: path, key: key)
            }
            skipWhitespace()
            guard consume(0x3A) else { throw ScanError.malformed } // :
            try parseValue(path: path + [key])
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw ScanError.malformed } // ,
        }
    }

    private mutating func parseArray(path: [String]) throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }
        while true {
            try parseValue(path: path)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw ScanError.malformed }
        }
    }

    private mutating func parseString() throws -> String {
        guard index < bytes.count, bytes[index] == 0x22 else {
            throw ScanError.malformed
        }
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 {
                index += 1
                let encoded = Data(bytes[start..<index])
                guard let value = try? JSONDecoder().decode(String.self, from: encoded) else {
                    throw ScanError.malformed
                }
                return value
            }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else { throw ScanError.malformed }
            } else if byte < 0x20 {
                throw ScanError.malformed
            }
            index += 1
        }
        throw ScanError.malformed
    }

    private mutating func parsePrimitive() throws {
        let start = index
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D:
                guard index > start else { throw ScanError.malformed }
                return
            default:
                index += 1
            }
        }
        guard index > start else { throw ScanError.malformed }
    }

    private mutating func skipWhitespace() {
        while index < bytes.count,
              bytes[index] == 0x20 || bytes[index] == 0x09
                || bytes[index] == 0x0A || bytes[index] == 0x0D {
            index += 1
        }
    }

    private mutating func consume(_ expected: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == expected else { return false }
        index += 1
        return true
    }
}
