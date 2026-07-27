# Goal spec: TokenStats becomes a Usage Window gauge only

Execution target for an autonomous run on branch `refactor/architecture`
(already created, off `main`). Working directory: repository root.

This file is the run's own instructions — do not delete or rewrite it during the run.
Note it is untracked when the run begins; commit it with M0 unless told otherwise.

---

## 1. Goal

**TokenStats tracks Usage Windows and Tokens Today. It does nothing else, and the
repository contains no language but Swift.**

The run is complete when every assertion in §2 holds simultaneously.

---

## 2. Success criteria

Each is a command plus the result that counts as passing. Run them from the
repository root. All must pass on the final commit.

| # | Command | Passing result |
|---|---|---|
| S1 | `cd apps/TokenStats && xcodebuild test -project TokenStats.xcodeproj -scheme TokenStats -destination 'platform=macOS'` | `TEST SUCCEEDED` |
| S2 | `rg -n 'bun\|@repo/\|drizzle\|turbo' --glob '!*.md' --glob '!.git/**'` | no matches |
| S3 | `fd -e ts -e tsx -e js -e json --glob '!apps/TokenStats/**' --glob '!.git/**' . packages apps plugins 2>/dev/null` | no output (paths absent entirely) |
| S4 | `rg -n 'SessionStore\|SessionsModel\|SessionsView\|HookInstaller\|GlassTabBar' apps/TokenStats` | no matches |
| S5 | `rg -c 'case \.claudeCode' apps/TokenStats/TokenStats` | at most **1** file (the registry) |
| S6 | `git log --oneline main..HEAD` | 6 commits, one per milestone, in M0–M5 order |
| S7 | `xcodebuild -project apps/TokenStats/TokenStats.xcodeproj -list` | parses without error |
| S8 | `ls apps/TokenStats/TokenStats/*.swift` | no output — every source file lives in a subgroup |

**S9 (manual, run last, requires a human):** launch the app; the popover shows the
Tokens Today hero and one section per Coding Agent with no tab bar; each of the three
gauge styles renders; signing out and back in works for **both** Coding Agents.

---

## 3. Invariants

These must hold **after every milestone**, not just at the end. A milestone that
breaks one is not done.

- **I1** — S1 passes. The test suite is green at every commit.
- **I2** — Usage Window fetch, parse, refresh scheduling, and gauge rendering behave
  exactly as before. This refactor changes structure, never behaviour.
- **I3** — Tokens Today produces the same numbers from the same transcript files.
- **I4** — Persisted user state is untouched: Keychain OAuth tokens, the appearance
  `UserDefaults` keys, the onboarding-completed flag, and the last-known usage JSON
  cache all keep their existing keys and formats. A user upgrading loses nothing and
  reconnects nothing.
- **I5** — The menu-bar label format is unchanged.
- **I6** — Each milestone is exactly one commit, revertible on its own.

---

## 4. Milestones

Strictly ordered. Do not begin a milestone until the previous one's exit gate passes.

### M0 — Test safety net

**Goal:** the Swift suite runs on demand and in CI.

- Add a `test` script to the app's `package.json` invoking `xcodebuild test` against
  the existing shared scheme (its `TestAction` is already wired to `TokenStatsTests`).
- Add a CI workflow running that test on push and pull request.

**Exit gate:** S1 passes locally; the new workflow file is valid YAML.

**Note:** the release workflow is *already red* on `main` and stays red until M1.
That is expected. Do not attempt to fix it here — M1 fixes it by deletion.

### M1 — Delete Sessions tracking and all TypeScript

**Goal:** the product is usage-only and the release pipeline is repaired.

Order within the commit matters — do the rescue first:

1. **Rescue before deleting.** `realHomeDirectory()` currently lives on the sessions
   database reader and is still needed by the Tokens Today model. Move it to a new
   `Support/HomeDirectory.swift` and repoint its callers. (`TokenUsage` needs no
   rescue — it already lives with the transcript reader, which survives.)
2. Delete the Swift files for the Sessions feature: the database reader, its view
   model, its view, its domain types, the hook installer, the tab bar (nothing left to
   switch between), and the hook installer's test file.
3. Trim the survivors: remove the hooks step from onboarding (its install row, the
   install/uninstall/status-refresh methods, the detection banner, the bun-availability
   gate, and the background poll task), reducing four steps to three; remove tab
   switching and the sessions model from the popover; drop the sessions model from the
   app delegate.
4. Delete outside the app: the hook CLI, the terminal viewer, all four TypeScript
   packages, both plugins, both marketplace manifests, the task-runner config, the root
   `package.json`, the lockfile, the generator directory, and the plugin release
   workflow.
5. **Remove the Xcode Run Script build phase** that copies `agent-sessions-cli.js` into
   the app bundle. This is the change that repairs the release.
6. Docs: rewrite the README for one product; delete the multi-context map; drop the
   removed product's terms from the app's `CONTEXT.md`; add an ADR stating TokenStats
   tracks usage only and explicitly superseding the two ADRs belonging to the removed
   hook system (supersede — do not delete them).
7. Delete `docs/superpowers/`. All seven files there describe things this milestone
   removes: three workspace-generator designs plus their implementation plans (the
   generators scaffold TypeScript packages and go with the generator directory), and
   the terminal viewer's concurrency design. **Do not delete `docs/specs/` — this spec
   lives there.**

**Exit gate:** S1, S2, S3, S4, S7 all pass.

### M2 — File layering

**Goal:** source is grouped by concern; no file sits at the group root.

Pure `git mv` into: `App/`, `Agents/` (with `ClaudeCode/` and `Codex/` subgroups),
`Usage/`, `Tokens/`, `Onboarding/`, `Settings/`, `Support/`, `DesignSystem/`. Mirror
the structure under the test target.

The Xcode project uses filesystem-synchronised groups with no membership exceptions,
so **this requires zero project-file edits**. If you find yourself editing
`project.pbxproj` in this milestone, stop — see §6.

**Exit gate:** S1, S7, S8 pass. `git show --stat` for this commit shows renames only,
no content changes.

### M3 — Split oversized views

**Goal:** no view file over ~250 lines; the sign-in controls exist once.

- Split the onboarding view into chrome-plus-navigation and one file per remaining step.
- Split the settings view into its shell, its section enum, and one file per pane.
- Split the gauge views into the content model, the circular gauge, the bar gauge, and
  the cluster.
- Unify the duplicated sign-in controls — Settings and onboarding hold the same switch,
  buttons, and paste-code field differing only in font — into one control parameterised
  by agent and font, in the design-system group. Do the same for the duplicated
  connection-status presentation.
- Move the agent icon badge and status badge into the design-system group.

**Exit gate:** S1 passes. No behavioural diff — this is extraction only.

### M4 — Coding Agent registry

**Goal:** every per-agent fact is declared once; S5 holds.

Introduce a protocol describing what varies per Coding Agent and a registry with one
conformance per agent:

```swift
protocol CodingAgentIntegration {
    var id: CodingAgentID { get }
    var displayName: String { get }
    var shortLabel: String { get }         // compact menu-bar label
    var brand: AgentBrand { get }          // asset name + tint
    var auth: any AgentAuthSession { get }
    var signInStyle: SignInStyle { get }   // .pasteCode | .loopback
    var gaugeLayout: GaugeLayout { get }   // window labels, emphasis, sizing
    var transcriptRoot: String { get }     // feeds the Tokens Today scan
    func makeProvider() -> UsageProvider
}
```

Then convert the call sites. **The known branch sites are exactly these ten** — the
usage model's short-label map, provider map, sign-out, and signed-in check; the
settings pane's sign-in controls, badge asset, and badge tint; the popover section's
gauge cluster choice; onboarding's sign-in controls; and the agent id's display name.
Additionally, the Tokens Today model's hardcoded scan-roots array must come from the
registry. If you find an eleventh branch site, see §6.

Also extract the shared auth core: the two per-agent auth sessions duplicate token
caching, the signed-in check, sign-out, and the refresh-if-expired path; only login
differs. Extract the shared half behind `AgentAuthSession` **with the clock injected**,
and leave each agent its own login. Do **not** merge the two OAuth clients — they
differ substantively.

**New tests required in this milestone:**
- A table-driven test walking every registered Coding Agent and asserting its published
  facts (display name, compact label, sign-in style, gauge layout labels and emphasis,
  transcript root). Follow the style of the existing reducer tests.
- Tests for the shared auth core with an injected clock: an unexpired token is returned
  as-is; an expired token triggers exactly one refresh; a failed refresh surfaces an
  error rather than a silent signed-out state. Follow the style of the existing refresh
  policy tests, which already inject time.

**Exit gate:** S1 and S5 pass, and the two new test groups exist and are green.

### M5 — Truth up the prose

**Goal:** no comment describes code that is not there.

Known stale headers to correct: the usage provider's "MVP has one conformer" (there are
two); the settings view's "its one job today is Account management" (three panes); the
onboarding view's header describing hook installation and "a three-step card"; the step
indicator's "three-segment" comment. Re-read every file header touched by M1–M4 and fix
any that now lie.

**Exit gate:** S1 passes; S6 now holds (six commits).

---

## 5. Decision rules

Pre-authorised calls. Apply these rather than stopping.

- **D1** — A surviving file references a type from a deleted file → move the type to
  `Support/`, keeping its behaviour identical. Never re-create a deleted type.
- **D2** — A test covers behaviour being deleted → delete the test with the behaviour.
  Never rewrite it to keep it passing.
- **D3** — A test covers behaviour being *moved* → move the test to mirror the new
  location, unchanged.
- **D4** — Two candidate homes exist for a file in M2 → prefer the group whose other
  members it imports from most.
- **D5** — Deleting a file leaves an unused import or a now-private helper → clean it
  up in the same commit.
- **D6** — A doc references a deleted feature → fix it in the milestone that deleted
  the feature, not in M5.
- **D7** — Compiler emits a new warning as a result of a change → fix it before the
  milestone's exit gate.

---

## 6. Stop conditions

Halt and report. Do not improvise around any of these.

- **H1** — S1 fails for a reason not explained by intentional deletion in the current
  milestone.
- **H2** — M2 appears to require editing `project.pbxproj`. The synchronised-group
  assumption is then wrong and the layering plan needs rethinking. (M1 *does* legitimately
  edit that file, once, to remove the Run Script phase — that is the only expected edit
  in the whole run.)
- **H3** — `project.pbxproj` fails to parse after an edit (S7).
- **H4** — An eleventh per-agent branch site appears in M4 that is not in the known list
  of ten. Report where it is; do not silently fold it in.
- **H5** — Any change would alter what the user sees: gauge visuals, menu-bar label
  format, Tokens Today figures, or persisted-state keys (I2–I5).
- **H6** — The auth extraction in M4 cannot preserve behaviour for both agents without
  changing one of their login flows.
- **H7** — A deletion in M1 turns out to have a consumer not listed in this spec.

---

## 7. Non-goals

Do not do these, even if they look adjacent and cheap.

- Replacing session tracking in any form — no spool, no Core Data, no alternative store.
- Merging the two OAuth clients.
- Adding a third Coding Agent.
- Flattening the repository to a single Xcode project at its root; the app keeps its
  current path so history stays continuous.
- Changing gauge visuals, appearance settings, the menu-bar label, or the Tokens Today
  calculation.
- Touching notarisation or signing beyond removing the build phase that breaks it.
- Publishing anything to the issue tracker.

---

## 8. Context the run needs

- The release on `main` is currently failing with `hook CLI bundle missing` — that is
  the pre-existing breakage M1 repairs. It is not caused by this branch.
- Seven issues covering the deleted tracking-hook design were closed as obsolete on
  2026-07-26. Do not consult or reopen them.
- Two agent-facing docs in the repo are known to be inaccurate: the issue-tracker doc
  names the wrong repository, and the triage-label doc claims labels that do not exist.
  Do not trust either. Correcting them is optional and out of the critical path.
- The domain glossary in the app's `CONTEXT.md` governs vocabulary: **Usage Window**
  (never "session" for a billing period), **Tokens Today**, **Limit**, **Coding Agent**.
  Use these terms in new code, comments, and commit messages.
- Commit messages follow the repo's existing conventional-commit style and are written
  in English.
