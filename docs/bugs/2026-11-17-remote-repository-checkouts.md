# Remote repository checkouts on agents

**Status:** ⏳ opened — catalog and placement design, replacing the MTrack Nagios pull

**Pointer:** `docs/bug-fix-process.md`, [7.0-tasks.md](../plans/7.0-tasks.md), [7.1-tasks-implementation.md](../plans/7.1-tasks-implementation.md), [1.1-implementation.md](../plans/1.1-implementation.md), [2026-11-17-windows-exe-distribution.md](2026-11-17-windows-exe-distribution.md)

---

## Problem

- 🔷 Script repositories are one concern. The library on this server (`script`, `script_repository`, `scripts/`) and a checkout of that repository on an agent are the same scripting story. This bug is the checkout on the agent.
- 🔷 **Expected:** Argus holds the repositories we can place, then records which machines have a checkout and the path on that machine. Clone and pull run as tasks on those agents. Many machines can be updated together.
- 🔷 **Actual:** `script_repository` is only a clone under `git/` on the Argus server, so the server can scan scripts. Nothing records a checkout on an agent. Updating those trees still happens in MTrack: one `GIT-PULL` at a time, collected by a Nagios NRPE check.

Linux machines get trees by checkout. Dropping loose files onto Linux is [2026-11-17-windows-exe-distribution.md](2026-11-17-windows-exe-distribution.md), and that bug is Windows executables only.

---

## Evidence

✔️ Argus today, and the MTrack flow this replaces:

### 1. The server library is not a checkout on the agent

- ✔️ `script_repository` (`shared/SQT/ScriptRepository.vala`) is `name`, `url`, `username`, `password`, and `key`. `ScriptRepository.clone` checks that URL out under `git/{name}` on the Argus server and fills `script` from the tree. [7.1](../plans/7.1-tasks-implementation.md).
- ✔️ [7.0](../plans/7.0-tasks.md) says that table is not MTrack's `mtrack_repos`. Remote checkouts, last-pulled commit, and stale trees were left for [1.1](../plans/1.1-implementation.md).
- 🚫 No table records `agent_id` plus a path for a repository. `script_agent` only says a library script may run on that machine.

### 2. MTrack already has the two layers

- ✔️ `mtrack_repos` (`Pman.MTrack/sql/mtrack_repos.sql`) is the catalog: `shortname`, `repopath`, `serverurl`, `description`.
- ✔️ `mtrack_deployment` (`Pman.MTrack/sql/mtrack_deployment.sql`) is one checkout: `server_id`, `repo_id`, `path`, `branch_id`, `commit`, `target_commit`.
- ✔️ A new deployment dialog (`Pman.Dialog.MTrackDeployment`) takes a base directory such as `/var/lib/git/` and clones `base + shortname`. `mtrack_deployment.path` can still be a one-off path. Some trees share a layout. Some do not.
- ✔️ `Mtrack_deployment::beforeUpdate` with `_pull` or `_clone` inserts one `mtrack_action` (`GIT-PULL` or `GIT-CLONE`) for that deployment. `onlyIfNonePending` refuses a second GIT action on that server.

### 3. The pull is sequential, and Nagios is the runner

- ✔️ `Pman.MTrack.Server.updateMany` walks the selected servers in `doMany`. Each step calls `updateSingle`, which queues the pull, runs it, refreshes that server, then starts the next server.
- ✔️ `Pman_MTrack_Server_Action::get` is what `check_git_update.php` calls over NRPE. It returns one `PENDING` row (`limit(1)`, `orderBy id ASC`) and marks it `RUNNING`. The client posts `SUCCESS` or `FAILED` back.
- ℹ️ [1.1](../plans/1.1-implementation.md) already names this: a local list of repositories, a pull on a folder on a remote machine, and the last pulled commit. Sister-Argus sync is the same note. It is not this bug.

---

## Root cause

- ✔️ Agent checkouts were left out of the script-library schema. The working copy of that job is MTrack's catalog plus `mtrack_deployment`, driven one action at a time by Nagios.

---

## Phases

- ⏳ **Phase 1 — Available repositories.** The set we are willing to check out onto machines.
- ⏳ **Phase 2 — Checkout locations.** Which machine, which path, then clone and pull as tasks.

Both phases use the same shape as the Windows file bug: a catalog of things, then a placement of each thing on a machine. [2026-11-17-windows-exe-distribution.md](2026-11-17-windows-exe-distribution.md).

---

## Phase 1 — Available repositories

- 🔷 A repository in this list is something an agent may check out. URL, a short name, and the credentials the checkout needs.
- 🔷 The script library on this server stays. `ScriptRepository.clone` / `pull` still fill `script` from `git/{name}`. A task still runs a script body. This phase does not turn the server clone into the agent checkout.
- 💩 Confirm whether Phase 1 is the existing `script_repository` rows (the repos this server already knows) or a sibling catalog. [7.0](../plans/7.0-tasks.md) kept `script_repository` meaning "cloned on this server". Adding agent paths onto that row would mix the two.
- 💩 Branch (or a default branch) belongs on the available repository, on the checkout, or on both. MTrack stores `branch_id` on the deployment and also has `mtrack_repos_branch`.

---

## Phase 2 — Checkout locations

- 🔷 One row per checkout: repository, `agent_id`, and the path on that machine.
- 🔷 The path is chosen per checkout. A dialog may offer a base directory plus the repository name, the way MTrack clones into `/var/lib/git/{shortname}`. A machine can also keep a path that does not follow that pattern.
- 🔷 Clone and pull are tasks on the agents that have that checkout. One task, many `task_target` rows, so machines update together. The agent runs `git` in that path. Nagios NRPE is not the transport.
- 🔷 The row remembers what is checked out (commit, and whether it matches the target) so a stale tree is visible without asking Nagios.
- 💩 How the agent authenticates. The server-side clone already stores a username and password or a deploy key on `script_repository`. The agent needs those, or a deploy key of its own, without the controller showing the secret.
- 💩 Whether a pull is "every checkout of this repository" or a ticked set of machines. MTrack's update walks an explicit server list.
- 💩 Recording failure. A task target already has an exit code and log files. The checkout row still needs a last-success time and the commit that was reached.
- 🚫 Sister-Argus sync of the catalog stays in [1.1](../plans/1.1-implementation.md). Not this bug.
- 🚫 Do not keep `check_git_update.php` or `mtrack_action` as the runner once the task path exists.
