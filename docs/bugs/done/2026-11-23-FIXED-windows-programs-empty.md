# Windows machine programs tab empty

**Status:** ✅

### User reported

- 🔷 Machine **Windows programs** tab showed no rows after connect; worked once snapshot SQL was fixed.

### Success scenario

- Agent posts `Programs` via `OSQuery.sync`; controller `Programs.list` shows installed software.

### Current behavior

- User confirmed fix (2026-11-23): remove bogus `appx_packages` branch; MSIX via `programs.package_family_name`.

### Proposed fix

- ✔️ [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala) — drop `FROM appx_packages`; `source = 'appx'` when `package_family_name != ''` on `programs`.

### Debugging

#### Current debug output

```text
SELECT count(*) FROM appx_packages   → Error: no such table: appx_packages
Execute.vala:121: osqueryi exited 1
```

### LLM

- ℹ️ `appx_packages` is not an upstream osquery table; Store/MSIX rows live in `programs` (5.17+).
- ℹ️ Prior report: [`2026-11-23-ISSUE-windows-programs-empty.md`](../2026-11-23-ISSUE-windows-programs-empty.md) (archived).