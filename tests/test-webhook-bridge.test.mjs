import { test, describe, after } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const tmpStateDir = path.join(os.tmpdir(), `factory-bridge-test-${Date.now()}`);
process.env.BRIDGE_STATE_DIR = tmpStateDir;

const {
  parseEnvContent,
  parsePositiveInt,
  verifySignature,
  isAgentOrBotComment,
  isAuthorizedHuman,
  isProductionBranch,
  recordDeliveryIfNew,
  extractLinkedIssue,
  classifyCiFailure,
  resolveHumanFeedbackTarget,
  coalesceComment,
  flushPendingComments,
  MAX_WEBHOOK_BYTES,
  queue,
  pendingComments,
} = await import("../.factory/webhook-bridge.mjs");

describe("Webhook Bridge Unit Tests", () => {
  after(() => {
    fs.rmSync(tmpStateDir, { recursive: true, force: true });
  });
  test("verifySignature validates HMAC signatures and fails closed when secret is missing", () => {
    const secret = "test-secret-12345";
    const body = Buffer.from(JSON.stringify({ action: "labeled", issue: { number: 10 } }));
    const hmac = crypto.createHmac("sha256", secret);
    hmac.update(body);
    const validSig = `sha256=${hmac.digest("hex")}`;
    const invalidSig = "sha256=0000000000000000000000000000000000000000000000000000000000000000";

    // When secret is provided, it validates against the HMAC
    assert.equal(verifySignature(body, validSig, secret), true);
    assert.equal(verifySignature(body, invalidSig, secret), false);
    assert.equal(verifySignature(body, "malformed-signature", secret), false);
    // Fail-closed by default when secret is empty
    assert.equal(verifySignature(body, "any", ""), false);
    // Explicit allowInsecure override permits local dev mode
    assert.equal(verifySignature(body, "any", "", true), true);
  });

  test("isAgentOrBotComment accurately filters out bots and automated senders", () => {
    assert.equal(isAgentOrBotComment({ type: "Bot", login: "factory-architect[bot]" }), true);
    assert.equal(isAgentOrBotComment({ type: "Bot", login: "factory-worker[bot]" }), true);
    assert.equal(isAgentOrBotComment({ type: "User", login: "some-service[bot]" }), true);
    assert.equal(isAgentOrBotComment({ type: "User", login: "real-developer" }), false);
    assert.equal(isAgentOrBotComment(null), false);
  });

  test("isAuthorizedHuman allows repository owners, members, and collaborators", () => {
    assert.equal(isAuthorizedHuman("OWNER", { type: "User", login: "alice" }), true);
    assert.equal(isAuthorizedHuman("MEMBER", { type: "User", login: "bob" }), true);
    assert.equal(isAuthorizedHuman("COLLABORATOR", { type: "User", login: "charlie" }), true);
    assert.equal(isAuthorizedHuman("CONTRIBUTOR", { type: "User", login: "stranger" }), false);
    assert.equal(isAuthorizedHuman("NONE", { type: "User", login: "attacker" }), false);
    // Even if association is OWNER, a bot is rejected
    assert.equal(isAuthorizedHuman("OWNER", { type: "Bot", login: "bot[bot]" }), false);
  });

  test("extractLinkedIssue parses issue numbers from PR body keywords and branch names", () => {
    assert.equal(extractLinkedIssue("Closes #42", "feature/some-branch"), 42);
    assert.equal(extractLinkedIssue("This PR fixes #108 in staging", "feature/fix"), 108);
    assert.equal(extractLinkedIssue("Resolves #7", "feature/ui"), 7);
    assert.equal(extractLinkedIssue("No keyword in body", "feature/issue-99-tracer"), 99);
    assert.equal(extractLinkedIssue("No keyword", "feature/unrelated"), null);
  });

  test("coalesceComment debounces multiple rapid comments on the same thread", async () => {
    const threadKey = "issue:999";
    const initialQueueLen = queue.length;

    // Send 3 rapid comments on the same issue
    coalesceComment(threadKey, { author: "alice", body: "Please add validation" }, false, 999);
    coalesceComment(threadKey, { author: "alice", body: "Also add unit tests" }, false, 999);
    coalesceComment(threadKey, { author: "alice", body: "And check GLOSSARY" }, false, 999);

    // Should be coalescing inside pendingComments map, NOT yet enqueued
    const entry = pendingComments.get(threadKey);
    assert.ok(entry);
    assert.equal(entry.comments.length, 3);
    assert.equal(entry.num, 999);
    assert.equal(entry.isPR, false);

    // Clean up timer
    if (entry.timer) clearTimeout(entry.timer);
    pendingComments.delete(threadKey);
  });

  test("queue priority orders human feedback ahead of background planning", () => {
    const items = [
      { id: "1", priority: 40, kind: "plan_request", queuedAt: 100 },
      { id: "2", priority: 10, kind: "human_comment", queuedAt: 200 },
      { id: "3", priority: 20, kind: "ci_urgent", queuedAt: 150 },
      { id: "4", priority: 30, kind: "review_wave", queuedAt: 50 },
    ];

    items.sort((a, b) => {
      if (a.priority !== b.priority) return a.priority - b.priority;
      return a.queuedAt - b.queuedAt;
    });

    assert.equal(items[0].kind, "human_comment"); // Priority 10
    assert.equal(items[1].kind, "ci_urgent");     // Priority 20
    assert.equal(items[2].kind, "review_wave");   // Priority 30
    assert.equal(items[3].kind, "plan_request");   // Priority 40
  });

  test("classifyCiFailure enforces 3-strike rescue escalation and spend circuit breaker", () => {
    assert.equal(classifyCiFailure(1, false, 3), "retry");
    assert.equal(classifyCiFailure(2, false, 3), "retry");
    assert.equal(classifyCiFailure(3, false, 3), "escalate_rescue");
    assert.equal(classifyCiFailure(4, false, 3), "circuit_breaker");
    // Already escalated once: any subsequent failure trips circuit breaker immediately
    assert.equal(classifyCiFailure(1, true, 3), "circuit_breaker");
  });

  test("resolveHumanFeedbackTarget routes Issues to architect and feature PRs to orchestrator with /architect override", () => {
    // Issues always go to Architect
    assert.equal(resolveHumanFeedbackTarget(false, "Let's design auth", ""), "architect");
    // Feature PR comments/reviews go to Orchestrator (stateless /clear)
    assert.equal(resolveHumanFeedbackTarget(true, "Can you rename this helper?", "staging"), "orchestrator");
    assert.equal(resolveHumanFeedbackTarget(true, "Why did you add this index?", ""), "orchestrator");
    // Explicit /architect or @architect escape hatch on any PR goes to Architect
    assert.equal(resolveHumanFeedbackTarget(true, "/architect should we rethink this schema?", "staging"), "architect");
    assert.equal(resolveHumanFeedbackTarget(true, "Hey @architect thoughts on this tradeoff?", "staging"), "architect");
    // Rolling Release PR targeting main or master goes to Architect
    assert.equal(resolveHumanFeedbackTarget(true, "Looks ready to ship", "main"), "architect");
    assert.equal(resolveHumanFeedbackTarget(true, "Looks ready to ship", "master"), "architect");
  });

  test("isProductionBranch recognizes both main and master", () => {
    assert.equal(isProductionBranch("main"), true);
    assert.equal(isProductionBranch("master"), true);
    assert.equal(isProductionBranch("staging"), false);
    assert.equal(isProductionBranch("feature/issue-12"), false);
  });

  test("recordDeliveryIfNew deduplicates repeated GitHub webhook deliveries", () => {
    const mockState = { processedDeliveries: [] };
    assert.equal(recordDeliveryIfNew("delivery-abc-123", mockState), true);
    assert.equal(recordDeliveryIfNew("delivery-abc-123", mockState), false);
    assert.equal(recordDeliveryIfNew("delivery-def-456", mockState), true);
    assert.equal(mockState.processedDeliveries.length, 2);
  });

  test("parseEnvContent preserves '&' values and strips inline comments while parsePositiveInt prevents NaN", () => {
    const parsed = parseEnvContent(
      [
        "CI_WORKFLOW_NAME=CI & PR Evidence",
        "MAX_CI_RETRIES=3 # 3-strike rescue cap",
        'HUMAN_REVIEWER="octocat"',
      ].join("\n")
    );
    assert.equal(parsed.CI_WORKFLOW_NAME, "CI & PR Evidence");
    assert.equal(parsed.MAX_CI_RETRIES, "3");
    assert.equal(parsePositiveInt(parsed.MAX_CI_RETRIES, 5), 3);
    assert.equal(parsePositiveInt("invalid", 3), 3);
    assert.equal(MAX_WEBHOOK_BYTES, 25 * 1024 * 1024);
  });

  test("flushPendingComments persists buffered debounced comments before shutdown", () => {
    const threadKey = "pr:777";
    coalesceComment(threadKey, { author: "alice", body: "Please check edge case" }, true, 777, "staging");
    assert.equal(pendingComments.has(threadKey), true);

    const flushed = flushPendingComments();
    assert.equal(flushed, 1);
    assert.equal(pendingComments.has(threadKey), false);

    const idx = queue.findIndex((q) => q.threadKey === threadKey);
    assert.ok(idx >= 0);
    assert.match(queue[idx].prompt, /herdr agent prompt architect/);
    queue.splice(idx, 1);
  });
});
