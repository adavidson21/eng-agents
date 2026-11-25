import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { makeWorkspace, cleanup, write } from './fixture.mjs';
import { testsDetect, testsEnsureEnv, testsScaffold } from '../lib/ui.mjs';

function angularApp(repo, extra = {}) {
  write(path.join(repo, 'package.json'), JSON.stringify({
    name: 'app',
    scripts: { start: 'ng serve' },
    dependencies: { '@angular/core': '^17.3.0' },
    devDependencies: { karma: '^6.4.0', ...extra },
  }, null, 2));
  write(path.join(repo, 'angular.json'), JSON.stringify({
    projects: { portal: { projectType: 'application', sourceRoot: 'src', architect: { serve: { options: { port: 4300 } } } } },
  }));
  write(path.join(repo, 'src', 'app', 'app.routes.ts'), "export const routes = [{ path: '', component: A }, { path: 'orders/:id', component: B }, { path: '**', redirectTo: '' }];\n");
}

test('tests_detect: Angular app without Playwright', async () => {
  const { root, repo } = makeWorkspace();
  try {
    angularApp(repo);
    const r = await testsDetect({ workspace: root, repo: 'app' });
    assert.equal(r.angular, '^17.3.0');
    assert.equal(r.angularProject.port, 4300);
    assert.equal(r.unitRunner, 'karma');
    assert.equal(r.playwright, null);
    assert.deepEqual(r.routes, ['/', '/orders/:id']);
    assert.ok(r.missing.includes('@playwright/test'));
    assert.ok(r.missing.includes('playwright.config'));
    assert.equal(r.guide.regressionTests.folder, 'e2e/');
  } finally { cleanup(root); }
});

test('tests_ensure_env: writes the config and folder, installs nothing when install is false', async () => {
  const { root, repo } = makeWorkspace();
  try {
    angularApp(repo);
    const r = await testsEnsureEnv({ workspace: root, repo: 'app', install: false });
    const cfg = fs.readFileSync(path.join(repo, 'playwright.config.ts'), 'utf8');
    assert.match(cfg, /testDir: '\.\/e2e'/);
    assert.match(cfg, /npx ng serve --port/);
    assert.match(cfg, /E2E_PORT \?\? 4300/);
    assert.ok(fs.existsSync(path.join(repo, 'e2e')));
    assert.equal(r.steps.find((s) => s.step === '@playwright/test').status, 'needed');
    assert.equal(r.ok, false);
    assert.deepEqual(r.regressionTests, { Command: 'npx playwright test', Runner: 'playwright', Folder: 'e2e/' });

    // Second run changes nothing it already did.
    fs.writeFileSync(path.join(repo, 'playwright.config.ts'), '// mine\n');
    const again = await testsEnsureEnv({ workspace: root, repo: 'app', install: false });
    assert.equal(again.steps.find((s) => s.step === 'playwright.config').status, 'already there');
    assert.equal(fs.readFileSync(path.join(repo, 'playwright.config.ts'), 'utf8'), '// mine\n');
  } finally { cleanup(root); }
});

test('tests_ensure_env: refuses a repo with no package.json', async () => {
  const { root } = makeWorkspace();
  try {
    await assert.rejects(testsEnsureEnv({ workspace: root, repo: 'app', install: false }), /REFUSED/);
  } finally { cleanup(root); }
});

test('tests_scaffold: one failing placeholder test per criterion, never overwrites', async () => {
  const { root, repo } = makeWorkspace();
  try {
    angularApp(repo, { '@playwright/test': '^1.48.0' });
    const args = {
      workspace: root, repo: 'app', file: 'refund-reason', route: '/orders/12',
      criteria: [{ id: 'AC-1', title: 'saves the refund reason' }, { id: 'AC-2', title: "shows the customer's note" }],
    };
    const r = await testsScaffold(args);
    assert.equal(r.file, 'e2e/refund-reason.spec.ts');
    const text = fs.readFileSync(path.join(repo, r.file), 'utf8');
    assert.match(text, /test\('saves the refund reason \[AC-1\]'/);
    assert.match(text, /test\('shows the customer\\'s note \[AC-2\]'/);
    assert.match(text, /page\.route\('\*\*\/api\/\*\*'/);
    assert.match(text, /page\.goto\('\/orders\/12'\)/);
    assert.equal((text.match(/expect\(false/g) || []).length, 2);
    await assert.rejects(testsScaffold(args), /EXISTS/);
    await assert.rejects(testsScaffold({ ...args, file: 'x', criteria: [{ id: '1', title: 'a' }] }), /REFUSED/);
    await assert.rejects(testsScaffold({ ...args, file: '../x' }), /REFUSED/);
  } finally { cleanup(root); }
});
