#!/usr/bin/env node
// Fetches per-account Claude quota from the 9router dashboard API and writes
// it to ~/.cache/9router-usage.json for statusline.sh to render. Run in the
// background by the status line; never prints anything.
//
// Cache shape: { fetchedAt, accounts: [{ name, five, fiveReset, week, weekReset }] }
// where five/week are % used and *Reset are epoch seconds (or null).
//
// Configuration (environment variables, or the files named below):
//   NINEROUTER_URL                 dashboard base URL. Defaults to ANTHROPIC_BASE_URL
//                                  (Claude Code exports settings.json "env" to this process).
//   NINEROUTER_DASHBOARD_PASSWORD  dashboard password. Defaults to the contents of
//                                  ~/.config/9router/dashboard-password.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const HOME = os.homedir();
const BASE = (process.env.NINEROUTER_URL || process.env.ANTHROPIC_BASE_URL || "")
  .replace(/\/+$/, "")
  .replace(/\/v1$/, "");
const CACHE = path.join(HOME, ".cache", "9router-usage.json");
const JAR = path.join(HOME, ".cache", "9router-dashboard-cookie");
const PASSWORD_FILE = path.join(HOME, ".config", "9router", "dashboard-password");

fs.mkdirSync(path.dirname(CACHE), { recursive: true });

async function login() {
  const password = (
    process.env.NINEROUTER_DASHBOARD_PASSWORD || fs.readFileSync(PASSWORD_FILE, "utf8")
  ).trim();
  const res = await fetch(`${BASE}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (!res.ok) throw new Error(`login ${res.status}`);
  const cookie = res.headers.getSetCookie().find((c) => c.startsWith("auth_token="));
  if (!cookie) throw new Error("no auth_token cookie");
  const value = cookie.split(";")[0];
  fs.writeFileSync(JAR, value, { mode: 0o600 });
  return value;
}

// The dashboard session lasts 24h; reuse it and log in again only on 401.
async function api(pathname) {
  let cookie = fs.existsSync(JAR) ? fs.readFileSync(JAR, "utf8").trim() : await login();
  let res = await fetch(`${BASE}${pathname}`, { headers: { cookie } });
  if (res.status === 401) {
    cookie = await login();
    res = await fetch(`${BASE}${pathname}`, { headers: { cookie } });
  }
  if (!res.ok) throw new Error(`${pathname} ${res.status}`);
  return res.json();
}

const epoch = (iso) => (iso ? Math.floor(Date.parse(iso) / 1000) : null);

try {
  const { connections } = await api("/api/providers");
  const claude = connections
    .filter((c) => c.provider === "claude" && c.isActive)
    .sort((a, b) => (a.priority || 999) - (b.priority || 999));

  const accounts = await Promise.all(
    claude.map(async (c) => {
      const { quotas = {} } = await api(`/api/usage/${c.id}`);
      const five = quotas["session (5h)"];
      const week = quotas["weekly (7d)"];
      return {
        name: c.name || c.email || c.id.slice(0, 8),
        five: five?.used ?? null,
        fiveReset: epoch(five?.resetAt),
        week: week?.used ?? null,
        weekReset: epoch(week?.resetAt),
      };
    }),
  );

  const tmp = `${CACHE}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ fetchedAt: Math.floor(Date.now() / 1000), accounts }));
  fs.renameSync(tmp, CACHE);
} catch {
  // Leave the previous cache in place; the status line shows it as-is.
}
