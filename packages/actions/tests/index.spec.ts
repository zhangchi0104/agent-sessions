import { describe, expect, it } from "@effect/vitest";
import * as Actions from "../src/index.ts";

describe("actions", () => {
  it("exports Claude Code schemas", () => {
    expect(Actions.ClaudeCode.hookEventNames).toContain("SessionStart");
  });
});
