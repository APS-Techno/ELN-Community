unit test_MarkdownLauncherRegressions;

interface

uses
  DUnitX.TestFramework, Winapi.Windows,
  unit_ELNPluginCore, unit_MarkdownEditorPlugin;

type
  [TestFixture]
  TMarkdownLauncherRegressions = class
  private
    FRoot, FRegistryPath: string;
    FRegistryKey: HKEY;
    FRegistryRedirected: Boolean;
    FPreviousService: IElnFileService;
    FServiceCaptured: Boolean;
    FLauncher: TMarkdownEditorLauncher;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure HostedPreviewOpensCompleteFileAndReusesDraft;
    [Test] procedure PrepareFailureDoesNotPublishAnEditor;
    [Test] procedure StandalonePathDoesNotRequireHostService;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, Vcl.Forms,
  form_MarkdownEditorWindow;

const
  TestFileId: Int64 = 4294967401;

type
  TCompleteFileService = class(TInterfacedObject, IElnFileService)
  public
    WorkingPath: string;
    PrepareCalls: Integer;
    RejectPrepare: Boolean;
    function PrepareLocalFile(FileId: Int64): string;
    function SaveLocalFile(FileId: Int64; const LocalPath: string;
      out ErrorMsg: string): TSaveResult;
    function SaveLocalFileForce(FileId: Int64; const LocalPath: string;
      out ErrorMsg: string): TSaveResult;
    function ReloadLocalFile(FileId: Int64; const LocalPath: string;
      out ErrorMsg: string): Boolean;
    function UploadAttachment(ItemId: Integer;
      const LocalPath, SuggestedName: string): string;
  end;

function TCompleteFileService.PrepareLocalFile(FileId: Int64): string;
begin
  if FileId <> TestFileId then raise Exception.Create('Unexpected file identity');
  Inc(PrepareCalls);
  if RejectPrepare then raise Exception.Create('Synthetic preparation failure');
  Result := WorkingPath;
end;

function TCompleteFileService.SaveLocalFile(FileId: Int64;
  const LocalPath: string; out ErrorMsg: string): TSaveResult;
begin
  raise Exception.Create('The launch regression must not save');
end;

function TCompleteFileService.SaveLocalFileForce(FileId: Int64;
  const LocalPath: string; out ErrorMsg: string): TSaveResult;
begin
  raise Exception.Create('The launch regression must not force-save');
end;

function TCompleteFileService.ReloadLocalFile(FileId: Int64;
  const LocalPath: string; out ErrorMsg: string): Boolean;
begin
  raise Exception.Create('The launch regression must not reload');
end;

function TCompleteFileService.UploadAttachment(ItemId: Integer;
  const LocalPath, SuggestedName: string): string;
begin
  raise Exception.Create('The launch regression must not upload');
end;

function FindEditor(FileId: Int64; const LocalPath: string;
  out Count: Integer): TformMarkdownEditor;
var
  I: Integer;
  Editor: TformMarkdownEditor;
begin
  Result := nil;
  Count := 0;
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I] is TformMarkdownEditor then
    begin
      Editor := TformMarkdownEditor(Screen.Forms[I]);
      if (Editor.FileId = FileId) and
        ((FileId <> 0) or (Editor.LocalPath = LocalPath)) then
      begin
        Inc(Count);
        Result := Editor;
      end;
    end;
end;

procedure TMarkdownLauncherRegressions.Setup;
var
  Id: TGUID;
  Disposition: DWORD;
begin
  FPreviousService := ElnFileService;
  FServiceCaptured := True;
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'MarkdownLauncher-' + GUIDToString(Id));
  FRegistryPath := 'Software\MarkdownLauncherTest-' + GUIDToString(Id);
  TDirectory.CreateDirectory(FRoot);
  try
    // Run this fixture in a serial, otherwise idle VCL process. No real user
    // plugin settings are read, exported, replaced or restored from a copy.
    Win32Check(RegCreateKeyExW(HKEY_CURRENT_USER, PWideChar(FRegistryPath),
      0, nil, REG_OPTION_VOLATILE, KEY_ALL_ACCESS, nil,
      FRegistryKey, @Disposition) = ERROR_SUCCESS);
    Win32Check(RegOverridePredefKey(HKEY_CURRENT_USER, FRegistryKey) = ERROR_SUCCESS);
    FRegistryRedirected := True;
    FLauncher := TMarkdownEditorLauncher.Create;
  except
    TearDown;
    raise;
  end;
end;

procedure TMarkdownLauncherRegressions.TearDown;
var
  I: Integer;
  Editor: TformMarkdownEditor;
begin
  try
    for I := Screen.FormCount - 1 downto 0 do
      if Screen.Forms[I] is TformMarkdownEditor then
      begin
        Editor := TformMarkdownEditor(Screen.Forms[I]);
        if Editor.LocalPath.StartsWith(IncludeTrailingPathDelimiter(FRoot)) then
        begin
          // Free directly: cleanup must not prompt, save a draft, or leave a
          // delayed caFree message holding the launcher's event method.
          Editor.OnClose := nil;
          Editor.OnCloseQuery := nil;
          Editor.Free;
        end;
      end;
  finally
    try
      FreeAndNil(FLauncher);
      if FServiceCaptured then
      begin
        ElnFileService := FPreviousService;
        FPreviousService := nil;
        FServiceCaptured := False;
      end;
    finally
      // Restore the predefined key BEFORE addressing or deleting our own key.
      if FRegistryRedirected then
      begin
        Win32Check(RegOverridePredefKey(HKEY_CURRENT_USER, 0) = ERROR_SUCCESS);
        FRegistryRedirected := False;
      end;
      if FRegistryKey <> 0 then
      begin
        RegCloseKey(FRegistryKey);
        FRegistryKey := 0;
        RegDeleteKeyW(HKEY_CURRENT_USER, PWideChar(FRegistryPath));
      end;
      if (FRoot <> '') and TDirectory.Exists(FRoot) then
        TDirectory.Delete(FRoot, True);
    end;
  end;
end;

procedure TMarkdownLauncherRegressions.HostedPreviewOpensCompleteFileAndReusesDraft;
var
  Service: TCompleteFileService;
  PreviewA, PreviewB: string;
  Editor, Reused: TformMarkdownEditor;
  Count: Integer;
begin
  Service := TCompleteFileService.Create;
  ElnFileService := Service;
  Service.WorkingPath := TPath.Combine(FRoot, 'working.md');
  PreviewA := TPath.Combine(FRoot, 'preview-A.md');
  PreviewB := TPath.Combine(FRoot, 'preview-B.md');
  TFile.WriteAllText(Service.WorkingPath, 'complete body'#13#10'complete tail');
  TFile.WriteAllText(PreviewA, 'partial preview A');
  TFile.WriteAllText(PreviewB, 'partial preview B');
  FLauncher.LaunchEditor(PreviewA, 10, TestFileId, nil);
  Editor := FindEditor(TestFileId, '', Count);
  Assert.AreEqual(1, Count);
  Assert.AreEqual(Service.WorkingPath, Editor.LocalPath);
  Assert.AreEqual('complete body'#13#10'complete tail', TrimRight(Editor.edSrc.Text));
  Editor.edSrc.Text := 'unsaved draft';
  Editor.edSrc.Modified := True;
  FLauncher.LaunchEditor(PreviewB, 10, TestFileId, nil);
  Reused := FindEditor(TestFileId, '', Count);
  Assert.AreEqual(1, Count);
  Assert.IsTrue(Editor = Reused);
  Assert.AreEqual('unsaved draft', TrimRight(Reused.edSrc.Text));
  Assert.IsTrue(Reused.edSrc.Modified);
  Assert.AreEqual(1, Service.PrepareCalls,
    'Reopening a hosted editor must not refresh its open-time baseline.');
end;

procedure TMarkdownLauncherRegressions.PrepareFailureDoesNotPublishAnEditor;
var
  Service: TCompleteFileService;
  Count: Integer;
  Editor: TformMarkdownEditor;
begin
  Service := TCompleteFileService.Create;
  ElnFileService := Service;
  Service.WorkingPath := TPath.Combine(FRoot, 'working.md');
  TFile.WriteAllText(Service.WorkingPath, 'complete');
  Service.RejectPrepare := True;
  Assert.WillRaise(procedure begin
    FLauncher.LaunchEditor(TPath.Combine(FRoot, 'preview.md'), 10, TestFileId, nil);
  end, Exception);
  Editor := FindEditor(TestFileId, '', Count);
  Assert.IsNull(Editor);
  Assert.AreEqual(0, Count);
  Service.RejectPrepare := False;
  FLauncher.LaunchEditor(TPath.Combine(FRoot, 'preview.md'), 10, TestFileId, nil);
  Editor := FindEditor(TestFileId, '', Count);
  Assert.AreEqual(1, Count);
  Assert.AreEqual('complete', TrimRight(Editor.edSrc.Text));
end;

procedure TMarkdownLauncherRegressions.StandalonePathDoesNotRequireHostService;
var
  Path: string;
  Editor: TformMarkdownEditor;
  Count: Integer;
begin
  ElnFileService := nil;
  Path := TPath.Combine(FRoot, 'standalone.md');
  TFile.WriteAllText(Path, 'standalone body');
  FLauncher.LaunchEditor(Path, 0, 0, nil);
  FLauncher.LaunchEditor(Path, 0, 0, nil);
  Editor := FindEditor(0, Path, Count);
  Assert.AreEqual(1, Count);
  Assert.AreEqual(Path, Editor.LocalPath);
  Assert.AreEqual('standalone body', TrimRight(Editor.edSrc.Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TMarkdownLauncherRegressions);
end.
