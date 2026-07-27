# 5. TokenStats tracks usage only

Date: 2026-07-26

Status: Accepted; language constraint amended by
[ADR-0006](0006-native-windows-companion.md)

Supersedes [agent-sessions ADR-0001 — Bundled-JS hook CLI run by bun](../../../../docs/adr/0001-bundled-js-hook-cli.md)
and [agent-sessions ADR-0002 — No ENDED status](../../../../docs/adr/0002-no-ended-status.md).

## Context

This repository grew two products at once. TokenStats showed **Usage Windows**
and **Tokens Today**. Alongside it, a session-tracking system answered "which
agent is waiting on me?": lifecycle hooks in a Claude Code plugin and a Codex
plugin invoked a bundled CLI (ADR-0001) that derived a three-value Status
(ADR-0002) into a shared SQLite database, read by a terminal viewer and by a
Sessions tab in the TokenStats popover.

That apparatus cost the repository four TypeScript packages, two apps, two
plugins, two marketplace manifests, a workspace generator, and a JavaScript
task runner — and it reached into the Xcode project, which copied the CLI
bundle into the app at build time. The bundle is gitignored on source
branches, so that build phase failed on any checkout that had not built it
first: the TokenStats release pipeline was broken by a dependency on the other
product.

Two facts decided this:

- **Nobody used the Sessions tab.** It was the one surface in TokenStats that
  read the hook-written database.
- **Nothing else needed hooks.** Usage Windows come from each agent's own usage
  endpoint over its own OAuth session; Tokens Today comes from scanning the
  agents' local transcript files. Neither reads the database, and neither ever
  did.

So the entire cross-language apparatus existed to serve one unused feature.

## Decision

**TokenStats tracks Usage Windows and Tokens Today. It does nothing else, and
this repository contains no language but Swift.**

Deleted: the Sessions tab and its database reader, view model, and domain
types; the in-app hook installer and the onboarding step that drove it; the
hook CLI; the terminal viewer; all four TypeScript packages; both plugins; both
marketplace manifests; the workspace generator; the task-runner config and root
manifest; the plugin release workflow; and the Xcode Run Script phase that
copied the CLI bundle into the app.

Not replaced. There is no spool directory, no Core Data store, and no
alternative session store — the feature is gone, not re-implemented.

ADR-0001 and ADR-0002 are superseded rather than deleted: they record decisions
that were correct for a system this repository no longer builds, and the
reasoning in them is the reason it was worth building at all.

[ADR-0003](0003-tokens-today-stays-an-in-process-estimate.md) is unaffected in
substance — Tokens Today is still an in-process, in-memory estimate driven by
an FSEvents watch — though its closing scope note refers to a Sessions tab poll
that no longer exists.

## Consequences

- **Positive:** the release pipeline is repaired, because the build phase that
  depended on a gitignored artifact from a deleted app is gone. One language,
  one toolchain, one test command. A contributor reads Swift and nothing else.
- **Positive:** the app's own dependency surface shrinks to the two usage
  endpoints and the local transcript files — no shared database, no hook
  processes, no `bun` on `PATH`.
- **Negative:** "which agent is waiting on me?" is no longer answered anywhere
  in this repository. Reinstating it means rebuilding the hook path from
  scratch; ADR-0001 and ADR-0002 record what that cost last time.
- **Negative:** users who installed the session-event-writer plugins keep a
  hook pointing at a CLI this repository no longer publishes. They must remove
  the plugins themselves — the app can no longer do it for them, since the
  installer was part of what was deleted.
