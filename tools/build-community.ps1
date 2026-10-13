param(
  [ValidateSet('StorageTests', 'StorageSmoke', 'NotebookTests', 'GateTests',
    'AuthorizationTests', 'LocalFileTests', 'ScientificTests', 'DesktopRegressionTests',
    'MarkdownEditorAttachmentTests', 'MarkdownLauncherTests', 'ViewerPackages',
    'CommunityDesktop', 'CommunityMCP')]
  [string]$Target = 'StorageTests',
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Debug',
  [ValidateSet('Win32', 'Win64')]
  [string]$Platform = 'Win32',
  [switch]$RunTests,
  [string]$SourceRoot = (Split-Path $PSScriptRoot -Parent),
  [string]$ViewerRoot,
  [string]$DependencyConfig
)

$ErrorActionPreference = 'Stop'
if ($RunTests -and $Target -in @('CommunityDesktop', 'CommunityMCP', 'ViewerPackages')) {
  throw 'RunTests is only supported for test targets; this helper never launches a host.'
}
$sourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if (-not $ViewerRoot) { $ViewerRoot = Join-Path $sourceRoot 'ViewerPlugins' }
$viewerRoot = [IO.Path]::GetFullPath($ViewerRoot)
if (-not $DependencyConfig) { $DependencyConfig = $env:ELN_BUILD_DEPENDENCIES }
if (-not $DependencyConfig) { $DependencyConfig = Join-Path $sourceRoot 'build-dependencies.local.psd1' }
if (-not (Test-Path -LiteralPath $DependencyConfig -PathType Leaf)) {
  throw "Explicit dependency configuration missing: $DependencyConfig"
}
$dependencies = Import-PowerShellDataFile -LiteralPath $DependencyConfig
foreach ($key in @('RsVarsPath', 'MSBuildPath', 'ShellPath', 'Dcc32Path', 'TmsRoot', 'ExternalUnitPaths')) {
  if (-not $dependencies.ContainsKey($key)) { throw "Dependency configuration key missing: $key" }
}
$rsvarsPath = $dependencies.RsVarsPath
$msbuildPath = $dependencies.MSBuildPath
$shellPath = $dependencies.ShellPath
$dcc32Path = $dependencies.Dcc32Path
$tmsRoot = $dependencies.TmsRoot
foreach ($required in @($rsvarsPath, $msbuildPath, $shellPath, $dcc32Path)) {
  if ($required -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or
      -not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required configured build tool missing or not absolute: $required"
  }
}
# Resolve standard RTL/VCL paths before MSBuild evaluates command-line properties.
# rsvars does not supply BDSLIB and clears PLATFORM.
$studioRoot = Split-Path (Split-Path $dcc32Path -Parent) -Parent
$delphiLibraryPath = Join-Path $studioRoot "lib\$Platform\release"
$delphiDebugDcuPath = Join-Path $studioRoot "lib\$Platform\debug"
foreach ($required in @($delphiLibraryPath, $delphiDebugDcuPath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Container)) {
    throw "Standard Delphi library directory missing: $required"
  }
}
$externalPaths = @($dependencies.ExternalUnitPaths | ForEach-Object {
  ([string]$_).Replace('{Platform}', $Platform).Replace('{Configuration}', $Configuration)
})
foreach ($dependency in $externalPaths) {
  if ($dependency -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or
      -not (Test-Path -LiteralPath $dependency -PathType Container)) {
    throw "Configured external dependency missing or not absolute: $dependency"
  }
}
if ($Target -notin @('StorageTests', 'StorageSmoke', 'MarkdownEditorAttachmentTests')) {
  foreach ($product in @('tms.biz.aurelius', 'tms.biz.bcl')) {
    $dependency = "$tmsRoot\$product\packages\d13\$Platform\$Configuration"
    if ($dependency -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or
        -not (Test-Path -LiteralPath $dependency -PathType Container)) {
      throw "Licensed configured external dependency missing or not absolute: $dependency"
    }
    $externalPaths += $dependency
  }
}
$desktopTarget = $Target -eq 'CommunityDesktop'
$viewerTarget = $Target -in @('AuthorizationTests', 'LocalFileTests', 'DesktopRegressionTests',
  'MarkdownLauncherTests', 'CommunityDesktop', 'CommunityMCP', 'ViewerPackages')
$outputRoot = Join-Path $sourceRoot "_OUT\$Target\$Platform\$Configuration"
$packageRoot = Join-Path $outputRoot 'Packages'
$sourceName = switch ($Target) {
  'StorageTests' { 'CommunityStorageTests.dpr' }
  'StorageSmoke' { 'CommunityStorageSmoke.dpr' }
  'NotebookTests' { 'LocalNotebookTests.dpr' }
  'GateTests' { 'LocalGateTests.dpr' }
  'AuthorizationTests' { 'AuthorizationTests.dpr' }
  'LocalFileTests' { 'LocalFileTests.dpr' }
  'ScientificTests' { 'CommunityScientificTests.dpr' }
  'DesktopRegressionTests' { 'DesktopRegressionTests.dpr' }
  'MarkdownEditorAttachmentTests' { 'test_MarkdownEditorAttachments.dpr' }
  'MarkdownLauncherTests' { 'MarkdownLauncherTests.dpr' }
  'CommunityDesktop' { 'ELNCommunity.dpr' }
  'CommunityMCP' { 'ELNCommunityMCP.dpr' }
}
$project = switch ($Target) {
  'CommunityDesktop' { Join-Path $sourceRoot 'ELN.Community.Desktop\ELNCommunity.dproj' }
  'CommunityMCP' { Join-Path $sourceRoot 'ELN.Community.MCP\ELNCommunityMCP.dproj' }
  'MarkdownEditorAttachmentTests' { Join-Path $viewerRoot 'Editor.Markdown\test\test_MarkdownEditorAttachments.dproj' }
  default { Join-Path $sourceRoot 'ELN.Community.Tests\CommunityStorageTests.dproj' }
}
$unitPaths = @(
  $sourceRoot, "$sourceRoot\ELN.Model", "$sourceRoot\ELN.Domain",
  "$sourceRoot\ELN.Community", "$sourceRoot\ELN.DB",
  "$sourceRoot\ELN.Model\ViewModels", "$sourceRoot\ELN.Community.Tests",
  "$sourceRoot\ELN.Desktop\Units"
)
if ($Target -in @('DesktopRegressionTests', 'MarkdownLauncherTests')) {
  $unitPaths += @("$viewerRoot\Viewer.ColumnarData", "$viewerRoot\Viewer.Markdown",
    "$viewerRoot\Editor.Markdown")
}
if ($Target -eq 'DesktopRegressionTests') {
  $unitPaths += @("$viewerRoot\Viewer.LAMMPS", "$viewerRoot\Viewer.XRDML",
    "$viewerRoot\Viewer.DSC", "$viewerRoot\Viewer.DM3", "$viewerRoot\Viewer.XRFX",
    "$viewerRoot\Viewer.XRayCalc")
}
if ($Target -eq 'MarkdownEditorAttachmentTests') {
  $unitPaths += @("$viewerRoot\Editor.Markdown", "$viewerRoot\Viewer.Markdown")
}
$viewerPackages = @('Core\ELNPluginCore', 'Core.Protocol\ELNProtocolCore')
if ($Target -eq 'ViewerPackages') {
  $viewerPackages += @('Viewer.Image\ELNImageViewer', 'Viewer.HTML\ELNHTMLViewer',
    'Viewer.Markdown\ELNMarkdownViewer', 'Viewer.ColumnarData\ELNColumnarDataViewer',
    'Viewer.PDF\ELNPDFViewer', 'Viewer.Protocol\ELNProtocolViewer',
    'Editor.Markdown\ELNMarkdownEditor', 'Viewer.JSON\ELNJSONViewer',
    'Viewer.Note\ELNNoteViewer', 'Viewer.OLE\ELNOLEViewer', 'Viewer.File\ELNFileViewer',
    'Viewer.LAMMPS\ELNLAMMPSViewer', 'Viewer.XRDML\ELNXRDMLViewer',
    'Viewer.DM3\ELNDM3Viewer', 'Viewer.OPJU\ELNOPJUViewer', 'Viewer.XRayCalc\ELNXRCViewer',
    'Viewer.XRFX\ELNXRFXViewer', 'Viewer.Deposition\ELNDepositionViewer',
    'Viewer.ProcessLog\ELNProcessLogViewer', 'Viewer.Recipe\ELNRecipeViewer',
    'Viewer.DSC\ELNDSCViewer', 'Viewer.DSR\ELNDSRViewer')
}
if ($viewerTarget) {
  foreach ($package in $viewerPackages) {
    $packageProject = Join-Path $viewerRoot "$package.dproj"
    if (-not (Test-Path -LiteralPath $packageProject -PathType Leaf)) {
      throw "Selected viewer package missing: $packageProject"
    }
  }
  $unitPaths += @(
    "$sourceRoot\ELN.Components", "$sourceRoot\ELN.Desktop\Views",
    "$sourceRoot\ELN.Desktop\ViewModels", "$sourceRoot\ELN.Desktop\Forms",
    "$sourceRoot\ELN.Desktop\Editors", "$sourceRoot\ELN.Desktop\Dialogs",
    "$sourceRoot\ELN.Desktop\Dialogs\System", "$sourceRoot\ELN.Desktop\Dialogs\Search",
    "$sourceRoot\ELN.Desktop\Dialogs\Projects", "$sourceRoot\ELN.Desktop\Dialogs\Items",
    "$sourceRoot\ELN.Desktop\Dialogs\Protocols", "$sourceRoot\ELN.Desktop\Dialogs\Protocols\Cards",
    "$sourceRoot\ELN.Desktop\Dialogs\Hypotheses", "$sourceRoot\ELN.Desktop\Dialogs\ExperimentTemplates",
    "$sourceRoot\ELN.Desktop\Dialogs\Export", "$sourceRoot\ELN.MCPServer"
  )
  foreach ($package in $viewerPackages) {
    $packageName = Split-Path $package -Leaf
    $packageDcu = Join-Path $packageRoot "$packageName\DCU"
    $packageHpp = Join-Path $packageRoot "$packageName\Hpp"
    $packageResources = Join-Path $packageRoot "$packageName\Resources"
    $packageOutput = if ($package -like 'Core*') { $outputRoot } else { Join-Path $outputRoot 'Plugins' }
    New-Item -ItemType Directory -Force -Path $packageRoot, $packageDcu, $packageHpp, $packageResources, $packageOutput | Out-Null
    $packageProject = Join-Path $viewerRoot "$package.dproj"
    # Current package contracts and source always precede configured installed units.
    $packagePaths = @($packageRoot, "$viewerRoot\Core", "$viewerRoot\Core.Protocol",
      (Split-Path $packageProject -Parent))
    if ($packageName -eq 'ELNMarkdownEditor') { $packagePaths += "$viewerRoot\Viewer.Markdown" }
    $packagePaths += $externalPaths
    $packageArguments = @(
      "`"$packageProject`"", '/t:Build',
      "/p:Config=$Configuration", "/p:Platform=$Platform",
      "`"/p:DelphiLibraryPath=$delphiLibraryPath`"",
      "`"/p:DelphiDebugDCUPath=$delphiDebugDcuPath`"",
      '/p:DCC_TranslatedLibraryPath=', '/p:DCC_TranslatedDebugLibraryPath=',
      '/p:DCC_ResourcePath=', '/p:DCC_TranslatedResourcePath=',
      "`"/p:DCC_UnitSearchPath=$($packagePaths -join '%3B')`"",
      "`"/p:ELN_ExternalUnitPaths=$($externalPaths -join '%3B')`"",
      "`"/p:DCC_DcpOutput=$packageRoot`"", "`"/p:DCC_BplOutput=$packageOutput`"",
      "`"/p:DCC_ExeOutput=$packageOutput`"", "`"/p:DCC_DcuOutput=$packageDcu`"",
      "`"/p:DCC_HppOutput=$packageHpp`"", "`"/p:DCC_ResourceOutput=$packageResources`"",
      '/p:DCC_MapFile=3', '/p:PreBuildEvent=', '/p:PostBuildEvent=', '/p:PreLinkEvent=', '/v:normal', '/nologo'
    )
    $packageCommand = "call `"$rsvarsPath`" && `"$msbuildPath`" " + ($packageArguments -join ' ')
    & $shellPath /d /c $packageCommand
    if ($LASTEXITCODE -ne 0) {
      throw "Viewer package $packageName failed with exit code $LASTEXITCODE"
    }
  }
  # Viewer contracts precede legacy same-name desktop units and installed DCPs.
  $unitPaths = @($packageRoot, "$viewerRoot\Core", "$viewerRoot\Core.Protocol") + $unitPaths
}
if ($Target -eq 'ViewerPackages') { return }
$unitPaths += $externalPaths
New-Item -ItemType Directory -Force -Path "$outputRoot\DCU", "$outputRoot\Hpp" | Out-Null
$encodedPaths = $unitPaths -join '%3B'
$arguments = @(
  "`"$project`"", '/t:Build', "/p:MainSource=$sourceName",
  "/p:Config=$Configuration", "/p:Platform=$Platform",
  "`"/p:DelphiLibraryPath=$delphiLibraryPath`"",
  "`"/p:DelphiDebugDCUPath=$delphiDebugDcuPath`"",
  '/p:DCC_TranslatedLibraryPath=', '/p:DCC_TranslatedDebugLibraryPath=',
  '/p:DCC_ResourcePath=', '/p:DCC_TranslatedResourcePath=',
  "`"/p:PluginCorePath=$viewerRoot\Core`"",
  "`"/p:ELN_ExternalUnitPaths=$($externalPaths -join '%3B')`"",
  "`"/p:DCC_UnitSearchPath=$encodedPaths`"",
  "`"/p:DCC_ExeOutput=$outputRoot`"", "`"/p:DCC_DcuOutput=$outputRoot\DCU`"",
  "`"/p:DCC_DcpOutput=$packageRoot`"", "`"/p:DCC_BplOutput=$outputRoot`"",
  "`"/p:DCC_HppOutput=$outputRoot\Hpp`"", "`"/p:DCC_ResourceOutput=$outputRoot`"",
  '/p:DCC_MapFile=3', '/p:PreBuildEvent=', '/p:PostBuildEvent=', '/p:PreLinkEvent=', '/v:normal', '/nologo'
)
if ($Target -in @('DesktopRegressionTests', 'MarkdownLauncherTests')) {
  $arguments += '"/p:DCC_Namespace=Winapi%3BSystem.Win%3BSystem%3BXml%3BData%3BVcl%3BVcl.Imaging%3BVcl.Samples%3BVcl.Shell"'
}
if ($viewerTarget) {
  # upfManager belongs to the externally installed manager package, not Core.
  $packages = @(
    'rtl', 'vcl', 'vcledge', 'TMSVCLPluginFrameworkPkgCoreDXE16',
    'TMSVCLPluginFrameworkPkgMgrDXE16', 'ELNPluginCore', 'ELNProtocolCore',
    'vclimg', 'vclwinx', 'Tee', 'RaizeComponentsVcl'
  ) -join '%3B'
  $arguments += "`"/p:DCC_UsePackage=$packages`""
  $arguments += '/p:UsePackages=true'
}
$buildCommand = "call `"$rsvarsPath`" && `"$msbuildPath`" " + ($arguments -join ' ')
& $shellPath /d /c $buildCommand
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }
if ($desktopTarget) {
  $iconGenerator = Join-Path $sourceRoot 'ELN.Desktop\Assets\DevTools\ToolBars\generate_icon_resources.py'
  & python $iconGenerator --output-dir (Join-Path $outputRoot 'Icons') --dcc32 $dcc32Path
  if ($LASTEXITCODE -ne 0) { throw "Icon resource build failed with exit code $LASTEXITCODE" }
  $catalogSource = Join-Path $sourceRoot 'ELN.Desktop\Assets\Runtime\CSV'
  Copy-Item -LiteralPath $catalogSource -Destination $outputRoot -Recurse -Force
  $helpSource = Join-Path $sourceRoot 'ELN.Desktop\Assets\Runtime\Help'
  Copy-Item -LiteralPath $helpSource -Destination $outputRoot -Recurse -Force
}
if ($RunTests) {
  $executable = Join-Path $outputRoot ([IO.Path]::ChangeExtension($sourceName, '.exe'))
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Expected test executable missing: $executable"
  }
  & $executable
  if ($LASTEXITCODE -ne 0) { throw "Tests failed with exit code $LASTEXITCODE" }
}
