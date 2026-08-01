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

            LabeledContent("Source") {
                Link("Frankfurter", destination: Self.frankfurterURL)
            }

            currencyStatus(context)

            HStack {
                Spacer()
                refreshButton
            }
        } header: {
            Text("API-equivalent currency")
        } footer: {
            Text("Official Model prices remain in USD. TokenStats downloads the complete "
                 + "USD reference-rate table automatically at most once every 24 hours. "
                 + "Retrying after an error sends one additional request.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

            if context.isStale {
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
        } else if context.isStale {
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

    private static let frankfurterURL = URL(string: "https://frankfurter.dev")!
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
        context.isFallback
            ? "US$10.00 — not converted"
            : "US$10.00  ≈  \(convertedText)"
    }

    private var previewAccessibilityLabel: String {
        context.isFallback
            ? "No usable \(context.requestedCode.rawValue) exchange rate; "
                + "ten US dollars is shown without conversion"
            : "Ten US dollars is approximately \(convertedText)"
    }

    private var convertedText: String {
        context.amount(forUSD: exampleUSD).formatted()
    }
}

private struct CurrencyPickerSheet: View {
    @Bindable var currencyModel: CurrencyModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Automatic") {
                    currencyRow(
                        selection: .system,
                        code: systemCurrencyCode,
                        title: "System Region",
                        subtitle: "\(currencyName(systemCurrencyCode)) "
                            + "(\(systemCurrencyCode.rawValue))"
                    )
                }

                Section {
                    ForEach(filteredCurrencies, id: \.rawValue) { code in
                        currencyRow(
                            selection: .fixed(code),
                            code: code,
                            title: currencyName(code),
                            subtitle: code.rawValue
                        )
                    }
                } header: {
                    Text("Currencies")
                } footer: {
                    if currencyModel.snapshot == nil {
                        Text("No rates are cached yet. Close this list and choose Refresh rates "
                             + "to load the Frankfurter currency table.")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search currencies")
            .navigationTitle("Choose Currency")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 440, minHeight: 500, idealHeight: 500)
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

    private var filteredCurrencies: [CurrencyCode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allCurrencies }
        return allCurrencies.filter { code in
            code.rawValue.localizedCaseInsensitiveContains(trimmed)
                || currencyName(code).localizedCaseInsensitiveContains(trimmed)
                || currencySymbol(code).localizedCaseInsensitiveContains(trimmed)
        }
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
}
