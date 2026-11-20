#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const APPS_ENV_PATH =
  process.env.FACTORY_APPS_ENV || "/run/factory-config/apps.env";
const AUTH_ROOT = process.env.FACTORY_AUTH_ROOT || "/run/factory-auth";
const REFRESH_MS = 45 * 60 * 1000;
const RUN_ONCE = process.argv.includes("--once");

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing apps config file: ${filePath}`);
  }
  const env = {};
  for (const line of fs.readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx > 0) {
      const key = trimmed.slice(0, idx).trim();
      let val = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, "");
      val = val.replace(/^\$HOME\b/, os.homedir()).replace(/^~\//, `${os.homedir()}/`);
      env[key] = val;
    }
  }
  return env;
}

function createAppJwt(appId, privateKeyPem) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "RS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(appId) })
  ).toString("base64url");
  const unsigned = `${header}.${payload}`;
  const signature = crypto
    .sign("RSA-SHA256", Buffer.from(unsigned), privateKeyPem)
    .toString("base64url");
  return `${unsigned}.${signature}`;
}

function writeAtomic(filePath, content, mode = 0o600) {
  const tmpPath = `${filePath}.tmp.${process.pid}`;
  fs.writeFileSync(tmpPath, content, { mode });
  fs.renameSync(tmpPath, filePath);
}

async function getBotUserId(slug, jwt) {
  try {
    const res = await fetch(`https://api.github.com/users/${slug}%5Bbot%5D`, {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${jwt}`,
        "User-Agent": "herdr-software-factory-token-refresher",
      },
    });
    if (res.ok) {
      const data = await res.json();
      return data.id ? String(data.id) : null;
    }
  } catch {
    // Non-fatal fallback
  }
  return null;
}

async function mintInstallationToken(roleName, appId, installationId, keyPath, slug) {
  if (!appId || !installationId || !keyPath) {
    throw new Error(`Incomplete configuration for role "${roleName}" in ${APPS_ENV_PATH}`);
  }
  const pem = fs.readFileSync(keyPath, "utf8");
  const jwt = createAppJwt(appId, pem);

  const res = await fetch(
    `https://api.github.com/app/installations/${installationId}/access_tokens`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${jwt}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "herdr-software-factory-token-refresher",
      },
    }
  );

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`GitHub token mint failed for ${roleName} (${res.status}): ${errText}`);
  }

  const data = await res.json();
  const botSlug = slug || `factory-${roleName}`;
  const botUserId = (await getBotUserId(botSlug, jwt)) || String(appId);

  const roleDir = path.join(AUTH_ROOT, roleName);
  fs.mkdirSync(roleDir, { recursive: true, mode: 0o700 });

  writeAtomic(path.join(roleDir, "token"), data.token, 0o600);
  writeAtomic(
    path.join(roleDir, "meta.json"),
    JSON.stringify(
      {
        role: roleName,
        slug: botSlug,
        appId: String(appId),
        userId: botUserId,
        expiresAt: data.expires_at,
        mintedAt: new Date().toISOString(),
      },
      null,
      2
    ),
    0o600
  );

  console.log(
    `[auth-minter] Minted 1h token for ${roleName} (${botSlug}[bot], id=${botUserId}) — expires ${data.expires_at}`
  );
}

async function refreshAll() {
  const cfg = loadEnvFile(APPS_ENV_PATH);
  fs.mkdirSync(AUTH_ROOT, { recursive: true, mode: 0o700 });

  await mintInstallationToken(
    "architect",
    cfg.ARCHITECT_APP_ID,
    cfg.ARCHITECT_INSTALLATION_ID,
    cfg.ARCHITECT_KEY_PATH,
    cfg.ARCHITECT_SLUG
  );

  await mintInstallationToken(
    "worker",
    cfg.WORKER_APP_ID,
    cfg.WORKER_INSTALLATION_ID,
    cfg.WORKER_KEY_PATH,
    cfg.WORKER_SLUG
  );

  const projectTokenPath = path.join(AUTH_ROOT, "architect", "project-token");
  if (cfg.GH_PROJECT_TOKEN) {
    writeAtomic(projectTokenPath, cfg.GH_PROJECT_TOKEN, 0o600);
  } else if (fs.existsSync(projectTokenPath)) {
    fs.unlinkSync(projectTokenPath);
  }
}

try {
  await refreshAll();
  if (RUN_ONCE) process.exit(0);
} catch (err) {
  console.error("[auth-minter] FATAL initial token mint error:", err.message);
  process.exit(1);
}

// Adaptive schedule: retries in 60s upon network or API error, or 45 mins on success
async function scheduleNextRefresh(delayMs) {
  setTimeout(async () => {
    try {
      await refreshAll();
      scheduleNextRefresh(REFRESH_MS);
    } catch (err) {
      console.error("[auth-minter] ERROR refreshing tokens (retrying in 60s):", err.message);
      scheduleNextRefresh(60 * 1000);
    }
  }, delayMs);
}

scheduleNextRefresh(REFRESH_MS);
