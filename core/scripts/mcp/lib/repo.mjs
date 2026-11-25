// repo_* tools: git state for one repo of the workspace (its worktree when repos.md gives a Path).
// Reads only, except repo_commit, which stages exactly the files named and commits them.
import path from 'node:path';
import { git, lines } from './proc.mjs';
import { ToolError, resolveRepo, rel } from './workspace.mjs';

async function gitOk(dir, args, what) {
  const r = await git(dir, args);
  if (r.code !== 0) throw new ToolError('GIT', `${what} failed: ${(r.stderr || r.stdout).trim().split(/\r?\n/).slice(-3).join(' ')}`);
  return r.stdout;
}

async function verify(dir, ref) {
  const r = await git(dir, ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`]);
  return r.code === 0;
}

// The base: the argument, repos.md's Base, then origin/HEAD, origin/main, main, origin/master, master.
export async function resolveBase(ctx, given) {
  const wanted = given || ctx.base;
  if (wanted) return { base: wanted, resolved: await verify(ctx.dir, wanted), from: given ? 'argument' : 'repos.md' };
  const head = await git(ctx.dir, ['rev-parse', '--abbrev-ref', 'origin/HEAD']);
  if (head.code === 0 && head.stdout.trim() && head.stdout.trim() !== 'origin/HEAD') {
    return { base: head.stdout.trim(), resolved: true, from: 'origin/HEAD' };
  }
  for (const c of ['origin/main', 'main', 'origin/master', 'master']) {
    if (await verify(ctx.dir, c)) return { base: c, resolved: true, from: 'default' };
  }
  return { base: null, resolved: false, from: 'none' };
}

// git status --porcelain: [{ path, status }], status two letters (" M", "??", "D ", ...).
export async function statusEntries(dir) {
  const out = await gitOk(dir, ['status', '--porcelain=v1', '--untracked-files=all'], 'git status');
  return lines(out).map((l) => {
    let p = l.slice(3);
    if (p.includes(' -> ')) p = p.split(' -> ').pop();
    return { status: l.slice(0, 2), path: p.replace(/^"|"$/g, '') };
  });
}

export async function repoCheck(args) {
  const ctx = resolveRepo(args);
  const branch = (await gitOk(ctx.dir, ['rev-parse', '--abbrev-ref', 'HEAD'], 'reading the branch')).trim();
  const dirty = await statusEntries(ctx.dir);
  const b = await resolveBase(ctx, args.base);
  let ahead = null;
  let behind = null;
  if (b.resolved) {
    const r = await git(ctx.dir, ['rev-list', '--left-right', '--count', `${b.base}...HEAD`]);
    if (r.code === 0) [behind, ahead] = r.stdout.trim().split(/\s+/).map(Number);
  }
  const problems = [];
  const branchOk = ctx.expectedBranch ? branch === ctx.expectedBranch : null;
  if (branchOk === false) problems.push(`on ${branch}, but repos.md says ${ctx.expectedBranch}`);
  if (dirty.length) problems.push(`${dirty.length} uncommitted change(s)`);
  if (b.base && !b.resolved) problems.push(`base ${b.base} not found (fetch it, or check repos.md)`);
  if (!b.base) problems.push('no base branch found');
  return {
    repo: ctx.repo,
    workingIn: rel(ctx.root, ctx.dir),
    worktree: ctx.worktree,
    branch,
    expectedBranch: ctx.expectedBranch,
    branchOk,
    clean: dirty.length === 0,
    uncommitted: dirty.slice(0, 200),
    base: b.base,
    baseFound: b.resolved,
    baseFrom: b.from,
    ahead,
    behind,
    ok: problems.length === 0,
    problems,
  };
}

export async function repoChanges(args) {
  const ctx = resolveRepo(args);
  const b = await resolveBase(ctx, args.base);
  if (!b.resolved) throw new ToolError('GIT', b.base ? `base ${b.base} not found` : 'no base branch found; pass base');
  const range = `${b.base}...HEAD`;
  const log = await gitOk(ctx.dir, ['log', '--format=%h%x09%s', '-n', '100', `${b.base}..HEAD`], 'git log');
  const numstat = await gitOk(ctx.dir, ['diff', '--numstat', range], 'git diff --numstat');
  const names = await gitOk(ctx.dir, ['diff', '--name-status', range], 'git diff --name-status');
  const status = new Map();
  for (const l of lines(names)) {
    const parts = l.split('\t');
    status.set(parts[parts.length - 1], parts[0].charAt(0));
  }
  let insertions = 0;
  let deletions = 0;
  const files = lines(numstat).map((l) => {
    const [a, d, ...p] = l.split('\t');
    let file = p.join('\t');
    if (file.includes(' => ')) file = file.replace(/\{([^}]*) => ([^}]*)\}/, '$2').replace(/^.* => /, '');
    const added = a === '-' ? null : Number(a);
    const removed = d === '-' ? null : Number(d);
    insertions += added || 0;
    deletions += removed || 0;
    return { path: file, status: status.get(file) || 'M', added, removed };
  });
  const result = {
    repo: ctx.repo,
    workingIn: rel(ctx.root, ctx.dir),
    base: b.base,
    commits: lines(log).map((l) => { const [sha, ...s] = l.split('\t'); return { sha, subject: s.join('\t') }; }),
    stat: { files: files.length, insertions, deletions },
    files,
    uncommitted: (await statusEntries(ctx.dir)).slice(0, 200),
  };
  if (args.file) {
    const r = await git(ctx.dir, ['diff', range, '--', args.file]);
    const text = r.stdout || '';
    result.diff = { file: args.file, truncated: text.length > 60000, text: text.slice(0, 60000) };
  }
  return result;
}

const NEEDS_YOU = [
  /(^|\/)package-lock\.json$/, /(^|\/)npm-shrinkwrap\.json$/, /(^|\/)yarn\.lock$/, /(^|\/)pnpm-lock\.yaml$/,
  /(^|\/)packages\.lock\.json$/, /\.lock$/, /\.designer\.cs$/i, /\.g\.cs$/i, /ModelSnapshot\.cs$/,
  /(^|\/)(dist|bin|obj|generated)\//i, /\.min\.(js|css)$/,
];

// Would merging the base in conflict? Uses git merge-tree, so nothing is checked out or changed.
export async function repoMergeCheck(args) {
  const ctx = resolveRepo(args);
  const b = await resolveBase(ctx, args.base);
  let fetched = null;
  if (args.fetch !== false && b.base && b.base.startsWith('origin/')) {
    const r = await git(ctx.dir, ['fetch', 'origin', b.base.slice('origin/'.length)], { timeoutMs: 180000 });
    fetched = r.code === 0 ? 'ok' : `failed: ${(r.stderr || '').trim().split(/\r?\n/).pop()}`;
  }
  if (!b.base) throw new ToolError('GIT', 'no base branch found; pass base');
  if (!(await verify(ctx.dir, b.base))) throw new ToolError('GIT', `base ${b.base} not found`);
  const behindOut = await gitOk(ctx.dir, ['rev-list', '--count', `HEAD..${b.base}`], 'git rev-list');
  const behind = Number(behindOut.trim());
  if (behind === 0) return { repo: ctx.repo, base: b.base, fetched, behind: 0, upToDate: true, clean: true, conflicts: [], needsYou: [] };
  const r = await git(ctx.dir, ['merge-tree', '--write-tree', '--name-only', '--no-messages', 'HEAD', b.base]);
  if (r.code !== 0 && r.code !== 1) {
    const msg = (r.stderr || r.stdout).trim();
    if (/unknown option|usage: git merge-tree/i.test(msg)) throw new ToolError('GIT', 'this check needs git 2.38 or later');
    throw new ToolError('GIT', `git merge-tree failed: ${msg.split(/\r?\n/).slice(-2).join(' ')}`);
  }
  const files = lines(r.stdout).slice(1);
  const needsYou = files.filter((f) => NEEDS_YOU.some((rx) => rx.test(f)));
  return {
    repo: ctx.repo,
    base: b.base,
    fetched,
    behind,
    upToDate: false,
    clean: r.code === 0,
    conflicts: files,
    needsYou,
    note: r.code === 0
      ? 'Merges cleanly. Merge it with git as the command says.'
      : 'Conflicts. Lock and generated files (needsYou) are never resolved by hand; the rest only when both sides can be kept with no decision about behavior.',
  };
}

export async function repoCommit(args) {
  const ctx = resolveRepo(args);
  const message = String(args.message || '').trim();
  if (!message) throw new ToolError('REFUSED', 'message is empty');
  if (/[\r\n]/.test(message)) throw new ToolError('REFUSED', 'message must be one line');
  if (message.length > 120) throw new ToolError('REFUSED', 'message is over 120 characters; keep it a short summary');
  const files = Array.isArray(args.files) ? args.files.map((f) => String(f).replace(/\\/g, '/').trim()).filter(Boolean) : [];
  if (files.length === 0) throw new ToolError('REFUSED', 'name the files to commit');
  for (const f of files) {
    const full = path.resolve(ctx.dir, f);
    if (path.isAbsolute(f) || f.split('/').includes('..') || !full.startsWith(ctx.dir + path.sep)) {
      throw new ToolError('REFUSED', `${f} is not a path inside the repo (use paths relative to ${rel(ctx.root, ctx.dir)})`);
    }
  }
  const branch = (await gitOk(ctx.dir, ['rev-parse', '--abbrev-ref', 'HEAD'], 'reading the branch')).trim();
  if (ctx.expectedBranch && branch !== ctx.expectedBranch) throw new ToolError('REFUSED', `on ${branch}, but repos.md says ${ctx.expectedBranch}`);
  if (['main', 'master', 'develop'].includes(branch)) throw new ToolError('REFUSED', `on ${branch}; commits go on the work item's branch`);
  const staged = lines(await gitOk(ctx.dir, ['diff', '--cached', '--name-only'], 'git diff --cached'));
  const extra = staged.filter((s) => !files.includes(s));
  if (extra.length) throw new ToolError('REFUSED', `other files are already staged: ${extra.join(', ')}`);
  const changed = new Set((await statusEntries(ctx.dir)).map((e) => e.path));
  const unchanged = files.filter((f) => !changed.has(f));
  if (unchanged.length) throw new ToolError('REFUSED', `no changes in: ${unchanged.join(', ')}`);
  await gitOk(ctx.dir, ['add', '--', ...files], 'git add');
  const c = await git(ctx.dir, ['commit', '-m', message]);
  if (c.code !== 0) {
    await git(ctx.dir, ['reset', '-q', '--', ...files]);
    throw new ToolError('GIT', `git commit failed (files unstaged again): ${(c.stderr || c.stdout).trim().split(/\r?\n/).slice(-3).join(' ')}`);
  }
  const sha = (await gitOk(ctx.dir, ['rev-parse', 'HEAD'], 'git rev-parse')).trim();
  return {
    repo: ctx.repo,
    branch,
    commit: sha.slice(0, 7),
    sha,
    message,
    files,
    stillUncommitted: (await statusEntries(ctx.dir)).map((e) => e.path).slice(0, 200),
  };
}
