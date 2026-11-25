// ui_* and tests_* tools. The first four call the existing scripts (Start-UiApp, Stop-UiApp, Test-Ui,
// Test-Suite) with the right arguments and return their result files as JSON. tests_detect, tests_ensure_env and
// tests_scaffold set up Playwright in a repo (Angular first) and write test skeletons for the model to fill in.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { run, runShell, psExe, lines, tail } from './proc.mjs';
import { ToolError, resolveRepo, requireGuide, readGuide, guideFieldTable, findWorkFolder, workspaceRoot, rel } from './workspace.mjs';

const SCRIPTS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = /^[a-z0-9-]{1,30}$/;

async function runScript(script, params, cwd, timeoutMs) {
  const file = path.join(SCRIPTS, script);
  if (!fs.existsSync(file)) throw new ToolError('NOSCRIPT', `${script} is not installed next to the Tandem tools`);
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', file];
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null || v === false || v === '') continue;
    args.push(`-${k}`);
    if (v !== true) args.push(String(v));
  }
  const r = await run(psExe(), args, { cwd, timeoutMs });
  if (r.notFound) throw new ToolError('NOPS', `${psExe()} was not found`);
  const all = lines(`${r.stdout}`);
  return { last: all.length ? all[all.length - 1].trim() : '', output: tail(`${r.stdout}\n${r.stderr}`, 20), timedOut: r.timedOut };
}

function itemRepo(args) {
  if (!args.item) throw new ToolError('NOITEM', 'item is required');
  const ctx = resolveRepo(args);
  const g = requireGuide(ctx);
  return { ctx, guide: rel(ctx.root, g.file), repoArg: rel(ctx.root, ctx.dir) };
}

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')); } catch { return null; }
}

function verdict(last, prefix) {
  const m = last.match(new RegExp(`^${prefix}:\\s*(\\w+)\\s*(.*)$`));
  return m ? { status: m[1], detail: m[2] } : { status: 'UNKNOWN', detail: last };
}

export async function uiAppStart(args) {
  const { ctx, guide, repoArg } = itemRepo(args);
  const r = await runScript('ui/Start-UiApp.ps1', { WorkFolder: ctx.work.rel, Repo: repoArg, Guide: guide }, ctx.root, 300000);
  const v = verdict(r.last, 'APP');
  return { repo: ctx.repo, status: v.status, url: v.status === 'RUNNING' ? v.detail : null, why: v.status === 'RUNNING' ? null : v.detail, last: r.last };
}

export async function uiAppStop(args) {
  const root = workspaceRoot(args);
  const work = findWorkFolder(root, args.item);
  if (!work) throw new ToolError('NOITEM', 'item is required');
  const r = await runScript('ui/Stop-UiApp.ps1', { WorkFolder: work.rel }, root, 60000);
  const v = verdict(r.last, 'APP');
  return { status: v.status, detail: v.detail, last: r.last };
}

export async function uiCheck(args) {
  const name = args.name || 'after';
  if (!NAME.test(name)) throw new ToolError('REFUSED', 'name: lower case letters, digits and dashes, up to 30');
  const { ctx, guide, repoArg } = itemRepo(args);
  const r = await runScript('ui/Test-Ui.ps1', {
    WorkFolder: ctx.work.rel, Repo: repoArg, Guide: guide, Name: name, Base: args.base,
    Quick: !!args.quick, Pages: Array.isArray(args.pages) ? args.pages.join(',') : args.pages, Uncommitted: !!args.uncommitted,
  }, ctx.root, 900000);
  const v = verdict(r.last, 'UI');
  const out = path.join(ctx.work.dir, 'ui');
  const results = readJson(path.join(out, `results-${name}.json`));
  const shotDir = path.join(out, name);
  const files = fs.existsSync(shotDir) ? fs.readdirSync(shotDir) : [];
  return {
    repo: ctx.repo,
    status: v.status,
    detail: v.detail,
    problems: results && Array.isArray(results.problems) ? results.problems.slice(0, 40) : [],
    results: results ? rel(ctx.root, path.join(out, `results-${name}.json`)) : null,
    pageText: files.filter((f) => /^aria-.*\.txt$/.test(f)).map((f) => rel(ctx.root, path.join(shotDir, f))),
    screenshots: files.filter((f) => f.endsWith('.png')).map((f) => rel(ctx.root, path.join(shotDir, f))),
    last: r.last,
    output: v.status === 'UNKNOWN' ? r.output : undefined,
  };
}

export async function testsSuite(args) {
  const name = args.name || 'after';
  if (!NAME.test(name)) throw new ToolError('REFUSED', 'name: lower case letters, digits and dashes, up to 30');
  const { ctx, guide, repoArg } = itemRepo(args);
  const r = await runScript('tests/Test-Suite.ps1', {
    WorkFolder: ctx.work.rel, Repo: repoArg, Guide: guide, Name: name, Base: args.base,
  }, ctx.root, 1500000);
  const v = verdict(r.last, 'Tests');
  const file = path.join(ctx.work.dir, 'tests', `results-${name}.json`);
  const results = readJson(file);
  return {
    repo: ctx.repo,
    status: v.status,
    detail: v.detail,
    results: results ? rel(ctx.root, file) : null,
    summary: results || null,
    last: r.last,
    output: v.status === 'UNKNOWN' ? r.output : undefined,
  };
}

// ---------------------------------------------------------------- Playwright setup (Angular first)

function readPkg(dir) {
  const p = readJson(path.join(dir, 'package.json'));
  if (!p) return null;
  return { pkg: p, deps: { ...(p.dependencies || {}), ...(p.devDependencies || {}) } };
}

function packageManager(dir) {
  if (fs.existsSync(path.join(dir, 'pnpm-lock.yaml'))) return 'pnpm';
  if (fs.existsSync(path.join(dir, 'yarn.lock'))) return 'yarn';
  return 'npm';
}

function findConfig(dir) {
  for (const n of ['playwright.config.ts', 'playwright.config.js', 'playwright.config.mjs', 'playwright.config.cjs']) {
    if (fs.existsSync(path.join(dir, n))) return n;
  }
  return null;
}

function walk(dir, test, max = 400, depth = 0, out = []) {
  if (depth > 8 || out.length >= max || !fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (out.length >= max) break;
    if (e.name.startsWith('.') || ['node_modules', 'dist', 'bin', 'obj', 'coverage'].includes(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, test, max, depth + 1, out);
    else if (test(e.name)) out.push(p);
  }
  return out;
}

function browsersInstalled() {
  const dirs = [];
  if (process.env.PLAYWRIGHT_BROWSERS_PATH && process.env.PLAYWRIGHT_BROWSERS_PATH !== '0') dirs.push(process.env.PLAYWRIGHT_BROWSERS_PATH);
  if (process.platform === 'win32') dirs.push(path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'ms-playwright'));
  else if (process.platform === 'darwin') dirs.push(path.join(os.homedir(), 'Library', 'Caches', 'ms-playwright'));
  else dirs.push(path.join(os.homedir(), '.cache', 'ms-playwright'));
  return dirs.some((d) => fs.existsSync(d) && fs.readdirSync(d).some((n) => /^chromium/.test(n)));
}

function angularInfo(dir) {
  const a = readJson(path.join(dir, 'angular.json'));
  if (!a || !a.projects) return null;
  const names = Object.keys(a.projects);
  const apps = names.filter((n) => (a.projects[n].projectType || 'application') === 'application');
  const project = a.defaultProject && a.projects[a.defaultProject] ? a.defaultProject : apps[0] || names[0];
  const serve = (((a.projects[project] || {}).architect || (a.projects[project] || {}).targets || {}).serve) || {};
  const port = (serve.options && Number(serve.options.port)) || 4200;
  return { project, apps, port, sourceRoot: (a.projects[project] || {}).sourceRoot || 'src' };
}

function routes(dir, sourceRoot) {
  const files = walk(path.join(dir, sourceRoot || 'src'), (n) => /(routes|routing[\w.-]*)\.ts$/.test(n) && !n.endsWith('.spec.ts'), 100);
  const found = new Set();
  for (const f of files) {
    const text = fs.readFileSync(f, 'utf8');
    for (const m of text.matchAll(/path:\s*['"`]([^'"`]*)['"`]/g)) if (m[1] !== '**') found.add(`/${m[1]}`.replace(/\/+/g, '/'));
  }
  return [...found].slice(0, 60);
}

function testDir(dir, config) {
  if (config) {
    const m = fs.readFileSync(path.join(dir, config), 'utf8').match(/testDir:\s*['"`]\.?\/?([^'"`]+)['"`]/);
    if (m) return m[1].replace(/\/$/, '');
  }
  for (const d of ['e2e', 'tests/e2e', 'playwright']) if (fs.existsSync(path.join(dir, d))) return d;
  return null;
}

function detectIn(ctx) {
  const dir = ctx.dir;
  const p = readPkg(dir);
  const config = findConfig(dir);
  const ng = angularInfo(dir);
  const td = testDir(dir, config);
  const specs = td ? walk(path.join(dir, td), (n) => /\.(spec|test|e2e)\.[cm]?[jt]s$/.test(n), 30) : [];
  const g = readGuide(ctx.repoFolder);
  const deps = p ? p.deps : {};
  const unitRunner = deps.vitest ? 'vitest' : deps.jest || deps['jest-preset-angular'] ? 'jest' : deps.karma ? 'karma' : null;
  const out = {
    repo: ctx.repo,
    workingIn: rel(ctx.root, dir),
    node: !!p,
    packageManager: p ? packageManager(dir) : null,
    angular: deps['@angular/core'] || null,
    angularProject: ng,
    unitRunner,
    playwright: deps['@playwright/test'] || null,
    playwrightConfig: config,
    browsers: browsersInstalled(),
    testDir: td,
    existingTests: specs.map((s) => path.relative(dir, s).replace(/\\/g, '/')),
    pattern: specs.length ? path.relative(dir, specs[0]).replace(/\\/g, '/') : null,
    routes: ng ? routes(dir, ng.sourceRoot) : [],
    guide: g ? { file: g.name, uiChecks: !!guideFieldTable(g.text, 'UI checks'), regressionTests: guideFieldTable(g.text, 'Regression tests') } : null,
  };
  out.missing = [];
  if (!out.node) out.missing.push('package.json');
  if (out.node && !out.playwright) out.missing.push('@playwright/test');
  if (!out.playwrightConfig) out.missing.push('playwright.config');
  if (!out.browsers) out.missing.push('browsers');
  if (out.guide && !out.guide.regressionTests) out.missing.push('repo guide ## Regression tests table');
  return out;
}

export async function testsDetect(args) {
  return detectIn(resolveRepo(args));
}

function configText(folder, serveCommand, port) {
  return `import { defineConfig, devices } from '@playwright/test';

// Written by Tandem (tests_ensure_env). Every test mocks its API calls with page.route; nothing here calls a real
// environment. E2E_PORT changes the port the app is served on for the tests.
const port = Number(process.env.E2E_PORT ?? ${port});

export default defineConfig({
  testDir: './${folder}',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: 'list',
  use: {
    baseURL: \`http://localhost:\${port}\`,
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: \`${serveCommand} --port \${port}\`,
    url: \`http://localhost:\${port}\`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
});
`;
}

const FOLDER = /^[A-Za-z0-9][A-Za-z0-9_\-/]{0,60}$/;

export async function testsEnsureEnv(args) {
  const ctx = resolveRepo(args);
  const before = detectIn(ctx);
  if (!before.node) throw new ToolError('REFUSED', `${ctx.repo} has no package.json; Playwright setup is for Node front ends`);
  const folder = String(args.folder || before.testDir || 'e2e').replace(/\\/g, '/').replace(/\/$/, '');
  if (!FOLDER.test(folder) || folder.split('/').includes('..')) throw new ToolError('REFUSED', `folder "${folder}" is not a simple relative path`);
  const install = args.install !== false;
  const steps = [];
  const pm = before.packageManager;

  if (before.playwright) steps.push({ step: '@playwright/test', status: 'already there', detail: before.playwright });
  else if (!install) steps.push({ step: '@playwright/test', status: 'needed', detail: 'install is off' });
  else {
    const cmd = pm === 'npm' ? 'npm install --save-dev @playwright/test' : `${pm} add -D @playwright/test`;
    const r = await runShell(cmd, { cwd: ctx.dir, timeoutMs: 900000 });
    steps.push({ step: '@playwright/test', status: r.code === 0 ? 'installed' : 'failed', detail: r.code === 0 ? cmd : tail(`${r.stdout}\n${r.stderr}`, 8).join('\n') });
  }

  if (before.playwrightConfig) steps.push({ step: 'playwright.config', status: 'already there', detail: before.playwrightConfig });
  else {
    const ng = before.angularProject;
    const p = readPkg(ctx.dir);
    let serve;
    let port = 4200;
    if (ng) {
      serve = ng.apps.length > 1 ? `npx ng serve --project ${ng.project}` : 'npx ng serve';
      port = ng.port;
    } else if (p && p.pkg.scripts && p.pkg.scripts.start) {
      serve = pm === 'npm' ? 'npm start --' : `${pm} start`;
      port = 3000;
    } else {
      throw new ToolError('REFUSED', 'no angular.json and no start script, so there is no way to serve the app for the tests; write playwright.config.ts by hand');
    }
    fs.writeFileSync(path.join(ctx.dir, 'playwright.config.ts'), configText(folder, serve, port), 'utf8');
    steps.push({ step: 'playwright.config', status: 'written', detail: `playwright.config.ts (testDir ./${folder}, serves with "${serve}" on ${port})` });
  }

  const folderPath = path.join(ctx.dir, folder);
  if (fs.existsSync(folderPath)) steps.push({ step: 'test folder', status: 'already there', detail: folder });
  else { fs.mkdirSync(folderPath, { recursive: true }); steps.push({ step: 'test folder', status: 'made', detail: `${folder} (empty folders are not committed; the first test file makes it real)` }); }

  if (before.browsers) steps.push({ step: 'browsers', status: 'already there', detail: 'chromium' });
  else if (!install || args.browsers === false) steps.push({ step: 'browsers', status: 'needed', detail: 'run: npx playwright install chromium' });
  else {
    const r = await runShell('npx playwright install chromium', { cwd: ctx.dir, timeoutMs: 900000 });
    steps.push({
      step: 'browsers',
      status: r.code === 0 ? 'installed' : 'failed',
      detail: r.code === 0 ? 'chromium' : `${tail(`${r.stdout}\n${r.stderr}`, 6).join('\n')}\nIf downloads are blocked, set PLAYWRIGHT_DOWNLOAD_HOST to an internal mirror or install the browser by hand.`,
    });
  }

  return {
    repo: ctx.repo,
    ok: steps.every((s) => s.status !== 'failed' && s.status !== 'needed'),
    steps,
    regressionTests: { Command: 'npx playwright test', Runner: 'playwright', Folder: `${folder}/` },
    next: before.guide && before.guide.regressionTests
      ? 'The repo guide already has a ## Regression tests table.'
      : 'Add a ## Regression tests table to the repo guide with the regressionTests values above.',
  };
}

const SLUG = /^[a-z0-9][a-z0-9-]{0,60}$/;
const q = (s) => String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'");

export async function testsScaffold(args) {
  const ctx = resolveRepo(args);
  const d = detectIn(ctx);
  if (!SLUG.test(args.file || '')) throw new ToolError('REFUSED', 'file: a short slug, for example refund-reason (".spec.ts" is added)');
  const route = String(args.route || '/');
  if (!route.startsWith('/')) throw new ToolError('REFUSED', 'route must start with /');
  const criteria = Array.isArray(args.criteria) ? args.criteria : [];
  if (criteria.length === 0) throw new ToolError('REFUSED', 'criteria: at least one { id: "AC-1", title }');
  for (const c of criteria) {
    if (!/^AC-\d+$/.test(c.id || '')) throw new ToolError('REFUSED', `criterion id "${c.id}" must look like AC-1`);
    if (!c.title || /[\r\n]/.test(c.title)) throw new ToolError('REFUSED', `criterion ${c.id} needs a one-line title`);
  }
  const folder = String(args.folder || d.testDir || 'e2e').replace(/\\/g, '/').replace(/\/$/, '');
  if (!FOLDER.test(folder) || folder.split('/').includes('..')) throw new ToolError('REFUSED', `folder "${folder}" is not a simple relative path`);
  const file = path.join(ctx.dir, folder, `${args.file}.spec.ts`);
  if (fs.existsSync(file)) throw new ToolError('EXISTS', `${path.relative(ctx.dir, file).replace(/\\/g, '/')} already exists; edit it instead`);
  const api = String(args.api || '**/api/**');
  const tests = criteria.map((c) => `
  test('${q(c.title)} [${c.id}]', async ({ page }) => {
    // Act: what the person does. Assert: what the person sees (getByRole, getByLabel, getByText).
    expect(false, 'Write this test: ${q(c.title)}').toBe(true);
  });
`).join('');
  const text = `import { test, expect } from '@playwright/test';

// Scaffolded by Tandem for ${route}. Fill in each test. Every API call stays mocked with page.route.
test.describe('${q(args.file.replace(/-/g, ' '))}', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('${q(api)}', async (route) => {
      // Replace with the responses this page needs.
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
    });
    await page.goto('${q(route)}');
  });
${tests}});
`;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text, 'utf8');
  return {
    repo: ctx.repo,
    file: path.relative(ctx.dir, file).replace(/\\/g, '/'),
    tests: criteria.map((c) => `${c.title} [${c.id}]`),
    pattern: d.pattern,
    next: `Replace each expect(false, ...) line with real steps${d.pattern ? `, in the style of ${d.pattern}` : ''}. The tests fail until you do.`,
  };
}
