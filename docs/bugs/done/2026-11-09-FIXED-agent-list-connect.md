# Agent list stays stale after connect

**Status:** ✅ closed 2026-11-10. Connect and disconnect broadcast `event.agent`.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 After registration the controller list shows the new machine.
- 🔷 When that machine connects, the Connected column stays disconnected.
- 🔷 A later `Agent.list` must copy into the rows already on screen. Clearing the grid drops an edit.

## Evidence

- ✔️ `event.pair` / `done` calls `Store.Agent.load`, which replaces `items` and emits `items_changed` for the whole list.
- ✔️ The app socket records `last_connected` and `agent_id` after the handshake, and again on close. It does not tell the controller.
- ✔️ `Agent.list` sets `connected` from the live app sockets. Nothing asks for that list when the socket opens or closes.

## Root cause

- ✔️ Connect and disconnect are silent, so the grid never reads the new `connected` flag.
- ✔️ `load` swaps the model, so a refresh rebuilds every row.

## Proposed fix

- 🔷 The app socket broadcasts `event.agent` / `connected` after a known machine is on the socket, and `event.agent` / `disconnected` after that socket stops.
- 🔷 The agent page loads on `event.agent` as well as `event.pair` / `done`.
- 🔷 A load that already has rows updates those objects, appends a new id, and removes an id that is gone.

## Next

- ✅ Closed. The agent page loads on `event.agent` and updates the rows already on screen.
