param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8000
)

$uri = "http://$HostName`:$Port/health"
Write-Host "Checking $uri"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5
    $response | ConvertTo-Json -Depth 5
    exit 0
}
catch {
    Write-Error "Healthcheck failed: $($_.Exception.Message)"
    exit 1
}
