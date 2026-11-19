// UI check tests: the PNG reader, writer and diff, the argument and problem helpers, and (when Playwright and
// a browser are installed) a real run against a tiny app: before, then after with a changed page and a
// console error. Run: node --test "core/scripts/ui/test/*.test.mjs"
// The real run needs `playwright` resolvable from the folder in UI_TEST_PLAYWRIGHT_DIR; it is skipped otherwise.

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { decodePng, diffImages, encodePng } from "../png.mjs";
import { parseArgs, problemsOf, run, sameOrigin, slugOf } from "../check-ui.mjs";

const img = (w, h, rgba) => ({ width: w, height: h, data: Buffer.alloc(w * h * 4, 0).fill(Buffer.from(rgba)) });

test("png: encode then decode gives the same pixels", () => {
  const a = img(7, 5, [10, 200, 30, 255]);
  a.data[0] = 255;
  const b = decodePng(encodePng(a));
  assert.equal(b.width, 7);
  assert.equal(b.height, 5);
  assert.deepEqual(b.data, a.data);
});

test("png: not a PNG is refused", () => {
  assert.throws(() => decodePng(Buffer.from("hello world")), /not a PNG/);
});

test("diff: same image is 0%, one changed pixel of four is 25%, other size is 100%", () => {
  const a = img(2, 2, [0, 0, 0, 255]);
  assert.equal(diffImages(a, img(2, 2, [0, 0, 0, 255])).changedPct, 0);
  const b = img(2, 2, [0, 0, 0, 255]);
  b.data[0] = 255;
  const d = diffImages(a, b);
  assert.equal(d.changedPct, 25);
  assert.equal(d.image.data[0], 230);
  const s = diffImages(a, img(3, 2, [0, 0, 0, 255]));
  assert.equal(s.changedPct, 100);
  assert.equal(s.sizeChanged, true);
});

test("diff: small differences under the threshold do not count", () => {
  const a = img(2, 1, [100, 100, 100, 255]);
  assert.equal(diffImages(a, img(2, 1, [110, 100, 95, 255])).changedPct, 0);
});

test("args, slugs and origins", () => {
  const o = parseArgs(["--cwd", "x", "--url", "http://localhost:1", "--pages", "/, /orders/12?x=1 ,", "--timeout", "3", "--name", "after"]);
  assert.deepEqual(o.pages, ["/", "/orders/12?x=1"]);
  assert.equal(o.timeout, 10);
  assert.equal(o.name, "after");
  assert.equal(slugOf("/"), "home");
  assert.equal(slugOf("/orders/12?x=1"), "orders-12-x-1");
  assert.equal(sameOrigin("http://localhost:4200/a", "http://localhost:4200"), true);
  assert.equal(sameOrigin("https://cdn.example/a.js", "http://localhost:4200"), false);
});

test("problems: errors, console errors, failed requests and worse accessibility", () => {
  const p = problemsOf([
    { path: "/", width: 1280, status: 200, consoleErrors: [], failedRequests: [], a11y: { imagesNoAlt: 1 }, a11yBefore: { imagesNoAlt: 1 } },
    { path: "/a", width: 640, status: 404, consoleErrors: ["boom"], failedRequests: ["http://x/api (HTTP 500)"], a11y: { inputsNoLabel: 2 }, a11yBefore: { inputsNoLabel: 0 } },
    { path: "/b", width: 640, error: "Timeout" },
  ]);
  assert.deepEqual(p, ["/a at 640px: HTTP 404", "/a at 640px: console error: boom", "/a at 640px: request failed: http://x/api (HTTP 500)", "/a at 640px: 2 more inputs with no label", "/b at 640px: Timeout"]);
});

test("run: skipped with a reason when the app is not running and there is no start command", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ui-"));
  const lines = [];
  const code = await run({ cwd: dir, url: "http://127.0.0.1:9", out: path.join(dir, "ui"), name: "after", pages: ["/"], timeout: 10 }, (l) => lines.push(l));
  assert.equal(code, 0);
  assert.match(lines.at(-1), /^UI: SKIPPED /);
  const r = JSON.parse(fs.readFileSync(path.join(dir, "ui", "results-after.json"), "utf8"));
  assert.equal(r.verdict, "skipped");
});

const PW = process.env.UI_TEST_PLAYWRIGHT_DIR;
test("run: before, then after with a changed page and a console error", { skip: !PW && "set UI_TEST_PLAYWRIGHT_DIR to a folder with playwright installed" }, async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ui-app-"));
  fs.symlinkSync(path.join(PW, "node_modules"), path.join(dir, "node_modules"), "junction");
  fs.writeFileSync(path.join(dir, "package.json"), "{}");
  const port = 40000 + Math.floor(Math.random() * 20000);
  const server = (v) => `require("http").createServer((q, s) => { s.setHeader("content-type", "text/html");
    s.end(q.url === "/orders" ? ${v === 2 ? `"<h1 style='background:red'>Orders changed</h1><script>console.error('boom')</script>"` : `"<h1>Orders</h1>"`} : "<h1>Home</h1><button>Go</button>"); }).listen(${port});`;
  fs.writeFileSync(path.join(dir, "server.js"), server(1));
  const o = { cwd: dir, url: `http://127.0.0.1:${port}`, out: path.join(dir, "ui"), pages: ["/", "/orders"], start: "node server.js", timeout: 30 };
  const lines = [];
  assert.equal(await run({ ...o, name: "before" }, (l) => lines.push(l)), 0);
  assert.match(lines.at(-1), /^UI: PASS 2 pages at 2 widths$/);
  fs.writeFileSync(path.join(dir, "server.js"), server(2));
  assert.equal(await run({ ...o, name: "after", compare: "before" }, (l) => lines.push(l)), 1);
  assert.match(lines.at(-1), /^UI: FAIL 2 pages at 2 widths, 2 changed since before; 2 problems: \/orders at 1280px: console error: boom/);
  const r = JSON.parse(fs.readFileSync(path.join(dir, "ui", "results-after.json"), "utf8"));
  assert.deepEqual(r.changed, ["/orders at 1280px", "/orders at 640px"]);
  assert.ok(fs.existsSync(path.join(dir, "ui", "diff", "orders-1280.png")));
  assert.equal(r.pages.find((p) => p.path === "/").diff.changedPct, 0);
});
