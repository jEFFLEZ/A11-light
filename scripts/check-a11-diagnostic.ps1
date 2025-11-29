param(
  [string[]]$Urls = @(
    "http://127.0.0.1:3000/api/health",
    "https://api.funesterie.pro/api/health",
    "https://api.funesterie.me/api/health",
    "https://funesterie.pro/.netlify/functions/proxy/health"
  )
)

foreach ($Url in $Urls) {
  Write-Host "Test: $Url" -ForegroundColor Cyan
  try {
    $r = Invoke-RestMethod -Uri $Url -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  OK" -ForegroundColor Green
  } catch {
    Write-Host "  NOT_OK" -ForegroundColor Red
  }
}
