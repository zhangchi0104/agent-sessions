#!/usr/bin/env bun
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { type ApplyHookEventInput, type HookAgent, SessionsRepo } from "@repo/actions";
import { layer as databaseLayer, ensureSchema, resolveDatabasePath } from "@repo/database";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

const AGENT_BY_COMMAND: Record<string, HookAgent> = {
  claude: "ClaudeCode",
  codex: "Codex",
};

const USAGE = "usage: agent-sessions-cli <claude|codex> <HookEventName>   (hook payload on stdin)";

/**
 * Records a single hook invocation. Never throws to the caller: a hook must not
 * break the agent, so every failure is logged to stderr and the process exits 0.
 */
async function main(): Promise<void> {
  const [command, eventArg] = process.argv.slice(2);
  const agent = command ? AGENT_BY_COMMAND[command] : undefined;
  if (!agent) {
    process.stderr.write(`[agent-sessions-cli] unknown command: ${command ?? "(none)"}\n${USAGE}\n`);
    return;
  }

  const eventName = eventArg ?? process.env.AGENT_SESSIONS_HOOK_EVENT ?? "unknown";
  const rawPayload = await Bun.stdin.text();

  const databasePath = resolveDatabasePath();
  mkdirSync(dirname(databasePath), { recursive: true });

  const appLayer = SessionsRepo.layerDrizzle.pipe(Layer.provideMerge(databaseLayer({ filename: databasePath })));

  const input: ApplyHookEventInput = {
    agent,
    eventName,
    rawPayload,
    fallbackCwd: process.cwd(),
    now: new Date(),
  };

  const program = Effect.gen(function* () {
    yield* ensureSchema;
    const repo = yield* SessionsRepo;
    yield* repo.applyHookEvent(input);
  }).pipe(Effect.provide(appLayer));

  await Effect.runPromise(program);
}

main()
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`[agent-sessions-cli] failed to record hook event: ${message}\n`);
  })
  .finally(() => {
    process.exit(0);
  });
