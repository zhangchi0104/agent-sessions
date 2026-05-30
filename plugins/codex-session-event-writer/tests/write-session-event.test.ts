import { Database } from "bun:sqlite";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "bun:test";

const pluginRoot = fileURLToPath(new URL("..", import.meta.url));
const tempPaths = new Set<string>();

afterEach(() => {
  for (const path of tempPaths) {
    rmSync(path, { force: true, recursive: true });
  }
  tempPaths.clear();
});

describe("codex-session-event-writer plugin", () => {
  it("writes a hook event when copied outside the repository", async () => {
    const tempRoot = join(
      tmpdir(),
      `codex-session-event-writer-${crypto.randomUUID()}`,
    );
    const standalonePluginRoot = join(tempRoot, "codex-session-event-writer");
    const databasePath = join(tempRoot, "events", "local.db");
    tempPaths.add(tempRoot);

    mkdirSync(dirname(standalonePluginRoot), { recursive: true });
    cpSync(pluginRoot, standalonePluginRoot, { recursive: true });

    const proc = Bun.spawn(["bash", "scripts/write-session-event.sh", "UserPromptSubmit"], {
      cwd: standalonePluginRoot,
      env: {
        ...process.env,
        DATABASE_PATH: databasePath,
      },
      stderr: "pipe",
      stdin: "pipe",
      stdout: "pipe",
    });

    proc.stdin.write(
      JSON.stringify({
        session_id: "standalone-session",
        hook_event_name: "UserPromptSubmit",
        cwd: "/tmp/standalone",
      }),
    );
    proc.stdin.end();

    const [exitCode, stderr] = await Promise.all([
      proc.exited,
      new Response(proc.stderr).text(),
    ]);

    expect(stderr).toBe("");
    expect(exitCode).toBe(0);

    const database = new Database(databasePath, { readonly: true });
    try {
      const row = database
        .query("select session_id, event_name, cwd from session_events")
        .get() as Record<string, unknown>;

      expect(row).toEqual({
        session_id: "standalone-session",
        event_name: "UserPromptSubmit",
        cwd: "/tmp/standalone",
      });
    } finally {
      database.close();
    }
  });
});
