#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_ROOT}/TokenStats.xcodeproj/project.pbxproj"
SCHEME_FILE="${PROJECT_ROOT}/TokenStats.xcodeproj/xcshareddata/xcschemes/TokenStats.xcscheme"
PRODUCTION_SOURCES="${PROJECT_ROOT}/TokenStats"
TEST_SOURCES="${PROJECT_ROOT}/TokenStatsTests"

APP_TARGET_ID="0BBC1D292FC67592004E2460"
UNIT_TARGET_ID="0BBC1D382FC67594004E2460"
UI_TARGET_ID="0BBC1D422FC67594004E2460"
UNIT_DEBUG_CONFIG_ID="0BBC1D512FC67594004E2460"
UNIT_RELEASE_CONFIG_ID="0BBC1D522FC67594004E2460"
PRODUCTION_GROUP_ID="0BBC1D2C2FC67592004E2460"
UNIT_GROUP_ID="0BBC1D3C2FC67594004E2460"

fail() {
    echo "unit-test isolation check failed: $*" >&2
    exit 1
}

extract_project_object() {
    local object_id="$1"
    awk -v object_id="$object_id" '
        $0 ~ "^\\t\\t" object_id " /\\*" { found = 1 }
        found { print }
        found && /^\t\t};$/ { exit }
    ' "$PROJECT_FILE"
}

extract_build_action_entry() {
    local blueprint_name="$1"
    awk -v blueprint_name="$blueprint_name" '
        /<BuildActionEntry/ { capturing = 1; entry = "" }
        capturing { entry = entry $0 "\n" }
        /<\/BuildActionEntry>/ && capturing {
            if (index(entry, "BlueprintName = \"" blueprint_name "\"")) {
                printf "%s", entry
                exit
            }
            capturing = 0
        }
    ' "$SCHEME_FILE"
}

extract_target_attributes() {
    local target_id="$1"
    awk -v target_id="$target_id" '
        $0 ~ "^[[:space:]]+" target_id " = \\{" { found = 1 }
        found { print }
        found && /^[[:space:]]+};$/ { exit }
    ' "$PROJECT_FILE"
}

[[ -f "$PROJECT_FILE" ]] || fail "project.pbxproj is missing"
[[ -f "$SCHEME_FILE" ]] || fail "shared TokenStats scheme is missing"

UNIT_TARGET="$(extract_project_object "$UNIT_TARGET_ID")"
[[ -n "$UNIT_TARGET" ]] || fail "TokenStatsTests target is missing"
grep -Fq "$PRODUCTION_GROUP_ID /* TokenStats */" <<<"$UNIT_TARGET" \
    || fail "TokenStatsTests must compile the shared production source group"
grep -Fq "$UNIT_GROUP_ID /* TokenStatsTests */" <<<"$UNIT_TARGET" \
    || fail "TokenStatsTests source group is missing"
grep -Fq 'dependencies = (' <<<"$UNIT_TARGET" \
    || fail "TokenStatsTests dependency list is missing"
if grep -Fq '/* PBXTargetDependency */' <<<"$UNIT_TARGET"; then
    fail "TokenStatsTests dependency list must stay empty"
fi

for config_id in "$UNIT_DEBUG_CONFIG_ID" "$UNIT_RELEASE_CONFIG_ID"; do
    CONFIG="$(extract_project_object "$config_id")"
    [[ -n "$CONFIG" ]] || fail "unit-test build configuration ${config_id} is missing"
    if grep -Eq 'BUNDLE_LOADER|TEST_HOST' <<<"$CONFIG"; then
        fail "unit-test configuration ${config_id} is application-hosted"
    fi
    grep -Fq 'EXCLUDED_SOURCE_FILE_NAMES = TokenStatsApp.swift;' <<<"$CONFIG" \
        || fail "unit-test configuration ${config_id} must exclude the @main source"
    grep -Fq 'STRING_CATALOG_GENERATE_SYMBOLS = YES;' <<<"$CONFIG" \
        || fail "unit-test configuration ${config_id} must generate catalog symbols"
    grep -Fq 'LM_SKIP_METADATA_EXTRACTION = YES;' <<<"$CONFIG" \
        || fail "unit-test configuration ${config_id} must skip irrelevant App Intents extraction"
    grep -Fq 'SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;' <<<"$CONFIG" \
        || fail "unit-test configuration ${config_id} must match the app's actor isolation"
    if grep -Fq 'TEST_TARGET_NAME' <<<"$CONFIG"; then
        fail "unit-test configuration ${config_id} must not name an application test target"
    fi
done

TEST_TARGET_ID_COUNT="$(grep -Fc "TestTargetID = ${APP_TARGET_ID};" "$PROJECT_FILE" || true)"
[[ "$TEST_TARGET_ID_COUNT" = "1" ]] \
    || fail "only TokenStatsUITests may retain the TokenStats TestTargetID"
UNIT_ATTRIBUTES="$(extract_target_attributes "$UNIT_TARGET_ID")"
UI_ATTRIBUTES="$(extract_target_attributes "$UI_TARGET_ID")"
if grep -Fq 'TestTargetID' <<<"$UNIT_ATTRIBUTES"; then
    fail "TokenStatsTests must not identify TokenStats.app as its test host"
fi
grep -Fq "TestTargetID = ${APP_TARGET_ID};" <<<"$UI_ATTRIBUTES" \
    || fail "TokenStatsUITests must retain TokenStats.app as its UI target"

APP_BUILD_ENTRY="$(extract_build_action_entry TokenStats)"
UNIT_BUILD_ENTRY="$(extract_build_action_entry TokenStatsTests)"
grep -Fq 'buildForTesting = "NO"' <<<"$APP_BUILD_ENTRY" \
    || fail "the default scheme must not build TokenStats.app for unit testing"
grep -Fq 'buildForTesting = "YES"' <<<"$UNIT_BUILD_ENTRY" \
    || fail "the default scheme must build TokenStatsTests"

if grep -Fq 'BlueprintName = "TokenStatsUITests"' "$SCHEME_FILE"; then
    fail "the foreground-driving UI target must stay out of the default scheme"
fi
if grep -R -Fq '@testable import TokenStats' "$TEST_SOURCES"; then
    fail "unhosted tests compile shared sources directly and must not import the app executable"
fi
if grep -R -Fq 'UserDefaults(suiteName:' "$TEST_SOURCES"; then
    fail "unit tests must use InMemoryUserDefaults instead of persistent preference suites"
fi

MAIN_SOURCES="$(grep -R -l -E '^[[:space:]]*@main([[:space:]]|$)' "$PRODUCTION_SOURCES" --include='*.swift' || true)"
[[ "$(wc -l <<<"$MAIN_SOURCES" | tr -d ' ')" = "1" ]] \
    || fail "production sources must contain exactly one @main entry point"
[[ "$(basename "$MAIN_SOURCES")" = "TokenStatsApp.swift" ]] \
    || fail "the unit target exclusion no longer matches the production @main source"

echo "Unit-test isolation valid: unhosted xctest bundle, no TokenStats.app build or UI target."
