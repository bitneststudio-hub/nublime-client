param(
  [string]$Project = 'C:\Users\happy\Projects\wildlime',   # 仓库根（monorepo）
  [string]$CoreDir = ''
)
# 构建 Flutter Windows 客户端，并把 xray/Wintun 核心一起打进产物。
$ErrorActionPreference = 'Stop'
$App = Join-Path $Project 'app'
if (-not (Test-Path $App)) { throw "app dir not found: $App" }
if (-not $CoreDir) { $CoreDir = Join-Path $App 'windows\core' }
if (-not (Test-Path $CoreDir)) { throw "core dir not found: $CoreDir (run tools\windows\fetch_core.ps1 first)" }

Set-Location $App
Write-Host '=== flutter build windows ==='
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed: $LASTEXITCODE" }

$out = Join-Path $App 'build\windows\x64\runner\Release'
Copy-Item $CoreDir -Destination $out -Recurse -Force

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$dist = Join-Path $App 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zip = Join-Path $dist "WildLime-win64-$stamp.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
$h = Get-FileHash $zip -Algorithm SHA256
Write-Host "ARTIFACT: $zip"
Write-Host ("SHA256  : " + $h.Hash)
Write-Host ("SIZE    : " + (Get-Item $zip).Length)
