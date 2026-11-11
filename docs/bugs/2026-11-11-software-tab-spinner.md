# Software tab spinner is a nested widget walk

**Status:** ✔️ the walk is gone — not verified on device

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 The spinner on a Software tab is placed by searching the switcher's private widgets.
- 🔷 That search sits inside the constructor, in nested loops.
- 🔷 It is pulled out. The tab owns its spinner.

## Evidence

- ✔️ `controller/tab/Asset/Software.vala` `map` waits an idle, then walks every child looking for css name `toggle`, then walks again looking for a `box`, then binds by index `0`, `1`, and `2`.
- ℹ️ `Adw.InlineViewSwitcher` builds that tree itself. The spinner was appended after the fact.

## Root cause

- ✔️ The switcher does not offer a spinner, so the constructor searched its children.

## Proposed fix

- 🔷 The page builds the tab row. Each tab is a toggle whose child is the icon, the title, and the spinner.
- 🔷 The three tabs are written in the constructor.
- 🔷 The active toggle name is the visible stack page.

## Attempts

- ✔️ The widget walk and `spinners_placed` are gone. Each tab is built in the constructor. A `tab` helper was added, then removed.

## Next

- 🔷 ⏳ Install the controller and open Software. The three tabs stay an inline switcher. A later load spins in that tab.
