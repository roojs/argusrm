# Throwaway: Authenticode + file SHA256 for programs noise filtering (Phase 1).
# Run on a Windows host that can read the PE paths (not on Linux — signatures are Win32).
#
# Usage:
#   Get-Content paths.txt | .\programs-authenticode-probe.ps1
#   .\programs-authenticode-probe.ps1 -Path C:\Windows\System32\lsass.exe
#   sqlite3 argus.sqlite "SELECT DISTINCT install_location FROM programs WHERE install_location LIKE '%.exe'" |
#     ssh user@winbox 'Out-File paths.txt -Encoding utf8'  # then run probe there
#
# Output: CSV to stdout (and optional -OutFile). Columns match docs/bugs/2026-11-23-ISSUE-programs-windows-installed-vs-noise.md

param(
	[Parameter(ValueFromPipeline = $true)]
	[string[]]$Path,
	[string]$OutFile = "",
	[switch]$IncludePublisher
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CertSha256Thumbprint {
	param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
	if (-not $Cert) { return "" }
	$hash = $Cert.GetCertHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
	return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function Get-SubjectKeyIdHex {
	param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
	if (-not $Cert) { return "" }
	foreach ($ext in $Cert.Extensions) {
		if ($ext.Oid.Value -eq "2.5.29.14") {
			# Format returns "Key Id=ab cd ..."; strip prefix and spaces.
			$formatted = $ext.Format($false)
			if ($formatted -match "Key Id=(.+)") {
				return ($Matches[1] -replace "\s", "").ToLowerInvariant()
			}
			return ([System.BitConverter]::ToString($ext.RawData)).Replace("-", "").ToLowerInvariant()
		}
	}
	return ""
}

function Get-SignerSubjectCn {
	param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
	if (-not $Cert) { return "" }
	return $Cert.Subject -replace "^CN=", "" -replace ",.*$", ""
}

function Probe-OnePath {
	param([string]$FilePath)
	$row = [ordered]@{
		path                 = $FilePath
		exists               = $false
		file_sha256          = ""
		signing_status       = ""
		signer_cert_sha256   = ""
		signer_subject_key_id = ""
		signer_publisher_cn  = ""
		signer_subject       = ""
		signer_issuer        = ""
		signer_serial        = ""
		time_stamp_cert_sha256 = ""
		error                = ""
	}
	try {
		if (-not (Test-Path -LiteralPath $FilePath)) {
			$row.error = "not_found"
			return [pscustomobject]$row
		}
		$row.exists = $true
		$row.file_sha256 = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
		$sig = Get-AuthenticodeSignature -LiteralPath $FilePath
		$row.signing_status = $sig.Status.ToString()
		if ($sig.SignerCertificate) {
			$cert = $sig.SignerCertificate
			$row.signer_cert_sha256 = Get-CertSha256Thumbprint -Cert $cert
			$row.signer_subject_key_id = Get-SubjectKeyIdHex -Cert $cert
			$row.signer_publisher_cn = Get-SignerSubjectCn -Cert $cert
			$row.signer_subject = $cert.Subject
			$row.signer_issuer = $cert.Issuer
			$row.signer_serial = $cert.SerialNumber
		}
		if ($sig.TimeStamperCertificate) {
			$row.time_stamp_cert_sha256 = Get-CertSha256Thumbprint -Cert $sig.TimeStamperCertificate
		}
	} catch {
		$row.error = $_.Exception.Message
	}
	return [pscustomobject]$row
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($p in $Path) {
	if ([string]::IsNullOrWhiteSpace($p)) { continue }
	$rows.Add((Probe-OnePath -FilePath $p.Trim()))
}
if ($rows.Count -eq 0 -and $args.Count -gt 0) {
	foreach ($p in $args) {
		$rows.Add((Probe-OnePath -FilePath $p))
	}
}
$csv = $rows | ConvertTo-Csv -NoTypeInformation
if ($OutFile -ne "") {
	$csv | Set-Content -LiteralPath $OutFile -Encoding UTF8
}
$csv | Write-Output