# Token storage uses the legacy keychain so the app carries no restricted entitlements

TokenStats stores its OAuth tokens (ADR-0001, ADR-0002) in the **legacy
file-based login keychain**, not the modern data-protection keychain. As a
direct consequence the app ships with an **empty entitlements file** — no
`keychain-access-groups`, no App Sandbox keys, nothing restricted. This is a
hard constraint on the shipped artifact, enforced by `scripts/build-dmg.sh`.

## Context

TokenStats is a notarized, **non-sandboxed Developer ID** menu-bar app
distributed directly as a `.dmg` (no Mac App Store, no embedded provisioning
profile). It needs to persist its own OAuth tokens privately across launches.

The original implementation used the data-protection keychain
(`kSecUseDataProtectionKeychain`), because in development the legacy keychain
re-prompts for the login-keychain password on every rebuild (the dev signature
changes each build). The data-protection keychain avoids that by granting access
via a *keychain access group* instead of an interactive ACL — but a keychain
access group requires the `keychain-access-groups` entitlement.

That entitlement is the trap. **AMFI authorizes restricted entitlements only
against an embedded provisioning profile.** A direct-distribution Developer ID
build has none, so the kernel SIGKILLs the process the instant it launches,
surfacing to the user as *"TokenStats.app can't be opened"* (launchd spawn exit
137 / POSIX 163). Crucially, `codesign --verify`, `spctl`, and notarization all
**pass** — none of them validate entitlement *authorization*; only the runtime
kernel does. So a broken build sails through CI and only dies on the user's Mac.

This bit the project **three times**:

1. App Sandbox `com.apple.security.temporary-exception.*` entitlements (added to
   reach `~/.claude` etc. under the sandbox) — SIGKILL. Fixed by dropping the
   sandbox (commit `c04930f`), which also removed `keychain-access-groups`.
2. Removing `keychain-access-groups` broke token sign-in with
   `errSecMissingEntitlement (-34018)`: the data-protection keychain grants an
   access group *only* via that entitlement, so every `SecItem*` failed. It was
   restored (commit `79a2c01`) on the stated premise that `keychain-access-groups`
   is "self-authorized by the team identifier and does not trip AMFI."
3. That premise is **empirically false** for this configuration. Re-signing the
   shipped binary and launching it shows: empty entitlements → launches;
   `keychain-access-groups` with the correct `472VSX7V86.` team prefix → SIGKILL
   (137); with a wrong prefix → SIGKILL; a harmless entitlement
   (`com.apple.security.cs.allow-jit`) → launches. Only `keychain-access-groups`
   kills it, regardless of prefix. AMFI treats it as restricted-and-unauthorized
   with no profile to authorize it against.

The two requirements were in direct conflict: the data-protection keychain needs
an entitlement that makes the app un-launchable.

## Decision

Resolve the conflict at the storage layer, not the entitlement layer: use the
**legacy login keychain** (drop `kSecUseDataProtectionKeychain`) and ship **no
restricted entitlements**.

The legacy keychain needs no entitlement. A signed, hardened-runtime Developer ID
binary with an empty entitlements file performs `SecItemAdd` / `SecItemCopyMatching`
on a generic-password item successfully (verified: status `0`, no `-34018`).
Access is governed by the item's ACL, keyed to the app's code signature:
TokenStats creates and reads its own item, so it is on that item's ACL and never
prompts on its own reads, and the **released build's signature is stable**, so
the grant persists across launches.

`scripts/build-dmg.sh` reads the entitlements back out of the **signed** app and
**aborts the release** if any restricted key (`keychain-access-groups`, sandbox
`temporary-exception`, `app-sandbox`) is present — turning "passes codesign but
the kernel kills it" into a build failure instead of a user-facing one.

## Consequences

- **Positive:** the app launches. No restricted entitlements means no AMFI kill
  surface at all, and the regression that recurred three times is now caught in
  CI on the actual shipped binary rather than by a user double-clicking the app.
  Token sign-in works without `-34018` because the legacy keychain needs no
  access group.
- **Negative:** during **local development**, a debug rebuild may re-prompt once
  for the login-keychain password, because the dev signature changes per build
  and the item's ACL no longer matches. This was the original motivation for the
  data-protection keychain. It is a dev-only annoyance and does not affect the
  shipped, stably-signed app; we accept it.
- The only way to keep the data-protection keychain would be to embed a
  Developer ID provisioning profile that authorizes the keychain access group.
  That means managing and renewing a profile in CI for a single generic-password
  item — rejected as disproportionate. If TokenStats ever needs to *share*
  keychain items with a sibling app (a genuine access-group use case), revisit
  this and take on the provisioning profile then.
