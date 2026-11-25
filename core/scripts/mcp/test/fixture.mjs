// A scratch workspace for the tool tests: one git repo "app" with a repo guide, a main branch, a work branch and a
// work item in .work. Commands in the guide are small node scripts, so the tests run the same on Windows and Linux.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

export function sh(dir, ...args) {
  return execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

export function write(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text, 'utf8');
}

export function makeWorkspace() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tandem-mcp-'));
  const repo = path.join(root, 'app');
  fs.mkdirSync(repo);
  sh(repo, 'init', '-q', '-b', 'main');
  sh(repo, 'config', 'user.name', 'Test');
  sh(repo, 'config', 'user.email', 'test@example.com');
  sh(repo, 'config', 'commit.gpgsign', 'false');
  write(path.join(repo, 'AGENTS.md'), `# app

## Tech stack

Stack: angular, playwright

## Commands

Run from the workspace root unless stated otherwise. One command per line.

| Purpose | Command |
|---|---|
| Build | \`node app/build.js\` |
| All unit tests | \`node app/unit.js\` |
| Lint | \`<command>\` |

## Regression tests

| Field | Value |
|---|---|
| Command | \`npx playwright test\` |
| Runner | \`playwright\` |
| Folder | \`e2e/\` |
`);
  write(path.join(repo, 'build.js'), "console.log('Build succeeded.');\n");
  write(path.join(repo, 'unit.js'), [
    "const fail = require('fs').existsSync(require('path').join(__dirname, 'FAIL'));",
    "if (fail) { console.log('  Failed Orders.Tests.TotalsTests.AddsTax [12 ms]'); console.log('  Failed Orders.Tests.TotalsTests.Rounds [3 ms]'); }",
    "console.log(fail ? 'Failed!  - Failed:     2, Passed:    8, Skipped:     0, Total:    10' : 'Passed!  - Failed:     0, Passed:    10, Skipped:     0, Total:    10');",
    'process.exit(fail ? 1 : 0);',
    '',
  ].join('\n'));
  write(path.join(repo, 'shared.txt'), 'one\ntwo\nthree\n');
  sh(repo, 'add', '-A');
  sh(repo, 'commit', '-q', '-m', 'first');
  sh(repo, 'checkout', '-q', '-b', 'dev/feature/L1-thing');
  write(path.join(root, '.work', 'L1-thing', 'repos.md'), `# Repos for L1

Lane: feature

| Order | Repo folder | Branch | Shared? | Why it is involved | Base | Path |
|---|---|---|---|---|---|---|
| 1 | app | dev/feature/L1-thing | no | the change | main | |
`);
  return { root, repo };
}

export function cleanup(root) {
  fs.rmSync(root, { recursive: true, force: true });
}
