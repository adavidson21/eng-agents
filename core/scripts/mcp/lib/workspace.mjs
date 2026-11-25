// Where things are: the workspace root, a work item's folder and repos.md, a repo's folder or worktree, and its
// repo guide (AGENTS.local.md, else AGENTS.md) with the Commands, UI checks and Regression tests tables.
import fs from 'node:fs';
import path from 'node:path';

export class ToolError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`);
    this.code = code;
  }
}

export function workspaceRoot(args) {
  const root = path.resolve(args.workspace || process.env.TANDEM_WORKSPACE || process.cwd());
  if (!fs.existsSync(root)) throw new ToolError('NOWORKSPACE', `${root} does not exist`);
  return root;
}

const NAME = /^[A-Za-z0-9][A-Za-z0-9._ -]*$/;

export function checkRepoName(repo) {
  if (!repo || typeof repo !== 'string' || !NAME.test(repo) || repo.includes('..')) {
    throw new ToolError('NOREPO', `"${repo}" is not a repo folder name (a folder directly inside the workspace root)`);
  }
}

// The item's folder in .work: an exact folder name, or the one folder that starts with "<id>-".
export function findWorkFolder(root, item) {
  if (!item) return null;
  const work = path.join(root, '.work');
  if (!fs.existsSync(work)) throw new ToolError('NOITEM', 'there is no .work folder in the workspace root');
  const names = fs.readdirSync(work, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
  if (names.includes(item)) return { name: item, dir: path.join(work, item), rel: `.work/${item}` };
  const hits = names.filter((n) => n.startsWith(`${item}-`));
  if (hits.length === 1) return { name: hits[0], dir: path.join(work, hits[0]), rel: `.work/${hits[0]}` };
  if (hits.length === 0) throw new ToolError('NOITEM', `no folder in .work for ${item}`);
  throw new ToolError('NOITEM', `more than one folder in .work starts with ${item}-: ${hits.join(', ')}`);
}

// Markdown table rows under a heading: a list of objects keyed by the header cells (lower case).
export function readTable(text, headingRx) {
  const out = [];
  let inSection = !headingRx;
  let header = null;
  for (const line of String(text || '').split(/\r?\n/)) {
    if (headingRx && /^\s*#{1,6}\s/.test(line)) {
      if (inSection && header) break;
      inSection = headingRx.test(line);
      header = null;
      continue;
    }
    if (!inSection) continue;
    const m = line.match(/^\s*\|(.*)\|\s*$/);
    if (!m) {
      if (header && line.trim() === '') continue;
      continue;
    }
    const cells = m[1].split('|').map((c) => c.trim());
    if (cells.every((c) => /^:?-+:?$/.test(c))) continue;
    if (!header) { header = cells.map((c) => c.toLowerCase()); continue; }
    const row = {};
    header.forEach((h, i) => { row[h] = clean(cells[i] || ''); });
    out.push(row);
  }
  return out;
}

// A table cell's value: backticks removed; template placeholders and TODO count as empty.
export function clean(value) {
  const v = String(value || '').replace(/`/g, '').trim();
  if (/^<.*>$/.test(v) || /^TODO/i.test(v)) return '';
  return v;
}

export function readReposMd(workFolder) {
  if (!workFolder) return [];
  const file = path.join(workFolder.dir, 'repos.md');
  if (!fs.existsSync(file)) return [];
  return readTable(fs.readFileSync(file, 'utf8'), null).filter((r) => r['repo folder']);
}

// The folder git, build and test commands run in: the repo row's Path (a worktree) when it has one.
export function resolveRepo(args) {
  const root = workspaceRoot(args);
  checkRepoName(args.repo);
  const repoFolder = path.join(root, args.repo);
  if (!fs.existsSync(repoFolder)) throw new ToolError('NOREPO', `no folder ${args.repo} in the workspace root`);
  const work = findWorkFolder(root, args.item);
  const row = readReposMd(work).find((r) => r['repo folder'] === args.repo) || null;
  let dir = repoFolder;
  let worktree = null;
  if (row && row.path) {
    const p = path.resolve(root, row.path);
    if (!p.startsWith(root + path.sep)) throw new ToolError('NOREPO', `repos.md Path for ${args.repo} is outside the workspace`);
    if (!fs.existsSync(p)) throw new ToolError('NOREPO', `repos.md says ${args.repo} is built in ${row.path}, but that folder is missing (run /resume)`);
    dir = p;
    worktree = row.path.replace(/\\/g, '/');
  }
  if (!fs.existsSync(path.join(dir, '.git'))) throw new ToolError('NOREPO', `${path.relative(root, dir) || dir} is not a git repo`);
  return {
    root,
    repo: args.repo,
    repoFolder,
    dir,
    worktree,
    work,
    row,
    expectedBranch: row ? row.branch || null : null,
    base: row ? row.base || null : null,
  };
}

// The repo guide is read from the repo folder (AGENTS.local.md is not committed, so a worktree may not have it).
export function readGuide(repoFolder) {
  for (const name of ['AGENTS.local.md', 'AGENTS.md']) {
    const file = path.join(repoFolder, name);
    if (fs.existsSync(file)) return { file, name, text: fs.readFileSync(file, 'utf8') };
  }
  return null;
}

export function requireGuide(ctx) {
  const g = readGuide(ctx.repoFolder);
  if (!g) throw new ToolError('NOGUIDE', `${ctx.repo} has no repo guide (AGENTS.local.md or AGENTS.md). Run /onboard-repo ${ctx.repo} first`);
  return g;
}

const COMMAND_KEYS = {
  build: /^build$/,
  unit: /^all unit tests$/,
  precommit: /^pre-?commit check/,
  oneTest: /^one test/,
  lint: /^lint$/,
  format: /^format check$/,
  playwright: /^playwright tests$/,
};

export function guideCommands(text) {
  const rows = readTable(text, /^\s*#{1,6}\s+Commands\s*$/i);
  const out = {};
  for (const r of rows) {
    const purpose = (r.purpose || '').toLowerCase();
    for (const [key, rx] of Object.entries(COMMAND_KEYS)) {
      if (rx.test(purpose) && r.command && !out[key]) out[key] = r.command;
    }
  }
  return out;
}

export function guideFieldTable(text, heading) {
  const rows = readTable(text, new RegExp(`^\\s*#{1,6}\\s+${heading}\\s*$`, 'i'));
  if (rows.length === 0) return null;
  const out = {};
  for (const r of rows) if (r.field) out[r.field.toLowerCase()] = r.value || '';
  return out;
}

export function guideStack(text) {
  const m = String(text || '').match(/^\s*Stack:\s*(.+)$/im);
  if (!m) return [];
  return m[1].replace(/`/g, '').split(',').map((s) => s.trim().toLowerCase()).filter((s) => s && !/^</.test(s));
}

// A command written from the workspace root names the repo folder ("api/src/Api.csproj"). When the repo is built
// in a worktree, point those paths at the worktree instead.
export function retarget(command, repo, worktree) {
  if (!worktree) return command;
  const esc = repo.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const rx = new RegExp(`(^|[\\s"'=(])(?:\\./)?${esc}(?=[/\\\\])`, 'g');
  return command.replace(rx, (_, pre) => `${pre}${worktree}`);
}

export function rel(root, p) {
  return path.relative(root, p).replace(/\\/g, '/') || '.';
}
