#requires -Version 7.0
param(
  [ValidateSet('Win32')][string]$Platform = 'Win32',
  [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
  [string]$DependencyConfig,
  [string]$RuntimeConfig,
  [switch]$ValidateOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
if (-not $DependencyConfig) { $DependencyConfig = $env:ELN_BUILD_DEPENDENCIES }
if (-not $DependencyConfig) { $DependencyConfig = Join-Path $repoRoot 'build-dependencies.local.psd1' }
if (-not $RuntimeConfig) { $RuntimeConfig = Join-Path $repoRoot 'installer-runtime.local.psd1' }
$outputRoot = Join-Path $repoRoot "_OUT/Installer/$Platform/$Configuration"
$stage = Join-Path $outputRoot 'Stage'
$stageScript = Join-Path $repoRoot 'Installer/Stage-Runtime.ps1'
$installerScript = Join-Path $repoRoot 'Installer/ELNCommunitySetup.iss'
$buildHelper = Join-Path $PSScriptRoot 'build-community.ps1'
foreach ($path in @($installerScript, $buildHelper)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Community installer source missing: $path" }
}
& $stageScript -RepoRoot $repoRoot -Platform $Platform -Configuration $Configuration -Destination $stage `
  -DependencyConfig $DependencyConfig -RuntimeConfig $RuntimeConfig -ValidateOnly
$dependencies = Import-PowerShellDataFile -LiteralPath $DependencyConfig
foreach ($product in @('tms.biz.aurelius', 'tms.biz.bcl')) {
  $path = Join-Path $dependencies.TmsRoot "$product/packages/d13/$Platform/$Configuration"
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Licensed build dependency missing: $path" }
}
$studioRoot = Split-Path (Split-Path $dependencies.Dcc32Path -Parent) -Parent
foreach ($relative in @("lib/$Platform/release", "lib/$Platform/debug")) {
  $path = Join-Path $studioRoot $relative
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Standard Delphi library missing: $path" }
}
if ($ValidateOnly) {
  Write-Host 'Community installer validation passed; no compilation or output mutation.'
  return
}
[void][IO.Directory]::CreateDirectory($outputRoot)
$log = Join-Path $outputRoot 'build-installer.log'
"ELN Community installer build: $Platform $Configuration" | Set-Content -LiteralPath $log -Encoding utf8
foreach ($target in @('CommunityDesktop', 'ViewerPackages')) {
  & $buildHelper -Target $target -Platform $Platform -Configuration $Configuration -DependencyConfig $DependencyConfig `
    -RuntimeConfig $RuntimeConfig 2>&1 | Tee-Object -FilePath $log -Append
}
$hostPath = Join-Path $repoRoot '_OUT/CommunityDesktop/ELNCommunity.exe'
$metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($hostPath)
$version = $null
if ($metadata.ProductName -ne 'ELN Community' -or $metadata.FileDescription -ne 'ELN Community Desktop' -or
    $metadata.OriginalFilename -ne 'ELNCommunity.exe' -or $metadata.FileVersion -ne $metadata.ProductVersion -or
    -not [version]::TryParse($metadata.FileVersion, [ref]$version) -or $version.Revision -lt 0) {
  throw "Community executable identity/version is missing or inconsistent: $hostPath"
}
& $stageScript -RepoRoot $repoRoot -Platform $Platform -Configuration $Configuration -Destination $stage `
  -DependencyConfig $DependencyConfig -RuntimeConfig $RuntimeConfig 2>&1 | Tee-Object -FilePath $log -Append
$runtime = Import-PowerShellDataFile -LiteralPath $RuntimeConfig
$installerOutput = Join-Path $outputRoot 'Output'
& $runtime.IsccPath '/Qp' "/DBuildStage=$stage" "/DMyAppVersion=$($version.ToString())" "/O$installerOutput" $installerScript `
  2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "Community installer compilation failed with exit code $LASTEXITCODE; log: $log" }
$installer = Join-Path $installerOutput "ELNCommunitySetup-$($version.ToString()).exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Community installer output missing: $installer" }
Write-Host "Community installer built: $installer"
