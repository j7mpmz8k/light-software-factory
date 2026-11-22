#!/usr/bin/env node
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const isDirectRun = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

const execFileAsync = promisify(execFile);

const candidateEnvFiles = [
  process.env.BRIDGE_ENV_FILE,
  "/run/factory-config/bridge.env",
  path.resolve("/workspace/.factory/.env"),
  path.resolve("/workspace/.env"),
].filter(Boolean);

for (const envFile of candidateEnvFiles) {
  if (fs.existsSync(envFile)) {
    for (const line of fs.readFileSync(envFile, "utf8").split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx > 0) {
        const key = trimmed.slice(0, idx).trim();
        const val = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
        if (!process.env[key]) process.env[key] = val;
      }
    }
    break;
  }
}

function detectHumanReviewer() {
  if (process.env.HUMAN_REVIEWER) return process.env.HUMAN_REVIEWER.replace(/^@/, "").trim();
  try {
    const codeowners = fs.readFileSync("/workspace/.github/CODEOWNERS", "utf8");
    const m = codeowners.match(/@([A-Za-z0-9-]+)/);
    return m ? m[1] : "";
  } catch {
    return "";
  }
}

const PORT = Number(process.env.WEBHOOK_PORT || 8787);
const BIND_HOST = process.env.WEBHOOK_BIND_HOST || "0.0.0.0";
const SECRET = process.env.GITHUB_WEBHOOK_SECRET || "";
const ARCHITECT_PANE = process.env.ARCHITECT_PANE || "architect";
const ORCHESTRATOR_PANE = process.env.ORCHESTRATOR_PANE || "orchestrator";
const FABLE_PANE = process.env.FABLE_PANE || "specialist-fable";
const MAX_CI_RETRIES = Number(process.env.MAX_CI_RETRIES || 3);
const CI_WORKFLOW_NAME = process.env.CI_WORKFLOW_NAME || "CI & PR Evidence";
const PROJECT_NUMBER = process.env.PROJECT_NUMBER || "";
const REPO_FULL = process.env.FACTORY_REPO || "";
const HUMAN_REVIEWER = detectHumanReviewer();

const STATE_DIR = path.resolve(
  process.env.BRIDGE_STATE_DIR || "/home/factory/.config/herdr/bridge-state"
);
const RETRY_STATE_FILE = path.join(STATE_DIR, "retry-state.json");
const QUEUE_STATE_FILE = path.join(STATE_DIR, "architect-queue.json");
const COMMENT_COALESCE_MS = Number(process.env.COMMENT_COALESCE_MS || 8_000);
const ARCHITECT_WAIT_TIMEOUT_MS = Number(process.env.ARCHITECT_WAIT_TIMEOUT_MS || 300_000);
const STALL_WATCHDOG_INTERVAL_MS = Number(process.env.STALL_WATCHDOG_INTERVAL_MS || 900_000);
const STALL_THRESHOLD_MS = Number(process.env.STALL_THRESHOLD_MS || 2_700_000);

const PRIORITY = {
  HUMAN_COMMENT: 10,
  CI_URGENT: 20,
  REVIEW_WAVE: 30,
  PLAN_READY: 40,
};

const BOARD_SYNC_SCRIPT = path.resolve("/workspace/.factory/board-sync.sh");
const SUB_ISSUE_SCRIPT = path.resolve("/workspace/.factory/sub-issue.sh");
const SYNC_HUB_SCRIPT = path.resolve("/workspace/.factory/sync-hub.sh");
const FACTORY_GH = path.resolve("/workspace/.factory/bin/gh");
const RELEASE_PR_SCRIPT = path.resolve("/workspace/.factory/release-pr.sh");

const ARCHITECT_EXEC_ENV = {
  ...process.env,
  FACTORY_ROLE: "architect",
};

// Fix D4: Do not drop comments quoting **[Architect]**; filter by sender bot status
function isAgentOrBotComment(sender = {}) {
  const login = String(sender?.login || "").toLowerCase();
  return sender?.type === "Bot" || login.endsWith("[bot]");
}

// Fix B1: Ensure comment is authored by a repo collaborator/owner, not an unauthenticated stranger
function isAuthorizedHuman(authorAssociation, sender = {}) {
  if (isAgentOrBotComment(sender)) return false;
  const TRUSTED_ROLES = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);
  return TRUSTED_ROLES.has(String(authorAssociation || "").toUpperCase());
}

function extractLinkedIssue(body = "", headBranch = "") {
  const bodyMatch = String(body || "").match(/(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/i);
  if (bodyMatch) return Number(bodyMatch[1]);
  const branchMatch = String(headBranch || "").match(/issue-(\d+)/i);
  return branchMatch ? Number(branchMatch[1]) : null;
}

async function ghAsArchitect(args, timeout = 20_000) {
  return execFileAsync(FACTORY_GH, args, { env: ARCHITECT_EXEC_ENV, timeout });
}

async function syncHubWorkspace() {
  if (!fs.existsSync(SYNC_HUB_SCRIPT)) return;
  try {
    await execFileAsync(SYNC_HUB_SCRIPT, [], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 30_000,
    });
  } catch (err) {
    console.warn("[bridge] Non-fatal sync-hub.sh warning:", err.message);
  }
}

async function syncBoardField(targetRef, fieldName, value) {
  if (!PROJECT_NUMBER || !targetRef) return;
  if (!fs.existsSync(BOARD_SYNC_SCRIPT)) return;
  try {
    await execFileAsync(BOARD_SYNC_SCRIPT, [String(targetRef), String(fieldName), String(value)], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 20_000,
    });
  } catch (err) {
    console.warn(`[bridge] Non-fatal board sync warning for ${targetRef}:`, err.message);
  }
}

async function surfaceAwaitingApproval(prNumber, linkedIssue, isReleasePr = false) {
  try {
    await ghAsArchitect(["pr", "edit", String(prNumber), "--add-label", "human-gate"]).catch(() => {});
    if (HUMAN_REVIEWER) {
      await ghAsArchitect(["pr", "edit", String(prNumber), "--add-reviewer", HUMAN_REVIEWER]).catch(() => {});
    }
    if (linkedIssue) {
      await ghAsArchitect(["issue", "edit", String(linkedIssue), "--add-label", "human-gate"]).catch(() => {});
      await syncBoardField(linkedIssue, "Status", "Awaiting Approval");
    }
    if (isReleasePr || !linkedIssue) {
      await syncBoardField(`pr:${prNumber}`, "Status", "Awaiting Approval");
    }
  } catch (err) {
    console.warn(`[bridge] Non-fatal Awaiting Approval sync warning for PR #${prNumber}:`, err.message);
  }
}

async function getParentEpic(issueNumber) {
  if (!issueNumber || !fs.existsSync(SUB_ISSUE_SCRIPT)) return null;
  try {
    const { stdout } = await execFileAsync(SUB_ISSUE_SCRIPT, ["parent", String(issueNumber)], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 15_000,
    });
    const parsed = JSON.parse(stdout.trim() || "null");
    return parsed && parsed.number ? parsed : null;
  } catch {
    return null;
  }
}

async function getSubIssueSummary(issueNumber) {
  if (!issueNumber || !fs.existsSync(SUB_ISSUE_SCRIPT)) {
    return { total: 0, completed: 0, percent_completed: 0 };
  }
  try {
    const { stdout } = await execFileAsync(SUB_ISSUE_SCRIPT, ["summary", String(issueNumber)], {
      env: ARCHITECT_EXEC_ENV,
      timeout: 15_000,
    });
    return JSON.parse(stdout.trim() || "{}");
  } catch {
    return { total: 0, completed: 0, percent_completed: 0 };
  }
}

async function inspectPrMeta(prNumber, headBranch = "") {
  try {
    const { stdout } = await ghAsArchitect([
      "pr",
      "view",
      String(prNumber),
      "--json",
      "body,labels,mergeable,mergeStateStatus,headRefName,baseRefName,statusCheckRollup",
    ]);
    const pr = JSON.parse(stdout);
    const labels = (pr.labels || []).map((l) => l.name);
    const checks = pr.statusCheckRollup || [];
    const gateCheck = checks.find((c) => (c.name || c.context) === "human-gate-guard");
    const gateState = gateCheck
      ? String(gateCheck.conclusion || gateCheck.state || gateCheck.status || "").toUpperCase()
      : "UNKNOWN";
    const humanGateBlocked = gateCheck ? gateState !== "SUCCESS" : false;

    return {
      linkedIssue: extractLinkedIssue(pr.body, pr.headRefName || headBranch),
      labels,
      hasFableEscalated: labels.includes("fable-escalated"),
      hasHumanGateLabel: labels.includes("human-gate"),
      humanGateBlocked,
      isConflicting: pr.mergeable === "CONFLICTING" || pr.mergeStateStatus === "DIRTY",
      headRefName: pr.headRefName || headBranch,
      baseRefName: pr.baseRefName || "",
    };
  } catch {
    return {
      linkedIssue: extractLinkedIssue("", headBranch),
      labels: [],
      hasFableEscalated: false,
      hasHumanGateLabel: false,
      humanGateBlocked: false,
      isConflicting: false,
      headRefName: headBranch,
      baseRefName: "",
    };
  }
}

function writeJsonAtomic(filePath, data) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tmp = `${filePath}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), "utf8");
  fs.renameSync(tmp, filePath);
}

function loadRetryState() {
  try {
    if (fs.existsSync(RETRY_STATE_FILE)) {
      return JSON.parse(fs.readFileSync(RETRY_STATE_FILE, "utf8"));
    }
  } catch {}
  return { prRetries: {}, stallAlerts: {}, processedDeliveries: [] };
}

function saveRetryState(state) {
  writeJsonAtomic(RETRY_STATE_FILE, state);
}

function loadQueueFromDisk() {
  try {
    if (fs.existsSync(QUEUE_STATE_FILE)) {
      const q = JSON.parse(fs.readFileSync(QUEUE_STATE_FILE, "utf8"));
      if (Array.isArray(q)) return q;
    }
  } catch {}
  return [];
}

function saveQueueToDisk() {
  writeJsonAtomic(QUEUE_STATE_FILE, queue);
}

const queue = loadQueueFromDisk();
const pendingComments = new Map();
let processing = false;
let currentItemSummary = null;
const DEAD_LETTER_FILE = path.join(STATE_DIR, "dead-letter-queue.json");

function recordDeadLetter(item, reason) {
  try {
    let deadLetters = [];
    if (fs.existsSync(DEAD_LETTER_FILE)) {
      deadLetters = JSON.parse(fs.readFileSync(DEAD_LETTER_FILE, "utf8"));
      if (!Array.isArray(deadLetters)) deadLetters = [];
    }
    deadLetters.push({
      ...item,
      failedAt: new Date().toISOString(),
      failureReason: reason,
    });
    // Keep last 50 failed items
    if (deadLetters.length > 50) deadLetters = deadLetters.slice(-50);
    writeJsonAtomic(DEAD_LETTER_FILE, deadLetters);
  } catch (err) {
    console.error("[bridge] Failed to record dead letter:", err.message);
  }
}

function sortQueue() {
  queue.sort((a, b) => {
    if (a.priority !== b.priority) return a.priority - b.priority;
    return a.queuedAt - b.queuedAt;
  });
}

function enqueuePrompt(promptText, opts = {}) {
  const item = {
    id: `turn_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    priority: opts.priority ?? PRIORITY.REVIEW_WAVE,
    kind: opts.kind || "general",
    threadKey: opts.threadKey || null,
    targetPane: opts.targetPane || ARCHITECT_PANE,
    shouldClear: Boolean(opts.shouldClear),
    attempts: 0,
    prompt: promptText,
    queuedAt: Date.now(),
  };

  queue.push(item);
  sortQueue();
  saveQueueToDisk();
  console.log(`[bridge] Enqueued turn ${item.id} -> ${item.targetPane} [${item.kind}, prio=${item.priority}, clear=${item.shouldClear}] (queue size: ${queue.length}).`);
  drainQueue();
}

function enqueueArchitectPrompt(promptText, opts = {}) {
  enqueuePrompt(promptText, { ...opts, targetPane: ARCHITECT_PANE, shouldClear: false });
}

function enqueueOrchestratorPrompt(promptText, opts = {}) {
  enqueuePrompt(promptText, { ...opts, targetPane: ORCHESTRATOR_PANE, shouldClear: true });
}

function coalesceComment(threadKey, commentData, isPR, num) {
  let entry = pendingComments.get(threadKey);
  if (!entry) {
    entry = {
      isPR,
      num,
      comments: [],
      timer: null,
    };
    pendingComments.set(threadKey, entry);
  }

  entry.comments.push(commentData);
  if (entry.timer) clearTimeout(entry.timer);

  entry.timer = setTimeout(() => {
    pendingComments.delete(threadKey);
    const commentsList = entry.comments
      .map((c) => `- @${c.author}: "${c.body}"`)
      .join("\n");
    const formattedPrompt = [
      `[GITHUB EVENT: HUMAN FEEDBACK] Comments on ${entry.isPR ? "PR" : "Issue"} #${entry.num}:`,
      commentsList,
    ].join("\n");

    enqueueArchitectPrompt(formattedPrompt, {
      priority: PRIORITY.HUMAN_COMMENT,
      kind: "human_comment",
      threadKey,
    });
  }, COMMENT_COALESCE_MS);
}

async function sendAndWaitAgentTurn(pane, promptText, shouldClear = false) {
  // 1. Ensure target agent is idle before starting
  try {
    await execFileAsync("herdr", ["agent", "wait", pane, "--until", "idle", "--until", "done", "--timeout", "15000"]);
  } catch {
    console.warn(`[bridge] Agent ${pane} not currently idle; continuing dispatch...`);
  }

  // 2. Wipe LLM context if requested
  if (shouldClear) {
    console.log(`[bridge] Sending /clear to ${pane} to reset LLM context before turn...`);
    await execFileAsync("herdr", ["agent", "send-keys", pane, "/clear", "Enter"]).catch(() => {});
    await new Promise((r) => setTimeout(r, 1500));
    try {
      await execFileAsync("herdr", ["agent", "wait", pane, "--until", "idle", "--until", "done", "--timeout", "5000"]);
    } catch {}
  }

  // 3. Dispatch prompt and wait for turn completion
  await execFileAsync(
    "herdr",
    [
      "agent",
      "prompt",
      pane,
      promptText,
      "--wait",
      "--until",
      "idle",
      "--until",
      "done",
      "--timeout",
      String(ARCHITECT_WAIT_TIMEOUT_MS),
    ],
    { timeout: ARCHITECT_WAIT_TIMEOUT_MS + 10_000 }
  );
  return { delivered: true };
}

async function drainQueue() {
  if (processing) return;
  processing = true;

  try {
    while (queue.length > 0) {
      sortQueue();
      const next = queue[0];
      currentItemSummary = `${next.kind}${next.threadKey ? ` (${next.threadKey})` : ""}`;
      try {
        await sendAndWaitAgentTurn(next.targetPane || ARCHITECT_PANE, next.prompt, next.shouldClear);
        queue.shift();
        saveQueueToDisk();
      } catch (err) {
        next.attempts = (next.attempts || 0) + 1;
        console.error(`[bridge] Turn failed on ${currentItemSummary} (attempt ${next.attempts}/3):`, err.message);
        if (next.attempts >= 3) {
          console.error(`[bridge] Evicting item ${next.id} to dead-letter queue after 3 failed attempts.`);
          const deadItem = queue.shift();
          recordDeadLetter(deadItem, err.message);
          saveQueueToDisk();
        } else {
          saveQueueToDisk();
          break;
        }
      }
    }
  } finally {
    currentItemSummary = null;
    processing = false;
    if (queue.length > 0) setTimeout(drainQueue, 5000);
  }
}

function verifySignature(rawBody, sigHeader, secretOverride = SECRET) {
  const secret = secretOverride || SECRET;
  if (!secret) return true;
  if (!sigHeader) return false;
  const hmac = crypto.createHmac("sha256", secret);
  hmac.update(rawBody);
  const digest = `sha256=${hmac.digest("hex")}`;
  try {
    return crypto.timingSafeEqual(Buffer.from(digest), Buffer.from(sigHeader));
  } catch {
    return false;
  }
}

async function handleEvent(event, payload) {
  // 1. Issue labeled plan -> sync workspace & wake architect
  if (event === "issues" && payload.action === "labeled" && payload.label?.name === "plan") {
    const issue = payload.issue;
    await syncHubWorkspace();
    await syncBoardField(issue.number, "Status", "Backlog");

    enqueueArchitectPrompt(
      [
        `[GITHUB EVENT: PLAN REQUEST] Issue #${issue.number} ("${issue.title}") was labeled "plan".`,
        `Decompose this feature into atomic Sub-Issues with Test Plans, link them via .factory/sub-issue.sh, post your Wave Blueprint, and stop.`,
      ].join("\n"),
      { priority: PRIORITY.PLAN_READY, kind: "plan_request", threadKey: `issue:${issue.number}` }
    );
    return;
  }

  // 2. Issue labeled ready -> claim & dispatch wave via Orchestrator
  if (event === "issues" && payload.action === "labeled" && payload.label?.name === "ready") {
    const issue = payload.issue;
    await syncHubWorkspace();
    await syncBoardField(issue.number, "Status", "In Progress");

    enqueueOrchestratorPrompt(
      [
        `[GITHUB EVENT: READY FOR EXECUTION] Issue #${issue.number} ("${issue.title}") was approved and labeled "ready".`,
        `Decompose this approved Spec into atomic Sub-Issues via skill: to-tickets and .factory/sub-issue.sh, then dispatch Wave 1 to idle workers using .factory/dispatch-worker.sh.`,
      ].join("\n"),
      { priority: PRIORITY.PLAN_READY, kind: "ready_dispatch", threadKey: `issue:${issue.number}` }
    );
    return;
  }

  // 3. Human comments (Fix B1: only authorized humans; Fix D4: quote-replies accepted; 8s coalescer)
  if (
    (event === "issue_comment" || event === "pull_request_review_comment") &&
    payload.action === "created"
  ) {
    const comment = payload.comment;
    if (isAgentOrBotComment(payload.sender)) return;
    if (!isAuthorizedHuman(comment.author_association, payload.sender)) {
      console.log(`[bridge] Ignored comment from untrusted user @${comment.user?.login} (author_association=${comment.author_association}).`);
      return;
    }

    const isPR = Boolean(payload.issue?.pull_request || payload.pull_request);
    const num = (payload.issue || payload.pull_request).number;
    const threadKey = `${isPR ? "pr" : "issue"}:${num}`;

    coalesceComment(
      threadKey,
      { author: comment.user?.login || "user", body: comment.body || "" },
      isPR,
      num
    );
    return;
  }

  // 4. Human Review submitted (Fix D5)
  if (event === "pull_request_review" && payload.action === "submitted") {
    const review = payload.review;
    if (isAgentOrBotComment(payload.sender)) return;
    if (!isAuthorizedHuman(review.author_association, payload.sender)) return;
    if (!review.body && review.state !== "CHANGES_REQUESTED") return;

    const prNum = payload.pull_request.number;
    enqueueArchitectPrompt(
      [
        `[GITHUB EVENT: HUMAN PR REVIEW (${review.state})] @${review.user.login} reviewed PR #${prNum}:`,
        review.body ? `"${review.body}"` : "(No review body text; status changed)",
      ].join("\n"),
      { priority: PRIORITY.HUMAN_COMMENT, kind: "human_review", threadKey: `pr:${prNum}` }
    );
    return;
  }

  // 5. PR Merged into staging -> Deterministic completion & release (Claude E1 recommendation)
  if (
    event === "pull_request" &&
    payload.action === "closed" &&
    payload.pull_request?.merged === true &&
    payload.pull_request?.base?.ref === "staging"
  ) {
    const pr = payload.pull_request;
    await syncHubWorkspace();
    const linkedIssue = extractLinkedIssue(pr.body, pr.head?.ref);
    if (!linkedIssue) return;

    await syncBoardField(linkedIssue, "Status", "Done");
    const parentEpic = await getParentEpic(linkedIssue);
    if (!parentEpic) return;

    const summary = await getSubIssueSummary(parentEpic.number);
    if (summary.total > 0 && summary.completed >= summary.total) {
      console.log(`[bridge] Epic #${parentEpic.number} 100% complete (${summary.completed}/${summary.total}). Deterministically closing & opening Release PR.`);
      await ghAsArchitect(["issue", "close", String(parentEpic.number)]).catch(() => {});
      if (fs.existsSync(RELEASE_PR_SCRIPT)) {
        await execFileAsync(RELEASE_PR_SCRIPT, [String(parentEpic.number)], { env: ARCHITECT_EXEC_ENV }).catch(() => {});
      }
    } else {
      enqueueOrchestratorPrompt(
        `[GITHUB EVENT: SUB-ISSUE MERGED] PR #${pr.number} (Sub-Issue #${linkedIssue}) merged to staging. Parent Epic #${parentEpic.number} progress: ${summary.completed}/${summary.total}. Dispatch next unblocked sub-issues using .factory/dispatch-worker.sh.`,
        { priority: PRIORITY.REVIEW_WAVE, kind: "wave_check", threadKey: `issue:${parentEpic.number}` }
      );
    }
    return;
  }

  // 5b. Production Release PR Merged into master -> Trigger Architect Retrospective
  if (
    event === "pull_request" &&
    payload.action === "closed" &&
    payload.pull_request?.merged === true &&
    payload.pull_request?.base?.ref === "master"
  ) {
    const pr = payload.pull_request;
    await syncHubWorkspace();
    enqueueArchitectPrompt(
      `[GITHUB EVENT: PRODUCTION RELEASE MERGED] Release PR #${pr.number} merged into master. Run skill: retro, update AGENTS.md and GLOSSARY.md, and run .factory/sync-skills.sh.`,
      { priority: PRIORITY.PLAN_READY, kind: "release_retro", threadKey: `pr:${pr.number}` }
    );
    return;
  }

  // 6. Workflow run completed
  if (event === "workflow_run" && payload.action === "completed") {
    const run = payload.workflow_run;
    if (run.name !== CI_WORKFLOW_NAME) return;

    if (run.event === "push" && run.head_branch === "staging") {
      if (run.conclusion === "failure") {
        await syncHubWorkspace();
        enqueueOrchestratorPrompt(
          `[GITHUB EVENT: STAGING BROKEN — POST-MERGE CI FAILED] Run #${run.id} FAILED on staging. PAUSE merges and dispatch hotfix.`,
          { priority: PRIORITY.CI_URGENT, kind: "staging_broken", threadKey: "branch:staging" }
        );
      }
      return;
    }

    const prs = run.pull_requests || [];
    if (prs.length === 0) return;
    const prNumber = prs[0].number;
    const prMeta = await inspectPrMeta(prNumber, run.head_branch);

    if (run.conclusion === "failure") {
      enqueueOrchestratorPrompt(
        `[GITHUB EVENT: CI FAILED] PR #${prNumber} failed CI run #${run.id}. Dispatch fix to assigned worker via .factory/dispatch-worker.sh.`,
        { priority: PRIORITY.CI_URGENT, kind: "ci_failed", threadKey: `pr:${prNumber}` }
      );
    } else if (run.conclusion === "success") {
      if (prMeta.humanGateBlocked || prMeta.hasHumanGateLabel) {
        await surfaceAwaitingApproval(prNumber, prMeta.linkedIssue, prMeta.baseRefName === "master");
        enqueueOrchestratorPrompt(
          `[GITHUB EVENT: CI PASSED — GATED] PR #${prNumber} passed CI, moved to Awaiting Approval. Post review summary and STOP.`,
          { priority: PRIORITY.REVIEW_WAVE, kind: "ci_gated", threadKey: `pr:${prNumber}` }
        );
      } else {
        if (prMeta.linkedIssue) await syncBoardField(prMeta.linkedIssue, "Status", "In Review");
        enqueueOrchestratorPrompt(
          `[GITHUB EVENT: CI PASSED] PR #${prNumber} passed CI with no protected path locks. Review diff & evidence via .factory/fetch-evidence.sh and skill: pr-evidence-review. If verified, squash-merge to staging.`,
          { priority: PRIORITY.REVIEW_WAVE, kind: "ci_passed", threadKey: `pr:${prNumber}` }
        );
      }
    }
  }
}

// Stall Watchdog: Detect silent stalled worker tasks
async function checkStalledIssues() {
  try {
    const { stdout } = await ghAsArchitect([
      "issue",
      "list",
      "--state",
      "open",
      "--label",
      "in-progress",
      "--json",
      "number,title,updatedAt",
    ]);
    const issues = JSON.parse(stdout || "[]");
    const retryState = loadRetryState();
    if (!retryState.stallAlerts) retryState.stallAlerts = {};
    const now = Date.now();

    for (const issue of issues) {
      const updatedAt = new Date(issue.updatedAt).getTime();
      const idleMs = now - updatedAt;
      if (idleMs > STALL_THRESHOLD_MS) {
        const lastAlert = retryState.stallAlerts[issue.number] || 0;
        // Alert at most once every 2 hours per issue
        if (now - lastAlert > 2 * 60 * 60 * 1000) {
          retryState.stallAlerts[issue.number] = now;
          saveRetryState(retryState);
          const idleMins = Math.round(idleMs / 60000);
          console.warn(`[bridge:watchdog] Detected stalled Sub-Issue #${issue.number} (idle for ${idleMins} mins).`);
          enqueueOrchestratorPrompt(
            `[WATCHDOG ALERT: STALLED TASK] Sub-Issue #${issue.number} ("${issue.title}") has had no activity for ${idleMins} minutes. Run 'herdr agent list' and 'herdr agent read <worker>' to inspect worker status and take action.`,
            { priority: PRIORITY.CI_URGENT, kind: "watchdog_stall", threadKey: `issue:${issue.number}` }
          );
        }
      }
    }
  } catch (err) {
    console.warn("[bridge:watchdog] Non-fatal stall check warning:", err.message);
  }
}

// Reconciliation scan on startup (Fix D2)
async function reconcileStartupState() {
  try {
    console.log("[bridge] Running startup reconciliation scan against GitHub...");
    // 1. Reconcile open issues needing attention
    const { stdout: openIssuesOut } = await ghAsArchitect([
      "issue",
      "list",
      "--state",
      "open",
      "--json",
      "number,title,labels",
    ]);
    const openIssues = JSON.parse(openIssuesOut || "[]");
    for (const issue of openIssues) {
      const labels = (issue.labels || []).map((l) => l.name);
      const isPlanEnqueued = queue.some((q) => q.threadKey === `issue:${issue.number}` && q.kind === "plan_request");
      const isReadyEnqueued = queue.some((q) => q.threadKey === `issue:${issue.number}` && q.kind === "ready_dispatch");

      if (labels.includes("plan") && !isPlanEnqueued) {
        console.log(`[bridge:reconcile] Recovering unhandled 'plan' issue #${issue.number}`);
        enqueueArchitectPrompt(
          `[GITHUB RECONCILE: PLAN REQUEST] Issue #${issue.number} ("${issue.title}") is labeled "plan". Decompose into atomic Sub-Issues with Test Plans, link via .factory/sub-issue.sh, post Wave Blueprint, and stop.`,
          { priority: PRIORITY.PLAN_READY, kind: "plan_request", threadKey: `issue:${issue.number}` }
        );
      } else if (labels.includes("ready") && !isReadyEnqueued) {
        console.log(`[bridge:reconcile] Recovering unhandled 'ready' issue #${issue.number}`);
        enqueueOrchestratorPrompt(
          `[GITHUB RECONCILE: READY FOR EXECUTION] Issue #${issue.number} ("${issue.title}") is approved and labeled "ready". Decompose approved Spec via skill: to-tickets and .factory/sub-issue.sh, then dispatch Wave 1 via .factory/dispatch-worker.sh.`,
          { priority: PRIORITY.PLAN_READY, kind: "ready_dispatch", threadKey: `issue:${issue.number}` }
        );
      }
    }

    // 2. Reconcile open PRs against staging
    const { stdout: openPrsOut } = await ghAsArchitect([
      "pr",
      "list",
      "--state",
      "open",
      "--base",
      "staging",
      "--json",
      "number,headRefName",
    ]);
    const openPrs = JSON.parse(openPrsOut || "[]");
    console.log(`[bridge] Reconciled ${openPrs.length} open staging PR(s) and ${openIssues.length} open issue(s).`);
  } catch (err) {
    console.warn("[bridge] Non-fatal reconciliation scan warning:", err.message);
  }
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, reviewer: HUMAN_REVIEWER, queued: queue.length }));
    return;
  }

  if (req.method !== "POST" || !req.url?.startsWith("/webhook")) {
    res.writeHead(404);
    res.end();
    return;
  }

  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const raw = Buffer.concat(chunks);
    if (!verifySignature(raw, req.headers["x-hub-signature-256"])) {
      res.writeHead(401);
      res.end("Invalid signature");
      return;
    }

    const event = req.headers["x-github-event"];
    let payload;
    try {
      payload = JSON.parse(raw.toString("utf8"));
    } catch {
      res.writeHead(400);
      res.end("Invalid JSON");
      return;
    }

    res.writeHead(202, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ received: event }));

    handleEvent(event, payload).catch((err) => console.error("[bridge] Event error:", err));
  });
});

let watchdogTimer = null;
if (isDirectRun) {
  server.listen(PORT, BIND_HOST, () => {
    console.log(`[bridge] Listening on :${PORT} | Architect: ${ARCHITECT_PANE} | Orchestrator: ${ORCHESTRATOR_PANE} | Human Reviewer: @${HUMAN_REVIEWER || "unset"}`);
    if (queue.length > 0) drainQueue();
    reconcileStartupState();
    if (STALL_WATCHDOG_INTERVAL_MS > 0) {
      watchdogTimer = setInterval(checkStalledIssues, STALL_WATCHDOG_INTERVAL_MS);
    }
  });
}

export {
  verifySignature,
  isAgentOrBotComment,
  isAuthorizedHuman,
  extractLinkedIssue,
  coalesceComment,
  enqueuePrompt,
  drainQueue,
  queue,
  pendingComments,
  server,
  watchdogTimer,
};
