<#
create-3node-shortcut.ps1
Crée un raccourci sur le bureau nommé "Start-A11-3Node.lnk" qui lance le helper batch
Start-A11-Full-helper.bat (démarre frontend, ollama, backend dans 3 fenêtres PowerShell).
Usage:
  pwsh -ExecutionPolicy Bypass -File .\scripts\create-3node-shortcut.ps1
#>

$ErrorActionPreference = 'Stop'
try {
    $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    # Assume helper batch is at repository root
    $repoRoot = Resolve-Path (Join-Path $scriptDir '..') | Select-Object -ExpandProperty Path
    $helper = Join-Path $repoRoot 'Start-A11-Full-helper.bat'
    if (-not (Test-Path $helper)) {
        Write-Error "Helper batch introuvable: $helper. Assurez-vous qu'il existe."
        exit 1
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutName = 'Start-A11-3Node.lnk'
    $shortcutPath = Join-Path $desktop $shortcutName

    # Remove existing shortcut if present
    if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force }

    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)

    # Use pwsh to ensure we can cd to D:\A11 and run the helper in the correct working directory
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        $shortcut.TargetPath = $pwsh.Source
        # Build a safe -Command argument that sets location and invokes the helper batch
        $command = "Set-Location -LiteralPath 'D:\\A11'; & '$helper'"
        # Escape the command argument by wrapping in `" ... `" so PowerShell executes correctly when invoked via shortcut
        $arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -Command `"$command`""
        $shortcut.Arguments = $arguments
        $shortcut.WorkingDirectory = 'D:\A11'
    } else {
        # Fallback: point directly to the batch file (Windows will use default handler)
        $shortcut.TargetPath = $helper
        $shortcut.WorkingDirectory = Split-Path $helper
    }

    $shortcut.WindowStyle = 1
    $shortcut.Description = 'Start A11 (Frontend, Ollama, Backend) — ouvre 3 fenêtres PowerShell'
    # try use pwsh icon if available, fallback to batch icon
    if ($pwsh) { $shortcut.IconLocation = "$($pwsh.Source),0" } else { $shortcut.IconLocation = "$helper,0" }
    $shortcut.Save()

    Write-Host "Raccourci créé sur le bureau : $shortcutPath" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "Erreur lors de la création du raccourci : $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
