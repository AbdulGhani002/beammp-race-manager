# Builds the two things the server needs and one archive that carries both.
#
#   powershell -ExecutionPolicy Bypass -File tools/build.ps1
#
# Output lands in build/:
#   RaceManager.zip           the client mod, as BeamMP ships it to players
#   deploy/                   the same tree the server has
#   racemanager-deploy.zip    upload this to the panel root and unarchive it

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$root   = Split-Path -Parent $PSScriptRoot
$build  = Join-Path $root "build"
$deploy = Join-Path $build "deploy"

if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory -Path $deploy -Force | Out-Null

# CreateFromDirectory writes Windows separators into the entry names, which a
# Linux host and BeamNG both read as one long filename rather than a path.
# Entries go in by hand so the names always use forward slashes.
function New-Zip {
  param([string] $SourceDir, [string] $ZipPath)

  $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, "Create")
  try {
    $base = (Resolve-Path $SourceDir).Path.TrimEnd("\") + "\"
    foreach ($file in Get-ChildItem $SourceDir -Recurse -File) {
      $name = $file.FullName.Substring($base.Length).Replace("\", "/")
      $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
      $out = $entry.Open()
      try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $out.Write($bytes, 0, $bytes.Length)
      } finally { $out.Dispose() }
    }
  } finally { $zip.Dispose() }
}

# --- client mod ------------------------------------------------------------
# scripts/, lua/ and ui/ sit at the root of the zip. BeamNG will not find the
# mod if they are inside a folder.
$clientZip = Join-Path $build "RaceManager.zip"
New-Zip -SourceDir (Join-Path $root "client") -ZipPath $clientZip
Write-Output ("client mod    {0,6:N1} KB" -f ((Get-Item $clientZip).Length / 1KB))

# --- server plugin ---------------------------------------------------------
$serverDst = Join-Path $deploy "Resources/Server/RaceManager"
New-Item -ItemType Directory -Path $serverDst -Force | Out-Null
Copy-Item (Join-Path $root "server/RaceManager/*.lua") $serverDst

# data/ is deliberately not shipped. Players, tracks and drafts already on the
# server have to survive an update.
$luaFiles = Get-ChildItem $serverDst -Filter *.lua
$lines = ($luaFiles | Get-Content | Measure-Object -Line).Lines
Write-Output ("server plugin {0,6} lua files, {1} lines" -f $luaFiles.Count, $lines)

$clientDst = Join-Path $deploy "Resources/Client"
New-Item -ItemType Directory -Path $clientDst -Force | Out-Null
Copy-Item $clientZip (Join-Path $clientDst "RaceManager.zip")

# --- one archive to upload -------------------------------------------------
$bundle = Join-Path $build "racemanager-deploy.zip"
New-Zip -SourceDir $deploy -ZipPath $bundle
Write-Output ("bundle        {0,6:N1} KB  ->  build/racemanager-deploy.zip" -f ((Get-Item $bundle).Length / 1KB))
Write-Output ""
Write-Output "Upload the bundle to the panel file manager at /home/container,"
Write-Output "use Unarchive on it, then restart the server."
