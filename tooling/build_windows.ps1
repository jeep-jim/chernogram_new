$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$logPath = Join-Path $PWD 'windows-build.txt'

function Invoke-LoggedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Command
  )
  "===== $Name =====" | Tee-Object -FilePath $logPath -Append
  cmd.exe /D /S /C "$Command 2>&1" | Tee-Object -FilePath $logPath -Append
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    throw "$Name failed with exit code $code"
  }
}

try {
  Set-Content -Path $logPath -Value '' -Encoding UTF8

  Invoke-LoggedCommand -Name 'FLUTTER' -Command 'flutter --version'
  Invoke-LoggedCommand -Name 'ENABLE WINDOWS' -Command 'flutter config --enable-windows-desktop'

  if (-not (Test-Path 'windows/CMakeLists.txt')) {
    Invoke-LoggedCommand `
      -Name 'CREATE WINDOWS PLATFORM' `
      -Command 'flutter create --platforms=windows --project-name chernogram --no-pub .'
  }

  Invoke-LoggedCommand `
    -Name 'FIX 0.15 COMPILE' `
    -Command 'python tooling/fix_v015_compile.py'
  Invoke-LoggedCommand `
    -Name 'FIX 0.16 FOUNDATION' `
    -Command 'python tooling/fix_v016_foundation.py'
  Invoke-LoggedCommand `
    -Name 'INSTALL PILLOW' `
    -Command 'python -m pip install pillow --disable-pip-version-check --quiet'
  Invoke-LoggedCommand `
    -Name 'PREPARE WINDOWS' `
    -Command 'python tooling/fix_windows_desktop.py'
  Invoke-LoggedCommand `
    -Name 'FIX 0.16.2 RUNTIME' `
    -Command 'python tooling/fix_v0162_runtime.py'
  Invoke-LoggedCommand `
    -Name 'FIX 0.16.2 BRAND' `
    -Command 'python tooling/fix_v0162_brand.py'
  Invoke-LoggedCommand `
    -Name 'MATERIALIZE 0.16.3 RINGTONE' `
    -Command 'python tooling/materialize_v0163_ringtone.py'
  Invoke-LoggedCommand `
    -Name 'FIX 0.16.3 REALTIME' `
    -Command 'python tooling/fix_v0163_realtime.py'
  Invoke-LoggedCommand `
    -Name 'FIX 0.16.4 FEEDBACK' `
    -Command 'python tooling/fix_v0164_feedback.py'
  Invoke-LoggedCommand -Name 'PUB GET' -Command 'flutter pub get'
  Invoke-LoggedCommand -Name 'FORMAT' -Command 'dart format lib'
  Invoke-LoggedCommand `
    -Name 'ANALYZE' `
    -Command 'flutter analyze --no-fatal-infos --no-fatal-warnings'
  Invoke-LoggedCommand -Name 'TEST' -Command 'flutter test'
  Invoke-LoggedCommand `
    -Name 'BUILD WINDOWS' `
    -Command 'flutter build windows --release'

  exit 0
}
catch {
  $message = "WINDOWS BUILD ERROR: $($_.Exception.Message)"
  Write-Host $message -ForegroundColor Red
  Add-Content -Path $logPath -Value $message -Encoding UTF8
  exit 1
}
