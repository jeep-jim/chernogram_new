$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$logPath = Join-Path $PWD 'windows-build.txt'

try {
  Start-Transcript -Path $logPath -Force | Out-Null

  Write-Host '===== FLUTTER ====='
  flutter --version
  if ($LASTEXITCODE -ne 0) { throw "flutter --version failed: $LASTEXITCODE" }

  Write-Host '===== ENABLE WINDOWS ====='
  flutter config --enable-windows-desktop
  if ($LASTEXITCODE -ne 0) { throw "flutter config failed: $LASTEXITCODE" }

  Write-Host '===== CREATE WINDOWS PLATFORM ====='
  if (-not (Test-Path 'windows/CMakeLists.txt')) {
    flutter create --platforms=windows --project-name chernogram --no-pub .
    if ($LASTEXITCODE -ne 0) { throw "flutter create failed: $LASTEXITCODE" }
  }

  Write-Host '===== APPLY APPLICATION PATCHES ====='
  $patches = @(
    'tooling/fix_v07_compile.py',
    'tooling/fix_v09_media_calls.py',
    'tooling/fix_v09_compile.py',
    'tooling/fix_v091_player_header.py',
    'tooling/fix_v010_rtc_circles.py',
    'tooling/fix_v0101_chat_keyboard.py',
    'tooling/fix_v011_messenger_polish.py',
    'tooling/fix_v011_compile.py'
  )
  foreach ($patch in $patches) {
    Write-Host "--- $patch"
    python $patch
    if ($LASTEXITCODE -ne 0) { throw "$patch failed: $LASTEXITCODE" }
  }

  Write-Host '===== PREPARE WINDOWS ====='
  python -m pip install pillow --disable-pip-version-check --quiet
  if ($LASTEXITCODE -ne 0) { throw "pip install pillow failed: $LASTEXITCODE" }
  python tooling/fix_windows_desktop.py
  if ($LASTEXITCODE -ne 0) { throw "fix_windows_desktop.py failed: $LASTEXITCODE" }

  Write-Host '===== PUB GET ====='
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed: $LASTEXITCODE" }

  Write-Host '===== FORMAT ====='
  dart format lib
  if ($LASTEXITCODE -ne 0) { throw "dart format failed: $LASTEXITCODE" }

  Write-Host '===== ANALYZE ====='
  flutter analyze --no-fatal-infos --no-fatal-warnings
  if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed: $LASTEXITCODE" }

  Write-Host '===== TEST ====='
  flutter test
  if ($LASTEXITCODE -ne 0) { throw "flutter test failed: $LASTEXITCODE" }

  Write-Host '===== BUILD WINDOWS ====='
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed: $LASTEXITCODE" }

  Stop-Transcript | Out-Null
  exit 0
}
catch {
  Write-Host "WINDOWS BUILD ERROR: $($_.Exception.Message)" -ForegroundColor Red
  try { Stop-Transcript | Out-Null } catch {}
  exit 1
}
