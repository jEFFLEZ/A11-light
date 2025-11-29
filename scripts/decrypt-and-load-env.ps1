<#
Decrypt and load environment variables from a .env.enc file produced by scripts/encrypt-env.ps1
Usage:
  pwsh -File scripts/decrypt-and-load-env.ps1          # loads .env.enc into process env (current PowerShell session)
  pwsh -File scripts/decrypt-and-load-env.ps1 -EncPath ".env.enc" -Force   # force overwrite existing env vars
  pwsh -File scripts/decrypt-and-load-env.ps1 -EncPath ".env.enc" -Preview # list keys that would be set (no values shown)

Security notes:
- This script uses DPAPI-protected strings produced by ConvertFrom-SecureString.
  Decryption works only for the same Windows user account on the same machine.
- The script never prints secret values to the console. It will only indicate which keys were set.
#>

param(
  [string]$EncPath = "$PSScriptRoot\..\.env.enc",
  [switch]$Force,
  [switch]$Preview
)

function Parse-EncEnv($path) {
  $h = @{}
  if (-not (Test-Path $path)) { throw "File not found: $path" }
  $lines = Get-Content $path | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
  foreach ($l in $lines) {
    if ($l -match "^\s*([^=]+)=(.*)$") {
      $k = $matches[1].Trim()
      $v = $matches[2].Trim()
      # Remove optional surrounding quotes
      if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Trim('"') }
      if ($v.StartsWith("'") -and $v.EndsWith("'")) { $v = $v.Trim("'") }
      $h[$k] = $v
    }
  }
  return $h
}

Write-Host "[decrypt-and-load-env] Reading $EncPath" -ForegroundColor Cyan
try {
  $pairs = Parse-EncEnv $EncPath
} catch {
  Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 2
}

foreach ($k in $pairs.Keys | Sort-Object) {
  $v = $pairs[$k]
  try {
    if ($v -and $v.StartsWith('ENC:')) {
      # Encrypted DPAPI string -> decrypt
      $cipher = $v.Substring(4)
      # Convert back to SecureString (DPAPI)
      $secure = ConvertTo-SecureString $cipher -ErrorAction Stop
      # Convert SecureString to plain text in-memory
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
      try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
      } finally {
        if ($bstr) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
      }

      if ($Preview) {
        Write-Host "[preview] (encrypted) $k => (will set)" -ForegroundColor Yellow
        continue
      }

      # Only set if Force or not already defined
      if ($Force -or -not (Get-Item env:$k -ErrorAction SilentlyContinue)) {
        Set-Item -Path "Env:$k" -Value $plain -ErrorAction Stop
        Write-Host "Set env: $k" -ForegroundColor Green
      } else {
        Write-Host "Skipped (exists): $k" -ForegroundColor DarkYellow
      }
    } else {
      # Plain value
      if ($Preview) {
        Write-Host "[preview] $k => (will set plain)" -ForegroundColor Yellow
        continue
      }
      if ($Force -or -not (Get-Item env:$k -ErrorAction SilentlyContinue)) {
        Set-Item -Path "Env:$k" -Value $v -ErrorAction Stop
        Write-Host "Set env: $k" -ForegroundColor Green
      } else {
        Write-Host "Skipped (exists): $k" -ForegroundColor DarkYellow
      }
    }
  } catch {
    Write-Host ("Failed to set {0}: {1}" -f $k, $_.Exception.Message) -ForegroundColor Red
  }
}

Write-Host "Done. Use 'Get-ChildItem Env:' to inspect environment variables in this session (values not printed by this script)." -ForegroundColor Cyan

# End of script
