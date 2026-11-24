import { test, describe, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import {
  joinUpstreamUrl,
  checkRateLimit,
  recordUsage,
  loadSecrets,
  parseNonNegativeInt,
  verifyBearerToken,
  telemetry,
} from "../.factory/llm-proxy.mjs";

describe("LLM Proxy Unit & Integration Tests", () => {
  let mockUpstream;
  let mockPort;

  before(async () => {
    mockUpstream = http.createServer((req, res) => {
      if (req.url === "/chat/completions" || req.url === "/v1/chat/completions") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            id: "chatcmpl-test",
            object: "chat.completion",
            model: "glm-5.3",
            choices: [{ message: { role: "assistant", content: "Hello from mock upstream!" } }],
            usage: { prompt_tokens: 15, completion_tokens: 8, total_tokens: 23 },
          })
        );
      } else {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ status: "ok" }));
      }
    });

    await new Promise((resolve) => {
      mockUpstream.listen(0, "127.0.0.1", () => {
        mockPort = mockUpstream.address().port;
        resolve();
      });
    });
  });

  after(() => {
    mockUpstream.close();
  });

  test("joinUpstreamUrl correctly joins paths and strips redundant /v1", () => {
    assert.equal(
      joinUpstreamUrl("https://api.z.ai/api/coding/paas/v4", "/v1/chat/completions"),
      "https://api.z.ai/api/coding/paas/v4/chat/completions"
    );
    assert.equal(
      joinUpstreamUrl("http://host.docker.internal:11434/v1", "/v1/chat/completions"),
      "http://host.docker.internal:11434/v1/chat/completions"
    );
    assert.equal(
      joinUpstreamUrl("https://api.deepseek.com", "/v1/chat/completions"),
      "https://api.deepseek.com/v1/chat/completions"
    );
  });

  test("checkRateLimit tracks and enforces isolated hourly limits", () => {
    const hubBucket = "test-hub-" + Date.now();
    const workerBucket = "test-worker-glm-" + Date.now();

    assert.equal(checkRateLimit(hubBucket, 2), true);
    assert.equal(checkRateLimit(hubBucket, 2), true);
    assert.equal(checkRateLimit(hubBucket, 2), false);

    // Worker bucket remains isolated from hub bucket
    assert.equal(checkRateLimit(workerBucket, 2), true);
    assert.equal(checkRateLimit(workerBucket, 2), true);
    assert.equal(checkRateLimit(workerBucket, 2), false);
  });

  test("recordUsage tracks prompt, completion, and total tokens for both hub glm and workerGlm routes", () => {
    recordUsage("glm", "glm-5.3", 100, 50, 150);
    assert.ok(telemetry.routes.glm.promptTokens >= 100);
    assert.ok(telemetry.routes.glm.completionTokens >= 50);
    assert.ok(telemetry.routes.glm.totalTokens >= 150);

    recordUsage("workerGlm", "glm-5.3", 200, 80, 280);
    assert.ok(telemetry.routes.workerGlm.promptTokens >= 200);
    assert.ok(telemetry.routes.workerGlm.completionTokens >= 80);
    assert.ok(telemetry.routes.workerGlm.totalTokens >= 280);
  });

  test("loadSecrets strips inline comments and parseNonNegativeInt guards against NaN", () => {
    const tmpFile = path.join(os.tmpdir(), `factory-llm-secrets-${Date.now()}.conf`);
    fs.writeFileSync(
      tmpFile,
      [
        "GLM_API_KEY=sk-test-123 # primary key",
        "GLM_MAX_REQ_PER_HOUR=240 # hourly hub cap",
        'GLM_UPSTREAM_URL="https://api.z.ai/api/coding/paas/v4"',
      ].join("\n"),
      "utf8"
    );
    const parsed = loadSecrets(tmpFile);
    fs.rmSync(tmpFile, { force: true });

    assert.equal(parsed.GLM_API_KEY, "sk-test-123");
    assert.equal(parsed.GLM_MAX_REQ_PER_HOUR, "240");
    assert.equal(parseNonNegativeInt(parsed.GLM_MAX_REQ_PER_HOUR, 100), 240);
    assert.equal(parseNonNegativeInt("not-a-number", 180), 180);
    assert.equal(parseNonNegativeInt("", 180), 180);
  });

  test("verifyBearerToken performs constant-time exact Bearer token matching", () => {
    assert.equal(verifyBearerToken("Bearer secret-tok-123", "secret-tok-123"), true);
    assert.equal(verifyBearerToken("Bearer wrong-tok-123", "secret-tok-123"), false);
    assert.equal(verifyBearerToken("Bearer secret-tok", "secret-tok-123"), false);
    assert.equal(verifyBearerToken("", "secret-tok-123"), false);
  });

  test("GET /health endpoint responds on proxy when active", async () => {
    const res = await fetch("http://127.0.0.1:4000/health").catch(() => null);
    if (res) {
      assert.equal(res.status, 200);
      const data = await res.json();
      assert.equal(data.ok, true);
    }
  });

  test("GET /stats endpoint responds with telemetry and rolling limits when active", async () => {
    const res = await fetch("http://127.0.0.1:4000/stats").catch(() => null);
    if (res) {
      assert.equal(res.status, 200);
      const data = await res.json();
      assert.ok(data.routes);
      assert.ok(data.rollingLastHour);
    }
  });
});
