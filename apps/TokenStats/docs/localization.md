# TokenStats macOS localization

TokenStats uses Apple's native localization stack: an Xcode String Catalog (`Localizable.xcstrings`), `LocalizedStringResource`, Xcode-generated type-safe symbols, and Foundation `FormatStyle`. The macOS app does not depend on a third-party localization library, write `AppleLanguages`, or replace/swizzle `Bundle` behavior.

This document covers `apps/TokenStats` only. The Windows client has its own native implementation and release lifecycle.

## Supported languages

- English (`en`) is the source language.
- Simplified Chinese (`zh-Hans`) is a complete launch language.
- German (`de`), French (`fr`), Japanese (`ja`), and Russian (`ru`) have complete, native-reviewed catalogs and are release-ready.
- Missing runtime translations fall back to English, but catalog validation rejects a missing or unreviewed value in any supported language before release.

The app language setting is ordered **Follow System**, **English**, **简体中文**, **Deutsch**, **Français**, **日本語**, **Русский**. Language names are presented in their own language. A preference change is saved immediately but does not partially relocalize the running process:

1. `effectiveLanguage` is frozen when the process starts.
2. Selecting a different language creates a pending restart state.
3. Selecting the effective language again clears the pending state.
4. **Restart Now** opens a new app instance through `NSWorkspace.OpenConfiguration` with `createsNewApplicationInstance = true`. The old instance terminates only after the open succeeds; a failed open leaves it running and presents a localized error.
5. **Later** keeps the current process entirely in its current language. The saved choice applies at the next launch.

The UI Locale starts from the current system Locale and replaces only its language/script components. An explicit in-app language supplies those components and clears an inherited script when the selected language has no explicit script; this prevents invalid combinations such as `de-Hans`. **Follow System** uses `Bundle.main.preferredLocalizations` so it also honors macOS's per-app language setting. Region, calendar, numbering system, and hour-cycle preferences remain the system values. Consequently, `zh-Hans-US` uses Simplified Chinese copy with US formatting, while `de-US` uses German copy with US formatting. System-owned macOS UI remains controlled by macOS.

## Catalog keys and source usage

Use stable semantic keys grouped from broad to narrow, for example:

```text
settings.general.language.title
settings.general.language.restart.message
usage.window.weekly
tokens.summary.metric.api_equivalent
```

Key rules:

- Use the generated symbol in business and UI code. Do not pass a visible string literal directly to `Text`, `Button`, `.help`, accessibility modifiers, or AppKit UI.
- Give every entry an `en`, `zh-Hans`, `de`, `fr`, `ja`, and `ru` value plus a translator comment that explains context, placeholders, and constraints.
- Localize a complete sentence. Do not concatenate translated fragments or build a sentence by joining independently translated labels.
- Use String Catalog plural variants for count-dependent grammar. Required categories are `one/other` for English and German, `one/few/many/other` for Russian, `one/many/other` for French, and `other` for Japanese. Simplified Chinese requires at least `other` and may retain the catalog's existing redundant `one` branch. Do not implement plural selection in Swift.
- Interpolate typed values into one resource so the catalog records placeholder order and translators can reorder placeholders.
- Keep a key's meaning stable. If the semantic meaning changes, create a new key instead of silently reusing an unrelated translation.
- Keys are implementation identifiers and must never appear in the runtime UI.

The canonical six-language product terms and definitions live in [`../CONTEXT.md`](../CONTEXT.md). Review every translation against that glossary; protected product names and model identifiers remain unchanged in all languages.

## Formatting and invariant data

Use Foundation `FormatStyle` with the effective UI language plus the user's system regional preferences for visible values:

- Numbers and compact numbers use locale-aware decimal separators and compact notation. Compact-unit vocabulary follows the effective UI language, while the preserved system region can refine symbols and regional forms; examples include English K/M/B, German Mio./Mrd., French M/Md, Russian млн/млрд, and Chinese/Japanese 万/亿 forms. Do not hand-author thresholds. Let Foundation choose compact precision and unit promotion. Put the full localized value in help and accessibility text when the visual value is abbreviated.
- Remaining percentages retain the product rule of rounding downward before locale-aware percent formatting.
- Relative times and durations use Foundation formatters and complete localized resources where surrounding grammar is needed.
- Dates and times shown to people use the UI Locale and the user's calendar/hour-cycle preferences.
- API-equivalent estimates remain canonically priced and aggregated in USD. Fixed USD is the default display choice. When macOS displays another selected ISO 4217 currency, multiply the exact USD aggregate by the cached USD reference rate, then round upward once at the target currency's standard minor unit. Windows remains USD-only. The selected app language never selects a display currency; currency names, amounts, dates, and times use the effective UI language together with the user's system region.

Machine-readable values remain locale-invariant. Use `en_US_POSIX` (and the existing fixed calendar/time-zone rules where applicable) for JSON, timestamps, cache date keys, protocol fields, and pricing-table parsing. Never localize identifiers stored in caches or sent to an API.

## Content that is not translated

Preserve these values exactly:

- TokenStats, Claude Code, Codex, and Fable brand/product names.
- Model IDs and model names reported by an integration.
- URLs, filesystem paths, command names, protocol values, JSON keys, OAuth codes, and other machine identifiers.
- Raw server, parser, and OAuth diagnostic payloads.

Localize controls, explanations, accessibility sentences, and the outer summary of an error. Raw diagnostics belong only in the expandable diagnostic detail. OAuth callback HTML is app-owned UI: localize its title/body, escape inserted values, and set `<html lang>` to the effective app language.

## Adding or changing a language

1. Add the generic language code to `Localizable.xcstrings`, Xcode `knownRegions`, the supported `AppLanguage` choices, and the catalog test's plural contract when it should be user-selectable. Do not add `CFBundleLocalizations`.
2. Translate every catalog entry directly in the String Catalog or review its JSON diff in the pull request, including every required plural branch. Preserve placeholder positions and types. Do not use an XLIFF round trip for this project.
3. Keep draft String Units out of the `translated` state. Have a product-language reviewer check terminology and a native-language reviewer check fluency, truncation, placeholder order, and accessibility sentences before marking the complete language reviewed.
4. Run `npm run test:localization` and the catalog completeness tests. All six values, required plural categories, `translated` states, placeholder schemas, and translator comments are release requirements.
5. Launch unit/UI coverage with fixed language and region combinations: `en-US`/`en-DE`, `zh-Hans-US`/`zh-Hans-CN`, `de-US`/`de-DE`, `fr-US`/`fr-FR`, `ja-US`/`ja-JP`, and `ru-US`/`ru-RU`. Run the opt-in `npm run test:ui` only in an isolated macOS session because it controls the foreground desktop.
6. Inspect fixed-width popovers, tables, settings, onboarding, and accessibility under Xcode's Double-Length, Tall, Accented, and RTL pseudolanguages. A pseudolanguage is test data, not a shipped language.
7. Run the full `npm test`, a Release build, and verify the built app contains `en.lproj`, `zh-Hans.lproj`, `de.lproj`, `fr.lproj`, `ja.lproj`, and `ru.lproj` resources.

For a copy-only change, update the existing semantic key only when its meaning is unchanged. Re-run the same completeness and UI checks because English copy edits can invalidate translations even when placeholders did not change.

## Hard-coded string guard

`scripts/check-localization.sh` rejects direct string literals passed to common SwiftUI/AppKit presentation APIs across the product source tree. It is a fast guard, not a substitute for catalog completeness tests or review.

A genuinely non-translatable literal needs a reason on the same line or immediately above it:

```swift
// i18n-ignore: Product name is intentionally invariant.
Text("TokenStats")
```

Use `i18n-ignore: <reason>` only for visible values that are intentionally invariant (for example a brand or protocol token). Empty reasons fail the check. Do not use an ignore for copy that merely has not been translated yet.
