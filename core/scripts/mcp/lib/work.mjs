// work_* tools: the .work bookkeeping that Workshop and the stats scripts read, written by code so it is the same
// every time and only says what really ran (progress entries, task checkboxes, review.md and pr.md result tables),
// plus work_lint, which checks the files a command wrote against their templates and Workshop's .work contract.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { git, lines } from './proc.mjs';
import { ToolError, workspaceRoot, findWorkFolder, readReposMd, rel } from './workspace.mjs';

const TEMPLATES = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'templates');
const LOG = /^[a-z0-9][a-z0-9-]{0,39}$/;

function item(args) {
  const root = workspaceRoot(args);
  if (!args.item) throw new ToolError('NOITEM', 'item is required');
  return { root, work: findWorkFolder(root, args.item) };
}

function read(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
}

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// A log written by checks_run (save): its command, last lines and exit code.
function readLog(work, name) {
  if (!LOG.test(name || '')) throw new ToolError('REFUSED', `log "${name}" is not a log name`);
  const file = path.join(work.dir, 'checks', `${name}.log`);
  const text = read(file);
  if (text === null) throw new ToolError('NOLOG', `no log ${name} in .work/${work.name}/checks (save it with checks_run first)`);
  const all = text.replace(/\r\n/g, '\n').split('\n');
  while (all.length && all[all.length - 1] === '') all.pop();
  const exitLine = all[all.length - 1] || '';
  const m = exitLine.match(/^exit (-?\d+)( \(timed out\))?$/);
  const body = m ? all.slice(1, -1) : all.slice(1);
  return {
    command: (all[0] || '').replace(/^\$ /, ''),
    exit: m ? Number(m[1]) : null,
    timedOut: !!(m && m[2]),
    lastLines: body.filter((l) => l.trim() !== '').slice(-20),
  };
}

function block(lines_) {
  return ['  ```', ...lines_.map((l) => `  ${l.replace(/```/g, "'''")}`), '  ```'];
}

function one(s, what) {
  const v = String(s || '').replace(/\s+/g, ' ').trim();
  if (!v) throw new ToolError('REFUSED', `${what} is empty`);
  return v;
}

export async function workProgressAdd(args) {
  const { work } = item(args);
  const command = String(args.command || '').replace(/^\//, '');
  if (!/^[a-z][a-z-]*( .+)?$/.test(command)) throw new ToolError('REFUSED', 'command: the command name, for example do-task or review');
  const agent = args.agent ? one(args.agent, 'agent') : null;
  const out = ['', `## ${today()} | /${command.split(' ')[0]}${agent ? ` | ${agent}` : ''}`, ''];
  out.push(`- Did: ${one(args.did, 'did')}`);
  const files = Array.isArray(args.files) ? args.files.filter(Boolean) : [];
  out.push(`- Files changed: ${files.length ? files.map((f) => `\`${f}\``).join(', ') : 'none'}`);

  let verify = null;
  if (args.outputLog) {
    const log = readLog(work, args.outputLog);
    const actual = log.timedOut ? 'FAIL' : log.exit === 0 ? 'PASS' : 'FAIL';
    if (args.verifyResult && args.verifyResult !== actual) {
      throw new ToolError('REFUSED', `verifyResult is ${args.verifyResult}, but log ${args.outputLog} ended with exit ${log.exit}${log.timedOut ? ' (timed out)' : ''}`);
    }
    verify = { command: log.command, result: actual, lines: log.lastLines };
  } else if (args.verifyCommand) {
    const result = args.verifyResult || 'not run';
    if (result === 'PASS') throw new ToolError('REFUSED', 'a PASS needs outputLog (a run saved with checks_run), so the output is the real one');
    verify = { command: one(args.verifyCommand, 'verifyCommand'), result, lines: [] };
  }
  if (verify) {
    out.push(`- Verify: \`${verify.command}\` -> ${verify.result}`);
    if (verify.lines.length) out.push('- Output (last lines):', ...block(verify.lines));
  }
  for (const [key, label] of [['redLog', 'Red run'], ['greenLog', 'Green run']]) {
    if (!args[key]) continue;
    const log = readLog(work, args[key]);
    if (key === 'redLog' && log.exit === 0) throw new ToolError('REFUSED', `the Red run (${args[key]}) passed; it must fail before the change`);
    if (key === 'greenLog' && log.exit !== 0) throw new ToolError('REFUSED', `the Green run (${args[key]}) did not pass`);
    out.push(`- ${label}:`, ...block(log.lastLines));
  }
  if (Array.isArray(args.manual) && args.manual.length) {
    out.push('- Manual validation:', ...args.manual.map((s, i) => `  ${i + 1}. ${one(s, 'a manual step')}`));
  }
  if (args.stats && typeof args.stats === 'object') {
    const pairs = Object.entries(args.stats).map(([k, v]) => {
      if (!/^[a-z][a-z_]*$/.test(k)) throw new ToolError('REFUSED', `stats key "${k}" must be lower case letters and _`);
      const val = String(v).trim();
      if (!val || /[\s,;]/.test(val)) throw new ToolError('REFUSED', `stats ${k}: one word, no spaces, commas or semicolons`);
      return `${k}=${val}`;
    });
    if (pairs.length) out.push(`- Stats: ${pairs.join(' ')}`);
  }
  out.push(`- Notes: ${args.notes ? one(args.notes, 'notes') : 'none'}`);
  out.push(`- Next: ${one(args.next, 'next')}`);

  const file = path.join(work.dir, 'progress.md');
  let text = read(file);
  if (text === null) {
    const wi = read(path.join(work.dir, 'workitem.md')) || '';
    const t = wi.match(/^#\s+Work item\s+\S+\s*:\s*(.+?)\s*$/m);
    const id = work.name.split('-')[0];
    text = `# Progress: ${id} ${t ? t[1] : work.name.slice(id.length + 1).replace(/-/g, ' ')}\n\nAppend a new entry at the bottom after every command. Never edit or delete old entries.\n\n---\n`;
  }
  fs.writeFileSync(file, `${text.replace(/\s*$/, '\n')}${out.join('\n')}\n`, 'utf8');
  return { file: `.work/${work.name}/progress.md`, entry: out.slice(1).join('\n') };
}

export async function workTaskDone(args) {
  const { work } = item(args);
  const n = Number(args.n);
  if (!Number.isInteger(n) || n < 1) throw new ToolError('REFUSED', 'n: the task number');
  if (args.log) {
    const log = readLog(work, args.log);
    if (log.exit !== 0) throw new ToolError('REFUSED', `log ${args.log} did not pass (exit ${log.exit}); a task is ticked only when its verify passed`);
  }
  const file = path.join(work.dir, 'tasks.md');
  const text = read(file);
  if (text === null) throw new ToolError('NOFILE', `.work/${work.name}/tasks.md does not exist`);
  const rx = new RegExp(`^(##\\s*\\[)([ xX])(\\]\\s*Task\\s+${n}\\s*:.*)$`, 'm');
  const m = text.match(rx);
  if (!m) throw new ToolError('NOTASK', `no "## [ ] Task ${n}:" heading in tasks.md`);
  if (m[2].toLowerCase() === 'x') return { task: n, changed: false, note: 'already ticked' };
  fs.writeFileSync(file, text.replace(rx, '$1x$3'), 'utf8');
  const remaining = (text.match(/^##\s*\[ \]\s*Task\s+\d+/gm) || []).length - 1;
  return { task: n, changed: true, openTasks: remaining };
}

// ---------------------------------------------------------------- review.md and pr.md from recorded results

function runs(work) {
  const text = read(path.join(work.dir, 'checks', 'runs.jsonl'));
  if (!text) return [];
  return lines(text).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}

function latest(list, repo, kinds) {
  return list.filter((r) => r.repo === repo && kinds.includes(r.kind) && !r.baseline && !r.save).pop() || null;
}

function newestResult(dir, skip) {
  if (!fs.existsSync(dir)) return null;
  let best = null;
  for (const f of fs.readdirSync(dir)) {
    const m = f.match(/^results-([a-z0-9-]+)\.json$/);
    if (!m || skip(m[1])) continue;
    try {
      const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, ''));
      if (!best || String(j.at || '') > String(best.at || '')) best = j;
    } catch { /* skip a broken file */ }
  }
  return best;
}

function testsText(r) {
  if (!r) return null;
  if (r.verdict === 'skipped') return `Tests: SKIPPED ${r.reason || ''}`.trim();
  const acc = Array.isArray(r.acceptance) && r.acceptance.length ? ` (${r.acceptance.join(', ')})` : '';
  const nNew = Array.isArray(r.newTests) ? r.newTests.length : 0;
  const flaky = r.flaky ? `, ${r.flaky} flaky` : '';
  return `Tests: ${r.verdict === 'pass' ? 'PASS' : 'FAIL'} ${r.passed || 0} passed${r.failed ? `, ${r.failed} failed` : ''}, ${nNew} new${acc}${flaky}`;
}

function uiText(r) {
  if (!r) return null;
  if (r.verdict === 'skipped') return `UI: SKIPPED ${r.reason || ''}`.trim();
  const pages = Array.isArray(r.pages) ? new Set(r.pages.map((p) => p.path)).size : 0;
  const widths = Array.isArray(r.pages) ? new Set(r.pages.map((p) => p.width)).size : 0;
  const probs = Array.isArray(r.problems) && r.problems.length ? `, ${r.problems.length} problem(s)` : '';
  const changed = Array.isArray(r.changed) && r.changed.length ? `, ${r.changed.length} changed since before` : '';
  return `UI: ${r.verdict === 'pass' ? 'PASS' : 'FAIL'} ${pages} page(s) at ${widths} width(s)${probs}${changed}`;
}

function runText(r) {
  if (!r) return null;
  if (r.timedOut) return 'FAIL (timed out)';
  if (r.passed) return r.tests ? `PASS (${r.tests.passed} passed)` : 'PASS';
  if (r.tests) return `FAIL (${r.tests.failed} failed${Array.isArray(r.new) ? `, ${r.new.length} new` : ''})`;
  return `FAIL${r.errors && r.errors.length ? `: ${r.errors[0]}` : ''}`;
}

function replaceSection(text, heading, body, before) {
  const rx = new RegExp(`(^##\\s+${heading}\\s*\\r?\\n)[\\s\\S]*?(?=^##\\s|(?![\\s\\S]))`, 'im');
  if (rx.test(text)) return text.replace(rx, `$1\n${body}\n\n`);
  const at = before ? text.search(new RegExp(`^##\\s+${before}`, 'im')) : -1;
  const sec = `## ${heading}\n\n${body}\n\n`;
  return at >= 0 ? text.slice(0, at) + sec + text.slice(at) : `${text.replace(/\s*$/, '\n\n')}${sec}`;
}

async function shortHead(root, row) {
  const dir = row.path ? path.resolve(root, row.path) : path.join(root, row['repo folder']);
  const r = await git(dir, ['rev-parse', '--short', 'HEAD']);
  return r.code === 0 ? r.stdout.trim() : '?';
}

export async function workFillResults(args) {
  const { root, work } = item(args);
  const which = args.file;
  if (!['review', 'pr'].includes(which)) throw new ToolError('REFUSED', 'file: review or pr');
  const repos = readReposMd(work);
  if (!repos.length) throw new ToolError('NOFILE', `.work/${work.name}/repos.md has no repo rows`);
  const all = runs(work);
  const reg = newestResult(path.join(work.dir, 'tests'), (n) => n === 'before');
  const ui = newestResult(path.join(work.dir, 'ui'), (n) => n === 'before' || n.startsWith('task-'));
  const missing = [];
  const rows = [];
  for (const row of repos) {
    const repo = row['repo folder'];
    const build = latest(all, repo, ['build']);
    const unit = latest(all, repo, ['unit', 'precommit']);
    if (!build && !unit) missing.push(`${repo}: no build or unit test run recorded (run checks_run with the item)`);
    rows.push({ repo, build, unit });
  }
  const file = path.join(work.dir, `${which}.md`);
  let text = read(file);
  if (text === null) throw new ToolError('NOFILE', `.work/${work.name}/${which}.md does not exist; write it from its template first`);

  if (which === 'review') {
    const heads = [];
    for (const row of repos) heads.push(`${row['repo folder']} ${await shortHead(root, row)}`);
    text = /^Reviewed at:.*$/m.test(text) ? text.replace(/^Reviewed at:.*$/m, `Reviewed at: ${heads.join(', ')}`) : text;
    const t = ['| Repo | Command | Result |', '|---|---|---|'];
    for (const r of rows) {
      for (const run of [r.build, r.unit].filter(Boolean)) t.push(`| ${r.repo} | \`${run.command}\` | ${runText(run)} |`);
      if (!r.build && !r.unit) t.push(`| ${r.repo} | none recorded | not run |`);
    }
    text = replaceSection(text, 'Test results', t.join('\n'), 'Pass 1');
    const regText = testsText(reg) || 'none in this repo';
    text = replaceSection(text, 'Regression tests', ['| Repo | Result |', '|---|---|', ...repos.map((r) => `| ${r['repo folder']} | ${regText} |`)].join('\n'), 'Pass 1');
    const uiT = uiText(ui) || 'UI: SKIPPED no UI check ran';
    text = replaceSection(text, 'UI checks', ['| Repo | Result |', '|---|---|', ...repos.map((r) => `| ${r['repo folder']} | ${uiT} |`)].join('\n'), 'Pass 1');
  } else {
    const builds = rows.map((r) => (!r.build ? null : r.build.passed ? null : `${r.repo} ${runText(r.build)}`)).filter(Boolean);
    const anyBuild = rows.some((r) => r.build);
    const unit = rows.filter((r) => r.unit).map((r) => `${r.repo} ${r.unit.passed ? `${r.unit.tests ? r.unit.tests.passed : 'all'} passed` : runText(r.unit)}`);
    const set = (label, value) => {
      const rx = new RegExp(`^(-\\s*${label}:).*$`, 'm');
      text = rx.test(text) ? text.replace(rx, `$1 ${value}`) : text;
    };
    set('Builds', anyBuild ? (builds.length ? builds.join('; ') : 'clean') : 'no build command');
    set('Unit tests', unit.length ? unit.join('; ') : 'not run');
    if (reg && reg.verdict !== 'skipped') {
      const acc = Array.isArray(reg.acceptance) && reg.acceptance.length ? ` covering ${reg.acceptance.join(', ')}` : '';
      const flaky = reg.flaky ? `, ${reg.flaky} flaky${Array.isArray(reg.flakyTests) && reg.flakyTests.length ? ` (${reg.flakyTests.map((f) => f.title).join('; ')})` : ''}` : '';
      set('Regression tests', `${reg.passed || 0} passed, ${Array.isArray(reg.newTests) ? reg.newTests.length : 0} new${acc}${flaky}${reg.failed ? `, ${reg.failed} failing` : ''}`);
    } else set('Regression tests', reg ? `skipped: ${reg.reason || 'no reason given'}` : 'none in this repo');
    const review = read(path.join(work.dir, 'review.md'));
    if (review) {
      const v = (review.match(/^\s*Verdict:\s*(.+?)\s*$/im) || [])[1] || 'UNKNOWN';
      const count = (sev) => (review.match(new RegExp(`^\\|\\s*\\d+\\s*\\|\\s*${sev}\\s*\\|`, 'gim')) || []).length;
      set('Review', `${v.toUpperCase()}, with ${count('Should fix')} Should fix and ${count('Nit')} Nit left`);
    }
  }
  fs.writeFileSync(file, text, 'utf8');
  return { file: `.work/${work.name}/${which}.md`, filled: which === 'review' ? ['Reviewed at', 'Test results', 'Regression tests', 'UI checks'] : ['Builds', 'Unit tests', 'Regression tests', 'Review'], missing };
}

// ---------------------------------------------------------------- lint

const GATE_FILES = ['spec', 'plan', 'bug', 'quick', 'refine', 'stories', 'milestones', 'tsd'];
const SEVERITIES = ['blocker', 'should fix', 'nit'];
const CATEGORIES = ['architecture', 'consistency', 'correctness', 'efcore', 'security', 'tests', 'angular', 'playwright', 'leftovers',
  'overbuild', 'tdd', 'spec', 'scope', 'checklist', 'ui', 'conflict', 'regression', 'flaky'];

// Text with code fences, inline code and HTML comments blanked out (line numbers kept).
function prose(text) {
  let t = text.replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
  t = t.replace(/^(\s*)(```|~~~)[\s\S]*?^\s*\2.*$/gm, (m) => m.replace(/[^\n]/g, ' '));
  return t.replace(/`[^`\n]*`/g, (m) => ' '.repeat(m.length));
}

function lineOf(text, index) {
  return text.slice(0, index).split('\n').length;
}

function templateHeadings(name) {
  const t = read(path.join(TEMPLATES, `${name}.md`));
  if (!t) return [];
  return [...prose(t).matchAll(/^##\s+(.+?)\s*$/gm)].map((m) => m[1]).filter((h) => !/[<>]|^\.\.\.$/.test(h) && !/^(Task|Feature) \d/.test(h));
}

function lintFile(name, text, ctx) {
  const problems = [];
  const add = (level, rule, message, line = null) => problems.push({ file: `${name}.md`, line, level, rule, message });
  const p = prose(text);

  for (const m of p.matchAll(/<(?!br\b|\/|!|https?:)[A-Za-z][^<>\n]{1,80}>/g)) {
    add('error', 'placeholder', `template placeholder left in: ${m[0]}`, lineOf(text, m.index));
    if (problems.filter((x) => x.rule === 'placeholder').length >= 15) break;
  }
  for (const m of p.matchAll(/TODO\(you\)/g)) add('warning', 'todo', 'TODO(you) left in', lineOf(text, m.index));

  for (const h of templateHeadings(name)) {
    if (!new RegExp(`^##\\s+${h.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'im').test(text)) add('warning', 'heading', `missing section "## ${h}" (from the template)`);
  }

  if (GATE_FILES.includes(name)) {
    const st = [...text.matchAll(/^\s*Status:\s*(.*?)\s*$/gim)];
    const level = ['spec', 'plan', 'bug', 'quick'].includes(name) ? 'error' : 'warning';
    if (st.length === 0) add(level, 'status', 'no Status: line (the gate Workshop reads)');
    else if (st.length > 1) add('error', 'status', `${st.length} Status: lines; there must be one`, lineOf(text, st[1].index));
    else if (!/^(DRAFT|APPROVED|PUBLISHED\b.*)$/i.test(st[0][1])) add('error', 'status', `Status: ${st[0][1]} is not DRAFT or APPROVED`, lineOf(text, st[0].index));
  }

  if (['spec', 'quick', 'refine'].includes(name)) {
    const ids = [...p.matchAll(/\*\*AC-(\d+):?\*\*/g)].map((m) => Number(m[1]));
    if (ids.length === 0) add('error', 'criteria', 'no acceptance criteria (**AC-1:** ...)');
    const dup = ids.filter((v, i) => ids.indexOf(v) !== i);
    if (dup.length) add('error', 'criteria', `AC ids used twice: ${[...new Set(dup)].map((d) => `AC-${d}`).join(', ')}`);
    ids.forEach((v, i) => { if (v !== i + 1 && !dup.includes(v)) add('warning', 'criteria', `AC ids are not in order 1, 2, 3 (found AC-${v} at position ${i + 1})`); });
  }

  if (name === 'tasks') {
    const heads = [...text.matchAll(/^##\s*\[([ xX])\]\s*Task\s+(\d+)\s*:\s*(.*?)\s*$/gm)];
    if (heads.length === 0) add('error', 'tasks', 'no "## [ ] Task 1: <title>" headings');
    const loose = [...text.matchAll(/^##\s+.*Task\s+\d+.*$/gm)].filter((m) => !/^##\s*\[[ xX]\]\s*Task\s+\d+\s*:/.test(m[0]));
    for (const m of loose) add('error', 'tasks', `task heading Workshop cannot read: "${m[0].trim()}" (use ## [ ] Task <n>: <title>)`, lineOf(text, m.index));
    const covered = new Set();
    heads.forEach((h, i) => {
      const n = Number(h[2]);
      const line = lineOf(text, h.index);
      if (n !== i + 1) add('error', 'tasks', `Task ${n} is number ${i + 1} in the file; number them 1, 2, 3`, line);
      const next = text.slice(h.index + 1).search(/^##\s/m);
      const end = next >= 0 ? h.index + 1 + next : text.length;
      const body = text.slice(h.index, end);
      if (!/^\s*-\s*Repo:\s*\S/m.test(body)) add('error', 'tasks', `Task ${n} has no "- Repo:" line`, line);
      const verifies = body.match(/^\s*-\s*Verify:\s*`[^`]+`/gm) || [];
      if (verifies.length !== 1) add('error', 'tasks', `Task ${n} needs exactly one "- Verify: \`<command>\`" line (found ${verifies.length})`, line);
      const files = [];
      const fm = body.match(/^\s*-\s*Files:\s*\n((?:\s+-\s+.*\n?)+)/m);
      if (fm) for (const l of fm[1].split('\n')) { const f = l.match(/`([^`]+)`/); if (f) files.push(f[1]); }
      const code = files.filter((f) => !/(^|[/\\])(tests?|e2e|__tests__)[/\\]|\.(spec|test)\.|Tests?[/\\.]/i.test(f));
      if (code.length > ctx.cap) add('error', 'tasks', `Task ${n} changes ${code.length} non-test files; the cap is ${ctx.cap}`, line);
      const cov = (body.match(/^\s*-\s*Covers:\s*(.*)$/m) || [])[1] || '';
      for (const m of cov.matchAll(/AC-(\d+)/g)) covered.add(Number(m[1]));
    });
    if (ctx.criteria.length) {
      const unknown = [...covered].filter((c) => !ctx.criteria.includes(c));
      if (unknown.length) add('error', 'coverage', `tasks cover criteria the spec does not have: ${unknown.map((u) => `AC-${u}`).join(', ')}`);
      const uncovered = ctx.criteria.filter((c) => !covered.has(c));
      if (uncovered.length) add('error', 'coverage', `no task covers ${uncovered.map((u) => `AC-${u}`).join(', ')}`);
    }
  }

  if (name === 'review') {
    const v = text.match(/^\s*Verdict:\s*(.+?)\s*$/im);
    if (!v) add('error', 'verdict', 'no Verdict: line');
    else if (!/^(READY|CHANGES NEEDED)$/i.test(v[1])) add('error', 'verdict', `Verdict: ${v[1]} is not READY or CHANGES NEEDED`, lineOf(text, v.index));
    let blockers = 0;
    for (const m of text.matchAll(/^\|\s*(\d+)\s*\|([^\n]*)$/gm)) {
      const cells = m[2].split('|').map((c) => c.trim());
      const sev = (cells[0] || '').toLowerCase();
      const line = lineOf(text, m.index);
      if (!SEVERITIES.includes(sev)) { add('error', 'finding', `finding ${m[1]}: severity "${cells[0]}" is not Blocker, Should fix or Nit`, line); continue; }
      if (sev === 'blocker') blockers++;
      if (cells.length >= 5 && !CATEGORIES.includes((cells[1] || '').toLowerCase())) add('warning', 'finding', `finding ${m[1]}: category "${cells[1]}" is not one of the /review categories`, line);
    }
    if (v && /^READY$/i.test(v[1]) && blockers) add('error', 'verdict', `Verdict READY with ${blockers} Blocker finding(s)`, lineOf(text, v.index));
  }

  if (name === 'progress') {
    let count = 0;
    const entries = text.split(/^(?=##\s)/m).filter((s) => s.startsWith('##'));
    for (const e of entries) {
      const head = e.split('\n')[0];
      const line = lineOf(text, text.indexOf(e));
      if (!/^##\s+\d{4}-\d{2}-\d{2}[^|]*?\s*\|\s*\/\S+/.test(head)) { add('error', 'progress', `entry heading Workshop cannot read: "${head.trim()}" (## <yyyy-mm-dd> | /<command> | <agent>)`, line); continue; }
      count++;
      if (!/^\s*-\s*Did:/m.test(e)) add('error', 'progress', 'entry has no "- Did:" line', line);
      if (!/^\s*-\s*Next:/m.test(e)) add('warning', 'progress', 'entry has no "- Next:" line', line);
      const stats = e.match(/^\s*-\s*Stats:\s*(.*)$/m);
      if (stats && !/^(\s*[a-z_]+=[^\s,;]+)+\s*$/i.test(stats[1].replace(/`/g, ''))) add('error', 'progress', `Stats line is not key=value pairs: "${stats[1]}"`, line);
    }
    if (count === 0) add('warning', 'progress', 'no entries yet');
  }

  if (name === 'pr') {
    const sections = prose(text).split(/^##[ \t]+/m).slice(1);
    const raw = text.split(/^##[ \t]+/m).slice(1);
    sections.forEach((s, i) => {
      const heading = s.split('\n')[0].trim();
      if (/^checks$/i.test(heading)) return;
      const body = raw[i];
      if (!/^\s*(?:-\s*)?(?:\*\*)?Branch:(?:\*\*)?\s*`?[^`\s]+`?\s*(?:->|=>|to|→)\s*`?[^`\s]+`?/im.test(body)) add('error', 'pr', `section ${heading}: no "Branch: \`<branch>\` -> \`<target>\`" line`);
      const t = body.match(/^\s*(?:\*\*)?Title:(?:\*\*)?[ \t]*(.+?)\s*$/im);
      if (!t) add('error', 'pr', `section ${heading}: no **Title:** line`);
      else if (t[1].length > 70) add('warning', 'pr', `section ${heading}: title is ${t[1].length} characters (keep it under 70)`);
      if (!/^\s*(?:\*\*)?Description:(?:\*\*)?/im.test(body)) add('error', 'pr', `section ${heading}: no **Description:** line`);
    });
    if (!sections.some((s) => !/^checks\b/i.test(s.trim()))) add('error', 'pr', 'no repo sections (## <repo-folder>)');
  }

  if (name === 'repos') {
    const lane = (text.match(/^\s*(?:-\s*)?Lane\s*:\s*(.*?)\s*$/im) || [])[1];
    if (!lane) add('error', 'repos', 'no Lane: line');
    else if (!/^(feature|bug|quick|spike)$/i.test(lane)) add('error', 'repos', `Lane: ${lane} is not feature, bug, quick or spike`);
    if (!ctx.repoRows.length) add('error', 'repos', 'no repo rows in the table');
    for (const r of ctx.repoRows) {
      if (!r.branch) add('error', 'repos', `${r['repo folder']}: no branch`);
      if (r.path && (!r.path.startsWith('.worktrees/') || r.path.includes('..'))) add('error', 'repos', `${r['repo folder']}: Path must start with .worktrees/ (Workshop ignores it otherwise)`);
    }
  }

  return problems;
}

const LINTABLE = ['spec', 'plan', 'bug', 'quick', 'tasks', 'review', 'pr', 'progress', 'repos', 'refine', 'stories', 'milestones', 'tsd', 'findings', 'triage', 'brief', 'handoff', 'retro'];

export async function workLint(args) {
  const { work } = item(args);
  let names;
  if (args.file) {
    const n = String(args.file).replace(/\.md$/, '');
    if (!LINTABLE.includes(n)) throw new ToolError('REFUSED', `file: one of ${LINTABLE.join(', ')}`);
    names = [n];
  } else names = LINTABLE.filter((n) => fs.existsSync(path.join(work.dir, `${n}.md`)));
  if (names.length === 0) throw new ToolError('NOFILE', `nothing to check in .work/${work.name}`);
  const factory = (() => { try { return JSON.parse(read(path.join(path.dirname(work.dir), 'factory.json')) || '{}'); } catch { return {}; } })();
  const cap = Number.isInteger(factory.taskFileCap) && factory.taskFileCap > 0 ? factory.taskFileCap : 6;
  const crit = read(path.join(work.dir, 'spec.md')) || read(path.join(work.dir, 'quick.md')) || '';
  const criteria = [...new Set([...prose(crit).matchAll(/\*\*AC-(\d+):?\*\*/g)].map((m) => Number(m[1])))];
  const ctx = { cap, criteria, repoRows: readReposMd(work) };
  const problems = [];
  for (const n of names) {
    const text = read(path.join(work.dir, `${n}.md`));
    if (text === null) { problems.push({ file: `${n}.md`, line: null, level: 'error', rule: 'missing', message: 'file does not exist' }); continue; }
    problems.push(...lintFile(n, text.replace(/\r\n/g, '\n'), ctx));
  }
  const errors = problems.filter((p) => p.level === 'error').length;
  return { item: work.name, checked: names.map((n) => `${n}.md`), ok: errors === 0, errors, warnings: problems.length - errors, problems: problems.slice(0, 60) };
}
