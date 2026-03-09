# Debugging: Check connection from iPhone / Simulator

Ways to confirm the Mac bridge is reachable and to see what’s going wrong when it isn’t.

---

## 1. Quick check from iPhone (no app)

**Safari on iPhone**

1. iPhone and Mac on the **same Wi‑Fi**.
2. On Mac: get your IP (e.g. **System Settings → Network → Wi‑Fi → Details**, or Terminal: `ipconfig getifaddr en0`).
3. On iPhone: open Safari and go to:
   ```text
   http://<Mac-IP>:3847/health
   ```
   Example: `http://10.0.0.214:3847/health`
4. You should see: `{"ok":true}`

- **If you see that** → Network and bridge are fine; the app should be able to connect via “Wi‑Fi (URL)” with the same base URL (e.g. `http://10.0.0.214:3847`).
- **If it fails** → Likely firewall, wrong IP, or iPhone not on same network. See [Troubleshooting in README](README.md#troubleshooting-iphone-cant-find-or-connect-to-mac).

---

## 2. Run the app from Xcode and watch the console (best for debugging)

**iPhone or Simulator**

1. Open **RemoteCursorApp** in Xcode.
2. Choose your **iPhone** or **iPhone Simulator** as the run destination.
3. Run the app (**⌘R**).
4. Leave the **Xcode debug console** open (View → Debug Area → Activate Console, or **⌘⇧C**).
5. In the app:
   - **Wi‑Fi**: Enter Mac URL and tap “Connect via Wi‑Fi”.
   - **Find Mac**: Tap “Find Mac” and wait (or tap a discovered Mac).

You’ll see lines like:

- **Wi‑Fi**
  - `[RemoteCursor HH:mm:ss] healthCheck: GET http://10.0.0.214:3847/health`
  - `[RemoteCursor HH:mm:ss] healthCheck: OK` or `healthCheck: error ...` / `healthCheck: failed (non-200)`
  - `[RemoteCursor HH:mm:ss] getRepos: GET http://...` when loading repos
- **Find Mac**
  - `[RemoteCursor HH:mm:ss] Peer: startBrowsing (serviceType=remotecursor)`
  - `[RemoteCursor HH:mm:ss] Peer: found Mac "Your Mac Name"`
  - `[RemoteCursor HH:mm:ss] Peer: inviting Your Mac Name`
  - `[RemoteCursor HH:mm:ss] Peer: session state=connecting peer=...` then `state=connected` or `state=notConnected`
  - If browsing fails: `Peer: didNotStartBrowsing error=...`

Use these to see:

- Whether the health check URL is correct and if the request succeeds or fails.
- Whether the Mac is discovered and whether the session reaches `connected` or stays `notConnected`.

---

## 3. View logs when the app is not running from Xcode (real device)

**Console.app on Mac (device connected by cable)**

1. Connect the **iPhone with a cable** to the Mac.
2. On iPhone: run the **RemoteCursor** app (from home screen or Xcode, then stop debugging so the app runs without Xcode).
3. On Mac: open **Console.app** (Applications → Utilities → Console).
4. Select your **iPhone** in the left sidebar.
5. In the search/filter box, type: **RemoteCursor** (or the app’s bundle ID).
6. Reproduce the issue (e.g. tap “Connect via Wi‑Fi” or “Find Mac”).

You’ll see the same `[RemoteCursor ...]` lines as in the Xcode console. Useful when the app is installed from TestFlight or run without Xcode.

---

## 4. Simulator vs real device

| Check | Simulator | Real device |
|-------|-----------|-------------|
| **Wi‑Fi (URL)** | Works: simulator uses Mac’s network. Use your Mac’s LAN IP (e.g. `http://10.0.0.214:3847`). `localhost` from simulator points to the simulator, not the Mac. | Same: use Mac’s LAN IP. iPhone must be on same Wi‑Fi as Mac. |
| **Find Mac (Multipeer)** | Often does **not** discover the Mac (simulator has limited MultipeerConnectivity). | Use a **real iPhone** to test “Find Mac”. |

So: use **Simulator** to debug **Wi‑Fi (URL)**; use a **real device** to debug **Find Mac**.

---

## 5. What to look for in logs

- **healthCheck: invalid URL base=...**  
  The URL you entered is malformed (e.g. missing `http://`). App normalizes it in code; if you still see this, the base is wrong.

- **healthCheck: error The Internet connection appears to be offline** (or similar)  
  Device has no network, or can’t reach that IP. Check Wi‑Fi and that you’re using the Mac’s IP, not `localhost`.

- **healthCheck: failed (non-200)**  
  Server responded but not HTTP 200. Check bridge is the app listening on 3847 (not another process).

- **Peer: didNotStartBrowsing error=...**  
  Multipeer browsing failed (e.g. Bluetooth off, or permission denied). Enable Bluetooth and **Settings → Remote Cursor → Local Network** (and Bluetooth if needed).

- **Peer: found Mac "..."** but no **session state=connected**  
  Mac was found but connection failed (invitation declined, timeout, or network). Ensure bridge is running and, on Mac, that you accepted or allowed the connection if a prompt appears.

- **Peer: session state=notConnected**  
  Connection dropped. Check both devices stay in range and that neither app was killed.

---

## 6. Bridge side (Mac)

When the iOS app connects:

- **Desktop bridge app**: Log window shows lines like `HTTP: GET /health`, `HTTP: GET /repos`, `HTTP: POST /agent`, and for Multipeer: “Peer: Connected to …”.
- **CLI bridge**: Same lines go to the terminal where you started the bridge.

If you see no `HTTP: GET /health` when tapping “Connect via Wi‑Fi”, the request never reached the Mac (firewall, wrong IP, or network). If you see `/health` but the app still says “Could not reach Mac”, check the response (e.g. bridge might be returning an error status).
