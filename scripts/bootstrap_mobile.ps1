$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$MobileDir = Join-Path $RepoRoot 'apps/mobile'
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('splitcrew-' + [guid]::NewGuid().ToString('N'))
$Generated = Join-Path $TempRoot 'mobile'

try {
    New-Item -ItemType Directory -Path $TempRoot | Out-Null
    flutter create --platforms=android --org io.github.tunglam0605 --project-name splitcrew_mobile $Generated
    if ($LASTEXITCODE -ne 0) { throw 'flutter create failed.' }

    $AndroidDir = Join-Path $MobileDir 'android'
    if (Test-Path $AndroidDir) { Remove-Item -Recurse -Force $AndroidDir }
    Copy-Item -Recurse (Join-Path $Generated 'android') $AndroidDir
    Copy-Item (Join-Path $Generated '.metadata') (Join-Path $MobileDir '.metadata') -Force

    Push-Location $MobileDir
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    Pop-Location

    Write-Host 'Android platform generated. Run: cd apps/mobile; flutter run'
}
finally {
    if ((Get-Location).Path -eq $MobileDir) { Pop-Location }
    if (Test-Path $TempRoot) { Remove-Item -Recurse -Force $TempRoot }
}
