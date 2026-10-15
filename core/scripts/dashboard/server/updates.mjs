// eng-agents live dashboard: Update checks and updates through update.ps1 in the repo this was installed from.

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HERE, httpError, log, psExe } from "./context.mjs";
import { sessions } from "./opencode-state.mjs";
import { autoActive, autopilot } from "./autopilot.mjs";
import { broadcast, broadcastLive } from "./live.mjs";

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
export const runningVersion = readVersion();
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
export const UPDATE_EVERY_MS = 6 * 3600e3;
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

export async function checkUpdates() {
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

export async function runUpdate({ component }) {
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

export async function restartAction() {
  if (!supervised) throw httpError(400, "This dashboard was not started with Start-LiveDashboard.ps1. Stop it and start it again.");
  const busy = updateBlocker();
  if (busy) throw httpError(409, `${busy}. Restart when it is done.`);
  restartSoon();
  return { ok: true };
}

export function updateData() {
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
