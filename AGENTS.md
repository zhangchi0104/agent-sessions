# Repository Guidelines

## Project Structure & Module Organization

This is a Bun-first Turborepo. `apps/agent-sessions-cli` receives Claude Code and Codex hook events; `apps/agent-sessions-tui` displays session state. Shared Effect/TypeScript logic lives in `packages/actions`; SQLite/Drizzle code and migrations live in `packages/database`. Shared configuration is under `packages/*-config`. `apps/TokenStats` is a Swift/SwiftUI macOS app with unit and UI test targets. Plugin manifests live in `plugins/`; generated plugin `bin/` bundles are release artifacts and should not be committed.

Read the nearest `AGENTS.md`, `CONTEXT.md`, `CLAUDE.md`, and `docs/adr/` before changing a bounded context.

## Build, Test, and Development Commands

- `bun install` — install all workspace dependencies (Bun 1.3.13+).
- `bun run build` — run Turbo builds, including TypeScript packages and the TokenStats release build.
- `bun run --filter '*' check` — run package Biome and TypeScript checks.
- `cd apps/agent-sessions-tui && bun run dev` — start the TUI in watch mode.
- `cd apps/agent-sessions-cli && bun run build:bundle` — rebuild the self-contained CLI into both plugins after CLI or dependency changes.
- `cd apps/TokenStats && bun run dev` — build and launch the Debug macOS app; use `bun run build` for Release.

## Coding Style & Naming Conventions

TypeScript uses Biome with two-space indentation and a 120-character line width. Run the owning package's `bun run check` before submitting. Follow existing kebab-case TypeScript filenames, camelCase functions, and PascalCase types. Swift follows Xcode conventions: four-space indentation, PascalCase types/files, and camelCase members. Keep domain logic in shared packages rather than duplicating it in CLI or UI entry points. For Effect code, follow the repository's `effect-solutions` guidance.

## Testing Guidelines

Run `cd packages/actions && bun run test` for Vitest `*.spec.ts` suites and `cd packages/database && bun run test` for Bun `*.test.ts` suites. Run TokenStats tests with `xcodebuild -project apps/TokenStats/TokenStats.xcodeproj -scheme TokenStats -destination 'platform=macOS' test`. Add focused regression tests beside the affected package; no repository-wide coverage threshold is configured.

## Commit & Pull Request Guidelines

History primarily follows Conventional Commits: `feat(TokenStats): ...`, `fix(ci): ...`, `docs: ...`. Use an imperative subject and scope it when one app or package owns the change. Pull requests should explain behavior and rationale, link the issue when applicable, list verification commands, and include screenshots for SwiftUI changes. Call out schema, hook-contract, plugin-bundle, or release-pipeline effects explicitly.

## Security & Configuration

Never commit OAuth tokens, signing/notarization credentials, or local SQLite files. Use `AGENT_SESSIONS_DB` to override the shared database path and `DATABASE_PATH` for Drizzle tooling.
