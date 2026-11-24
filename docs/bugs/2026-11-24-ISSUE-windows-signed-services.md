# Windows services signed by Windows stay on the software list

**Status:** ⏳

### User decisions required

- 💩 Approve **Proposed fix** before it is applied. The match is `signer_cert_sha256`, not the certificate display name.

### User reported

- 🔷 A service comes off the general list only when a determinate check says it is part of Windows.
- 🔷 The check is the signature on the file Windows registered for that service.
- 🔷 Signed by Microsoft Corporation is not enough. That certificate is also Office, Edge, and Visual Studio.
- 🔷 Propose the code that does this filter.

### Success scenario

- A service whose signing certificate thumbprint is one of the two Windows certificates below is stored and left out of the software list.
- A service signed by any other certificate stays on the list. That includes Microsoft Corporation and the hardware-compatibility certificate VirtualBox uses.
- A service with no signature result stays on the list.
- Startup-folder items stay on the list.

### Current behavior

- What you said
  - Services need the same kind of proof used for the MSI pieces.
  - The proof has to be determinate.
- On DESKTOP-GITPJFF, after the MSI hide
  - The snapshot still has 641 service rows.
  - 362 of those had no signature, because the path was `\SystemRoot\System32\drivers\...` or `system32\drivers\...`.
  - Expanding that path and reading Authenticode: 351 are Microsoft Windows, 1 is the Defender early-launch publisher, 2 are the hardware-compatibility publisher on VirtualBox, 2 are OpenVPN, 2 are Oracle, 3 Bluetooth drivers have no signature.
  - Services that already resolved include 226 signed Microsoft Windows Publisher, and 11 signed Microsoft Corporation.

### Codebase observed behavior

- [`agent/windows/ExeEnrichment.vala`](../../agent/windows/ExeEnrichment.vala) `locate` keeps a path that ends in `.exe` or `.dll`, or a regex match for those two suffixes. A `.sys` path is dropped. `\SystemRoot` is left as written, so the later file open does not see `C:\Windows\...`.

```vala
var pe_path = new GLib.Regex("([A-Za-z]:\\\\.*?\\.(?:exe|dll))",
	GLib.RegexCompileFlags.CASELESS);
if (!lower.has_suffix(".exe") && !lower.has_suffix(".dll")) {
```

- [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala) `list` omits `system_component = '1'` and otherwise returns every service row.
- [`win32/pe-authenticode.c`](../../win32/pe-authenticode.c) stores a trusted file as `signing_result` `Valid` and the certificate display name as `signer_publisher`.

### Debugging

#### Current debug output

- Osquery `authenticode` on the expanded driver path, DESKTOP-GITPJFF, 2026-11-24.

```text
result = trusted
signer = Microsoft Windows
     n = 351

result = missing
     n = 3

result = trusted
signer = Microsoft Windows Hardware Compatibility Publisher
     n = 2

result = trusted
signer = OpenVPN Technologies, Inc.
     n = 2

result = trusted
signer = Oracle Corporation
     n = 2

result = trusted
signer = Microsoft Windows Early Launch Anti-malware Publisher
     n = 1
```

- Takeaway: the Windows signer is readable once `\SystemRoot` is `C:\Windows`. The hardware-compatibility signer is VirtualBox, not Windows.

#### Debug code added (remove when complete)

None.

### Proposed fix

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### Phase 1 — `agent/windows/ExeEnrichment.vala` `locate`: open the driver path

**Why:** the signature cannot be read until `\SystemRoot` and a leading `system32\` are a real file, and `.sys` is a file we accept.

**Where:** `locate`, the regex, the suffix test, and the path stored on the row.

**Depends on:** none.

#### Remove

```vala
			var pe_path = new GLib.Regex("([A-Za-z]:\\\\.*?\\.(?:exe|dll))",
				GLib.RegexCompileFlags.CASELESS);
```

#### Replace with

```vala
			var pe_path = new GLib.Regex("([A-Za-z]:\\\\.*?\\.(?:exe|dll|sys))",
				GLib.RegexCompileFlags.CASELESS);
```

#### Remove

```vala
						if (!lower.has_suffix(".exe") && !lower.has_suffix(".dll")) {
```

#### Replace with

```vala
						if (!lower.has_suffix(".exe") && !lower.has_suffix(".dll") &&
							!lower.has_suffix(".sys")) {
```

#### Add

After the regex `path = match.fetch(1)` block, before `this.row_path.set`. Turn the registered service path into a file path.

```vala
						if (path.has_prefix("\\SystemRoot\\")) {
							path = "C:\\Windows" + path.substring("\\SystemRoot".length);
						}
						if (path.down().has_prefix("system32\\")) {
							path = "C:\\Windows\\" + path;
						}
```

### ✔️ Phase 2 — `shared/OSQuery/Programs.vala` `list`: omit those certificate thumbprints

**Why:** the list is what the software screen shows. The row stays stored. The match is the SHA-256 of the signing certificate, `signer_cert_sha256`. The hashes are written in the query. A comment before the select points at the public report.

**Where:** each of the four queries in `list`, after `system_component != '1'`. The comment is immediately before the first select.

**Depends on:** Phase 1 for the driver paths that do not yet store a thumbprint. A row that already has one of these thumbprints is hidden now.

#### Add

Before the first select in `list`:

```vala
			// Microsoft Windows, Production PCA 2011.
			// To check it, look here:
			// https://www.joesandbox.com/analysis/1772502/1/html
			// 1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de
			// Microsoft Windows Publisher, same issuer
			// 12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50
			// Defender early-launch driver
			// 836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1
```

After every `system_component != '1'` in `list`.

```vala
					AND NOT (
						source = 'service'
						AND signing_result = 'Valid'
						AND lower(signer_cert_sha256) IN (
							'1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de',
							'12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50',
							'836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1',
							'e866d202865ed3d83c35dff4cde3a2d0fc1d2b17c084e8b26dd0ca28a8c75cfb',
							'aec8b67481dfcd2b03398cf9c9439e80ef3e75d407fb0753f9e6c548bc3b5eff',
							'2724aeb0c497bf5fd732958120d1ae3341cfd252ab1680de03d10503abc666c1',
							'1721693d3e23c7abf800ae7b86654ed86dceab48c530a57c00d24ef23ff7407e',
							'2d7ffce2c256016291b67285456aa8da779d711bbf8e6b85c212a157ddfbe77e'
						)
					)
```

### LLM

- ℹ️ Machine: DESKTOP-GITPJFF via `snappr-win`. Snapshot test `tests/programs-osquery-report.vala`. Osquery `authenticode` after expanding `\SystemRoot` and a leading `system32\`.
- ℹ️ Already-resolved services, from that same test output: signer `Microsoft Windows Publisher` 226, `Microsoft Windows` 6, `Microsoft Corporation` 11.
- ℹ️ `WinVerifyTrust` on `C:\Windows\System32\drivers\1394ohci.sys` is trusted. The signature is in a Windows catalog, not inside the file. `certutil -dump` on that file returns `CRYPT_E_NO_MATCH`. [`win32/pe-authenticode.c`](../../win32/pe-authenticode.c) copies the certificate only from an embedded signature, so `signer_cert_sha256` stays empty for those drivers until the reader takes the certificate from the trust result. Until that is filled, the list filter does not hide them.
- ℹ️ Windows leaf SHA-256 `1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de` is the value [Joe Sandbox lists for Ntfs.sys](https://www.joesandbox.com/analysis/1772502/1/html), with SHA-1 `3B77DB29AC72AA6B5880ECB2ED5EC1EC6601D847`, subject Microsoft Windows, issuer Microsoft Windows Production PCA 2011, signature check completed successfully. `signer_cert_sha256` stores that SHA-256.
- ℹ️ Early-launch SHA-1 `B6DB1A725D0F6A336C51DF6CD40A6A10C9242F04` is `WdBoot.sys`, subject Microsoft Windows Early Launch Anti-malware Publisher. No public page lists it. It is not the SHA-256 stored in `signer_cert_sha256`.
- ℹ️ `VBoxGuest.sys` and `VBoxSF.sys` are `6022340C9F4CB00307DF8DB036D392ADAC766212`, subject `CN=Microsoft Windows Hardware Compatibility Publisher`.
- ℹ️ `signer_subject_key_id` is the key id inside the certificate. It can stay the same when Microsoft reissues that cert. The filter uses the certificate thumbprint, which is the id already stored for the ignore set.
- 🚫 Do not filter on `signer_publisher` or the certificate display name.
- 🚫 Do not treat thumbprint `6022340c9f4cb00307df8db036d392adac766212` as Windows. That is the hardware-compatibility certificate on the VirtualBox drivers.
- 🚫 Do not hide a Microsoft Corporation certificate. Those services are Office, Edge, .NET, and Visual Studio.
- 🚫 Do not hide startup-folder rows. On this machine they are Edge, OneDrive, OpenVPN, and VirtualBox.
- 🚫 Do not drop the service from the snapshot. `list` hides it. An empty `signing_result` stays visible.
- ℹ️ The path forms seen were `\SystemRoot\...` and `system32\...`. `%SystemRoot%` was not in this snapshot.
