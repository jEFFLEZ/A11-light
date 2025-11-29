param(
  [string]$Url = "https://api.funesterie.pro/api/health"
)

try {
  $r = Invoke-RestMethod -Uri $Url -TimeoutSec 5 -ErrorAction Stop
  Write-Host "OK"
  exit 0
} catch {
  Write-Host "NOT_OK"
  exit 1
}
