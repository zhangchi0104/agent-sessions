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
            currencySection

            Section {
                Picker(selection: $appearance.tokenValueDisplay) {
                    ForEach(TokenValueDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text(TokensSettingsCopy.tokenValuesTitle)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text(TokensSettingsCopy.tokenValuesTitle)
            } footer: {
                Text(TokensSettingsCopy.tokenValuesFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(TokensSettingsCopy.title))
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
            LabeledContent {
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
                .help(Text(TokensSettingsCopy.displayCurrencyHelp))
                .accessibilityLabel(Text(
                    TokensSettingsCopy.displayCurrencyAccessibilityLabel(selectionLabel)
                ))
            } label: {
                Text(TokensSettingsCopy.displayCurrencyLabel)
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
            .accessibilityHint(Text(
                isShowingRateDetails
                    ? TokensSettingsCopy.rateDetailsCollapseAccessibilityHint
                    : TokensSettingsCopy.rateDetailsExpandAccessibilityHint
            ))
        } header: {
            Text(TokensSettingsCopy.currencySectionTitle)
        }
    }

    @ViewBuilder
    private func rateDetails(_ context: CurrencyDisplayContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                Text(referenceRateText(context))
                    .monospacedDigit()
                    .textSelection(.enabled)
            } label: {
                Text(TokensSettingsCopy.referenceRateLabel)
            }

            if let quoteDate = context.rateDate {
                LabeledContent {
                    Text(CurrencyAmountFormatting.rateDateText(quoteDate, locale: locale))
                } label: {
                    Text(TokensSettingsCopy.rateDateLabel)
                }
            }

            if let fetchedAt = context.fetchedAt {
                LabeledContent {
                    Text(dateTimeText(fetchedAt))
                } label: {
                    Text(TokensSettingsCopy.fetchedLabel)
                }
            }

            if let nextRefresh = currencyModel.nextAutomaticRefreshAt {
                LabeledContent {
                    Text(dateTimeText(nextRefresh))
                } label: {
                    Text(TokensSettingsCopy.nextEligibleRefreshLabel)
                }
            }

            LabeledContent {
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
                .help(Text(TokensSettingsCopy.changeProviderHelp))
                .accessibilityLabel(Text(
                    TokensSettingsCopy.changeProviderAccessibilityLabel(
                        activeSourceDescriptor.displayName
                    )
                ))
            } label: {
                Text(TokensSettingsCopy.rateProviderLabel)
            }

            LabeledContent {
                Button {
                    isConfiguringRateSource = true
                } label: {
                    HStack(spacing: 6) {
                        Text(currencyModel.activeSource.endpoint.absoluteString)
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(currencyModel.activeSource.endpoint.absoluteString)
                .accessibilityLabel(Text(
                    TokensSettingsCopy.changeEndpointAccessibilityLabel(
                        currencyModel.activeSource.endpoint.absoluteString
                    )
                ))
            } label: {
                Text(TokensSettingsCopy.apiEndpointLabel)
            }

            LabeledContent {
                Link(
                    activeSourceDescriptor.attributionTitle,
                    destination: activeSourceDescriptor.attributionURL
                )
            } label: {
                Text(TokensSettingsCopy.attributionLabel)
            }

            Text(activeSourceDescriptor.id.settingsExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            currencyStatus(context)

            HStack {
                Spacer()
                refreshButton
            }

            Text(TokensSettingsCopy.rateRequestPolicy)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rateDetailsLabel(_ context: CurrencyDisplayContext) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(TokensSettingsCopy.rateDetailsTitle)
            if currencyModel.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(TokensSettingsCopy.updatingRates)
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
                     ? TokensSettingsCopy.loadingRates
                     : TokensSettingsCopy.refreshingRatesWithLastKnown)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let lastError = currencyModel.lastError {
            Label(lastError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            Text(currencyModel.snapshot == nil
                 ? TokensSettingsCopy.retryExplanationWithoutCache
                 : TokensSettingsCopy.retryExplanationWithCache)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if currencyModel.isSnapshotStale {
                Label {
                    Text(TokensSettingsCopy.staleRateWarning)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                    .foregroundStyle(.secondary)
            }

            if context.isFallback {
                Label {
                    Text(TokensSettingsCopy.fallbackWarning(context.requestedCode.rawValue))
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .foregroundStyle(.secondary)
            }
        } else if context.isFallback {
            Label {
                Text(TokensSettingsCopy.unavailableCurrencyWarning(
                    context.requestedCode.rawValue
                ))
            } icon: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .foregroundStyle(.secondary)
        } else if currencyModel.isSnapshotStale {
            Label {
                Text(TokensSettingsCopy.usingLastKnownRate)
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
                .foregroundStyle(.secondary)
        } else if currencyModel.snapshot == nil {
            Label {
                Text(TokensSettingsCopy.noRatesCachedInstruction)
            } icon: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if currencyModel.isRefreshing {
            Button {} label: {
                Text(TokensSettingsCopy.updatingButton)
            }
                .disabled(true)
                .accessibilityLabel(Text(TokensSettingsCopy.updatingAccessibilityLabel))
        } else if currencyModel.canRetry {
            Button {
                Task { await currencyModel.retryNow() }
            } label: {
                Label {
                    Text(TokensSettingsCopy.retryNowButton)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help(Text(TokensSettingsCopy.retryNowHelp))
        } else if currencyModel.isEligible {
            Button {
                Task { await currencyModel.refreshIfEligible() }
            } label: {
                Label {
                    Text(TokensSettingsCopy.refreshRatesButton)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } else {
            Button {
            } label: {
                Label {
                    Text(TokensSettingsCopy.updatedButton)
                } icon: {
                    Image(systemName: "checkmark")
                }
            }
            .disabled(true)
            .accessibilityLabel(Text(TokensSettingsCopy.updatedAccessibilityLabel))
        }
    }

    private func dateTimeText(_ date: Date) -> String {
        Date.FormatStyle()
            .year()
            .month()
            .day()
            .hour()
            .minute()
            .locale(locale)
            .format(date)
    }

    private var selectionLabel: String {
        switch currencyModel.selection {
        case .system:
            let code = systemCurrencyCode
            return localized(TokensSettingsCopy.systemRegionSelectionLabel(
                currencyName(code),
                code.rawValue
            ))
        case .fixed(let code):
            return localized(TokensSettingsCopy.fixedCurrencySelectionLabel(
                currencyName(code),
                code.rawValue
            ))
        }
    }

    private var systemCurrencyCode: CurrencyCode {
        let identifier = Locale.autoupdatingCurrent.currency?.identifier ?? CurrencyCode.usd.rawValue
        return CurrencyCode(identifier) ?? .usd
    }

    private func referenceRateText(_ context: CurrencyDisplayContext) -> String {
        guard !context.isFallback else {
            return localized(TokensSettingsCopy.referenceRateUnavailable(
                context.requestedCode.rawValue
            ))
        }
        return localized(TokensSettingsCopy.referenceRate(
            decimalText(context.rate, maximumFractionDigits: 6),
            context.currencyCode.rawValue
        ))
    }

    private func decimalText(_ value: Decimal, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func currencyName(_ code: CurrencyCode) -> String {
        locale.localizedString(forCurrencyCode: code.rawValue)
            ?? code.rawValue
    }

    private var activeSourceDescriptor: ExchangeRateProviderDescriptor {
        currencyModel.availableSourceDescriptors.first {
            $0.id == currencyModel.activeSource.providerID
        } ?? currencyModel.activeSource.providerID.descriptor
    }

    private func rateDetailsStatus(
        _ context: CurrencyDisplayContext
    ) -> (text: String, systemImage: String, color: Color) {
        if currencyModel.lastError != nil {
            return (
                currencyModel.snapshot == nil
                    ? localized(TokensSettingsCopy.updateFailedWithoutCache)
                    : localized(TokensSettingsCopy.updateFailedWithCache),
                "exclamationmark.triangle.fill",
                .orange
            )
        }
        if context.isFallback {
            return (
                localized(TokensSettingsCopy.fallbackStatus(context.requestedCode.rawValue)),
                "arrow.uturn.backward.circle",
                .orange
            )
        }
        if currencyModel.isSnapshotStale {
            return (
                localized(TokensSettingsCopy.staleRateStatus),
                "clock.arrow.circlepath",
                .secondary
            )
        }
        if currencyModel.snapshot == nil {
            return (localized(TokensSettingsCopy.noRatesCachedStatus), "tray", .secondary)
        }
        return (
            localized(TokensSettingsCopy.upToDateStatus(activeSourceDescriptor.displayName)),
            "checkmark.circle.fill",
            .green
        )
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        AppLocalizer(locale: locale).localized(resource)
    }
}

private struct CurrencyPreview: View {
    let context: CurrencyDisplayContext

    @Environment(\.locale) private var locale
    private let exampleUSD = Decimal(10)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(TokensSettingsCopy.previewTitle)
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
            return localized(TokensSettingsCopy.previewNotConverted(exampleUSDText))
        }
        if isNativeUSD {
            return localized(TokensSettingsCopy.previewNoConversion(exampleUSDText))
        }
        return localized(TokensSettingsCopy.previewApproximate(exampleUSDText, convertedText))
    }

    private var previewAccessibilityLabel: String {
        if context.isFallback {
            return localized(TokensSettingsCopy.previewFallbackAccessibilityLabel(
                context.requestedCode.rawValue,
                exampleUSDText
            ))
        }
        if isNativeUSD {
            return localized(TokensSettingsCopy.previewUSDAccessibilityLabel(exampleUSDText))
        }
        return localized(TokensSettingsCopy.previewConvertedAccessibilityLabel(
            exampleUSDText,
            convertedText
        ))
    }

    private var exampleUSDText: String {
        exampleUSD.formatted(
            .currency(code: CurrencyCode.usd.rawValue)
                .precision(.fractionLength(2))
                .locale(locale)
        )
    }

    private var convertedText: String {
        context.amount(forUSD: exampleUSD).formatted()
    }

    private var isNativeUSD: Bool {
        context.requestedCode == .usd && context.currencyCode == .usd
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        AppLocalizer(locale: locale).localized(resource)
    }
}

private struct CurrencyPickerSheet: View {
    @Bindable var currencyModel: CurrencyModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(TokensSettingsCopy.currencyPickerTitle)
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 20)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField(text: $query) {
                        Text(TokensSettingsCopy.currencySearchPlaceholder)
                    }
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
                        .accessibilityLabel(Text(
                            TokensSettingsCopy.clearCurrencySearchAccessibilityLabel
                        ))
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 220, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityElement(children: .contain)

                Button {
                    dismiss()
                } label: {
                    Text(TokensSettingsCopy.closeButton)
                }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            List {
                if !filteredPopularCurrencies.isEmpty {
                    Section {
                        ForEach(filteredPopularCurrencies, id: \.rawValue) { code in
                            currencyRow(
                                selection: .fixed(code),
                                code: code,
                                title: currencyName(code),
                                subtitle: code.rawValue
                            )
                        }
                    } header: {
                        Text(TokensSettingsCopy.popularCurrenciesSectionTitle)
                    }
                }

                if automaticMatchesQuery {
                    Section {
                        currencyRow(
                            selection: .system,
                            code: systemCurrencyCode,
                            title: localized(TokensSettingsCopy.systemRegionTitle),
                            subtitle: localized(TokensSettingsCopy.fixedCurrencySelectionLabel(
                                currencyName(systemCurrencyCode),
                                systemCurrencyCode.rawValue
                            ))
                        )
                    } header: {
                        Text(TokensSettingsCopy.automaticSectionTitle)
                    } footer: {
                        if currencyModel.snapshot == nil {
                            Text(TokensSettingsCopy.noCachedRatesPickerFooter(activeProviderName))
                        }
                    }
                }

                if !filteredGeneralCurrencies.isEmpty {
                    Section {
                        ForEach(filteredGeneralCurrencies, id: \.rawValue) { code in
                            currencyRow(
                                selection: .fixed(code),
                                code: code,
                                title: currencyName(code),
                                subtitle: code.rawValue
                            )
                        }
                    } header: {
                        Text(TokensSettingsCopy.allCurrenciesSectionTitle)
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
        return localized(TokensSettingsCopy.systemRegionTitle)
            .localizedCaseInsensitiveContains(trimmed)
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
        .accessibilityLabel(Text(
            isSelected
                ? TokensSettingsCopy.selectedCurrencyAccessibilityLabel(title, subtitle)
                : TokensSettingsCopy.currencyAccessibilityLabel(title, subtitle)
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var systemCurrencyCode: CurrencyCode {
        currencyModel.systemCurrencyCode
    }

    private func currencyName(_ code: CurrencyCode) -> String {
        locale.localizedString(forCurrencyCode: code.rawValue)
            ?? code.rawValue
    }

    private func currencySymbol(_ code: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code.rawValue
        return formatter.currencySymbol ?? code.rawValue
    }

    private var activeProviderName: String {
        currencyModel.availableSourceDescriptors.first {
            $0.id == currencyModel.activeSource.providerID
        }?.displayName ?? currencyModel.activeSource.providerID.rawValue
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        AppLocalizer(locale: locale).localized(resource)
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
                    Picker(selection: $selectedProviderID) {
                        ForEach(currencyModel.availableSourceDescriptors) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.id)
                        }
                    } label: {
                        Text(TokensSettingsCopy.providerPickerLabel)
                    }

                    Text(selectedDescriptor.id.settingsExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledContent {
                        Link(
                            selectedDescriptor.attributionTitle,
                            destination: selectedDescriptor.attributionURL
                        )
                    } label: {
                        Text(TokensSettingsCopy.attributionLabel)
                    }

                    LabeledContent {
                        Link(destination: selectedDescriptor.documentationURL) {
                            Text(TokensSettingsCopy.openAPIDocumentationLink)
                        }
                    } label: {
                        Text(TokensSettingsCopy.documentationLabel)
                    }
                } header: {
                    Text(TokensSettingsCopy.rateProviderLabel)
                }

                Section {
                    TextField(text: $endpointText) {
                        Text(TokensSettingsCopy.endpointPlaceholder)
                    }
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .disabled(currencyModel.isValidatingSource)
                        .accessibilityLabel(Text(
                            TokensSettingsCopy.endpointFieldAccessibilityLabel
                        ))

                    HStack {
                        Text(TokensSettingsCopy.endpointCredentialWarning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button {
                            endpointText = selectedDescriptor.defaultEndpoint.absoluteString
                            currencyModel.clearSourceValidationError()
                        } label: {
                            Text(TokensSettingsCopy.restoreDefaultButton)
                        }
                        .disabled(
                            currencyModel.isValidatingSource
                                || endpointText == selectedDescriptor.defaultEndpoint.absoluteString
                        )
                    }
                } header: {
                    Text(TokensSettingsCopy.httpsEndpointSectionTitle)
                } footer: {
                    Text(TokensSettingsCopy.endpointVerificationFooter)
                }

                if let validationError = currencyModel.sourceValidationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Text(
                                TokensSettingsCopy.sourceValidationErrorAccessibilityLabel(
                                    validationError
                                )
                            ))
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(currencyModel.isValidatingSource)
            .navigationTitle(Text(TokensSettingsCopy.sourceSheetTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        currencyModel.clearSourceValidationError()
                        dismiss()
                    } label: {
                        Text(TokensSettingsCopy.cancelButton)
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
                                Text(TokensSettingsCopy.verifyingSource)
                            }
                        } else {
                            Text(TokensSettingsCopy.verifyAndUseButton)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        currencyModel.isValidatingSource
                            || endpointText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityLabel(Text(
                        currencyModel.isValidatingSource
                            ? TokensSettingsCopy.verifyingSourceAccessibilityLabel
                            : TokensSettingsCopy.verifyAndUseAccessibilityLabel
                    ))
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

private extension ExchangeRateProviderID {
    var settingsExplanation: LocalizedStringResource {
        switch self {
        case .frankfurter:
            LocalizedStringResource.settingsTokensCurrencyProviderFrankfurterExplanation
        case .exchangeRateAPI:
            LocalizedStringResource.settingsTokensCurrencyProviderExchangeRateApiExplanation
        case .ecb:
            LocalizedStringResource.settingsTokensCurrencyProviderEcbExplanation
        }
    }
}

private enum TokensSettingsCopy {
    static let title = LocalizedStringResource.settingsTokensTitle
    static let tokenValuesTitle = LocalizedStringResource.settingsAppearanceTokenValuesTitle
    static let tokenValuesFooter = LocalizedStringResource.settingsAppearanceTokenValuesFooter

    static let currencySectionTitle = LocalizedStringResource.settingsTokensCurrencySectionTitle
    static let displayCurrencyLabel = LocalizedStringResource.settingsTokensCurrencyDisplayLabel
    static let displayCurrencyHelp = LocalizedStringResource.settingsTokensCurrencyDisplayHelp

    static func displayCurrencyAccessibilityLabel(_ selection: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyDisplayAccessibilityLabel(selection)
    }

    static let rateDetailsExpandAccessibilityHint =
        LocalizedStringResource.settingsTokensCurrencyDetailsExpandAccessibilityHint
    static let rateDetailsCollapseAccessibilityHint =
        LocalizedStringResource.settingsTokensCurrencyDetailsCollapseAccessibilityHint
    static let rateDetailsTitle = LocalizedStringResource.settingsTokensCurrencyDetailsTitle
    static let referenceRateLabel =
        LocalizedStringResource.settingsTokensCurrencyDetailsReferenceRateLabel
    static let rateDateLabel = LocalizedStringResource.settingsTokensCurrencyDetailsRateDateLabel
    static let fetchedLabel = LocalizedStringResource.settingsTokensCurrencyDetailsFetchedLabel
    static let nextEligibleRefreshLabel =
        LocalizedStringResource.settingsTokensCurrencyDetailsNextEligibleRefreshLabel
    static let rateProviderLabel =
        LocalizedStringResource.settingsTokensCurrencyDetailsRateProviderLabel
    static let changeProviderHelp =
        LocalizedStringResource.settingsTokensCurrencyDetailsRateProviderChangeHelp

    static func changeProviderAccessibilityLabel(_ provider: String) -> LocalizedStringResource {
        LocalizedStringResource
            .settingsTokensCurrencyDetailsRateProviderChangeAccessibilityLabel(provider)
    }

    static let apiEndpointLabel =
        LocalizedStringResource.settingsTokensCurrencyDetailsApiEndpointLabel

    static func changeEndpointAccessibilityLabel(_ endpoint: String) -> LocalizedStringResource {
        LocalizedStringResource
            .settingsTokensCurrencyDetailsApiEndpointChangeAccessibilityLabel(endpoint)
    }

    static let attributionLabel =
        LocalizedStringResource.settingsTokensCurrencyDetailsAttributionLabel
    static let rateRequestPolicy =
        LocalizedStringResource.settingsTokensCurrencyDetailsRequestPolicy
    static let updatingRates =
        LocalizedStringResource.settingsTokensCurrencyStatusUpdatingRates
    static let loadingRates = LocalizedStringResource.settingsTokensCurrencyStatusLoadingRates
    static let refreshingRatesWithLastKnown =
        LocalizedStringResource.settingsTokensCurrencyStatusRefreshingWithLastKnown
    static let retryExplanationWithoutCache =
        LocalizedStringResource.settingsTokensCurrencyStatusRetryWithoutCache
    static let retryExplanationWithCache =
        LocalizedStringResource.settingsTokensCurrencyStatusRetryWithCache
    static let staleRateWarning =
        LocalizedStringResource.settingsTokensCurrencyStatusStaleWarning

    static func fallbackWarning(_ code: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyStatusFallbackWarning(code)
    }

    static func unavailableCurrencyWarning(_ code: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyStatusUnavailableWarning(code)
    }

    static let usingLastKnownRate =
        LocalizedStringResource.settingsTokensCurrencyStatusUsingLastKnown
    static let noRatesCachedInstruction =
        LocalizedStringResource.settingsTokensCurrencyStatusNoRatesInstruction
    static let updatingButton =
        LocalizedStringResource.settingsTokensCurrencyRefreshUpdatingButton
    static let updatingAccessibilityLabel =
        LocalizedStringResource.settingsTokensCurrencyRefreshUpdatingAccessibilityLabel
    static let retryNowButton =
        LocalizedStringResource.settingsTokensCurrencyRefreshRetryButton
    static let retryNowHelp = LocalizedStringResource.settingsTokensCurrencyRefreshRetryHelp
    static let refreshRatesButton =
        LocalizedStringResource.settingsTokensCurrencyRefreshRefreshButton
    static let updatedButton =
        LocalizedStringResource.settingsTokensCurrencyRefreshUpdatedButton
    static let updatedAccessibilityLabel =
        LocalizedStringResource.settingsTokensCurrencyRefreshUpdatedAccessibilityLabel

    static func systemRegionSelectionLabel(
        _ currencyName: String,
        _ code: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencySelectionSystemRegion(
            currencyName,
            code
        )
    }

    static func fixedCurrencySelectionLabel(
        _ currencyName: String,
        _ code: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencySelectionFixed(currencyName, code)
    }

    static func referenceRateUnavailable(_ code: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyReferenceRateUnavailable(code)
    }

    static func referenceRate(_ rate: String, _ code: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyReferenceRateValue(rate, code)
    }

    static let updateFailedWithoutCache =
        LocalizedStringResource.settingsTokensCurrencySummaryUpdateFailedWithoutCache
    static let updateFailedWithCache =
        LocalizedStringResource.settingsTokensCurrencySummaryUpdateFailedWithCache

    static func fallbackStatus(_ code: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencySummaryFallback(code)
    }

    static let staleRateStatus =
        LocalizedStringResource.settingsTokensCurrencySummaryStale
    static let noRatesCachedStatus =
        LocalizedStringResource.settingsTokensCurrencySummaryNoRates

    static func upToDateStatus(_ provider: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencySummaryUpToDate(provider)
    }

    static let previewTitle = LocalizedStringResource.settingsTokensCurrencyPreviewTitle

    static func previewNotConverted(_ usd: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPreviewNotConverted(usd)
    }

    static func previewNoConversion(_ usd: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPreviewNoConversion(usd)
    }

    static func previewApproximate(
        _ usd: String,
        _ convertedAmount: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPreviewApproximate(
            usd,
            convertedAmount
        )
    }

    static func previewFallbackAccessibilityLabel(
        _ code: String,
        _ usd: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPreviewFallbackAccessibilityLabel(
            code,
            usd
        )
    }

    static func previewUSDAccessibilityLabel(_ usd: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPreviewUsdAccessibilityLabel(usd)
    }

    static func previewConvertedAccessibilityLabel(
        _ usd: String,
        _ convertedAmount: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPreviewConvertedAccessibilityLabel(
            usd,
            convertedAmount
        )
    }

    static let currencyPickerTitle =
        LocalizedStringResource.settingsTokensCurrencyPickerTitle
    static let currencySearchPlaceholder =
        LocalizedStringResource.settingsTokensCurrencyPickerSearchPlaceholder
    static let clearCurrencySearchAccessibilityLabel =
        LocalizedStringResource.settingsTokensCurrencyPickerSearchClearAccessibilityLabel
    static let closeButton =
        LocalizedStringResource.settingsTokensCurrencyPickerCloseButton
    static let popularCurrenciesSectionTitle =
        LocalizedStringResource.settingsTokensCurrencyPickerPopularSection
    static let systemRegionTitle =
        LocalizedStringResource.settingsTokensCurrencyPickerSystemRegion
    static let automaticSectionTitle =
        LocalizedStringResource.settingsTokensCurrencyPickerAutomaticSection

    static func noCachedRatesPickerFooter(_ provider: String) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPickerNoRatesFooter(provider)
    }

    static let allCurrenciesSectionTitle =
        LocalizedStringResource.settingsTokensCurrencyPickerAllCurrenciesSection

    static func selectedCurrencyAccessibilityLabel(
        _ title: String,
        _ subtitle: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPickerRowSelectedAccessibilityLabel(
            title,
            subtitle
        )
    }

    static func currencyAccessibilityLabel(
        _ title: String,
        _ subtitle: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencyPickerRowAccessibilityLabel(
            title,
            subtitle
        )
    }

    static let sourceSheetTitle =
        LocalizedStringResource.settingsTokensCurrencySourceTitle
    static let providerPickerLabel =
        LocalizedStringResource.settingsTokensCurrencySourceProviderPicker
    static let documentationLabel =
        LocalizedStringResource.settingsTokensCurrencySourceDocumentationLabel
    static let openAPIDocumentationLink =
        LocalizedStringResource.settingsTokensCurrencySourceDocumentationLink
    static let endpointPlaceholder =
        LocalizedStringResource.settingsTokensCurrencySourceEndpointPlaceholder
    static let endpointFieldAccessibilityLabel =
        LocalizedStringResource.settingsTokensCurrencySourceEndpointAccessibilityLabel
    static let endpointCredentialWarning =
        LocalizedStringResource.settingsTokensCurrencySourceEndpointCredentialWarning
    static let restoreDefaultButton =
        LocalizedStringResource.settingsTokensCurrencySourceRestoreDefaultButton
    static let httpsEndpointSectionTitle =
        LocalizedStringResource.settingsTokensCurrencySourceHttpsEndpointSection
    static let endpointVerificationFooter =
        LocalizedStringResource.settingsTokensCurrencySourceEndpointVerificationFooter

    static func sourceValidationErrorAccessibilityLabel(
        _ error: String
    ) -> LocalizedStringResource {
        LocalizedStringResource.settingsTokensCurrencySourceValidationErrorAccessibilityLabel(
            error
        )
    }

    static let cancelButton =
        LocalizedStringResource.settingsTokensCurrencySourceCancelButton
    static let verifyingSource =
        LocalizedStringResource.settingsTokensCurrencySourceVerifying
    static let verifyAndUseButton =
        LocalizedStringResource.settingsTokensCurrencySourceVerifyAndUseButton
    static let verifyingSourceAccessibilityLabel =
        LocalizedStringResource.settingsTokensCurrencySourceVerifyingAccessibilityLabel
    static let verifyAndUseAccessibilityLabel =
        LocalizedStringResource.settingsTokensCurrencySourceVerifyAndUseAccessibilityLabel
}
