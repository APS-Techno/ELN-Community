#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$StageScript = Join-Path $PSScriptRoot 'Stage-Runtime.ps1'
$SourceRoot = Split-Path $PSScriptRoot -Parent
$CatalogNames = @('EquipmentTypes.csv', 'ValueTypes.csv', 'FileTypes.csv', 'Equipment.csv',
  'ActionTypes.csv', 'FileTypeLinks.csv', 'ActionTypeEquipment.csv')
$ViewerDirectories = @('Core', 'Core.Protocol', 'Viewer.Image', 'Viewer.HTML',
  'Viewer.Markdown', 'Viewer.ColumnarData', 'Viewer.PDF', 'Viewer.Protocol', 'Editor.Markdown',
  'Viewer.JSON', 'Viewer.Note', 'Viewer.OLE', 'Viewer.File', 'Viewer.LAMMPS', 'Viewer.XRDML',
  'Viewer.DM3', 'Viewer.OPJU', 'Viewer.XRayCalc', 'Viewer.XRFX', 'Viewer.Deposition',
  'Viewer.ProcessLog', 'Viewer.Recipe', 'Viewer.DSC', 'Viewer.DSR')
$StandardPackages = @('rtl370.bpl', 'vcl370.bpl', 'vclimg370.bpl', 'vclwinx370.bpl',
  'vcledge370.bpl', 'xmlrtl370.bpl', 'bindengine370.bpl', 'dbrtl370.bpl', 'vcldb370.bpl',
  'vclactnband370.bpl', 'vclx370.bpl', 'Tee9370.bpl')
$ComponentPackages = @('RaizeComponentsVcl370.bpl', 'SynEditDR370.bpl',
  'TMSVCLPluginFrameworkPkgCoreDXE16.bpl', 'TMSVCLPluginFrameworkPkgMgrDXE16.bpl', 'JamShellBrowserRuntime.bpl')
$Passed = 0
$Failed = 0
function Assert([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Operation, [string]$MessagePart) {
  $failure = $null
  try { & $Operation } catch { $failure = $_ }
  Assert ($null -ne $failure) "Expected rejection: $MessagePart"
  Assert ($failure.Exception.Message.Contains($MessagePart)) "Unexpected rejection: $($failure.Exception.Message)"
}
function Write-FixtureFile([string]$Path, [string]$Content = 'synthetic runtime fixture') {
  [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
  [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function New-StageFixture([switch]$WithoutCompiledInput) {
  $root = Join-Path ([IO.Path]::GetTempPath()) ('ELN-Community-Stage-Test-' + [guid]::NewGuid())
  $repo = Join-Path $root 'Community'
  $destination = Join-Path $repo '_OUT/Installer/Win32/Release/Stage'
  $toolBin = Join-Path $root 'Toolchain/bin'
  $bplRoot = Join-Path $root 'InstalledBpl'
  $runtimeRoot = Join-Path $root 'InstalledRuntime'
  [void][IO.Directory]::CreateDirectory($repo)
  foreach ($relative in @('ELN.Desktop/Assets/Runtime/CSV', 'ELN.Desktop/Assets/Runtime/Help',
      'ELN.Desktop/Assets/Runtime/ProtocolTemplates', 'ELN.Desktop/Assets/Runtime/ExperimentTemplates',
      'ViewerPlugins/Viewer.Markdown/assets', 'ViewerPlugins/Core.Protocol/Templates', 'Notices')) {
    $source = Join-Path $SourceRoot $relative
    $target = Join-Path $repo $relative
    [void][IO.Directory]::CreateDirectory((Split-Path $target -Parent))
    Copy-Item -LiteralPath $source -Destination $target -Recurse
  }
  foreach ($name in @('LICENSE', 'NOTICE', 'THIRD-PARTY-NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination (Join-Path $repo $name)
  }
  foreach ($directory in $ViewerDirectories) {
    $target = Join-Path $repo "ViewerPlugins/$directory"
    [void][IO.Directory]::CreateDirectory($target)
    $package = @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot "ViewerPlugins/$directory") -Filter '*.dpk' -File)
    Assert ($package.Count -eq 1) "Ambiguous source viewer fixture: $directory"
    Copy-Item -LiteralPath $package[0].FullName -Destination $target
    $declaration = [regex]::Match([IO.File]::ReadAllText($package[0].FullName), '(?im)^\s*package\s+([A-Za-z_][A-Za-z0-9_]*)\s*;')
    Assert $declaration.Success "Missing fixture package identity: $directory"
    if (-not $WithoutCompiledInput) {
      $relative = if ($directory -like 'Core*') { $declaration.Groups[1].Value + '.bpl' } else { 'Plugins/' + $declaration.Groups[1].Value + '.bpl' }
      Write-FixtureFile (Join-Path $repo "_OUT/ViewerPackages/Win32/Release/$relative")
    }
  }
  if (-not $WithoutCompiledInput) {
    foreach ($name in @('ELNCommunity.exe', 'ELNPluginCore.bpl', 'ELNProtocolCore.bpl', 'Icons/ELNIcons.dll')) {
      Write-FixtureFile (Join-Path $repo "_OUT/CommunityDesktop/Win32/Release/$name")
    }
  }
  foreach ($name in @('rsvars.bat', 'dcc32.exe', 'msbuild.exe', 'cmd.exe') + $StandardPackages) {
    Write-FixtureFile (Join-Path $toolBin $name)
  }
  foreach ($name in $ComponentPackages) { Write-FixtureFile (Join-Path $bplRoot $name) }
  $sqlite = Join-Path $runtimeRoot 'sqlite3.dll'
  $webview = Join-Path $runtimeRoot 'WebView2Loader.dll'
  $iscc = Join-Path $runtimeRoot 'ISCC.exe'
  foreach ($path in @($sqlite, $webview, $iscc)) { Write-FixtureFile $path }
  [void][IO.Directory]::CreateDirectory((Join-Path $root 'Tms'))
  $dependencies = Join-Path $root 'dependencies.psd1'
  Write-FixtureFile $dependencies ("@{ RsVarsPath = '$toolBin\rsvars.bat'; Dcc32Path = '$toolBin\dcc32.exe'; MSBuildPath = '$toolBin\msbuild.exe'; ShellPath = '$toolBin\cmd.exe'; TmsRoot = '$root\Tms'; ExternalUnitPaths = @() }")
  $runtimeConfig = Join-Path $root 'runtime.psd1'
  Write-FixtureFile $runtimeConfig ("@{ IsccPath = '$iscc'; RuntimeBplRoot = '$bplRoot'; SQLiteRuntime = '$sqlite'; WebView2Runtime = '$webview' }")
  $demo = Join-Path $repo 'Installer/Demo'
  [void][IO.Directory]::CreateDirectory($demo)
  foreach ($name in @('Equipment.csv', 'ActionTypeEquipment.csv')) {
    Copy-Item -LiteralPath (Join-Path $SourceRoot "Installer/Demo/$name") -Destination $demo
  }
  $stageSentinel = Join-Path $destination 'previous-runtime.txt'
  if (-not $WithoutCompiledInput) {
    Write-FixtureFile (Join-Path $destination '.eln-community-stage') $repo
    Write-FixtureFile $stageSentinel 'previous complete runtime'
  }
  $sourceSentinel = Join-Path $repo 'source-preservation.txt'
  Write-FixtureFile $sourceSentinel 'source must remain unchanged'
  [pscustomobject]@{
    Root = $root; RepoRoot = $repo; Destination = $destination; SQLiteRuntime = $sqlite
    StageSentinel = $stageSentinel; SourceSentinel = $sourceSentinel
    Arguments = @{ RepoRoot = $repo; Platform = 'Win32'; Configuration = 'Release'; Destination = $destination
      DependencyConfig = $dependencies; RuntimeConfig = $runtimeConfig }
  }
}
function Run-TestCase([string]$Name, [scriptblock]$Test, [switch]$WithoutCompiledInput) {
  $fixture = $null
  try {
    $fixture = New-StageFixture -WithoutCompiledInput:$WithoutCompiledInput
    & $Test $fixture
    $script:Passed++
    Write-Host "PASS $Name"
  } catch {
    $script:Failed++
    Write-Host "FAIL ${Name}: $($_.Exception.Message)"
  } finally {
    if ($fixture -and (Test-Path -LiteralPath $fixture.Root)) {
      Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
  }
}
Run-TestCase 'MissingRuntimePreservesPreviousStage' {
  param($f)
  $before = (Get-FileHash -LiteralPath $f.StageSentinel).Hash
  Remove-Item -LiteralPath $f.SQLiteRuntime
  $arguments = $f.Arguments
  Assert-Throws { & $StageScript @arguments } $f.SQLiteRuntime
  Assert ((Get-FileHash -LiteralPath $f.StageSentinel).Hash -eq $before) 'Previous stage changed'
}
Run-TestCase 'UnsafeDestinationPreservesSource' {
  param($f)
  $before = (Get-FileHash -LiteralPath $f.SourceSentinel).Hash
  foreach ($destination in @($f.RepoRoot, (Join-Path $f.RepoRoot 'ELN.Desktop'), (Split-Path $f.RepoRoot -Parent))) {
    $arguments = $f.Arguments.Clone()
    $arguments.Destination = $destination
    Assert-Throws { & $StageScript @arguments } 'Unsafe staging destination'
    Assert ((Get-FileHash -LiteralPath $f.SourceSentinel).Hash -eq $before) 'Source changed'
  }
}
Run-TestCase 'AssetRootJunctionPreservesPreviousStage' {
  param($f)
  $before = (Get-FileHash -LiteralPath $f.StageSentinel).Hash
  $outside = Join-Path $f.Root 'OutsideCommunity'
  Write-FixtureFile (Join-Path $outside 'outside.txt') 'must not enter the package'
  $help = Join-Path $f.RepoRoot 'ELN.Desktop/Assets/Runtime/Help'
  Remove-Item -LiteralPath $help -Recurse -Force
  [void](New-Item -ItemType Junction -Path $help -Target $outside)
  $arguments = $f.Arguments
  Assert-Throws { & $StageScript @arguments } 'reparse point'
  Assert ((Get-FileHash -LiteralPath $f.StageSentinel).Hash -eq $before) 'Junction input replaced the previous stage'
}
Run-TestCase 'NestedAssetJunctionPreservesPreviousStage' {
  param($f)
  $before = (Get-FileHash -LiteralPath $f.StageSentinel).Hash
  $outside = Join-Path $f.Root 'OutsideCommunity'
  Write-FixtureFile (Join-Path $outside 'outside.txt') 'must not be silently skipped or packaged'
  $link = Join-Path $f.RepoRoot 'ELN.Desktop/Assets/Runtime/Help/LinkedOutside'
  [void](New-Item -ItemType Junction -Path $link -Target $outside)
  $arguments = $f.Arguments
  Assert-Throws { & $StageScript @arguments } 'reparse point'
  Assert ((Get-FileHash -LiteralPath $f.StageSentinel).Hash -eq $before) 'Nested junction replaced the previous stage'
}
Run-TestCase 'AssetAncestorJunctionPreservesPreviousStage' {
  param($f)
  $before = (Get-FileHash -LiteralPath $f.StageSentinel).Hash
  $assets = Join-Path $f.RepoRoot 'ELN.Desktop/Assets'
  $outside = Join-Path $f.Root 'OutsideAssets'
  [IO.Directory]::Move($assets, $outside)
  [void](New-Item -ItemType Junction -Path $assets -Target $outside)
  $arguments = $f.Arguments
  Assert-Throws { & $StageScript @arguments } 'reparse point'
  Assert ((Get-FileHash -LiteralPath $f.StageSentinel).Hash -eq $before) 'Ancestor junction replaced the previous stage'
}
Run-TestCase 'ValidateOnlyCreatesNoOutput' {
  param($f)
  $arguments = $f.Arguments
  & $StageScript @arguments -ValidateOnly
  Assert (-not (Test-Path -LiteralPath $f.Destination)) 'Validation created a stage'
} -WithoutCompiledInput
Run-TestCase 'EmptyCatalogTransformRemovesDataRows' {
  param($f)
  $arguments = $f.Arguments
  & $StageScript @arguments
  foreach ($name in $CatalogNames) {
    $path = Join-Path $f.Destination "Catalogs/Empty/$name"
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing catalog: $name"
    Assert (@(Import-Csv -LiteralPath $path).Count -eq 0) "Empty catalog contains data: $name"
  }
}
Run-TestCase 'DemoReferencesResolve' {
  param($f)
  $arguments = $f.Arguments
  & $StageScript @arguments
  $full = Join-Path $f.Destination 'Catalogs/Full'
  $equipment = @(Import-Csv -LiteralPath (Join-Path $full 'Equipment.csv'))
  $types = @(Import-Csv -LiteralPath (Join-Path $full 'EquipmentTypes.csv'))
  $actions = @(Import-Csv -LiteralPath (Join-Path $full 'ActionTypes.csv'))
  $links = @(Import-Csv -LiteralPath (Join-Path $full 'ActionTypeEquipment.csv'))
  foreach ($instrument in $equipment) { Assert ($types.Type -contains $instrument.EquipmentType) 'Unknown demo equipment type' }
  foreach ($link in $links) {
    Assert ($equipment.Model -contains $link.Equipment) 'Unknown assigned demo instrument'
    Assert ($actions.Title -contains $link.ActionType) 'Unknown assigned demo action'
  }
  $pairs = @($links | ForEach-Object { "$($_.Equipment)/$($_.ActionType)" })
  $expected = @('Demo Furnace/Annealing', 'Demo Diffractometer/XRD', 'Demo Balance/Mass', 'Demo Deposition System/Deposition')
  Assert (@(Compare-Object $expected $pairs).Count -eq 0) 'Demo assignments differ from the approved set'
}
Write-Host "$Passed passed; $Failed failed"
if ($Failed) { exit 1 }
