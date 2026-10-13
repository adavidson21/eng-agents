#!/usr/bin/env node
// Copies the shared themes from Prioritizer (themes.css, the styling source of truth) into
// dashboard.template.html: the CSS block, the theme menu and its swatches, and the list the page
// checks before first paint. Run it when Prioritizer's themes change, and bump the dashboard version.
//
//   node sync-themes.mjs                  copy from Prioritizer's main branch on GitHub
//   node sync-themes.mjs --from <path>    copy from a local themes.css (or another URL)
//   node sync-themes.mjs --check          change nothing; exit 1 if the template has drifted
//
// No dependencies beyond Node 18+.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATE = path.join(HERE, "dashboard.template.html");
const DEFAULT_FROM = "https://raw.githubusercontent.com/adavidson21/prioritizer/main/themes.css";

const args = process.argv.slice(2);
let from = DEFAULT_FROM;
let check = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--from" && args[i + 1]) from = args[++i];
  else if (args[i] === "--check") check = true;
  else if (args[i] === "--help" || args[i] === "-h") {
    console.log("Usage: node sync-themes.mjs [--from <path or URL to themes.css>] [--check]");
    process.exit(0);
  } else fail(`Unknown option: ${args[i]}`);
}

function fail(msg) {
  console.error(`sync-themes: ${msg}`);
  process.exit(2);
}

async function readSource(src) {
  if (/^https?:\/\//i.test(src)) {
    const r = await fetch(src, { cache: "no-store" });
    if (!r.ok) fail(`${src} answered HTTP ${r.status}`);
    return r.text();
  }
  return fs.readFileSync(path.resolve(src), "utf8");
}

const css = (await readSource(from)).replace(/\r\n/g, "\n");

// "themes: slate=Slate, graphite=Graphite, ..." in the header comment names the themes in menu order.
const namesLine = /^\s*themes:\s*(.+)$/m.exec(css);
if (!namesLine) fail(`No "themes:" line in ${from}.`);
const themes = namesLine[1].split(",").map((p) => p.trim().split("=")).map(([k, v]) => [k.trim(), (v || k).trim()]);
if (!themes.length || themes.some(([k]) => !/^[a-z][a-z0-9-]*$/.test(k))) fail(`Bad "themes:" line in ${from}.`);
for (const [k] of themes) if (!new RegExp(`data-theme=["']?${k}["']?\\]`).test(css)) fail(`themes.css names "${k}" but has no :root[data-theme=${k}] block.`);

// Menu swatches: each theme's bg and accent.
const swatch = {};
for (const [k] of themes) {
  const m = new RegExp(`data-theme=["']?${k}["']?\\]\\s*\\{([^}]*)\\}`).exec(css);
  const v = (n) => (new RegExp(`--${n}:\\s*(#[0-9a-fA-F]{3,8})`).exec(m ? m[1] : "") || [])[1];
  if (!v("bg") || !v("accent")) fail(`Theme "${k}" needs --bg and --accent as hex colors.`);
  swatch[k] = [v("bg"), v("accent")];
}

// Everything after the header comment is the CSS to copy.
const body = css.replace(/^\s*\/\*[\s\S]*?\*\/\s*/, "").trim();

const ascii = (s) => s.replace(/[^\x20-\x7e]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
const blocks = {
  css: `/* themes:begin  Copied from Prioritizer's themes.css by sync-themes.mjs. Do not edit here: change
   themes.css in Prioritizer, then run node sync-themes.mjs. */
${body}
/* themes:end */`,
  names: `/*theme-names*/${JSON.stringify(themes.map(([k]) => k))}/*/theme-names*/`,
  menu: `/*theme-menu*/${ascii(JSON.stringify([["system", "System"], ...themes]))}/*/theme-menu*/`,
  swatch: `/*theme-swatch*/${JSON.stringify(swatch)}/*/theme-swatch*/`,
};
const patterns = {
  css: /\/\* themes:begin[\s\S]*?\/\* themes:end \*\//,
  names: /\/\*theme-names\*\/[\s\S]*?\/\*\/theme-names\*\//,
  menu: /\/\*theme-menu\*\/[\s\S]*?\/\*\/theme-menu\*\//,
  swatch: /\/\*theme-swatch\*\/[\s\S]*?\/\*\/theme-swatch\*\//,
};

const tpl = fs.readFileSync(TEMPLATE, "utf8");
let out = tpl;
for (const k of Object.keys(blocks)) {
  if (!patterns[k].test(out)) fail(`dashboard.template.html has no ${k} markers.`);
  out = out.replace(patterns[k], () => blocks[k]);
}

if (check) {
  if (out !== tpl) {
    console.error(`Dashboard themes differ from ${from}. Run: node ${path.relative(process.cwd(), fileURLToPath(import.meta.url))}`);
    process.exit(1);
  }
  console.log(`Dashboard themes match ${from} (${themes.length} themes).`);
} else if (out === tpl) {
  console.log(`Already in sync with ${from} (${themes.length} themes).`);
} else {
  fs.writeFileSync(TEMPLATE, out);
  console.log(`Updated dashboard.template.html from ${from}: ${themes.map(([, v]) => v).join(", ")}.`);
  console.log("Bump core/scripts/dashboard/VERSION and add a CHANGELOG line.");
}
