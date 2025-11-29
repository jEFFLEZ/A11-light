param(
  [switch]$Force,
  [switch]$NoOllama
)

# If a sentinel file exists, don't auto-start unless -Force supplied
$repoRoot = (Resolve-Path -Path $PSScriptRoot).Path
$sentinel = Join-Path $repoRoot '..\.no-autostart'
if ((Test-Path $sentinel) -and (-not $Force)) {
  Write-Host "Autostart blocked by sentinel ($sentinel). To override, run: pwsh start-a11-system.ps1 -Force" -ForegroundColor Yellow
  return
}

# Load env from .env if available and set environment variables (won't overwrite existing env vars)
try {
    $envFile = Join-Path $repoRoot '..\.env'
    $dotnetEnv = Get-Content $envFile -ErrorAction SilentlyContinue
    if ($dotnetEnv) {
        foreach ($line in $dotnetEnv) {
            $trimmed = $line.Trim()
            if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
            if ($trimmed -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Remove optional surrounding quotes
                if ($value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Trim('"') }
                if ($value.StartsWith("'") -and $value.EndsWith("'")) { $value = $value.Trim("'") }
                # Only set if not already present in environment
                if (-not (Test-Path "Env:$key")) {
                    Set-Item -Path "Env:$key" -Value $value
                }
            }
        }
    }
} catch { }

# Read HOST_SERVER and LLAMA_HOST from env or default
if (-not $env:HOST_SERVER) { $env:HOST_SERVER = '127.0.0.1' }
if (-not $env:LLAMA_HOST) { $env:LLAMA_HOST = '127.0.0.2' }
if (-not $env:LLAMA_PORT) { $env:LLAMA_PORT = '11434' }

if ($NoOllama) {
  Write-Host "NoOllama flag set: skipping Ollama start and forcing LLAMA_BASE to http://127.0.0.1:11434" -ForegroundColor Cyan
  $env:LLAMA_BASE = "http://127.0.0.1:11434"
} else {
  $env:LLAMA_BASE = "http://$($env:LLAMA_HOST):$($env:LLAMA_PORT)"
}

Write-Host "Binding server to $env:HOST_SERVER:3000 and LLAMA to $env:LLAMA_BASE"

# Helper to start Ollama and verify it stays running
function Start-Ollama {
    try {
        $cmd = (Get-Command 'ollama' -ErrorAction SilentlyContinue).Source
        if (-not $cmd) { $cmd = 'ollama.exe' }
        $args = @('serve')
        # Use environment variable OLLAMA_HOST (expected format: host:port) instead of CLI flags
        if ($env:LLAMA_HOST -and $env:LLAMA_PORT) {
            $env:OLLAMA_HOST = "$($env:LLAMA_HOST):$($env:LLAMA_PORT)"
        } elseif ($env:LLAMA_HOST) {
            $env:OLLAMA_HOST = $env:LLAMA_HOST
        }
        $proc = Start-Process -FilePath $cmd -ArgumentList $args -WindowStyle Hidden -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 3
        if ($proc -and (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        Write-Host "   ❌ Erreur démarrage Ollama: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 1. Lancer Ollama (si pas déjà démarré)
Write-Host "`n1. Vérification d'Ollama..." -ForegroundColor Cyan
$ollamaRunning = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
if ($NoOllama) {
  Write-Host "   ⚠️  Skipping Ollama start due to -NoOllama flag" -ForegroundColor Yellow
} elseif ($ollamaRunning) {
    Write-Host "   ✅ Ollama déjà en cours d'exécution" -ForegroundColor Green
}
else {
    Write-Host "   🚀 Démarrage d'Ollama..." -ForegroundColor Yellow
    if (Start-Ollama) {
        Write-Host "   ✅ Ollama démarré (bound to $env:LLAMA_HOST:$env:LLAMA_PORT)" -ForegroundColor Green
    }
    else {
        Write-Host "   ❌ Erreur lors du démarrage d'Ollama, vérifiez l'installation et le PATH" -ForegroundColor Red
        Write-Host "   💡 Vérifiez que Ollama est installé: https://ollama.ai/download" -ForegroundColor Yellow
    }
}

# 2. Lancer le serveur A-11
Write-Host "`n2. Lancement du serveur A-11..." -ForegroundColor Cyan
function Test-PortInUse($port, $address='127.0.0.1') {
    try {
        $connection = Get-NetTCPConnection -LocalPort $port -LocalAddress $address -ErrorAction SilentlyContinue
        return $null -ne $connection
    }
    catch {
        return $false
    }
}

if (Test-PortInUse -port 3000 -address $env:HOST_SERVER) {
    Write-Host "   ⚠️  Port 3000 already in use on $env:HOST_SERVER, attempting to stop existing node processes..." -ForegroundColor Yellow
    $connections = Get-NetTCPConnection -LocalPort 3000 -LocalAddress $env:HOST_SERVER -ErrorAction SilentlyContinue
    if ($connections) {
        $connections | ForEach-Object {
            try {
                Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
                Write-Host "   ⏹️  Process stopped (PID: $($_.OwningProcess))" -ForegroundColor Yellow
            } catch {
                Write-Host "   ⚠️ Failed to stop PID $($_.OwningProcess): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    Start-Sleep -Seconds 2
}

try {
    $repoRootParent = (Resolve-Path -Path "$PSScriptRoot\..").Path
    $serverPath = Join-Path $repoRootParent 'apps\server'
    if (-not (Test-Path $serverPath)) {
        Write-Host "   ❌ Server path not found: $serverPath" -ForegroundColor Red
    } else {
        Set-Location $serverPath
        # Ensure HOST_SERVER is available to the started process
        $env:HOST_SERVER = $env:HOST_SERVER
        Start-Process -FilePath "node" -ArgumentList "server.cjs" -WorkingDirectory $serverPath -WindowStyle Hidden -ErrorAction Stop
        Start-Sleep -Seconds 3

        # Vérifier que le serveur répond
        try {
            $health = Invoke-WebRequest -Uri "http://$($env:HOST_SERVER):3000/health" -TimeoutSec 5 -ErrorAction Stop
            Write-Host "   ✅ Serveur A-11 opérationnel on $env:HOST_SERVER:3000" -ForegroundColor Green
        }
        catch {
            Write-Host "   ⚠️  Serveur en cours de démarrage..." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "   ❌ Erreur lors du démarrage du serveur: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Vérification du tunnel Cloudflare
Write-Host "`n3. Vérification du tunnel Cloudflare..."
$cloudflaredConfig = 'C:\Users\cella\.cloudflared\config.yml'
$cloudflaredCert = 'C:\Users\cella\.cloudflared\cert.pem'
$tunnelName = 'funesterie-tunnel-named'

# Check that config and cert exist
if (-not (Test-Path $cloudflaredConfig)) {
    Write-Host "   ❌ Configuration cloudflared introuvable: $cloudflaredConfig" -ForegroundColor Red
}
elseif (-not (Test-Path $cloudflaredCert)) {
    Write-Host "   ❌ Origincert introuvable: $cloudflaredCert" -ForegroundColor Red
}
else {
    try {
        $tunnelList = & cloudflared --config $cloudflaredConfig tunnel list 2>&1 | Out-String
        if ($tunnelList -match $tunnelName) {
            Write-Host "   ✅ Tunnel '$tunnelName' déjà enregistré" -ForegroundColor Green
        } else {
            Write-Host "   ❌ Tunnel '$tunnelName' non enregistré localement. Tentative de lancement..." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "   ⚠️  Impossible de lister les tunnels: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "`n✅ SYSTÈME LANCÉ !" -ForegroundColor Green
Write-Host "   - Serveur local: http://$($env:HOST_SERVER):3000" -ForegroundColor White
Write-Host "   - Health check: http://$($env:HOST_SERVER):3000/health" -ForegroundColor White

# Garder le script actif pour maintenir les processus
Write-Host "`n⏳ Appuyez sur Ctrl+C pour arrêter tous les services..." -ForegroundColor Gray

# Boucle infinie pour garder le script actif
try {
    while ($true) {
        Start-Sleep -Seconds 10
        $nodeProcess = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*server.cjs*" }
        $ollamaProcess = Get-Process -Name "ollama" -ErrorAction SilentlyContinue

        if (-not $nodeProcess) {
            Write-Host "⚠️  Serveur Node.js arrêté, redémarrage..." -ForegroundColor Yellow
            try {
                if (Test-Path $serverPath) { Set-Location $serverPath }
                Start-Process -FilePath "node" -ArgumentList "server.cjs" -WindowStyle Hidden -WorkingDirectory $serverPath
            }
            catch {
                Write-Host "❌ Impossible de redémarrer le serveur Node.js" -ForegroundColor Red
            }
        }

        if (-not $ollamaProcess) {
            if ($NoOllama) {
                Write-Host "⚠️  Ollama est désactivé par le drapeau -NoOllama, saut du redémarrage." -ForegroundColor Yellow
            } else {
                Write-Host "⚠️  Ollama arrêté, redémarrage..." -ForegroundColor Yellow
                try {
                    if (Start-Ollama) {
                        Write-Host "   ✅ Ollama redémarré" -ForegroundColor Green
                    } else {
                        Write-Host "   ❌ Échec du redémarrage d'Ollama" -ForegroundColor Red
                    }
                }
                catch {
                    Write-Host "❌ Impossible de redémarrer Ollama" -ForegroundColor Red
                }
            }
        }
    }
}
catch {
    Write-Host "`n⏹️  Arrêt des services..." -ForegroundColor Yellow

    Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*server.cjs*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "✅ Services arrêtés" -ForegroundColor Green
}