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
