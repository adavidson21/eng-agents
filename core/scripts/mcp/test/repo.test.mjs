import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { makeWorkspace, cleanup, sh, write } from './fixture.mjs';
import { repoCheck, repoChanges, repoMergeCheck, repoCommit } from '../lib/repo.mjs';

test('repo_check: branch matches repos.md, clean, base found', async () => {
  const { root } = makeWorkspace();
  try {
    const r = await repoCheck({ workspace: root, repo: 'app', item: 'L1' });
    assert.equal(r.branch, 'dev/feature/L1-thing');
    assert.equal(r.branchOk, true);
    assert.equal(r.clean, true);
    assert.equal(r.base, 'main');
    assert.equal(r.baseFound, true);
    assert.equal(r.ok, true);
  } finally { cleanup(root); }
});

test('repo_check: wrong branch and dirty files are problems', async () => {
  const { root, repo } = makeWorkspace();
  try {
    sh(repo, 'checkout', '-q', 'main');
    write(path.join(repo, 'new.txt'), 'x');
    const r = await repoCheck({ workspace: root, repo: 'app', item: 'L1' });
    assert.equal(r.branchOk, false);
    assert.equal(r.clean, false);
    assert.equal(r.ok, false);
    assert.equal(r.problems.length, 2);
    assert.deepEqual(r.uncommitted.map((u) => u.path), ['new.txt']);
  } finally { cleanup(root); }
});

test('repo_check: unknown repo and bad names are refused', async () => {
  const { root } = makeWorkspace();
  try {
    await assert.rejects(repoCheck({ workspace: root, repo: 'nope' }), /NOREPO/);
    await assert.rejects(repoCheck({ workspace: root, repo: '../app' }), /NOREPO/);
    await assert.rejects(repoCheck({ workspace: root, repo: 'app', item: 'L9' }), /NOITEM/);
  } finally { cleanup(root); }
});

test('repo_changes: commits, files, totals and one file diff', async () => {
  const { root, repo } = makeWorkspace();
  try {
    write(path.join(repo, 'feature.txt'), 'a\nb\n');
    sh(repo, 'add', 'feature.txt');
    sh(repo, 'commit', '-q', '-m', 'Add feature');
    const r = await repoChanges({ workspace: root, repo: 'app', item: 'L1', file: 'feature.txt' });
    assert.equal(r.commits.length, 1);
    assert.equal(r.commits[0].subject, 'Add feature');
    assert.deepEqual(r.files, [{ path: 'feature.txt', status: 'A', added: 2, removed: 0 }]);
    assert.equal(r.stat.insertions, 2);
    assert.match(r.diff.text, /\+a/);
  } finally { cleanup(root); }
});

test('repo_merge_check: up to date, clean, and conflicting', async () => {
  const { root, repo } = makeWorkspace();
  try {
    let r = await repoMergeCheck({ workspace: root, repo: 'app', item: 'L1', fetch: false });
    assert.equal(r.upToDate, true);

    sh(repo, 'checkout', '-q', 'main');
    write(path.join(repo, 'other.txt'), 'x\n');
    sh(repo, 'add', 'other.txt');
    sh(repo, 'commit', '-q', '-m', 'other');
    sh(repo, 'checkout', '-q', 'dev/feature/L1-thing');
    r = await repoMergeCheck({ workspace: root, repo: 'app', item: 'L1', fetch: false });
    assert.equal(r.behind, 1);
    assert.equal(r.clean, true);

    sh(repo, 'checkout', '-q', 'main');
    write(path.join(repo, 'shared.txt'), 'one\nMAIN\nthree\n');
    sh(repo, 'commit', '-q', '-am', 'main edit');
    sh(repo, 'checkout', '-q', 'dev/feature/L1-thing');
    write(path.join(repo, 'shared.txt'), 'one\nBRANCH\nthree\n');
    sh(repo, 'commit', '-q', '-am', 'branch edit');
    const head = sh(repo, 'rev-parse', 'HEAD');
    r = await repoMergeCheck({ workspace: root, repo: 'app', item: 'L1', fetch: false });
    assert.equal(r.clean, false);
    assert.deepEqual(r.conflicts, ['shared.txt']);
    assert.equal(sh(repo, 'rev-parse', 'HEAD'), head, 'nothing changed');
    assert.equal(sh(repo, 'status', '--porcelain'), '');
  } finally { cleanup(root); }
});

test('repo_commit: commits only the named files', async () => {
  const { root, repo } = makeWorkspace();
  try {
    write(path.join(repo, 'a.txt'), 'a');
    write(path.join(repo, 'b.txt'), 'b');
    const r = await repoCommit({ workspace: root, repo: 'app', item: 'L1', files: ['a.txt'], message: 'Add a' });
    assert.deepEqual(r.files, ['a.txt']);
    assert.deepEqual(r.stillUncommitted, ['b.txt']);
    assert.equal(sh(repo, 'log', '-1', '--format=%s'), 'Add a');
    assert.equal(sh(repo, 'show', '--name-only', '--format=', 'HEAD'), 'a.txt');
  } finally { cleanup(root); }
});

test('repo_commit: refusals', async () => {
  const { root, repo } = makeWorkspace();
  try {
    write(path.join(repo, 'a.txt'), 'a');
    const base = { workspace: root, repo: 'app', item: 'L1' };
    await assert.rejects(repoCommit({ ...base, files: ['a.txt'], message: 'two\nlines' }), /REFUSED: message must be one line/);
    await assert.rejects(repoCommit({ ...base, files: [], message: 'x' }), /REFUSED: name the files/);
    await assert.rejects(repoCommit({ ...base, files: ['../outside.txt'], message: 'x' }), /REFUSED: .* not a path inside/);
    await assert.rejects(repoCommit({ ...base, files: ['shared.txt'], message: 'x' }), /REFUSED: no changes in: shared.txt/);
    write(path.join(repo, 'b.txt'), 'b');
    sh(repo, 'add', 'b.txt');
    await assert.rejects(repoCommit({ ...base, files: ['a.txt'], message: 'x' }), /REFUSED: other files are already staged: b.txt/);
    sh(repo, 'reset', '-q');
    sh(repo, 'checkout', '-q', 'main');
    await assert.rejects(repoCommit({ ...base, files: ['a.txt'], message: 'x' }), /REFUSED: on main, but repos.md says/);
    await assert.rejects(repoCommit({ workspace: root, repo: 'app', files: ['a.txt'], message: 'x' }), /REFUSED: on main; commits go/);
  } finally { cleanup(root); }
});

test('worktree: repos.md Path is where git runs', async () => {
  const { root, repo } = makeWorkspace();
  try {
    sh(repo, 'checkout', '-q', 'main');
    const wt = path.join(root, '.worktrees', 'L1-thing', 'app');
    sh(repo, 'worktree', 'add', '-q', wt, 'dev/feature/L1-thing');
    const md = path.join(root, '.work', 'L1-thing', 'repos.md');
    fs.writeFileSync(md, fs.readFileSync(md, 'utf8').replace('| main | |', '| main | .worktrees/L1-thing/app |'));
    const r = await repoCheck({ workspace: root, repo: 'app', item: 'L1' });
    assert.equal(r.workingIn, '.worktrees/L1-thing/app');
    assert.equal(r.branchOk, true);
  } finally { cleanup(root); }
});
