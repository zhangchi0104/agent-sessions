# Usage data comes from an independent OAuth login, not local files

TokenStats needs Claude Code's authoritative usage figure (percent of the 5-hour and weekly Usage Windows consumed, and reset times). We read it from the same OAuth-authenticated usage endpoint Claude Code uses, and TokenStats performs its **own** OAuth login rather than reusing Claude Code's stored credentials.

## Considered Options

- **Local-file token sum** (`~/.claude/projects/**/*.jsonl`): only an *estimate* — the real 5-hour limit is computed server-side with weighting we can't reproduce. Rejected as the source of truth.
- **Reuse Claude Code's Keychain token** (`Claude Code-credentials`): triggers macOS Keychain ACL prompts, and — worse — refreshing the shared OAuth token *rotates* it, which can silently break the user's real Claude Code session. Rejected.
- **Independent OAuth login** (chosen): TokenStats logs in separately and stores its own token in its own Keychain item. Costs a second login, but never interferes with Claude Code's credentials.

## Consequences

- Depends on an unofficial, undocumented usage endpoint — may break when Anthropic changes it. This is accepted fragility for the MVP.
- The OAuth client used is Anthropic's; this is not an officially sanctioned third-party integration. Revisit if an official usage API appears.
- **Login uses a paste-the-code flow, not a URL-scheme callback.** Because we use Anthropic's OAuth client (which we don't control), a custom redirect URI like `tokenstats://callback` almost certainly isn't an allowed callback. The browser-based authorization-code + PKCE flow therefore surfaces a code the user pastes into TokenStats — mirroring Claude Code's own login. Revisit only with a sanctioned client.
