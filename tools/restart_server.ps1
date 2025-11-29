Write-Host 'Stopping server.cjs processes (if any)';
$p = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*server.cjs*' }
if ($p) { foreach ($x in $p) { Write-Host ('Stopping PID {0}' -f $x.ProcessId); Stop-Process -Id $x.ProcessId -Force -ErrorAction SilentlyContinue } } else { Write-Host 'No server.cjs running' }
Start-Sleep -Seconds 1
Write-Host 'Starting server in D:\A11\apps\server';
$proc = Start-Process -FilePath 'node' -ArgumentList 'server.cjs' -WorkingDirectory 'D:\A11\apps\server' -PassThru
Write-Host ('Started PID {0}' -f $proc.Id)
