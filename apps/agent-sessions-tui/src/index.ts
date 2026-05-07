import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { SessionsRepo } from "@repo/actions";
import { layer as databaseLayer, migrate } from "@repo/database";
import type { sessions } from "@repo/database/schema";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

type Session = typeof sessions.$inferSelect;

const ESC = "\x1B[";
const stdin = process.stdin;
const stdout = process.stdout;

const DEFAULT_DB_PATH = join(homedir(), ".local", "agent-sessions", "sessions.db");

function parseArgs(argv: readonly string[]): { db: string } {
  const idx = argv.indexOf("--db");
  if (idx >= 0 && idx + 1 < argv.length) {
    const next = argv[idx + 1];
    if (next) return { db: next };
  }
  return { db: DEFAULT_DB_PATH };
}

function pad(value: string, width: number): string {
  if (value.length === width) return value;
  if (value.length > width) return `${value.slice(0, Math.max(0, width - 1))}…`;
  return value + " ".repeat(width - value.length);
}

const COLUMNS = [
  { key: "status", header: "STATUS", width: 18 },
  { key: "agent", header: "AGENT", width: 12 },
  { key: "sessionName", header: "NAME", width: 28 },
  { key: "workingDirectory", header: "DIR", width: 40 },
  { key: "updatedAt", header: "UPDATED", width: 24 },
] as const;

export function formatHeader(): string {
  return COLUMNS.map((c) => pad(c.header, c.width)).join("  ");
}

export function formatSession(session: Session): string {
  return [
    pad(session.status, 18),
    pad(session.agent, 12),
    pad(session.sessionName, 28),
    pad(session.workingDirectory, 40),
    pad(session.updatedAt.toISOString(), 24),
  ].join("  ");
}

function render(sessions: readonly Session[]): void {
  stdout.write(`${ESC}2J${ESC}H`);
  stdout.write(`@repo/agent-sessions-tui — ${sessions.length} session(s)\n\n`);
  if (sessions.length === 0) {
    stdout.write("No sessions found.\n\n");
  } else {
    stdout.write(`${formatHeader()}\n`);
    for (const session of sessions) {
      stdout.write(`${formatSession(session)}\n`);
    }
    stdout.write("\n");
  }
  stdout.write("Press q or Ctrl+C to quit.\n");
}

function cleanup(): void {
  if (stdin.isTTY) stdin.setRawMode(false);
  stdin.pause();
  stdout.write(`${ESC}?25h${ESC}0m\n`);
}

const { db } = parseArgs(process.argv.slice(2));
mkdirSync(dirname(db), { recursive: true });

const appLayer = SessionsRepo.layerDrizzle.pipe(Layer.provideMerge(databaseLayer({ filename: db })));

const program = Effect.gen(function* () {
  yield* migrate;
  const repo = yield* SessionsRepo;
  const list = yield* repo.listSessions({});

  render(list);

  if (stdin.isTTY) {
    stdin.setEncoding("utf8");
    stdin.setRawMode(true);
    stdin.resume();
    stdout.write(`${ESC}?25l`);

    stdin.on("data", (key) => {
      if (key === "q" || key === "") {
        cleanup();
        process.exit(0);
      }
    });
  }
}).pipe(
  Effect.catch((error) =>
    Effect.sync(() => {
      stdout.write(`\nError: ${String(error)}\n`);
      process.exit(1);
    }),
  ),
  Effect.provide(appLayer),
);

Effect.runPromise(program);
