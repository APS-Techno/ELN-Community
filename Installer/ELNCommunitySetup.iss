#ifndef BuildStage
  #error BuildStage must select the validated Community runtime stage.
#endif
#ifndef MyAppVersion
  #error MyAppVersion must come from the built Community executable.
#endif

[Setup]
AppId={{C95824E6-6A8B-4269-B699-D569D1D5F7CB}
AppName=ELN Community
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
AppVerName=ELN Community {#MyAppVersion}
AppPublisher=APS Technology
DefaultDirName={localappdata}\Programs\ELN Community
DefaultGroupName=ELN Community
AllowNoIcons=yes
PrivilegesRequired=lowest
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
LicenseFile=..\LICENSE
SetupIconFile=..\ELN.Desktop\Assets\DevTools\AppIcons\ELN3_icon.ico
UninstallDisplayIcon={app}\ELNCommunity.exe
OutputDir=..\_OUT\Installer\Win64\Release\Output
OutputBaseFilename=ELNCommunitySetup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
CloseApplicationsFilter=*.exe,*.dll,*.bpl
RestartApplications=no
UsePreviousTasks=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "demodata"; Description: "Install demo/reference data"; GroupDescription: "CSV catalogs for new notebooks:"; Flags: unchecked

[Files]
Source: "{#BuildStage}\Program\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildStage}\Catalogs\Full\*.csv"; DestDir: "{app}\CSV"; Tasks: demodata; Flags: ignoreversion
Source: "{#BuildStage}\Catalogs\Empty\*.csv"; DestDir: "{app}\CSV"; Tasks: not demodata; Flags: ignoreversion

[Icons]
Name: "{group}\ELN Community"; Filename: "{app}\ELNCommunity.exe"
Name: "{group}\Uninstall ELN Community"; Filename: "{uninstallexe}"
Name: "{autodesktop}\ELN Community"; Filename: "{app}\ELNCommunity.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ELNCommunity.exe"; Description: "Launch ELN Community"; Flags: nowait postinstall skipifsilent
