import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { makeWorkspace, cleanup, write } from './fixture.mjs';
import { checksRun } from '../lib/checks.mjs';
import { workProgressAdd, workTaskDone, workFillResults, workLint } from '../lib/work.mjs';

const wf = (root, f) => path.join(root, '.work', 'L1-thing', f);

const TASKS = `# Tasks: L1 thing

---

## [ ] Task 1: Add the total

- Repo: \`app\`
- Covers: AC-1
- Files:
  - \`app/src/total.js\` (new)
  - \`app/tests/total.test.js\` (new)
- Verify: \`node app/unit.js\`
- Done when: it passes

---

## [ ] Task 2: Show it

- Repo: \`app\`
- Covers: AC-2
- Files:
  - \`app/src/view.js\` (changed)
- Verify: \`node app/unit.js\`
- Done when: it passes
`;

const SPEC = `# Spec: L1 thing

Status: DRAFT

## Goal

Totals.

## Current behavior

None.

## Acceptance criteria

- **AC-1:** Given an order, when it is saved, then the total is shown.
- **AC-2:** Given an order, when it is opened, then the total is shown.

## Non-goals

- None

## Decisions made during clarification

| Question | Answer |
|---|---|
| a | b |

## Assumptions

- None

## Open questions

- None
`;

test('work_progress_add: real output from the log, refuses a PASS the log does not show', async () => {
  const { root, repo } = makeWorkspace();
  try {
    await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'unit', save: 'task-1-green' });
    const r = await workProgressAdd({
      workspace: root, item: 'L1', command: 'do-task', agent: 'implementer', did: 'Added the total.',
      files: ['app/src/total.js'], outputLog: 'task-1-green', greenLog: 'task-1-green',
      manual: ['Open /orders/1', 'Verify the total shows'], stats: { verify: 'PASS', full: 'skipped', attempts: 1 }, next: '`/do-task L1 2`',
    });
    const text = fs.readFileSync(wf(root, 'progress.md'), 'utf8');
    assert.match(text, /^# Progress: L1 thing$/m);
    assert.match(text, /^## \d{4}-\d{2}-\d{2} \| \/do-task \| implementer$/m);
    assert.match(text, /^- Verify: `node app\/unit.js` -> PASS$/m);
    assert.match(text, /Passed!  - Failed:     0/);
    assert.match(text, /^- Stats: verify=PASS full=skipped attempts=1$/m);
    assert.match(text, /^  2\. Verify the total shows$/m);
    assert.match(r.entry, /- Next: `\/do-task L1 2`/);

    write(path.join(repo, 'FAIL'), '');
    await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'unit', save: 'task-2-green' });
    const base = { workspace: root, item: 'L1', command: 'do-task', did: 'x', next: 'y' };
    await assert.rejects(workProgressAdd({ ...base, outputLog: 'task-2-green', verifyResult: 'PASS' }), /REFUSED: verifyResult is PASS, but log/);
    await assert.rejects(workProgressAdd({ ...base, greenLog: 'task-2-green' }), /REFUSED: the Green run/);
    await assert.rejects(workProgressAdd({ ...base, redLog: 'task-1-green' }), /REFUSED: the Red run/);
    await assert.rejects(workProgressAdd({ ...base, verifyCommand: 'x', verifyResult: 'PASS' }), /REFUSED: a PASS needs outputLog/);
    await assert.rejects(workProgressAdd({ ...base, stats: { verify: 'PASS FAIL' } }), /REFUSED: stats verify/);
    await assert.rejects(workProgressAdd({ ...base, outputLog: 'nope' }), /NOLOG/);
    const failEntry = await workProgressAdd({ ...base, outputLog: 'task-2-green' });
    assert.match(failEntry.entry, /-> FAIL/);
  } finally { cleanup(root); }
});

test('work_task_done: ticks one task, refuses a failed log', async () => {
  const { root, repo } = makeWorkspace();
  try {
    write(wf(root, 'tasks.md'), TASKS);
    const r = await workTaskDone({ workspace: root, item: 'L1', n: 2 });
    assert.equal(r.changed, true);
    assert.equal(r.openTasks, 1);
    const text = fs.readFileSync(wf(root, 'tasks.md'), 'utf8');
    assert.match(text, /^## \[ \] Task 1:/m);
    assert.match(text, /^## \[x\] Task 2:/m);
    assert.equal((await workTaskDone({ workspace: root, item: 'L1', n: 2 })).changed, false);
    await assert.rejects(workTaskDone({ workspace: root, item: 'L1', n: 9 }), /NOTASK/);
    write(path.join(repo, 'FAIL'), '');
    await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'unit', save: 'bad' });
    await assert.rejects(workTaskDone({ workspace: root, item: 'L1', n: 1, log: 'bad' }), /REFUSED/);
  } finally { cleanup(root); }
});

test('work_fill_results: review.md and pr.md tables from recorded runs and result files', async () => {
  const { root } = makeWorkspace();
  try {
    await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'build' });
    await checksRun({ workspace: root, repo: 'app', item: 'L1', kind: 'unit' });
    write(wf(root, 'tests/results-after.json'), JSON.stringify({
      version: 1, name: 'after', at: '2026-11-24T10:00:00Z', verdict: 'pass', passed: 48, failed: 0, flaky: 1,
      newTests: [{ title: 'a [AC-1]' }, { title: 'b [AC-2]' }], acceptance: ['AC-1', 'AC-2'], flakyTests: [{ title: 'loads' }],
    }));
    write(wf(root, 'ui/results-after.json'), JSON.stringify({ version: 1, at: '2026-11-24T10:00:00Z', verdict: 'pass', pages: [{ path: '/', width: 1280 }, { path: '/', width: 390 }], problems: [], changed: [] }));
    write(wf(root, 'review.md'), '# Review: L1 thing\n\nVerdict: READY\n\nReviewed at: <repo> <short commit>\n\n## Test results\n\n| Repo | Command | Result |\n|---|---|---|\n| <repo> | `<command>` | <PASS> |\n\n## Pass 1: Spec compliance\n\nok\n\n## Pass 2: Code quality\n\n| # | Severity | Category | Location | Problem | Suggested fix |\n|---|---|---|---|---|---|\n| 1 | Nit | leftovers | `app/a.js:1` | log | remove |\n');
    const r = await workFillResults({ workspace: root, item: 'L1', file: 'review' });
    assert.deepEqual(r.missing, []);
    const review = fs.readFileSync(wf(root, 'review.md'), 'utf8');
    assert.match(review, /^Reviewed at: app [0-9a-f]{7}$/m);
    assert.match(review, /\| app \| `node app\/build.js` \| PASS \|/);
    assert.match(review, /\| app \| `node app\/unit.js` \| PASS \(10 passed\) \|/);
    assert.match(review, /## Regression tests\n\n\| Repo \| Result \|\n\|---\|---\|\n\| app \| Tests: PASS 48 passed, 2 new \(AC-1, AC-2\), 1 flaky \|/);
    assert.match(review, /\| app \| UI: PASS 1 page\(s\) at 2 width\(s\) \|/);
    assert.ok(review.indexOf('## UI checks') < review.indexOf('## Pass 1'), 'missing sections go before Pass 1');
    assert.match(review, /\| 1 \| Nit \| leftovers/, 'findings are untouched');

    write(wf(root, 'pr.md'), '# PR text: L1\n\n## Checks\n\n- Builds: <clean>\n- Unit tests: <n>\n- Regression tests: <n>\n- Docs: no doc change needed\n- Clean up: none\n- Review: <READY>\n\n---\n\n## app\n');
    await workFillResults({ workspace: root, item: 'L1', file: 'pr' });
    const pr = fs.readFileSync(wf(root, 'pr.md'), 'utf8');
    assert.match(pr, /^- Builds: clean$/m);
    assert.match(pr, /^- Unit tests: app 10 passed$/m);
    assert.match(pr, /^- Regression tests: 48 passed, 2 new covering AC-1, AC-2, 1 flaky \(loads\)$/m);
    assert.match(pr, /^- Docs: no doc change needed$/m);
    assert.match(pr, /^- Review: READY, with 0 Should fix and 1 Nit left$/m);
  } finally { cleanup(root); }
});

test('work_fill_results: reports repos with nothing recorded', async () => {
  const { root } = makeWorkspace();
  try {
    write(wf(root, 'review.md'), '# Review\n\nVerdict: READY\n');
    const r = await workFillResults({ workspace: root, item: 'L1', file: 'review' });
    assert.equal(r.missing.length, 1);
    assert.match(fs.readFileSync(wf(root, 'review.md'), 'utf8'), /\| app \| none recorded \| not run \|/);
  } finally { cleanup(root); }
});

test('work_lint: a clean item passes', async () => {
  const { root } = makeWorkspace();
  try {
    write(wf(root, 'spec.md'), SPEC);
    write(wf(root, 'tasks.md'), `${TASKS}\n## Coverage check\n\n| Acceptance criterion | Covered by tasks |\n|---|---|\n| AC-1 | 1 |\n| AC-2 | 2 |\n`);
    const r = await workLint({ workspace: root, item: 'L1' });
    assert.equal(r.ok, true, JSON.stringify(r.problems));
    assert.deepEqual(r.checked, ['spec.md', 'tasks.md', 'repos.md']);
  } finally { cleanup(root); }
});

test('work_lint: catches what breaks Workshop or the pipeline', async () => {
  const { root } = makeWorkspace();
  try {
    write(wf(root, 'spec.md'), SPEC.replace('Status: DRAFT', 'Status: maybe').replace('**AC-2:**', '**AC-1:**').replace('Totals.', '<One or two sentences>'));
    write(path.join(root, '.work', 'factory.json'), JSON.stringify({ taskFileCap: 1 }));
    write(wf(root, 'tasks.md'), TASKS
      .replace('## [ ] Task 2: Show it', '## Task 2: Show it')
      .replace('- Covers: AC-1', '- Covers: AC-1, AC-7')
      .replace('  - `app/tests/total.test.js` (new)', '  - `app/src/more.js` (new)')
      .replace('- Verify: `node app/unit.js`\n- Done when: it passes\n\n---', '- Done when: it passes\n\n---'));
    write(wf(root, 'review.md'), '# Review\n\nVerdict: READY\n\n| # | Severity | Category | Location | Problem | Suggested fix |\n|---|---|---|---|---|---|\n| 1 | Blocker | correctness | `a` | b | c |\n| 2 | Major | stuff | `a` | b | c |\n');
    write(wf(root, 'progress.md'), '# Progress: L1 thing\n\n## Started the item\n\n- Did: x\n\n## 2026-11-24 | /start | planner\n\n- Did: set up\n- Stats: questions=1, assumptions 2\n- Next: /spec L1\n');
    write(wf(root, 'pr.md'), '# PR\n\n## Checks\n\n- Builds: clean\n\n---\n\n## app\n\n**Title:** x\n');
    const r = await workLint({ workspace: root, item: 'L1' });
    const msgs = r.problems.filter((p) => p.level === 'error').map((p) => `${p.file} ${p.message}`);
    const has = (rx) => assert.ok(msgs.some((m) => rx.test(m)), `expected ${rx} in:\n${msgs.join('\n')}`);
    has(/spec.md Status: maybe is not DRAFT or APPROVED/);
    has(/spec.md AC ids used twice: AC-1/);
    has(/spec.md template placeholder left in: <One or two sentences>/);
    has(/tasks.md task heading Workshop cannot read: "## Task 2: Show it"/);
    has(/tasks.md Task 1 needs exactly one "- Verify/);
    has(/tasks.md Task 1 changes 2 non-test files; the cap is 1/);
    has(/tasks.md tasks cover criteria the spec does not have: AC-7/);
    has(/review.md finding 2: severity "Major"/);
    has(/review.md Verdict READY with 1 Blocker/);
    has(/progress.md entry heading Workshop cannot read: "## Started the item"/);
    has(/progress.md Stats line is not key=value pairs/);
    has(/pr.md section app: no "Branch:/);
    has(/pr.md section app: no \*\*Description:\*\*/);
    assert.equal(r.ok, false);
    const one = await workLint({ workspace: root, item: 'L1', file: 'review' });
    assert.deepEqual(one.checked, ['review.md']);
    await assert.rejects(workLint({ workspace: root, item: 'L1', file: 'secrets' }), /REFUSED/);
  } finally { cleanup(root); }
});

test('work_lint: test files do not count toward the cap', async () => {
  const { root } = makeWorkspace();
  try {
    write(path.join(root, '.work', 'factory.json'), JSON.stringify({ taskFileCap: 1 }));
    write(wf(root, 'tasks.md'), TASKS);
    const r = await workLint({ workspace: root, item: 'L1', file: 'tasks' });
    assert.ok(!r.problems.some((p) => /cap/.test(p.message)), JSON.stringify(r.problems));
  } finally { cleanup(root); }
});
