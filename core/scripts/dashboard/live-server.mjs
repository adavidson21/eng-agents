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
// No dependencies beyond Node 18+. Never writes outside .work/_dashboard/. Never calls ADO.
// Usually started by Start-LiveDashboard.ps1. Run with --help for options.

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = "eng-agents-dashboard";
const FRESH_SESSION = new Set(["do-task", "check-docs"]); // the pipeline says: run these in a new session
const isWin = process.platform === "win32";
const V1_DEFAULT_URL = "http://127.0.0.1:4096";

// ------------------------------------------------------------------ options

function parseArgs(argv) {
  const o = {
    workspace: process.cwd(),
    port: 4300,
    opencode: null, // null: find it (2.x background service, else 1.x on 4096)
    startOpencode: true,
    opencodeCmd: "opencode",
    ps: null,
    config: null,
    open: true,
    poll: 20,
    checkUpdates: true,
    shellOrigins: [],
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const v = () => {
      if (i + 1 >= argv.length) fail(`Missing value for ${a}`);
      return argv[++i];
    };
    if (a === "--workspace") o.workspace = v();
    else if (a === "--port") o.port = +v();
    else if (a === "--opencode") o.opencode = v().replace(/\/+$/, "");
    else if (a === "--no-start-opencode") o.startOpencode = false;
    else if (a === "--opencode-cmd") o.opencodeCmd = v();
    else if (a === "--ps") o.ps = v();
    else if (a === "--config") o.config = v();
    else if (a === "--no-open") o.open = false;
    else if (a === "--no-update-check") o.checkUpdates = false;
    else if (a === "--poll") o.poll = Math.max(5, +v());
    else if (a === "--shell-origin") o.shellOrigins.push(v());
    else if (a === "--help" || a === "-h") {
      console.log(`Usage: node live-server.mjs [options]

  --workspace <dir>      Workspace root (the folder that holds .work). Default: current folder
  --port <n>             Dashboard port. Default: 4300
  --opencode <url>       opencode server to use. Default: found automatically
                         (2.x: the background service; 1.x: http://127.0.0.1:4096)
  --no-start-opencode    Do not start opencode if it is not running
  --opencode-cmd <cmd>   Command that runs opencode. Default: opencode
  --ps <exe>             PowerShell to run New-Dashboard.ps1. Default: pwsh, else powershell
  --config <path>        ADO config.json passed to New-Dashboard.ps1 (for work item links)
  --poll <seconds>       How often to re-read git state. Default: 20
  --no-open              Do not open the browser
  --no-update-check      Do not check for eng-agents updates (update.ps1 -Check)
  --shell-origin <url>   A site allowed to embed this dashboard and read item stages, for example
                         https://prioritizer.example.com. Repeatable. Also read from
                         "dashboard": { "shellOrigins": [...] } in the --config file.`);
      process.exit(0);
    } else fail(`Unknown option: ${a}. Run with --help.`);
  }
  o.workspace = path.resolve(o.workspace);
  return o;
}

function fail(msg) {
  console.error(`live dashboard: ${msg}`);
  process.exit(1);
}

const major = +process.versions.node.split(".")[0];
if (major < 18) fail(`Node 18 or newer is required (found ${process.versions.node}).`);

const opt = parseArgs(process.argv.slice(2));
const workRoot = path.join(opt.workspace, ".work");
if (!fs.existsSync(workRoot)) fail(`No .work folder in ${opt.workspace}. Run this from your workspace root, or pass --workspace.`);
const stateDir = path.join(workRoot, "_dashboard");
const sessionsFile = path.join(stateDir, "sessions.json");
const scriptPath = path.join(HERE, "New-Dashboard.ps1");
const templatePath = path.join(HERE, "dashboard.template.html");
if (!fs.existsSync(scriptPath)) fail(`Missing ${scriptPath}. Re-run install.ps1.`);
if (!fs.existsSync(templatePath)) fail(`Missing ${templatePath}. Re-run install.ps1.`);
fs.mkdirSync(stateDir, { recursive: true });

const token = crypto.randomBytes(18).toString("base64url");

// Sites allowed to embed this dashboard (a "shell" such as Prioritizer) and to use /api/shell/*.
// Off unless configured: --shell-origin, or "dashboard": { "shellOrigins": [...] } in config.json.
function normalizeOrigin(o) {
  try {
    const u = new URL(String(o).trim());
    const local = u.hostname === "127.0.0.1" || u.hostname === "localhost";
    if (u.protocol !== "https:" && !(u.protocol === "http:" && local)) return null; // https, or http on this machine (for testing)
    if (u.pathname !== "/" || u.search || u.hash || u.username) return null;
    return u.origin;
  } catch {
    return null;
  }
}
function readShellOrigins() {
  const list = [...opt.shellOrigins];
  if (opt.config) {
    try {
      const cfg = JSON.parse(fs.readFileSync(opt.config, "utf8").replace(/^\uFEFF/, ""));
      const fromCfg = cfg && cfg.dashboard && cfg.dashboard.shellOrigins;
      if (Array.isArray(fromCfg)) list.push(...fromCfg);
    } catch {} // no config, or unreadable: New-Dashboard.ps1 reports that
  }
  const out = [];
  for (const o of list) {
    const n = normalizeOrigin(o);
    if (!n) console.warn(`live dashboard: ignoring shell origin "${o}" (use https://host, or http://localhost:<port> for testing).`);
    else if (!out.includes(n)) out.push(n);
  }
  return out;
}
const shellOrigins = readShellOrigins();
const selfOrigins = () => [`http://127.0.0.1:${opt.port}`, `http://localhost:${opt.port}`];
const log = (...a) => console.log(new Date().toLocaleTimeString(), ...a);
const sameDir = (a, b) => {
  if (!a || !b) return false;
  const x = path.resolve(a), y = path.resolve(b);
  return isWin ? x.toLowerCase() === y.toLowerCase() : x === y;
};
// The workspace root or a folder inside it (a TUI started inside one of its repos).
const inWorkspace = (dir) => {
  if (!dir) return false;
  const x = path.resolve(dir), y = opt.workspace;
  const [a, b] = isWin ? [x.toLowerCase(), y.toLowerCase()] : [x, y];
  return a === b || a.startsWith(b + path.sep);
};

function findPs() {
  if (opt.ps) return opt.ps;
  for (const exe of ["pwsh", "powershell"]) {
    const r = spawnSync(exe, ["-NoProfile", "-Command", "$PSVersionTable.PSVersion.Major"], { encoding: "utf8", windowsHide: true });
    if (r.status === 0) return exe;
  }
  fail("PowerShell not found. Install PowerShell 7 (pwsh) or pass --ps.");
}
const psExe = findPs();

// ------------------------------------------------------------------ the model (New-Dashboard.ps1 -AsJson)

let model = null;
let modelError = null;
let refreshing = false;
let refreshAgain = false;

function runModel() {
  return new Promise((resolve) => {
    const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "-WorkRoot", workRoot, "-AsJson"];
    if (opt.config) args.push("-ConfigPath", opt.config);
    const p = spawn(psExe, args, { cwd: opt.workspace, windowsHide: true });
    let out = "";
    let err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("error", (e) => resolve({ error: e.message }));
    p.on("close", (code) => {
      if (code !== 0) return resolve({ error: (err || out || `exit ${code}`).trim().split(/\r?\n/).slice(-3).join(" ") });
      try {
        resolve({ data: JSON.parse(out) });
      } catch (e) {
        resolve({ error: "Could not read New-Dashboard.ps1 output: " + e.message });
      }
    });
  });
}

async function refresh() {
  if (refreshing) {
    refreshAgain = true;
    return;
  }
  refreshing = true;
  try {
    const r = await runModel();
    if (r.error) {
      modelError = r.error;
      log("refresh failed:", r.error);
    } else {
      model = r.data;
      modelError = null;
      linkSessionsFromModel();
    }
    broadcast("model", pageData());
  } finally {
    refreshing = false;
    if (refreshAgain) {
      refreshAgain = false;
      setTimeout(refresh, 50);
    }
  }
}

let debounce = null;
function scheduleRefresh(ms = 400) {
  clearTimeout(debounce);
  debounce = setTimeout(refresh, ms);
}

function watchWork() {
  const ignore = (f) => !f || /^_dashboard([\\/]|$)/.test(f) || /dashboard\.html$/i.test(f);
  try {
    fs.watch(workRoot, { recursive: true }, (_e, f) => {
      if (!ignore(String(f || ""))) scheduleRefresh();
    });
  } catch (e) {
    log("File watching is not available here; polling only.", e.message);
  }
  setInterval(() => scheduleRefresh(0), opt.poll * 1000);
}

// ------------------------------------------------------------------ item <-> session links (.work/_dashboard/sessions.json)

// { "<folder>": { "sessions": [ { "id": "ses_...", "command": "/do-task 41207 3", "created": "<iso>" } ] } }
let links = {};
try {
  links = JSON.parse(fs.readFileSync(sessionsFile, "utf8")) || {};
} catch {
  links = {};
}

function saveLinks() {
  const tmp = sessionsFile + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(links, null, 2));
  fs.renameSync(tmp, sessionsFile);
}

function linkSession(folder, id, command) {
  if (!folder || !id) return;
  const entry = (links[folder] = links[folder] || { sessions: [] });
  const found = entry.sessions.find((s) => s.id === id);
  if (found) {
    if (command) found.command = command;
    entry.sessions = entry.sessions.filter((s) => s.id !== id).concat(found);
  } else {
    entry.sessions.push({ id, command: command || null, created: new Date().toISOString() });
    if (entry.sessions.length > 20) entry.sessions = entry.sessions.slice(-20);
  }
  saveLinks();
}

function currentSession(folder) {
  const e = links[folder];
  if (!e || !e.sessions.length) return null;
  return e.sessions[e.sessions.length - 1].id;
}

function folderForSession(id) {
  for (const [f, e] of Object.entries(links)) if (e.sessions.some((s) => s.id === id)) return f;
  return null;
}

// Which item a token belongs to: "41207", "tsd-x", ".work/docs-y/guide.md".
function folderForToken(tok) {
  if (!model || !tok) return null;
  const t = String(tok).trim().replace(/\\/g, "/");
  for (const it of model.items || []) {
    if (it.id && t === String(it.id)) return it.folder;
    if (t === it.folder) return it.folder;
    if (t.includes(`.work/${it.folder}/`) || t === `.work/${it.folder}`) return it.folder;
  }
  return null;
}

// From command arguments ("41207 3").
function folderForArgs(args) {
  return folderForToken(String(args || "").trim().split(/\s+/)[0]);
}

// From an expanded eng-agents command prompt. Each one names its item in bold on the first line,
// for example "Do task **3** of work item **41207**." (opencode 2.x sends only the expanded text).
function folderForPrompt(text) {
  const first = String(text || "").split(/\r?\n/)[0];
  const bold = first.match(/\*\*([^*]+)\*\*/g) || [];
  for (const b of bold) {
    const f = folderForToken(b.slice(2, -2).trim().split(/\s+/)[0]);
    if (f) return f;
  }
  return null;
}

// Commands run before the model existed (or before an item folder existed) get linked once it does.
const unlinked = new Map(); // sessionID -> { find: () => folder, command }
function linkSessionsFromModel() {
  for (const [sid, u] of unlinked) {
    const f = u.find();
    if (f) {
      linkSession(f, sid, u.command);
      unlinked.delete(sid);
    }
  }
}

function linkFrom(sid, find, command) {
  if (!sid || folderForSession(sid)) return;
  const f = find();
  if (f) linkSession(f, sid, command);
  else unlinked.set(sid, { find, command });
}

// ------------------------------------------------------------------ live opencode state (shared by both APIs)

const oc = {
  api: null, // the adapter in use
  kind: null, // "v2" | "v1"
  url: null,
  connected: false,
  version: null,
  error: null,
  started: false, // we started a 1.x `opencode serve`
  commands: new Set(),
};
const sessions = new Map(); // id -> { id, title, status, activity, text, textAt, busySince, error, command }
const permissions = new Map(); // id -> normalized request
const questions = new Map(); // id -> normalized request

function upsertSession(id, patch) {
  if (!id) return {};
  const s = sessions.get(id) || { id, title: null, status: "idle", activity: null, text: null, error: null, updated: null };
  for (const [k, v] of Object.entries(patch)) if (v !== undefined) s[k] = v;
  sessions.set(id, s);
  return s;
}

function setBusy(sid) {
  const prev = sessions.get(sid);
  const starting = !prev || prev.status === "idle";
  upsertSession(sid, { status: "busy", ...(starting ? { error: null, busySince: Date.now() } : {}) });
  autoOnBusy(sid);
}

function setIdle(sid, error) {
  upsertSession(sid, { status: "idle", activity: null, ...(error !== undefined ? { error } : {}) });
  oc.api.lastText(sid).then(broadcastLive, () => {});
  autoOnIdle(sid);
}

const turnText = new Map(); // text block key -> text so far
function appendText(sid, key, delta) {
  const t = (turnText.get(key) || "") + (delta || "");
  turnText.set(key, t);
  if (turnText.size > 500) turnText.delete(turnText.keys().next().value);
  upsertSession(sid, { text: t, textAt: Date.now(), activity: "Writing a reply" });
}

function setText(sid, key, text) {
  if (key) turnText.set(key, text || "");
  upsertSession(sid, { text: text || "", textAt: Date.now(), activity: "Writing a reply" });
}

function toolLine(name, input, title) {
  const inp = input || {};
  const what = title || inp.description || inp.command || inp.filePath || inp.path || inp.pattern || "";
  return `${name}${what ? ": " + String(what).split(/\r?\n/)[0].slice(0, 160) : ""}`;
}

let promptsTimer = null;
function refreshPromptsSoon() {
  clearTimeout(promptsTimer);
  promptsTimer = setTimeout(() => {
    oc.api.loadPrompts().then(broadcastLive, (e) => log("prompts:", e.message));
  }, 120);
}

// ------------------------------------------------------------------ HTTP helpers for opencode

async function httpJson(url, { method = "GET", body, headers = {}, timeout = 15000 } = {}) {
  const ctrl = new AbortController();
  const t = timeout ? setTimeout(() => ctrl.abort(), timeout) : null;
  try {
    const r = await fetch(url, {
      method,
      headers: { ...(body !== undefined ? { "content-type": "application/json" } : {}), ...headers },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
    const text = await r.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = text;
    }
    return { ok: r.ok, status: r.status, data, type: r.headers.get("content-type") || "" };
  } finally {
    if (t) clearTimeout(t);
  }
}

function errText(r) {
  const d = r && r.data;
  const msg = d && typeof d === "object" ? d.message || (d.data && d.data.message) || d.name || d._tag : null;
  return msg ? String(msg).slice(0, 300) : `HTTP ${r ? r.status : "?"}`;
}

// Runs the opencode CLI (fixed arguments only) and returns its output. Never blocks the page.
function ocCli(args, timeout = 30000) {
  return new Promise((resolve) => {
    const o = { cwd: opt.workspace, windowsHide: true };
    // On Windows opencode may be a .cmd shim, which needs a shell. The arguments are fixed, so one string is safe.
    const p = isWin ? spawn(`"${opt.opencodeCmd}" ${args.join(" ")}`, { ...o, shell: true }) : spawn(opt.opencodeCmd, args, o);
    let out = "";
    let err = "";
    const t = setTimeout(() => {
      err += " (timed out)";
      try { p.kill(); } catch {}
    }, timeout);
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("error", (e) => {
      clearTimeout(t);
      resolve({ ok: false, out: "", err: e.message });
    });
    p.on("close", (code) => {
      clearTimeout(t);
      resolve({ ok: code === 0, out: out.trim(), err: err.trim() });
    });
  });
}

// ------------------------------------------------------------------ opencode 2.x adapter

function makeV2(url, password) {
  const base = url.replace(/\/+$/, "");
  const auth = password ? { authorization: "Basic " + Buffer.from(`${process.env.OPENCODE_SERVER_USERNAME || "opencode"}:${password}`).toString("base64") } : {};
  const loc = () => `location%5Bdirectory%5D=${encodeURIComponent(opt.workspace)}`;
  const call = (p, o = {}) => httpJson(base + p, { ...o, headers: { ...auth, ...(o.headers || {}) } });
  const wsSessions = new Set(); // sessions in this workspace
  const toolNames = new Map(); // tool call id -> tool name

  function normPermission(p) {
    return {
      id: p.id,
      sessionID: p.sessionID,
      permission: p.action,
      patterns: p.resources || [],
      always: p.save || [],
      title: (p.metadata && (p.metadata.command || p.metadata.filepath || p.metadata.filePath)) || (p.resources || [])[0] || null,
      message: p.message || null,
    };
  }
  function normForm(f) {
    return {
      id: f.id,
      sessionID: f.sessionID,
      title: f.title,
      questions: (f.fields || []).map((x) => ({
        key: x.key,
        header: x.title || "",
        question: x.description || x.title || "",
        options: (x.options || []).map((o) => ({ label: o.label || String(o.value), value: o.value !== undefined ? o.value : o.label, description: o.description || "" })),
        multiple: x.type === "multiselect" || !!x.multiple,
        custom: x.custom !== false,
      })),
    };
  }

  return {
    kind: "v2",
    url: base,
    hasPassword: !!password,
    async info() {
      const r = await call("/api/info", { timeout: 3000 });
      return r.ok && r.data ? { version: r.data.version || null } : null;
    },
    async loadCommands() {
      const r = await call(`/api/command?${loc()}`);
      if (r.ok && r.data && Array.isArray(r.data.data)) oc.commands = new Set(r.data.data.map((c) => c.name));
    },
    async loadSessions() {
      const r = await call(`/api/session?directory=${encodeURIComponent(opt.workspace)}&limit=200`);
      const list = r.ok && r.data && Array.isArray(r.data.data) ? r.data.data : null;
      if (!list) return null;
      for (const s of list) {
        wsSessions.add(s.id);
        upsertSession(s.id, { title: s.title || null, updated: s.time && s.time.updated });
      }
      const act = await call("/api/session/active");
      const active = act.ok && act.data && act.data.data ? act.data.data : {};
      for (const id of wsSessions) upsertSession(id, { status: active[id] ? "busy" : "idle" });
      return list.map((s) => s.id);
    },
    async sessionExists(id) {
      const r = await call(`/api/session/${id}`);
      return r.ok;
    },
    async loadPrompts() {
      const [p, f] = await Promise.all([call(`/api/permission/request?${loc()}`), call(`/api/form?${loc()}`)]);
      if (p.ok && p.data && Array.isArray(p.data.data)) {
        permissions.clear();
        for (const x of p.data.data) permissions.set(x.id, normPermission(x));
      }
      if (f.ok && f.data && Array.isArray(f.data.data)) {
        questions.clear();
        for (const x of f.data.data) questions.set(x.id, normForm(x));
      }
    },
    async lastText(id) {
      if (!id) return;
      const r = await call(`/api/session/${id}/message?limit=12&order=desc`);
      const list = r.ok && r.data && Array.isArray(r.data.data) ? r.data.data : null;
      if (!list) return;
      for (const m of list) {
        if (m.type !== "assistant") continue;
        const text = (m.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();
        if (text) {
          upsertSession(id, { text, textAt: (m.time && (m.time.completed || m.time.created)) || null });
          return;
        }
      }
    },
    async createSession(title) {
      const r = await call("/api/session", { method: "POST", body: { title, location: { directory: opt.workspace } } });
      if (!r.ok || !r.data || !r.data.data) throw httpError(502, `opencode could not create a session (${errText(r)}).`);
      wsSessions.add(r.data.data.id);
      return { id: r.data.data.id, title: r.data.data.title || title };
    },
    async runCommand(id, name, args) {
      const r = await call(`/api/session/${id}/command`, { method: "POST", body: { name, text: args }, timeout: 30000 });
      return r.ok ? null : errText(r);
    },
    async prompt(id, text) {
      const r = await call(`/api/session/${id}/prompt`, { method: "POST", body: { text } });
      if (!r.ok) throw httpError(502, `opencode did not take the reply (${errText(r)}).`);
    },
    async abort(id) {
      const r = await call(`/api/session/${id}/interrupt`, { method: "POST" });
      if (!r.ok) throw httpError(502, `opencode could not stop it (${errText(r)}).`);
    },
    async replyPermission(p, answer) {
      const r = await call(`/api/session/${p.sessionID}/permission/${p.id}/reply`, { method: "POST", body: { decision: answer } });
      if (!r.ok) throw httpError(502, `opencode did not take the answer (${errText(r)}).`);
    },
    async replyQuestion(q, answers) {
      const answer = {};
      q.questions.forEach((qq, i) => {
        const picked = (answers[i] || []).map((label) => {
          const o = qq.options.find((x) => x.label === label);
          return o ? String(o.value) : label;
        });
        answer[qq.key] = qq.multiple ? picked : picked[0];
      });
      const r = await call(`/api/session/${q.sessionID}/form/${q.id}/reply`, { method: "POST", body: { answer } });
      if (!r.ok) throw httpError(502, `opencode did not take the answer (${errText(r)}).`);
    },
    async rejectQuestion(q) {
      const r = await call(`/api/session/${q.sessionID}/form/${q.id}`, { method: "DELETE" });
      if (!r.ok) throw httpError(502, `opencode could not dismiss it (${errText(r)}).`);
    },
    eventsRequest() {
      return { url: base + "/api/event", headers: auth };
    },
    onEvent(ev) {
      const t = ev.type || "";
      const d = ev.data || {};
      const sid = d.sessionID || (d.form && d.form.sessionID) || (d.info && d.info.metadata && d.info.metadata.sessionID);
      const here = ev.location && ev.location.directory ? inWorkspace(ev.location.directory) : null;
      if (t === "session.created" && (here || inWorkspace(d.location && d.location.directory))) wsSessions.add(sid);
      if (t.startsWith("permission.") || t.startsWith("form.")) {
        if (here !== false) refreshPromptsSoon();
        return true;
      }
      if (t === "command.updated") {
        if (here !== false) this.loadCommands().catch(() => {});
        return false;
      }
      if (!sid || !wsSessions.has(sid)) return false;
      if (t === "session.created" || /^session\.(updated|title\.updated|renamed)$/.test(t)) {
        if (d.title) upsertSession(sid, { title: d.title });
      } else if (t === "session.deleted") {
        sessions.delete(sid);
        wsSessions.delete(sid);
      } else if (t === "session.execution.started") setBusy(sid);
      else if (t.startsWith("session.execution.")) {
        const outcome = t.slice("session.execution.".length);
        const msg = d.error ? d.error.message || d.error.name || String(d.error) : null;
        setIdle(sid, outcome === "succeeded" ? null : outcome === "interrupted" ? "Stopped." : `Failed${msg ? ": " + String(msg).slice(0, 300) : "."}`);
      } else if (t === "session.text.delta") appendText(sid, `${d.assistantMessageID}:${d.ordinal}`, d.delta);
      else if (t === "session.text.ended") setText(sid, `${d.assistantMessageID}:${d.ordinal}`, d.text);
      else if (t.startsWith("session.reasoning.")) upsertSession(sid, { activity: "Thinking" });
      else if (t === "session.tool.input.started") {
        toolNames.set(d.id, d.name);
        if (toolNames.size > 500) toolNames.delete(toolNames.keys().next().value);
        upsertSession(sid, { activity: d.name });
      } else if (t === "session.tool.called") upsertSession(sid, { activity: toolLine(toolNames.get(d.id) || d.name || "tool", d.input) });
      else if (t === "session.inbox.enqueued" && d.item && d.item.type === "user") {
        const text = d.item.payload && d.item.payload.text;
        linkFrom(sid, () => folderForPrompt(text) || (/^\/\S/.test(text || "") ? folderForArgs(String(text).replace(/^\/\S+\s*/, "")) : null), null);
      } else return false;
      return true;
    },
    // The TUI on a session. 2.x clients share the background service, so no URL is needed.
    terminalArgs(id) {
      return id ? ["--session", id] : [];
    },
    attachCommand(id) {
      const dir = /\s/.test(opt.workspace) ? `"${opt.workspace}"` : opt.workspace;
      return `opencode${id ? " --session " + id : ""} ${dir}`;
    },
  };
}

// ------------------------------------------------------------------ opencode 1.x adapter

function makeV1(url) {
  const base = url.replace(/\/+$/, "");
  const call = (p, o = {}) => {
    const u = new URL(base + p);
    u.searchParams.set("directory", opt.workspace);
    for (const [k, v] of Object.entries(o.query || {})) u.searchParams.set(k, v);
    return httpJson(u.toString(), o);
  };
  const msgRole = new Map(); // messageID -> role

  const normPermission = (p) => ({
    id: p.id,
    sessionID: p.sessionID,
    permission: p.permission || p.type,
    patterns: p.patterns || (p.pattern ? [].concat(p.pattern) : []),
    always: p.always || [],
    title: (p.metadata && (p.metadata.command || p.metadata.filepath || p.metadata.filePath)) || p.title || null,
  });
  const normQuestion = (q) => ({
    id: q.id,
    sessionID: q.sessionID,
    questions: (q.questions || []).map((x, i) => ({
      key: String(i),
      header: x.header || "",
      question: x.question || "",
      options: (x.options || []).map((o) => ({ label: o.label, value: o.label, description: o.description || "" })),
      multiple: !!x.multiple,
      custom: x.custom !== false,
    })),
  });

  return {
    kind: "v1",
    url: base,
    async info() {
      try {
        const r = await httpJson(base + "/global/health", { timeout: 2500 });
        return r.ok && r.data && r.data.healthy ? { version: r.data.version || null } : null;
      } catch {
        return null;
      }
    },
    async loadCommands() {
      const r = await call("/command");
      if (r.ok && Array.isArray(r.data)) oc.commands = new Set(r.data.map((c) => c.name));
    },
    async loadSessions() {
      const r = await call("/session");
      if (!r.ok || !Array.isArray(r.data)) return null;
      for (const s of r.data) upsertSession(s.id, { title: s.title, updated: s.time && s.time.updated });
      const st = await call("/session/status");
      const map = st.ok && st.data && typeof st.data === "object" ? st.data : {};
      for (const s of r.data) upsertSession(s.id, { status: map[s.id] ? map[s.id].type : "idle" });
      return r.data.map((s) => s.id);
    },
    async sessionExists(id) {
      return (await call(`/session/${id}`)).ok;
    },
    async loadPrompts() {
      const [p, q] = await Promise.all([call("/permission"), call("/question")]);
      if (p.ok && Array.isArray(p.data)) {
        permissions.clear();
        for (const x of p.data) permissions.set(x.id, normPermission(x));
      }
      if (q.ok && Array.isArray(q.data)) {
        questions.clear();
        for (const x of q.data) questions.set(x.id, normQuestion(x));
      }
    },
    async lastText(id) {
      if (!id) return;
      const r = await call(`/session/${id}/message`, { query: { limit: "8" } });
      if (!r.ok || !Array.isArray(r.data)) return;
      for (let i = r.data.length - 1; i >= 0; i--) {
        const m = r.data[i];
        if (!m.info || m.info.role !== "assistant") continue;
        const text = (m.parts || []).filter((p) => p.type === "text" && !p.synthetic).map((p) => p.text).join("\n").trim();
        if (text) {
          upsertSession(id, { text, textAt: (m.info.time && (m.info.time.completed || m.info.time.created)) || null });
          return;
        }
      }
    },
    async createSession(title) {
      const r = await call("/session", { method: "POST", body: { title } });
      if (!r.ok || !r.data || !r.data.id) throw httpError(502, `opencode could not create a session (${errText(r)}).`);
      return { id: r.data.id, title: r.data.title || title };
    },
    // The 1.x command endpoint answers only when the agent finishes, so the caller does not wait for it.
    async runCommand(id, name, args) {
      const r = await call(`/session/${id}/command`, { method: "POST", body: { command: name, arguments: args }, timeout: 0 });
      return r.ok ? null : errText(r);
    },
    async prompt(id, text) {
      const r = await call(`/session/${id}/prompt_async`, { method: "POST", body: { parts: [{ type: "text", text }] } });
      if (!r.ok) throw httpError(502, `opencode did not take the reply (${errText(r)}).`);
    },
    async abort(id) {
      const r = await call(`/session/${id}/abort`, { method: "POST" });
      if (!r.ok) throw httpError(502, `opencode could not stop it (${errText(r)}).`);
    },
    async replyPermission(p, answer) {
      let r = await call(`/session/${p.sessionID}/permissions/${p.id}`, { method: "POST", body: { response: answer } });
      if (r.status === 404) r = await call(`/permission/${p.id}/reply`, { method: "POST", body: { reply: answer } });
      if (!r.ok) throw httpError(502, `opencode did not take the answer (${errText(r)}).`);
    },
    async replyQuestion(q, answers) {
      const r = await call(`/question/${q.id}/reply`, { method: "POST", body: { answers } });
      if (!r.ok) throw httpError(502, `opencode did not take the answer (${errText(r)}).`);
    },
    async rejectQuestion(q) {
      const r = await call(`/question/${q.id}/reject`, { method: "POST" });
      if (!r.ok) throw httpError(502, `opencode could not dismiss it (${errText(r)}).`);
    },
    eventsRequest() {
      const u = new URL(base + "/event");
      u.searchParams.set("directory", opt.workspace);
      return { url: u.toString(), headers: {} };
    },
    onEvent(ev) {
      const p = ev.properties || {};
      const sid = p.sessionID || (p.info && p.info.sessionID) || (p.part && p.part.sessionID);
      switch (ev.type) {
        case "session.created":
        case "session.updated":
          if (p.info) upsertSession(p.info.id, { title: p.info.title, updated: p.info.time && p.info.time.updated });
          break;
        case "session.deleted":
          if (p.info) sessions.delete(p.info.id);
          break;
        case "session.status": {
          const type = (p.status && p.status.type) || "idle";
          if (type === "idle") upsertSession(sid, { status: "idle" });
          else setBusy(sid);
          if (type === "retry") upsertSession(sid, { activity: `Retrying (attempt ${p.status.attempt}): ${p.status.message || ""}` });
          break;
        }
        case "session.idle":
          setIdle(sid);
          break;
        case "session.error": {
          const e = p.error || {};
          const msg = (e.data && (e.data.message || e.data.providerID)) || e.name || "Unknown error";
          if (sid) upsertSession(sid, e.name === "MessageAbortedError" ? { activity: null, error: "Stopped." } : { error: String(msg).slice(0, 500) });
          break;
        }
        case "message.updated":
          if (p.info) {
            msgRole.set(p.info.id, p.info.role);
            if (msgRole.size > 2000) msgRole.delete(msgRole.keys().next().value);
          }
          break;
        case "message.part.updated": {
          const part = p.part || {};
          if (part.type === "tool") upsertSession(sid, { activity: toolLine(part.tool, part.state && part.state.input, part.state && part.state.title) });
          else if (part.type === "text" && msgRole.get(part.messageID) === "assistant" && !part.synthetic) setText(sid, part.id, part.text);
          else if (part.type === "reasoning") upsertSession(sid, { activity: "Thinking" });
          break;
        }
        case "message.part.delta":
          if (p.field !== "text" || msgRole.get(p.messageID) !== "assistant") return false;
          appendText(sid, p.partID, p.delta);
          break;
        case "permission.asked":
        case "permission.updated": // older 1.x
          if (p.id) permissions.set(p.id, normPermission(p));
          break;
        case "permission.replied":
          permissions.delete(p.requestID || p.permissionID || p.id);
          break;
        case "question.asked":
          if (p.id) questions.set(p.id, normQuestion(p));
          break;
        case "question.replied":
        case "question.rejected":
          questions.delete(p.requestID || p.id);
          break;
        case "command.executed":
          upsertSession(sid, { command: `/${p.name}${p.arguments ? " " + p.arguments : ""}` });
          linkFrom(sid, () => folderForArgs(p.arguments), `/${p.name} ${p.arguments || ""}`.trim());
          break;
        case "server.instance.disposed":
        case "global.disposed":
          setTimeout(() => loadState().then(broadcastLive, () => {}), 500);
          break;
        default:
          return false;
      }
      return true;
    },
    terminalArgs(id) {
      return ["attach", base, ...(id ? ["--session", id] : [])];
    },
    attachCommand(id) {
      const dir = /\s/.test(opt.workspace) ? `"${opt.workspace}"` : opt.workspace;
      return `opencode attach ${base}${id ? " --session " + id : ""} --dir ${dir}`;
    },
  };
}

// ------------------------------------------------------------------ finding opencode

// 2.x: the background service. `opencode service start` starts it if needed and prints its URL.
async function v2Password() {
  if (process.env.OPENCODE_SERVER_PASSWORD) return process.env.OPENCODE_SERVER_PASSWORD;
  const files = [];
  const paths = await ocCli(["debug", "paths"]);
  const cfg = (paths.out.match(/^config\s+(.+)$/m) || [])[1];
  if (cfg) files.push(path.join(cfg.trim(), "service.json"));
  files.push(path.join(os.homedir(), ".config", "opencode", "service.json"));
  if (process.env.XDG_CONFIG_HOME) files.push(path.join(process.env.XDG_CONFIG_HOME, "opencode", "service.json"));
  for (const f of files) {
    try {
      const pw = JSON.parse(fs.readFileSync(f, "utf8")).password;
      if (pw) return pw;
    } catch {}
  }
  return null;
}

async function v2Service(start) {
  const r = await ocCli(["service", start ? "start" : "status"], 60000);
  const url = (r.out.match(/https?:\/\/\S+/) || [])[0];
  return url ? { url: url.replace(/\/+$/, "") } : { error: (r.err || r.out || "no output").split(/\r?\n/).slice(-2).join(" ") };
}

// Picks the adapter: an explicit --opencode URL is probed; otherwise the installed CLI decides.
async function pickAdapter() {
  if (opt.opencode) {
    const probe = await httpJson(opt.opencode + "/api/info", { timeout: 2500 }).catch(() => null);
    const isV2 = probe && (probe.ok || probe.status === 401) && /json/.test(probe.type);
    return isV2 ? makeV2(opt.opencode, await v2Password()) : makeV1(opt.opencode);
  }
  const ver = await ocCli(["--version"], 15000);
  const m = /(\d+)\.(\d+)\.(\d+)/.exec(ver.out);
  if (!m) {
    oc.error = `Could not run "${opt.opencodeCmd} --version" (${ver.err || "no output"}). Is opencode on PATH?`;
    return makeV1(V1_DEFAULT_URL);
  }
  if (+m[1] >= 2) {
    const s = await v2Service(opt.startOpencode);
    if (s.error) {
      oc.error = `opencode ${m[0]}: ${opt.startOpencode ? "could not start" : "no"} background service (${s.error}). Start it with: opencode service start`;
      return null;
    }
    return makeV2(s.url, await v2Password());
  }
  return makeV1(V1_DEFAULT_URL);
}

// 1.x only: start `opencode serve` when nothing answers on the URL.
function startV1Serve(url) {
  const u = new URL(url);
  if (!/^(127\.0\.0\.1|localhost|\[::1\])$/.test(u.hostname)) {
    oc.error = `No opencode server at ${url}, and it is not local, so it was not started.`;
    return;
  }
  const port = u.port || "4096";
  const logFile = path.join(stateDir, "opencode.log");
  const out = fs.openSync(logFile, "a");
  log(`Starting: ${opt.opencodeCmd} serve --port ${port} (log: ${logFile})`);
  const serveArgs = ["serve", "--port", port, "--hostname", "127.0.0.1"];
  const spawnOpts = { cwd: opt.workspace, stdio: ["ignore", out, out], windowsHide: true };
  // On Windows opencode is usually a .cmd shim, which needs a shell. The arguments are fixed, so one string is safe.
  const child = isWin ? spawn(`"${opt.opencodeCmd}" ${serveArgs.join(" ")}`, { ...spawnOpts, shell: true }) : spawn(opt.opencodeCmd, serveArgs, spawnOpts);
  child.on("error", (e) => {
    oc.error = `Could not start opencode (${e.message}). Start it yourself: opencode serve --port ${port}`;
    log(oc.error);
  });
  child.on("exit", (code) => {
    if (oc.started) log(`opencode serve exited (${code}). See ${logFile}`);
    oc.started = false;
  });
  oc.started = true;
  const stop = () => {
    try {
      if (isWin) spawnSync("taskkill", ["/pid", String(child.pid), "/T", "/F"], { windowsHide: true });
      else child.kill();
    } catch {}
  };
  process.on("exit", stop);
}

async function connectOpencode() {
  if (!oc.api) {
    oc.api = await pickAdapter();
    if (!oc.api) {
      oc.connected = false;
      broadcastLive();
      setTimeout(connectOpencode, 10000);
      return;
    }
    oc.kind = oc.api.kind;
    oc.url = oc.api.url;
  }
  let info = await oc.api.info().catch(() => null);
  if (!info && oc.kind === "v1" && opt.startOpencode && !oc.started && !opt.opencode) {
    startV1Serve(oc.url);
    for (let i = 0; i < 40 && !info; i++) {
      await sleep(750);
      info = await oc.api.info().catch(() => null);
    }
  }
  if (!info) {
    oc.connected = false;
    if (!oc.error || /Lost opencode/.test(oc.error)) {
      oc.error = oc.kind === "v2"
        ? `opencode's background service at ${oc.url} did not answer${oc.api && !oc.api.hasPassword ? " (no password found in service.json)" : ""}. Try: opencode service restart`
        : `opencode is not running at ${oc.url}. Start it with: opencode serve --port ${new URL(oc.url).port || 4096}`;
    }
    broadcastLive();
    // 2.x: the service may have moved or restarted with a new password; look it up again.
    if (oc.kind === "v2" && !opt.opencode) oc.api = null;
    setTimeout(connectOpencode, 5000);
    return;
  }
  oc.version = info.version;
  oc.error = null;
  try {
    await loadState();
  } catch (e) {
    log("opencode: could not load sessions:", e.message);
  }
  followEvents();
}

async function loadState() {
  await oc.api.loadCommands().catch(() => {});
  const ids = await oc.api.loadSessions();
  // Drop links to sessions that no longer exist.
  if (ids) {
    const have = new Set(ids);
    let changed = false;
    for (const [f, e] of Object.entries(links)) {
      const keep = [];
      for (const s of e.sessions) if (have.has(s.id) || (await oc.api.sessionExists(s.id))) keep.push(s);
      if (keep.length !== e.sessions.length) {
        changed = true;
        if (keep.length) e.sessions = keep;
        else delete links[f];
      }
    }
    if (changed) saveLinks();
  }
  await oc.api.loadPrompts();
  await Promise.all(Object.keys(links).map((f) => oc.api.lastText(currentSession(f))));
}

let eventsCtrl = null;
async function followEvents() {
  if (eventsCtrl) eventsCtrl.abort();
  eventsCtrl = new AbortController();
  try {
    const req = oc.api.eventsRequest();
    const r = await fetch(req.url, { signal: eventsCtrl.signal, headers: { accept: "text/event-stream", ...req.headers } });
    if (!r.ok || !r.body) throw new Error(`event stream: HTTP ${r.status}`);
    oc.connected = true;
    log(`opencode ${oc.version || ""} connected at ${oc.url} (${oc.kind === "v2" ? "2.x API" : "1.x API"})`);
    broadcastLive();
    const reader = r.body.getReader();
    const dec = new TextDecoder();
    let buf = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.search(/\r?\n\r?\n/)) >= 0) {
        const chunk = buf.slice(0, i);
        buf = buf.slice(i).replace(/^\r?\n\r?\n/, "");
        const data = chunk
          .split(/\r?\n/)
          .filter((l) => l.startsWith("data:"))
          .map((l) => l.slice(5).trimStart())
          .join("\n");
        if (!data) continue;
        try {
          if (oc.api.onEvent(JSON.parse(data))) broadcastLive();
        } catch (e) {
          log("bad event:", e.message);
        }
      }
    }
    throw new Error("event stream closed");
  } catch (e) {
    if (e.name === "AbortError") return;
    oc.connected = false;
    oc.error = `Lost opencode at ${oc.url} (${e.message}). Reconnecting.`;
    log(oc.error);
    broadcastLive();
    setTimeout(connectOpencode, 3000);
  }
}

// ------------------------------------------------------------------ actions

function parseCommand(text) {
  const m = /^\/([a-z0-9][a-z0-9-]*)(?:\s+([\s\S]*))?$/i.exec(String(text || "").trim());
  if (!m) return null;
  return { name: m[1].toLowerCase(), args: (m[2] || "").trim() };
}

function findItem(folder) {
  return model && (model.items || []).find((i) => i.folder === folder);
}

function labelFor(item) {
  return item.id ? String(item.id) : item.folder;
}

function needOpencode() {
  if (!oc.connected || !oc.api) throw httpError(503, oc.error || "opencode is not connected.");
}

// fresh: always use a new session (autopilot runs every step in one). fromAuto: autopilot is the caller.
async function runCommand({ folder, command }, { fresh = false, fromAuto = false } = {}) {
  needOpencode();
  const item = findItem(folder);
  if (!item) throw httpError(404, `No work item folder "${folder}". Refresh the page.`);
  const cmd = parseCommand(command);
  if (!cmd) throw httpError(400, `Not a command: ${command}`);
  if (oc.commands.size && !oc.commands.has(cmd.name)) throw httpError(400, `opencode has no /${cmd.name} command. Re-run install.ps1, then restart opencode.`);
  if (!fromAuto && autoActive(folder)) throw httpError(409, "Autopilot is running this item. Stop it first.");

  let sid = fresh || FRESH_SESSION.has(cmd.name) ? null : currentSession(folder);
  if (sid) {
    const s = sessions.get(sid);
    if (!s) sid = null; // deleted in opencode
    else if (s.status !== "idle") throw httpError(409, "This item's session is still working. Wait for it, or stop it first.");
  }
  if (!sid) {
    const created = await oc.api.createSession(`${labelFor(item)}: /${cmd.name}${cmd.args ? " " + cmd.args : ""}`);
    sid = created.id;
    upsertSession(sid, { title: created.title });
  }
  const full = `/${cmd.name} ${cmd.args}`.trim();
  linkSession(folder, sid, full);
  upsertSession(sid, { status: "busy", busySince: Date.now(), activity: `Starting /${cmd.name}`, error: null, text: null, command: full });
  broadcastLive();

  oc.api
    .runCommand(sid, cmd.name, cmd.args)
    .then((err) => {
      if (err) {
        upsertSession(sid, { status: "idle", activity: null, error: `/${cmd.name} failed: ${err}` });
        broadcastLive();
        autoOnFail(sid, `/${cmd.name} failed: ${err}`);
      }
    })
    .catch((e) => {
      upsertSession(sid, { error: `/${cmd.name}: ${e.message}` });
      broadcastLive();
      autoOnFail(sid, `/${cmd.name}: ${e.message}`);
    });
  log(`run ${full} (${folder}) in ${sid}`);
  return { session: sid };
}

// /start for a work item that has no .work folder yet (from a shell such as Prioritizer).
// The folder appears once /start creates it; the session is linked to it then.
const starting = new Map(); // id -> { sid, at }, until its folder shows up (or 10 minutes pass)
const START_FORGET_MS = 10 * 60e3;
async function startItem({ id, lane }) {
  needOpencode();
  const wid = String(id || "").trim();
  if (!/^\d{1,10}$/.test(wid)) throw httpError(400, "The work item id must be a number.");
  if (lane !== "feature" && lane !== "bug") throw httpError(400, 'Lane must be "feature" or "bug".');
  if (folderForToken(wid)) throw httpError(409, `Work item ${wid} is already started. Open the dashboard to continue it.`);
  const prev = starting.get(wid);
  if (prev && (sessions.get(prev.sid) || {}).status !== "idle") throw httpError(409, `Work item ${wid} is already starting.`);
  if (oc.commands.size && !oc.commands.has("start")) throw httpError(400, "opencode has no /start command. Re-run install.ps1, then restart opencode.");

  const args = `${wid} ${lane}`;
  const created = await oc.api.createSession(`${wid}: /start ${args}`);
  const sid = created.id;
  starting.set(wid, { sid, at: Date.now() });
  upsertSession(sid, { title: created.title, status: "busy", busySince: Date.now(), activity: "Starting /start", error: null, text: null, command: `/start ${args}` });
  linkFrom(sid, () => folderForToken(wid), `/start ${args}`);
  broadcastLive();
  oc.api
    .runCommand(sid, "start", args)
    .then((err) => {
      if (err) {
        upsertSession(sid, { status: "idle", activity: null, error: `/start failed: ${err}` });
        broadcastLive();
      }
      scheduleRefresh(0);
    })
    .catch((e) => {
      upsertSession(sid, { error: `/start: ${e.message}` });
      broadcastLive();
    });
  log(`run /start ${args} in ${sid} (from the shell)`);
  return { session: sid };
}

// What a shell needs to badge its tasks: one row per numbered work item, plus /start in progress.
function shellData() {
  const items = [];
  for (const it of (model && model.items) || []) {
    if (it.kind !== "item" || !it.id) continue;
    const sid = currentSession(it.folder);
    const s = sid ? sessions.get(sid) : null;
    items.push({
      id: String(it.id),
      title: it.title,
      lane: it.lane,
      stage: it.stage,
      bucket: it.bucket,
      next: it.next ? { command: it.next.command || null, action: it.next.action || null, needsYou: !!it.next.needsYou } : null,
      tasks: it.tasks ? { done: it.tasks.done || 0, total: it.tasks.total || 0 } : null,
      paused: !!it.paused,
      blocked: !!it.blocked,
      agent: s ? s.status : null,
      waiting: !!s && ([...permissions.values()].some((p) => p.sessionID === sid) || [...questions.values()].some((q) => q.sessionID === sid)),
    });
  }
  // Started from the shell, folder not there yet: /start is running, waiting on the engineer (it asks
  // when it cannot fetch the item), or done and the next refresh will pick the folder up.
  const pending = [];
  for (const [wid, st] of starting) {
    const s = sessions.get(st.sid);
    if (folderForToken(wid) || !s || Date.now() - st.at > START_FORGET_MS) {
      starting.delete(wid);
      continue;
    }
    const waiting = [...permissions.values()].some((p) => p.sessionID === st.sid) || [...questions.values()].some((q) => q.sessionID === st.sid);
    pending.push({ id: wid, agent: s.status, waiting, error: s.error || null });
  }
  return {
    app: APP,
    version: runningVersion,
    workspace: path.basename(opt.workspace),
    opencode: { connected: oc.connected, error: oc.error },
    error: modelError,
    items,
    starting: pending,
  };
}

async function reply({ session, text }) {
  needOpencode();
  if (!sessions.has(session)) throw httpError(404, "Unknown session.");
  const t = String(text || "").trim();
  if (!t) throw httpError(400, "Type a reply first.");
  if (t.startsWith("/")) {
    const folder = folderForSession(session);
    if (folder) return runCommand({ folder, command: t });
  }
  await oc.api.prompt(session, t);
  upsertSession(session, { status: "busy", busySince: Date.now(), activity: "Reading your reply", error: null, text: null });
  autoOnReply(session);
  broadcastLive();
  return { ok: true };
}

async function answerPermission({ id, reply: answer }) {
  needOpencode();
  const p = permissions.get(id);
  if (!p) throw httpError(404, "That prompt was already answered.");
  if (!["once", "always", "reject"].includes(answer)) throw httpError(400, "Bad answer.");
  await oc.api.replyPermission(p, answer);
  permissions.delete(id);
  broadcastLive();
  return { ok: true };
}

async function answerQuestion({ id, answers, reject }) {
  needOpencode();
  const q = questions.get(id);
  if (!q) throw httpError(404, "That question was already answered.");
  if (reject) await oc.api.rejectQuestion(q);
  else {
    if (!Array.isArray(answers)) throw httpError(400, "Bad answer.");
    await oc.api.replyQuestion(q, answers);
  }
  questions.delete(id);
  broadcastLive();
  return { ok: true };
}

async function abort({ session }) {
  needOpencode();
  await oc.api.abort(session);
  return { ok: true };
}

function attachCommand(session) {
  return oc.api ? oc.api.attachCommand(session) : null;
}

// Opens a terminal window with the opencode TUI on a session (Windows and macOS).
function openTerminal({ session }) {
  needOpencode();
  if (session && !/^ses_[A-Za-z0-9]+$/.test(session)) throw httpError(400, "Bad session id.");
  const tui = [opt.opencodeCmd, ...oc.api.terminalArgs(session)].join(" ");
  if (isWin) {
    const ws = opt.workspace.replace(/'/g, "''");
    const inner = tui.replace(/'/g, "''");
    const script = `Start-Process -FilePath powershell.exe -WorkingDirectory '${ws}' -ArgumentList @('-NoExit','-Command','${inner}')`;
    const enc = Buffer.from(script, "utf16le").toString("base64");
    spawn("powershell.exe", ["-NoProfile", "-EncodedCommand", enc], { detached: true, stdio: "ignore", windowsHide: true }).unref();
    return { ok: true };
  }
  if (process.platform === "darwin") {
    const sh = `cd '${opt.workspace.replace(/'/g, "'\\''")}' && ${tui}`;
    const as = `tell application "Terminal" to do script "${sh.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"\ntell application "Terminal" to activate`;
    spawn("osascript", ["-e", as], { detached: true, stdio: "ignore" }).unref();
    return { ok: true };
  }
  throw httpError(501, "Opening a terminal is only supported on Windows and macOS. Copy the command instead.");
}

// ------------------------------------------------------------------ autopilot
//
// Runs the build half of the pipeline for one work item without you switching sessions:
//   (/approve <id> plan|bug) -> /tasks -> /do-task <id> <n> for each open task -> /review <id> auto -> /pr
// Every step runs in a new session, and the next step comes from the same Get-NextStep rules
// as the page, read fresh from disk after each step. It never pushes.
//
// It stops and waits for you when:
//   - the next step needs you (a draft to approve, a blocked task, review findings it cannot turn into tasks)
//   - a step ends without moving the item forward (for example the agent asked you something in its reply)
//   - a step fails or you press Stop on the agent
//   - the review still is not READY after MAX_FIX_ROUNDS rounds of fix tasks
// Permission prompts and agent questions do not stop it: the step waits for your answer on the page.
// Replying to the agent in a waiting step's session resumes it.

const autoFile = path.join(stateDir, "autopilot.json");
const AUTO_STEPS = new Set(["approve", "tasks", "do-task", "review", "pr"]);
const MAX_FIX_ROUNDS = 2;

// { "<folder>": { status, message, command, lastCommand, session, inFlight, sawBusy,
//                 approveFirst, fixRounds, started, updated, log: [{ at, text }] } }
// status: "running" | "waiting" (needs you) | "done" | "stopped"
let autopilot = {};
try {
  autopilot = JSON.parse(fs.readFileSync(autoFile, "utf8")) || {};
} catch {
  autopilot = {};
}
for (const a of Object.values(autopilot)) {
  if (a.status === "running") {
    a.status = "waiting";
    a.inFlight = false;
    a.message = "The dashboard restarted. Click Resume to carry on.";
  }
}
try {
  if (Object.keys(autopilot).length) saveAuto();
} catch {}

function saveAuto() {
  const tmp = autoFile + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(autopilot, null, 2));
  fs.renameSync(tmp, autoFile);
}

function autoActive(folder) {
  const a = autopilot[folder];
  return !!a && a.status === "running";
}

function autoLog(folder, text) {
  const a = autopilot[folder];
  if (!a) return;
  a.updated = new Date().toISOString();
  a.log = (a.log || []).concat({ at: a.updated, text }).slice(-30);
  log(`autopilot ${folder}: ${text}`);
}

function autoSet(folder, status, message) {
  const a = autopilot[folder];
  if (!a) return;
  a.status = status;
  a.message = message || null;
  a.inFlight = false;
  autoLog(folder, message || status);
  saveAuto();
  broadcastLive();
}

// Why the item needs you, in one line, from the page's own next step.
function needsYouText(it) {
  const n = it.next || {};
  if (it.blocked) return `Task blocked: ${it.blocked}`;
  if (n.stage === "review") return "The review is not READY and there are no fix tasks to run. Read review.md, add fix tasks or fix it yourself, then click Resume.";
  if (n.action) return `${n.action}${n.command ? ` (${n.command})` : ""}. Then click Resume.`;
  return "The next step needs you. Then click Resume.";
}

const stepping = new Set();
// finished: called because the step autopilot started just ended (not a start or resume).
async function autoStep(folder, finished = false) {
  const a = autopilot[folder];
  if (!a || a.status !== "running" || a.inFlight || stepping.has(folder)) return;
  stepping.add(folder);
  try {
    // Fresh read of .work, not the debounced one: the step that just ended may have written files.
    const r = await runModel();
    if (r.error) return autoSet(folder, "waiting", `Could not read .work: ${r.error}`);
    model = r.data;
    modelError = null;
    linkSessionsFromModel();
    broadcast("model", pageData());

    const it = findItem(folder);
    if (!it || it.kind !== "item") return autoSet(folder, "stopped", "The work item folder is gone.");
    if (it.paused) return autoSet(folder, "waiting", `The item is paused. Run /resume ${it.id}, then click Resume.`);

    // How did the last step end?
    const last = a.session ? sessions.get(a.session) : null;
    if (finished && last && last.error) return autoSet(folder, "waiting", `${a.command} stopped: ${last.error}`);
    // A review that turned Blockers into fix tasks starts a fix round.
    if (finished && a.command && /^\/review\b.*\sauto$/.test(a.command) && it.gates.review && it.gates.review !== "READY") a.fixRounds = (a.fixRounds || 0) + 1;

    const n = it.next || {};
    if (n.stage === "ship") return autoSet(folder, "done", "PR text is ready in pr.md. Push the branches and open the PRs.");

    let cmd = n.command;
    const approving = cmd && /^\/approve\b/.test(cmd) && (n.stage === "plan" || n.stage === "bug");
    if (approving && a.approveFirst) cmd = `/approve ${it.id} ${n.stage}`;
    else if (n.needsYou || !cmd) return autoSet(folder, "waiting", needsYouText(it));

    const parsed = parseCommand(cmd);
    if (!parsed || !AUTO_STEPS.has(parsed.name)) return autoSet(folder, "waiting", `Next is ${cmd}, which autopilot does not run. Run it yourself, then click Resume.`);

    // The same step again means the last run did not move the item forward.
    if (cmd === a.lastCommand) {
      const said = finished && last && last.text ? ` The agent said: "${String(last.text).trim().split(/\r?\n/).slice(-1)[0].slice(0, 200)}"` : "";
      return autoSet(folder, "waiting", `${cmd} ended without finishing. Reply to the agent, or fix it yourself, then click Resume.${said}`);
    }

    let full = cmd;
    if (parsed.name === "review") {
      if ((a.fixRounds || 0) >= MAX_FIX_ROUNDS) autoLog(folder, `${MAX_FIX_ROUNDS} fix rounds done. This review will ask you which findings to fix.`);
      else full = `${cmd} auto`;
    }

    a.lastCommand = cmd;
    a.command = full;
    a.inFlight = true;
    a.sawBusy = false;
    if (approving) a.approveFirst = false;
    const run = await runCommand({ folder, command: full }, { fresh: true, fromAuto: true });
    a.session = run.session;
    autoLog(folder, `Running ${full}`);
    saveAuto();
    broadcastLive();
  } catch (e) {
    autoSet(folder, "waiting", `Could not start the next step: ${e.message}`);
  } finally {
    stepping.delete(folder);
  }
}

function autoForSession(sid) {
  for (const [folder, a] of Object.entries(autopilot)) if (a.session === sid) return [folder, a];
  return [null, null];
}

function autoOnBusy(sid) {
  const [, a] = autoForSession(sid);
  if (a && a.inFlight) a.sawBusy = true;
}

function autoOnIdle(sid) {
  const [folder, a] = autoForSession(sid);
  if (!a || a.status !== "running" || !a.inFlight || !a.sawBusy) return;
  a.inFlight = false;
  saveAuto();
  // Give the agent's last file writes and the error event (opencode 1.x) a moment to land.
  setTimeout(() => autoStep(folder, true), 1500);
}

function autoOnFail(sid, msg) {
  const [folder, a] = autoForSession(sid);
  if (a && a.status === "running") autoSet(folder, "waiting", msg);
}

// You answered the agent in the step it stopped on: pick up again when that turn ends.
function autoOnReply(sid) {
  const [folder, a] = autoForSession(sid);
  if (!a || a.status !== "waiting") return;
  a.status = "running";
  a.message = null;
  a.inFlight = true;
  a.sawBusy = false;
  autoLog(folder, "Resumed by your reply");
  saveAuto();
}

async function autopilotAction({ folder, action }) {
  const it = findItem(folder);
  if (!it || it.kind !== "item") throw httpError(404, `No work item folder "${folder}". Refresh the page.`);
  const a = autopilot[folder];

  if (action === "stop") {
    if (!a) return { ok: true };
    autoSet(folder, "stopped", a.inFlight ? `Stopped. ${a.command} finishes on its own; nothing runs after it.` : "Stopped.");
    return { ok: true };
  }
  if (action === "dismiss") {
    delete autopilot[folder];
    saveAuto();
    broadcastLive();
    return { ok: true };
  }
  if (!["start", "approve-start", "resume"].includes(action)) throw httpError(400, "Bad action.");

  needOpencode();
  if (a && a.status === "running") throw httpError(409, "Autopilot is already running this item.");
  if (it.paused) throw httpError(409, `The item is paused. Run /resume ${it.id} first.`);
  const s = sessions.get(currentSession(folder));
  if (s && s.status !== "idle") throw httpError(409, "This item's agent is still working. Wait for it, or stop it first.");

  const gate = it.lane === "bug" ? it.gates.bug : it.gates.plan;
  const n = it.next || {};
  const canApprove = n.command && /^\/approve\b/.test(n.command) && (n.stage === "plan" || n.stage === "bug");
  if (action === "approve-start" && !canApprove) throw httpError(409, "There is no plan or bug analysis waiting for approval.");
  const pendingApprove = action === "resume" && a && a.approveFirst && canApprove;
  if (action !== "approve-start" && !pendingApprove && gate !== "APPROVED") {
    throw httpError(409, `Autopilot starts after ${it.lane === "bug" ? "bug.md" : "plan.md"} is approved.`);
  }

  if (action === "resume" && a) {
    a.status = "running";
    a.message = null;
    a.lastCommand = null; // you fixed something: allow the same step once more
    a.inFlight = false;
    autoLog(folder, "Resumed");
  } else {
    autopilot[folder] = { status: "running", message: null, command: null, lastCommand: null, session: null, inFlight: false, sawBusy: false, approveFirst: action === "approve-start", fixRounds: 0, started: new Date().toISOString(), log: [] };
    autoLog(folder, action === "approve-start" ? "Started: approve, then build" : "Started");
  }
  saveAuto();
  broadcastLive();
  await autoStep(folder);
  const now = autopilot[folder];
  if (now && now.status === "waiting") throw httpError(409, now.message);
  return { ok: true };
}

function autoData() {
  const out = {};
  for (const [folder, a] of Object.entries(autopilot)) {
    out[folder] = { status: a.status, message: a.message, command: a.command, session: a.session, fixRounds: a.fixRounds || 0, maxFixRounds: MAX_FIX_ROUNDS, started: a.started, updated: a.updated, log: (a.log || []).slice(-8) };
  }
  return out;
}

// ------------------------------------------------------------------ updates (update.ps1 in the repo this was installed from)
//
// The page shows "Update available" from update.ps1 -Check -Json, run at start and every few hours.
// Update runs update.ps1 -Component <dashboard|all> -Yes, the same as from a terminal. Then the server
// exits with RESTART_CODE and Start-LiveDashboard.ps1 starts it again on the new code. The page reloads
// by itself when the server comes back.

const RESTART_CODE = 75;
const supervised = process.env.ENG_DASHBOARD_SUPERVISED === "1";
const versionFile = path.join(HERE, "VERSION");
const readVersion = () => {
  try {
    return fs.readFileSync(versionFile, "utf8").trim() || null;
  } catch {
    return null;
  }
};
const runningVersion = readVersion();
const engHome = path.resolve(HERE, "..", ".."); // <Target>/eng-agents
const installTarget = path.dirname(engHome);
function installSource() {
  try {
    const m = JSON.parse(fs.readFileSync(path.join(engHome, "manifest.json"), "utf8").replace(/^\uFEFF/, ""));
    return m && m.source ? m.source : null;
  } catch {
    return null;
  }
}
const UPDATE_EVERY_MS = 6 * 3600e3;
const updates = { checking: false, checkedAt: null, error: null, status: null, updating: null, lastRun: null };

function updateScript() {
  const src = installSource();
  if (!src) return { error: "The install has no source repo recorded. Run install.ps1 from your eng-agents clone once." };
  const file = path.join(src, "update.ps1");
  if (!fs.existsSync(file)) return { error: `update.ps1 not found in ${src}. Pull the repo (git pull) and run install.ps1 once.` };
  return { file };
}

function runUpdateScript(extra, timeout) {
  return new Promise((resolve) => {
    const u = updateScript();
    if (u.error) return resolve({ ok: false, out: u.error });
    const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", u.file, "-Target", installTarget, ...extra];
    const p = spawn(psExe, args, { cwd: path.dirname(u.file), windowsHide: true, env: { ...process.env, NO_COLOR: "1", GIT_TERMINAL_PROMPT: "0" } });
    let out = "";
    const t = setTimeout(() => {
      out += "\n(timed out)";
      try { p.kill(); } catch {}
    }, timeout);
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (out += d));
    p.on("error", (e) => {
      clearTimeout(t);
      resolve({ ok: false, out: e.message });
    });
    p.on("close", (code) => {
      clearTimeout(t);
      resolve({ ok: code === 0, out: out.replace(/\x1b\[[0-9;]*m/g, "").trim() });
    });
  });
}

async function checkUpdates() {
  if (updates.checking || updates.updating) return;
  updates.checking = true;
  broadcastLive();
  try {
    const r = await runUpdateScript(["-Check", "-Json"], 90000);
    updates.checkedAt = new Date().toISOString();
    if (!r.ok) {
      updates.error = r.out.split(/\r?\n/).slice(-2).join(" ") || "update.ps1 failed";
      return;
    }
    try {
      updates.status = JSON.parse(r.out.slice(r.out.indexOf("{")));
      updates.error = null;
      const s = updates.status;
      const avail = ["dashboard", "core"].filter((c) => s.components && s.components[c] && s.components[c].update);
      if (avail.length) log(`Update available: ${avail.map((c) => `${c} ${s.components[c].available}`).join(", ")}`);
    } catch (e) {
      updates.error = "Could not read update.ps1 output: " + e.message;
    }
  } finally {
    updates.checking = false;
    broadcastLive();
  }
}

// Why updating now would get in the way, or null.
function updateBlocker() {
  if (Object.keys(autopilot).some(autoActive)) return "Autopilot is running";
  if ([...sessions.values()].some((s) => s.status && s.status !== "idle")) return "An agent is working";
  return null;
}

function restartSoon() {
  log("Restarting the dashboard on the updated code.");
  broadcast("restart", {});
  setTimeout(() => process.exit(RESTART_CODE), 400);
}

async function runUpdate({ component }) {
  if (component !== "dashboard" && component !== "all") throw httpError(400, "component must be dashboard or all.");
  if (updates.updating) throw httpError(409, "An update is already running.");
  const busy = updateBlocker();
  if (busy) throw httpError(409, `${busy}. Update when it is done.`);
  updates.updating = component;
  broadcastLive();
  let r;
  try {
    log(`Updating ${component === "all" ? "eng-agents" : "the dashboard"} (update.ps1)`);
    r = await runUpdateScript(["-Component", component, "-Yes"], 300000);
  } finally {
    updates.updating = null;
  }
  updates.lastRun = { component, ok: r.ok, output: r.out.split(/\r?\n/).slice(-40).join("\n"), at: new Date().toISOString() };
  log(r.ok ? "Update finished." : "Update failed:\n" + updates.lastRun.output);
  if (!r.ok) {
    broadcastLive();
    throw httpError(500, "The update failed. See the Updates panel for the output.");
  }
  updates.status = null;
  if (supervised) {
    restartSoon();
    return { ok: true, restarting: true };
  }
  checkUpdates();
  const tail = component === "all" ? " Restart opencode to load new agents and commands." : "";
  return { ok: true, restarting: false, message: `Updated. Stop the dashboard and start it again to use it.${tail}` };
}

async function restartAction() {
  if (!supervised) throw httpError(400, "This dashboard was not started with Start-LiveDashboard.ps1. Stop it and start it again.");
  const busy = updateBlocker();
  if (busy) throw httpError(409, `${busy}. Restart when it is done.`);
  restartSoon();
  return { ok: true };
}

function updateData() {
  const src = installSource();
  const ps = /pwsh/i.test(path.basename(psExe)) ? "pwsh" : "powershell";
  return {
    running: runningVersion,
    installed: readVersion(),
    supervised,
    checking: updates.checking,
    checkedAt: updates.checkedAt,
    error: updates.error,
    status: updates.status,
    updating: updates.updating,
    lastRun: updates.lastRun,
    busyReason: updateBlocker(),
    shell: src ? `${ps} -NoProfile -ExecutionPolicy Bypass -File "${path.join(src, "update.ps1")}"` : null,
  };
}

// ------------------------------------------------------------------ page data and SSE

function liveData() {
  const items = {};
  for (const [folder, e] of Object.entries(links)) {
    items[folder] = { current: currentSession(folder), sessions: e.sessions.map((s) => ({ ...s, title: (sessions.get(s.id) || {}).title || null })) };
  }
  const tracked = {};
  for (const [id, s] of sessions) {
    const f = folderForSession(id);
    const relevant = f || s.status !== "idle" || [...permissions.values()].some((p) => p.sessionID === id) || [...questions.values()].some((q) => q.sessionID === id);
    if (relevant) tracked[id] = { ...s, folder: f, attach: attachCommand(id) };
  }
  return {
    opencode: { url: oc.url, kind: oc.kind, connected: oc.connected, version: oc.version, error: oc.error, started: oc.started, attach: attachCommand(null) },
    items,
    sessions: tracked,
    permissions: [...permissions.values()].map((p) => ({ ...p, folder: folderForSession(p.sessionID) })),
    questions: [...questions.values()].map((q) => ({ id: q.id, sessionID: q.sessionID, questions: q.questions, folder: folderForSession(q.sessionID) })),
    autopilot: autoData(),
    updates: updateData(),
    canOpenTerminal: isWin || process.platform === "darwin",
  };
}

function pageData() {
  const base = model || { items: [], repos: [], activity: [], workspace: opt.workspace, generatedMs: Date.now(), generated: new Date().toISOString() };
  return { ...base, liveMode: { token, error: modelError, live: liveData(), embedOrigins: shellOrigins } };
}

const clients = new Set();
function broadcast(type, data) {
  const msg = `event: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) res.write(msg);
}

let liveTimer = null;
function broadcastLive() {
  if (liveTimer) return;
  liveTimer = setTimeout(() => {
    liveTimer = null;
    broadcast("live", liveData());
  }, 200);
}

// ------------------------------------------------------------------ HTTP server

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

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

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

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
