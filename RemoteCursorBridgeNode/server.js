#!/usr/bin/env node
const express = require('express');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { exec } = require('child_process');
const { loadRepos, HTTP_PORT, BONJOUR_SERVICE_TYPE } = require('./config');
const { run, runStreaming } = require('./agentRunner');

const app = express();
app.use(express.json({ limit: '50mb' }));
app.use(express.raw({ type: 'application/octet-stream', limit: '50mb' }));

// Log requests (same as Swift bridge)
app.use((req, res, next) => {
  console.log(`HTTP: ${req.method} ${req.path}`);
  next();
});

// GET /health
app.get('/health', (req, res) => {
  res.json({ ok: true });
});

// GET /repos
app.get('/repos', (req, res) => {
  const repos = loadRepos();
  res.json({ repos });
});

// POST /agent (non-streaming)
app.post('/agent', async (req, res) => {
  const { workspace, message, sessionId } = req.body || {};
  if (!workspace || !message) {
    return res.status(400).json({ error: 'Missing workspace or message' });
  }
  try {
    const { output, error, sessionId: sid } = await run(workspace, message, sessionId);
    const body = { output, error };
    if (sid) body.sessionId = sid;
    res.json(body);
  } catch (e) {
    res.status(500).json({ error: String(e.message) });
  }
});

// POST /agent/stream — NDJSON: { delta } lines then { done: true, output?, error?, sessionId? }
app.post('/agent/stream', async (req, res) => {
  const { workspace, message, sessionId } = req.body || {};
  if (!workspace || !message) {
    return res.status(400).json({ error: 'Missing workspace or message' });
  }
  res.setHeader('Content-Type', 'application/x-ndjson');
  res.setHeader('Transfer-Encoding', 'chunked');
  res.flushHeaders && res.flushHeaders();

  const sendLine = (obj) => {
    res.write(JSON.stringify(obj) + '\n');
    if (res.flush) res.flush();
  };

  try {
    const result = await runStreaming(workspace, message, sessionId, (delta) => {
      sendLine({ delta });
    });
    sendLine({
      done: true,
      output: result.output,
      error: result.error,
      ...(result.sessionId && { sessionId: result.sessionId }),
    });
  } catch (e) {
    sendLine({ done: true, output: null, error: String(e.message) });
  }
  res.end();
});

// GET /files?path=
app.get('/files', (req, res) => {
  const dirPath = req.query.path;
  if (!dirPath) return res.status(400).json({ error: 'Missing path', files: [] });
  try {
    const stat = fs.statSync(dirPath);
    if (!stat.isDirectory()) {
      return res.json({ error: 'Not a directory', files: [] });
    }
    const names = fs.readdirSync(dirPath).sort();
    const files = names
      .filter((n) => !n.startsWith('.'))
      .map((name) => {
        const full = path.join(dirPath, name);
        const s = fs.statSync(full);
        const entry = { name, path: full, isDirectory: s.isDirectory() };
        if (!s.isDirectory()) entry.size = s.size;
        return entry;
      });
    res.json({ files });
  } catch (e) {
    res.json({ error: e.message || 'Cannot read directory', files: [] });
  }
});

// GET /file?path=
app.get('/file', (req, res) => {
  const filePath = req.query.path;
  if (!filePath) return res.status(400).json({ error: 'Missing path' });
  try {
    if (!fs.existsSync(filePath)) return res.json({ error: 'File not found' });
    const content = fs.readFileSync(filePath, 'utf8');
    res.json({ content, path: filePath });
  } catch (e) {
    res.json({ error: e.code === 'ENOENT' ? 'File not found' : (e.message || 'Cannot read file') });
  }
});

// POST /file — body: { path, content }
app.post('/file', (req, res) => {
  const { path: filePath, content } = req.body || {};
  if (!filePath || content === undefined) {
    return res.status(400).json({ error: 'Missing path or content' });
  }
  try {
    fs.writeFileSync(filePath, String(content), 'utf8');
    res.json({ ok: true });
  } catch (e) {
    res.json({ error: e.message });
  }
});

// POST /run — body: { command, workspace? }
app.post('/run', (req, res) => {
  const { command, workspace } = req.body || {};
  if (!command) return res.status(400).json({ error: 'Missing command' });
  const cwd = workspace && fs.existsSync(workspace) ? workspace : undefined;
  exec(command, { cwd, shell: '/bin/zsh', maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
    const exitCode = err && err.code != null ? err.code : 0;
    res.json({ stdout: stdout || '', stderr: stderr || '', exitCode });
  });
});

// POST /upload-image — body: { data: base64 } or raw binary
app.post('/upload-image', (req, res) => {
  let imageData = Buffer.isBuffer(req.body) ? req.body : null;
  if (!imageData && req.body && typeof req.body === 'object' && req.body.data) {
    imageData = Buffer.from(req.body.data, 'base64');
  }
  if (!imageData || imageData.length === 0) {
    return res.status(400).json({ error: 'No image data' });
  }
  const cacheDir = path.join(os.tmpdir(), 'remotecursor_images');
  fs.mkdirSync(cacheDir, { recursive: true });
  const filename = `img_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}.jpg`;
  const filePath = path.join(cacheDir, filename);
  try {
    fs.writeFileSync(filePath, imageData);
    res.json({ path: filePath, ok: true });
  } catch (e) {
    res.json({ error: e.message });
  }
});

// POST /trust-workspace — body: { workspace }
app.post('/trust-workspace', (req, res) => {
  const { workspace } = req.body || {};
  if (!workspace) return res.status(400).json({ error: 'Missing workspace' });
  const home = os.homedir();
  const settingsPath = path.join(home, 'Library', 'Application Support', 'Cursor', 'User', 'settings.json');
  let msg = 'Trust applied. If the agent still rejects, click Trust in the Cursor window on your Mac.';
  if (fs.existsSync(settingsPath)) {
    try {
      const data = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      data['security.workspace.trust.enabled'] = false;
      fs.writeFileSync(settingsPath, JSON.stringify(data, null, 2));
      msg += ' Disabled workspace trust in settings.';
    } catch (_) {}
  }
  res.json({ ok: true, message: msg });
});

// 404
app.use((req, res) => {
  res.status(404).send('Not Found');
});

const server = app.listen(HTTP_PORT, () => {
  console.log(`HTTP: Listening on port ${HTTP_PORT} (Wi‑Fi)`);

  // Bonjour: advertise _remotecursor._tcp so iOS can discover this bridge
  try {
    const Bonjour = require('bonjour')();
    Bonjour.publish({
      name: 'Remote Cursor Bridge',
      type: BONJOUR_SERVICE_TYPE,
      port: HTTP_PORT,
    });
    console.log(`Bonjour: Advertising _${BONJOUR_SERVICE_TYPE}._tcp on port ${HTTP_PORT}`);
  } catch (e) {
    console.warn('Bonjour: Could not advertise:', e.message);
  }
});

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
