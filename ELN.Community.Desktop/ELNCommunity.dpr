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
  frm_CommunitySplash in 'frm_CommunitySplash.pas' {frmCommunitySplash},
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
  editor_ReaderValueMappings in '..\ELN.Desktop\Editors\editor_ReaderValueMappings.pas',
  dlg_DerivedValue in '..\ELN.Desktop\Dialogs\Items\dlg_DerivedValue.pas' {dlgDerivedValue},
  editor_LinkTypes in '..\ELN.Desktop\Editors\editor_LinkTypes.pas' {edLinkTypes},
  unit_LocalNotebook in '..\ELN.Community\unit_LocalNotebook.pas',
  unit_LocalNotebookStorage in '..\ELN.Community\unit_LocalNotebookStorage.pas',
  unit_LocalElnFileService in '..\ELN.Community\unit_LocalElnFileService.pas',
  unit_DomainEntities in '..\ELN.Domain\unit_DomainEntities.pas',
  unit_NativeLibrary in '..\ELN.Search\unit_NativeLibrary.pas',
  unit_OnnxRuntimeApi in '..\ELN.Search\unit_OnnxRuntimeApi.pas',
  unit_UnigramTokenizer in '..\ELN.Search\unit_UnigramTokenizer.pas',
  unit_TextEmbedder in '..\ELN.Search\unit_TextEmbedder.pas',
  unit_VectorSearch in '..\ELN.Search\unit_VectorSearch.pas',
  unit_SearchPassages in '..\ELN.Search\unit_SearchPassages.pas',
  unit_PassageContext in '..\ELN.Search\unit_PassageContext.pas',
  unit_SearchDocumentProvider in '..\ELN.Model\unit_SearchDocumentProvider.pas',
  unit_SemanticSearchApi in '..\ELN.Search\unit_SemanticSearchApi.pas',
  unit_SemanticSearchFilter in '..\ELN.Model\unit_SemanticSearchFilter.pas',
  unit_SearchVisibility in '..\ELN.Model\unit_SearchVisibility.pas',
  unit_SearchIndexStore in '..\ELN.Search\unit_SearchIndexStore.pas',
  unit_SearchIndexer in '..\ELN.Search\unit_SearchIndexer.pas',
  unit_HybridSearch in '..\ELN.Search\unit_HybridSearch.pas',
  unit_SearchArtifacts in '..\ELN.Search\unit_SearchArtifacts.pas',
  unit_SearchArtifactInstall in '..\ELN.Search\unit_SearchArtifactInstall.pas',
  unit_TarGz in '..\ELN.Search\unit_TarGz.pas',
  unit_SemanticSearchService in '..\ELN.Search\unit_SemanticSearchService.pas',
  unit_LocalSemanticSearch in '..\ELN.Search\unit_LocalSemanticSearch.pas',
  unit_CrossEncoder in '..\ELN.Search\unit_CrossEncoder.pas',
  unit_MainThreadSearchSource in '..\ELN.Desktop\Units\unit_MainThreadSearchSource.pas',
  unit_PdfiumApi in '..\ELN.Search\unit_PdfiumApi.pas',
  unit_TextExtractors in '..\ELN.Search\unit_TextExtractors.pas',
  unit_MarkupEntities in '..\ELN.Search\unit_MarkupEntities.pas',
  unit_TextStreamDecoder in '..\ELN.Search\unit_TextStreamDecoder.pas',
  unit_XmlTextScanner in '..\ELN.Search\unit_XmlTextScanner.pas',
  unit_OpenXmlPackage in '..\ELN.Search\unit_OpenXmlPackage.pas',
  unit_OfficeTextExtractors in '..\ELN.Search\unit_OfficeTextExtractors.pas',
  unit_MarkupTextExtractors in '..\ELN.Search\unit_MarkupTextExtractors.pas',
  unit_JsonTextExtractor in '..\ELN.Search\unit_JsonTextExtractor.pas',
  unit_RtfTextExtractor in '..\ELN.Search\unit_RtfTextExtractor.pas',
  unit_TextExtractorRegistry in '..\ELN.Search\unit_TextExtractorRegistry.pas',
  unit_FileTextStage in '..\ELN.Search\unit_FileTextStage.pas',
  dlg_SearchSetup in '..\ELN.Desktop\Dialogs\Search\dlg_SearchSetup.pas' {dlgSearchSetup};

{$R *.res}

var
  ConfigPath: string;
  Settings: TNotebookSettings;
  SavedTheme, ThemeName: string;
  I: Integer;
  Splash: TfrmCommunitySplash;
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
  Splash := TfrmCommunitySplash.Display;
  try
    Splash.SetStatus('Loading images');
    Application.CreateForm(TdmTreeImages, dmTreeImages);
    Splash.SetStatus('Building main window');
    Application.CreateForm(TfrmCommunityMain, frmCommunityMain);
    Splash.SetStatus('Loading reference editors');
    Application.CreateForm(TedFileTypes, edFileTypes);
    Application.CreateForm(TedEquipmentTypes, edEquipmentTypes);
    Application.CreateForm(TedEquipment, edEquipment);
    Application.CreateForm(TedActionTypes, edActionTypes);
    Application.CreateForm(TedValueTypes, edValueTypes);
    Application.CreateForm(TedLinkTypes, edLinkTypes);
  except
    FreeAndNil(Splash);
    raise;
  end;
  FreeAndNil(Splash);
  Application.Run;
end.
