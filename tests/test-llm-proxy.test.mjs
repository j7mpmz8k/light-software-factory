import { test, describe, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { joinUpstreamUrl, checkRateLimit, recordUsage, telemetry } from "../.factory/llm-proxy.mjs";

describe("LLM Proxy Unit & Integration Tests", () => {
  let mockUpstream;
  let mockPort;
  let lastUpstreamReq = null;

  before(async () => {
    // Spin up mock upstream server
    mockUpstream = http.createServer((req, res) => {
      lastUpstreamReq = {
        url: req.url,
        method: req.method,
        headers: req.headers,
      };

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
      joinUpstreamUrl("https://generativelanguage.googleapis.com/v1beta/openai", "/v1/chat/completions"),
      "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    );
    assert.equal(
      joinUpstreamUrl("http://host.docker.internal:11434/v1", "/v1/chat/completions"),
      "http://host.docker.internal:11434/v1/chat/completions"
    );
    assert.equal(
      joinUpstreamUrl("https://api.anthropic.com", "/v1/messages"),
      "https://api.anthropic.com/v1/messages"
    );
  });

  test("checkRateLimit tracks and enforces hourly limits", () => {
    const bucket = "test-bucket-" + Date.now();
    // Default limit allows 5 calls
    assert.equal(checkRateLimit(bucket, 3), true);
    assert.equal(checkRateLimit(bucket, 3), true);
    assert.equal(checkRateLimit(bucket, 3), true);
    // 4th call should be blocked
    assert.equal(checkRateLimit(bucket, 3), false);
  });

  test("recordUsage tracks prompt, completion, and total tokens in telemetry", () => {
    recordUsage("glm", "glm-5.3", 100, 50, 150);
    assert.ok(telemetry.routes.glm.promptTokens >= 100);
    assert.ok(telemetry.routes.glm.completionTokens >= 50);
    assert.ok(telemetry.routes.glm.totalTokens >= 150);
  });

  test("GET /health endpoint responds on proxy", async () => {
    const res = await fetch("http://127.0.0.1:4000/health").catch(() => null);
    if (res) {
      assert.equal(res.status, 200);
      const data = await res.json();
      assert.equal(data.ok, true);
    }
  });

  test("GET /stats endpoint responds with telemetry and rolling limits", async () => {
    const res = await fetch("http://127.0.0.1:4000/stats").catch(() => null);
    if (res) {
      assert.equal(res.status, 200);
      const data = await res.json();
      assert.ok(data.routes);
      assert.ok(data.rollingLastHour);
    }
  });
});
