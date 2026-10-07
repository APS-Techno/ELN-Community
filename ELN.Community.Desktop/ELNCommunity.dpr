program ELNCommunity;

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  unit_NotebookSettings in '..\ELN.Desktop\Units\unit_NotebookSettings.pas',
  unit_ELNThemeHelper,
  frm_CommunityMain in 'frm_CommunityMain.pas' {frmCommunityMain},
  frm_LocalProfile in 'frm_LocalProfile.pas' {dlgLocalProfile},
  frm_CommunityPreferences in 'frm_CommunityPreferences.pas' {dlgCommunityPreferences},
  dm_TreeImages in '..\ELN.Desktop\Views\dm_TreeImages.pas' {dmTreeImages: TDataModule},
  frame_ProjectsPanel in '..\ELN.Desktop\Views\frame_ProjectsPanel.pas',
  frame_ItemTree in '..\ELN.Desktop\Views\frame_ItemTree.pas',
  frame_ContentViewer in '..\ELN.Desktop\Views\frame_ContentViewer.pas',
  frame_Dashboard in '..\ELN.Desktop\Views\frame_Dashboard.pas',
  frame_Hypotheses in '..\ELN.Desktop\Views\frame_Hypotheses.pas',
  editor_FileTypes in '..\ELN.Desktop\Editors\editor_FileTypes.pas' {edFileTypes},
  editor_EquipmentTypes in '..\ELN.Desktop\Editors\editor_EquipmentTypes.pas' {edEquipmentTypes},
  editor_Equipment in '..\ELN.Desktop\Editors\editor_Equipment.pas' {edEquipment},
  editor_ActionTypes in '..\ELN.Desktop\Editors\editor_ActionTypes.pas' {edActionTypes},
  editor_ValueTypes in '..\ELN.Desktop\Editors\editor_ValueTypes.pas' {edValueTypes},
  editor_LinkTypes in '..\ELN.Desktop\Editors\editor_LinkTypes.pas' {edLinkTypes},
  unit_LocalNotebook in '..\ELN.Community\unit_LocalNotebook.pas',
  unit_LocalNotebookStorage in '..\ELN.Community\unit_LocalNotebookStorage.pas',
  unit_LocalElnFileService in '..\ELN.Community\unit_LocalElnFileService.pas',
  unit_DomainEntities in '..\ELN.Domain\unit_DomainEntities.pas';

{$R '..\ELN.Desktop\ELabNotebook3.res'}

var
  ConfigPath: string;
  Settings: TNotebookSettings;
  SavedTheme, ThemeName: string;
  I: Integer;
begin
  // Install the isolated preference location BEFORE streaming any scientific
  // frame; several frames read UI preferences in their constructors.
  ConfigPath := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
    'ELN Community\desktop.ini');
  for I := 1 to ParamCount do
    if ParamStr(I) = '--config' then
    begin
      if I = ParamCount then raise EArgumentException.Create('Missing --config value');
      ConfigPath := TPath.GetFullPath(ParamStr(I + 1));
    end;
  ForceDirectories(ExtractFilePath(ConfigPath));
  TNotebookSettings.SetConfigFile(ConfigPath);
  Settings := TNotebookSettings.Create(ConfigPath);
  try
    SavedTheme := Settings.VCLTheme;
    for ThemeName in TStyleManager.StyleNames do
      if SameText(ThemeName, SavedTheme) then
      begin
        TStyleManager.TrySetStyle(ThemeName);
        Break;
      end;
  finally
    Settings.Free;
  end;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'ELN Community';
  Application.CreateForm(TdmTreeImages, dmTreeImages);
  Application.CreateForm(TfrmCommunityMain, frmCommunityMain);
  Application.CreateForm(TedFileTypes, edFileTypes);
  Application.CreateForm(TedEquipmentTypes, edEquipmentTypes);
  Application.CreateForm(TedEquipment, edEquipment);
  Application.CreateForm(TedActionTypes, edActionTypes);
  Application.CreateForm(TedValueTypes, edValueTypes);
  Application.CreateForm(TedLinkTypes, edLinkTypes);
  Application.Run;
end.
