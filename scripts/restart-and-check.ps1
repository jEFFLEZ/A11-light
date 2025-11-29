# restart-and-check.ps1
# Stops node server.cjs processes, launches start-a11-system.ps1, then checks health/diagnostic/ollama/public and cloudflared config

Write-Host "[STEP] Stop node server.cjs processes if running"
try {
    $procs = Get-WmiObject Win32_Process | Where-Object { $_.Name -match 'node' -and $_.CommandLine -match 'server.cjs' }
    if ($procs) {
        foreach ($p in $procs) {
            Write-Host "Stopping PID $($p.ProcessId) - CMD: $($p.CommandLine)"
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
    } else {
        Write-Host "No node server.cjs processes found"
    }
} catch {
    Write-Host "Warning: failed to inspect processes: $($_.Exception.Message)"
}

Write-Host "[STEP] Start start-a11-system.ps1 (background)"
try {
    $startScript = Join-Path (Get-Location) 'start-a11-system.ps1'
    if (-not (Test-Path $startScript)) { $startScript = 'D:\A11\start-a11-system.ps1' }
    Start-Process -FilePath pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$startScript -WindowStyle Hidden -ErrorAction Stop
    Write-Host "Launched $startScript"
} catch {
    Write-Host "Failed to launch start script: $($_.Exception.Message)"
}

Start-Sleep -Seconds 8

function TryInvoke($url, $timeout=5) {
    try {
        $r = Invoke-RestMethod -Uri $url -TimeoutSec $timeout
        Write-Host "OK: $url"
        $r | ConvertTo-Json -Depth 5 | Write-Host
    } catch {
        Write-Host "FAIL: $url -> $($_.Exception.Message)"
    }
}

Write-Host "[STEP] Checking local health"
TryInvoke 'http://127.0.0.1:3000/health' 5

Write-Host "[STEP] Checking diagnostic"
TryInvoke 'http://127.0.0.1:3000/api/diagnostic' 10

Write-Host "[STEP] Checking Ollama (11434)"
TryInvoke 'http://127.0.0.1:11434/api/tags' 5

Write-Host "[STEP] Checking public health https://api.funesterie.me/health"
TryInvoke 'https://api.funesterie.me/health' 10

$cloudCfg = 'C:\Users\cella\.cloudflared\config.yml'
if (Test-Path $cloudCfg) { Write-Host "CLOUDFLARED CONFIG FOUND: $cloudCfg" } else { Write-Host "CLOUDFLARED CONFIG NOT FOUND: $cloudCfg" }

Write-Host "[STEP] Tail server logs (last 200 lines)"
if (Test-Path 'server.out.log') { Get-Content -Path 'server.out.log' -Tail 200 | Write-Host } else { Write-Host 'server.out.log not found' }
if (Test-Path 'server.err.log') { Get-Content -Path 'server.err.log' -Tail 200 | Write-Host } else { Write-Host 'server.err.log not found' }

Write-Host "[DONE]"