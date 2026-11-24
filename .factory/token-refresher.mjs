#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const isDirectRun = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

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
      let val = trimmed.slice(idx + 1).trim();
      if (!val.startsWith('"') && !val.startsWith("'")) {
        val = val.replace(/\s+#.*$/, "").trim();
      } else {
        val = val.replace(/^["']|["']$/g, "");
      }
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
  let pemPath = keyPath;
  if (!fs.existsSync(pemPath)) {
    const baseName = path.basename(keyPath);
    const inContainerPath = path.join("/run/factory-keys", baseName);
    if (fs.existsSync(inContainerPath)) {
      pemPath = inContainerPath;
    }
  }
  const pem = fs.readFileSync(pemPath, "utf8");
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

let refreshTimer = null;

function scheduleNextRefresh(delayMs = REFRESH_MS) {
  if (refreshTimer) clearTimeout(refreshTimer);
  refreshTimer = setTimeout(async () => {
    try {
      await refreshAll();
      scheduleNextRefresh(REFRESH_MS);
    } catch (err) {
      console.error("[auth-minter] Scheduled token refresh failed; retrying in 60s:", err.message);
      scheduleNextRefresh(60_000);
    }
  }, delayMs);
  if (typeof refreshTimer.unref === "function") refreshTimer.unref();
  return refreshTimer;
}

if (isDirectRun) {
  let booted = false;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      await refreshAll();
      booted = true;
      break;
    } catch (err) {
      console.error(`[auth-minter] Initial token mint attempt ${attempt}/3 failed:`, err.message);
      if (attempt < 3) await new Promise((r) => setTimeout(r, 3000));
    }
  }

  if (!booted) {
    console.error("[auth-minter] FATAL initial token mint error: all 3 attempts exhausted.");
    process.exit(1);
  }

  if (RUN_ONCE) process.exit(0);

  const activeTimer = scheduleNextRefresh(REFRESH_MS);
  if (typeof activeTimer.ref === "function") activeTimer.ref();
}

export {
  loadEnvFile,
  createAppJwt,
  getBotUserId,
  mintInstallationToken,
  refreshAll,
  scheduleNextRefresh,
  writeAtomic,
};
