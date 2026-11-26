# Downloads Inter and Noto Sans Telugu TTFs into assets/google_fonts/ so the
# app renders its fonts fully offline (google_fonts prefers bundled files).
#
# Usage:  powershell -ExecutionPolicy Bypass -File tool\setup_fonts.ps1
# After it succeeds, add this to pubspec.yaml under `flutter:`:
#   assets:
#     - assets/google_fonts/

$ErrorActionPreference = 'Stop'

$dest = Join-Path $PSScriptRoot '..\assets\google_fonts'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$files = @(
  @{ Url = 'https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip'; Zip = 'inter.zip' }
)

$tmp = Join-Path $env:TEMP 'gymdesk_fonts'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host 'Downloading Inter...'
$zipPath = Join-Path $tmp 'inter.zip'
Invoke-WebRequest -Uri $files[0].Url -OutFile $zipPath
Write-Host 'Extracting...'
Expand-Archive -Path $zipPath -DestinationPath (Join-Path $tmp 'inter') -Force

# Inter 4.x ships static TTFs under extras/ttf
$interStatic = Get-ChildItem -Recurse -Filter 'Inter-Regular.ttf' (Join-Path $tmp 'inter') |
  Select-Object -First 1
if ($interStatic) {
  $srcDir = $interStatic.DirectoryName
  foreach ($w in 'Regular', 'Medium', 'SemiBold', 'Bold') {
    Copy-Item (Join-Path $srcDir "Inter-$w.ttf") $dest -Force
  }
}
else {
  # Fallback: variable font single file
  $varFont = Get-ChildItem -Recurse -Filter 'InterVariable.ttf' (Join-Path $tmp 'inter') |
    Select-Object -First 1
  if (-not $varFont) { throw 'Inter TTFs not found in the downloaded archive.' }
  Copy-Item $varFont.FullName (Join-Path $dest 'Inter-Regular.ttf') -Force
  Write-Warning 'Only the variable Inter font was found; it was copied as Inter-Regular.ttf.'
}

Write-Host 'Downloading Noto Sans Telugu...'
$teluguUrl = 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanstelugu/NotoSansTelugu%5Bwdth%2Cwght%5D.ttf'
Invoke-WebRequest -Uri $teluguUrl -OutFile (Join-Path $dest 'NotoSansTelugu.ttf')

Write-Host "Done. Fonts copied to $dest"
Write-Host 'Add the assets entry to pubspec.yaml (see header of this script).'
