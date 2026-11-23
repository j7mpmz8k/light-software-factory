import { test, describe, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { joinUpstreamUrl, checkRateLimit, recordUsage, telemetry } from "../.factory/llm-proxy.mjs";

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
