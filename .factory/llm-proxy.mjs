#!/usr/bin/env node
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Readable, Transform, pipeline } from "node:stream";

const isDirectRun = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

function parseNonNegativeInt(val, fallback) {
  if (val === undefined || val === null || String(val).trim() === "") return fallback;
  const n = Number.parseInt(String(val).trim(), 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

function verifyBearerToken(authHeader, expectedToken) {
  if (!expectedToken || !authHeader) return false;
  const expected = Buffer.from(`Bearer ${expectedToken}`, "utf8");
  const actual = Buffer.from(String(authHeader), "utf8");
  if (expected.length !== actual.length) return false;
  return crypto.timingSafeEqual(expected, actual);
}

const SECRETS_FILE =
  process.env.LLM_SECRETS_FILE ||
  process.env.FACTORY_LLM_SECRETS ||
  "/run/factory-config/llm-secrets.env";
const PORT = parseNonNegativeInt(process.env.LLM_PROXY_PORT, 4000) || 4000;

function loadSecrets(filePath) {
  if (!fs.existsSync(filePath)) {
    console.warn(`[llm-proxy] Secrets file not found at ${filePath}; running with environment defaults.`);
    return {};
  }
  const env = {};
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx > 0) {
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim();
      if (!val.startsWith('"') && !val.startsWith("'")) {
        val = val.replace(/\s+#.*$/, "").trim();
      } else {
        val = val.replace(/^["']|["']$/g, "");
      }
      env[key] = val;
    }
  }
  return env;
}

const secrets = loadSecrets(SECRETS_FILE);

const GLM_UPSTREAM_URL = (
  secrets.GLM_UPSTREAM_URL ||
  process.env.GLM_UPSTREAM_URL ||
  "https://api.z.ai/api/coding/paas/v4"
).replace(/\/+$/, "");
const GLM_API_KEY = secrets.GLM_API_KEY || process.env.GLM_API_KEY || "";

const VISION_UPSTREAM_URL = (
  secrets.VISION_UPSTREAM_URL ||
  process.env.VISION_UPSTREAM_URL ||
  GLM_UPSTREAM_URL
).replace(/\/+$/, "");
const VISION_API_KEY =
  secrets.VISION_API_KEY || process.env.VISION_API_KEY || GLM_API_KEY;

const BACKUP_UPSTREAM_URL = (
  secrets.BACKUP_UPSTREAM_URL ||
  process.env.BACKUP_UPSTREAM_URL ||
  GLM_UPSTREAM_URL
).replace(/\/+$/, "");
const BACKUP_API_KEY =
  secrets.BACKUP_API_KEY || process.env.BACKUP_API_KEY || GLM_API_KEY;

const GLM_WORKER_UPSTREAM_URL = (
  secrets.GLM_WORKER_UPSTREAM_URL ||
  process.env.GLM_WORKER_UPSTREAM_URL ||
  GLM_UPSTREAM_URL
).replace(/\/+$/, "");
const GLM_WORKER_API_KEY =
  secrets.GLM_WORKER_API_KEY || process.env.GLM_WORKER_API_KEY || GLM_API_KEY;

// Require proxy tokens (reject missing token in production)
const ARCHITECT_PROXY_TOKEN =
  process.env.ARCHITECT_PROXY_TOKEN || secrets.ARCHITECT_PROXY_TOKEN;
const GLM_WORKER_PROXY_TOKEN =
  process.env.GLM_WORKER_PROXY_TOKEN || secrets.GLM_WORKER_PROXY_TOKEN || "proxy-worker-glm-only";

if (isDirectRun && !ARCHITECT_PROXY_TOKEN) {
  console.error("[llm-proxy] FATAL: ARCHITECT_PROXY_TOKEN is required.");
  process.exit(1);
}

const GLM_MAX_REQ_PER_HOUR = parseNonNegativeInt(
  secrets.GLM_MAX_REQ_PER_HOUR ?? process.env.GLM_MAX_REQ_PER_HOUR,
  240
);
const GLM_WORKER_MAX_REQ_PER_HOUR = parseNonNegativeInt(
  secrets.GLM_WORKER_MAX_REQ_PER_HOUR ?? process.env.GLM_WORKER_MAX_REQ_PER_HOUR,
  180
);

const ALLOWED_ARCHITECT_MODELS = new Set(
  [
    process.env.ARCHITECT_MODEL,
    process.env.ARCHITECT_VISION_MODEL,
    process.env.ORCHESTRATOR_MODEL,
    process.env.ARCHITECT_BACKUP_MODEL,
    process.env.GLM_WORKER_MODEL,
    ...(process.env.EXTRA_ALLOWED_MODELS || "").split(","),
  ]
    .map((s) => (s || "").trim())
    .filter(Boolean)
);

const rateBuckets = {
  glm: [],
  workerGlm: [],
};

function emptyRouteStats() {
  return {
    requests: 0,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    rateLimited: 0,
    errors: 0,
    lastRequestAt: null,
    byModel: {},
  };
}

const telemetry = {
  startedAt: new Date().toISOString(),
  routes: {
    glm: emptyRouteStats(),
    vision: emptyRouteStats(),
    backup: emptyRouteStats(),
    workerGlm: emptyRouteStats(),
  },
};

function recordUsage(route, modelName, promptTokens, completionTokens, totalTokens) {
  const r = telemetry.routes[route];
  if (!r) return;
  const p = Number(promptTokens || 0);
  const c = Number(completionTokens || 0);
  const t = Number(totalTokens || p + c);
  if (p <= 0 && c <= 0 && t <= 0) return;

  r.promptTokens += p;
  r.completionTokens += c;
  r.totalTokens += t;

  const mKey = modelName || "unknown";
  if (!r.byModel[mKey]) {
    r.byModel[mKey] = { requests: 0, promptTokens: 0, completionTokens: 0, totalTokens: 0 };
  }
  r.byModel[mKey].promptTokens += p;
  r.byModel[mKey].completionTokens += c;
  r.byModel[mKey].totalTokens += t;
}

function recordModelRequest(route, modelName) {
  const r = telemetry.routes[route];
  if (!r) return;
  r.requests += 1;
  r.lastRequestAt = new Date().toISOString();
  const mKey = modelName || "unknown";
  if (!r.byModel[mKey]) {
    r.byModel[mKey] = { requests: 0, promptTokens: 0, completionTokens: 0, totalTokens: 0 };
  }
  r.byModel[mKey].requests += 1;
}

function createUsageTapStream(route, modelName, contentType) {
  const isSse = String(contentType || "").toLowerCase().includes("text/event-stream");
  const isJson = String(contentType || "").toLowerCase().includes("application/json");
  let sseTail = "";
  let jsonBuf = [];
  let jsonSize = 0;
  let capturedPrompt = 0;
  let capturedCompletion = 0;
  let capturedTotal = 0;

  function extractFromObj(obj) {
    if (!obj || typeof obj !== "object") return;
    if (obj.usage && typeof obj.usage === "object") {
      if (obj.usage.prompt_tokens != null) capturedPrompt = Math.max(capturedPrompt, Number(obj.usage.prompt_tokens) || 0);
      if (obj.usage.completion_tokens != null) capturedCompletion = Math.max(capturedCompletion, Number(obj.usage.completion_tokens) || 0);
      if (obj.usage.total_tokens != null) capturedTotal = Math.max(capturedTotal, Number(obj.usage.total_tokens) || 0);
      if (obj.usage.input_tokens != null) capturedPrompt = Math.max(capturedPrompt, Number(obj.usage.input_tokens) || 0);
      if (obj.usage.output_tokens != null) capturedCompletion = Math.max(capturedCompletion, Number(obj.usage.output_tokens) || 0);
    }
    if (obj.message?.usage) {
      if (obj.message.usage.input_tokens != null) {
        capturedPrompt = Math.max(capturedPrompt, Number(obj.message.usage.input_tokens) || 0);
      }
      if (obj.message.usage.output_tokens != null) {
        capturedCompletion = Math.max(capturedCompletion, Number(obj.message.usage.output_tokens) || 0);
      }
    }
  }

  return new Transform({
    transform(chunk, _encoding, callback) {
      try {
        if (isSse) {
          sseTail += chunk.toString("utf8");
          const lines = sseTail.split(/\r?\n/);
          sseTail = lines.pop() || "";
          for (const line of lines) {
            if (!line.startsWith("data:")) continue;
            const dataStr = line.slice(5).trim();
            if (!dataStr || dataStr === "[DONE]") continue;
            try {
              extractFromObj(JSON.parse(dataStr));
            } catch {}
          }
        } else if (isJson && jsonSize < 2 * 1024 * 1024) {
          jsonBuf.push(chunk);
          jsonSize += chunk.length;
        }
      } catch {}
      callback(null, chunk);
    },
    flush(callback) {
      try {
        if (isJson && jsonBuf.length > 0) {
          extractFromObj(JSON.parse(Buffer.concat(jsonBuf).toString("utf8")));
        }
        recordUsage(route, modelName, capturedPrompt, capturedCompletion, capturedTotal);
      } catch {}
      callback();
    },
  });
}

function checkRateLimit(bucket, limit) {
  if (limit <= 0) return true;
  const now = Date.now();
  const cutoff = now - 60 * 60 * 1000;
  if (!rateBuckets[bucket]) rateBuckets[bucket] = [];
  rateBuckets[bucket] = rateBuckets[bucket].filter((ts) => ts > cutoff);
  if (rateBuckets[bucket].length >= limit) return false;
  rateBuckets[bucket].push(now);
  return true;
}

function joinUpstreamUrl(baseUrl, subPath) {
  let cleanSub = subPath.startsWith("/") ? subPath : `/${subPath}`;
  const hasVersionOrProviderPrefix = /\/(v\d+[a-z0-9]*|openai)$/i.test(baseUrl);
  if (hasVersionOrProviderPrefix && cleanSub.startsWith("/v1/")) {
    cleanSub = cleanSub.slice(3);
  }
  return `${baseUrl}${cleanSub}`;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    const MAX_BODY = 10 * 1024 * 1024;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        req.destroy();
        reject(new Error("Request body too large (max 10MB)"));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function sendJson(res, status, obj) {
  const body = Buffer.from(JSON.stringify(obj, null, 2));
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": body.length,
  });
  res.end(body);
}

const SKIP_REQ_HEADERS = new Set([
  "host",
  "connection",
  "content-length",
  "transfer-encoding",
  "authorization",
  "x-api-key",
]);

const SKIP_RES_HEADERS = new Set([
  "connection",
  "keep-alive",
  "transfer-encoding",
  "content-encoding",
  "content-length",
]);

const server = http.createServer(async (req, res) => {
  const rawUrl = req.url || "/";
  if (req.method === "GET" && rawUrl === "/health") {
    return sendJson(res, 200, {
      ok: true,
      apiKeyConfigured: Boolean(GLM_API_KEY),
      routes: {
        glm: Boolean(GLM_UPSTREAM_URL),
        vision: Boolean(VISION_UPSTREAM_URL),
        workerGlm: Boolean(GLM_WORKER_UPSTREAM_URL),
      },
      allowedArchitectModels: [...ALLOWED_ARCHITECT_MODELS],
    });
  }

  if (req.method === "GET" && rawUrl === "/stats") {
    const now = Date.now();
    const cutoff = now - 60 * 60 * 1000;
    return sendJson(res, 200, {
      ...telemetry,
      rollingLastHour: {
        hubGlmAndVisionRequests: rateBuckets.glm.filter((ts) => ts > cutoff).length,
        hubGlmMaxPerHour: GLM_MAX_REQ_PER_HOUR,
        workerGlmRequests: rateBuckets.workerGlm.filter((ts) => ts > cutoff).length,
        workerGlmMaxPerHour: GLM_WORKER_MAX_REQ_PER_HOUR,
      },
    });
  }

  let route = null;
  let subPath = "";
  if (rawUrl === "/glm" || rawUrl.startsWith("/glm/")) {
    route = "glm";
    subPath = rawUrl.slice("/glm".length) || "/";
  } else if (rawUrl === "/vision" || rawUrl.startsWith("/vision/")) {
    route = "vision";
    subPath = rawUrl.slice("/vision".length) || "/";
  } else if (rawUrl === "/backup" || rawUrl.startsWith("/backup/")) {
    route = "backup";
    subPath = rawUrl.slice("/backup".length) || "/";
  } else if (rawUrl === "/worker-glm" || rawUrl.startsWith("/worker-glm/")) {
    route = "workerGlm";
    subPath = rawUrl.slice("/worker-glm".length) || "/";
  } else {
    return sendJson(res, 404, { error: "Unknown proxy route. Use /glm, /vision, /backup, /worker-glm, /health, or /stats." });
  }

  // Answer Hermes probe endpoints locally without charging hourly quota or failing upstream
  if (req.method === "GET" && (subPath === "/models" || subPath === "/v1/models" || subPath === "/api/v1/models")) {
    return sendJson(res, 200, {
      data: [...ALLOWED_ARCHITECT_MODELS].map((id) => ({ id, object: "model", owned_by: "custom" })),
    });
  }

  const incomingAuth = String(req.headers["authorization"] || "");

  if (route === "glm" || route === "vision" || route === "backup") {
    if (!verifyBearerToken(incomingAuth, ARCHITECT_PROXY_TOKEN)) {
      return sendJson(res, 401, { error: "Unauthorized for hub LLM route" });
    }
    if (!checkRateLimit("glm", GLM_MAX_REQ_PER_HOUR)) {
      telemetry.routes[route].rateLimited += 1;
      return sendJson(res, 429, { error: `Hub GLM hourly limit (${GLM_MAX_REQ_PER_HOUR}/hr) exceeded` });
    }
  } else if (route === "workerGlm") {
    if (!verifyBearerToken(incomingAuth, GLM_WORKER_PROXY_TOKEN)) {
      return sendJson(res, 401, { error: "Unauthorized for worker-glm route" });
    }
    if (!checkRateLimit("workerGlm", GLM_WORKER_MAX_REQ_PER_HOUR)) {
      telemetry.routes.workerGlm.rateLimited += 1;
      return sendJson(res, 429, { error: `worker-glm hourly limit (${GLM_WORKER_MAX_REQ_PER_HOUR}/hr) exceeded` });
    }
  }

  let bodyBuf;
  try {
    bodyBuf = req.method === "GET" || req.method === "HEAD" ? null : await readBody(req);
  } catch (err) {
    return sendJson(res, 413, { error: err.message });
  }

  let requestedModel = "";
  if (bodyBuf && bodyBuf.length > 0) {
    try {
      const parsed = JSON.parse(bodyBuf.toString("utf8"));
      requestedModel = String(parsed?.model || "");
    } catch {}

    if (
      ALLOWED_ARCHITECT_MODELS.size > 0 &&
      requestedModel &&
      !ALLOWED_ARCHITECT_MODELS.has(requestedModel)
    ) {
      console.warn(`[llm-proxy] Blocked disallowed model "${requestedModel}" on /${route}`);
      return sendJson(res, 403, {
        error: `Model "${requestedModel}" is not in allowed list: ${[...ALLOWED_ARCHITECT_MODELS].join(", ")}`,
      });
    }
  }

  let targetUrl = "";
  const outHeaders = {};
  for (const [k, v] of Object.entries(req.headers)) {
    const lk = k.toLowerCase();
    if (!SKIP_REQ_HEADERS.has(lk) && v !== undefined) {
      outHeaders[lk] = Array.isArray(v) ? v.join(", ") : v;
    }
  }

  if (route === "glm") {
    targetUrl = joinUpstreamUrl(GLM_UPSTREAM_URL, subPath);
    if (GLM_API_KEY) outHeaders["authorization"] = `Bearer ${GLM_API_KEY}`;
  } else if (route === "vision") {
    targetUrl = joinUpstreamUrl(VISION_UPSTREAM_URL, subPath);
    if (VISION_API_KEY) outHeaders["authorization"] = `Bearer ${VISION_API_KEY}`;
  } else if (route === "backup") {
    targetUrl = joinUpstreamUrl(BACKUP_UPSTREAM_URL, subPath);
    if (BACKUP_API_KEY) outHeaders["authorization"] = `Bearer ${BACKUP_API_KEY}`;
  } else if (route === "workerGlm") {
    targetUrl = joinUpstreamUrl(GLM_WORKER_UPSTREAM_URL, subPath);
    if (GLM_WORKER_API_KEY) outHeaders["authorization"] = `Bearer ${GLM_WORKER_API_KEY}`;
  }

  recordModelRequest(route, requestedModel);

  const abortController = new AbortController();
  res.on("close", () => {
    if (!res.writableEnded) abortController.abort();
  });

  try {
    const upstreamRes = await fetch(targetUrl, {
      method: req.method,
      headers: outHeaders,
      body: bodyBuf && bodyBuf.length > 0 ? bodyBuf : undefined,
      signal: abortController.signal,
    });

    if (!upstreamRes.ok) {
      telemetry.routes[route].errors += 1;
    }

    const resHeaders = {};
    upstreamRes.headers.forEach((val, key) => {
      if (!SKIP_RES_HEADERS.has(key.toLowerCase())) {
        resHeaders[key] = val;
      }
    });

    res.writeHead(upstreamRes.status, resHeaders);
    if (upstreamRes.body) {
      const tap = createUsageTapStream(route, requestedModel, upstreamRes.headers.get("content-type"));
      pipeline(Readable.fromWeb(upstreamRes.body), tap, res, (err) => {
        if (err && err.name !== "AbortError") {
          telemetry.routes[route].errors += 1;
        }
      });
    } else {
      res.end();
    }
  } catch (err) {
    if (err.name !== "AbortError") {
      telemetry.routes[route].errors += 1;
      console.error(`[llm-proxy] Upstream error on /${route}:`, err.message);
      if (!res.headersSent) {
        sendJson(res, 502, { error: "Upstream inference server unreachable" });
      }
    }
  }
});

if (isDirectRun) {
  server.listen(PORT, "0.0.0.0", () => {
    console.log(
      `[llm-proxy] Listening on :${PORT} | Hub->${GLM_UPSTREAM_URL} | Vision->${VISION_UPSTREAM_URL} | WorkerGLM->${GLM_WORKER_UPSTREAM_URL} | Allowed=[${[...ALLOWED_ARCHITECT_MODELS].join(", ")}] | Telemetry: GET /stats`
    );
  });
}

export {
  server,
  telemetry,
  joinUpstreamUrl,
  checkRateLimit,
  recordUsage,
  loadSecrets,
  parseNonNegativeInt,
  verifyBearerToken,
  ALLOWED_ARCHITECT_MODELS,
};
