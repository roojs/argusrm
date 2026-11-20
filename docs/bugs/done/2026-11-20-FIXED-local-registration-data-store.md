# Local registration data — shared `SQT.Server` + controller store (design + scaffold)

**Status:** ✅ closed 2026-11-20 — **R1 design implemented in tree**; **client cutover** closed in [2026-11-20-FIXED-local-registration-cutover.md](2026-11-20-FIXED-local-registration-cutover.md); **remainder** in [2026-11-20-local-registration-cutover-remainder.md](../2026-11-20-local-registration-cutover-remainder.md).

**Pointer:** [2.6.1-management-client-link-spec.md](../../plans/2.6.1-management-client-link-spec.md), [5.2 done plan](../../plans/done/5.2-DONE-controller-user-registration.md)

---

## What shipped (agent + controller clients)

- ✔️ [`shared/SQT/Server.vala`](../../shared/SQT/Server.vala) — `server` table `init_db`, row fields, cached **`address_list()`**, **`socket(index)`**, **`pem_*`**, **`has_certificate`**, **`tls_certificate()`**, shared **`save` / `remove`**, virtual **`load_certificates` / `store_certificates` / `clear_registration`**.
- ✔️ [`controller/SQT/Server.vala`](../../controller/SQT/Server.vala) — libsecret / Android credential file; **`Json.gobject_to_data`** / **`from_data`** for stored row.
- ✔️ [`controller/store/Server.vala`](../../controller/store/Server.vala) — **`Store.Server(app)`**, **`list()`** with **`load_certificates`**.
- ✔️ [`controller/Application.vala`](../../controller/Application.vala) + Android twin — **`client_db`** open on construct, **`backup_real`** on shutdown.
- ✔️ [`agent/SQT/Server.vala`](../../agent/SQT/Server.vala) — PEM files under **`data_dir`**, **`0600`** / **`Cert.ensure`** on store.

**Rejected in implementation (per user):** persisted **`is_active`**, store **`open` / `get(name)` / `set_active`**, name-based **`remove`**, separate **`ClientDatabase`** opener, manual PEM JSON builder, **`reset_address_list`** on save.

---

## Not done here (moved to cutover bugs)

- ✅ **Main cutover** — [2026-11-20-FIXED-local-registration-cutover.md](2026-11-20-FIXED-local-registration-cutover.md).
- ⏳ **Remainder** — [2026-11-20-local-registration-cutover-remainder.md](../2026-11-20-local-registration-cutover-remainder.md) (deregister cleanup, Bootstrap `Register.save`, hygiene).

---

## Archive

The long-form problem statement, R1 tables, open-design thread, and day-by-day changelog were retired with this closure. **Do not extend this file** — use the remainder bug for open work.