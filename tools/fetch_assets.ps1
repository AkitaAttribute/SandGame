$ErrorActionPreference = "Stop"
$repo = "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0.git"
$cache = Join-Path $PSScriptRoot "..\.asset-cache\kaykit-skeletons"
$target = Join-Path $PSScriptRoot "..\addons\kaykit_character_pack_skeletons"

if (Test-Path $cache) { Remove-Item -Recurse -Force $cache }
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
New-Item -ItemType Directory -Force (Split-Path $cache) | Out-Null
New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null

git clone --depth 1 $repo $cache
Copy-Item -Recurse -Force (Join-Path $cache "addons\kaykit_character_pack_skeletons") $target
Write-Host "KayKit Skeletons installed at $target"
