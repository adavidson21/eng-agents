// Reading build, test and lint output into numbers and names. Best effort: dotnet (MSBuild, VSTest), Jest, Vitest,
// Karma (Angular), the Angular/TypeScript compiler and ESLint. Anything not recognised still has its exit code.

const MAX_NAMES = 50;

function uniq(list, max = MAX_NAMES) {
  return [...new Set(list.map((s) => s.trim()).filter(Boolean))].slice(0, max);
}

export function parseOutput(text) {
  const t = String(text || '').replace(/\x1b\[[0-9;]*m/g, '');
  const result = { tests: null, failing: [], errors: [], lint: null };

  // dotnet test: one summary line per test project.
  const dn = [...t.matchAll(/(?:Failed|Passed)!\s*-\s*Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)/g)];
  if (dn.length) {
    const sum = { failed: 0, passed: 0, skipped: 0, total: 0 };
    for (const m of dn) { sum.failed += +m[1]; sum.passed += +m[2]; sum.skipped += +m[3]; sum.total += +m[4]; }
    result.tests = sum;
    result.failing.push(...[...t.matchAll(/^\s*Failed\s+(\S.*?)\s+\[[\d.<>\s]*(?:ms|s|m)\]\s*$/gm)].map((m) => m[1]));
  }

  // Jest: "Tests:       1 failed, 2 skipped, 10 passed, 13 total"
  const jest = [...t.matchAll(/^Tests:\s+(.*?)(\d+) total\s*$/gm)].pop();
  if (!result.tests && jest) {
    const n = (w) => { const m = jest[1].match(new RegExp(`(\\d+) ${w}`)); return m ? +m[1] : 0; };
    result.tests = { failed: n('failed'), passed: n('passed'), skipped: n('skipped') + n('todo'), total: +jest[2] };
    result.failing.push(...[...t.matchAll(/^\s*● (?!Console)(.+?)\s*$/gm)].map((m) => m[1]));
  }

  // Vitest: "Tests  1 failed | 10 passed (11)"
  const vi = [...t.matchAll(/^\s*Tests\s+(.*?)\((\d+)\)\s*$/gm)].pop();
  if (!result.tests && vi && /passed|failed|skipped/.test(vi[1])) {
    const n = (w) => { const m = vi[1].match(new RegExp(`(\\d+) ${w}`)); return m ? +m[1] : 0; };
    result.tests = { failed: n('failed'), passed: n('passed'), skipped: n('skipped') + n('todo'), total: +vi[2] };
    result.failing.push(...[...t.matchAll(/^\s*(?:FAIL|×|✗)\s+(\S.*?\s>\s.+?)\s*$/gm)].map((m) => m[1]));
  }

  // Karma: "Executed 11 of 11 (1 FAILED) (skipped 2)" (the last one wins), or "TOTAL: 1 FAILED, 10 SUCCESS".
  const karma = [...t.matchAll(/Executed (\d+) of (\d+)(?: \((\d+) FAILED\))?(?: \(skipped (\d+)\))?/g)].pop();
  if (!result.tests && karma) {
    const failed = karma[3] ? +karma[3] : 0;
    const executed = +karma[1];
    result.tests = { failed, passed: executed - failed, skipped: karma[4] ? +karma[4] : 0, total: +karma[2] };
    result.failing.push(...[...t.matchAll(/^\s*(?:Headless)?Chrom\w*[^)]*\)\s+(.+?) FAILED\s*$/gm)].map((m) => m[1]));
  }
  const total = t.match(/TOTAL: (\d+) FAILED, (\d+) SUCCESS/);
  if (!result.tests && total) result.tests = { failed: +total[1], passed: +total[2], skipped: 0, total: +total[1] + +total[2] };

  // Compiler errors.
  result.errors.push(...[...t.matchAll(/^(.*?: error [A-Z]+\d+: .*?)(?: \[[^\]]*\])?\s*$/gm)].map((m) => m[1]));
  result.errors.push(...[...t.matchAll(/^.*?(error TS\d+: .*)$/gm)].map((m) => m[1]));
  result.errors.push(...[...t.matchAll(/^\s*✘ \[ERROR\] (.*)$/gm)].map((m) => m[1]));

  // ESLint: "✖ 3 problems (2 errors, 1 warning)"
  const es = t.match(/✖ (\d+) problems? \((\d+) errors?, (\d+) warnings?\)/);
  if (es) result.lint = { problems: +es[1], errors: +es[2], warnings: +es[3] };

  result.failing = uniq(result.failing);
  result.errors = uniq(result.errors, 15);
  return result;
}

// The repo's row in baseline.md: { command, result, failing: [names] | null, count }.
export function baselineRow(text, repo) {
  for (const line of String(text || '').split(/\r?\n/)) {
    const m = line.match(/^\s*\|(.*)\|\s*$/);
    if (!m) continue;
    const cells = m[1].split('|').map((c) => c.trim());
    if (cells[0] !== repo) continue;
    const cell = (cells[3] || '').trim();
    let failing = [];
    let count = 0;
    if (/^none$/i.test(cell) || cell === '') failing = [];
    else if (/^\d+(\s+tests?)?$/i.test(cell)) { failing = null; count = parseInt(cell, 10); }
    else failing = cell.split(',').map((s) => s.replace(/`/g, '').trim()).filter(Boolean);
    if (failing) count = failing.length;
    return { command: (cells[1] || '').replace(/`/g, ''), result: cells[2] || '', failing, count };
  }
  return null;
}

// Failing tests now, split into ones that already failed before the work item and new ones.
export function compareWithBaseline(failingNow, row) {
  if (!row) return { found: false, preExisting: [], new: failingNow };
  if (row.failing === null) {
    return { found: true, preExisting: [], new: failingNow, note: `baseline lists only a count (${row.count}); check names by hand` };
  }
  const before = row.failing.map((s) => s.toLowerCase());
  const pre = [];
  const fresh = [];
  for (const name of failingNow) {
    const n = name.toLowerCase();
    if (before.some((b) => n.includes(b) || b.includes(n))) pre.push(name); else fresh.push(name);
  }
  return { found: true, preExisting: pre, new: fresh };
}
