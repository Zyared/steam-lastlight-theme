@echo off
setlocal
title Last Light theme for Steam
set "LL_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:LL_SELF,[Text.Encoding]::UTF8); $m='#SCRIPT'+'#'; $e='#PAYLOAD'+'#'; $i=$t.IndexOf($m)+$m.Length; $j=$t.LastIndexOf($e); if($j -lt $i){$j=$t.Length}; & ([scriptblock]::Create($t.Substring($i,$j-$i)))"
echo.
pause
exit /b
#SCRIPT#
# Removes the LastLight theme and returns Steam to the default look. Millennium itself stays installed.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ThemeName = 'LastLight'
try {
  $p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if (-not $p -or -not (Test-Path (Join-Path $p 'steam.exe'))) { throw 'Steam не найден.' }
  $steam = (Resolve-Path $p).Path
  $id = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).RunningAppID
  if ($id -and $id -ne 0) { throw 'Сейчас запущена игра. Закрой её и запусти ещё раз.' }

  $probe = Join-Path $steam ('.ll-write-test-' + [guid]::NewGuid().ToString('N'))
  try { [IO.File]::WriteAllText($probe, 'x'); Remove-Item $probe -Force }
  catch {
    Write-Host 'Нужны права администратора, Windows спросит разрешение.'
    Start-Process $env:LL_SELF -Verb RunAs
    return
  }

  if (Get-Process steam -ErrorAction SilentlyContinue) {
    Write-Host 'Закрываю Steam...'
    & (Join-Path $steam 'steam.exe') -shutdown
    $t = 0
    while ((Get-Process steam -ErrorAction SilentlyContinue) -and $t -lt 60) { Start-Sleep 1; $t++ }
    if (Get-Process steam -ErrorAction SilentlyContinue) { throw 'Steam не закрылся за минуту. Закрой его вручную и запусти ещё раз.' }
  }

  $cfg = Join-Path $steam 'millennium\config\config.json'
  if (Test-Path $cfg) {
    $txt = [IO.File]::ReadAllText($cfg)
    $txt = $txt -replace ('"activeTheme"\s*:\s*"' + $ThemeName + '"'), '"activeTheme": "default"'
    $null = $txt | ConvertFrom-Json
    [IO.File]::WriteAllText($cfg, $txt, (New-Object Text.UTF8Encoding $false))
  }
  foreach ($d in 'millennium\themes', 'steamui\skins') {
    $dir = Join-Path (Join-Path $steam $d) $ThemeName
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force; Write-Host "Удалено: $dir" }
  }
  Start-Process explorer.exe 'steam://open/main'
  Write-Host ''
  Write-Host 'Готово: тема удалена, Steam запускается со стандартным видом.' -ForegroundColor Green
  Write-Host 'Millennium остался установленным.'
}
catch {
  Write-Host ''
  Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

