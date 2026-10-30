param(
  [string]$Destination = $(if ($env:ELN_SEARCH_ARTIFACTS) { $env:ELN_SEARCH_ARTIFACTS }
    else { Join-Path $env:LOCALAPPDATA 'APS-ELN\search-artifacts' }),
  [string]$Manifest = (Join-Path $PSScriptRoot '..\ELN.Search\search-artifacts.json'),
  [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$pins = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ($pins.ManifestVersion -ne 3) { throw "Unsupported manifest version: $($pins.ManifestVersion). This script needs version 3." }
$script:problems = 0

function Test-Optional($Part) {
  return [bool]($Part.PSObject.Properties['Optional'] -and $Part.Optional)
}

function Test-Pinned([string]$Path, $Pin) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $item = Get-Item -LiteralPath $Path
  if ($item.Length -ne $Pin.Size) { return $false }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Pin.Sha256
}

function Write-Absent([string]$Path, [bool]$Optional) {
  if ($Optional) { Write-Host "absent    $Path (optional)"; return }
  Write-Host "MISSING   $Path"
  $script:problems++
}

function Get-Pinned([string]$Url, [string]$Path, $Pin, [bool]$Optional) {
  if (Test-Pinned $Path $Pin) { Write-Host "ok        $Path"; return }
  if ($VerifyOnly) { Write-Absent $Path $Optional; return }
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  $partial = "$Path.partial"
  Write-Host "download  $Url"
  & curl.exe --fail --location --retry 3 --silent --show-error --output $partial $Url
  if ($LASTEXITCODE -ne 0) { throw "Download failed ($LASTEXITCODE): $Url" }
  if (-not (Test-Pinned $partial $Pin)) {
    Remove-Item -LiteralPath $partial -Force
    throw "Size or SHA-256 mismatch: $Url"
  }
  Move-Item -LiteralPath $partial -Destination $Path -Force
  Write-Host "verified  $Path"
}

function Install-Model($Model) {
  $modelRoot = Join-Path $Destination $Model.Folder
  $optional = Test-Optional $Model
  foreach ($file in $Model.Files) {
    Get-Pinned "$($Model.BaseUrl)/$($file.Name)" (Join-Path $modelRoot $file.Name) $file $optional
  }
}

function Install-Archive($Archive) {
  $root = Join-Path $Destination $Archive.Folder
  $archivePath = Join-Path $root $Archive.Name
  $optional = Test-Optional $Archive
  $missing = @($Archive.Files | Where-Object { -not (Test-Pinned (Join-Path $root $_.Name) $_) })
  if ($missing.Count -gt 0 -and -not $VerifyOnly) {
    Get-Pinned $Archive.Url $archivePath $Archive $optional
    if ($Archive.Kind -eq 'zip') {
      Expand-Archive -LiteralPath $archivePath -DestinationPath $root -Force
    }
    elseif ($Archive.Kind -eq 'tar.gz') {
      $members = @($missing | ForEach-Object { $_.Name.Replace('\', '/') })
      & tar.exe -xzf $archivePath -C $root @members
      if ($LASTEXITCODE -ne 0) { throw "tar failed ($LASTEXITCODE): $archivePath" }
    }
    else { throw "Unsupported archive kind: $($Archive.Kind)" }
    Remove-Item -LiteralPath $archivePath -Force
  }
  foreach ($file in $Archive.Files) {
    $path = Join-Path $root $file.Name
    if (Test-Pinned $path $file) { Write-Host "ok        $path" }
    else { Write-Absent $path $optional }
  }
}

foreach ($optionalPass in @($false, $true)) {
  foreach ($model in @($pins.Models)) {
    if ((Test-Optional $model) -eq $optionalPass) { Install-Model $model }
  }
  foreach ($archive in @($pins.Archives)) {
    if ((Test-Optional $archive) -eq $optionalPass) { Install-Archive $archive }
  }
}

if ($script:problems -gt 0) { throw "$($script:problems) required artifact file(s) are missing or modified." }
Write-Host "Search artifacts ready in $Destination"
