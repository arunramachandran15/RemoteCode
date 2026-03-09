# Node Bridge Menubar App

macOS **menubar app** to run the Node.js bridge in the background and **enable/disable** it from the menu.

## Build

1. Open **RemoteCursorBridge.xcodeproj** (in `RemoteCursorBridge/`).
2. Select the **NodeBridgeMenu** scheme.
3. Build and run (⌘R).

The app appears in the **menu bar** (network icon). It does not show in the Dock (`LSUIElement`).

## Use

- **Click the menubar icon** → menu:
  - **Start Bridge** / **Stop Bridge** — turn the Node bridge on or off.
  - **Set Bridge Path…** — choose the `RemoteCursorBridgeNode` folder (the one that contains `server.js` and `package.json`). Required the first time, or if the app can’t find the folder.
  - **Path: …** — shows the current bridge folder (if set).
  - **Quit** — quit the app and stop the bridge.

On first run the app tries to find `RemoteCursorBridgeNode` next to the app or in a few default locations. If it doesn’t find it, use **Set Bridge Path…** and pick the folder where you ran `npm install` for the Node bridge.

## Requirements

- **Node.js** installed (`node` on PATH; e.g. `/usr/local/bin/node` or `/opt/homebrew/bin/node`).
- The **RemoteCursorBridgeNode** project with `npm install` already run in that folder.

When the bridge is running, the iOS app can connect via **Wi‑Fi (URL)** or **Find Mac (Bonjour)** as usual.
