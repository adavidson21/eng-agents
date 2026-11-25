import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { makeWorkspace, cleanup } from './fixture.mjs';

const server = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'tandem.mjs');

function talk(cwd, messages) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [server], { cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '';
    const want = messages.filter((m) => m.id !== undefined).length;
    child.stdout.on('data', (c) => {
      out += c.toString();
      const got = out.split('\n').filter(Boolean);
      if (got.length >= want) { child.stdin.end(); resolve(got.map((l) => JSON.parse(l)).sort((a, b) => a.id - b.id)); }
    });
    child.on('error', reject);
    setTimeout(() => { child.kill(); reject(new Error(`timed out; got: ${out}`)); }, 20000);
    for (const m of messages) child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', ...m })}\n`);
  });
}

test('MCP: initialize, list tools, call a tool from the workspace root', async () => {
  const { root } = makeWorkspace();
  try {
    const [init, list, call, bad, unknown] = await talk(root, [
      { id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 't', version: '1' } } },
      { method: 'notifications/initialized' },
      { id: 2, method: 'tools/list' },
      { id: 3, method: 'tools/call', params: { name: 'repo_check', arguments: { repo: 'app', item: 'L1' } } },
      { id: 4, method: 'tools/call', params: { name: 'repo_check', arguments: { repo: 'missing' } } },
      { id: 5, method: 'nope' },
    ]);
    assert.equal(init.result.protocolVersion, '2025-03-26');
    assert.equal(init.result.serverInfo.name, 'tandem');
    const names = list.result.tools.map((t) => t.name);
    for (const n of ['repo_check', 'repo_changes', 'repo_merge_check', 'repo_commit', 'checks_list', 'checks_run',
      'ui_app_start', 'ui_app_stop', 'ui_check', 'tests_suite', 'tests_detect', 'tests_ensure_env', 'tests_scaffold']) {
      assert.ok(names.includes(n), n);
    }
    for (const t of list.result.tools) assert.equal(t.inputSchema.type, 'object');
    const r = JSON.parse(call.result.content[0].text);
    assert.equal(r.branchOk, true);
    assert.equal(bad.result.isError, true);
    assert.match(bad.result.content[0].text, /^NOREPO:/);
    assert.equal(unknown.error.code, -32601);
  } finally { cleanup(root); }
});
