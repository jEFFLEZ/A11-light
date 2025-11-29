param(
  [switch]$Auto
)

Write-Host "[install-ollama] Vérification de la présence d'ollama..." -ForegroundColor Cyan
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollamaCmd) {
  Write-Host "ollama déjà installé : $($ollamaCmd.Source)" -ForegroundColor Green
  exit 0
}

Write-Host "ollama non trouvé sur le système." -ForegroundColor Yellow

# If Auto and winget available, try winget install
$winget = Get-Command winget -ErrorAction SilentlyContinue
$choco = Get-Command choco -ErrorAction SilentlyContinue
$scoop = Get-Command scoop -ErrorAction SilentlyContinue

if ($Auto -and $winget) {
  Write-Host "Tentative d'installation automatique via winget..." -ForegroundColor Cyan
  try {
    & winget install --id Ollama.Ollama -e --source winget
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Installation via winget réussie. Vérifie 'ollama --version'." -ForegroundColor Green
      exit 0
    } else {
      Write-Host "winget a échoué (exit $LASTEXITCODE)." -ForegroundColor Yellow
    }
  } catch {
    Write-Host "Erreur winget: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

Write-Host "Aucune installation automatique réalisée." -ForegroundColor Yellow
Write-Host "Outils disponibles:" -ForegroundColor Cyan
Write-Host "  - winget : $([bool]$winget)" -ForegroundColor White
Write-Host "  - choco  : $([bool]$choco)" -ForegroundColor White
Write-Host "  - scoop  : $([bool]$scoop)" -ForegroundColor White

Write-Host "Ouvre la page de téléchargement d'Ollama dans ton navigateur..." -ForegroundColor Cyan
Start-Process "https://ollama.ai/download" -ErrorAction SilentlyContinue

Write-Host "Instructions manuelles recommandées:" -ForegroundColor Green
Write-Host "  1) Télécharge et installe depuis https://ollama.ai/download" -ForegroundColor White
Write-Host "  2) Ajoute le répertoire d'installation à ton PATH si nécessaire" -ForegroundColor White
Write-Host "  3) Vérifie avec: ollama --version" -ForegroundColor White

Write-Host "Si tu veux tenter une installation automatique (winget), relance ce script avec -Auto si winget est installé." -ForegroundColor Yellow
exit 0
