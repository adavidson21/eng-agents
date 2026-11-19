// The build's warm app (app.mjs, Core 4.15.0): {port} gets a free port, serve starts the app once and records it,
// a second serve reuses it, stop ends it and removes the record, an app that stops before it is ready is skipped.
// Also check-ui.mjs's new arguments and its accessibility text. Run: node --test "core/scripts/ui/test/*.test.mjs"

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { alive, freePort, parseArgs, readApp, runningApp, serve, stop, up, withPort } from "../app.mjs";
import { parseArgs as checkArgs, treeText } from "../check-ui.mjs";

const SERVER = `require("http").createServer((q, s) => { s.setHeader("content-type", "text/html"); s.end("<h1>Hi</h1>"); }).listen(Number(process.argv[2]), "127.0.0.1");`;

test("args, ports and {port}", async () => {
  const o = parseArgs(["serve", "--cwd", "x", "--url", "http://127.0.0.1:{port}", "--out", "o", "--timeout", "3"]);
  assert.equal(o.mode, "serve");
  assert.equal(o.timeout, 10);
  assert.equal(o.url, "http://127.0.0.1:{port}");
  const p = await freePort();
  assert.ok(p > 0 && p < 65536);
  assert.equal(withPort("npm start -- --port {port} --x {port}", 4321), "npm start -- --port 4321 --x 4321");
  assert.equal(withPort(null, 1), null);
  assert.equal(alive(process.pid), true);
  assert.equal(alive(-1), false);
});

test("serve starts the app once, reuses it, and stop ends it", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ui-app-"));
  fs.writeFileSync(path.join(dir, "server.js"), SERVER);
  const out = path.join(dir, "work", "ui");
  const o = { cwd: dir, url: "http://127.0.0.1:{port}", start: "node server.js {port}", out, timeout: 20 };
  const lines = [];
  try {
    assert.equal(await serve(o, (l) => lines.push(l)), 0);
    assert.match(lines.at(-1), /^APP: RUNNING http:\/\/127\.0\.0\.1:\d+$/);
    const a = readApp(out);
    assert.ok(a.pid > 0 && a.port > 0 && a.ours === true);
    assert.equal(a.url, `http://127.0.0.1:${a.port}`);
    assert.equal(await up(a.url + "/"), true);
    assert.ok(await runningApp(out));

    await serve(o, (l) => lines.push(l));
    assert.equal(lines.at(-1), `APP: RUNNING ${a.url}`, "the second serve reuses the same app");
    assert.equal(readApp(out).pid, a.pid);

    assert.equal(await stop({ out }, (l) => lines.push(l)), 0);
    assert.equal(lines.at(-1), "APP: STOPPED");
    assert.equal(readApp(out), null);
    let gone = false;
    for (let i = 0; i < 40 && !gone; i++) { gone = !(await up(a.url + "/")); if (!gone) await new Promise((r) => setTimeout(r, 100)); }
    assert.ok(gone, "the app no longer answers");
    await stop({ out }, (l) => lines.push(l));
    assert.equal(lines.at(-1), "APP: NONE");
  } finally {
    await stop({ out }, () => {});
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("serve: an app that exits before it is ready is skipped with its last line; no start command is skipped", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ui-app-"));
  const out = path.join(dir, "ui");
  const lines = [];
  try {
    await serve({ cwd: dir, url: "http://127.0.0.1:{port}", start: "node -e \"console.log('needs a database'); process.exit(3)\"", out, timeout: 20 }, (l) => lines.push(l));
    assert.equal(lines.at(-1), "APP: SKIPPED the app stopped before it was ready: needs a database");
    assert.equal(readApp(out), null);
    await serve({ cwd: dir, url: "http://127.0.0.1:9", out, timeout: 10 }, (l) => lines.push(l));
    assert.match(lines.at(-1), /^APP: SKIPPED the app is not running at http:\/\/127\.0\.0\.1:9\/ and the UI checks table has no Start command$/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("a stale app record is removed", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ui-app-"));
  try {
    fs.writeFileSync(path.join(dir, "app.json"), JSON.stringify({ version: 1, pid: 999999, url: "http://127.0.0.1:9", ours: true }));
    assert.equal(await runningApp(dir), null);
    assert.equal(fs.existsSync(path.join(dir, "app.json")), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("check-ui: --widths, --aria and the accessibility tree as text", () => {
  const o = checkArgs(["--cwd", "x", "--aria", "--widths", "1280, 99", "--name", "task-2"]);
  assert.equal(o.aria, true);
  assert.deepEqual(o.widths, [1280]);
  assert.equal(o.name, "task-2");
  const text = treeText({ role: "WebArea", name: "Orders", children: [{ role: "generic", children: [{ role: "heading", name: "Refunds" }, { role: "button", name: "Save" }] }, { role: "textbox", name: "Reason", value: "late" }] });
  assert.equal(text, '- WebArea "Orders"\n  - heading "Refunds"\n  - button "Save"\n  - textbox "Reason": late\n');
});
