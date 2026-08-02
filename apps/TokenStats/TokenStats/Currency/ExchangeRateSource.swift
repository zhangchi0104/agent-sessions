//
//  ExchangeRateSource.swift
//  TokenStats
//
//  User-selectable exchange-rate sources. A source chooses a known response
//  adapter plus one HTTPS endpoint that must continue to speak that adapter's
//  schema. Endpoints never contain credentials.
//

import Foundation

nonisolated enum ExchangeRateProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case frankfurter
    case exchangeRateAPI
    case ecb

    var id: String { rawValue }

    var descriptor: ExchangeRateProviderDescriptor {
        switch self {
        case .frankfurter:
            ExchangeRateProviderDescriptor(
                id: self,
                displayName: "Frankfurter",
                defaultEndpoint: URL(
                    string: "https://api.frankfurter.dev/v2/rates?base=USD"
                )!,
                attributionTitle: "Frankfurter",
                attributionURL: URL(string: "https://frankfurter.dev/")!,
                documentationURL: URL(string: "https://frankfurter.dev/")!,
                explanation: "Broad daily reference-rate coverage from multiple public providers.",
                minimumUsableQuoteCount: 50
            )
        case .exchangeRateAPI:
            ExchangeRateProviderDescriptor(
                id: self,
                displayName: "ExchangeRate-API Open",
                defaultEndpoint: URL(string: "https://open.er-api.com/v6/latest/USD")!,
                attributionTitle: "Rates By Exchange Rate API",
                attributionURL: URL(string: "https://www.exchangerate-api.com/")!,
                documentationURL: URL(string: "https://www.exchangerate-api.com/docs/free")!,
                explanation: "A keyless daily USD table; attribution is required by the service.",
                minimumUsableQuoteCount: 50
            )
        case .ecb:
            ExchangeRateProviderDescriptor(
                id: self,
                displayName: "European Central Bank",
                defaultEndpoint: URL(
                    string: "https://data-api.ecb.europa.eu/service/data/EXR/"
                        + "D..EUR.SP00.A?lastNObservations=1&detail=dataonly&format=csvdata"
                )!,
                attributionTitle: "Source: ECB statistics",
                attributionURL: URL(
                    string: "https://data.ecb.europa.eu/key-figures/"
                        + "ecb-interest-rates-and-exchange-rates/exchange-rates"
                )!,
                documentationURL: URL(string: "https://data.ecb.europa.eu/help/api/data")!,
                explanation: "Official EUR reference rates converted once into USD cross-rates; "
                    + "coverage is limited to currencies published for the latest ECB date.",
                minimumUsableQuoteCount: 20
            )
        }
    }
}

nonisolated struct ExchangeRateProviderDescriptor: Identifiable, Equatable, Sendable {
    let id: ExchangeRateProviderID
    let displayName: String
    let defaultEndpoint: URL
    let attributionTitle: String
    let attributionURL: URL
    let documentationURL: URL
    let explanation: String
    let minimumUsableQuoteCount: Int
}

nonisolated struct ExchangeRateSource: Codable, Equatable, Sendable {
    let providerID: ExchangeRateProviderID
    let endpoint: URL

    static let `default` = ExchangeRateSource(
        providerID: .frankfurter,
        endpoint: ExchangeRateProviderID.frankfurter.descriptor.defaultEndpoint
    )

    init(providerID: ExchangeRateProviderID, endpoint: URL) {
        self.providerID = providerID
        self.endpoint = endpoint
    }

    static func validated(
        providerID: ExchangeRateProviderID,
        endpointText: String
    ) throws -> ExchangeRateSource {
        let trimmed = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExchangeRateSourceError.emptyEndpoint }
        guard trimmed.utf8.count <= 2_048 else {
            throw ExchangeRateSourceError.endpointTooLong
        }
        guard var components = URLComponents(string: trimmed) else {
            throw ExchangeRateSourceError.invalidEndpoint
        }
        guard components.scheme?.lowercased() == "https" else {
            throw ExchangeRateSourceError.httpsRequired
        }
        guard let host = components.host, !host.isEmpty else {
            throw ExchangeRateSourceError.missingHost
        }
        var canonicalHost = host.lowercased()
        while canonicalHost.hasSuffix(".") {
            canonicalHost.removeLast()
        }
        guard !canonicalHost.isEmpty else {
            throw ExchangeRateSourceError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw ExchangeRateSourceError.credentialsNotAllowed
        }
        guard components.fragment == nil else {
            throw ExchangeRateSourceError.fragmentNotAllowed
        }
        let credentialQueryNames: Set<String> = [
            "access-key", "access-token", "access_key", "access_token", "api-key",
            "api_key", "apikey", "app_id", "auth", "auth_token", "authorization",
            "client-secret", "client_secret", "credential", "key", "password", "secret",
            "token",
        ]
        guard !(components.queryItems ?? []).contains(where: {
            credentialQueryNames.contains($0.name.lowercased())
        }) else {
            throw ExchangeRateSourceError.credentialsNotAllowed
        }

        let credentialPathNames = credentialQueryNames.subtracting(["app_id", "authorization"])
        let pathSegments = components.path.split(separator: "/").map {
            $0.removingPercentEncoding?.lowercased() ?? $0.lowercased()
        }
        guard !pathSegments.contains(where: credentialPathNames.contains) else {
            throw ExchangeRateSourceError.credentialsNotAllowed
        }
        // ExchangeRate-API's paid service places the API key directly in the
        // path on this host. The supported Open Access service is keyless and
        // uses open.er-api.com instead.
        if canonicalHost == "v6.exchangerate-api.com" {
            throw ExchangeRateSourceError.credentialsNotAllowed
        }

        components.scheme = "https"
        components.host = canonicalHost
        guard let endpoint = components.url else {
            throw ExchangeRateSourceError.invalidEndpoint
        }
        return ExchangeRateSource(providerID: providerID, endpoint: endpoint)
    }

    var isValid: Bool {
        (try? Self.validated(
            providerID: providerID,
            endpointText: endpoint.absoluteString
        )) == self
    }
}

nonisolated enum ExchangeRateSourceError: Error, Equatable, LocalizedError {
    case emptyEndpoint
    case endpointTooLong
    case invalidEndpoint
    case httpsRequired
    case missingHost
    case credentialsNotAllowed
    case fragmentNotAllowed

    var errorDescription: String? {
        switch self {
        case .emptyEndpoint:
            "Enter an exchange-rate API URL."
        case .endpointTooLong:
            "The exchange-rate API URL is too long."
        case .invalidEndpoint:
            "Enter a valid absolute exchange-rate API URL."
        case .httpsRequired:
            "Exchange-rate API URLs must use HTTPS."
        case .missingHost:
            "The exchange-rate API URL must include a host."
        case .credentialsNotAllowed:
            "Do not put usernames, passwords, or API keys in the URL."
        case .fragmentNotAllowed:
            "Exchange-rate API URLs cannot contain a fragment."
        }
    }
}

nonisolated struct ExchangeRateSourcePreferences: Codable, Equatable, Sendable {
    var selectedProviderID: ExchangeRateProviderID
    private(set) var endpointOverrides: [String: String]

    static let `default` = ExchangeRateSourcePreferences(
        selectedProviderID: .frankfurter,
        endpointOverrides: [:]
    )

    init(
        selectedProviderID: ExchangeRateProviderID,
        endpointOverrides: [String: String]
    ) {
        self.selectedProviderID = selectedProviderID
        self.endpointOverrides = endpointOverrides
    }

    var activeSource: ExchangeRateSource {
        source(for: selectedProviderID)
    }

    func source(for providerID: ExchangeRateProviderID) -> ExchangeRateSource {
        if let override = endpointOverrides[providerID.rawValue],
           let source = try? ExchangeRateSource.validated(
               providerID: providerID,
               endpointText: override
           ) {
            return source
        }
        return ExchangeRateSource(
            providerID: providerID,
            endpoint: providerID.descriptor.defaultEndpoint
        )
    }

    mutating func activate(_ source: ExchangeRateSource) {
        selectedProviderID = source.providerID
        let defaultEndpoint = source.providerID.descriptor.defaultEndpoint
        if source.endpoint == defaultEndpoint {
            endpointOverrides.removeValue(forKey: source.providerID.rawValue)
        } else {
            endpointOverrides[source.providerID.rawValue] = source.endpoint.absoluteString
        }
    }

    func sanitized() -> ExchangeRateSourcePreferences {
        var validOverrides: [String: String] = [:]
        for providerID in ExchangeRateProviderID.allCases {
            guard let value = endpointOverrides[providerID.rawValue],
                  let source = try? ExchangeRateSource.validated(
                      providerID: providerID,
                      endpointText: value
                  )
            else { continue }
            if source.endpoint != providerID.descriptor.defaultEndpoint {
                validOverrides[providerID.rawValue] = source.endpoint.absoluteString
            }
        }
        return ExchangeRateSourcePreferences(
            selectedProviderID: selectedProviderID,
            endpointOverrides: validOverrides
        )
    }
}
