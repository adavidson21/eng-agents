#!/usr/bin/env node
// eng-agents live dashboard server.
//
// Serves the dashboard page on 127.0.0.1 and keeps it current:
//   - Watches .work and polls git, rebuilding the data with New-Dashboard.ps1 -AsJson
//     (the same parser and next-step rules as the static /dashboard page).
//   - Connects to an opencode server (`opencode serve`), starting one if none is running,
//     and follows its event stream: session busy/idle, tool activity, agent replies,
//     permission prompts, and questions.
//   - Runs pipeline commands from the page: one opencode session per work item, except
//     /do-task and /check-docs, which get a fresh session as the pipeline requires.
//
// No dependencies beyond Node 18+. Never writes outside .work/_dashboard/. Never calls ADO.
// Usually started by Start-LiveDashboard.ps1. Run with --help for options.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = "eng-agents-dashboard";
const FRESH_SESSION = new Set(["do-task", "check-docs"]); // the pipeline says: run these in a new session
const isWin = process.platform === "win32";

// ------------------------------------------------------------------ options

function parseArgs(argv) {
  const o = {
    workspace: process.cwd(),
    port: 4300,
    opencode: "http://127.0.0.1:4096",
    startOpencode: true,
    opencodeCmd: "opencode",
    ps: null,
    config: null,
    open: true,
    poll: 20,
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
    else if (a === "--poll") o.poll = Math.max(5, +v());
    else if (a === "--help" || a === "-h") {
      console.log(`Usage: node live-server.mjs [options]

  --workspace <dir>      Workspace root (the folder that holds .work). Default: current folder
  --port <n>             Dashboard port. Default: 4300
  --opencode <url>       opencode server. Default: http://127.0.0.1:4096
  --no-start-opencode    Do not start "opencode serve" if none is running
  --opencode-cmd <cmd>   Command that runs opencode. Default: opencode
  --ps <exe>             PowerShell to run New-Dashboard.ps1. Default: pwsh, else powershell
  --config <path>        ADO config.json passed to New-Dashboard.ps1 (for work item links)
  --poll <seconds>       How often to re-read git state. Default: 20
  --no-open              Do not open the browser`);
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
const log = (...a) => console.log(new Date().toLocaleTimeString(), ...a);

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

async function refresh(reason) {
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
      setTimeout(() => refresh("again"), 50);
    }
  }
}

let debounce = null;
function scheduleRefresh(reason, ms = 400) {
  clearTimeout(debounce);
  debounce = setTimeout(() => refresh(reason), ms);
}

function watchWork() {
  const ignore = (f) => !f || /^_dashboard([\\/]|$)/.test(f) || /dashboard\.html$/i.test(f);
  try {
    fs.watch(workRoot, { recursive: true }, (_e, f) => {
      if (!ignore(String(f || ""))) scheduleRefresh("files");
    });
  } catch (e) {
    log("File watching is not available here; polling only.", e.message);
  }
  setInterval(() => scheduleRefresh("poll", 0), opt.poll * 1000);
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

// Which item a command belongs to, from its arguments ("41207 3", "tsd-x", ".work/docs-y/guide.md").
function folderForArgs(args) {
  if (!model || !args) return null;
  const first = String(args).trim().split(/\s+/)[0] || "";
  for (const it of model.items || []) {
    if (it.id && first === String(it.id)) return it.folder;
    if (first === it.folder) return it.folder;
    if (first.replace(/\\/g, "/").includes(`.work/${it.folder}/`)) return it.folder;
  }
  return null;
}

// Commands run before the model existed (or before an item folder existed) get linked once it does.
const unlinked = new Map(); // sessionID -> { args, command }
function linkSessionsFromModel() {
  for (const [sid, u] of unlinked) {
    const f = folderForArgs(u.args);
    if (f) {
      linkSession(f, sid, u.command);
      unlinked.delete(sid);
    }
  }
}

// ------------------------------------------------------------------ opencode connection

const oc = {
  url: opt.opencode,
  connected: false,
  version: null,
  error: null,
  started: false,
  commands: new Set(),
};
const sessions = new Map(); // id -> { id, title, status, activity, text, error, updated }
const msgRole = new Map(); // messageID -> role
const partText = new Map(); // partID -> text
const permissions = new Map(); // id -> request
const questions = new Map(); // id -> request

function ocUrl(p, q = {}) {
  const u = new URL(oc.url + p);
  u.searchParams.set("directory", opt.workspace);
  for (const [k, v] of Object.entries(q)) u.searchParams.set(k, v);
  return u.toString();
}

async function ocFetch(p, { method = "GET", body, query, timeout = 15000 } = {}) {
  const ctrl = new AbortController();
  const t = timeout ? setTimeout(() => ctrl.abort(), timeout) : null;
  try {
    const r = await fetch(ocUrl(p, query), {
      method,
      headers: body ? { "content-type": "application/json" } : {},
      body: body ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
    const text = await r.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = text;
    }
    return { ok: r.ok, status: r.status, data };
  } finally {
    if (t) clearTimeout(t);
  }
}

async function health() {
  try {
    const r = await fetch(oc.url + "/global/health", { signal: AbortSignal.timeout(2500) });
    if (!r.ok) return null;
    return await r.json();
  } catch {
    return null;
  }
}

function startOpencode() {
  const u = new URL(oc.url);
  if (!/^(127\.0\.0\.1|localhost|\[::1\])$/.test(u.hostname)) {
    oc.error = `No opencode server at ${oc.url}, and it is not local, so it was not started.`;
    return;
  }
  const port = u.port || "4096";
  const logFile = path.join(stateDir, "opencode.log");
  const out = fs.openSync(logFile, "a");
  log(`Starting: ${opt.opencodeCmd} serve --port ${port} (log: ${logFile})`);
  const serveArgs = ["serve", "--port", port, "--hostname", "127.0.0.1"];
  const spawnOpts = { cwd: opt.workspace, stdio: ["ignore", out, out], windowsHide: true };
  // On Windows opencode is usually a .cmd shim, which needs a shell. The arguments are fixed, so one string is safe.
  const child = isWin
    ? spawn(`"${opt.opencodeCmd}" ${serveArgs.join(" ")}`, { ...spawnOpts, shell: true })
    : spawn(opt.opencodeCmd, serveArgs, spawnOpts);
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
  let h = await health();
  if (!h && opt.startOpencode && !oc.started) {
    startOpencode();
    for (let i = 0; i < 40 && !h; i++) {
      await sleep(750);
      h = await health();
    }
  }
  if (!h) {
    oc.connected = false;
    if (!oc.error) oc.error = `opencode is not running at ${oc.url}. Start it with: opencode serve --port ${new URL(oc.url).port || 4096}`;
    broadcastLive();
    setTimeout(connectOpencode, 5000);
    return;
  }
  oc.version = h.version || null;
  oc.error = null;
  try {
    await loadInitialState();
  } catch (e) {
    log("opencode: could not load sessions:", e.message);
  }
  followEvents();
}

async function loadInitialState() {
  const cmds = await ocFetch("/command");
  if (cmds.ok && Array.isArray(cmds.data)) oc.commands = new Set(cmds.data.map((c) => c.name));

  // Drop links to sessions that no longer exist.
  const list = await ocFetch("/session");
  if (list.ok && Array.isArray(list.data)) {
    const ids = new Set(list.data.map((s) => s.id));
    let changed = false;
    for (const s of list.data) upsertSession(s.id, { title: s.title, updated: s.time && s.time.updated });
    for (const [f, e] of Object.entries(links)) {
      const keep = e.sessions.filter((s) => ids.has(s.id));
      if (keep.length !== e.sessions.length) {
        changed = true;
        if (keep.length) e.sessions = keep;
        else delete links[f];
      }
    }
    if (changed) saveLinks();
  }

  const st = await ocFetch("/session/status");
  if (st.ok && st.data && typeof st.data === "object") {
    for (const [id, s] of Object.entries(st.data)) upsertSession(id, { status: s.type });
  }

  permissions.clear();
  const perms = await ocFetch("/permission");
  if (perms.ok && Array.isArray(perms.data)) for (const p of perms.data) permissions.set(p.id, p);

  questions.clear();
  const qs = await ocFetch("/question");
  if (qs.ok && Array.isArray(qs.data)) for (const q of qs.data) questions.set(q.id, q);

  // Last reply of each item's current session.
  await Promise.all(Object.keys(links).map((f) => loadLastText(currentSession(f))));
}

async function loadLastText(id) {
  if (!id) return;
  const r = await ocFetch(`/session/${id}/message`, { query: { limit: "8" } });
  if (!r.ok || !Array.isArray(r.data)) return;
  for (let i = r.data.length - 1; i >= 0; i--) {
    const m = r.data[i];
    if (!m.info || m.info.role !== "assistant") continue;
    const text = (m.parts || []).filter((p) => p.type === "text" && !p.synthetic).map((p) => p.text).join("\n").trim();
    if (text) {
      upsertSession(id, { text, textAt: (m.info.time && (m.info.time.completed || m.info.time.created)) || null });
      break;
    }
  }
}

function upsertSession(id, patch) {
  if (!id) return {};
  const s = sessions.get(id) || { id, title: null, status: "idle", activity: null, text: null, error: null, updated: null };
  for (const [k, v] of Object.entries(patch)) if (v !== undefined) s[k] = v;
  sessions.set(id, s);
  return s;
}

let eventsCtrl = null;
async function followEvents() {
  if (eventsCtrl) eventsCtrl.abort();
  eventsCtrl = new AbortController();
  try {
    const r = await fetch(ocUrl("/event"), { signal: eventsCtrl.signal, headers: { accept: "text/event-stream" } });
    if (!r.ok || !r.body) throw new Error(`event stream: HTTP ${r.status}`);
    oc.connected = true;
    log(`opencode ${oc.version || ""} connected at ${oc.url}`);
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
          onEvent(JSON.parse(data));
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

function toolLine(part) {
  const st = part.state || {};
  const inp = st.input || {};
  const what = st.title || inp.description || inp.command || inp.filePath || inp.pattern || inp.path || "";
  return `${part.tool}${what ? ": " + String(what).split(/\r?\n/)[0].slice(0, 160) : ""}`;
}

function onEvent(ev) {
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
      const prev = sessions.get(sid);
      const starting = type !== "idle" && (!prev || prev.status === "idle");
      upsertSession(sid, { status: type, ...(starting ? { error: null, busySince: Date.now() } : {}) });
      if (type === "retry") upsertSession(sid, { activity: `Retrying (attempt ${p.status.attempt}): ${p.status.message || ""}` });
      break;
    }
    case "session.idle":
      upsertSession(sid, { status: "idle", activity: null });
      loadLastText(sid).then(broadcastLive, () => {});
      break;
    case "session.error": {
      const e = p.error || {};
      const msg = (e.data && (e.data.message || e.data.providerID)) || e.name || "Unknown error";
      if (sid && e.name !== "MessageAbortedError") upsertSession(sid, { error: String(msg).slice(0, 500) });
      if (sid && e.name === "MessageAbortedError") upsertSession(sid, { activity: null, error: "Stopped." });
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
      if (part.type === "tool") upsertSession(sid, { activity: toolLine(part) });
      else if (part.type === "text" && msgRole.get(part.messageID) === "assistant" && !part.synthetic) {
        partText.set(part.id, part.text || "");
        upsertSession(sid, { text: part.text || "", textAt: Date.now(), activity: "Writing a reply" });
      } else if (part.type === "reasoning") upsertSession(sid, { activity: "Thinking" });
      break;
    }
    case "message.part.delta": {
      if (p.field !== "text" || msgRole.get(p.messageID) !== "assistant") break;
      const t = (partText.get(p.partID) || "") + (p.delta || "");
      partText.set(p.partID, t);
      if (partText.size > 500) partText.delete(partText.keys().next().value);
      upsertSession(sid, { text: t, textAt: Date.now(), activity: "Writing a reply" });
      break;
    }
    case "permission.asked":
    case "permission.updated": // older opencode
      if (p.id) permissions.set(p.id, p);
      break;
    case "permission.replied":
      permissions.delete(p.requestID || p.permissionID || p.id);
      break;
    case "question.asked":
      if (p.id) questions.set(p.id, p);
      break;
    case "question.replied":
    case "question.rejected":
      questions.delete(p.requestID || p.id);
      break;
    case "command.executed": {
      upsertSession(sid, { command: `/${p.name}${p.arguments ? " " + p.arguments : ""}` });
      if (!folderForSession(sid)) {
        const f = folderForArgs(p.arguments);
        if (f) linkSession(f, sid, `/${p.name} ${p.arguments || ""}`.trim());
        else if (p.arguments) unlinked.set(sid, { args: p.arguments, command: `/${p.name} ${p.arguments}` });
      }
      break;
    }
    case "server.instance.disposed":
    case "global.disposed":
      setTimeout(() => loadInitialState().then(broadcastLive, () => {}), 500);
      break;
    default:
      return; // not interesting; no broadcast
  }
  broadcastLive();
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

async function runCommand({ folder, command }) {
  if (!oc.connected) throw httpError(503, oc.error || "opencode is not connected.");
  const item = findItem(folder);
  if (!item) throw httpError(404, `No work item folder "${folder}". Refresh the page.`);
  const cmd = parseCommand(command);
  if (!cmd) throw httpError(400, `Not a command: ${command}`);
  if (oc.commands.size && !oc.commands.has(cmd.name)) throw httpError(400, `opencode has no /${cmd.name} command. Re-run install.ps1, then restart opencode.`);

  let sid = FRESH_SESSION.has(cmd.name) ? null : currentSession(folder);
  if (sid) {
    const s = sessions.get(sid);
    if (!s) sid = null; // deleted in opencode
    else if (s.status !== "idle") throw httpError(409, "This item's session is still working. Wait for it, or stop it first.");
  }
  if (!sid) {
    const title = `${labelFor(item)}: /${cmd.name}${cmd.args ? " " + cmd.args : ""}`;
    const r = await ocFetch("/session", { method: "POST", body: { title } });
    if (!r.ok || !r.data || !r.data.id) throw httpError(502, `opencode could not create a session (HTTP ${r.status}).`);
    sid = r.data.id;
    upsertSession(sid, { title: r.data.title || title });
  }
  linkSession(folder, sid, `/${cmd.name} ${cmd.args}`.trim());
  upsertSession(sid, { status: "busy", busySince: Date.now(), activity: `Starting /${cmd.name}`, error: null, text: null, command: `/${cmd.name} ${cmd.args}`.trim() });
  broadcastLive();

  // The command endpoint answers only when the agent finishes, so do not wait for it.
  ocFetch(`/session/${sid}/command`, { method: "POST", body: { command: cmd.name, arguments: cmd.args }, timeout: 0 })
    .then((r) => {
      if (!r.ok) {
        const msg = (r.data && (r.data.message || (r.data.data && r.data.data.message) || r.data.name)) || `HTTP ${r.status}`;
        upsertSession(sid, { status: "idle", activity: null, error: `/${cmd.name} failed: ${String(msg).slice(0, 300)}` });
        broadcastLive();
      }
    })
    .catch((e) => {
      upsertSession(sid, { error: `/${cmd.name}: ${e.message}` });
      broadcastLive();
    });
  log(`run /${cmd.name} ${cmd.args} (${folder}) in ${sid}`);
  return { session: sid };
}

async function reply({ session, text }) {
  if (!oc.connected) throw httpError(503, oc.error || "opencode is not connected.");
  if (!sessions.has(session)) throw httpError(404, "Unknown session.");
  const t = String(text || "").trim();
  if (!t) throw httpError(400, "Type a reply first.");
  if (t.startsWith("/")) {
    const folder = folderForSession(session);
    if (folder) return runCommand({ folder, command: t });
  }
  const r = await ocFetch(`/session/${session}/prompt_async`, { method: "POST", body: { parts: [{ type: "text", text: t }] } });
  if (!r.ok) throw httpError(502, `opencode did not take the reply (HTTP ${r.status}).`);
  upsertSession(session, { status: "busy", busySince: Date.now(), activity: "Reading your reply", error: null, text: null });
  broadcastLive();
  return { ok: true };
}

async function answerPermission({ id, reply: answer }) {
  const p = permissions.get(id);
  if (!p) throw httpError(404, "That prompt was already answered.");
  if (!["once", "always", "reject"].includes(answer)) throw httpError(400, "Bad answer.");
  let r = await ocFetch(`/session/${p.sessionID}/permissions/${id}`, { method: "POST", body: { response: answer } });
  if (r.status === 404) r = await ocFetch(`/permission/${id}/reply`, { method: "POST", body: { reply: answer } });
  if (!r.ok) throw httpError(502, `opencode did not take the answer (HTTP ${r.status}).`);
  permissions.delete(id);
  broadcastLive();
  return { ok: true };
}

async function answerQuestion({ id, answers, reject }) {
  if (!questions.has(id)) throw httpError(404, "That question was already answered.");
  const r = reject
    ? await ocFetch(`/question/${id}/reject`, { method: "POST" })
    : await ocFetch(`/question/${id}/reply`, { method: "POST", body: { answers } });
  if (!r.ok) throw httpError(502, `opencode did not take the answer (HTTP ${r.status}).`);
  questions.delete(id);
  broadcastLive();
  return { ok: true };
}

async function abort({ session }) {
  const r = await ocFetch(`/session/${session}/abort`, { method: "POST" });
  if (!r.ok) throw httpError(502, `opencode could not stop it (HTTP ${r.status}).`);
  return { ok: true };
}

function attachCommand(session) {
  const dir = /\s/.test(opt.workspace) ? `"${opt.workspace}"` : opt.workspace;
  return `opencode attach ${oc.url}${session ? " --session " + session : ""} --dir ${dir}`;
}

// Opens a terminal window with the opencode TUI attached to this server (Windows and macOS).
function openTerminal({ session }) {
  if (session && !/^ses_[A-Za-z0-9]+$/.test(session)) throw httpError(400, "Bad session id.");
  const attach = `${opt.opencodeCmd} attach ${oc.url}${session ? " --session " + session : ""}`;
  if (isWin) {
    const ws = opt.workspace.replace(/'/g, "''");
    const inner = attach.replace(/'/g, "''");
    const script = `Start-Process -FilePath powershell.exe -WorkingDirectory '${ws}' -ArgumentList @('-NoExit','-Command','${inner}')`;
    const enc = Buffer.from(script, "utf16le").toString("base64");
    spawn("powershell.exe", ["-NoProfile", "-EncodedCommand", enc], { detached: true, stdio: "ignore", windowsHide: true }).unref();
    return { ok: true };
  }
  if (process.platform === "darwin") {
    const sh = `cd '${opt.workspace.replace(/'/g, "'\\''")}' && ${attach}`;
    const as = `tell application "Terminal" to do script "${sh.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"\ntell application "Terminal" to activate`;
    spawn("osascript", ["-e", as], { detached: true, stdio: "ignore" }).unref();
    return { ok: true };
  }
  throw httpError(501, "Opening a terminal is only supported on Windows and macOS. Copy the command instead.");
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
    opencode: { url: oc.url, connected: oc.connected, version: oc.version, error: oc.error, started: oc.started, attach: attachCommand(null) },
    items,
    sessions: tracked,
    permissions: [...permissions.values()].map((p) => ({
      id: p.id,
      sessionID: p.sessionID,
      permission: p.permission || p.type,
      patterns: p.patterns || (p.pattern ? [].concat(p.pattern) : []),
      always: p.always || [],
      title: (p.metadata && (p.metadata.command || p.metadata.filepath || p.metadata.filePath)) || p.title || null,
      folder: folderForSession(p.sessionID),
    })),
    questions: [...questions.values()].map((q) => ({ id: q.id, sessionID: q.sessionID, questions: q.questions || [], folder: folderForSession(q.sessionID) })),
    canOpenTerminal: isWin || process.platform === "darwin",
  };
}

function pageData() {
  const base = model || { items: [], repos: [], activity: [], workspace: opt.workspace, generatedMs: Date.now(), generated: new Date().toISOString() };
  return { ...base, liveMode: { token, error: modelError, live: liveData() } };
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
  "/api/run": runCommand,
  "/api/reply": reply,
  "/api/permission": answerPermission,
  "/api/question": answerQuestion,
  "/api/abort": abort,
  "/api/terminal": openTerminal,
  "/api/refresh": async () => {
    await refresh("button");
    return { ok: true };
  },
};

const server = http.createServer(async (req, res) => {
  // Only this machine, only this page: block other sites and DNS rebinding.
  const host = String(req.headers.host || "");
  if (host !== `127.0.0.1:${opt.port}` && host !== `localhost:${opt.port}`) return send(res, 403, { error: "Bad host." });
  const origin = req.headers.origin;
  if (origin && origin !== `http://127.0.0.1:${opt.port}` && origin !== `http://localhost:${opt.port}`) return send(res, 403, { error: "Bad origin." });

  const url = new URL(req.url, `http://${host}`);
  try {
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) return send(res, 200, renderPage(), "text/html; charset=utf-8");
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
if (running && running.app === APP && path.resolve(running.workspace) === opt.workspace) {
  console.log(`Already running: ${pageUrl}`);
  if (opt.open) openBrowser(pageUrl);
  process.exit(0);
}
if (running) fail(`Port ${opt.port} is in use${running.workspace ? " by the dashboard for " + running.workspace : ""}. Pick another port (Start-LiveDashboard.ps1 -Port <n>).`);

server.on("error", (e) => fail(e.code === "EADDRINUSE" ? `Port ${opt.port} is in use. Pick another port (Start-LiveDashboard.ps1 -Port <n>).` : e.message));
server.listen(opt.port, "127.0.0.1", async () => {
  console.log(`Live dashboard: ${pageUrl}`);
  console.log(`Workspace:      ${opt.workspace}`);
  console.log(`Attach the TUI: ${attachCommand(null)}`);
  console.log("Keep this window open. Ctrl+C stops the dashboard" + (opt.startOpencode ? ", and opencode if the dashboard started it." : "."));
  await refresh("start");
  watchWork();
  connectOpencode();
  if (opt.open) openBrowser(pageUrl);
});

// SIGHUP: the console window was closed (Windows) or the terminal went away.
for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(sig, () => process.exit(0));
