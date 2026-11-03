# Download the pinned Xray-core Windows build into windows\core
param(
  [string]$Version = '26.7.11',
  [string]$Project = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Project) { $Project = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }   # repo root
$core = Join-Path $Project 'app\windows\core'
New-Item -ItemType Directory -Path $core -Force | Out-Null

$url = "https://github.com/XTLS/Xray-core/releases/download/v$Version/Xray-windows-64.zip"
$zip = Join-Path $env:TEMP "Xray-windows-64-$Version.zip"
Write-Host "downloading $url"
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $core -Force

foreach ($f in 'xray.exe','wintun.dll','geoip.dat','geosite.dat','LICENSE','LICENSE-Wintun') {
  if (-not (Test-Path (Join-Path $core $f))) { throw "missing after extract: $f" }
}
Write-Host "core ready at $core"
Get-ChildItem $core | Format-Table Name,Length -Auto
