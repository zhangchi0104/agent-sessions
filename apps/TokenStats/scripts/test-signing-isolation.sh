#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="${TOKENSTATS_SIGNING_PROJECT_FILE:-${PROJECT_ROOT}/TokenStats.xcodeproj/project.pbxproj}"
SIGNING_CONFIG="${PROJECT_ROOT}/Config/Signing.xcconfig"
SIGNING_EXAMPLE="${PROJECT_ROOT}/Config/Signing.local.xcconfig.example"
LOCAL_CONFIG="Config/Signing.local.xcconfig"

fail() {
  echo "error: signing isolation check failed: $*" >&2
  exit 1
}

require_single_setting() {
  local file="$1"
  local key="$2"
  local expected_pattern="$3"
  local description="$4"
  local assignment_pattern
  local count

  assignment_pattern="^[[:space:]]*\"?${key}(\\[[^]]+\\])?\"?[[:space:]]*="
  count="$(grep -Ec "$assignment_pattern" "$file" || true)"
  [[ "$count" = "1" ]] || fail "expected exactly one ${description} assignment, found ${count}"
  grep -Eq "$expected_pattern" "$file" || fail "${description} has the wrong value"
}

[[ -f "$PROJECT_FILE" ]] || fail "project file is missing"
[[ -f "$SIGNING_CONFIG" ]] || fail "Config/Signing.xcconfig is missing"
[[ -f "$SIGNING_EXAMPLE" ]] || fail "Config/Signing.local.xcconfig.example is missing"

FORBIDDEN_PROJECT_SETTING='^[[:space:]]*"?(CODE_SIGN_IDENTITY|CODE_SIGN_STYLE|DEVELOPMENT_TEAM|DevelopmentTeam|PROVISIONING_PROFILE|PROVISIONING_PROFILE_SPECIFIER)(\[[^]]+\])?"?[[:space:]]*='
if grep -Eq "$FORBIDDEN_PROJECT_SETTING" "$PROJECT_FILE"; then
  grep -En "$FORBIDDEN_PROJECT_SETTING" "$PROJECT_FILE" >&2
  fail "personal signing settings must not be stored in project.pbxproj"
fi

require_single_setting "$SIGNING_CONFIG" CODE_SIGN_STYLE '^[[:space:]]*CODE_SIGN_STYLE[[:space:]]*=[[:space:]]*Manual[[:space:]]*$' "shared signing style"
require_single_setting "$SIGNING_CONFIG" CODE_SIGN_IDENTITY '^[[:space:]]*CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*-[[:space:]]*$' "shared signing identity"
require_single_setting "$SIGNING_CONFIG" DEVELOPMENT_TEAM '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*$' "shared development team"
require_single_setting "$SIGNING_CONFIG" PROVISIONING_PROFILE_SPECIFIER '^[[:space:]]*PROVISIONING_PROFILE_SPECIFIER[[:space:]]*=[[:space:]]*$' "shared provisioning profile"

INCLUDE_COUNT="$(grep -Ec '^[[:space:]]*#include[?][[:space:]]+"Signing[.]local[.]xcconfig"[[:space:]]*$' "$SIGNING_CONFIG" || true)"
[[ "$INCLUDE_COUNT" = "1" ]] || fail "expected one optional local signing include, found ${INCLUDE_COUNT}"

require_single_setting "$SIGNING_EXAMPLE" CODE_SIGN_STYLE '^[[:space:]]*CODE_SIGN_STYLE[[:space:]]*=[[:space:]]*Automatic[[:space:]]*$' "example signing style"
require_single_setting "$SIGNING_EXAMPLE" CODE_SIGN_IDENTITY '^[[:space:]]*CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*Apple Development[[:space:]]*$' "example signing identity"
require_single_setting "$SIGNING_EXAMPLE" DEVELOPMENT_TEAM '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*YOUR_10_CHARACTER_TEAM_ID[[:space:]]*$' "example Team ID"

SIGNING_FILE_ID="$(awk '/\/\* Signing[.]xcconfig \*\/ = \{isa = PBXFileReference/ { print $1 }' "$PROJECT_FILE")"
[[ -n "$SIGNING_FILE_ID" ]] || fail "Signing.xcconfig file reference is missing"
FILE_REFERENCE_COUNT="$(awk '/\/\* Signing[.]xcconfig \*\/ = \{isa = PBXFileReference/ { count += 1 } END { print count + 0 }' "$PROJECT_FILE")"
[[ "$FILE_REFERENCE_COUNT" = "1" ]] || fail "expected one Signing.xcconfig file reference, found ${FILE_REFERENCE_COUNT}"

PROJECT_CONFIG_IDS="$(awk '
  /\/\* Build configuration list for PBXProject "TokenStats" \*\/ =/ { in_project = 1 }
  in_project && /buildConfigurations = \(/ { in_configs = 1; next }
  in_configs && /\);/ { exit }
  in_configs && /\/\* (Debug|Release) \*\// { print $1 }
' "$PROJECT_FILE")"
set -- $PROJECT_CONFIG_IDS
[[ "$#" = "2" ]] || fail "expected Project Debug and Release configuration IDs"

for project_config_id in "$@"; do
  resolved_base_id="$(awk -v config_id="$project_config_id" '
    $1 == config_id { in_config = 1 }
    in_config && /baseConfigurationReference =/ { print $3; exit }
    in_config && /^[[:space:]]*};/ { exit }
  ' "$PROJECT_FILE")"
  [[ "$resolved_base_id" = "$SIGNING_FILE_ID" ]] \
    || fail "Project configuration ${project_config_id} does not use Signing.xcconfig"
done

BASE_CONFIG_COUNT="$(grep -Ec "baseConfigurationReference = ${SIGNING_FILE_ID} /\\* Signing[.]xcconfig \\*/;" "$PROJECT_FILE" || true)"
[[ "$BASE_CONFIG_COUNT" = "2" ]] || fail "expected exactly two Signing.xcconfig base references, found ${BASE_CONFIG_COUNT}"

CONFIG_GROUP_LINKS="$(awk -v signing_id="$SIGNING_FILE_ID" '
  /\/\* Config \*\/ = \{/ { in_group = 1 }
  in_group && $1 == signing_id { count += 1 }
  in_group && /^[[:space:]]*};/ { print count + 0; exit }
' "$PROJECT_FILE")"
[[ "$CONFIG_GROUP_LINKS" = "1" ]] || fail "Config group must contain the Signing.xcconfig reference exactly once"

grep -Fqx '/Config/Signing.local.xcconfig' "${PROJECT_ROOT}/.gitignore" \
  || fail "the local signing file is not precisely listed in .gitignore"
git -C "$PROJECT_ROOT" check-ignore -q -- "$LOCAL_CONFIG" \
  || fail "the local signing file is not ignored"

for shared_config in Config/Signing.xcconfig Config/Signing.local.xcconfig.example; do
  if git -C "$PROJECT_ROOT" check-ignore -q -- "$shared_config"; then
    fail "shared signing file ${shared_config} must not be ignored"
  fi
done
if git -C "$PROJECT_ROOT" ls-files --error-unmatch -- "$LOCAL_CONFIG" >/dev/null 2>&1; then
  fail "the local signing file must not be tracked"
fi

echo "signing isolation verification passed"
