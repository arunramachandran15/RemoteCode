# Remote Cursor

Control Cursor’s agent from your iPhone over **Bluetooth** or **Wi‑Fi**.

- **Mac**: Run the bridge app; it advertises over Bluetooth/Wi‑Fi and runs the Cursor agent for a chosen repo.
- **iOS**: Open the app, choose “Find Mac” (Bluetooth/Wi‑Fi) or “Wi‑Fi (URL)”, then pick a repo and send messages to the agent.

## Requirements

- Mac with [Cursor](https://cursor.com) and **Cursor CLI** (`agent` in PATH). Install from Cursor: **Cursor → Install CLI** or [Cursor CLI docs](https://cursor.com/docs/cli/overview).
- iPhone and Mac on the same network (for Wi‑Fi URL), or use “Find Mac” for Bluetooth / peer-to-peer Wi‑Fi (no router needed).
- Repo paths on the Mac added in the bridge config (see below).

## Mac bridge (run on your Mac)

1. Open `RemoteCursorBridge` in Xcode.
2. Edit **Config** (or `config.json` next to the app) and add your repo paths, e.g.:
   - `/Volumes/work/NilanTech/MyProject`
3. Build and run. The bridge will:
   - Listen for HTTP on **port 3847** (Wi‑Fi).
   - Advertise as **Remote Cursor** over Bluetooth/Wi‑Fi for the iOS app to find.

Get your Mac’s IP (Wi‑Fi): **System Settings → Network → Wi‑Fi → Details** (or run `ipconfig getifaddr en0` in Terminal).

### Node.js bridge (same API + Bonjour)

You can run a **Node.js** bridge with the same HTTP API so the **same iOS app** works without changes:

```bash
cd RemoteCursorBridgeNode && npm install && npm start
```

- Listens on port **3847** (or `RC_PORT`).
- Advertises **Bonjour** (`_remotecursor._tcp`). In the app use **Find Mac (Bonjour)** to discover and connect.
- Or use **Wi‑Fi (URL)** with `http://<Mac-IP>:3847` as with the Swift bridge.

See [RemoteCursorBridgeNode/README.md](RemoteCursorBridgeNode/README.md) for config and API details.

## iOS app

1. Open `RemoteCursorApp` in Xcode.
2. Build and run on your iPhone (or simulator for Wi‑Fi only; Bluetooth/peer discovery works best on device).
3. **Connect**:
   - **Find Mac (Bluetooth / Wi‑Fi)**: Tap “Find Mac”, then select your Mac (Swift bridge). No URL needed.
   - **Find Mac (Bonjour)**: Tap “Find Mac (Bonjour)” to discover a Node.js bridge on the network, then tap it to connect.
   - **Wi‑Fi (URL)**: Enter `http://<Mac IP>:3847` and connect (works with Swift or Node bridge).
4. Pick a repo and type a message; tap **Send** to run the agent and see the reply.

## Connection types

| Method        | Transport           | Use when                          |
|---------------|---------------------|-----------------------------------|
| **Find Mac**  | Bluetooth / P2P Wi‑Fi | Same room; no router or IP needed |
| **Wi‑Fi (URL)** | Wi‑Fi (LAN)       | Mac and iPhone on same Wi‑Fi      |

Both options talk to the same bridge: **Find Mac** uses Apple’s MultipeerConnectivity (Bluetooth or peer-to-peer Wi‑Fi); **Wi‑Fi (URL)** uses HTTP over your local network.

---

## Troubleshooting: iPhone can’t find or connect to Mac

For **how to verify from the iPhone/simulator and view debug logs**, see **[DEBUGGING.md](DEBUGGING.md)** (Safari health check, Xcode console, Console.app).

### 1. **Bridge must be running on the Mac**
- Run **RemoteCursorBridge** (CLI) or **RemoteCursorBridgeApp** (desktop app).
- You should see “HTTP: Listening on port 3847” and “Peer: Advertising…” in the log/terminal.

### 2. **Try Wi‑Fi (URL) first** (easiest to verify)
- On Mac: get IP with `ipconfig getifaddr en0` (or System Settings → Network → Wi‑Fi → Details).
- On iPhone: in the app choose **Wi‑Fi (URL)** and enter `http://<that-IP>:3847` (e.g. `http://192.168.1.5:3847`), then tap **Connect via Wi‑Fi**.
- **Quick test**: On iPhone Safari open `http://<Mac-IP>:3847/health`. You should see `{"ok":true}`. If that fails, the problem is network/firewall, not the app.

### 3. **macOS Firewall**
- **System Settings → Network → Firewall** (or Security & Privacy → Firewall).
- If Firewall is On: click **Options** and either **Allow** “RemoteCursorBridgeApp” (or the CLI binary), or turn off firewall temporarily to test.
- When you first run the bridge app, if macOS asks “Allow incoming connections?”, choose **Allow**.

### 4. **iPhone and Mac on the same network** (for Wi‑Fi URL)
- Both must be on the same Wi‑Fi (or same subnet). If the Mac is on Ethernet and iPhone on Wi‑Fi from the same router, that’s usually fine.
- Avoid VPNs or “client isolation” on the router that blocks device-to-device traffic.

### 5. **iOS permissions** (for “Find Mac” and local discovery)
- **Settings → Remote Cursor → Local Network** must be **ON**.
- **Settings → Remote Cursor → Bluetooth** must be allowed if you use “Find Mac”.
- If you previously denied: delete the app, reinstall, and allow when prompted. Or turn **Local Network** and **Bluetooth** back on for Remote Cursor in Settings.

### 6. **“Find Mac” (Bluetooth / peer)**
- Turn **Bluetooth ON** on both iPhone and Mac.
- Keep the app in the **foreground** on the iPhone and tap **Find Mac**; wait a few seconds for your Mac name to appear.
- Ensure the **bridge is running** on the Mac and that you’ve allowed any firewall prompt for it.

### 7. **Port 3847**
- The bridge uses **port 3847**. Nothing else should be using it. If you changed the port in `Config`, use that port in the URL and in the health check.
