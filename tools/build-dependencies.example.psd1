# Copy to <product-root>/build-dependencies.local.psd1 (ignored), or pass
# -DependencyConfig <absolute-file-path>. ELN_BUILD_DEPENDENCIES is also supported.
# Replace these example locations with your licensed external installations.
@{
  RsVarsPath = 'C:\LicensedTools\Delphi\bin\rsvars.bat'
  MSBuildPath = 'C:\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
  ShellPath = 'C:\Windows\System32\cmd.exe'
  Dcc32Path = 'C:\LicensedTools\Delphi\bin\dcc32.exe'
  # Products root containing tms.biz.aurelius and tms.biz.bcl.
  TmsRoot = 'C:\LicensedLibraries\TMS\Products'
  # Only external dependencies. Never add another APS source/output checkout.
  # Literal placeholders are expanded by the helper, not by PowerShell.
  ExternalUnitPaths = @(
    'C:\LicensedLibraries\TMSPluginFramework\{Platform}\{Configuration}'
    'C:\LicensedLibraries\KSVC\Lib\RX13\{Platform}'
    'C:\ExternalLibraries\VirtualTreeView\Source'
    'C:\ExternalLibraries\SynEdit\Source'
    'C:\ExternalLibraries\SynEdit\Source\Highlighters'
    'C:\LicensedLibraries\SynEditDR\{Platform}\{Configuration}'
  )
}
# Direct IDE builds use explicit ELN_EXTERNAL_UNIT_PATHS (semicolon-separated
# resolved external paths) and ELN_TMS_ROOT environment variables, then restart
# the IDE. The helper supplies the same paths as MSBuild global properties.
# DUnitX units must be available through Delphi or ExternalUnitPaths.
