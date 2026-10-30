# 0.0 Argus — overview

**Status:** ⏳ proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Index:** [1.0-summary.md](1.0-summary.md)

---

## Purpose

- 🔷 Remote management of machines.
- 🔷 An agent runs on each managed machine.
- 🔷 Argus is the control server.
- 🔷 A client talks to Argus and controls it.
- 🔷 First managed machines are Windows. A Linux agent comes later.
- 🔷 Phase 1 proves one desktop can be enrolled and then managed.
- ℹ️ Later abilities are [1.2](1.2-software-inventory.md) through [1.5](1.5-monitor-and-notify.md).

---

## Roles

- 🔷 **Agent**
  - Runs on the managed machine.
  - Windows first.
  - Installed as admin.
  - Thin.
  - Startup follows the OLLMchat Android client: wait for a broadcast, then register with certificates.
- 🔷 **Argus**
  - The control server.
  - Issues certificates.
  - Distributes files.
  - Holds the machine records.
  - Keeps a second socket for downloads and other bulk transfer.
- 🔷 **Controller**
  - The client that talks to Argus.
  - The long-run client is a desktop application.
  - A web app is not the path under consideration.
  - The phone is the first controller, for registration and later for alerts.
- 🔷 The controller does not install a separate agent.
  - It is usually a Linux box.
  - It can be a Windows box.
  - It enrolls on the same broadcast and is stored as a control client.

---

## Enrollment

- 🔷 Argus publishes a short Avahi broadcast that it is available.
- 🔷 Avahi runs only on Argus. Clients browse for that broadcast.
- 🔷 The broadcast is started by a remote instruction from a controller, or by a command-line tool.
- 🔷 The controller shows a number for that window.
- 🔷 The agent is already installed and is hunting for the broadcast.
- 🔷 The person types the number into the desktop.
- 🔷 Registration uses the RPC library and certificates, the same way as the other projects.
- 🔷 The machine is then pending, or in-process.
- 🔷 The agent downloads the osquery installer from Argus on the download socket, then installs it.
- 🔷 It then runs a basic query and Argus fills the record in.
- 🔷 The phone flow for that window:
  - Install the Android client.
  - Tell Argus to broadcast.
  - The phone shows the number.
  - Type that number into the desktop.
- ℹ️ Detail is [1.1](1.1-enroll-desktop.md).
- ℹ️ OLLMchat pairing: `libocrpc/Transport/PairPublish.vala`, `ollmfilesd/ClientCert.vala`.

---

## After a machine exists

- 🔷 First data is only the identity of the machine.
  - Username.
  - Computer name.
  - Type of computer.
  - Speed.
  - An identifier that can be referenced.
  - Some network information.
- 🔷 Server records follow osquery’s data to a large degree.
- 🔷 Next is the list of installed software.
  - A catalog, maybe a git repository, categorises that software.
- 🔷 Then install: Argus holds the files, can fetch them from online, and the controller picks a package for a machine. The agent pulls those files on the download socket.
- 🔷 Then uninstall, using the Windows uninstall entries.
- 🔷 Then monitoring.
  - New applications are the critical alert.
  - A ChatGPT desktop install should warn quickly.
  - A port that is not the expected one is later, and is osquery data.
- 🔷 Warnings reach Nagios through a cron or shell script that asks Argus if any warning is open.
- 🔷 The same warnings can be broadcast to Android phones that have the app.

---

## Sockets

- 🔷 The main socket is the app RPC.
  - Registration, commands, identity, and warnings stay here.
- 🔷 A second socket carries downloads and other bulk transfer.
  - The osquery installer.
  - Later package file sets.
- 🔷 A transfer on the second socket must not clog the main socket.
- 🔷 The second socket is fixed in the Argus config.
- 🔷 The registration response sends that socket info to the client.

---

## What we reuse

- 🔷 The RPC library, and certificate registration as in the other projects.
- 🔷 Avahi on Argus for the short availability broadcast. Clients only browse.
- 🔷 A little of the Pman track that manages processes.
- ℹ️ Snappr for a Windows admin install and a resident process. Not the clipping app.
- ℹ️ Nagios checks that are a shell script on a timer. See `server.media-outreach/etc/nagios/`.
- ℹ️ Pman CLI processes live under `web.MediaOutreach/Pman/`.
