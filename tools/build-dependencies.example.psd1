@{
  RsVarsPath = 'C:\LicensedTools\Delphi\bin\rsvars.bat'
  MSBuildPath = 'C:\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
  ShellPath = 'C:\Windows\System32\cmd.exe'
  Dcc32Path = 'C:\LicensedTools\Delphi\bin\dcc32.exe'
  TmsRoot = 'C:\LicensedLibraries\TMS\Products'
  # Only for -Platform Linux64: the Ubuntu 22.04 SDK sysroot made by the IDE SDK Manager.
  LinuxSdkRoot = 'C:\Users\Developer\Documents\Embarcadero\Studio\SDKs\ubuntu22.04.sdk'
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
  # Optional: entries added for one platform only. Linux64 uses only its own list.
  PlatformExternalUnitPaths = @{
    Win32 = @()
    Win64 = @()
    Linux64 = @(
      'C:\LicensedLibraries\TMS\Products\tms.biz.aurelius\source\drivers'
      'C:\LicensedLibraries\TMS\Products\tms.biz.bcl\source\extra'
    )
  }
}
