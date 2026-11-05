@echo off
setlocal
title Last Light theme for Steam
set "LL_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:LL_SELF,[Text.Encoding]::UTF8); $m='#SCRIPT'+'#'; $e='#PAYLOAD'+'#'; $i=$t.IndexOf($m)+$m.Length; $j=$t.LastIndexOf($e); if($j -lt $i){$j=$t.Length}; & ([scriptblock]::Create($t.Substring($i,$j-$i)))"
echo.
pause
exit /b
#SCRIPT#
# Installs the Last Light theme for Steam. Runs from the single-file Install-LastLight.bat, which carries the theme.
param()
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$ThemeName = 'LastLight'
$InstallerUrl = 'https://github.com/SteamClientHomebrew/Installer/releases/latest/download/MillenniumInstaller-Windows.exe'
$ExpectedSigner = 'SignPath Foundation'
$Self = $env:LL_SELF

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Step($text) { Write-Host ''; Write-Host ">> $text" -ForegroundColor Yellow }
function Fail($text) { throw $text }

function Get-SteamPath {
  $p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if (-not $p -or -not (Test-Path (Join-Path $p 'steam.exe'))) { Fail 'Steam не найден. Установи Steam и запусти установщик ещё раз.' }
  return (Resolve-Path $p).Path
}
function Test-GameRunning {
  $id = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).RunningAppID
  return ($id -and $id -ne 0)
}
function Stop-Steam($steam) {
  if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { return }
  Say 'Закрываю Steam...'
  & (Join-Path $steam 'steam.exe') -shutdown
  $t = 0
  while ((Get-Process steam -ErrorAction SilentlyContinue) -and $t -lt 60) { Start-Sleep 1; $t++ }
  if (Get-Process steam -ErrorAction SilentlyContinue) { Fail 'Steam не закрылся за минуту. Закрой его вручную и запусти установщик ещё раз.' }
}
# Goes through Explorer so Steam never inherits administrator rights from this script.
function Start-Steam { Start-Process explorer.exe 'steam://open/main' }

function Test-Millennium($steam) {
  return (Test-Path (Join-Path $steam 'millennium\lib\millennium.dll')) -or (Test-Path (Join-Path $steam 'wsock32.dll'))
}
function Install-Millennium($steam) {
  Step 'Millennium не найден, скачиваю официальный установщик'
  $dir = Join-Path $env:TEMP ('lastlight-millennium-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir | Out-Null
  $file = Join-Path $dir 'MillenniumInstaller-Windows.exe'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest $InstallerUrl -OutFile $file -UseBasicParsing
  $sig = Get-AuthenticodeSignature $file
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($ExpectedSigner)) {
    Remove-Item $dir -Recurse -Force
    Fail "Подпись установщика Millennium не прошла проверку ($($sig.Status)). Ничего не установлено."
  }
  Say "Подпись в порядке: $ExpectedSigner" 'Green'
  Say ''
  Say 'Сейчас откроется окно Millennium: нажми в нём кнопку установки и закрой окно, когда закончит.' 'White'
  # Not -Wait: it also waits for child processes, and the Millennium window starts Steam, which keeps running.
  (Start-Process $file -WorkingDirectory $dir -PassThru).WaitForExit()
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  if (-not (Test-Millennium $steam)) { Fail 'Millennium не установился. Запусти установщик ещё раз.' }
  Say 'Millennium установлен.' 'Green'
}
function Wait-MillenniumConfig($steam) {
  $cfg = Join-Path $steam 'millennium\config\config.json'
  if (Test-Path $cfg) { return $cfg }
  Say 'Запускаю Steam, чтобы Millennium создал настройки. Если Steam попросит войти, войди в аккаунт...'
  if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { Start-Steam }
  $t = 0
  while (-not (Test-Path $cfg) -and $t -lt 300) { Start-Sleep 2; $t += 2 }
  if (-not (Test-Path $cfg)) { Fail 'Настройки Millennium не появились за 5 минут. Запусти Steam, дождись входа и запусти установщик ещё раз.' }
  Start-Sleep 5
  return $cfg
}
function Test-Writable($dir) {
  $f = Join-Path $dir ('.ll-write-test-' + [guid]::NewGuid().ToString('N'))
  try { [IO.File]::WriteAllText($f, 'x'); Remove-Item $f -Force; return $true } catch { return $false }
}
function Get-ThemesDir($steam) {
  $new = Join-Path $steam 'millennium\themes'
  $old = Join-Path $steam 'steamui\skins'
  if (Test-Path $new) { return $new }
  if (Test-Path $old) { return $old }
  if (Test-Path (Join-Path $steam 'millennium')) { New-Item -ItemType Directory -Path $new | Out-Null; return $new }
  New-Item -ItemType Directory -Path $old | Out-Null
  return $old
}
function Set-ActiveTheme($cfg, $name) {
  Copy-Item $cfg "$cfg.before-lastlight.bak" -Force
  $txt = [IO.File]::ReadAllText($cfg)
  if ($txt -notmatch '"activeTheme"\s*:') { Fail 'В настройках Millennium нет параметра activeTheme: похоже, формат изменился. Выбери тему Last Light вручную в настройках Millennium.' }
  $txt = $txt -replace '"activeTheme"\s*:\s*"[^"]*"', ('"activeTheme": "' + $name + '"')
  $txt = $txt -replace '"allowedStyles"\s*:\s*false', '"allowedStyles": true'
  $txt = $txt -replace '"allowedScripts"\s*:\s*false', '"allowedScripts": true'
  $null = $txt | ConvertFrom-Json   # refuses to save a broken file
  [IO.File]::WriteAllText($cfg, $txt, (New-Object Text.UTF8Encoding $false))
}
function Expand-Theme($target) {
  $text = [IO.File]::ReadAllText($Self, [Text.Encoding]::UTF8)
  $mark = '#PAYLOAD' + '#'
  $i = $text.LastIndexOf($mark)
  if ($i -lt 0) { Fail 'Файл установщика повреждён: внутри нет темы. Скачай его заново.' }
  $b64 = ($text.Substring($i + $mark.Length) -replace '[^A-Za-z0-9+/=]', '')
  $tmp = Join-Path $env:TEMP ('lastlight-theme-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'theme.zip'
  [IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String($b64))
  Expand-Archive $zip -DestinationPath (Join-Path $tmp 'x')
  if (-not (Test-Path (Join-Path $tmp 'x\skin.json'))) { Remove-Item $tmp -Recurse -Force; Fail 'Файл установщика повреждён: в теме нет skin.json. Скачай его заново.' }
  $dest = Join-Path $target $ThemeName
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Path $dest | Out-Null
  Copy-Item (Join-Path $tmp 'x\*') $dest -Recurse -Force
  Remove-Item $tmp -Recurse -Force
  return $dest
}

try {
  Write-Host ''
  Write-Host '  LAST LIGHT :: тема для Steam' -ForegroundColor Yellow

  $steam = Get-SteamPath
  Say "Steam: $steam"
  if (Test-GameRunning) { Fail 'Сейчас запущена игра. Закрой её и запусти установщик ещё раз.' }

  if (-not (Test-Millennium $steam)) { Install-Millennium $steam } else { Say 'Millennium уже установлен.' 'Green' }

  # Program Files can be read-only for a normal user: ask for rights only when they are really needed.
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin -and -not (Test-Writable $steam)) {
    Say 'Для записи в папку Steam нужны права администратора, Windows спросит разрешение.' 'White'
    Start-Process $Self -Verb RunAs
    return
  }

  $cfg = Wait-MillenniumConfig $steam
  Step 'Ставлю тему'
  Stop-Steam $steam
  $dest = Expand-Theme (Get-ThemesDir $steam)
  Say "Тема скопирована: $dest"
  Set-ActiveTheme $cfg $ThemeName
  Say 'Тема включена.' 'Green'

  Step 'Запускаю Steam'
  Start-Steam
  Write-Host ''
  Write-Host 'Готово! Эффекты можно отключить в настройках темы в Millennium.' -ForegroundColor Green
}
catch {
  Write-Host ''
  Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

#PAYLOAD#
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
