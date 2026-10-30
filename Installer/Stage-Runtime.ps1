#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [ValidateSet('Win64')][string]$Platform = 'Win64',
  [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
  [Parameter(Mandatory)][string]$Destination,
  [string]$DependencyConfig,
  [string]$RuntimeConfig,
  [switch]$ValidateOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]'\/')
$Destination = [IO.Path]::GetFullPath($Destination).TrimEnd([char[]]'\/')
function Test-AtOrBelow([string]$Path, [string]$Root) {
  return $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
    $Path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Assert-Input([string]$Path, [string]$Kind) {
  if (-not (Test-Path -LiteralPath $Path -PathType $Kind)) { throw "Required Community input missing: $Path" }
}
function Assert-SafeDestination {
  if ((Test-AtOrBelow $RepoRoot $Destination) -or
      ((Test-AtOrBelow $Destination $RepoRoot) -and -not (Test-AtOrBelow $Destination (Join-Path $RepoRoot '_OUT')))) {
    throw "Unsafe staging destination: $Destination"
  }
  $ancestor = $Destination
  while ($ancestor) {
    if (Test-Path -LiteralPath $ancestor) {
      if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Unsafe staging destination (reparse point): $ancestor"
      }
    }
    $ancestor = Split-Path $ancestor -Parent
  }
  if (Test-Path -LiteralPath $Destination) {
    $marker = Join-Path $Destination '.eln-community-stage'
    if (-not (Test-Path -LiteralPath $Destination -PathType Container) -or
        -not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw "Unsafe staging destination (not Community-owned): $Destination" }
    if ((Get-Item -LiteralPath $marker -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
      throw "Unsafe staging destination (marker reparse point): $marker"
    }
    if (-not [IO.File]::ReadAllText($marker).Trim().Equals($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Unsafe staging destination (different Community root): $Destination"
    }
  }
}
Assert-Input $RepoRoot 'Container'
Assert-SafeDestination
if (-not $DependencyConfig) { $DependencyConfig = Join-Path $RepoRoot 'build-dependencies.local.psd1' }
if (-not $RuntimeConfig) { $RuntimeConfig = Join-Path $RepoRoot 'installer-runtime.local.psd1' }
foreach ($path in @($DependencyConfig, $RuntimeConfig)) {
  if (-not [IO.Path]::IsPathFullyQualified($path)) { throw "Configuration path must be absolute: $path" }
  Assert-Input $path 'Leaf'
}
$dependencies = Import-PowerShellDataFile -LiteralPath $DependencyConfig
foreach ($key in @('RsVarsPath', 'MSBuildPath', 'ShellPath', 'Dcc32Path', 'TmsRoot', 'ExternalUnitPaths')) {
  if (-not $dependencies.ContainsKey($key)) { throw "Build dependency configuration requires $key." }
}
foreach ($key in @('RsVarsPath', 'MSBuildPath', 'ShellPath', 'Dcc32Path', 'TmsRoot')) {
  $path = [string]$dependencies[$key]
  if (-not [IO.Path]::IsPathFullyQualified($path)) { throw "$key must be absolute." }
  Assert-Input $path $(if ($key -eq 'TmsRoot') { 'Container' } else { 'Leaf' })
}
if ($dependencies.ExternalUnitPaths -isnot [array]) { throw 'ExternalUnitPaths must be an array.' }
foreach ($entry in $dependencies.ExternalUnitPaths) {
  $path = ([string]$entry).Replace('{Platform}', $Platform).Replace('{Configuration}', $Configuration)
  if (-not [IO.Path]::IsPathFullyQualified($path)) { throw "External unit path must be absolute: $path" }
  Assert-Input $path 'Container'
}
$runtime = Import-PowerShellDataFile -LiteralPath $RuntimeConfig
foreach ($key in @('IsccPath', 'RuntimeBplRoot', 'SQLiteRuntime', 'WebView2Runtime')) {
  if (-not $runtime.ContainsKey($key)) { throw "Installer runtime configuration requires $key." }
  $path = [string]$runtime[$key]
  if (-not [IO.Path]::IsPathFullyQualified($path)) { throw "$key must be absolute." }
  Assert-Input $path $(if ($key -eq 'RuntimeBplRoot') { 'Container' } else { 'Leaf' })
}
foreach ($pair in @(@{ Key = 'SQLiteRuntime'; Name = 'sqlite3.dll' }, @{ Key = 'WebView2Runtime'; Name = 'WebView2Loader.dll' })) {
  if ([IO.Path]::GetFileName($runtime[$pair.Key]) -ine $pair.Name) { throw "$($pair.Key) must select $($pair.Name)." }
}
$hostRoot = Join-Path $RepoRoot '_OUT/CommunityDesktop'
$viewerRoot = Join-Path $RepoRoot "_OUT/ViewerPackages/$Platform/$Configuration"
$files = [Collections.Generic.List[object]]::new()
function Add-File([string]$Source, [string]$Relative, [bool]$Compiled = $false) {
  if (-not ($ValidateOnly -and $Compiled)) { Assert-Input $Source 'Leaf' }
  $files.Add([pscustomobject]@{ Source = $Source; Relative = $Relative })
}
function Add-Tree([string]$Source, [string]$Relative) {
  Assert-Input $Source 'Container'
  $ancestor = [IO.Path]::GetFullPath($Source)
  while ($ancestor) {
    if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
      throw "Community asset directory must not be a reparse point: $ancestor"
    }
    $ancestor = Split-Path $ancestor -Parent
  }
  $entries = @(Get-ChildItem -LiteralPath $Source -Recurse -Force)
  foreach ($entry in $entries) {
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      throw "Community asset must not be a reparse point: $($entry.FullName)"
    }
  }
  $children = @($entries | Where-Object { -not $_.PSIsContainer })
  if ($children.Count -eq 0) { throw "Required Community asset directory is empty: $Source" }
  foreach ($child in $children) {
    Add-File $child.FullName (Join-Path $Relative ([IO.Path]::GetRelativePath($Source, $child.FullName)))
  }
}
Add-File (Join-Path $hostRoot 'ELNCommunity.exe') 'Program/ELNCommunity.exe' $true
Add-File (Join-Path $hostRoot 'Icons/ELNIcons.dll') 'Program/Icons/ELNIcons.dll' $true
Add-File (Join-Path $RepoRoot "_OUT/CommunityMCP/$Platform/$Configuration/ELNCommunityMCP.exe") 'Program/ELNCommunityMCP.exe' $true
foreach ($directory in @('Core', 'Core.Protocol', 'Viewer.Image', 'Viewer.HTML', 'Viewer.Markdown',
    'Viewer.ColumnarData', 'Viewer.PDF', 'Viewer.Protocol', 'Editor.Markdown', 'Viewer.JSON',
    'Viewer.Note', 'Viewer.OLE', 'Viewer.File', 'Viewer.LAMMPS', 'Viewer.XRDML', 'Viewer.DM3',
    'Viewer.OPJU', 'Viewer.XRayCalc', 'Viewer.XRFX', 'Viewer.Deposition', 'Viewer.ProcessLog',
    'Viewer.Recipe', 'Viewer.DSC', 'Viewer.DSR', 'Viewer.ZRWViewer', 'Viewer.MitFile', 'Viewer.FIBPS',
    'Viewer.TriboViewer', 'Viewer.VK4')) {
  $sourceDirectory = Join-Path $RepoRoot "ViewerPlugins/$directory"
  Assert-Input $sourceDirectory 'Container'
  $packages = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.dpk' -File)
  if ($packages.Count -ne 1) { throw "Expected one selected Community package: $sourceDirectory" }
  $declaration = [regex]::Match([IO.File]::ReadAllText($packages[0].FullName), '(?im)^\s*package\s+([A-Za-z_][A-Za-z0-9_]*)\s*;')
  if (-not $declaration.Success) { throw "Community package identity missing: $($packages[0].FullName)" }
  $name = $declaration.Groups[1].Value + '.bpl'
  $relative = if ($directory -like 'Core*') { $name } else { 'Plugins/' + $name }
  Add-File (Join-Path $viewerRoot $relative) (Join-Path 'Program' $relative) $true
}
$delphiBin = Join-Path (Split-Path (Split-Path $dependencies.RsVarsPath -Parent) -Parent) 'bin64'
foreach ($name in @('rtl370.bpl', 'vcl370.bpl', 'vclimg370.bpl', 'vclwinx370.bpl', 'vcledge370.bpl',
    'xmlrtl370.bpl', 'bindengine370.bpl', 'dbrtl370.bpl', 'vcldb370.bpl', 'vclactnband370.bpl', 'vclx370.bpl', 'Tee9370.bpl')) {
  $source = Join-Path $delphiBin $name
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { $source = Join-Path $runtime.RuntimeBplRoot $name }
  Add-File $source (Join-Path 'Program' $name)
}
# TMS Smart Setup keeps the framework BPLs beside the DCPs, not in the shared Delphi Bpl folder.
function Resolve-ExternalBpl([string]$Name) {
  $directories = @($dependencies.ExternalUnitPaths)
  if ($dependencies.ContainsKey('PlatformExternalUnitPaths') -and
      $dependencies.PlatformExternalUnitPaths.ContainsKey($Platform)) {
    $directories += @($dependencies.PlatformExternalUnitPaths[$Platform])
  }
  foreach ($entry in $directories) {
    $candidate = Join-Path ([string]$entry).Replace('{Platform}', $Platform).Replace('{Configuration}', $Configuration) $Name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  return Join-Path $runtime.RuntimeBplRoot $Name
}
foreach ($name in @('RaizeComponentsVcl370.bpl', 'SynEditDR370.bpl', 'JamShellBrowserRuntime.bpl')) {
  Add-File (Join-Path $runtime.RuntimeBplRoot $name) (Join-Path 'Program' $name)
}
foreach ($name in @('TMSVCLPluginFrameworkPkgCore370.bpl', 'TMSVCLPluginFrameworkPkgMgr370.bpl')) {
  Add-File (Resolve-ExternalBpl $name) (Join-Path 'Program' $name)
}
Add-File (Join-Path $RepoRoot 'ELN.Search/search-artifacts.json') 'Program/search-artifacts.json'
Add-File $runtime.SQLiteRuntime 'Program/sqlite3.dll'
Add-File $runtime.WebView2Runtime 'Program/WebView2Loader.dll'
foreach ($relative in @('Help', 'ProtocolTemplates', 'ExperimentTemplates')) {
  Add-Tree (Join-Path $RepoRoot "ELN.Desktop/Assets/Runtime/$relative") (Join-Path 'Program' $relative)
}
Add-Tree (Join-Path $RepoRoot 'ViewerPlugins/Viewer.Markdown/assets') 'Program/Plugins/MarkdownViewer'
Add-Tree (Join-Path $RepoRoot 'ViewerPlugins/Core.Protocol/Templates') 'Program/Plugins/Templates'
Add-Tree (Join-Path $RepoRoot 'Notices') 'Program/Notices'
foreach ($name in @('LICENSE', 'NOTICE', 'THIRD-PARTY-NOTICES.md')) { Add-File (Join-Path $RepoRoot $name) (Join-Path 'Program' $name) }
$headers = @{}
foreach ($name in @('EquipmentTypes.csv', 'ValueTypes.csv', 'FileTypes.csv', 'Equipment.csv',
    'ActionTypes.csv', 'FileTypeLinks.csv', 'ActionTypeEquipment.csv')) {
  $source = Join-Path $RepoRoot "ELN.Desktop/Assets/Runtime/CSV/$name"
  Assert-Input $source 'Leaf'
  $reader = [IO.StreamReader]::new($source, [Text.Encoding]::UTF8, $true)
  try { $headers[$name] = $reader.ReadLine() } finally { $reader.Dispose() }
  if ([string]::IsNullOrWhiteSpace($headers[$name])) { throw "Community catalog has no header: $source" }
  $fullSource = if ($name -in @('Equipment.csv', 'ActionTypeEquipment.csv')) { Join-Path $RepoRoot "Installer/Demo/$name" } else { $source }
  Add-File $fullSource "Catalogs/Full/$name"
}
if ($ValidateOnly) {
  Write-Host 'Community installer prerequisites validated; compiled output was not checked and no stage was created.'
  return
}
$parent = Split-Path $Destination -Parent
[void][IO.Directory]::CreateDirectory($parent)
$temp = Join-Path $parent ('.community-stage-' + [guid]::NewGuid())
$backup = Join-Path $parent ('.community-stage-backup-' + [guid]::NewGuid())
try {
  [void][IO.Directory]::CreateDirectory($temp)
  foreach ($file in $files) {
    $target = Join-Path $temp $file.Relative
    [void][IO.Directory]::CreateDirectory((Split-Path $target -Parent))
    Copy-Item -LiteralPath $file.Source -Destination $target
  }
  & (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Build-HelpIndex.ps1') -HelpRoot (Join-Path $temp 'Program/Help') | Out-Null
  $empty = Join-Path $temp 'Catalogs/Empty'
  [void][IO.Directory]::CreateDirectory($empty)
  foreach ($name in $headers.Keys) {
    [IO.File]::WriteAllText((Join-Path $empty $name), $headers[$name] + "`r`n`r`n", [Text.UTF8Encoding]::new($false))
  }
  [IO.File]::WriteAllText((Join-Path $temp '.eln-community-stage'), $RepoRoot, [Text.UTF8Encoding]::new($false))
  Assert-SafeDestination
  $movedOld = Test-Path -LiteralPath $Destination -PathType Container
  if ($movedOld) { [IO.Directory]::Move($Destination, $backup) }
  try { [IO.Directory]::Move($temp, $Destination) } catch {
    if ($movedOld) { [IO.Directory]::Move($backup, $Destination) }
    throw
  }
  if ($movedOld) { Remove-Item -LiteralPath $backup -Recurse -Force }
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "Community runtime and full/empty catalogs staged: $Destination"
