<#
Save Netlify token and site id to a restricted .env.netlify file.
Usage:
  - Interactive prompt: pwsh -File scripts\save-netlify-token.ps1
  - Non-interactive: pwsh -File scripts\save-netlify-token.ps1 -Token '<token>' -SiteId '<site_id>'

The script writes D:\A11\.env.netlify and sets file ACLs so only the current user can read it.
#>
param(
  [string]$Token,
  [string]$SiteId
)

function PromptSecure([string]$prompt) {
  $ss = Read-Host -AsSecureString $prompt
  return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
}

try {
  if (-not $Token) {
    $Token = PromptSecure 'Enter NETLIFY_AUTH_TOKEN (input hidden)'
  }
  if (-not $SiteId) {
    $SiteId = Read-Host 'Enter NETLIFY_SITE_ID (or leave empty)'
  }

  if (-not $Token) { Write-Error 'NETLIFY_AUTH_TOKEN is required.'; exit 1 }

  $root = (Resolve-Path -Path .).Path
  $envFile = Join-Path $root '.env.netlify'

  $content = @()
  $content += "NETLIFY_AUTH_TOKEN=$Token"
  if ($SiteId) { $content += "NETLIFY_SITE_ID=$SiteId" }

  Set-Content -Path $envFile -Value $content -Encoding UTF8 -Force

  Write-Host "Wrote $envFile"

  # Restrict ACLs: remove inheritance and grant full control to current user only
  try {
    $user = "$env:USERDOMAIN\\$env:USERNAME"
    icacls $envFile /inheritance:r | Out-Null
    icacls $envFile /grant:r "${user}:(R)" | Out-Null
    icacls $envFile /remove "Everyone" | Out-Null
    Write-Host "Restricted permissions on $envFile to $user"
  } catch {
    Write-Warning "Failed to adjust ACLs: $($_.Exception.Message)"
    Write-Host "You may want to run: icacls $envFile /inheritance:r ; icacls $envFile /grant:r \"$env:USERDOMAIN\\$env:USERNAME:(R)\""
  }

  Write-Host 'Done. Keep .env.netlify secret. To push envs to Netlify, run the provided script or use envapt/netlify CLI.'
} catch {
  Write-Error "Error: $($_.Exception.Message)"
  exit 1
}
