import { test, describe } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { loadEnvFile, createAppJwt, writeAtomic, scheduleNextRefresh } from "../.factory/token-refresher.mjs";

describe("Token Refresher Unit Tests", () => {
  const tmpDir = path.join(os.tmpdir(), "factory-token-refresher-test-" + Date.now());

  test("loadEnvFile correctly parses variables, trims comments and quotes", () => {
    fs.mkdirSync(tmpDir, { recursive: true });
    const testEnvPath = path.join(tmpDir, "test-apps.conf");
    fs.writeFileSync(
      testEnvPath,
      [
        "# This is a comment",
        "ARCHITECT_APP_ID=123456 # inline comment",
        'ARCHITECT_SLUG="factory-architect"',
        "ARCHITECT_KEY_PATH=$HOME/keys/arch.pem",
        "",
        "EMPTY_VAL=",
      ].join("\n"),
      "utf8"
    );

    const parsed = loadEnvFile(testEnvPath);
    assert.equal(parsed.ARCHITECT_APP_ID, "123456");
    assert.equal(parsed.ARCHITECT_SLUG, "factory-architect");
    assert.equal(parsed.ARCHITECT_KEY_PATH, path.join(os.homedir(), "keys/arch.pem"));
    assert.equal(parsed.EMPTY_VAL, "");

    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  test("createAppJwt generates a valid RS256 JWT header and signature structure", () => {
    // Generate ephemeral 2048-bit RSA keypair for testing
    const { privateKey } = crypto.generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });

    const appId = "998877";
    const jwt = createAppJwt(appId, privateKey);
    const parts = jwt.split(".");
    assert.equal(parts.length, 3);

    const header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));

    assert.equal(header.alg, "RS256");
    assert.equal(header.typ, "JWT");
    assert.equal(payload.iss, appId);
    assert.ok(payload.exp > payload.iat);
  });

  test("writeAtomic writes file atomically and sets proper mode", () => {
    fs.mkdirSync(tmpDir, { recursive: true });
    const targetFile = path.join(tmpDir, "atomic-test.txt");
    writeAtomic(targetFile, "secret-token-content", 0o600);

    assert.ok(fs.existsSync(targetFile));
    assert.equal(fs.readFileSync(targetFile, "utf8"), "secret-token-content");
    const stat = fs.statSync(targetFile);
    assert.equal(stat.mode & 0o777, 0o600);

    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  test("scheduleNextRefresh is defined and schedules a clearable refresh timer", () => {
    const timer = scheduleNextRefresh(60_000);
    assert.ok(timer);
    clearTimeout(timer);
  });
});
