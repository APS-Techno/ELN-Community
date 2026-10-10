@{
  RsVarsPath = 'C:\LicensedTools\Delphi\bin\rsvars.bat'
  MSBuildPath = 'C:\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
  ShellPath = 'C:\Windows\System32\cmd.exe'
  Dcc32Path = 'C:\LicensedTools\Delphi\bin\dcc32.exe'
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
