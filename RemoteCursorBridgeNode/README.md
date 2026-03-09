# Remote Cursor Bridge (Node.js)

Same HTTP API as the Swift bridge so the **same iOS app** can connect via Wi‑Fi URL or by discovering this bridge via Bonjour.

## Requirements

- Node.js 18+
- Cursor with CLI (`agent` in PATH). Install from Cursor: **Cursor → Install CLI**.

## Quick start

```bash
cd RemoteCursorBridgeNode
npm install
npm start
```

- HTTP server listens on **port 3847** (or `RC_PORT` env).
- Bonjour advertises `_remotecursor._tcp` so the app can use **Find Mac (Bonjour)**.

## Config

- **Repos**: Create `config.json` next to `server.js` or in the current working directory:
  ```json
  { "repos": ["/path/to/repo1", "/path/to/repo2"] }
  ```
- If no config, default repo paths (home, Projects, etc.) are used.

## iOS app

- **Wi‑Fi (URL)**: Enter `http://<Mac-IP>:3847` and connect — same as with the Swift bridge.
- **Find Mac (Bonjour)**: Tap "Find Mac (Bonjour)", pick the advertised bridge, then connect. The app uses the same HTTP API (same signatures).

## API (same as Swift bridge)

| Method | Path | Body / Query | Response |
|--------|------|--------------|----------|
| GET | `/health` | — | `{ "ok": true }` |
| GET | `/repos` | — | `{ "repos": string[] }` |
| POST | `/agent` | `{ workspace, message, sessionId? }` | `{ output?, error?, sessionId? }` |
| POST | `/agent/stream` | same | NDJSON: `{ delta }` then `{ done, output?, error?, sessionId? }` |
| GET | `/files` | `?path=` | `{ files: [] }` or `{ error, files: [] }` |
| GET | `/file` | `?path=` | `{ content, path }` or `{ error }` |
| POST | `/file` | `{ path, content }` | `{ ok }` or `{ error }` |
| POST | `/run` | `{ command, workspace? }` | `{ stdout, stderr, exitCode }` |
| POST | `/upload-image` | `{ data: base64 }` or raw | `{ path, ok }` or `{ error }` |
| POST | `/trust-workspace` | `{ workspace }` | `{ ok, message }` |
