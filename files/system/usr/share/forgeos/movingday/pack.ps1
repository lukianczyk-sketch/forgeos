# ForgeOS Moving Day (Job 14) - packs this Windows user's things onto the USB stick for ForgeOS.
# It only READS this PC and writes only into "ForgeOS Moving Box" on the stick: Documents, Pictures,
# Music, Videos, Desktop, Downloads, browser bookmarks, the program list and (with you) saved passwords.
$ErrorActionPreference = 'Continue'
function P { [IO.Path]::Combine([string[]]$args) }
$Stick = Split-Path -Parent $PSScriptRoot
$Box = P $Stick 'ForgeOS Moving Box'
$U = P $Box 'Users' $env:USERNAME
$Pw = P $Box 'passwords'

function Known($Name) {
  $id = @{ Documents = 'MyDocuments'; Pictures = 'MyPictures'; Music = 'MyMusic'; Videos = 'MyVideos'; Desktop = 'Desktop' }[$Name]
  if ($id -and -not $env:FORGEOS_MD_TEST) { return [Environment]::GetFolderPath($id) }
  return (P $env:USERPROFILE $Name)
}

function Size($Path) {
  $s = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if ($s) { return [int64]$s } else { return [int64]0 }
}

function Copy-Folder($From, $To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  if (Get-Command robocopy -ErrorAction SilentlyContinue) {
    robocopy $From $To /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF desktop.ini Thumbs.db *.lnk *.tmp | Out-Null
    return ($LASTEXITCODE -lt 8)
  }
  Copy-Item -Path (P $From '*') -Destination $To -Recurse -Force -ErrorAction SilentlyContinue
  return $true
}

function Copy-File($From, $ToDir) {
  New-Item -ItemType Directory -Force -Path $ToDir | Out-Null
  Copy-Item -LiteralPath $From -Destination $ToDir -Force
}

Write-Host 'ForgeOS Moving Day - packing your things onto this USB stick. Nothing on this PC is changed.'
$Folders = 'Documents', 'Pictures', 'Music', 'Videos', 'Desktop', 'Downloads'
$Total = [int64]0
foreach ($f in $Folders) {
  $p = Known $f
  if ($p -and (Test-Path -LiteralPath $p)) {
    $s = Size $p; $Total += $s
    Write-Host ('  {0,-10} {1,8:N1} GB' -f $f, ($s / 1GB))
  }
}
Write-Host ('Total: {0:N1} GB' -f ($Total / 1GB))
$Free = $null
try { $Free = (New-Object System.IO.DriveInfo((Split-Path -Qualifier $Stick -ErrorAction Stop))).AvailableFreeSpace } catch { }
if ($null -ne $Free -and $Free -lt ($Total + 100MB)) {
  Write-Host ('The stick has only {0:N1} GB free. Use a bigger stick or an external drive.' -f ($Free / 1GB))
  exit 4
}
$a = Read-Host 'Copy all of this onto the stick? Type Y and press Enter'
if ($a -notmatch '^[Yy]') { Write-Host 'Nothing was copied.'; exit 1 }

$bad = 0
foreach ($f in $Folders) {
  $p = Known $f
  if ($p -and (Test-Path -LiteralPath $p)) {
    Write-Host ('Copying {0}...' -f $f)
    if (-not (Copy-Folder $p (P $U $f))) { $bad++ }
  }
}

Write-Host 'Copying bookmarks...'
foreach ($b in @(@('Google', 'Chrome'), @('Microsoft', 'Edge'), @('BraveSoftware', 'Brave-Browser'))) {
  $data = P $env:LOCALAPPDATA $b[0] $b[1] 'User Data'
  foreach ($prof in Get-ChildItem -LiteralPath $data -Directory -ErrorAction SilentlyContinue) {
    $bm = P $prof.FullName 'Bookmarks'
    if (Test-Path -LiteralPath $bm) { Copy-File $bm (P $U 'AppData' 'Local' $b[0] $b[1] 'User Data' $prof.Name) }
  }
}
foreach ($prof in Get-ChildItem -LiteralPath (P $env:APPDATA 'Mozilla' 'Firefox' 'Profiles') -Directory -ErrorAction SilentlyContinue) {
  $pl = P $prof.FullName 'places.sqlite'
  if (Test-Path -LiteralPath $pl) { Copy-File $pl (P $U 'AppData' 'Roaming' 'Mozilla' 'Firefox' 'Profiles' $prof.Name) }
}

Write-Host 'Making the list of your programs...'
$WinTools = '^(Windows (Accessories|Administrative Tools|Ease of Access|PowerShell|System|Tools)|Accessibility|Accessories|Administrative Tools|Maintenance|Startup|System Tools)$'
$names = @()
if (Test-Path 'HKLM:\') {
  $k = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $names += Get-ItemProperty "HKLM:\$k", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\$k" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } | ForEach-Object { $_.DisplayName }
}
foreach ($sm in @((P $env:ProgramData 'Microsoft' 'Windows' 'Start Menu' 'Programs'), (P $env:APPDATA 'Microsoft' 'Windows' 'Start Menu' 'Programs'))) {
  $names += Get-ChildItem -LiteralPath $sm -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -notmatch $WinTools } | ForEach-Object { $_.BaseName }
}
New-Item -ItemType Directory -Force -Path $Pw | Out-Null
$names | Sort-Object -Unique | Set-Content -LiteralPath (P $Box 'programs.txt') -Encoding UTF8

Write-Host ''
Write-Host 'Last step: your saved passwords. Windows keeps them locked, so each browser saves them for you:'
Write-Host '  Chrome or Brave: Settings > Passwords > Settings > Export passwords'
Write-Host '  Edge: Settings > Passwords > the ... button > Export passwords'
Write-Host '  Firefox: Passwords > the ... button > Export passwords'
Write-Host 'Save each file into the "passwords" folder on the stick (it opens now).'
if (Get-Command explorer.exe -ErrorAction SilentlyContinue) { Start-Process explorer.exe $Pw }
Read-Host 'Press Enter when you are done (or if you have no saved passwords)' | Out-Null

$info = [ordered]@{ made_by = 'ForgeOS Moving Day'; version = 1; user = $env:USERNAME; pc = $env:COMPUTERNAME; date = (Get-Date -Format s) }
$info | ConvertTo-Json | Set-Content -LiteralPath (P $Box 'box.json') -Encoding UTF8
if ($bad -gt 0) { Write-Host 'Some files could not be copied (a file over 4 GB needs a stick formatted as exFAT or NTFS).' }
Write-Host 'Done. Plug the stick into the ForgeOS PC and open Moving Day. It erases the password file after the move.'
if ($bad -gt 0) { exit 1 }
exit 0
