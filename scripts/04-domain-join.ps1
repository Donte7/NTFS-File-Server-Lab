Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

Write-Host "Setting DNS to DC01 (10.0.1.7)..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "10.0.1.7"
Write-Host "DNS set to 10.0.1.7" -ForegroundColor Cyan

Write-Host "Waiting for lab.local to resolve..." -ForegroundColor Yellow
$retries = 0
$resolved = $false
while ($retries -lt 12 -and -not $resolved) {
    Start-Sleep -Seconds 15
    $retries = $retries + 1
    $resolved = [bool](Resolve-DnsName "lab.local" -ErrorAction SilentlyContinue)
    Write-Host "Attempt $retries -- resolved: $resolved"
}

if (-not $resolved) {
    throw "lab.local did not resolve after 3 minutes."
}

Write-Host "lab.local resolved successfully." -ForegroundColor Green

Write-Host "Building domain credential..." -ForegroundColor Yellow
$securePass = ConvertTo-SecureString "ADMIN_PASSWORD" -AsPlainText -Force
$domainCred = New-Object System.Management.Automation.PSCredential("LAB\azureadmin", $securePass)

Write-Host "Joining lab.local domain..." -ForegroundColor Yellow
Add-Computer -DomainName "lab.local" -Credential $domainCred -Restart -Force