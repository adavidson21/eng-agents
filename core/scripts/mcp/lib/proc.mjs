// Running programs for the Tandem tools: git with arguments (no shell), and the repo guide's commands (a shell,
// since they are written as one line). Output is captured, capped, and the process tree is killed on timeout.
import { spawn } from 'node:child_process';

const MAX_BYTES = 8 * 1024 * 1024;
export const isWindows = process.platform === 'win32';

export function run(file, args, { cwd, timeoutMs = 120000, env, input } = {}) {
  return new Promise((resolve) => {
    const started = Date.now();
    let out = '';
    let err = '';
    let bytes = 0;
    let timedOut = false;
    let child;
    try {
      child = spawn(file, args, {
        cwd,
        env: { ...process.env, ...(env || {}) },
        windowsHide: true,
        detached: !isWindows,
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (e) {
      resolve({ code: -1, stdout: '', stderr: String(e.message || e), timedOut: false, durationMs: 0, notFound: true });
      return;
    }
    const take = (chunk, which) => {
      bytes += chunk.length;
      if (bytes > MAX_BYTES) return;
      if (which === 'out') out += chunk.toString('utf8');
      else err += chunk.toString('utf8');
    };
    child.stdout.on('data', (c) => take(c, 'out'));
    child.stderr.on('data', (c) => take(c, 'err'));
    const timer = setTimeout(() => {
      timedOut = true;
      killTree(child);
    }, timeoutMs);
    child.on('error', (e) => {
      clearTimeout(timer);
      resolve({ code: -1, stdout: out, stderr: err + String(e.message || e), timedOut, durationMs: Date.now() - started, notFound: e.code === 'ENOENT' });
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code: code === null ? -1 : code, stdout: out, stderr: err, timedOut, durationMs: Date.now() - started });
    });
    if (input) child.stdin.write(input);
    child.stdin.end();
  });
}

function killTree(child) {
  try {
    if (isWindows) spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true });
    else process.kill(-child.pid, 'SIGKILL');
  } catch {
    try { child.kill('SIGKILL'); } catch { /* already gone */ }
  }
}

export function psExe() {
  return process.env.TANDEM_PS || (isWindows ? 'powershell' : 'pwsh');
}

// One command line from a repo guide. Windows: PowerShell, the shell Tandem's commands are written for there.
// Elsewhere: /bin/sh.
export function runShell(command, opts = {}) {
  if (isWindows) {
    const wrapped = `& { ${command} }; if ($LASTEXITCODE) { exit $LASTEXITCODE } elseif (-not $?) { exit 1 }`;
    return run(psExe(), ['-NoProfile', '-NonInteractive', '-Command', wrapped], opts);
  }
  return run('/bin/sh', ['-c', command], opts);
}

export function git(dir, args, opts = {}) {
  return run('git', ['-C', dir, ...args], { timeoutMs: 120000, ...opts, env: { GIT_TERMINAL_PROMPT: '0', ...(opts.env || {}) } });
}

export function lines(text) {
  return String(text || '').split(/\r?\n/).filter((l) => l.length > 0);
}

export function tail(text, count = 40, width = 300) {
  return lines(text).slice(-count).map((l) => (l.length > width ? l.slice(0, width) + '...' : l));
}
