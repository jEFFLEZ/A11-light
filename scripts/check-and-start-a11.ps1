# Vérifie les prérequis pour A11 et lance le démarrage si demandé.
# Usage:
#   pwsh -File "scripts/check-and-start-a11.ps1"      # uniquement vérifications
#   pwsh -File "scripts/check-and-start-a11.ps1" -Start  # vérifications puis démarre start-a11-system.ps1
param(
    [switch]$Start
)
$root = "D:/A11"

function Check-Command($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $true }
    return $false
}

function Parse-DotEnv($path) {
    if (-not (Test-Path $path)) { return @{} }
    $lines = Get-Content $path | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
    $h = @{}
    foreach ($l in $lines) {
        if ($l -match "^\s*([^=]+)=(.*)") {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim().Trim('"')
            $h[$k] = $v
        }
    }
    return $h
}

Write-Host "[A11] Vérification des prérequis..." -ForegroundColor Cyan
$checks = @{}
$checks.Node = Check-Command node
$checks.Npm = Check-Command npm
$checks.Netlify = Check-Command netlify
$checks.Cloudflared = Check-Command cloudflared
$checks.Ollama = Check-Command ollama
$checks.Pwsh = Check-Command pwsh

foreach ($k in $checks.Keys) {
    $ok = $checks[$k]
    Write-Host "- $k :" ($(if ($ok) { "OK" } else { "MANQUANT" }))
}

# fichiers essentiels
$files = @{
    'backend' = Join-Path $root 'apps/server/server.cjs'
    'frontend package' = Join-Path $root 'apps/web/package.json'
    'netlify config' = Join-Path $root 'netlify.toml'
    'start script' = Join-Path $root 'start-a11-system.ps1'
}
foreach ($k in $files.Keys) {
    $exists = Test-Path $files[$k]
    Write-Host "- $k :" ($(if ($exists) { "OK" } else { "MANQUANT" }))
}

# env vars
$envPath = Join-Path $root '.env'
$env = Parse-DotEnv $envPath
$needed = @('CF_ACCESS_CLIENT_ID','CF_ACCESS_CLIENT_SECRET','UPSTREAM_ORIGIN','VITE_API_BASE','PORT')
Write-Host "\nVariables d'environnement :"
foreach ($n in $needed) {
    $present = $false
    if ($env.ContainsKey($n)) { $present = $true }
    elseif ([System.Environment]::GetEnvironmentVariable($n)) { $present = $true }
    if ($present) { Write-Host "- $n : OK" } else { Write-Host "- $n : MANQUANT" }
}

# ports
Write-Host "\nVérification ports locaux :"
$port3000 = Test-NetConnection -ComputerName 127.0.0.1 -Port 3000 -WarningAction SilentlyContinue
Write-Host "- localhost:3000 reachable:" ($(if ($port3000.TcpTestSucceeded) { 'OUI' } else { 'NON' }))
$port11434 = Test-NetConnection -ComputerName 127.0.0.1 -Port 11434 -WarningAction SilentlyContinue
Write-Host "- localhost:11434 (Ollama) reachable:" ($(if ($port11434.TcpTestSucceeded) { 'OUI' } else { 'NON' }))

# résumé
$missingPrereq = @()
foreach ($k in $checks.Keys) { if (-not $checks[$k]) { $missingPrereq += $k } }
foreach ($k in $files.Keys) { if (-not (Test-Path $files[$k])) { $missingPrereq += $k } }
foreach ($n in $needed) { if (-not ($env.ContainsKey($n) -or [bool](Get-Item env:$n -ErrorAction SilentlyContinue))) { $missingPrereq += $n } }

if ($missingPrereq.Count -eq 0) {
    Write-Host "\nTous les prérequis semblent présents." -ForegroundColor Green
} else {
    Write-Host "\nPré-requis manquants / actions recommandées:" -ForegroundColor Yellow
    $missingPrereq | ForEach-Object { Write-Host "- $_" }
    Write-Host "\nComplète les éléments manquants avant de démarrer. Voir .github/copilot-instructions.md pour les détails." -ForegroundColor Yellow
}

if ($Start) {
    if ($missingPrereq.Count -gt 0) {
        Write-Host "\nDémarrage annulé : prérequis manquants." -ForegroundColor Red
        exit 1
    }
    $startScript = $files['start script']
    if (Test-Path $startScript) {
        Write-Host "\nDémarrage de A11 via $startScript" -ForegroundColor Cyan
        Start-Process -FilePath pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" -NoNewWindow
        Write-Host "Script de démarrage lancé." -ForegroundColor Green
    } else {
        Write-Host "Script de démarrage introuvable." -ForegroundColor Red
        exit 1
    }
}

Write-Host "\nTerminé."