$ErrorActionPreference = 'Stop'

$body = @{ 
  model = 'llama3.1:latest';
  messages = @(@{ role = 'user'; content = 'Salut, je suis john' });
  stream = $false
} | ConvertTo-Json -Depth 5

Write-Host 'Sending fake request to local A-11...'
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/v1/chat/completions' -Method Post -Body $body -ContentType 'application/json' -Headers @{ 'X-NEZ-TOKEN' = 'nez:a11-client-funesterie-pro' } -TimeoutSec 30 -ErrorAction Stop
  $out = $r | ConvertTo-Json -Depth 10
  $out | Out-File -FilePath 'tools/fake_john_response.json' -Encoding utf8
  Write-Host 'OK: response saved to tools/fake_john_response.json'
  Write-Host $out
} catch {
  Write-Host 'ERROR:' $_.Exception.Message
  if ($_.Exception.Response) {
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      $reader = New-Object System.IO.StreamReader($stream)
      $text = $reader.ReadToEnd()
      Write-Host 'Response Body:'
      Write-Host $text
    } catch {
      # ignore
    }
  }
}
