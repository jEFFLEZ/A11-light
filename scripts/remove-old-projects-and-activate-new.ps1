param(
    [switch]$Force
)

# Check for common IDE/build processes that may lock project files
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'devenv','msbuild','dotnet' }
if ($procs -and -not $Force) {
    Write-Host "Processus IDE/MSBuild détectés (verrou potentiel):"
    $procs | ForEach-Object { Write-Host " - $($_.Name)   Id: $($_.Id)" }
    Write-Host "Fermez ces processus puis relancez ce script, ou exécutez avec -Force pour tenter la suppression malgré tout." -ForegroundColor Yellow
    exit 1
}

$cwd = Get-Location
Write-Host "Travail dans: $cwd"

$toRemove = @("A11-System.proj","A11-System-alt.proj")
foreach ($f in $toRemove) {
    if (Test-Path $f) {
        try {
            Remove-Item $f -Force -ErrorAction Stop
            Write-Host "Supprimé: $f"
        } catch {
            Write-Host "Échec suppression ${f}: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Non trouvé: $f"
    }
}

# Activate the consolidated file if present
$newFile = "A11.proj.new"
$targetName = "A11-System.proj"
if (Test-Path $newFile) {
    if (Test-Path $targetName) {
        Write-Host "$targetName existe déjà. Suppression nécessaire avant renommage." -ForegroundColor Yellow
    } else {
        try {
            Move-Item -Path $newFile -Destination $targetName -Force -ErrorAction Stop
            Write-Host "Renommé $newFile -> $targetName"
        } catch {
            Write-Host "Échec renommage: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "$newFile introuvable. Rien à renommer." -ForegroundColor Yellow
}

Write-Host "Opération terminée."