# Throwaway T1a: osquery (authenticode + hash) vs Win32 Authenticode (cert ids + publisher).
# Proves what we can get from osquery alone vs what needs a secondary call on the agent.
#
# Usage (Windows, osqueryi on PATH):
#   Get-Content paths.txt | .\programs-authenticode-compare.ps1 -OutFile compare.csv
#   .\programs-authenticode-compare.ps1 -Path 'C:\Windows\System32\lsass.exe'
#
# Optional: join registry publisher from export CSV (path, source, name, registry_publisher)
#   .\programs-authenticode-compare.ps1 -PathsFile paths.txt -RegistryCsv programs-paths.csv

param(
	[Parameter(ValueFromPipeline = $true)]
	[string[]]$Path,
	[string]$PathsFile = "",
	[string]$RegistryCsv = "",
	[string]$Osqueryi = "osqueryi",
	[string]$OutFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Escape-SqlString {
	param([string]$Value)
	return ($Value -replace "'", "''")
}

function Invoke-OsqueryJson {
	param([string]$Query)
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $Osqueryi
	$psi.Arguments = "--json `"$Query`""
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$p = [System.Diagnostics.Process]::Start($psi)
	$out = $p.StandardOutput.ReadToEnd()
	$err = $p.StandardError.ReadToEnd()
	$p.WaitForExit()
	if ($p.ExitCode -ne 0) {
		throw "osqueryi exit $($p.ExitCode): $err"
	}
	if ($out.Trim() -eq "") {
		return $null
	}
	return $out | ConvertFrom-Json
}

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
			$formatted = $ext.Format($false)
			if ($formatted -match "Key Id=(.+)") {
				return ($Matches[1] -replace "\s", "").ToLowerInvariant()
			}
		}
	}
	return ""
}

function Get-SignerPublisherCn {
	param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
	if (-not $Cert) { return "" }
	if ($Cert.Subject -match "(?:^|,)CN=([^,]+)") {
		return $Matches[1]
	}
	return $Cert.Subject
}

$registryByPath = @{}
if ($RegistryCsv -ne "" -and (Test-Path -LiteralPath $RegistryCsv)) {
	Import-Csv -LiteralPath $RegistryCsv | ForEach-Object {
		$key = $_.install_location
		if (-not $registryByPath.ContainsKey($key)) {
			$registryByPath[$key] = $_
		}
	}
}

function Compare-OnePath {
	param([string]$FilePath)
	$row = [ordered]@{
		path                    = $FilePath
		exists                  = $false
		registry_publisher      = ""
		registry_source         = ""
		registry_name           = ""
		osq_sha256              = ""
		osq_subject_name        = ""
		osq_issuer_name         = ""
		osq_serial_number       = ""
		osq_result              = ""
		osq_original_program_name = ""
		osq_error               = ""
		ps_sha256               = ""
		ps_signing_status       = ""
		signer_cert_sha256      = ""
		signer_subject_key_id   = ""
		signer_publisher_cn     = ""
		signer_subject          = ""
		signer_issuer           = ""
		signer_serial           = ""
		subject_match_osq_ps    = ""
		sha256_match_osq_ps     = ""
		error                   = ""
	}
	if ($registryByPath.ContainsKey($FilePath)) {
		$r = $registryByPath[$FilePath]
		$row.registry_publisher = $r.registry_publisher
		$row.registry_source = $r.source
		$row.registry_name = $r.name
	}
	try {
		if (-not (Test-Path -LiteralPath $FilePath)) {
			$row.error = "not_found"
			return [pscustomobject]$row
		}
		$row.exists = $true
		$ep = Escape-SqlString $FilePath
		try {
			$hashRows = Invoke-OsqueryJson "SELECT sha256 FROM hash WHERE path = '$ep' LIMIT 1;"
			if ($hashRows -and $hashRows.Count -gt 0) {
				$row.osq_sha256 = [string]$hashRows[0].sha256
			}
		} catch {
			$row.osq_error = "hash: $($_.Exception.Message)"
		}
		try {
			$authRows = Invoke-OsqueryJson @"
SELECT subject_name, issuer_name, serial_number, result, original_program_name
FROM authenticode WHERE path = '$ep' LIMIT 1;
"@
			if ($authRows -and $authRows.Count -gt 0) {
				$a = $authRows[0]
				$row.osq_subject_name = [string]$a.subject_name
				$row.osq_issuer_name = [string]$a.issuer_name
				$row.osq_serial_number = [string]$a.serial_number
				$row.osq_result = [string]$a.result
				$row.osq_original_program_name = [string]$a.original_program_name
			}
		} catch {
			$row.osq_error = ($row.osq_error + "; auth: " + $_.Exception.Message).Trim("; ")
		}
		$row.ps_sha256 = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
		$sig = Get-AuthenticodeSignature -LiteralPath $FilePath
		$row.ps_signing_status = $sig.Status.ToString()
		if ($sig.SignerCertificate) {
			$cert = $sig.SignerCertificate
			$row.signer_cert_sha256 = Get-CertSha256Thumbprint -Cert $cert
			$row.signer_subject_key_id = Get-SubjectKeyIdHex -Cert $cert
			$row.signer_publisher_cn = Get-SignerPublisherCn -Cert $cert
			$row.signer_subject = $cert.Subject
			$row.signer_issuer = $cert.Issuer
			$row.signer_serial = $cert.SerialNumber
		}
		$row.sha256_match_osq_ps = if ($row.osq_sha256 -ne "" -and $row.ps_sha256 -ne "") {
			if ($row.osq_sha256.ToLowerInvariant() -eq $row.ps_sha256) { "yes" } else { "no" }
		} else { "" }
		$row.subject_match_osq_ps = if ($row.osq_subject_name -ne "" -and $row.signer_publisher_cn -ne "") {
			if ($row.osq_subject_name -eq $row.signer_publisher_cn) { "yes" }
			elseif ($row.signer_subject -like "*$($row.osq_subject_name)*") { "partial" }
			else { "no" }
		} else { "" }
	} catch {
		$row.error = $_.Exception.Message
	}
	return [pscustomobject]$row
}

$allPaths = New-Object System.Collections.Generic.List[string]
if ($PathsFile -ne "") {
	Get-Content -LiteralPath $PathsFile | ForEach-Object {
		if (-not [string]::IsNullOrWhiteSpace($_)) { $allPaths.Add($_.Trim()) }
	}
}
foreach ($p in $Path) {
	if (-not [string]::IsNullOrWhiteSpace($p)) { $allPaths.Add($p.Trim()) }
}
$rows = New-Object System.Collections.Generic.List[object]
foreach ($p in $allPaths) {
	$rows.Add((Compare-OnePath -FilePath $p))
}
$csv = $rows | ConvertTo-Csv -NoTypeInformation
if ($OutFile -ne "") {
	$csv | Set-Content -LiteralPath $OutFile -Encoding UTF8
}
$csv | Write-Output