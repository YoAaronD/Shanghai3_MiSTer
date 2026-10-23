# Make a release of the Shanghai III core (Windows PowerShell 5.1 or PowerShell 7).
#
#   powershell -ExecutionPolicy Bypass -File scripts\make_release.ps1 [-Date YYYYMMDD]
#
# Run after a successful Quartus build. It:
#   1. copies output_files\Shanghai3.rbf to releases\Shanghai3_<Date>.rbf (commit that file);
#   2. writes output_files\Shanghai3_MiSTer_<Date>.zip, laid out like the MiSTer SD card:
#        _Arcade/Shanghai III (Japan).mra
#        _Arcade/cores/Shanghai3_<Date>.rbf
#      Attach the zip to the GitHub release. Users copy its _Arcade folder onto the SD root.
# The date defaults to today. ROMs are never included.
param([string]$Date = (Get-Date -Format 'yyyyMMdd'))

$ErrorActionPreference = 'Stop'
if ($Date -notmatch '^\d{8}$') { throw "Date must be YYYYMMDD, got '$Date'" }

$root     = Split-Path -Parent $PSScriptRoot
$built    = Join-Path (Join-Path $root 'output_files') 'Shanghai3.rbf'
$releases = Join-Path $root 'releases'
$rbfName  = "Shanghai3_$Date.rbf"
$rbf      = Join-Path $releases $rbfName
$mraName  = 'Shanghai III (Japan).mra'
$mra      = Join-Path $releases $mraName
$zipPath  = Join-Path (Join-Path $root 'output_files') "Shanghai3_MiSTer_$Date.zip"

if (Test-Path -LiteralPath $built) {
    Copy-Item -LiteralPath $built -Destination $rbf -Force
    Write-Host "Copied the Quartus build to releases\$rbfName"
} elseif (Test-Path -LiteralPath $rbf) {
    Write-Host "No new build in output_files; using the existing releases\$rbfName"
} else {
    throw "Neither output_files\Shanghai3.rbf nor releases\$rbfName exists. Compile first."
}
if (-not (Test-Path -LiteralPath $mra)) { throw "Missing releases\$mraName" }

# Build the zip with forward-slash entry names (Compress-Archive in PowerShell 5.1
# writes backslashes, which some unzip tools on Linux/MiSTer mishandle).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $mra, "_Arcade/$mraName")
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $rbf, "_Arcade/cores/$rbfName")
} finally {
    $zip.Dispose()
}
Write-Host "Wrote output_files\Shanghai3_MiSTer_$Date.zip:"
Write-Host "  _Arcade/$mraName"
Write-Host "  _Arcade/cores/$rbfName"
