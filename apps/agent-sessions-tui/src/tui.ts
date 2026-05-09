import {
  BoxRenderable,
  bold,
  type CliRenderer,
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
import type { sessions } from "@repo/database/schema";

type Session = typeof sessions.$inferSelect;

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

export function mountUi(renderer: CliRenderer, list: readonly Session[]): void {
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
