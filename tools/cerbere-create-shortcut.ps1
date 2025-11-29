<# Create a desktop shortcut to launch cerbere.ps1 #>
$script = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'cerbere.ps1'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop 'cerbere.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($lnk)
$Shortcut.TargetPath = 'pwsh'
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$Shortcut.WorkingDirectory = Split-Path -Parent $script
$Shortcut.WindowStyle = 1
$Shortcut.Save()
Write-Host "Shortcut created on desktop: $lnk"
