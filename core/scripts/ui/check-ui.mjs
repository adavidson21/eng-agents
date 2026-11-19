#!/usr/bin/env node
// UI checks for one repo: starts the app, opens each page in headless Chromium at two widths, takes
// screenshots, checks for load errors, console errors, failed requests and simple accessibility problems,
// compares with an earlier run (`--compare`), stops the app and writes results-<name>.json.
// Called by Test-UI.ps1 (which reads the repo guide's UI checks table); not meant to be run by hand.
//
//   node check-ui.mjs --cwd <repo or worktree> --url http://localhost:4200 --pages /,/orders --out <work folder>/ui
//                     --name after [--start "npm start"] [--ready /] [--seed "npm run seed"] [--compare before]
//                     [--timeout 180]
//
// The last line printed is always one of: "UI: PASS ...", "UI: FAIL ...", "UI: SKIPPED ...".
// Exit code: 0 for PASS and SKIPPED, 1 for FAIL.

import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { decodePng, diffImages, encodePng } from "./png.mjs";

export const WIDTHS = [1280, 640];

export function parseArgs(argv) {
  const o = { pages: ["/"], timeout: 180, ready: null, start: null, seed: null, compare: null };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const v = argv[i + 1];
    if (!k.startsWith("--")) continue;
    const key = k.slice(2);
    i++;
    if (key === "pages") o.pages = String(v || "/").split(",").map((p) => p.trim()).filter(Boolean);
    else if (key === "timeout") o.timeout = Math.max(10, Number(v) || 180);
    else o[key] = v;
  }
  return o;
}

/** A file name for a page path: "/" -> "home", "/orders/12?x=1" -> "orders-12-x-1". */
export function slugOf(p) {
  const s = String(p).replace(/^\/+|\/+$/g, "").replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "").toLowerCase();
  return (s || "home").slice(0, 60);
}

/** Same origin as the app: requests we count as failures when they fail. */
export function sameOrigin(a, b) {
  try {
    return new URL(a).origin === new URL(b).origin;
  } catch {
    return false;
  }
}

/** Pages that got worse than the earlier run, or failed outright. Returns a list of one-line problems. */
export function problemsOf(pages) {
  const out = [];
  for (const p of pages) {
    const at = `${p.path} at ${p.width}px`;
    if (p.error) out.push(`${at}: ${p.error}`);
    else if (p.status >= 400) out.push(`${at}: HTTP ${p.status}`);
    for (const e of p.consoleErrors || []) out.push(`${at}: console error: ${e}`);
    for (const r of p.failedRequests || []) out.push(`${at}: request failed: ${r}`);
    if (p.a11y && p.a11yBefore) {
      for (const k of Object.keys(p.a11y)) if (p.a11y[k] > (p.a11yBefore[k] || 0)) out.push(`${at}: ${p.a11y[k] - (p.a11yBefore[k] || 0)} more ${A11Y_WORDS[k] || k}`);
    }
  }
  return out;
}

export const A11Y_WORDS = { imagesNoAlt: "images with no alt text", controlsNoName: "buttons or links with no name", inputsNoLabel: "inputs with no label" };

function loadPlaywright(cwd) {
  const tries = [];
  const roots = [path.join(cwd, "package.json"), path.join(process.cwd(), "package.json"), import.meta.url];
  for (const root of roots) {
    let req;
    try {
      req = createRequire(root);
    } catch {
      continue;
    }
    for (const name of ["playwright", "@playwright/test", "playwright-core"]) {
      try {
        const m = req(name);
        if (m && m.chromium) return m;
      } catch (e) {
        tries.push(name);
      }
    }
  }
  return null;
}

async function up(url) {
  try {
    const r = await fetch(url, { redirect: "manual" });
    return r.status < 500;
  } catch {
    return false;
  }
}

function startApp(cmd, cwd) {
  const win = process.platform === "win32";
  const child = spawn(cmd, { cwd, shell: true, detached: !win, stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, BROWSER: "none", CI: "1" } });
  let tail = "";
  const keep = (d) => { tail = (tail + d.toString()).slice(-2000); };
  child.stdout.on("data", keep);
  child.stderr.on("data", keep);
  return { child, tail: () => tail };
}

function stopApp(app) {
  if (!app || app.child.exitCode !== null) return;
  try {
    if (process.platform === "win32") spawnSync("taskkill", ["/pid", String(app.child.pid), "/T", "/F"], { stdio: "ignore" });
    else process.kill(-app.child.pid, "SIGTERM");
  } catch {}
}

const A11Y_SCRIPT = () => {
  const named = (el) => (el.getAttribute("aria-label") || el.getAttribute("title") || el.textContent || "").trim() || (el.querySelector("img[alt]") && el.querySelector("img[alt]").getAttribute("alt").trim());
  const visible = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  const imagesNoAlt = [...document.querySelectorAll("img")].filter((i) => visible(i) && !i.hasAttribute("alt")).length;
  const controlsNoName = [...document.querySelectorAll("button, a[href], [role=button]")].filter((b) => visible(b) && !named(b) && !b.getAttribute("aria-labelledby")).length;
  const inputsNoLabel = [...document.querySelectorAll("input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea")].filter((i) => {
    if (!visible(i)) return false;
    if (i.getAttribute("aria-label") || i.getAttribute("aria-labelledby") || i.getAttribute("title")) return false;
    if (i.id && document.querySelector(`label[for="${CSS.escape(i.id)}"]`)) return false;
    return !i.closest("label");
  }).length;
  return { imagesNoAlt, controlsNoName, inputsNoLabel };
};

export async function run(o, log = console.log) {
  const out = path.resolve(o.out);
  const shots = path.join(out, o.name);
  const result = { version: 1, name: o.name, at: new Date().toISOString(), url: o.url, verdict: "skipped", reason: null, pages: [], problems: [] };
  const finish = (verdict, reason) => {
    result.verdict = verdict;
    result.reason = reason || null;
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, `results-${o.name}.json`), JSON.stringify(result, null, 2));
    const word = verdict.toUpperCase();
    log(`UI: ${word} ${reason || ""}`.trim());
    return verdict === "fail" ? 1 : 0;
  };
  if (!o.url || !o.cwd || !o.out || !/^[a-z0-9-]{1,30}$/.test(String(o.name || ""))) return finish("skipped", "bad arguments (need --cwd, --url, --out and --name)");

  const pw = loadPlaywright(o.cwd);
  if (!pw) return finish("skipped", "Playwright is not installed for this repo (npm i -D playwright, then npx playwright install chromium)");

  const base = o.url.replace(/\/+$/, "");
  const readyUrl = base + (o.ready ? (o.ready.startsWith("/") ? o.ready : "/" + o.ready) : "/");
  let app = null;
  let browser = null;
  let earlier = null;
  try {
    if (!(await up(readyUrl))) {
      if (!o.start) return finish("skipped", `the app is not running at ${readyUrl} and the UI checks table has no Start command`);
      if (o.seed) {
        const s = spawnSync(o.seed, { cwd: o.cwd, shell: true, encoding: "utf8", timeout: o.timeout * 1000 });
        if (s.status !== 0) return finish("skipped", `the seed command failed: ${String(s.stderr || s.stdout || "").trim().split(/\r?\n/).slice(-1)[0] || "exit " + s.status}`);
      }
      app = startApp(o.start, o.cwd);
      const until = Date.now() + o.timeout * 1000;
      while (!(await up(readyUrl))) {
        if (app.child.exitCode !== null) return finish("skipped", `the app stopped before it was ready (it needs something it cannot get locally?): ${app.tail().trim().split(/\r?\n/).slice(-1)[0] || "exit " + app.child.exitCode}`);
        if (Date.now() > until) return finish("skipped", `the app was not ready at ${readyUrl} after ${o.timeout} seconds`);
        await new Promise((r) => setTimeout(r, 1000));
      }
    }

    fs.rmSync(shots, { recursive: true, force: true });
    fs.mkdirSync(shots, { recursive: true });
    browser = await pw.chromium.launch();
    if (o.compare) {
      try {
        earlier = JSON.parse(fs.readFileSync(path.join(out, `results-${o.compare}.json`), "utf8"));
      } catch {}
    }
    for (const p of o.pages) {
      for (const width of WIDTHS) {
        const ctx = await browser.newContext({ viewport: { width, height: 900 } });
        const page = await ctx.newPage();
        const consoleErrors = [];
        const failedRequests = [];
        page.on("console", (m) => { if (m.type() === "error" && consoleErrors.length < 10) consoleErrors.push(m.text().slice(0, 200)); });
        page.on("pageerror", (e) => { if (consoleErrors.length < 10) consoleErrors.push(String(e.message || e).slice(0, 200)); });
        page.on("requestfailed", (r) => { if (sameOrigin(r.url(), base) && failedRequests.length < 10) failedRequests.push(`${r.url().slice(0, 150)} (${(r.failure() && r.failure().errorText) || "failed"})`); });
        page.on("response", (r) => { if (r.status() >= 500 && sameOrigin(r.url(), base) && failedRequests.length < 10) failedRequests.push(`${r.url().slice(0, 150)} (HTTP ${r.status()})`); });
        const file = `${slugOf(p)}-${width}.png`;
        const row = { path: p, width, file: `${o.name}/${file}`, status: null, error: null, consoleErrors, failedRequests, a11y: null, a11yBefore: null, diff: null };
        try {
          const resp = await page.goto(base + (p.startsWith("/") ? p : "/" + p), { waitUntil: "networkidle", timeout: 30000 });
          row.status = resp ? resp.status() : null;
          await page.screenshot({ path: path.join(shots, file), fullPage: true, animations: "disabled" });
          row.a11y = await page.evaluate(A11Y_SCRIPT);
        } catch (e) {
          row.error = String(e.message || e).split(/\r?\n/)[0].slice(0, 200);
        }
        await ctx.close();
        const prev = earlier && (earlier.pages || []).find((x) => x.path === p && x.width === width);
        if (prev) {
          row.a11yBefore = prev.a11y || null;
          const a = path.join(out, prev.file || "");
          const b = path.join(shots, file);
          if (prev.file && fs.existsSync(a) && fs.existsSync(b)) {
            try {
              const d = diffImages(decodePng(fs.readFileSync(a)), decodePng(fs.readFileSync(b)));
              row.diff = { against: o.compare, changedPct: d.changedPct, sizeChanged: d.sizeChanged, file: null };
              if (d.image && d.changedPct > 0) {
                fs.mkdirSync(path.join(out, "diff"), { recursive: true });
                fs.writeFileSync(path.join(out, "diff", file), encodePng(d.image));
                row.diff.file = `diff/${file}`;
              }
            } catch (e) {
              row.diff = { against: o.compare, changedPct: null, sizeChanged: false, file: null, error: String(e.message || e) };
            }
          }
        }
        result.pages.push(row);
      }
    }
  } finally {
    if (browser) await browser.close().catch(() => {});
    stopApp(app);
  }
  result.problems = problemsOf(result.pages);
  const changed = result.pages.filter((p) => p.diff && (p.diff.sizeChanged || p.diff.changedPct > 0)).map((p) => `${p.path} at ${p.width}px`);
  result.changed = changed;
  const summary = `${o.pages.length} page${o.pages.length === 1 ? "" : "s"} at ${WIDTHS.length} widths${o.compare && earlier ? `, ${changed.length} changed since ${o.compare}` : ""}`;
  if (result.problems.length) return finish("fail", `${summary}; ${result.problems.length} problem${result.problems.length === 1 ? "" : "s"}: ${result.problems.slice(0, 3).join("; ")}`);
  return finish("pass", summary);
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  run(parseArgs(process.argv.slice(2))).then((code) => process.exit(code), (e) => {
    console.log(`UI: SKIPPED the check itself failed: ${String(e && e.message || e).split(/\r?\n/)[0]}`);
    process.exit(0);
  });
}
