# Debian: preview install and remove

**Status:** ⏳ opened — show the dependency list and wait for approval before a Debian install or remove

**Pointer:** `docs/bug-fix-process.md`, closed catalog [done/2026-11-16-FIXED-debian-package-catalog-integration.md](done/2026-11-16-FIXED-debian-package-catalog-integration.md), [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-windows-uninstall-task-queue.md), [rpc-commands.md](../rpc-commands.md), [`shared/SQT/AptPkgDepends.vala`](../../shared/SQT/AptPkgDepends.vala)

---

## Problem

- 🔷 Debian remove is not queued. Before it is approved, the controller shows the packages that would be removed with it.
- 🔷 Install is the same idea the other way. Before it is approved, the controller shows the packages that would be pulled in.
- 🔷 The other reason for this RPC is the dependency tree. `apt_pkg` / `apt_pkg_depends` answer what a package depends on, and what depends on it. Windows uninstall left Debian out until that tree existed.
- 🔷 **Actual:** no catalog RPC, no approval list, no Debian install or remove task.

---

## Carried from the catalog bug

- 🚫 Header bar controls. The approval UI sits on the page, as the other Debian actions do.
- ℹ️ Phase 1 import skipped `|` alternatives. A preview does not guess which alternative. It stays conservative.
- 🚫 No `apt_url_agent`. A machine's repos stay `apt_sources_catalog` joined to `apt_url` on `url_key`.

---

## Open

- 💩 The remove list is not chosen yet. It may be the packages that depend on the one being removed, the packages apt would autoremove, or a simulation of `apt-get remove`.
- 💩 Install preview is in this bug so it can be thought through with the remove preview. The list of packages that would be installed is not designed yet.
- 💩 One machine, or every machine that has the package.
- 💩 An approved remove still has to become a task. The Windows hold button queues immediately. Debian does not copy that until this list is approved.
- 🔷 Test the closure offline against a known package set. No network.

---

## Next

- 🔷 Decide what the remove list contains, and what the install list contains.
- 🔷 Then the RPC, the approval UI, and the test.

---

## Attempts / changelog

- ✔️ 2026-11-17: Split out of slice **G** of [done/2026-11-16-FIXED-debian-package-catalog-integration.md](done/2026-11-16-FIXED-debian-package-catalog-integration.md).
