# One-shot state dump for the VPN on Windows
Write-Output '=== process ==='
Get-Process xray -ErrorAction SilentlyContinue | Format-Table Id,ProcessName,StartTime -Auto
Write-Output '=== adapter ==='
Get-NetAdapter -Name 'WildLime' -ErrorAction SilentlyContinue | Format-Table Name,Status,ifIndex,LinkSpeed -Auto
Write-Output '=== routes ==='
Get-NetRoute -DestinationPrefix '0.0.0.0/1','128.0.0.0/1' -ErrorAction SilentlyContinue | Format-Table DestinationPrefix,NextHop,ifIndex -Auto
Write-Output '=== dns ==='
Get-DnsClientServerAddress -InterfaceAlias 'WildLime' -ErrorAction SilentlyContinue | Format-Table AddressFamily,ServerAddresses -Auto
Write-Output '=== egress ==='
try { (Invoke-WebRequest -Uri 'https://ifconfig.me' -TimeoutSec 20 -UseBasicParsing).Content } catch { "FAILED: $($_.Exception.Message)" }
