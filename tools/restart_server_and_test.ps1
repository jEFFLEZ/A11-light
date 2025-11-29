# Restart server.cjs safely and run nez tests
$ErrorActionPreference = 'Stop'

Write-Host "== Restart server.cjs and run NEZ tests =="
Set-Location -Path "D:\A11"

# Stop any existing server.cjs processes
Write-Host "Stopping existing server.cjs processes (if any)..."
$procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and ($_.CommandLine -like '*server.cjs*') }
if ($procs) {
    foreach ($p in $procs) {
        try {
            Write-Host ("Stopping PID {0} ..." -f $p.ProcessId)
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning ("Failed to stop PID {0}: {1}" -f $p.ProcessId, $_.Exception.Message)
        }
    }
} else {
    Write-Host "No server.cjs process found"
}

Start-Sleep -Seconds 1

# Start the server
Write-Host "Starting server (node server.cjs) in D:\A11\apps\server ..."
$startInfo = Start-Process -FilePath 'node' -ArgumentList 'server.cjs' -WorkingDirectory 'D:\A11\apps\server' -WindowStyle Hidden -PassThru
Write-Host ("Started PID {0}" -f $startInfo.Id)

# Wait for health to respond (try localhost variants)
$hosts = @('127.0.0.1','127.0.0.2')
$healthy = $false
$timeout = [DateTime]::UtcNow.AddSeconds(30)
while (-not $healthy -and [DateTime]::UtcNow -lt $timeout) {
    foreach ($h in $hosts) {
        try {
            $url = "http://$h:3000/health"
            $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 3 -ErrorAction Stop
            Write-Host ("Health OK on {0}:" -f $h)
            $resp | ConvertTo-Json -Depth 3 | Write-Host
            $healthy = $true
            break
        } catch {
            Write-Host ("Health not ready on {0}" -f $h)
        }
    }
    if (-not $healthy) { Start-Sleep -Seconds 2 }
}

if (-not $healthy) {
    Write-Warning "Server did not become healthy within timeout. Proceeding to run tests may fail."
}

# Run existing test script
Write-Host "Running tools/run_nez_test.ps1 ..."
try {
    pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run_nez_test.ps1
} catch {
    Write-Warning "run_nez_test failed: $($_.Exception.Message)"
}

Write-Host "Done."