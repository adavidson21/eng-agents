#!/usr/bin/env node
// eng-agents live dashboard server.
//
// Serves the dashboard page on 127.0.0.1 and keeps it current:
//   - Watches .work and polls git, rebuilding the data with New-Dashboard.ps1 -AsJson
//     (the same parser and next-step rules as the static /dashboard page).
//   - Connects to opencode and follows its event stream: session busy/idle, tool activity,
//     agent replies, permission prompts, and questions. Works with both server APIs:
//       opencode 2.x  the shared background service (`opencode service start`), /api routes,
//                     password from the service's service.json
//       opencode 1.x  `opencode serve` on port 4096, started here if none is running
//   - Runs pipeline commands from the page: one opencode session per work item, except
//     /do-task and /check-docs, which get a fresh session as the pipeline requires.
//
// No dependencies beyond Node 18+. Writes to .work/_dashboard/ and keeps .work/dashboard.html (the
// static page) current. Deletes an item's .work/<folder> only when you abandon or remove it from the
// page. Never calls ADO.
// Usually started by Start-LiveDashboard.ps1. Run with --help for options.
//
// This file is the HTTP server and startup. The rest is in server/, one module per concern:
//   context.mjs           options, paths, session token, allowed shell sites, logging, PowerShell
//   model.mjs             New-Dashboard.ps1 -AsJson, watching .work, the static page snapshot
//   links.mjs             which opencode session belongs to which work item
//   opencode-state.mjs    live opencode state shared by both APIs, HTTP helpers
//   opencode-v2.mjs       opencode 2.x adapter        opencode-v1.mjs   opencode 1.x adapter
//   opencode-connect.mjs  finding opencode, loading state, following its events
//   actions.mjs           page actions and the shell API (docs/shell-api.md)
//   autopilot.mjs         hands-off build after the plan
//   updates.mjs           update checks and updates through update.ps1
//   live.mjs              page data and the event stream to open pages
// Only context.mjs is used while modules load; everything else is called at run time, so the
// modules can import each other freely.

import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { APP, fail, httpError, isWin, log, opt, sameDir, selfOrigins, shellOrigins, templatePath, token, workRoot } from "./server/context.mjs";
import { refresh, watchWork } from "./server/model.mjs";
import { connectOpencode } from "./server/opencode-connect.mjs";
import { abort, answerPermission, answerQuestion, attachCommand, openTerminal, pushBranch, removeItem, reply, runCommand, shellData, startItem } from "./server/actions.mjs";
import { autopilotAction } from "./server/autopilot.mjs";
import { UPDATE_EVERY_MS, checkUpdates, restartAction, runUpdate } from "./server/updates.mjs";
import { clients, pageData } from "./server/live.mjs";

// ------------------------------------------------------------------ HTTP server

function send(res, status, body, type = "application/json; charset=utf-8") {
  res.writeHead(status, { "content-type": type, "cache-control": "no-store", "x-content-type-options": "nosniff" });
  res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let b = "";
    req.on("data", (c) => {
      b += c;
      if (b.length > 1e6) reject(httpError(413, "Too large."));
    });
    req.on("end", () => {
      try {
        resolve(b ? JSON.parse(b) : {});
      } catch {
        reject(httpError(400, "Bad JSON."));
      }
    });
  });
}

function renderPage() {
  const tpl = fs.readFileSync(templatePath, "utf8");
  const json = JSON.stringify(pageData()).replace(/</g, "\\u003c").replace(/>/g, "\\u003e").replace(/&/g, "\\u0026");
  return tpl.replace("__ENG_DATA__", () => json);
}

// .work/<folder>/<file>.md only, read-only.
function serveWorkFile(res, rel) {
  let parts;
  try {
    parts = rel.split("/").map(decodeURIComponent);
  } catch {
    return send(res, 404, "Not found", "text/plain");
  }
  if (parts.length !== 2 || !/\.md$/i.test(parts[1]) || parts.some((p) => !p || p.startsWith(".") || /[\\/]/.test(p))) return send(res, 404, "Not found", "text/plain");
  const full = path.join(workRoot, parts[0], parts[1]);
  if (!full.startsWith(workRoot + path.sep)) return send(res, 404, "Not found", "text/plain");
  fs.readFile(full, (err, buf) => (err ? send(res, 404, "Not found", "text/plain") : send(res, 200, buf, "text/plain; charset=utf-8")));
}

const actions = {
  "/api/run": (body) => runCommand(body),
  "/api/autopilot": autopilotAction,
  "/api/reply": reply,
  "/api/permission": answerPermission,
  "/api/question": answerQuestion,
  "/api/abort": abort,
  "/api/remove": removeItem,
  "/api/push": pushBranch,
  "/api/terminal": openTerminal,
  "/api/update": runUpdate,
  "/api/update-check": async () => {
    checkUpdates();
    return { ok: true };
  },
  "/api/restart": restartAction,
  "/api/refresh": async () => {
    await refresh();
    return { ok: true };
  },
};

// The shell API: a configured shell site reads item stages and starts items. Browsers send Origin on
// these cross-site requests and cannot fake it, so the allowlist is the check (like the ADO helper).
const shellActions = {
  "GET /api/shell/status": async () => shellData(),
  "POST /api/shell/start": (body) => startItem(body),
};

function sendShell(res, origin, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "access-control-allow-origin": origin,
    vary: "Origin",
  });
  res.end(JSON.stringify(body));
}

// Only these sites may put the page in a frame (clickjacking guard): this page and configured shells.
const frameAncestors = () => ["'self'", ...shellOrigins].join(" ");

const server = http.createServer(async (req, res) => {
  // Only this machine, only this page: block other sites and DNS rebinding.
  const host = String(req.headers.host || "");
  if (host !== `127.0.0.1:${opt.port}` && host !== `localhost:${opt.port}`) return send(res, 403, { error: "Bad host." });
  const origin = req.headers.origin;
  const url = new URL(req.url, `http://${host}`);

  if (url.pathname.startsWith("/api/shell/")) {
    if (!origin || !shellOrigins.includes(origin)) return send(res, 403, { error: "This site is not an allowed shell. Add it to dashboard.shellOrigins in config.json." });
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "access-control-allow-origin": origin,
        "access-control-allow-methods": "GET, POST, OPTIONS",
        "access-control-allow-headers": "content-type",
        "access-control-allow-private-network": "true",
        "access-control-max-age": "600",
        vary: "Origin",
      });
      return res.end();
    }
    const fn = shellActions[`${req.method} ${url.pathname}`];
    if (!fn) return sendShell(res, origin, 404, { error: "Not found." });
    try {
      const body = req.method === "POST" ? await readBody(req) : {};
      return sendShell(res, origin, 200, await fn(body));
    } catch (e) {
      if (!e.status) log("error:", e.stack || e.message);
      return sendShell(res, origin, e.status || 500, { error: e.message });
    }
  }

  if (origin && !selfOrigins().includes(origin)) return send(res, 403, { error: "Bad origin." });
  try {
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      res.setHeader("content-security-policy", `frame-ancestors ${frameAncestors()}`);
      return send(res, 200, renderPage(), "text/html; charset=utf-8");
    }
    if (req.method === "GET" && url.pathname === "/api/ping") return send(res, 200, { app: APP, workspace: opt.workspace });
    if (req.method === "GET" && url.pathname.startsWith("/files/")) return serveWorkFile(res, url.pathname.slice(7));
    if (req.method === "GET" && url.pathname === "/api/events") {
      if (url.searchParams.get("token") !== token) return send(res, 403, { error: "Reload the page." });
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive" });
      res.write(`event: model\ndata: ${JSON.stringify(pageData())}\n\n`);
      clients.add(res);
      const ping = setInterval(() => res.write(": ping\n\n"), 25000);
      req.on("close", () => {
        clearInterval(ping);
        clients.delete(res);
      });
      return;
    }
    if (req.method === "POST" && actions[url.pathname]) {
      if (req.headers["x-eng-token"] !== token) return send(res, 403, { error: "Reload the page." });
      const body = await readBody(req);
      return send(res, 200, await actions[url.pathname](body));
    }
    send(res, 404, { error: "Not found." });
  } catch (e) {
    if (!e.status) log("error:", e.stack || e.message);
    send(res, e.status || 500, { error: e.message });
  }
});

function openBrowser(url) {
  try {
    if (isWin) spawn("cmd", ["/c", "start", "", url], { detached: true, stdio: "ignore", windowsHide: true }).unref();
    else if (process.platform === "darwin") spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
    else spawn("xdg-open", [url], { detached: true, stdio: "ignore" }).on("error", () => {}).unref();
  } catch {}
}

// Already running for this workspace? Just open it.
async function alreadyRunning() {
  try {
    const r = await fetch(`http://127.0.0.1:${opt.port}/api/ping`, { signal: AbortSignal.timeout(1500) });
    const j = await r.json();
    return j && j.app === APP ? j : { other: true };
  } catch {
    return null;
  }
}

const pageUrl = `http://127.0.0.1:${opt.port}/`;
const running = await alreadyRunning();
if (running && running.app === APP && sameDir(running.workspace, opt.workspace)) {
  console.log(`Already running: ${pageUrl}`);
  if (opt.open) openBrowser(pageUrl);
  process.exit(0);
}
if (running) fail(`Port ${opt.port} is in use${running.workspace ? " by the dashboard for " + running.workspace : ""}. Pick another port (Start-LiveDashboard.ps1 -Port <n>).`);

server.on("error", (e) => fail(e.code === "EADDRINUSE" ? `Port ${opt.port} is in use. Pick another port (Start-LiveDashboard.ps1 -Port <n>).` : e.message));
server.listen(opt.port, "127.0.0.1", async () => {
  console.log(`Live dashboard: ${pageUrl}`);
  console.log(`Workspace:      ${opt.workspace}`);
  if (shellOrigins.length) console.log(`Shell sites:    ${shellOrigins.join(", ")}`);
  console.log("Keep this window open. Ctrl+C stops the dashboard (and opencode 1.x if the dashboard started it).");
  await refresh();
  watchWork();
  await connectOpencode();
  const tui = attachCommand(null);
  if (tui) console.log(`Terminal on the same sessions: ${tui}`);
  if (opt.open) openBrowser(pageUrl);
  if (opt.checkUpdates) {
    setTimeout(checkUpdates, 15000);
    setInterval(checkUpdates, UPDATE_EVERY_MS).unref();
  }
});

// SIGHUP: the console window was closed (Windows) or the terminal went away.
for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(sig, () => process.exit(0));
