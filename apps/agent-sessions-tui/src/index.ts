import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import {
  BoxRenderable,
  bold,
  type CliRenderer,
  createCliRenderer,
  dim,
  fg,
  green,
  type TextChunk,
  TextRenderable,
  type TextTableContent,
  TextTableRenderable,
  t,
  yellow,
} from "@opentui/core";
import { SessionsRepo } from "@repo/actions";
import { layer as databaseLayer, migrate } from "@repo/database";
import type { sessions } from "@repo/database/schema";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

type Session = typeof sessions.$inferSelect;

const DEFAULT_DB_PATH = join(homedir(), ".local", "agent-sessions", "sessions.db");

function parseArgs(argv: readonly string[]): { db: string } {
  const idx = argv.indexOf("--db");
  if (idx >= 0 && idx + 1 < argv.length) {
    const next = argv[idx + 1];
    if (next) return { db: next };
  }
  return { db: DEFAULT_DB_PATH };
}

function statusCell(status: Session["status"]): TextChunk[] {
  switch (status) {
    case "RUNNING":
      return [green(bold(status))];
    case "PENDING_APPROVAL":
      return [yellow(status)];
    case "IDLE":
      return [dim(status)];
  }
}

function buildTableContent(list: readonly Session[]): TextTableContent {
  const header: TextChunk[][] = [[bold("STATUS")], [bold("AGENT")], [bold("NAME")], [bold("DIR")], [bold("UPDATED")]];
  const rows: TextChunk[][][] = list.map((session) => [
    statusCell(session.status),
    [fg("#7dd3fc")(session.agent)],
    t`${session.sessionName}`.chunks,
    [dim(session.workingDirectory)],
    [dim(session.updatedAt.toISOString())],
  ]);
  return [header, ...rows];
}

function mountUi(renderer: CliRenderer, list: readonly Session[]): void {
  const root = new BoxRenderable(renderer, {
    flexDirection: "column",
    padding: 1,
    gap: 1,
    width: "100%",
    height: "100%",
  });

  const summary = list.length === 1 ? "1 session" : `${list.length} sessions`;
  const header = new TextRenderable(renderer, {
    content: t`${bold("@repo/agent-sessions-tui")} ${dim(`— ${summary}`)}`,
  });
  root.add(header);

  if (list.length === 0) {
    root.add(
      new TextRenderable(renderer, {
        content: t`${dim("No sessions found. Run an agent to seed the database.")}`,
      }),
    );
  } else {
    root.add(
      new TextTableRenderable(renderer, {
        content: buildTableContent(list),
        columnGap: 2,
        cellPadding: 0,
        showBorders: false,
        outerBorder: false,
        columnWidthMode: "content",
      }),
    );
  }

  root.add(
    new TextRenderable(renderer, {
      content: t`${dim("Press q or Ctrl+C to quit.")}`,
    }),
  );

  renderer.root.add(root);
}

const { db } = parseArgs(process.argv.slice(2));
mkdirSync(dirname(db), { recursive: true });

const appLayer = SessionsRepo.layerDrizzle.pipe(Layer.provideMerge(databaseLayer({ filename: db })));

const loadSessions = Effect.gen(function* () {
  yield* migrate;
  const repo = yield* SessionsRepo;
  return yield* repo.listSessions({});
}).pipe(Effect.provide(appLayer));

const list = await Effect.runPromise(loadSessions).catch((error: unknown) => {
  process.stderr.write(`\nError loading sessions: ${String(error)}\n`);
  process.exit(1);
});

const renderer = await createCliRenderer({ exitOnCtrlC: true });
mountUi(renderer, list);
renderer.start();

renderer.keyInput.on("keypress", (key) => {
  if (key.name === "q") {
    renderer.destroy();
    process.exit(0);
  }
});
