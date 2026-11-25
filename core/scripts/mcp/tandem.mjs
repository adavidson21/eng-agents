#!/usr/bin/env node
// Tandem's local MCP server: repo, checks, UI and test tools for opencode, over stdio (one JSON-RPC message per
// line). No dependencies, no network listener. install.ps1 adds it to opencode.json as the "tandem" server; opencode
// starts it from the workspace root, so tools take repo folder names and work item ids, not paths.
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { TOOLS } from './lib/tools.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const SUPPORTED = ['2025-06-18', '2025-03-26', '2024-11-05'];

function version() {
  for (const p of [path.join(here, '..', '..', 'VERSION'), path.join(here, '..', '..', 'manifest.json')]) {
    try {
      const t = fs.readFileSync(p, 'utf8');
      if (p.endsWith('VERSION')) return t.trim();
      const m = JSON.parse(t);
      if (m.components && m.components.core && m.components.core.version) return m.components.core.version;
    } catch { /* try the next */ }
  }
  return '0.0.0';
}

function send(msg) {
  process.stdout.write(`${JSON.stringify(msg)}\n`);
}

export async function callTool(name, args) {
  const tool = TOOLS.find((t) => t.name === name);
  if (!tool) return { content: [{ type: 'text', text: `NOTOOL: no tool named ${name}` }], isError: true };
  try {
    const result = await tool.run(args || {});
    return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
  } catch (e) {
    const text = e && e.code ? e.message : `FAILED: ${(e && e.message) || e}`;
    return { content: [{ type: 'text', text }], isError: true };
  }
}

async function handle(msg) {
  const { id, method, params } = msg;
  const reply = (result) => { if (id !== undefined) send({ jsonrpc: '2.0', id, result }); };
  const fail = (code, message) => { if (id !== undefined) send({ jsonrpc: '2.0', id, error: { code, message } }); };
  switch (method) {
    case 'initialize': {
      const asked = params && params.protocolVersion;
      reply({
        protocolVersion: SUPPORTED.includes(asked) ? asked : SUPPORTED[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'tandem', version: version() },
        instructions: 'Tandem\'s repo, checks, UI and test tools. Use them instead of the matching git, build, test and script command lines; the commands say when.',
      });
      return;
    }
    case 'ping':
      reply({});
      return;
    case 'tools/list':
      reply({ tools: TOOLS.map(({ name, description, inputSchema, annotations }) => ({ name, description, inputSchema, annotations })) });
      return;
    case 'tools/call':
      reply(await callTool(params && params.name, params && params.arguments));
      return;
    default:
      if (method && method.startsWith('notifications/')) return;
      fail(-32601, `Method not found: ${method}`);
  }
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', (line) => {
    if (!line.trim()) return;
    let msg;
    try { msg = JSON.parse(line); } catch { send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }); return; }
    Promise.resolve(handle(msg)).catch((e) => {
      if (msg && msg.id !== undefined) send({ jsonrpc: '2.0', id: msg.id, error: { code: -32603, message: String((e && e.message) || e) } });
    });
  });
  rl.on('close', () => process.exit(0));
}
