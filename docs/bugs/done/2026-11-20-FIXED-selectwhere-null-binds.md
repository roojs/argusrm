# Client `selectWhere` with null bind maps

**Status:** ✅ closed 2026-11-20 — `selectWhere` call sites pass empty bind maps, not `null`.

## Symptom

- Desktop controller startup: “Checking connections” then failure; nothing usable from saved servers.
- Windows/Linux agent: no management link, tray shows generic “Disconnected” without registration reset flows.
- Controller log: `sq_query_selectWhere: assertion 'int_binds != NULL' failed`.

## Cause

`SQ.Query.selectWhere` requires non-null `int_binds` and `text_binds` (even when the SQL has no placeholders). After the connection-layer refactor, client code used `null, null`:

- `controller/store/Server.vala` — list saved servers at Bootstrap startup
- `agent/Connection.vala` — load saved server row (three call sites)

`shared/SQT/Server.save()` was already fixed locally; store list and agent connection were not.

## Fix

Pass empty `Gee.HashMap` instances instead of `null`. Regression check in `tests/registration-enroll.vala` (`WHERE deleted_dt = 0` with empty maps).

## Evidence

`~/.cache/argusrm/controller.log` (2026-11-20): repeated critical lines for `sq_query_selectWhere` during Bootstrap `check()`.

## Automated tests

**Gate (must pass as root):**

```bash
sudo meson test -C build registration-local-login --print-errorlogs
```

Meson timeout is **30s** (not 120s). RPC and TCP probes use **5s** (`call_timeout_seconds` / socket probe timeout). The test prints `step:` lines so a hang shows which phase stuck. Server tests set `Application.opt_test_minimal` to skip scripts git init.

Spawns a temp server, runs the **built** `argusrm-controller --server-socket … --give-me-a-certificate`, parses Bootstrap JSON, TCP-probes, and completes **TLS `RPC-Daemon.hello`** with the issued certificate.

**Unit (fast, non-root):** `registration-wire`, `registration-enroll`, `registration-bootstrap`, `registration-controller-cli` — helpers only; they do **not** replace `registration-local-login`.

`registration-certificate` also requires root and fails (does not skip) when euid ≠ 0.

## `registration-local-login` hello timeout (2026-11-20)

**Symptom:** Controller `--give-me-a-certificate` fails in ~5s with `RPC-Daemon.hello id=1: call timed out` while the test process holds the main loop.

**Cause:** The test used blocking `Subprocess.communicate_utf8` while serving RPC on the same thread; the Unix listener never dispatched until the subprocess finished.

**Fix:** `yield proc.communicate_utf8_async` so the outer `MainLoop` keeps handling server I/O during the pkexec-helper subprocess.

## `registration-local-login` TLS listen (2026-11-20)

**Symptom:** Certificate JSON succeeds; then `fail TLS listen` and `nf_tables_apply: assertion 'self != NULL'`.

**Cause:** The test stood up only the Unix RPC socket. It never ran `tls.ensure()`, created `app.firewall`, or bound `ssl_listen` like `Application.command_line` does before `Registration.certificate` calls `firewall.apply`.

**Fix:** Match production order in the test (server TLS identity, nftables allowlist, `ssl_listen.listen`, then Unix listener). Bind management TLS on an **ephemeral loopback port**, not `Argus.SOCKET_PORT`, so a running `argusrm-server` does not block the test. `Registration.certificate` always calls `firewall.apply` — same as the rest of the server; only half-started harnesses leave `app.firewall` null.

## pkexec JSON parse / GObject critical (2026-11-20)

**Symptom:** `registration-local-login` passes controller exit 0 but fails `Json.gobject_from_data`; controller stderr shows non-writable `has-certificate`, `title`, `addresses-subtitle`.

**Cause:** `OLLMrpc.Bin` and `Json.gobject_to_data` walked every GObject property, including read-only UI fields. RPC unpack tried `set_property`; JSON round-trip produced members that could not be deserialized.

**Fix:** `Argus.Shared.SQT.Server` skips non-writable properties in `bin_write_prop`, `bin_read_prop`, `serialize_property`, and `deserialize_property`.

## scripts git init / g_file_test (2026-11-20)

**Symptom:** Journal shows `g_file_test: assertion 'filename != NULL' failed` and `scripts git init: no error` at service start.

**Cause:** Constructor called `Ggit.Repository.init_repository` on a tree that already had a broken `scripts/.git`, or before paths were validated. libgit2-glib tripped GLib assertions; the catch only logged a useless `"no error"`.

**Fix:** `SQT.Script.check_repo` uses `git -C scripts init` only when `.git` is missing (no libgit at startup). Broken `.git` is left for manual removal. `fetch_osquery` failure is a warning, not fatal.

## Unix socket connection refused (2026-11-20)

**Symptom:** `sudo argusrm-controller-cli` → `connect …/argus.sock: Connection refused`. Journal may show `g_file_test` and **no** `unix registration socket at …` line.

**Cause:** Startup used to run nftables before `listen.start()`. Any firewall or port parse error exited before `argus.sock` existed. Running the build tree **without root** also fails at `error: firewall allowlist was not applied` (no socket). Installed `/usr/bin/argusrm-server` can still be an older binary until `meson install`.

**Fix:** Bind `argus.sock` immediately after RPC registration, **before** firewall setup (`server/Application.vala`). Download bind failure stays non-fatal. Verify: `sudo meson install -C build`, `sudo systemctl restart argusrm-server`, journal must show `unix registration socket at /var/lib/argusrm/argus.sock`.

## TLS hello on loopback (2026-11-20)

Local login: cert on Unix `argus.sock` only; management probes use interface IPs from the certificate JSON (no `127.0.0.1` fallback). See [2026-11-20-ollmrpc-loopback-plain-tcp.md](../2026-11-20-ollmrpc-loopback-plain-tcp.md).

## Related — local login after fix

- **Empty `addresses`** when `TcpListen.ifaces()` is empty: `Registration.certificate` errors; certificate step must succeed before TCP probe.
- **pkexec helper segfault** on `GApplication` teardown after `--give-me-a-certificate` JSON: `Application.command_line` uses `Posix._exit` for that mode.
- **Installed path**: Bootstrap prefers `Argus.CONTROLLER_EXECUTABLE` so pkexec matches polkit policy.