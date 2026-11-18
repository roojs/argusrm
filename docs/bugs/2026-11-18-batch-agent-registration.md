# Batch registration for Linux agents

**Status:** ⏳ Phases 1 and 2 are in the tree. Phases 3–7 wait. Each phase is one step of the flow, and the next phase waits until this one is reviewed.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md` (`Agent.offer`, `Agent.request_registration`), [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala), [`controller/tab/Agent.vala`](../../controller/tab/Agent.vala), [`server/Agent.vala`](../../server/Agent.vala), [`server/Net/SslListen.vala`](../../server/Net/SslListen.vala), [`agent/Application.vala`](../../agent/Application.vala)

---

## Problem

- 🔷 A batch install of the Linux agent cannot use the current registration. The controller issues a number, and somebody has to type that number on each machine.
- 🔷 **Expected:** the Linux agents ask to join on their own. The person at the controller sees the machines that asked, ticks the ones to keep, and accepts them. The rest can be rejected. The dialog can be closed.
- 🔷 **Actual:** **Agent or Controller** opens a six-digit number for sixty seconds. One accepted number closes that window. Each agent is started with `--pin` and tries once.

---

## Evidence

- ✔️ **Agent or Controller** is the button on the agents page. It runs `win.register`, which opens `controller/dialog/Pairing.vala`.
- ✔️ `Agent.offer` returns six digits, opens the registration socket, and disables the registration firewall for sixty seconds. The app socket and its firewall stay as they are. The first accepted `Agent.request_registration` clears the number, enables the registration firewall again, and broadcasts `event.pair` / `done`. The dialog closes on `done`.
- ✔️ `Agent.request_registration` is `ssssbss`: pin, certificate request, requester, OS family, controller flag, username, hostname. A pin that is not the issued number is `number rejected`.
- ✔️ A finished registration inserts `agent` with `status = 1` and the peer address, then `Agent.allowlist` rebuilds the app firewall. The allowlist is `agent.ip` where `status = 1`.
- ✔️ The app socket requires a client certificate. `SslConnection.allow_request` allows a `status = 1` row. Anything else is closed. The app firewall drops an address that is not on that list, so the handshake never starts.
- ✔️ The Linux agent registers once. `agent/Application.vala` calls `Register.try_connection` and exits on failure. There is no retry while the window is closed.
- ✔️ The tick dialogs are `controller/dialog/Distribute.vala` and `controller/dialog/Upgrade.vala`. The dialog header bar is the title. Under it, a bar holds a `Gtk.SearchEntry` (`hexpand`) and **Select all** (`halign` end). The body is a stack: a spinner, a scrolled column view, and an empty label. The action buttons sit on a row at the bottom, end-aligned. The last one is `suggested-action`.

---

## Phases

- ✔️ **Phase 1 — Agent asks.** `argusrm-agent --batch` sends pin `0000` and the batch flag. A closed registration port is tried again every ten seconds for about three minutes.
- ✔️ **Phase 2 — Server queues the request.** An open window appends `agent_pending` and returns a temporary certificate. The app firewall stays unchanged. The dialog stays in number mode.
- 🔷 ⏳ **Phase 3 — Agent stores the certificate.** A pending reply is written to the certificate files. The agent stops calling the registration port. It does not dial the normal port yet.
- 🔷 ⏳ **Phase 4 — Agent polls the normal port.** Every twenty seconds, for about five minutes. If none of those connects, the agent deletes the certificate and fails out.
- 🔷 ⏳ **Phase 5 — Controller shows the list.** The dialog flips to the existing tick list. Number mode stops. Search and **Select all** are that dialog's bar. No **Reject** and no **Accept** yet.
- 🔷 ⏳ **Phase 6 — Reject and the header X.** **Reject** drops the ticked rows. The X ends the window and drops whatever is still queued.
- 🔷 ⏳ **Phase 7 — Accept.** **Accept** makes the ticked certificates permanent and rebuilds the app firewall. The next poll on the normal port connects.

---

## Phase 1 — Agent asks

Review is `argusrm-agent --batch` with a server address. A typed `--pin` is unchanged. The server accepts the new flag and still requires the issued number, so `0000` is `number rejected` until Phase 2.

- ✔️ `--batch` sends pin `0000` and `Register.batch`. The call is `ssssbbss`: pin, certificate request, requester, OS family, controller flag, batch flag, username, hostname.
- ✔️ `--batch` needs `--server` or `--host`. It does not take `--pin`.
- ✔️ A failed connect is tried again every ten seconds for about three minutes, then the process exits non-zero. A reply from the server stops the retry. `number rejected` is a reply.
- ✔️ The same path is on `argusrm-agent-gtk` when that program is run as root with the option. The install command is `argusrm-agent`.
- ℹ️ A closed window does not answer RPC. The registration firewall is an empty allowlist, and the socket is stopped when the offer ends. `Register.try_connection` returns `INTERNAL_ERROR` for that failure.
- 🚫 A batch request from a controller registration, or from the Windows tray. This path is the Linux agent.
- 🚫 Storing a pending certificate, dialing the normal port, `agent_pending`, or a dialog change in this phase.

---

## Phase 2 — Server queues the request

Review is one open registration window and several flagged `0000` calls. Each call appends a row and returns a certificate. The dialog still shows the number. The app firewall does not change.

- ✔️ The registration window has to be open. `listen.pin` is set only while `Agent.offer` has the registration firewall down.
- ✔️ An open window answers pin `0000` with the batch flag, and not a controller, with `msg` `pending` and the signed certificate. The number stays valid. The registration socket stays up. `event.pair` `done` is not sent.
- ✔️ Each of those requests is appended to `agent_pending`. It is not an `agent` row. The app firewall is not applied. The download socket is not opened for that request.
- ✔️ `0000` without the flag, or the batch flag with another pin, stays `number rejected`.
- ✔️ One row per request:
  - `id`
  - `ip` — the peer address
  - `hostname` — already on `Agent.request_registration`
  - `fingerprint`
  - `certificate` — the temporary PEM
  - `requester`
  - `created`
- 💩 `hostname` is the extra column. Phase 5 needs the address. Drop `hostname` if the row should be the address only.
- 💩 The pending reply uses the same array as a finished registration (certificate, CA, download path, normal-port addresses) and `msg` `pending`.
- 🚫 Leaving the registration firewall down when the dialog is closed.
- 🚫 Reusing `agent.status = 0`. That value is already a controller registration that is not active yet.
- 🚫 Putting the private key in the table. The agent keeps the key it generated. The server stores the certificate it signed.
- 🚫 An `agent` row, an app-firewall change, or a dialog change in this phase.

---

## Phase 3 — Agent stores the certificate

Review is the agent after a pending reply. The files are on disk. The process has not dialed the normal port.

- 🔷 The agent writes the temporary certificate from the pending reply.
- 🔷 It stops calling the registration port.
- 🔷 It does not treat pending as a finished registration, and it does not dial `Argus.SOCKET_PORT`.
- 🚫 Another call on the registration port after the certificate is stored.

---

## Phase 4 — Agent polls the normal port

Review is the five minutes after the certificate is stored. Accept does not exist yet, so every poll fails and the certificate is deleted.

- 🔷 The agent addresses the normal port, `Argus.SOCKET_PORT`. It does not go back to the registration port.
- 🔷 It polls that port with the temporary certificate. Every twenty seconds, for about five minutes.
- 🔷 Those attempts fail until Phase 7. The app firewall does not list that address yet, so the connection does not arrive. A refused connect during the five minutes is the poll, and the agent tries again.
- 🔷 If the five minutes end without a connection, the agent deletes the temporary certificate and fails out.
- 💩 The poll is a connect with the temporary certificate. It is not a second registration call. No new method, unless a later approval adds one, in which case `docs/rpc-commands.md` gets it in that change.
- 🚫 After the temporary certificate, another call on the registration port.

---

## Phase 5 — Controller shows the list

Review is the dialog. The queue from Phase 2 is what it shows. **Reject** and **Accept** are absent.

- 🔷 Same dialog as the six-digit number. It opens in number mode.
- 🔷 A typed six-digit registration works while the dialog is still in number mode. One success still closes the dialog, as it does today.
- 🔷 The first pending `0000` request flips it out of number mode. Number mode stops. The issued number is cleared, the sixty second countdown stops, and a typed pin is `number rejected`. The dialog does not return to the number.
- 🔷 The list is the existing tick dialog. `controller/dialog/Distribute.vala`. The header bar is the title. Search and **Select all** are the bar those dialogs already use. Further requests append while it stays open.
- 🔷 The registration socket stays open for flagged `0000` requests. Stopping number mode does not close that socket.
- 💩 Search filters the address text. The entry is `hexpand`, and **Select all** is `halign` end on that same bar.
- 💩 The body is the same stack: spinner, scrolled column view (`min_content_height` 240), and an empty label.
- 💩 The dialog already listens for `event.pair`. A pending request broadcasts `event.pair` with action `pending` and the address, so the open dialog appends a row. It does not broadcast `done`. `done` closes this dialog after a typed number, which only happens before the flip.
- 💩 **Select all** ticks every row in the filtered list, which is what `Distribute` does. A row hidden by the search stays as it was. A row that arrives after **Select all** is unticked. `Upgrade` renames the button to **Select none** once every listed row is ticked. This dialog does the same.
- 💩 With the hostname column the row text is `192.168.88.14    web-03`, and search matches that text too.
- 🚫 **Reject** and **Accept** in this phase.
- 🚫 A new arrangement of these controls.
- 🚫 Closing the dialog on the first pending request.
- 🚫 Buttons on the window header bar. The header in use here is the dialog header.

```
+--------------------------------------------------+
| Register                                       X |
+--------------------------------------------------+
| [ Search________________________ ] [ Select all ]|
|                                                  |
| [ ]  192.168.88.12                               |
| [x]  192.168.88.14                               |
| [x]  192.168.88.21                               |
|                                                  |
+--------------------------------------------------+
```

---

## Phase 6 — Reject and the header X

Review is the list with **Reject**, and the X. **Accept** is still absent, so this phase cannot open the app firewall.

- 🔷 **Reject** drops the ticked rows. Those certificates never become permanent. The app firewall is unchanged.
- 🔷 The X on the dialog header dismisses it. There is no Close button.
- 🔷 The X ends the open window. The registration firewall comes back. Rows still in the queue are dropped and are not accepted.
- 💩 **Reject** sits on the bottom action row, end-aligned.
- 💩 Reject with nothing ticked does nothing.
- 🚫 A Close button. The header X is the close.
- 🚫 **Accept** in this phase.

```
+--------------------------------------------------+
| Register                                       X |
+--------------------------------------------------+
| [ Search________________________ ] [ Select all ]|
|                                                  |
| [ ]  192.168.88.12                               |
| [x]  192.168.88.14                               |
| [x]  192.168.88.21                               |
|                                                  |
|                                         [ Reject ]|
+--------------------------------------------------+
```

---

## Phase 7 — Accept

Review is the permanent certificate and the app firewall. The agent's next poll on the normal port connects.

- 🔷 **Accept** keeps the ticked rows. It makes each ticked certificate permanent: an `agent` row with `status = 1`, that fingerprint, and that address. Then the app firewall is rebuilt from the allowlist. Those rows leave the queue.
- 🔷 The agent's next poll on the normal port is an ordinary agent connection.
- 💩 **Accept** sits to the right of **Reject**. **Accept** is `suggested-action`.
- 💩 Accept with nothing ticked does nothing.
- 🚫 Opening the app firewall before Accept.

```
+--------------------------------------------------+
| Register                                       X |
+--------------------------------------------------+
| [ Search________________________ ] [ Select all ]|
|                                                  |
| [ ]  192.168.88.12                               |
| [x]  192.168.88.14                               |
| [x]  192.168.88.21                               |
|                                                  |
|                             [ Reject ] [ Accept ] |
+--------------------------------------------------+
```

---

## Next

- 🔷 ⏳ Phase 3, after Phase 2 is reviewed. The agent writes the pending certificate and stops. `agent_pending` stores `hostname` beside the address.
- 🔷 ⏳ Phase 4. The normal-port poll, and deleting the certificate when it fails.
- 🔷 ⏳ Phase 5. The dialog flips to the tick list. Number mode stops.
- 🔷 ⏳ Phase 6. **Reject** and the header X.
- 🔷 ⏳ Phase 7. **Accept** and the app firewall.
