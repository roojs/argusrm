# Windows Software fleet grid — UI load / responsiveness

**Status:** ⏳

**Pointer:** `docs/bug-fix-process.md`, [`tests/programs-grid-offtest.vala`](../../tests/programs-grid-offtest.vala), [`tests/programs-grid-offtest-lib/`](../../tests/programs-grid-offtest-lib/)


---

### User decisions required

**Apply Phase A** in product (one line in `Base.vala`) then **you** verify Windows Software fleet — **not done yet**.

### User reported

- 🔷 Spinner dead / UI frozen **~3–4 s** on Windows Software (fleet).
- 🔷 Scroll jams when scrolling down after load.
- 🔷 Earlier **bundled** controller/SQL tweaks — **no perceived improvement**; stack reverted (2026-11-23).

### Success scenario

- Spinner animates during load; no multi-second UI freeze; scroll works during/after fleet load.

### Current behavior (code)

- [`controller/tab/Base.vala`](../../controller/tab/Base.vala) ~268: `SortListModel` **`incremental = false`**.
- [`controller/store/Programs.vala`](../../controller/store/Programs.vala): `this.items = listed` on RPC complete.

### Trials (facts only)

Record: **where** tested, **what** changed, **symptom / metric**, **outcome**. No “confidence” — only rows that happened or are explicitly **not run**.

| ID | Where tested | Reproduced slow load? | Change tried | Measured / felt | Outcome |
|----|----------------|----------------------|--------------|-----------------|--------|
| T1 | **Your controller** (device) | **Yes** (you) | Bundled: incremental sort, store chunking, slim SQL, etc. | You: **no perceived improvement** | **Reverted** to HEAD |
| T2a | Off-test (old harness) | Partial | Artificial pump after apply | ~1 s | **Invalid** — pump hid freeze (removed 2026-11-23) |
| T2b | `argus-programs-grid-offtest` + **in-test Unix RPC** (`ProgramsGridOfftestRpcServer`, real `Programs.list` on sqlite) | **FAIL** | grid repro after RPC fetch | **prod_worst_frozen_ms** still &lt; 3000 on copy DB (xvfb, 2026-11-23) | Exit **1** `REPRO_FAIL`; no live server / libsecret needed |
| T3 | **Off-test** same run | Same | fixB defer sorter | **807 ms**, ticks **26** | More main-loop ticks; **not** tried in product |
| T4 | **Off-test** same run | Same | fixC freeze sorter while `busy` | **844 ms**, ticks **28** | **not** tried in product |
| T5 | **Off-test** sqlite path | N/A | Slim vs legacy fleet SQL | Query **25 vs 47 ms**; payload **40k vs 178k chars**; **same 949 rows** | **Irrelevant** to UI freeze in harness |
| T6 | **Off-test** stub path (dropped) | No | Single-column stub grid | Sort/apply **~1–5 ms** | **Did not** reproduce freeze — led to real-grid off-test |
| T7 | **Product** | **Your** slow load | **Phase A only** (`incremental = true` in `Base.column_grid`) | — | **NOT RUN** |
| T8 | **Product** `--gui` off-test | — | Load + scroll by hand | — | **NOT RUN** (you or agent) |
| T9 | **Product** live `Programs.list` RPC | — | `--rpc HOST 817 SERVER` in off-test | — | **NOT RUN** |
| T10 | Debian unfilter bug | User: slow on unfilter | Documented same `incremental = true` edit | See other bug log | **Not** verified on Windows Programs on **this** tree — `Base.vala` on HEAD still **`incremental = false`** |

**Repro summary**

| Your symptom | Reproduced on your machine? | Reproduced in off-test/product? |
|--------------|----------------------------|--------------------------------|
| Slow load ~3–4 s | **Yes** (you) | **No** at that duration (harness ~1 s starvation) |
| Spinner stuck | You say yes | **Not** visually checked in `--gui` |
| Scroll jam | You say yes | **Not** — synthetic scroll steps only in T2 |

### Debugging

#### Current debug output

See trial **T2** table; raw row mix: service 641, programs 233, appx 127, startup 12 (1013 per-machine raw).

#### Debug code added (remove when complete)

Off-test harness only — no product debug.

### Proposed fix

#### Phase A — `SortListModel incremental = true` in `column_grid()` ⏳

**Basis:** Trial **T2** (harness: prod worse than fixA on `timer_ticks` + wall ms). Trial **T7** **not run** — **unknown** on your controller until you try.

**Where:** [`controller/tab/Base.vala`](../../controller/tab/Base.vala)

##### Remove

```vala
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = false
			};
```

##### Replace with

```vala
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = true
			};
```

**After apply — fill this row in Trials:**

| ID | Where | Change | You measure | Outcome |
|----|-------|--------|-------------|---------|
| T7 | Product, Windows Software fleet | Phase A only | e.g. load time, spinner moves Y/N, scroll Y/N | *(pending)* |

---

#### Phase B — Defer `sorted.sorter` until post-`busy` idle ⏳

**Basis:** Trial **T3** only (harness). **Do not apply** until **T7** fails your verify.

**Where:** [`controller/tab/Base.vala`](../../controller/tab/Base.vala) — see [`tests/programs-grid-offtest-page.vala`](../../tests/programs-grid-offtest-page.vala).

---

#### Phase C — Slim fleet SQL

**Irrelevant** — trial **T5**.

---

#### Rejected

- Hide `service`/`startup` via default filter (trial rejected by user).

### Product / approval

| | |
|--|--|
| Phase A on HEAD | **Not applied** |
| Your approval to land Phase A | **Not given** |
| Other product edits in plan | **None** (B only after failed T7) |

### Commands

```bash
ninja -C build tests/argus-programs-grid-offtest
xvfb-run -a build/tests/argus-programs-grid-offtest /tmp/argus.sqlite.copy
build/tests/argus-programs-grid-offtest /tmp/argus.sqlite.copy --gui
```

### LLM

- User (2026-11-23): replace “confidence” with **Trials** table; only facts and **NOT RUN** rows.
- Drop essay blocks; extend **T7** after isolated Phase A + user verify.