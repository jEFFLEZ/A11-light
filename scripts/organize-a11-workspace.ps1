# Script d'organisation automatique du workspace A11
# Crée la structure recommandée et déplace les fichiers principaux

$root = "D:/A11"

# 1. Création des dossiers
$folders = @(
    "apps/server",
    "apps/web/netlify/functions",
    "scripts",
    "tools",
    "pr-files",
    "docs",
    ".github",
    "A11.System",
    "A11.Info"
)
foreach ($folder in $folders) {
    $fullPath = Join-Path $root $folder
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath | Out-Null
    }
}

# 2. Déplacement backend
if (Test-Path "$root/server.cjs") {
    Move-Item "$root/server.cjs" "$root/apps/server/server.cjs" -Force
}
if (Test-Path "$root/routes") {
    Move-Item "$root/routes" "$root/apps/server/routes" -Force
}

# 3. Déplacement frontend
if (Test-Path "$root/netlify.toml") {
    Move-Item "$root/netlify.toml" "$root/apps/web/netlify.toml" -Force
}
if (Test-Path "$root/apps/web/netlify/functions/proxy.cjs") {
    Move-Item "$root/apps/web/netlify/functions/proxy.cjs" "$root/apps/web/netlify/functions/proxy.js" -Force
}
if (Test-Path "$root/apps/web/package.json") {
    Move-Item "$root/apps/web/package.json" "$root/apps/web/package.json" -Force
}

# 4. Déplacement scripts
Get-ChildItem -Path $root -Filter '*.ps1' | Where-Object { $_.DirectoryName -eq $root } | Move-Item -Destination "$root/scripts" -Force
Get-ChildItem -Path $root/scripts -Filter '*.psm1' | Move-Item -Destination "$root/scripts" -Force

# 5. Déplacement outils
Get-ChildItem -Path $root -Filter '*.json' | Where-Object { $_.DirectoryName -eq $root } | Move-Item -Destination "$root/tools" -Force

# 6. Déplacement docs
Get-ChildItem -Path $root -Filter '*.md' | Where-Object { $_.DirectoryName -eq $root } | Move-Item -Destination "$root/docs" -Force

# 7. Déplacement workflows
Get-ChildItem -Path $root -Filter '*.yml' | Where-Object { $_.DirectoryName -eq "$root/.github" } | Move-Item -Destination "$root/.github" -Force

# 8. Déplacement projets .NET
Get-ChildItem -Path $root -Filter 'A11.System.*' | Where-Object { $_.DirectoryName -eq $root } | Move-Item -Destination "$root/A11.System" -Force
Get-ChildItem -Path $root -Filter 'A11.Info.*' | Where-Object { $_.DirectoryName -eq $root } | Move-Item -Destination "$root/A11.Info" -Force

Write-Host "Organisation du workspace terminée. Vérifiez les dossiers pour valider le résultat."