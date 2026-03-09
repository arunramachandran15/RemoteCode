const fs = require('fs');
const path = require('path');
const os = require('os');

const DEFAULT_REPOS = [
  os.homedir(),
  path.join(os.homedir(), 'Projects'),
  path.join(os.homedir(), 'Developer'),
  path.join(os.homedir(), 'work'),
  path.join(os.homedir(), 'Code'),
  '/Volumes/work',
  '/Volumes/work/NilanTech',
  '/Volumes/work/NilanTech/RemoteCursor',
];

function getConfigPath() {
  const candidates = [
    path.join(__dirname, 'config.json'),
    path.join(process.cwd(), 'config.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return path.join(process.cwd(), 'config.json');
}

function loadRepos() {
  const configPath = getConfigPath();
  let raw = DEFAULT_REPOS;
  if (fs.existsSync(configPath)) {
    try {
      const data = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      if (Array.isArray(data.repos) && data.repos.length > 0) {
        raw = data.repos;
      }
    } catch (_) {}
  }
  const existing = raw.filter((p) => {
    try {
      const s = fs.statSync(p);
      return s.isDirectory();
    } catch {
      return false;
    }
  });
  return existing.length > 0 ? existing : [os.homedir()];
}

const HTTP_PORT = Number(process.env.RC_PORT) || 3847;
const BONJOUR_SERVICE_TYPE = 'remotecursor'; // _remotecursor._tcp

module.exports = {
  loadRepos,
  HTTP_PORT,
  BONJOUR_SERVICE_TYPE,
  getConfigPath,
};
