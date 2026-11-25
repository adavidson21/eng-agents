import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { makeWorkspace, cleanup, write } from './fixture.mjs';
import { checksList, checksRun } from '../lib/checks.mjs';
import { parseOutput, baselineRow, compareWithBaseline } from '../lib/parse.mjs';
import { retarget, readTable } from '../lib/workspace.mjs';

test('checks_list reads the guide', async () => {
  const { root } = makeWorkspace();
  try {
    const r = await checksList({ workspace: root, repo: 'app' });
    assert.deepEqual(r.stack, ['angular', 'playwright']);
    assert.equal(r.commands.build, 'node app/build.js');
    assert.equal(r.commands.unit, 'node app/unit.js');
    assert.equal(r.commands.lint, undefined, 'placeholders are not commands');
    assert.equal(r.regressionTests.command, 'npx playwright test');
    assert.equal(r.uiChecks, null);
  } finally { cleanup(root); }
});

test('checks_run: build passes, missing command is NOCOMMAND', async () => {
  const { root } = makeWorkspace();
  try {
    const r = await checksRun({ workspace: root, repo: 'app', kind: 'build' });
    assert.equal(r.passed, true);
    assert.equal(r.exitCode, 0);
    assert.ok(r.tail.some((l) => l.includes('Build succeeded')));
    await assert.rejects(checksRun({ workspace: root, repo: 'app', kind: 'lint' }), /NOCOMMAND/);
    await assert.rejects(checksRun({ workspace: root, repo: 'app', kind: 'command' }), /NOCOMMAND/);
    await assert.rejects(checksRun({ workspace: root, repo: 'app', kind: 'build', command: 'echo hi' }), /REFUSED/);
  } finally { cleanup(root); }
});

test('checks_run: baseline written, then failures split into old and new', async () => {
  const { root, repo } = makeWorkspace();
  try {
    write(path.join(repo, 'FAIL'), '');
    // precommit falls back to All unit tests.
    const first = await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'precommit', baseline: true });
    assert.equal(first.kind, 'unit');
    assert.equal(first.passed, false);
    assert.deepEqual(first.tests, { failed: 2, passed: 8, skipped: 0, total: 10 });
    const md = fs.readFileSync(path.join(root, '.work', 'L1-thing', 'baseline.md'), 'utf8');
    assert.match(md, /\| app \| `node app\/unit.js` \| FAIL \| Orders.Tests.TotalsTests.AddsTax, Orders.Tests.TotalsTests.Rounds \|/);

    fs.writeFileSync(path.join(root, '.work', 'L1-thing', 'baseline.md'), md.replace(', Orders.Tests.TotalsTests.Rounds', ''));
    const second = await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'unit', save: 'task-1-green' });
    assert.deepEqual(second.baseline.preExisting, ['Orders.Tests.TotalsTests.AddsTax']);
    assert.deepEqual(second.baseline.new, ['Orders.Tests.TotalsTests.Rounds']);
    assert.equal(second.baseline.newFailures, true);
    assert.ok(fs.existsSync(path.join(root, '.work', 'L1-thing', 'checks', 'task-1-green.log')));

    // Rewriting the baseline replaces the row, never duplicates it.
    fs.rmSync(path.join(repo, 'FAIL'));
    await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'unit', baseline: true });
    const again = fs.readFileSync(path.join(root, '.work', 'L1-thing', 'baseline.md'), 'utf8');
    assert.equal((again.match(/^\| app \|/gm) || []).length, 1);
    assert.match(again, /\| app \| `node app\/unit.js` \| PASS \| none \|/);
  } finally { cleanup(root); }
});

test('checks_run: save and baseline need an item', async () => {
  const { root } = makeWorkspace();
  try {
    await assert.rejects(checksRun({ workspace: root, repo: 'app', kind: 'unit', save: 'x' }), /NOITEM/);
  } finally { cleanup(root); }
});

test('retarget points repo paths at the worktree', () => {
  const wt = '.worktrees/L1-thing/app';
  assert.equal(retarget('dotnet test app/tests/A.csproj', 'app', wt), `dotnet test ${wt}/tests/A.csproj`);
  assert.equal(retarget('dotnet test "app/tests/A.csproj" --filter x', 'app', wt), `dotnet test "${wt}/tests/A.csproj" --filter x`);
  assert.equal(retarget('npm --prefix app test', 'app', wt), 'npm --prefix app test', 'only paths into the folder');
  assert.equal(retarget('dotnet test myapp/x.csproj', 'app', wt), 'dotnet test myapp/x.csproj');
  assert.equal(retarget('dotnet test app\\x.csproj', 'app', wt), `dotnet test ${wt}\\x.csproj`);
  assert.equal(retarget('dotnet test app/x.csproj', 'app', null), 'dotnet test app/x.csproj');
});

test('parse: dotnet, MSBuild errors', () => {
  const r = parseOutput([
    'src/Orders/Totals.cs(12,5): error CS0103: The name \'x\' does not exist [src/Orders/Orders.csproj]',
    '  Failed Orders.Tests.A.B [5 ms]',
    'Failed!  - Failed:     1, Passed:     4, Skipped:     1, Total:     6, Duration: 1 s - Orders.Tests.dll',
    'Passed!  - Failed:     0, Passed:     3, Skipped:     0, Total:     3',
  ].join('\n'));
  assert.deepEqual(r.tests, { failed: 1, passed: 7, skipped: 1, total: 9 });
  assert.deepEqual(r.failing, ['Orders.Tests.A.B']);
  assert.deepEqual(r.errors, ["src/Orders/Totals.cs(12,5): error CS0103: The name 'x' does not exist"]);
});

test('parse: jest, karma, vitest, angular and eslint', () => {
  const jest = parseOutput('  ● Orders › saves the reason\n  ● Console\nTests:       1 failed, 2 skipped, 10 passed, 13 total\n');
  assert.deepEqual(jest.tests, { failed: 1, passed: 10, skipped: 2, total: 13 });
  assert.deepEqual(jest.failing, ['Orders › saves the reason']);

  const karma = parseOutput('Chrome Headless 120.0 (Linux x86_64) OrdersComponent should save FAILED\nChrome Headless 120.0 (Linux x86_64): Executed 3 of 12 SUCCESS\nChrome Headless 120.0 (Linux x86_64): Executed 12 of 12 (1 FAILED) (skipped 2)\n');
  assert.deepEqual(karma.tests, { failed: 1, passed: 11, skipped: 2, total: 12 });
  assert.deepEqual(karma.failing, ['OrdersComponent should save']);

  const vi = parseOutput(' FAIL  src/a.spec.ts > Orders > saves\n Tests  1 failed | 4 passed (5)\n');
  assert.deepEqual(vi.tests, { failed: 1, passed: 4, skipped: 0, total: 5 });
  assert.deepEqual(vi.failing, ['src/a.spec.ts > Orders > saves']);

  const ng = parseOutput('✘ [ERROR] TS2322: Type \'string\' is not assignable [plugin angular-compiler]\nError: src/app/a.ts:3:1 - error TS2304: Cannot find name \'y\'.\n');
  assert.equal(ng.errors.length, 2);

  const es = parseOutput('✖ 3 problems (2 errors, 1 warning)\n');
  assert.deepEqual(es.lint, { problems: 3, errors: 2, warnings: 1 });
});

test('baseline rows: names, none, and counts', () => {
  const md = '| Repo | Command | Result | Failing |\n|---|---|---|---|\n| api | `x` | FAIL | A.B, C.D |\n| ui | `y` | PASS | none |\n| big | `z` | FAIL | 23 tests |\n';
  assert.deepEqual(baselineRow(md, 'api').failing, ['A.B', 'C.D']);
  assert.deepEqual(baselineRow(md, 'ui').failing, []);
  assert.equal(baselineRow(md, 'big').failing, null);
  assert.equal(baselineRow(md, 'none'), null);
  const c = compareWithBaseline(['Ns.A.B', 'E.F'], baselineRow(md, 'api'));
  assert.deepEqual(c.preExisting, ['Ns.A.B']);
  assert.deepEqual(c.new, ['E.F']);
});

test('readTable keys rows by header', () => {
  const rows = readTable('## Commands\n\n| Purpose | Command |\n|---|---|\n| Build | `dotnet build` |\n\n## Next\n| a | b |\n', /^##\s+Commands$/);
  assert.deepEqual(rows, [{ purpose: 'Build', command: 'dotnet build' }]);
});
