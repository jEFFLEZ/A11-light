<#
Quick helper to start the A-11 local stack (backend, router, frontend).
Creates separate PowerShell windows for each service so logs remain visible.

Usage: Run this script with PowerShell (ExecutionPolicy bypass if needed):
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\cerbere.ps1

Notes:
- The backend (apps/server) will auto-launch a local `llama-server` if no LLAMA_BASE is set.
- Ollama startup is optional and attempted only if an `ollama` executable is found; adjust OLLAMA_START_CMD as needed.
- This script creates new terminals (pwsh) so you can keep an eye on output.
#>

param()

# Use PSScriptRoot to reliably get script directory and compute repo root
$root = $PSScriptRoot
# Compute repo root as parent of script directory
$repoRootStr = (Get-Item (Join-Path $root '..')).FullName
Write-Host "[cerbere] repoRoot = $repoRootStr"

function Start-WindowedProcess($workDir, $label, $command) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command powershell -ErrorAction SilentlyContinue }
    if (-not $pwsh) {
        Write-Warning "No pwsh/powershell found in PATH. Cannot launch $label in a new window."
        return
    }

    # Pass working directory to Start-Process to avoid quoting problems with paths that contain spaces
    $argList = @('-NoExit', '-NoProfile', '-Command', $command)

    Write-Host "[cerbere] Launching $label -> $command (cwd: $workDir)"
    Start-Process -FilePath $pwsh.Path -ArgumentList $argList -WorkingDirectory $workDir
}

# 1) Backend (apps/server) - will spawn llama-server if needed
$backendDir = Join-Path $repoRootStr 'apps\server'
Start-WindowedProcess $backendDir 'backend' 'npm run dev'

# 2) Router (llm-router) - optional but recommended
# router lives inside apps/server; use npm script dev:router
Start-WindowedProcess $backendDir 'router' 'npm run dev:router'

# 3) Frontend (apps/web)
$webDir = Join-Path $repoRootStr 'apps\web'
Start-WindowedProcess $webDir 'frontend' 'npm run dev'

# 4) Optional: Ollama (if present on PATH) - start in its own window
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaCmd) {
    # Use the windowed launcher so logs are visible
    $ollamaWork = Split-Path $ollamaCmd.Path
    # Some Ollama versions use 'serve' rather than 'daemon'
    Start-WindowedProcess $ollamaWork 'ollama' "& '$($ollamaCmd.Path)' serve"
} else {
    Write-Host "[cerbere] No 'ollama' executable found in PATH. Skipping ollama start. You can start it manually (ollama serve)."
}

# 5) Optional: llama-server (llama.cpp) - try to start if an executable is found
function Find-LlamaServerExe() {
    $candidates = @(
        [System.IO.Path]::Combine($repoRootStr, 'llama.cpp','build','bin','Release','llama-server.exe'),
        [System.IO.Path]::Combine($repoRootStr, 'llama.cpp','build','bin','llama-server.exe'),
        'C:\Program Files\llama\llama-server.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

$llamaExe = Find-LlamaServerExe
if ($llamaExe) {
    # Prepare reasonable default args; user can edit .env.local to control CTX/BATCH/PARALLEL
    $model = $env:DEFAULT_MODEL
    # prefer project Models/keykey default if present
    if (-not $model -or $model -eq '') {
        $candidateModel = Join-Path $repoRootStr 'Models\keykey\Llama-3.2-3B-Instruct-Q4_K_M.gguf'
        if (Test-Path $candidateModel) {
            $model = $candidateModel
            Write-Host "[cerbere] Using discovered model: $model"
        } else {
            $model = Join-Path $repoRootStr 'models\default.gguf'
        }
    }
    $ctx = $env:CTX_SIZE; if (-not $ctx) { $ctx = 8192 }
    $batch = $env:BATCH_SIZE; if (-not $batch) { $batch = 4096 }
    $parallel = $env:PARALLEL; if (-not $parallel) { $parallel = 8 }

    $llamaArgs = "-m `"$model`" --host 127.0.0.1 --port 8000 --ctx-size $ctx --batch-size $batch --parallel $parallel --temp 0.7"
    Start-WindowedProcess (Split-Path $llamaExe) 'llama-server' "& '$llamaExe' $llamaArgs"
} else {
    Write-Host "[cerbere] No llama-server.exe found in common locations. Skipping auto-start of llama-server."
    Write-Host "If you want to start it manually, run something like:`n  .\llama.cpp\build\bin\Release\llama-server.exe -m C:\path\to\model.gguf --host 127.0.0.1 --port 8000"
}

Write-Host "[cerbere] Launched services. Check the new windows for logs."
Write-Host "If you want a desktop shortcut, run tools\cerbere-create-shortcut.ps1 (optional)."
