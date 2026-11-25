// The Tandem tools: name, what it is for, its arguments, and the function that runs it.
import { repoCheck, repoChanges, repoMergeCheck, repoCommit } from './repo.mjs';
import { checksList, checksRun } from './checks.mjs';
import { workProgressAdd, workTaskDone, workFillResults, workLint } from './work.mjs';
import { uiAppStart, uiAppStop, uiCheck, testsSuite, testsDetect, testsEnsureEnv, testsScaffold } from './ui.mjs';

const repo = { type: 'string', description: 'Repo folder name, directly inside the workspace root (for example portal-ui).' };
const item = { type: 'string', description: 'Work item id or .work folder name (for example L12). With it, the repo\'s worktree Path, branch and base come from repos.md.' };
const itemRequired = { ...item, description: 'Work item id or .work folder name (for example L12).' };
const base = { type: 'string', description: 'Base to compare with (for example origin/main). Default: repos.md\'s Base, else the remote\'s default branch.' };
const workspace = { type: 'string', description: 'Workspace root. Default: the folder opencode was started in.' };
const runName = { type: 'string', description: 'Run name, for example before, after, pr or task-2. Default after.' };

const obj = (properties, required = []) => ({ type: 'object', properties: { ...properties, workspace }, required, additionalProperties: false });
const ro = { readOnlyHint: true, openWorldHint: false };

export const TOOLS = [
  {
    name: 'repo_check',
    description: 'Git state of one repo before you work in it: current branch vs repos.md, uncommitted files, base found, commits ahead and behind. Use instead of git branch --show-current and git status --porcelain. ok is false with problems when something is off.',
    inputSchema: obj({ repo, item, base }, ['repo']),
    annotations: ro,
    run: repoCheck,
  },
  {
    name: 'repo_changes',
    description: 'What a branch changed against its base: commits, files with lines added and removed, totals, and uncommitted files. Pass file to get that file\'s diff. Use instead of git log <base>..HEAD, git diff --stat and git diff <base>...HEAD.',
    inputSchema: obj({ repo, item, base, file: { type: 'string', description: 'Optional: one file (path in the repo) to return the diff of.' } }, ['repo']),
    annotations: ro,
    run: repoChanges,
  },
  {
    name: 'repo_merge_check',
    description: 'Would merging the base into this branch conflict? Fetches the base, then checks with git merge-tree without touching the working folder. Returns behind count, clean, conflicting files, and needsYou (lock and generated files never to resolve by hand). Changes nothing; do the actual merge with git as the command says.',
    inputSchema: obj({ repo, item, base, fetch: { type: 'boolean', description: 'Fetch the base from origin first. Default true.' } }, ['repo']),
    annotations: { readOnlyHint: true, openWorldHint: true },
    run: repoMergeCheck,
  },
  {
    name: 'repo_commit',
    description: 'Commit exactly the files you name on the work item\'s branch. Refuses when the branch is not the one in repos.md, other files are already staged, a named file has no changes, or the message is not one short line. Use instead of git add and git commit.',
    inputSchema: obj({
      repo,
      item,
      files: { type: 'array', items: { type: 'string' }, description: 'Paths relative to the repo (or its worktree) to stage and commit.' },
      message: { type: 'string', description: 'One-line commit message, following the pipeline guide\'s convention.' },
    }, ['repo', 'files', 'message']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: repoCommit,
  },
  {
    name: 'checks_list',
    description: 'The repo guide\'s Stack line, Commands table (build, unit, precommit, oneTest, lint, format, playwright), UI checks and Regression tests tables, read for you.',
    inputSchema: obj({ repo, item }, ['repo']),
    annotations: ro,
    run: checksList,
  },
  {
    name: 'checks_run',
    description: 'Run a repo guide command and get the result as data: passed, test counts, failing test names, compiler errors, lint counts and the last lines. kind build, unit (All unit tests), precommit (Pre-commit check, else All unit tests), lint, format, or command (your own line, for example One test class with a filter or a task\'s verify command). In a worktree, paths are pointed at it for you. With item, failing tests are split into baseline.preExisting and baseline.new. save writes the full output to .work/<item>/checks/<save>.log (Red and Green runs); baseline true writes this repo\'s row in baseline.md (/start).',
    inputSchema: obj({
      repo,
      item,
      kind: { type: 'string', enum: ['build', 'unit', 'precommit', 'lint', 'format', 'command'] },
      command: { type: 'string', description: 'Only for kind command: the command line, written from the workspace root like the repo guide\'s.' },
      timeoutSeconds: { type: 'number', description: 'Default 1200, at most 3600.' },
      save: { type: 'string', description: 'Optional log name, for example task-2-red or task-2-green.' },
      baseline: { type: 'boolean', description: 'Write this run as the repo\'s row in baseline.md. Only at /start, before any change.' },
    }, ['repo', 'kind']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: checksRun,
  },
  {
    name: 'ui_app_start',
    description: 'Start the work item\'s app once for the build (Start-UiApp.ps1), or reuse the one running. status RUNNING with url, or SKIPPED with why (not a failure).',
    inputSchema: obj({ repo, item: itemRequired }, ['repo', 'item']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: uiAppStart,
  },
  {
    name: 'ui_app_stop',
    description: 'Stop the app ui_app_start started for this work item (Stop-UiApp.ps1). An app that was already running before is only forgotten.',
    inputSchema: obj({ item: itemRequired }, ['item']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: uiAppStop,
  },
  {
    name: 'ui_check',
    description: 'UI check of a repo\'s pages (Test-Ui.ps1): status PASS, FAIL or SKIPPED, the problems list, and paths to each page\'s text (aria) and screenshots. quick true for a per-task check (one width, page text written, uses the warm app); pages limits it to some paths; uncommitted skips when the uncommitted changes touch no UI files; base skips when the branch touches no UI files.',
    inputSchema: obj({
      repo,
      item: itemRequired,
      name: runName,
      quick: { type: 'boolean' },
      pages: { type: 'array', items: { type: 'string' }, description: 'Paths such as /orders/12. Default: the table\'s Pages.' },
      uncommitted: { type: 'boolean' },
      base,
    }, ['repo', 'item']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: uiCheck,
  },
  {
    name: 'tests_suite',
    description: 'Run the repo\'s whole end-to-end suite (Test-Suite.ps1, the Regression tests table) and get the results: passed, failed, flaky, pre-existing failures, the item\'s new tests and the [AC-n] criteria they cover. name before at /start, after at /review, pr at /pr. Pass base so new tests are found.',
    inputSchema: obj({ repo, item: itemRequired, name: runName, base }, ['repo', 'item']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: testsSuite,
  },
  {
    name: 'tests_detect',
    description: 'What a front-end repo has for end-to-end tests: Angular version and project, dev server port, unit test runner, Playwright version and config, browsers installed, test folder, existing tests (pattern is one to copy), routes found in the routing files, and what is missing.',
    inputSchema: obj({ repo, item }, ['repo']),
    annotations: ro,
    run: testsDetect,
  },
  {
    name: 'tests_ensure_env',
    description: 'Set up Playwright in a Node front end, doing only what is missing: installs @playwright/test with the repo\'s package manager, writes playwright.config.ts with webServer serving the app (ng serve for Angular), makes the test folder, installs Chromium. Returns each step and the Regression tests table values for the repo guide. Safe to run again.',
    inputSchema: obj({
      repo,
      item,
      folder: { type: 'string', description: 'Test folder. Default: the existing one, else e2e.' },
      install: { type: 'boolean', description: 'Install packages and browsers. Default true; false only reports what is needed.' },
      browsers: { type: 'boolean', description: 'Install Chromium when missing. Default true.' },
    }, ['repo']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: true },
    run: testsEnsureEnv,
  },
  {
    name: 'tests_scaffold',
    description: 'Write a new Playwright spec file with one test per acceptance criterion, titled "<title> [AC-n]", an API mock (page.route) and page.goto(route). Each test fails until you replace its placeholder with real steps. Never overwrites a file.',
    inputSchema: obj({
      repo,
      item,
      file: { type: 'string', description: 'File slug, for example refund-reason (writes <folder>/refund-reason.spec.ts).' },
      route: { type: 'string', description: 'Page path the tests open, for example /orders/12.' },
      criteria: {
        type: 'array',
        items: { type: 'object', properties: { id: { type: 'string' }, title: { type: 'string' } }, required: ['id', 'title'] },
        description: 'Acceptance criteria a person can see: [{ id: "AC-1", title: "saves the refund reason" }].',
      },
      api: { type: 'string', description: 'URL pattern to mock. Default **/api/**.' },
      folder: { type: 'string', description: 'Test folder. Default: the one Playwright uses, else e2e.' },
    }, ['repo', 'file', 'route', 'criteria']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: testsScaffold,
  },
  {
    name: 'work_progress_add',
    description: 'Append a progress.md entry in the exact format Workshop and /stats read. Output, Red and Green blocks are copied from logs saved by checks_run (save), so they are the real output; a PASS needs outputLog, and a verifyResult that disagrees with the log is refused. Use instead of writing the entry by hand.',
    inputSchema: obj({
      item: itemRequired,
      command: { type: 'string', description: 'The command, for example do-task, review or pr.' },
      agent: { type: 'string', description: 'Your agent name, for example implementer.' },
      did: { type: 'string', description: 'One or two lines: what this command did.' },
      files: { type: 'array', items: { type: 'string' }, description: 'Files changed (repo/path). Empty for none.' },
      outputLog: { type: 'string', description: 'Saved log of the verify run (checks_run save), for example task-2-green.' },
      verifyCommand: { type: 'string', description: 'Only without outputLog: the verify command that could not be run.' },
      verifyResult: { type: 'string', enum: ['PASS', 'FAIL', 'not run'] },
      redLog: { type: 'string', description: 'Saved log of the Red run (must have failed).' },
      greenLog: { type: 'string', description: 'Saved log of the Green run (must have passed).' },
      manual: { type: 'array', items: { type: 'string' }, description: 'Manual validation steps, in order (do-task only).' },
      stats: { type: 'object', additionalProperties: { type: ['string', 'number'] }, description: 'The Stats pairs the command asks for, for example { verify: "PASS", full: "skipped", ui: "PASS", attempts: 1 }.' },
      notes: { type: 'string', description: 'Problems or things noticed, for example "Noticed: O12". Default none.' },
      next: { type: 'string', description: 'The exact next command, for example `/do-task L12 3`.' },
    }, ['item', 'command', 'did', 'next']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: workProgressAdd,
  },
  {
    name: 'work_task_done',
    description: 'Tick "## [ ] Task <n>" in tasks.md. With log, refuses unless that saved verify run passed. Use instead of editing the checkbox.',
    inputSchema: obj({ item: itemRequired, n: { type: 'number', description: 'Task number.' }, log: { type: 'string', description: 'Saved log of the passing verify run.' } }, ['item', 'n']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: workTaskDone,
  },
  {
    name: 'work_fill_results',
    description: 'Fill the result parts of review.md (Reviewed at, Test results, Regression tests, UI checks) or pr.md (Checks: Builds, Unit tests, Regression tests, Review) from what really ran: the runs checks_run recorded for the item and the newest tests/ and ui/ results. Write the file from its template first; everything else in it stays yours. missing lists repos with no recorded run.',
    inputSchema: obj({ item: itemRequired, file: { type: 'string', enum: ['review', 'pr'] } }, ['item', 'file']),
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    run: workFillResults,
  },
  {
    name: 'work_lint',
    description: 'Check a work item\'s files against their templates and what Workshop reads: leftover <placeholders>, missing sections, the Status line, AC ids, task headings, one Verify per task, the file cap, every criterion covered, the review verdict and findings, progress entries and Stats lines, pr.md sections, repos.md. Errors break Workshop or the pipeline; fix them before you finish. file checks one (spec, tasks, review, pr, progress...); without it, every file in the folder.',
    inputSchema: obj({ item: itemRequired, file: { type: 'string', description: 'Optional: one file, for example tasks or review.' } }, ['item']),
    annotations: ro,
    run: workLint,
  },
];
