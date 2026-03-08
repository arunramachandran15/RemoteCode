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

## iOS app

1. Open `RemoteCursorApp` in Xcode.
2. Build and run on your iPhone (or simulator for Wi‑Fi only; Bluetooth/peer discovery works best on device).
3. **Connect**:
   - **Find Mac (Bluetooth / Wi‑Fi)**: Tap “Find Mac”, then select your Mac. No URL needed.
   - **Wi‑Fi (URL)**: Enter `http://<Mac IP>:3847` and connect.
4. Pick a repo and type a message; tap **Send** to run the agent and see the reply.

## Connection types

| Method        | Transport           | Use when                          |
|---------------|---------------------|-----------------------------------|
| **Find Mac**  | Bluetooth / P2P Wi‑Fi | Same room; no router or IP needed |
| **Wi‑Fi (URL)** | Wi‑Fi (LAN)       | Mac and iPhone on same Wi‑Fi      |

Both options talk to the same bridge: **Find Mac** uses Apple’s MultipeerConnectivity (Bluetooth or peer-to-peer Wi‑Fi); **Wi‑Fi (URL)** uses HTTP over your local network.
