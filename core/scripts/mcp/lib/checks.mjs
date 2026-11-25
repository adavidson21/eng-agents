// checks_* tools: the repo guide's Build, unit test, lint and format commands, run the same way every time, with
// the result as numbers and names, compared with the work item's baseline.md.
import fs from 'node:fs';
import path from 'node:path';
import { runShell, tail } from './proc.mjs';
import { parseOutput, baselineRow, compareWithBaseline } from './parse.mjs';
import {
  ToolError, resolveRepo, requireGuide, guideCommands, guideFieldTable, guideStack, retarget, rel,
} from './workspace.mjs';

export async function checksList(args) {
  const ctx = resolveRepo(args);
  const g = requireGuide(ctx);
  return {
    repo: ctx.repo,
    guide: rel(ctx.root, g.file),
    workingIn: rel(ctx.root, ctx.dir),
    stack: guideStack(g.text),
    commands: guideCommands(g.text),
    uiChecks: guideFieldTable(g.text, 'UI checks'),
    regressionTests: guideFieldTable(g.text, 'Regression tests'),
  };
}

const KINDS = ['build', 'unit', 'precommit', 'lint', 'format', 'command'];
const SAVE = /^[a-z0-9][a-z0-9-]{0,39}$/;

function pickCommand(kind, commands, given) {
  if (kind === 'command') {
    if (!given) throw new ToolError('NOCOMMAND', 'kind "command" needs command (for example the repo guide\'s One test class line with your filter)');
    return { command: given, used: 'command' };
  }
  if (given) throw new ToolError('REFUSED', `command is only for kind "command"; kind "${kind}" runs the repo guide's line`);
  if (kind === 'precommit' && !commands.precommit) {
    if (!commands.unit) throw new ToolError('NOCOMMAND', 'the repo guide has no Pre-commit check or All unit tests command');
    return { command: commands.unit, used: 'unit' };
  }
  const c = commands[kind];
  const label = { build: 'Build', unit: 'All unit tests', precommit: 'Pre-commit check', lint: 'Lint', format: 'Format check' }[kind];
  if (!c) throw new ToolError('NOCOMMAND', `the repo guide's Commands table has no ${label} command`);
  return { command: c, used: kind };
}

function baselineText(folderName, rows) {
  return [
    `# Test baseline: ${folderName}`,
    '',
    'Written by `/start` right after the branches were created, before any change. `/do-task` reads it to tell old failures from new ones. Re-run a repo\'s command and update its row if the base branch changes.',
    '',
    '| Repo | Command | Result | Failing tests before this work item |',
    '|---|---|---|---|',
    ...rows,
    '',
  ].join('\n');
}

function writeBaseline(work, repo, command, outcome, failing) {
  const file = path.join(work.dir, 'baseline.md');
  const cell = failing.length === 0 ? 'none' : failing.length > 20 ? `${failing.length} tests` : failing.join(', ');
  const row = `| ${repo} | \`${command}\` | ${outcome} | ${cell} |`;
  if (!fs.existsSync(file)) {
    fs.writeFileSync(file, baselineText(work.name, [row]), 'utf8');
    return rel(path.dirname(path.dirname(work.dir)), file);
  }
  const text = fs.readFileSync(file, 'utf8');
  const out = [];
  let replaced = false;
  let lastRow = -1;
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*\|\s*([^|]+?)\s*\|/);
    if (m && m[1] === repo) { out.push(row); replaced = true; lastRow = out.length - 1; continue; }
    if (m && m[1].startsWith('<')) continue; // the template's example row
    out.push(line);
    if (/^\s*\|/.test(line)) lastRow = out.length - 1;
  }
  if (!replaced) out.splice(lastRow + 1, 0, row);
  fs.writeFileSync(file, out.join('\n'), 'utf8');
  return rel(path.dirname(path.dirname(work.dir)), file);
}

export async function checksRun(args) {
  const kind = args.kind;
  if (!KINDS.includes(kind)) throw new ToolError('REFUSED', `kind must be one of ${KINDS.join(', ')}`);
  const ctx = resolveRepo(args);
  const g = requireGuide(ctx);
  const picked = pickCommand(kind, guideCommands(g.text), args.command && String(args.command).trim());
  if ((args.save || args.baseline) && !ctx.work) throw new ToolError('NOITEM', 'save and baseline need item');
  if (args.save && !SAVE.test(args.save)) throw new ToolError('REFUSED', 'save must be a short name: lower case letters, digits and dashes');
  const command = retarget(picked.command, ctx.repo, ctx.worktree);
  const timeoutMs = Math.min(Math.max(Number(args.timeoutSeconds) || 1200, 10), 3600) * 1000;
  const r = await runShell(command, { cwd: ctx.root, timeoutMs });
  const output = `${r.stdout}${r.stderr ? `\n${r.stderr}` : ''}`;
  const parsed = parseOutput(output);
  const passed = r.code === 0 && !r.timedOut;
  const result = {
    repo: ctx.repo,
    kind: picked.used,
    command,
    ranFrom: rel(ctx.root, ctx.root),
    passed,
    exitCode: r.code,
    timedOut: r.timedOut,
    durationSeconds: Math.round(r.durationMs / 100) / 10,
    tests: parsed.tests,
    failing: parsed.failing,
    errors: parsed.errors,
    lint: parsed.lint,
    tail: tail(output),
  };
  if (r.notFound) result.note = 'the shell could not start the command';
  if (ctx.work) {
    const bfile = path.join(ctx.work.dir, 'baseline.md');
    if (!args.baseline && fs.existsSync(bfile)) {
      result.baseline = compareWithBaseline(parsed.failing, baselineRow(fs.readFileSync(bfile, 'utf8'), ctx.repo));
      result.baseline.newFailures = !passed && (result.baseline.new.length > 0 || parsed.failing.length === 0);
    }
    if (args.save) {
      const dir = path.join(ctx.work.dir, 'checks');
      fs.mkdirSync(dir, { recursive: true });
      const file = path.join(dir, `${args.save}.log`);
      fs.writeFileSync(file, `$ ${command}\n${output}\nexit ${r.code}${r.timedOut ? ' (timed out)' : ''}\n`, 'utf8');
      result.log = rel(ctx.root, file);
    }
    if (args.baseline) {
      const outcome = r.timedOut || r.notFound ? 'could not run' : passed ? 'PASS' : 'FAIL';
      result.baselineWritten = writeBaseline(ctx.work, ctx.repo, picked.command, outcome, parsed.failing);
    }
  }
  return result;
}
