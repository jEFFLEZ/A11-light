# Remove A11 startup artifacts: scheduled tasks, services, startup shortcuts, registry Run entries
$keywords = @('a11','alpha','funest','start-a11','cloudflared','ollama','funesterie')
Write-Host "Keywords: $($keywords -join ', ')"`n
# Scheduled Tasks
try {
  Write-Host '== Scheduled Tasks =='
  $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
  if ($tasks) {
    foreach ($t in $tasks) {
      $match = $false
      foreach ($kw in $keywords) { if ($t.TaskName -match $kw -or ($t.TaskPath -and $t.TaskPath -match $kw)) { $match = $true; break } }
      if ($match) {
        Write-Host "Disabling Scheduled Task: $($t.TaskName)"
        try { Disable-ScheduledTask -TaskName $t.TaskName -ErrorAction Stop; Write-Host " Disabled: $($t.TaskName)" } catch { Write-Host (' Disable failed: {0}' -f $_.Exception.Message) }
      }
    }
  } else { Write-Host 'No scheduled tasks found or insufficient privileges.' }
} catch { Write-Host ('Scheduled tasks step failed: {0}' -f $_.Exception.Message) }

# Services
Write-Host '\n== Services =='
foreach ($svcName in @('cloudflared')) {
  try {
    $sv = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($sv) {
      if ($sv.Status -ne 'Stopped') { Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue; Write-Host ('Stopped service: {0}' -f $svcName) }
      try { Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop; Write-Host ('Disabled service: {0}' -f $svcName) } catch { Write-Host ('Failed to change startup type: {0} - {1}' -f $svcName, $_.Exception.Message) }
    } else { Write-Host ('No service named {0}' -f $svcName) }
  } catch { Write-Host ('Service step failed for {0}: {1}' -f $svcName, $_.Exception.Message) }
}

# Startup folder shortcuts
Write-Host '\n== Startup Folder =='
$startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
try {
  if (Test-Path $startup) {
    Get-ChildItem -Path $startup -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
      foreach ($kw in $keywords) {
        if ($_.Name -match $kw -or $_.FullName -match $kw) {
          try { Remove-Item $_.FullName -Force -ErrorAction Stop; Write-Host ("Removed shortcut: {0}" -f $_.FullName) } catch { Write-Host ("Failed to remove shortcut: {0} - {1}" -f $_.FullName, $_.Exception.Message) }
          break
        }
      }
    }
  } else { Write-Host 'Startup folder not found.' }
} catch { Write-Host ('Startup folder step failed: {0}' -f $_.Exception.Message) }

# Registry Run entries
Write-Host '\n== Registry Run Keys =='
$runPaths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')
foreach ($rp in $runPaths) {
  try {
    if (Test-Path $rp) {
      $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue | Select-Object -Property *
      if ($props) {
        foreach ($p in $props.PSObject.Properties) {
          $name = $p.Name
          $value = (Get-ItemProperty -Path $rp -Name $name -ErrorAction SilentlyContinue).$name
          if ($value) {
            foreach ($kw in $keywords) {
              if ($value -match $kw -or $name -match $kw) {
                try { Remove-ItemProperty -Path $rp -Name $name -ErrorAction Stop; Write-Host ('Removed reg entry: {0} from {1}' -f $name, $rp) } catch { Write-Host ('Failed to remove reg entry: {0} - {1}' -f $name, $_.Exception.Message) }
                break
              }
            }
          }
        }
      }
    }
  } catch { Write-Host ('Registry step failed for {0}: {1}' -f $rp, $_.Exception.Message) }
}

Write-Host '\nDone. Review output above. Reboot required to fully apply service changes.'
