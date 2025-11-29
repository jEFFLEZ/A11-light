param(
  [switch]$Background,
  [switch]$ForceEnvLoad
)

# Start only the A11 backend server (no Ollama). Useful for debugging OpenAI provider.
# Usage:
#   pwsh -File scripts/start-server-only.ps1          # runs in foreground (shows logs)
#   pwsh -File scripts/start-server-only.ps1 -Background # starts as background process

function Load-DotEnvIfPresent($path) {
  if (Test-Path $path) {
    try {
      $lines = Get-Content $path | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
      foreach ($l in $lines) {
        if ($l -match "^\s*([^=]+)=(.*)") {
          $k = $matches[1].Trim()
          $v = $matches[2].Trim().Trim('"')
          if ($ForceEnvLoad -or -not (Test-Path "Env:$k")) {
            Set-Item -Path "Env:$k" -Value $v -ErrorAction SilentlyContinue
          }
        }
      }
      Write-Host ("Loaded env from {0}" -f $path)
    } catch {
      Write-Host ("Failed to load env from {0}: {1}" -f $path, $_.Exception.Message) -ForegroundColor Yellow
    }
  }
}

# Prefer apps/server/.env.local then repo root .env
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path "$scriptDir\.." | Select-Object -ExpandProperty Path
$localEnv = Join-Path $repoRoot 'apps\server\.env.local'
$rootEnv = Join-Path $repoRoot '.env'

Load-DotEnvIfPresent $localEnv
Load-DotEnvIfPresent $rootEnv

if (-not $env:HOST_SERVER) { $env:HOST_SERVER = '127.0.0.1' }
if (-not $env:PORT) { $env:PORT = '3000' }
if (-not $env:LLAMA_HOST) { $env:LLAMA_HOST = '127.0.0.2' }
if (-not $env:LLAMA_PORT) { $env:LLAMA_PORT = '11434' }
$env:LLAMA_BASE = "http://$($env:LLAMA_HOST):$($env:LLAMA_PORT)"

$serverPath = Join-Path $repoRoot 'apps\server'
if (-not (Test-Path $serverPath)) {
  Write-Host "Server directory not found: $serverPath" -ForegroundColor Red
  exit 1
}

Set-Location $serverPath
Write-Host ("Starting A11 server in {0} (HOST={1} PORT={2})" -f $serverPath, $env:HOST_SERVER, $env:PORT) -ForegroundColor Cyan

if ($Background) {
  # Start as detached process
  $startInfo = Start-Process -FilePath "node" -ArgumentList "server.cjs" -WorkingDirectory $serverPath -PassThru
  if ($startInfo) {
    Write-Host ("Server started as background process (PID: {0})" -f $startInfo.Id) -ForegroundColor Green
    exit 0
  } else {
    Write-Host "Failed to start server in background." -ForegroundColor Red
    exit 2
  }
} else {
  # Run in foreground so logs are visible
  try {
    & node server.cjs
  } catch {
    Write-Host ("Server exited with error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
  }
}
