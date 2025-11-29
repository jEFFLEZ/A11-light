$src='C:\Users\cella\.cloudflared\backup\9619b595-201d-4f87-b0ed-538f6aeb9fbf.json'
$dst='C:\Users\cella\.cloudflared\9619b595-201d-4f87-b0ed-538f6aeb9fbf.json'
if (-not (Test-Path $src)) { Write-Host "Backup not found: $src"; exit 2 }
Copy-Item -Path $src -Destination $dst -Force
try { icacls $dst /inheritance:r /grant:r "$env:USERNAME:(R)" | Out-Null } catch {}
Write-Host "Restored: $dst"
$log='D:\A11\cloudflared.log'
if (Test-Path $log) { Remove-Item $log -Force }
$cfpath='C:\Program Files\cloudflared\cloudflared.exe'
if (-not (Test-Path $cfpath)) { Write-Host "cloudflared binary not found at $cfpath"; exit 3 }
$arglist = @('tunnel','run','--config','C:\Users\cella\.cloudflared\config.yml','--loglevel','debug','--logfile',$log)
try {
  $proc = Start-Process -FilePath $cfpath -ArgumentList $arglist -PassThru -ErrorAction Stop
  Start-Sleep -Seconds 4
  Write-Host "Started cloudflared PID: $($proc.Id)"
} catch {
  Write-Host "Failed to start cloudflared: $($_.Exception.Message)"
  exit 4
}
if (Test-Path $log) { Write-Host '--- cloudflared.log (tail 120) ---'; Get-Content $log -Tail 120 | ForEach-Object { Write-Host $_ } } else { Write-Host 'No cloudflared.log yet' }
try { $h=Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health' -TimeoutSec 5 -ErrorAction Stop; Write-Host 'Backend health:'; Write-Host (ConvertTo-Json $h -Depth 5) } catch { Write-Host 'Backend no-response:' $_.Exception.Message }
