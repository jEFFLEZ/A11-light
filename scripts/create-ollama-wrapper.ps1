# Create a global wrapper for local Ollama installation
# Usage: run as Administrator to add wrapper to Program Files and update MACHINE PATH
$src = 'C:\Users\cella\AppData\Local\Programs\Ollama\ollama app.exe'
if (-not (Test-Path $src)) {
  Write-Host "Source Ollama binary not found: $src"
  exit 2
}
$destDir = 'C:\Program Files\ollama'
if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
$wrapper = Join-Path $destDir 'ollama.cmd'
$content = "`"$src`" %*"
Set-Content -Path $wrapper -Value $content -Encoding ASCII
Write-Host "Created wrapper: $wrapper"

# Update Machine PATH safely
$envTarget = [System.EnvironmentVariableTarget]::Machine
$machinePath = [Environment]::GetEnvironmentVariable('Path', $envTarget)
if (-not $machinePath) { $machinePath = '' }
# Normalize separators
$parts = $machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
if ($parts -notcontains $destDir) {
  $parts += $destDir
  $newPath = ($parts -join ';')
  [Environment]::SetEnvironmentVariable('Path', $newPath, $envTarget)
  Write-Host "Added to Machine PATH: $destDir"
} else {
  Write-Host "Machine PATH already contains: $destDir"
}

# Verification
try {
  $cmd = "$wrapper --version"
  Write-Host "Invoking wrapper for basic verification..."
  & cmd /c $wrapper --version 2>&1 | Write-Host
} catch {
  Write-Host "Wrapper verification returned an error (this may be normal if Ollama GUI doesn't support --version)."
}
Write-Host 'Done.'
