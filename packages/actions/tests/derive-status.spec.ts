import { describe, expect, it } from "@effect/vitest";
import { deriveStatus } from "../src/helpers/derive-status.ts";

describe("deriveStatus", () => {
  describe("ClaudeCode", () => {
    it("maps working events to RUNNING", () => {
      for (const event of ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch", "SubagentStart"]) {
        expect(deriveStatus("ClaudeCode", event)).toBe("RUNNING");
      }
    });

    it("maps PermissionRequest and permission_prompt notifications to PENDING_APPROVAL", () => {
      expect(deriveStatus("ClaudeCode", "PermissionRequest")).toBe("PENDING_APPROVAL");
      expect(deriveStatus("ClaudeCode", "Notification", { notificationType: "permission_prompt" })).toBe(
        "PENDING_APPROVAL",
      );
    });

    it("maps Stop, SessionEnd and idle_prompt notifications to IDLE", () => {
      expect(deriveStatus("ClaudeCode", "Stop")).toBe("IDLE");
      expect(deriveStatus("ClaudeCode", "SessionEnd")).toBe("IDLE");
      expect(deriveStatus("ClaudeCode", "Notification", { notificationType: "idle_prompt" })).toBe("IDLE");
    });

    it("treats other notifications and unknown events as log-only", () => {
      expect(deriveStatus("ClaudeCode", "Notification", { notificationType: "auth_success" })).toBeNull();
      expect(deriveStatus("ClaudeCode", "Notification")).toBeNull();
      expect(deriveStatus("ClaudeCode", "SessionStart")).toBeNull();
      expect(deriveStatus("ClaudeCode", "SubagentStop")).toBeNull();
    });
  });

  describe("Codex", () => {
    it("maps working events to RUNNING", () => {
      for (const event of ["UserPromptSubmit", "PreToolUse", "PostToolUse"]) {
        expect(deriveStatus("Codex", event)).toBe("RUNNING");
      }
    });

    it("maps any Notification to PENDING_APPROVAL (no PermissionRequest hook)", () => {
      expect(deriveStatus("Codex", "Notification")).toBe("PENDING_APPROVAL");
      expect(deriveStatus("Codex", "Notification", { notificationType: "whatever" })).toBe("PENDING_APPROVAL");
    });

    it("maps Stop and SessionEnd to IDLE", () => {
      expect(deriveStatus("Codex", "Stop")).toBe("IDLE");
      expect(deriveStatus("Codex", "SessionEnd")).toBe("IDLE");
    });

    it("does not promote SubagentStart (Claude-only) for Codex", () => {
      expect(deriveStatus("Codex", "SubagentStart")).toBeNull();
      expect(deriveStatus("Codex", "SessionStart")).toBeNull();
    });
  });
});
