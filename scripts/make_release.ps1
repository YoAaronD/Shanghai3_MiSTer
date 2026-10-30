# Make a release of the SunsoftGA9201 core (Shanghai III, Hebereke no Popoon, Blocken) (Windows PowerShell 5.1 or PowerShell 7).
#
#   powershell -ExecutionPolicy Bypass -File scripts\make_release.ps1 [-Date YYYYMMDD]
#
# Run after a successful Quartus build. It:
#   1. copies output_files\SunsoftGA9201.rbf to releases\SunsoftGA9201_<Date>.rbf (commit that file);
#   2. writes output_files\SunsoftGA9201_MiSTer_<Date>.zip, laid out like the MiSTer SD card:
#        _Arcade/<every .mra in releases\>
#        _Arcade/cores/SunsoftGA9201_<Date>.rbf
#      Attach the zip to the GitHub release. Users copy its _Arcade folder onto the SD root.
# The date defaults to today. ROMs are never included.
param([string]$Date = (Get-Date -Format 'yyyyMMdd'))

$ErrorActionPreference = 'Stop'
if ($Date -notmatch '^\d{8}$') { throw "Date must be YYYYMMDD, got '$Date'" }

$root     = Split-Path -Parent $PSScriptRoot
$built    = Join-Path (Join-Path $root 'output_files') 'SunsoftGA9201.rbf'
$releases = Join-Path $root 'releases'
$rbfName  = "SunsoftGA9201_$Date.rbf"
$rbf      = Join-Path $releases $rbfName
$mras     = @(Get-ChildItem -LiteralPath $releases -Filter '*.mra' | Sort-Object Name)
$zipPath  = Join-Path (Join-Path $root 'output_files') "SunsoftGA9201_MiSTer_$Date.zip"

if (Test-Path -LiteralPath $built) {
    Copy-Item -LiteralPath $built -Destination $rbf -Force
    Write-Host "Copied the Quartus build to releases\$rbfName"
} elseif (Test-Path -LiteralPath $rbf) {
    Write-Host "No new build in output_files; using the existing releases\$rbfName"
} else {
    throw "Neither output_files\SunsoftGA9201.rbf nor releases\$rbfName exists. Compile first."
}
if ($mras.Count -eq 0) { throw "No .mra files in releases\" }

# Build the zip with forward-slash entry names (Compress-Archive in PowerShell 5.1
# writes backslashes, which some unzip tools on Linux/MiSTer mishandle).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($m in $mras) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $m.FullName, "_Arcade/$($m.Name)")
    }
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $rbf, "_Arcade/cores/$rbfName")
} finally {
    $zip.Dispose()
}
Write-Host "Wrote output_files\SunsoftGA9201_MiSTer_$Date.zip:"
foreach ($m in $mras) { Write-Host "  _Arcade/$($m.Name)" }
Write-Host "  _Arcade/cores/$rbfName"
