$ErrorActionPreference = 'Stop'

$headers = @{ 'X-NEZ-TOKEN' = 'nez:a11-client-funesterie-pro' }
$body = @{ devToken = 'nez:a11-client-funesterie-pro' } | ConvertTo-Json

Write-Output "=== HANDSHAKE (with header) ==="
try {
  $h = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/v1/nez/handshake' -Method Post -Body $body -ContentType 'application/json' -Headers $headers -TimeoutSec 15
  Write-Output "HANDSHAKE_OK"
  $h | ConvertTo-Json -Depth 5 | Write-Output
} catch {
  Write-Output "HANDSHAKE_ERROR"
  Write-Output $_.Exception.Message
}

if ($h -and $h.token) {
  Write-Output "=== CALL /v1/chat/completions (local) ==="
  $jwt = $h.token
  $req = @{ model='llama3.1:latest'; messages=@(@{ role='user'; content='Salut' }); stream=$false } | ConvertTo-Json -Depth 5
  try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/v1/chat/completions' -Method Post -Body $req -ContentType 'application/json' -Headers @{ Authorization = "Bearer $jwt" } -TimeoutSec 120
    Write-Output "COMPLETIONS_OK"
    $r | ConvertTo-Json -Depth 5 | Write-Output
  } catch {
    Write-Output "COMPLETIONS_ERROR"
    Write-Output $_.Exception.Message
  }
} else {
  Write-Output "NO_JWT"
}
