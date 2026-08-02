//
//  TokensPane.swift
//  TokenStats
//
//  Settings → Tokens: configure Token Odometer presentation and the currency
//  used to display the USD-based API-equivalent estimate.
//

import SwiftUI

struct TokensPane: View {
    @Bindable var appearance: AppearanceSettings
    @Bindable var currencyModel: CurrencyModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var isChoosingCurrency = false
    @State private var isConfiguringRateSource = false
    @State private var isShowingRateDetails = false

    var body: some View {
        Form {
            Section {
                Picker("Tokens summary", selection: $appearance.tokenSummaryMetric) {
                    ForEach(TokenSummaryMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Tokens summary")
            } footer: {
                Text("Billing tokens count direct input, cache writes, and output. "
                     + "API equivalent estimates standard list-price cost from the "
                     + "Models recorded in local transcripts. Token Kind filters "
                     + "change neither summary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            currencySection

            Section {
                Picker("Token values", selection: $appearance.tokenValueDisplay) {
                    ForEach(TokenValueDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Token values")
            } footer: {
                Text("Enabled Token Kinds use this format. Disabled kinds keep "
                     + "a dimmed raw value and are excluded from composition percentages.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tokens")
        .sheet(isPresented: $isChoosingCurrency) {
            CurrencyPickerSheet(currencyModel: currencyModel)
        }
        .sheet(isPresented: $isConfiguringRateSource) {
            ExchangeRateSourceSheet(currencyModel: currencyModel)
        }
    }

    private var currencySection: some View {
        let context = currencyModel.displayContext
        return Section {
            LabeledContent("Display currency") {
                Button {
                    isChoosingCurrency = true
                } label: {
                    HStack(spacing: 6) {
                        Text(selectionLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .help("Choose the currency used for API-equivalent estimates")
                .accessibilityLabel("Display currency, \(selectionLabel)")
            }

            CurrencyPreview(context: context)
                .id("\(context.requestedCode.rawValue)-\(context.currencyCode.rawValue)")
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.25),
                    value: context.requestedCode
                )

            DisclosureGroup(isExpanded: $isShowingRateDetails) {
                rateDetails(context)
                    .padding(.top, 8)
            } label: {
                rateDetailsLabel(context)
            }
            .accessibilityHint(
                isShowingRateDetails
                    ? "Collapse exchange-rate details"
                    : "Expand exchange-rate details"
            )
        } header: {
            Text("API-equivalent currency")
        }
    }

    @ViewBuilder
    private func rateDetails(_ context: CurrencyDisplayContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Reference rate") {
                Text(referenceRateText(context))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }

            if let quoteDate = context.rateDate {
                LabeledContent("Rate date") {
                    Text(CurrencyAmountFormatting.rateDateText(quoteDate, locale: locale))
                }
            }

            if let fetchedAt = context.fetchedAt {
                LabeledContent("Fetched") {
                    Text(fetchedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let nextRefresh = currencyModel.nextAutomaticRefreshAt {
                LabeledContent("Next eligible refresh") {
                    Text(nextRefresh.formatted(date: .abbreviated, time: .shortened))
                }
            }

            LabeledContent("Rate provider") {
                Button {
                    isConfiguringRateSource = true
                } label: {
                    HStack(spacing: 6) {
                        Text(activeSourceDescriptor.displayName)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Change the exchange-rate provider or API endpoint")
                .accessibilityLabel(
                    "Rate provider, \(activeSourceDescriptor.displayName). Change provider or endpoint"
                )
            }

            LabeledContent("API endpoint") {
                Button {
                    isConfiguringRateSource = true
                } label: {
                    HStack(spacing: 6) {
                        Text(activeEndpointHost)
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(currencyModel.activeSource.endpoint.absoluteString)
                .accessibilityLabel(
                    "Exchange-rate API host, \(activeEndpointHost). Full endpoint, "
                        + currencyModel.activeSource.endpoint.absoluteString
                        + ". Change provider or endpoint."
                )
            }

            LabeledContent("Attribution") {
                Link(
                    activeSourceDescriptor.attributionTitle,
                    destination: activeSourceDescriptor.attributionURL
                )
            }

            Text(activeSourceDescriptor.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            currencyStatus(context)

            HStack {
                Spacer()
                refreshButton
            }

            Text("Official Model prices remain in USD. TokenStats downloads a complete "
                 + "USD reference-rate table from the selected provider automatically at "
                 + "most once every 24 hours. Retrying after an error sends one additional request.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rateDetailsLabel(_ context: CurrencyDisplayContext) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Exchange rate details")
            if currencyModel.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating rates…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                let status = rateDetailsStatus(context)
                Label(status.text, systemImage: status.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
    }

    @ViewBuilder
    private func currencyStatus(_ context: CurrencyDisplayContext) -> some View {
        if currencyModel.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(currencyModel.snapshot == nil
                     ? "Loading exchange rates…"
                     : "Refreshing rates; the last known rate remains in use.")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let lastError = currencyModel.lastError {
            Label(lastError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            Text(currencyModel.snapshot == nil
                ? "Retry now to request rates again. This sends one additional request "
                   + "before the next scheduled update."
                 : "The last known rate remains in use. Retry now to request rates "
                   + "again; this sends one additional request before the next scheduled update.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if currencyModel.isSnapshotStale {
                Label("The cached exchange rate may be out of date.", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }

            if context.isFallback {
                Label(
                    "\(context.requestedCode.rawValue) is unavailable; showing USD fallback.",
                    systemImage: "arrow.uturn.backward.circle"
                )
                .foregroundStyle(.secondary)
            }
        } else if context.isFallback {
            Label(
                "\(context.requestedCode.rawValue) is unavailable; showing USD.",
                systemImage: "arrow.uturn.backward.circle"
            )
            .foregroundStyle(.secondary)
        } else if currencyModel.isSnapshotStale {
            Label("Using the last known reference rate.", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        } else if currencyModel.snapshot == nil {
            Label(
                "No exchange rates are cached yet. Refresh rates to load more currencies.",
                systemImage: "arrow.clockwise.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if currencyModel.isRefreshing {
            Button("Updating…") {}
                .disabled(true)
                .accessibilityLabel("Exchange rates are updating")
        } else if currencyModel.canRetry {
            Button {
                Task { await currencyModel.retryNow() }
            } label: {
                Label("Retry now", systemImage: "arrow.clockwise")
            }
            .help("Retry now, even if the normal daily refresh is not yet eligible")
        } else if currencyModel.isEligible {
            Button {
                Task { await currencyModel.refreshIfEligible() }
            } label: {
                Label("Refresh rates", systemImage: "arrow.clockwise")
            }
        } else {
            Button {
            } label: {
                Label("Updated", systemImage: "checkmark")
            }
            .disabled(true)
            .accessibilityLabel("Exchange rates are up to date")
        }
    }

    private var selectionLabel: String {
        switch currencyModel.selection {
        case .system:
            let code = systemCurrencyCode
            return "System Region — \(currencyName(code)) (\(code.rawValue))"
        case .fixed(let code):
            return "\(currencyName(code)) (\(code.rawValue))"
        }
    }

    private var systemCurrencyCode: CurrencyCode {
        let identifier = Locale.autoupdatingCurrent.currency?.identifier ?? CurrencyCode.usd.rawValue
        return CurrencyCode(identifier) ?? .usd
    }

    private func referenceRateText(_ context: CurrencyDisplayContext) -> String {
        guard !context.isFallback else {
            return "\(context.requestedCode.rawValue) rate unavailable — USD fallback"
        }
        return "1 USD = \(decimalText(context.rate, maximumFractionDigits: 6)) "
            + context.currencyCode.rawValue
    }

    private func decimalText(_ value: Decimal, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func currencyName(_ code: CurrencyCode) -> String {
        Locale.autoupdatingCurrent.localizedString(forCurrencyCode: code.rawValue)
            ?? code.rawValue
    }

    private var activeSourceDescriptor: ExchangeRateProviderDescriptor {
        currencyModel.availableSourceDescriptors.first {
            $0.id == currencyModel.activeSource.providerID
        } ?? currencyModel.activeSource.providerID.descriptor
    }

    private var activeEndpointHost: String {
        currencyModel.activeSource.endpoint.host
            ?? currencyModel.activeSource.endpoint.absoluteString
    }

    private func rateDetailsStatus(
        _ context: CurrencyDisplayContext
    ) -> (text: String, systemImage: String, color: Color) {
        if currencyModel.lastError != nil {
            return (
                currencyModel.snapshot == nil
                    ? "Update failed · no rates cached"
                    : "Update failed · last known rates retained",
                "exclamationmark.triangle.fill",
                .orange
            )
        }
        if context.isFallback {
            return (
                "\(context.requestedCode.rawValue) unavailable · USD fallback",
                "arrow.uturn.backward.circle",
                .orange
            )
        }
        if currencyModel.isSnapshotStale {
            return ("Cached rate may be out of date", "clock.arrow.circlepath", .secondary)
        }
        if currencyModel.snapshot == nil {
            return ("No exchange rates cached", "tray", .secondary)
        }
        return ("Up to date · \(activeSourceDescriptor.displayName)", "checkmark.circle.fill", .green)
    }
}

private struct CurrencyPreview: View {
    let context: CurrencyDisplayContext

    private let exampleUSD = Decimal(10)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(previewText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewAccessibilityLabel)
    }

    private var previewText: String {
        if context.isFallback {
            return "US$10.00 — not converted"
        }
        if isNativeUSD {
            return "US$10.00 — no conversion"
        }
        return "US$10.00  ≈  \(convertedText)"
    }

    private var previewAccessibilityLabel: String {
        if context.isFallback {
            return "No usable \(context.requestedCode.rawValue) exchange rate; "
                + "ten US dollars is shown without conversion"
        }
        if isNativeUSD {
            return "Ten US dollars; no currency conversion is needed"
        }
        return "Ten US dollars is approximately \(convertedText)"
    }

    private var convertedText: String {
        context.amount(forUSD: exampleUSD).formatted()
    }

    private var isNativeUSD: Bool {
        context.requestedCode == .usd && context.currencyCode == .usd
    }
}

private struct CurrencyPickerSheet: View {
    @Bindable var currencyModel: CurrencyModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Display Currency")
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 20)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("Search currencies", text: $query)
                        .textFieldStyle(.plain)
                        .lineLimit(1)

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear currency search")
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 220, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityElement(children: .contain)

                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            List {
                if !filteredPopularCurrencies.isEmpty {
                    Section("Popular") {
                        ForEach(filteredPopularCurrencies, id: \.rawValue) { code in
                            currencyRow(
                                selection: .fixed(code),
                                code: code,
                                title: currencyName(code),
                                subtitle: code.rawValue
                            )
                        }
                    }
                }

                if automaticMatchesQuery {
                    Section {
                        currencyRow(
                            selection: .system,
                            code: systemCurrencyCode,
                            title: "System Region",
                            subtitle: "\(currencyName(systemCurrencyCode)) "
                                + "(\(systemCurrencyCode.rawValue))"
                        )
                    } header: {
                        Text("Automatic")
                    } footer: {
                        if currencyModel.snapshot == nil {
                            Text("No rates are cached yet. Close this list and choose Refresh rates "
                                 + "to load the \(activeProviderName) currency table.")
                        }
                    }
                }

                if !filteredGeneralCurrencies.isEmpty {
                    Section("All Currencies") {
                        ForEach(filteredGeneralCurrencies, id: \.rawValue) { code in
                            currencyRow(
                                selection: .fixed(code),
                                code: code,
                                title: currencyName(code),
                                subtitle: code.rawValue
                            )
                        }
                    }
                }

                if hasNoSearchResults {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 500, idealHeight: 520)
    }

    private var allCurrencies: [CurrencyCode] {
        var byCode: [String: CurrencyCode] = [:]
        for code in currencyModel.availableCurrencies {
            byCode[code.rawValue] = code
        }
        byCode[CurrencyCode.usd.rawValue] = .usd
        return byCode.values.sorted {
            let left = currencyName($0)
            let right = currencyName($1)
            let comparison = left.localizedStandardCompare(right)
            return comparison == .orderedSame ? $0.rawValue < $1.rawValue : comparison == .orderedAscending
        }
    }

    private static let popularCurrencyOrder = ["USD", "CNY", "JPY", "EUR", "GBP", "KRW"]

    private var popularCurrencies: [CurrencyCode] {
        let availableByCode = Dictionary(
            uniqueKeysWithValues: allCurrencies.map { ($0.rawValue, $0) }
        )
        return Self.popularCurrencyOrder.compactMap { availableByCode[$0] }
    }

    private var generalCurrencies: [CurrencyCode] {
        let popular = Set(popularCurrencies)
        return allCurrencies.filter { !popular.contains($0) }
    }

    private var filteredPopularCurrencies: [CurrencyCode] {
        popularCurrencies.filter(matchesQuery)
    }

    private var filteredGeneralCurrencies: [CurrencyCode] {
        generalCurrencies.filter(matchesQuery)
    }

    private var hasNoSearchResults: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !automaticMatchesQuery
            && filteredPopularCurrencies.isEmpty
            && filteredGeneralCurrencies.isEmpty
    }

    private var automaticMatchesQuery: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return "System Region".localizedCaseInsensitiveContains(trimmed)
            || systemCurrencyCode.rawValue.localizedCaseInsensitiveContains(trimmed)
            || currencyName(systemCurrencyCode).localizedCaseInsensitiveContains(trimmed)
            || currencySymbol(systemCurrencyCode).localizedCaseInsensitiveContains(trimmed)
    }

    private func matchesQuery(_ code: CurrencyCode) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return code.rawValue.localizedCaseInsensitiveContains(trimmed)
            || currencyName(code).localizedCaseInsensitiveContains(trimmed)
            || currencySymbol(code).localizedCaseInsensitiveContains(trimmed)
    }

    @ViewBuilder
    private func currencyRow(
        selection: DisplayCurrencySelection,
        code: CurrencyCode,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = currencyModel.selection == selection
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                currencyModel.selection = selection
            }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(currencySymbol(code))
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var systemCurrencyCode: CurrencyCode {
        currencyModel.systemCurrencyCode
    }

    private func currencyName(_ code: CurrencyCode) -> String {
        Locale.autoupdatingCurrent.localizedString(forCurrencyCode: code.rawValue)
            ?? code.rawValue
    }

    private func currencySymbol(_ code: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .currency
        formatter.currencyCode = code.rawValue
        return formatter.currencySymbol ?? code.rawValue
    }

    private var activeProviderName: String {
        currencyModel.availableSourceDescriptors.first {
            $0.id == currencyModel.activeSource.providerID
        }?.displayName ?? currencyModel.activeSource.providerID.rawValue
    }
}

private struct ExchangeRateSourceSheet: View {
    @Bindable var currencyModel: CurrencyModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProviderID: ExchangeRateProviderID
    @State private var endpointText: String

    init(currencyModel: CurrencyModel) {
        self.currencyModel = currencyModel
        let source = currencyModel.activeSource
        _selectedProviderID = State(initialValue: source.providerID)
        _endpointText = State(initialValue: source.endpoint.absoluteString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedProviderID) {
                        ForEach(currencyModel.availableSourceDescriptors) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.id)
                        }
                    }

                    Text(selectedDescriptor.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledContent("Attribution") {
                        Link(
                            selectedDescriptor.attributionTitle,
                            destination: selectedDescriptor.attributionURL
                        )
                    }

                    LabeledContent("Documentation") {
                        Link("Open API documentation", destination: selectedDescriptor.documentationURL)
                    }
                } header: {
                    Text("Rate provider")
                }

                Section {
                    TextField("Full HTTPS API URL", text: $endpointText)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .disabled(currencyModel.isValidatingSource)
                        .accessibilityLabel("Exchange-rate API endpoint")

                    HStack {
                        Text("Use a public, keyless endpoint compatible with this provider. "
                             + "Do not include credentials or API keys in the URL.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button("Restore Default") {
                            endpointText = selectedDescriptor.defaultEndpoint.absoluteString
                            currencyModel.clearSourceValidationError()
                        }
                        .disabled(
                            currencyModel.isValidatingSource
                                || endpointText == selectedDescriptor.defaultEndpoint.absoluteString
                        )
                    }
                } header: {
                    Text("HTTPS endpoint")
                } footer: {
                    Text("TokenStats verifies the endpoint before switching. It contacts only "
                         + "the selected endpoint and never fails over to another service.")
                }

                if let validationError = currencyModel.sourceValidationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Could not use rate provider. \(validationError)")
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(currencyModel.isValidatingSource)
            .navigationTitle("Exchange Rate Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        currencyModel.clearSourceValidationError()
                        dismiss()
                    }
                    .disabled(currencyModel.isValidatingSource)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let activated = await currencyModel.validateAndActivateSource(
                                providerID: selectedProviderID,
                                endpointText: endpointText
                            )
                            if activated {
                                dismiss()
                            }
                        }
                    } label: {
                        if currencyModel.isValidatingSource {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Verifying…")
                            }
                        } else {
                            Text("Verify & Use")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        currencyModel.isValidatingSource
                            || endpointText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityLabel(
                        currencyModel.isValidatingSource
                            ? "Verifying exchange-rate source"
                            : "Verify and use exchange-rate source"
                    )
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 430, idealHeight: 470)
        .interactiveDismissDisabled(currencyModel.isValidatingSource)
        .onAppear {
            syncFromActiveSource()
        }
        .onChange(of: selectedProviderID) { _, providerID in
            endpointText = currencyModel.configuredSource(for: providerID).endpoint.absoluteString
            currencyModel.clearSourceValidationError()
        }
        .onChange(of: endpointText) {
            currencyModel.clearSourceValidationError()
        }
        .onDisappear {
            currencyModel.clearSourceValidationError()
        }
    }

    private var selectedDescriptor: ExchangeRateProviderDescriptor {
        currencyModel.availableSourceDescriptors.first { $0.id == selectedProviderID }
            ?? selectedProviderID.descriptor
    }

    private func syncFromActiveSource() {
        let source = currencyModel.activeSource
        selectedProviderID = source.providerID
        endpointText = source.endpoint.absoluteString
        currencyModel.clearSourceValidationError()
    }
}
