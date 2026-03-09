const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');

// Cache agent path so we don't run execSync('which agent') on every request (saves 50–200ms per request).
let cachedAgentPath = null;

function findAgent() {
  if (cachedAgentPath) return cachedAgentPath;
  const pathEnv = [
    path.join(os.homedir(), '.local', 'bin'),
    '/usr/local/bin',
    '/opt/homebrew/bin',
    '/usr/bin',
    process.env.PATH || '',
  ].join(':');
  try {
    const { execSync } = require('child_process');
    const out = execSync('which agent', { encoding: 'utf8', env: { ...process.env, PATH: pathEnv } });
    const p = out.trim();
    if (p && fs.existsSync(p)) {
      cachedAgentPath = p;
      return p;
    }
  } catch (_) {}
  const candidates = [
    path.join(os.homedir(), '.local', 'bin', 'agent'),
    '/usr/local/bin/agent',
    '/opt/homebrew/bin/agent',
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      cachedAgentPath = p;
      return p;
    }
  }
  return null;
}

function agentEnv() {
  return {
    ...process.env,
    CURSOR_TRUST_WORKSPACE: '1',
    VSCODE_SKIP_WORKSPACE_TRUST: '1',
  };
}

/**
 * Run agent with streaming. Same semantics as Swift AgentRunner.runStreaming.
 * onChunk(delta) for each text delta; returns { output, error, sessionId }.
 */
function runStreaming(workspace, message, sessionId, onChunk) {
  const agentPath = findAgent();
  if (!agentPath) {
    return {
      output: null,
      error: 'Cursor CLI (agent) not found. Install from Cursor → Install CLI, then restart the bridge.',
      sessionId: null,
    };
  }

  let fullOutput = '';
  let sid = sessionId;
  const args = sid
    ? ['--resume', sid, '-p', message, '--trust', '--workspace', workspace, '--output-format', 'stream-json', '--stream-partial-output']
    : ['-p', message, '--trust', '--workspace', workspace, '--output-format', 'stream-json', '--stream-partial-output'];

  return new Promise((resolve) => {
    const proc = spawn(agentPath, args, {
      cwd: workspace,
      env: agentEnv(),
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let buffer = '';
    function processLine(line) {
      line = line.trim();
      if (!line) return;
      try {
        const json = JSON.parse(line);
        const type = json.type;
        if (type === 'result' && json.subtype === 'success') {
          if (json.result) fullOutput = json.result;
          if (json.session_id) sid = json.session_id;
          return;
        }
        if (type === 'assistant' && json.message && Array.isArray(json.message.content)) {
          for (const part of json.message.content) {
            if (part.type === 'text' && part.text) {
              fullOutput += part.text;
              if (onChunk) onChunk(part.text);
            }
          }
          return;
        }
        const text = json.text || json.content || json.delta;
        if (text) {
          fullOutput += text;
          if (onChunk) onChunk(text);
        }
      } catch (_) {}
    }

    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', (chunk) => {
      buffer += chunk;
      let idx;
      while ((idx = buffer.indexOf('\n')) !== -1) {
        processLine(buffer.slice(0, idx));
        buffer = buffer.slice(idx + 1);
      }
    });

    let stderr = '';
    proc.stderr.setEncoding('utf8');
    proc.stderr.on('data', (d) => { stderr += d; });

    proc.on('close', (code) => {
      buffer.split('\n').forEach(processLine);
      let err = stderr.trim();
      if (err.includes('No such file or directory') || err.includes('not found')) {
        err = 'Cursor CLI (agent) not found. Install from Cursor → Install CLI. Restart the bridge.';
      }
      if ((fullOutput + ' ' + err).toLowerCase().includes('trust') && !err) {
        err = `Workspace trust required. Open '${workspace}' in Cursor on your Mac and click 'Trust' in the dialog, then try again.`;
      }
      resolve({
        output: fullOutput || null,
        error: code !== 0 ? (err || `Exit code ${code}`) : (err || null),
        sessionId: sid,
      });
    });
  });
}

function run(workspace, message, sessionId) {
  return runStreaming(workspace, message, sessionId, () => {});
}

module.exports = { findAgent, runStreaming, run };
