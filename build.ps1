# Builds Install-LastLight.bat: one file that carries the installer script and the theme.
# Run after changing anything in theme\ or installer\:  powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false

$zip = Join-Path $env:TEMP ('ll-build-' + [guid]::NewGuid().ToString('N') + '.zip')
Compress-Archive -Path (Join-Path $root 'theme\*') -DestinationPath $zip
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
Remove-Item $zip

function Get-Launcher($marker) {
  return @(
    '@echo off',
    'setlocal',
    'title Last Light theme for Steam',
    'set "LL_SELF=%~f0"',
    ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:LL_SELF,[Text.Encoding]::UTF8); $m=''#' + $marker + '''+''#''; $e=''#PAYLOAD''+''#''; $i=$t.IndexOf($m)+$m.Length; $j=$t.LastIndexOf($e); if($j -lt $i){$j=$t.Length}; & ([scriptblock]::Create($t.Substring($i,$j-$i)))"'),
    'echo.',
    'pause',
    'exit /b',
    ''
  ) -join "`r`n"
}

$script = [IO.File]::ReadAllText((Join-Path $root 'installer\install.ps1'), [Text.Encoding]::UTF8)
$install = (Get-Launcher 'SCRIPT') + '#SCRIPT' + "#`r`n" + ($script -replace "`r?`n", "`r`n") + "`r`n#PAYLOAD#`r`n" + $b64 + "`r`n"
[IO.File]::WriteAllText((Join-Path $root 'Install-LastLight.bat'), $install, $utf8)

$script = [IO.File]::ReadAllText((Join-Path $root 'installer\uninstall.ps1'), [Text.Encoding]::UTF8)
$remove = (Get-Launcher 'SCRIPT') + '#SCRIPT' + "#`r`n" + ($script -replace "`r?`n", "`r`n") + "`r`n"
[IO.File]::WriteAllText((Join-Path $root 'Uninstall-LastLight.bat'), $remove, $utf8)

Write-Host ("Install-LastLight.bat: {0:N0} KB" -f ((Get-Item (Join-Path $root 'Install-LastLight.bat')).Length / 1KB))
Write-Host ("Uninstall-LastLight.bat: {0:N0} KB" -f ((Get-Item (Join-Path $root 'Uninstall-LastLight.bat')).Length / 1KB))
