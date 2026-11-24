# Management link — Application and call-site migration (post–Connection shape)

**Status:** ✅ closed 2026-11-21 — **Connection** owns the link; registration store cutover shipped. Legacy **`Application`** / tray / monitor cleanup and **RDP second socket** continue under tail bugs below (not new work in this file).

**Pointer:** `docs/bug-fix-process.md`, [2.6.1-management-client-link-spec.md](../../plans/2.6.1-management-client-link-spec.md) (**§ Outstanding (after link shape)**), [2.6-DONE-management-connection.md](../../plans/done/2.6-DONE-management-connection.md), [`agent/Connection.vala`](../../../agent/Connection.vala), [`agent/Application.vala`](../../../agent/Application.vala)

**Tail work (open):** 2026-11-20-local-registration-cutover-remainder.md (deregister, Register polish, route-aware probes); 2026-11-19-CLOSED-desktop-status-and-reconnect.md (`stream_connection`, RDP notifications, reconnect).

**Prerequisite (done):** 2026-11-20-FIXED-local-registration-cutover.md, 2026-11-20-FIXED-local-registration-data-store.md.

---

## Problem

- 🔷 The **management client link** for the agent is implemented in **`Connection`**: six states, scheduler, inlined config read / TLS / hello in **`on_*`**, **`client()`** when **`CONNECTED`**, **`watch()`** and **`Application.notification`** from **`enter_connected`**.
- 🔷 **`Application` and other agent code** still use pre-2.6 patterns: **`attach_connection`**, static **`connection_down`**, **`state_changed`**, convenience getters, and OSQuery/monitors that poke **`connection_down`** directly.
- 🔷 **`stream_connection()`** on **`Application`** always returns **`null`** so the long-lived link is not duplicated into Application — **Windows RDP** second TLS is therefore **broken** until the spec names where that socket opens.
- 🔷 Gtk **CLI “already registered”** uses **`open_connection()`** → **`server.client()`** only; if the link is not **`CONNECTED`**, the check fails even when certs exist (by design until one-off path is spec’d).

**Expected (spec):** **`Application`** constructs **`server`** once; link owns connect/reconnect; UI reads **`notify::state`** and deadline properties; send failures use **`link.mark_down()`**; no TLS/hello on **`Application`**.

**Actual:** Mixed legacy and new — build passes; behaviour mostly works on the happy path; tray/gtk/RDP/inventory edges listed below.

---

## Connection shape (not in scope to redesign)

- ✔️ **`State`** enum names match spec (`DISCONNECTED_WILL_RETRY` … `DISCONNECTED_DEAD`).
- ✔️ **`enter_state`** → **`on_<state>()`**; transition helpers **`enter_connected`**, **`schedule_retry`**, **`enter_dead`**.
- ✔️ Constructor: 1s timeout, early return without **`client.pem`**, else start attempt chain.
- ✔️ No public **`read_server_*`**, **`open_tls_*`**, **`bind_without_watch`** on the class (logic inlined in handlers).
- 🚫 Do **not** move this logic back onto **`Application`** as a workaround.

---

## Outstanding work

### Link (`agent/Connection.vala`)

| ID | Item |
| --- | --- |
| L1 | ⏳ **`mark_down()`** — spec entry for RPC send failure → **`enter_state(DISCONNECTED_WILL_RETRY)`**; not implemented. |
| L2 | 💩 **`notify::state`** / deadline property notifies — confirm GObject notifies are emitted on property sets (tray migration). |
| L3 | 💩 Registration hand-off when **`client.pem`** appears **after** ctor — today **`Application.attach_connection()`** replaces **`server`** with **`new Connection`**. Spec prefers a single construct story. |

### Application (`agent/Application.vala`)

| ID | Item |
| --- | --- |
| A1 | ⏳ Remove **`attach_connection()`** after spec approves hand-off (L3). |
| A2 | ⏳ Retire **`Application.connection_down`** — **`Connection`** sets it in **`on_*`** today; callers should use **`mark_down()`** / state. |
| A3 | ⏳ Retire **`state_changed`** — tray **`Win32.Service`** and **`agent.removed`**; use **`notify::state`** on **`server`**. |
| A4 | ⏳ **`connection` getter** — alias for **`server.client()`**; migrate call sites to **`server.client()`** then drop getter if spec allows. |
| A5 | ⏳ **`open_connection()`** — shim for gtk/cli; spec § one-off TLS exception or wait for **`CONNECTED`**. |
| A6 | ⏳ **`stream_connection()`** — stub **`null`**; blocks RDP until spec assigns owner (not Application). |
| A7 | ⏳ **`start_inventory_once()`** — Windows path from link; Linux **`command_line`** 5s poll + inline **`OSQuery.Initialize`** — align with § inventory hook. |
| A8 | ⏳ **`status_notice`** — still written from **`Connection.on_disconnected_dead`**; tray should read **`failure_detail`** on link. |

### Call sites

| ID | File | Item |
| --- | --- | --- |
| C1 | `agent/Win32/Service.vala` | **`attach_connection`**, **`state_changed`**, **`connection_down`**, **`stream_connection()`**, duplicate osquery-init after registration. |
| C2 | `agent/linux/Application.vala` | D-Bus **`ServiceStatus`**, **`connection_down`**, **`open_connection()`** in command path. |
| C3 | `agent/linux/Application.cli.vala` | **`open_connection()`**, **`connection_down`** in status string. |
| C4 | `agent/OSQuery/*.vala`, `linux/PackageMonitor.vala`, `linux/Apt/History.vala` | Set **`Application.connection_down = true`** on send failure — migrate to **`mark_down()`**. |

### Controller

| ID | Item |
| --- | --- |
| X1 | ⏳ No agent-style **`Connection`** in controller; **`Window`** reconnect loop remains pre-spec. |

### RDP / second socket

| ID | Item |
| --- | --- |
| R1 | ⏳ **`stream_connection()`** removed from Application body; **`Win32/Service.relay_start`** gets **`null`** → **`RETRY_SECOND_CONNECTION`** path only. Needs spec + implementation outside Application. |

---

## Evidence (current tree)

- ✔️ **`Application` constructor** — `this.server = new Connection(this)` (`agent/Application.vala`).
- ✔️ **`attach_connection`** — only `this.server = new Connection(this)`; still called after CLI/browse registration and from **`Win32/Service`**.
- ✔️ **`open_connection` / `stream_connection`** — delegate / stub only (no TLS read on Application).
- ✔️ **`Connection.enter_connected`** — `#if !LINUX` → **`app.start_inventory_once()`**.
- ✔️ Build: agent compiles with above split.

---

## Prerequisite — local registration store

- 🔷 **2026-11-20-FIXED-local-registration-cutover.md** is **done**; remainder work is in 2026-11-20-local-registration-cutover-remainder.md. Without it, **`checking_config`** stays duplicated in **`agent/Connection`**, controller **`Bootstrap`**, and future controller link code.
- 🔷 Items **directly gated** by 2026-11-20-local-registration-cutover.md (`Controller.Store.Server` on controller; not raw SQLite in link code):
  - **L3** — registration hand-off when material appears after ctor (store notify or single construct reading **`get_active()`**).
  - **R6 in store log** — agent **`on_checking_config`** / cert wipe → store API only.
  - **X1** — controller management link + **server flip** via same interface as agent; drop `Bootstrap.use()` / `Window` inline TLS. (Tail — remainder bug.)
- ℹ️ Agent **`mark_down()`** (L1) and tray **`notify::state`** (A2–A3, C1–C3) can proceed in parallel only if they **do not** add new config-read paths; prefer **after** shared **`validate()`** exists.

---

## Conclusions

- **Root issue** is not the link state machine — it is **unfinished migration** of **`Application`**, tray, gtk, monitors, and RDP to the access rules in the spec.
- **Earlier root issue** for connection work: **no shared local registration store** — scaffold and main cutover **closed** (see pointers above).
- **Do not** re-add deleted **`Application`** connect helpers or static TLS helpers on **`Connection`** to close gaps; update the plan § Outstanding or a **new** bug with fenced hunks.
- **Do not** implement controller link **`checking_config`** by copying **`Bootstrap.use()`** TLS assembly; wait for store **`material_for_tls()`**.
- **RDP second connection** is a **product** gap tied to 2026-11-19-CLOSED-desktop-status-and-reconnect.md until the stream socket owner is spec’d.

---

## Archive

The **Outstanding work** tables below are a **historical checklist** at closure. Open items (**`mark_down()`**, **`connection_down`**, tray **`notify::state`**, **`stream_connection()`**, controller link) are tracked in the **Tail work** bugs in the status line — **do not extend this file**.

---

## Next steps (superseded — see Tail work in status)

Historical ordering at closure; follow 2026-11-20-local-registration-cutover-remainder.md and 2026-11-19-CLOSED-desktop-status-and-reconnect.md instead of extending this file.