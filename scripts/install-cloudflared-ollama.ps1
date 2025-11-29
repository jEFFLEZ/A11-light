# Install cloudflared and ollama to Program Files
# Run as Administrator
function Abort($msg){ Write-Host "ERROR: $msg"; exit 1 }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Abort 'Script must be run as Administrator.'
}
$ErrorActionPreference = 'Stop'
try {
  Write-Host '=== Installing cloudflared ==='
  $cfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
  $cfDestDir = Join-Path $env:ProgramFiles 'cloudflared'
  $cfExe = Join-Path $cfDestDir 'cloudflared.exe'
  if (-not (Test-Path $cfDestDir)) { New-Item -Path $cfDestDir -ItemType Directory -Force | Out-Null }
  $tmpCf = Join-Path $env:TEMP 'cloudflared.exe'
  Write-Host "Downloading cloudflared from $cfUrl to $tmpCf..."
  Invoke-WebRequest -Uri $cfUrl -OutFile $tmpCf -UseBasicParsing
  Move-Item -Path $tmpCf -Destination $cfExe -Force
  Write-Host "cloudflared installed to: $cfExe"
} catch {
  Write-Host "cloudflared install failed: $($_.Exception.Message)"
}
try {
  Write-Host '=== Installing Ollama ==='
  $ollUrl = 'https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip'
  $ollDestDir = Join-Path $env:ProgramFiles 'ollama'
  if (-not (Test-Path $ollDestDir)) { New-Item -Path $ollDestDir -ItemType Directory -Force | Out-Null }
  $tmpZip = Join-Path $env:TEMP 'ollama.zip'
  Write-Host "Downloading Ollama from $ollUrl to $tmpZip..."
  Invoke-WebRequest -Uri $ollUrl -OutFile $tmpZip -UseBasicParsing
  Write-Host 'Extracting...'
  Expand-Archive -Path $tmpZip -DestinationPath (Join-Path $env:TEMP 'ollama_extracted') -Force
  $found = Get-ChildItem -Path (Join-Path $env:TEMP 'ollama_extracted') -Filter 'ollama*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) {
    $ollExeDest = Join-Path $ollDestDir 'ollama.exe'
    Move-Item -Path $found.FullName -Destination $ollExeDest -Force
    Write-Host "ollama installed to: $ollExeDest"
  } else {
    Write-Host 'ollama binary not found in archive'
  }
} catch {
  Write-Host "ollama install failed: $($_.Exception.Message)"
}
# Update Machine PATH
try {
  Write-Host '=== Updating Machine PATH ==='
  $machinePath = [Environment]::GetEnvironmentVariable('Path',[EnvironmentVariableTarget]::Machine)
  $add = @((Join-Path $env:ProgramFiles 'cloudflared'), (Join-Path $env:ProgramFiles 'ollama'))
  foreach ($p in $add) {
    if ($p -and ($machinePath -notlike "*${p}*")) { $machinePath = $machinePath + ';' + $p }
  }
  [Environment]::SetEnvironmentVariable('Path',$machinePath,[EnvironmentVariableTarget]::Machine)
  Write-Host 'Machine PATH updated.'
} catch {
  Write-Host "Failed to update PATH: $($_.Exception.Message)"
}
# Verify
Write-Host '=== Verifying installations ==='
try { & (Join-Path $env:ProgramFiles 'cloudflared\cloudflared.exe') --version 2>&1 | Write-Host } catch { Write-Host 'cloudflared verify failed' }
try { & (Join-Path $env:ProgramFiles 'ollama\ollama.exe') --version 2>&1 | Write-Host } catch { Write-Host 'ollama verify failed' }
Write-Host 'Done. If versions shown, installation succeeded. You may need to open a new shell to use updated PATH.'
