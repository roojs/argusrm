# Server log noise during registration and controller startup

**Status:** ✔️ applied in tree (argusrm); one line still needs OLLMchat if desired

**Debugging:** `docs/bug-fix-process.md`, pasted server log 2026-11-28

---

## User reported

- Dense server log during Android registration and desktop controller `hello` / list RPCs.
- Expected: only real failures as warnings; empty lists and probes not spamming criticals or warnings.

## Log line → cause → fix

| Log | Cause | Fix |
| --- | ----- | --- |
| `type id '0' is invalid` / GValue criticals after `.list` | `OLLMrpc.val("o", empty ArrayList)` | ✔️ Handlers omit `retval` when `rows.size == 0` |
| `Network.vala:181: Unacceptable TLS certificate` | `lookup_ip` HTTPS to ifconfig.me, no cert accept | ✔️ `message.accept_certificate` (BAD_IDENTITY only); lookup failure → `GLib.debug` |
| `SslListen.vala:194: ssl handshake failed … non-properly terminated` | TCP port check on 819 without TLS (browse / `Register.probe`) | ✔️ Registration listener logs probe at **debug** |
| `Connection.vala:381: Unexpected early end-of-stream` after `Offering.enroll` | `TlsClient` closes after one reply; server read loop treats EOF as warning | ⏳ **OLLMchat** `Connection.vala` — demote that message to debug (user skipped cross-repo edit this session) |
| `Rpc.vala:213: number rejected` | Wrong or stale PIN | Operational — not a code defect |
| Android `root parse does not accept object arrays` | Client-side parse / separate attempt | Track on device log vs server `Offering.enroll` line |

## Root cause (lists)

- Handlers always packed empty lists through `OLLMrpc.val`, violating omit-`retval` wire policy and tripping `g_value_init(0)`.

## Proposed fix (applied)

- List handlers: conditional `retval` (see `server/SQT/`, `shared/OSQuery/`, etc.).
- `server/Offering/Network.vala` `lookup_ip`.
- `server/Net/SslListen.vala` registration handshake catch.

### LLM

- `server/Offering/Network.vala`, `server/Net/SslListen.vala`, list handlers, `controller/store/DebPackages.vala`, `CHANGELOG.md`
- Rebuild and restart `argusrm-server` to verify log on controller open + registration window.