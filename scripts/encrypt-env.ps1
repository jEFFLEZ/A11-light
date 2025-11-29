param(
  [string]$RootEnv = "$PSScriptRoot\..\.env",
  [string]$LocalEnv = "$PSScriptRoot\..\apps\server\.env.local",
  [string]$OutPath = "$PSScriptRoot\..\.env.enc"
)

# Sensitive keys list - extend as needed
$sensitive = @(
  'OPENAI_API_KEY',
  'CF_ACCESS_CLIENT_SECRET',
  'CF_ACCESS_CLIENT_ID',
  'OCRSPACE_API_KEY',
  'A11_PASS',
  'DATABASE_URL'
)

function Parse-DotEnv($path) {
  $h = @{}
  if (-not (Test-Path $path)) { return $h }
  $lines = Get-Content $path | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
  foreach ($l in $lines) {
    if ($l -match "^\s*([^=]+)=(.*)$") {
      $k = $matches[1].Trim()
      $v = $matches[2].Trim()
      # Trim optional surrounding quotes
      if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Trim('"') }
      if ($v.StartsWith("'") -and $v.EndsWith("'")) { $v = $v.Trim("'") }
      $h[$k] = $v
    }
  }
  return $h
}

Write-Host "[encrypt-env] Loading env files (root=$RootEnv, local=$LocalEnv)" -ForegroundColor Cyan
$root = Parse-DotEnv $RootEnv
$local = Parse-DotEnv $LocalEnv

# Merge: root wins, otherwise local
$merged = @{}
foreach ($k in ($root.Keys + $local.Keys | Sort-Object -Unique)) {
  if ($root.ContainsKey($k) -and $root[$k]) { $merged[$k] = $root[$k] }
  elseif ($local.ContainsKey($k) -and $local[$k]) { $merged[$k] = $local[$k] }
  else { $merged[$k] = '' }
}

# Build encrypted output
$out = @()
foreach ($k in $merged.Keys | Sort-Object) {
  $v = $merged[$k]
  if ($sensitive -contains $k -and $v) {
    try {
      $secure = ConvertTo-SecureString $v -AsPlainText -Force
      $encrypted = $secure | ConvertFrom-SecureString
      $out += "$k=ENC:$encrypted"
      Write-Host "Encrypted $k" -ForegroundColor Green
    } catch {
      Write-Host ("Failed to encrypt {0}: {1}" -f $k, $_.Exception.Message) -ForegroundColor Yellow
    }
  } else {
    # Non-sensitive or empty
    $escaped = $v -replace '"','\"'
    $out += "$k=`"$escaped`""
  }
}

# Backup existing enc file
if (Test-Path $OutPath) {
  $bak = "$OutPath.bak_$(Get-Date -Format o).bak"
  Copy-Item $OutPath $bak -Force
  Write-Host "Backed up existing $OutPath -> $bak" -ForegroundColor Yellow
}

$out | Set-Content -Path $OutPath -Encoding UTF8
Write-Host "Wrote encrypted env to $OutPath" -ForegroundColor Cyan
Write-Host "NOTE: .env.enc contains DPAPI-protected values readable only by this user on this machine." -ForegroundColor Yellow

