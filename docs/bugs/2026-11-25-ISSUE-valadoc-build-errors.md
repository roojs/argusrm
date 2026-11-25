# Valadoc fails when the docs workflow runs on commit

**Status:** ✔️

## User decisions required

None.

## User reported

- 🔷 Fix the valadoc so a commit does not get an error on the valadoc build.

## Success scenario

- `ninja -C build docs/valadoc` exits 0.
- The GitHub Pages workflow step that runs that target is not failed by a valadoc error.

## Current behavior

- User asked to fix the valadoc build that errors on commit.
- `ninja -C build docs/valadoc` was run.
- First run stopped on a duplicate `Application`.
- After that file was left out, the same target stopped on missing `Linux`, `Lxw`, `Filters.InterfaceAddresses`, and `Storage`.
- After those inputs were added, the same target stopped on two doc-comment errors.
- After those comments were rewritten, the target printed `Succeeded - 106 warning(s)` and exited 0.

## Codebase observed behavior

- [`docs/meson.build`](../../docs/meson.build) listed `server/tests/offering-test-application.vala` next to `server/Application.vala`. Both declare `Argus.Server.Application`.
- The same list omitted `controller/store/Mounts.vala`, `controller/filter/Mounts.vala`, `controller/filter/InterfaceAddresses.vala`, and `controller/tab/Asset/Machine/Storage.vala`, which [`controller/meson.build`](../../controller/meson.build) compiles.
- The valadoc command had no `--pkg=linux` and no `--pkg=xlsxwriter`. [`server/meson.build`](../../server/meson.build) passes `--pkg linux`. [`controller/meson.build`](../../controller/meson.build) passes `--vapidir` `vapi` and `--pkg xlsxwriter`.
- [`server/Apt/CatalogImport.vala`](../../server/Apt/CatalogImport.vala) used `{@code …}`, which valadoc rejects.
- [`controller/store/Distributable.vala`](../../controller/store/Distributable.vala) had `<<<<<<<<<<` inside a doc comment. Valadoc reported `unexpected token`.

## Debugging

#### Current debug output

- Source: `ninja -C build docs/valadoc`, 2026-11-25, local build tree.
  - First failure:

```
offering-test-application.vala:27.2-27.39: error: `Argus.Server' already contains a definition for `Application'
Failed: 1 error(s), 0 warning(s)
```

  - Takeaway: the test stub cannot be documented in the same run as the real server `Application`.
  - After the stub and its two test files were removed from the input list:

```
Network.vala:220.6-220.10: error: The symbol `Linux' could not be found
Programs.vala:200.13-200.15: error: The symbol `Lxw' could not be found
InterfaceAddresses.vala:44.11-44.53: error: The type name `Argus.Controller.Filters.InterfaceAddresses' could not be found
Detail.vala:56.11-56.17: error: The type name `Storage' could not be found
```

  - After packages and the missing controller files were added:

```
CatalogImport.vala:22.27-22.31: error: Invalid taglet in this context: code
Distributable.vala:243.6-243.7: error: unexpected token: <space>
Failed: 2 error(s), 59 warning(s)
```

  - Final run: `Succeeded - 106 warning(s)` and exit 0.

#### Debug code added (remove when complete)

None.

## Proposed fix

Applied in the tree. See **LLM**.

## LLM

- ℹ️ Workflow: [`.github/workflows/deploy-docs.yml`](../../.github/workflows/deploy-docs.yml) runs `ninja -C build docs/valadoc` on push to master.
- ✔️ Left `tests/offering-*.vala` out of valadoc. The stub replaces `Application`. Comment in [`server/meson.build`](../../server/meson.build) and [`docs/meson.build`](../../docs/meson.build).
- ✔️ Added the four controller files, `--vapidir` `vapi`, `--pkg=linux`, and `--pkg=xlsxwriter`.
- ✔️ Replaced `{@code apt_pkg_depends_staging}` with `''apt_pkg_depends_staging''`. Replaced `{@code state}` in [`agent/Application.vala`](../../agent/Application.vala) the same way. Dropped the chevrons in the distributable doc comment and left “Windows installers only.”
- ℹ️ The successful run still prints 106 warnings (unhandled errors, `@link` names, deprecated `Gtk.StyleContext`). They do not fail the target.
- 🚫 Windows and Android sources, `main.vala`, and other test binaries stay out. That matches the existing “Linux sources only” note in [`docs/meson.build`](../../docs/meson.build).
