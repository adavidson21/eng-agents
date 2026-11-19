#!/usr/bin/env node
// A build's app, kept running between UI checks (Core 4.15.0): started once for a work item's repo (or its worktree),
// recorded in <work folder>/ui/app.json, reused by every per-task UI check and by Workshop's Try it, stopped at review,
// on Remove, or by Workshop after it has been idle. Called by Start-UiApp.ps1 and Stop-UiApp.ps1 (which read the repo
// guide's UI checks table); not meant to be run by hand.
//
//   node app.mjs serve --cwd <repo or worktree> --url "http://localhost:{port}" --out <work folder>/ui
//                      [--start "npm start -- --port {port}"] [--ready /] [--seed "npm run seed"] [--timeout 180]
//   node app.mjs stop  --out <work folder>/ui
//
// {port} in the URL and Start is a free port picked here, so builds on one repo never collide.
// The last line printed is always "APP: RUNNING <url>", "APP: STOPPED", "APP: NONE" or "APP: SKIPPED <why>".

import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { pathToFileURL } from "node:url";

export function parseArgs(argv) {
  const o = { mode: argv[0] && !argv[0].startsWith("--") ? argv[0] : null, timeout: 180, ready: null, start: null, seed: null };
  for (let i = o.mode ? 1 : 0; i < argv.length; i++) {
    const k = argv[i];
    if (!k.startsWith("--")) continue;
    const key = k.slice(2);
    const v = argv[i + 1];
    i++;
    if (key === "timeout") o.timeout = Math.max(10, Number(v) || 180);
    else o[key] = v;
  }
  return o;
}

/** A port nothing listens on, from the OS. */
export function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on("error", reject);
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

/** Puts the port in for {port}. */
export const withPort = (text, port) => (text == null ? text : String(text).split("{port}").join(String(port)));

/** Whether the process is still there. */
export function alive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === "EPERM";
  }
}

/** The app recorded for this work folder, or null. */
export function readApp(out) {
  try {
    const a = JSON.parse(fs.readFileSync(path.join(out, "app.json"), "utf8"));
    return a && typeof a.url === "string" ? a : null;
  } catch {
    return null;
  }
}

export async function up(url) {
  try {
    const r = await fetch(url, { redirect: "manual" });
    return r.status < 500;
  } catch {
    return false;
  }
}

export const readyUrlOf = (url, ready) => url.replace(/\/+$/, "") + (ready ? (ready.startsWith("/") ? ready : "/" + ready) : "/");

/** The URL of a recorded app that is still running and answering, or null (a stale record is removed). */
export async function runningApp(out, ready) {
  const a = readApp(out);
  if (!a) return null;
  if (alive(a.pid) && (await up(readyUrlOf(a.url, ready || a.ready)))) return a;
  try { fs.rmSync(path.join(out, "app.json"), { force: true }); } catch {}
  return null;
}

function killTree(pid) {
  try {
    if (process.platform === "win32") spawnSync("taskkill", ["/pid", String(pid), "/T", "/F"], { stdio: "ignore", windowsHide: true });
    else process.kill(-pid, "SIGTERM");
  } catch {
    try { process.kill(pid, "SIGTERM"); } catch {}
  }
}

export async function serve(o, log = console.log) {
  const done = (line) => { log(line); return 0; };
  if (!o.cwd || !o.url || !o.out) return done("APP: SKIPPED bad arguments (need --cwd, --url and --out)");
  const out = path.resolve(o.out);
  fs.mkdirSync(out, { recursive: true });
  const was = await runningApp(out, o.ready);
  if (was) return done(`APP: RUNNING ${was.url}`);

  const port = String(o.url).includes("{port}") || String(o.start || "").includes("{port}") ? await freePort() : null;
  const url = withPort(o.url, port);
  const start = withPort(o.start, port);
  const readyUrl = readyUrlOf(url, o.ready);
  if (await up(readyUrl)) {
    // Something else already serves this address (the engineer's own dev server): use it, never stop it.
    fs.writeFileSync(path.join(out, "app.json"), JSON.stringify({ version: 1, pid: null, url, ready: o.ready || null, port, cwd: o.cwd, started: new Date().toISOString(), ours: false }, null, 2));
    return done(`APP: RUNNING ${url}`);
  }
  if (!start) return done(`APP: SKIPPED the app is not running at ${readyUrl} and the UI checks table has no Start command`);
  if (o.seed) {
    const s = spawnSync(withPort(o.seed, port), { cwd: o.cwd, shell: true, encoding: "utf8", timeout: o.timeout * 1000, windowsHide: true });
    if (s.status !== 0) return done(`APP: SKIPPED the seed command failed: ${String(s.stderr || s.stdout || "").trim().split(/\r?\n/).slice(-1)[0] || "exit " + s.status}`);
  }
  const logFile = path.join(out, "app.log");
  const fd = fs.openSync(logFile, "w");
  const child = spawn(start, { cwd: o.cwd, shell: true, detached: true, windowsHide: true, stdio: ["ignore", fd, fd], env: { ...process.env, BROWSER: "none", CI: "1", PORT: port ? String(port) : process.env.PORT } });
  fs.closeSync(fd);
  let exited = null;
  child.on("exit", (code) => { exited = code === null ? "killed" : code; });
  const until = Date.now() + o.timeout * 1000;
  while (!(await up(readyUrl))) {
    if (exited !== null) {
      const tail = fs.existsSync(logFile) ? fs.readFileSync(logFile, "utf8").trim().split(/\r?\n/).slice(-1)[0] : "";
      return done(`APP: SKIPPED the app stopped before it was ready: ${tail || "exit " + exited}`);
    }
    if (Date.now() > until) {
      killTree(child.pid);
      return done(`APP: SKIPPED the app was not ready at ${readyUrl} after ${o.timeout} seconds`);
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  fs.writeFileSync(path.join(out, "app.json"), JSON.stringify({ version: 1, pid: child.pid, url, ready: o.ready || null, port, cwd: o.cwd, started: new Date().toISOString(), ours: true }, null, 2));
  child.unref();
  return done(`APP: RUNNING ${url}`);
}

export async function stop(o, log = console.log) {
  if (!o.out) { log("APP: SKIPPED bad arguments (need --out)"); return 0; }
  const out = path.resolve(o.out);
  const a = readApp(out);
  if (!a) { log("APP: NONE"); return 0; }
  if (a.ours !== false && alive(a.pid)) killTree(a.pid);
  try { fs.rmSync(path.join(out, "app.json"), { force: true }); } catch {}
  log("APP: STOPPED");
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  const o = parseArgs(process.argv.slice(2));
  const fn = o.mode === "stop" ? stop : o.mode === "serve" ? serve : null;
  if (!fn) {
    console.log("APP: SKIPPED usage: node app.mjs serve|stop ...");
    process.exit(0);
  }
  fn(o).then((code) => process.exit(code), (e) => {
    console.log(`APP: SKIPPED ${String(e && e.message || e).split(/\r?\n/)[0]}`);
    process.exit(0);
  });
}
