# Task queue: Client disconnected

**Status:** ✅ closed 2026-11-17 — the released library takes the array length, and a task queues. Argus did not patch the library.

**Pointer:** [OLLMchat `2026-11-17-rpc-args-int-array.md`](../../../OLLMchat/docs/bugs/2026-11-17-rpc-args-int-array.md), [`server/SQT/Task.vala`](../../server/SQT/Task.vala)

---

## Problem

- 🔷 Queueing a task toasts `Could not queue task: Client: disconnected`.
- 🔷 The server dies inside `Task.submit` while walking `agent_ids`.

## Where it is fixed

- ℹ️ `Task.submit` is `oaib` and `Task.target` is `iai`. Both take `int[]`.
- ℹ️ Packing that array is `libocrpc`. The failure is recorded there.
