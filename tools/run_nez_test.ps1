$ErrorActionPreference = 'Stop'

Write-Output "=== NEZ HANDSHAKE TEST ==="
try {
    $body = @{ devToken = 'nez:a11-client-funesterie-pro' } | ConvertTo-Json
    $h = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/v1/nez/handshake' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
    Write-Output "HANDSHAKE_OK"
    $h | ConvertTo-Json -Depth 5 | Write-Output
} catch {
    Write-Output "HANDSHAKE_ERROR"
    Write-Output $_.Exception.Message
}

Write-Output "=== CHAT COMPLETIONS TEST ==="
try {
    $req = @{ model='llama3.1:latest'; messages=@(@{ role='user'; content='Salut' }); stream=$false } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Uri 'https://api.funesterie.me/v1/chat/completions' -Method Post -Body $req -ContentType 'application/json' -Headers @{ 'X-NEZ-TOKEN' = 'nez:a11-client-funesterie-pro' } -TimeoutSec 120
    Write-Output "COMPLETIONS_OK"
    $r | ConvertTo-Json -Depth 5 | Write-Output
} catch {
    Write-Output "COMPLETIONS_ERROR"
    Write-Output $_.Exception.Message
}
