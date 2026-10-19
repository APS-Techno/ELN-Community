unit test_FileIdentity;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFileIdentityTests = class
  public
    [Test] procedure FileTokensKeepEveryDigit;
    [Test] procedure MessageHalvesRoundTripWithoutPointers;
    [Test] procedure PersistedLookupPathAndViewerStateKeepInt64;
    [Test] procedure ToolParametersKeepInt64;
    [Test] procedure AttachmentTitleDropsTheWholeTypeExtension;
    [Test] procedure ReplacementKeepsACompoundTypeAndItsName;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON,
  Winapi.Windows,
  Aurelius.Drivers.Interfaces, Aurelius.Engine.ObjectManager,
  unit_LocalNotebook, unit_ProjectModel, unit_ItemModel,
  unit_FileModel, unit_ViewerStateModel, unit_ViewerState, unit_UsersHistory,
  unit_Project, unit_Item, unit_ItemTypes, unit_FileType,
  unit_FileLocator, unit_PreviewMessages, unit_TimeHelper, unit_FilePaths,
  unit_LocalElnFileService, unit_ToolsWrite, unit_AuditLog, unit_AuditHelper,
  unit_MCPTools, unit_ToolDownloads, unit_User, unit_ELNPluginCore,
  unit_FileSelection;

procedure TFileIdentityTests.FileTokensKeepEveryDigit;
begin
  Assert.AreEqual('[2147483648]', FileNameToken(Int64(2147483648)));
  Assert.AreEqual('[9007199254740993]', FileNameToken(Int64(9007199254740993)));
end;

procedure TFileIdentityTests.AttachmentTitleDropsTheWholeTypeExtension;
begin
  Assert.AreEqual('Deposition_2026-10-14_11-56-09', AttachmentTitle(
    'h:\Runs\Deposition_2026-10-14_11-56-09.depo.json', '.depo.json'));
  Assert.AreEqual('run', AttachmentTitle('RUN.DEPO.JSON', '.depo.json').ToLower);
  Assert.AreEqual('events', AttachmentTitle('events.process.log', '.process.log'));
  Assert.AreEqual('run.depo', AttachmentTitle('run.depo.json', '.json'));
  Assert.AreEqual('notes', AttachmentTitle('notes.txt', '.json'));
  Assert.AreEqual('notes', AttachmentTitle('notes.txt', ''));
end;

procedure TFileIdentityTests.ReplacementKeepsACompoundTypeAndItsName;
var
  Types: TFileTypes;
  Json, Depo, Tsv: TFileType;
begin
  Types := TFileTypes.Create;
  Json := TFileType.Create;
  Depo := TFileType.Create;
  Tsv := TFileType.Create;
  try
    Json.Ext := '.json';
    Depo.Ext := '.depo.json';
    Tsv.Ext := '.tsv';
    Types.AddRange([Json, Depo, Tsv]);
    Assert.AreSame(Depo, ResolveReplacementFileType('new.DEPO.JSON', Depo, Types));
    Assert.AreSame(Json, ResolveReplacementFileType('new.depo.json', Json, Types));
    Assert.AreSame(Depo, ResolveReplacementFileType('new.depo.json', Tsv, Types));
    Assert.AreSame(Json, ResolveReplacementFileType('settings.json', Depo, Types));
    Assert.IsNull(ResolveReplacementFileType('photo.png', Depo, Types));
  finally
    Types.Free;
    Tsv.Free;
    Depo.Free;
    Json.Free;
  end;
end;

procedure TFileIdentityTests.MessageHalvesRoundTripWithoutPointers;
const
  Ids: array[0..4] of Int64 = (0, 2147483648, 4294967295,
    9007199254740993, 9223372036854775807);
var
  Id: Int64;
  LowHalf: WPARAM;
  HighHalf: LPARAM;
begin
  for Id in Ids do
  begin
    EncodeFileIdMessage(Id, LowHalf, HighHalf);
    Assert.AreEqual(Id, DecodeFileIdMessage(LowHalf, HighHalf));
  end;
end;

procedure TFileIdentityTests.ToolParametersKeepInt64;
var
  Params: TJSONObject;
  Id: Int64;
begin
  Params := TJSONObject.ParseJSONValue(
    '{"file_id":9007199254740993,"other_file_id":2147483648}') as TJSONObject;
  try
    Assert.AreEqual(Int64(9007199254740993), GetReqInt64(Params, 'file_id'));
    Assert.IsTrue(GetOptInt64(Params, 'other_file_id', Id));
    Assert.AreEqual(Int64(2147483648), Id);
  finally
    Params.Free;
  end;
end;

procedure TFileIdentityTests.PersistedLookupPathAndViewerStateKeepInt64;
const
  Ids: array[0..1] of Int64 = (2147483648, 9007199254740993);
var
  Root: string;
  Guid: TGUID;
  Notebook: TLocalNotebook;
  Projects: TProjectsModel;
  Items: TItemModel;
  Project: TProject;
  History: TUsersHistory;
  HistoryId: Integer;
  Service: IElnFileService;
  StoragePath, WorkingPath: string;
  Item: TItem;
  FileType: TFileType;
  FileRow: unit_Item.TFile;
  Manager: TObjectManager;
  Files: TFileModel;
  States: TViewerStateModel;
  Statement: IDBStatement;
  Rows: IDBResultSet;
  StoredId: Int64;
  Id: Int64;
  OriginalId: Int64;
  UserId: Integer;
  Context: TToolContext;
  Registry: TToolRegistry;
  Params, Response: TJSONObject;
  DownloadPath: string;
  RenamedStoragePath, RenameTitle: string;
  Step: Integer;
begin
  CreateGUID(Guid);
  Root := TPath.Combine(TPath.GetTempPath, 'ELN-FileIdentity-' + GUIDToString(Guid));
  Notebook := nil;
  try
    Notebook := TLocalNotebook.CreateNew(TPath.Combine(Root, 'notebook.sqlite'),
      TPath.Combine(Root, 'files'), 'Synthetic', 'Identity', 'fixture-password');
    UserId := Notebook.Principal.Id;
    Projects := TProjectsModel.Create(Notebook.Manager, Notebook.AccessPolicy);
    try
      Projects.AssignUser(Notebook.Principal);
      Project := Projects.AddProject('Identity fixture', '', Notebook.Principal);
    finally
      Projects.Free;
    end;
    Items := TItemModel.Create(Notebook.Manager);
    try
      Items.AssignProject(Project.Id, 0);
      Item := Items.AddItem(TItemType.Other, 'Synthetic item');
      FileType := TFileType.Create;
      FileType.Ext := '.txt';
      FileType.CreatedDate := UTCNow;
      FileType.CreatedBy := UserId;
      Notebook.Manager.Save(FileType);
      Notebook.Manager.Flush;
      FileRow := Items.AddFile(FileType, 'identity', UserId, Item);
      OriginalId := FileRow.Id;
    finally
      Items.Free;
    end;
    for Id in Ids do
    begin
      Statement := Notebook.Connection.CreateStatement;
      Statement.SetSQLCommand('UPDATE Files SET Id = ' + IntToStr(Id) +
        ' WHERE Id = ' + IntToStr(OriginalId));
      Statement.Execute;
      Statement := nil;
      OriginalId := Id;
      Manager := TObjectManager.Create(Notebook.Connection);
      try
        Files := TFileModel.Create(Manager);
        try
          FileRow := Files.GetFile(Id);
          Assert.IsNotNull(FileRow);
          Assert.AreEqual(Id, FileRow.Id);
          Assert.AreEqual(FileNameToken(Id) + 'identity.txt', Files.GetFileName(Id));
        finally
          Files.Free;
        end;
        StoragePath := Format('Projects\%s\%s\%s',
          [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName),
           FileRow.FullName]);
        Notebook.Storage.WriteBytes(StoragePath, TEncoding.UTF8.GetBytes('exact identity'));
        Service := TLocalElnFileService.Create(Manager, UserId,
          Notebook.AccessPolicy, Notebook.Storage, TPath.Combine(Root, 'files'),
          TPath.Combine(Root, 'working'));
        try
          WorkingPath := Service.PrepareLocalFile(Id);
          Assert.AreEqual('exact identity', System.IOUtils.TFile.ReadAllText(WorkingPath));
        finally
          Service := nil;
        end;
        Context := Default(TToolContext);
        Context.Manager := Manager;
        Context.User := Manager.Find<TUser>(UserId);
        Context.AccessPolicy := Notebook.AccessPolicy;
        Context.Storage := Notebook.Storage;
        Context.ScopedProjects := [Project.Id];
        Registry := TToolRegistry.Create(Context);
        try
          RegisterWriteTools(Registry);
          RenamedStoragePath := Format('Projects\%s\%s\%s',
            [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName),
             FileNameToken(Id) + 'identity-renamed.txt']);
          for Step := 0 to 1 do
          begin
            if Step = 0 then
              RenameTitle := 'identity-renamed'
            else
              RenameTitle := 'identity';
            Params := TJSONObject.ParseJSONValue('{"file_id":' + IntToStr(Id) +
              ',"new_title":"' + RenameTitle + '"}') as TJSONObject;
            try
              Response := Registry.Execute('rename_file', Params);
              try
                Assert.AreEqual(Id, Response.GetValue<Int64>('id'));
              finally
                Response.Free;
              end;
            finally
              Params.Free;
            end;
            if Step = 0 then
            begin
              Assert.IsFalse(Notebook.Storage.Exists(StoragePath),
                'Old storage path must be absent after rename');
              Assert.IsTrue(Notebook.Storage.Exists(RenamedStoragePath),
                'Renamed storage path must exist');
              Assert.AreEqual('exact identity', TEncoding.UTF8.GetString(
                Notebook.Storage.ReadBytes(RenamedStoragePath)));
            end
            else
            begin
              Assert.IsTrue(Notebook.Storage.Exists(StoragePath),
                'Original storage path must exist after renaming back');
              Assert.IsFalse(Notebook.Storage.Exists(RenamedStoragePath),
                'Renamed storage path must be absent after renaming back');
              Assert.AreEqual('exact identity', TEncoding.UTF8.GetString(
                Notebook.Storage.ReadBytes(StoragePath)));
            end;
          end;
        finally
          Registry.Free;
        end;
        DownloadPath := DownloadFileToLocal(Context, Id);
        try
          Assert.AreEqual('exact identity', System.IOUtils.TFile.ReadAllText(DownloadPath));
        finally
          DeleteLocalDownload(DownloadPath);
        end;
        History := TUsersHistory.Create;
        History.UserID := UserId;
        History.LastProject := 0;
        History.LastFolder := 0;
        History.LastItem := 0;
        History.LastChild := Id;
        Manager.Save(History);
        Manager.Flush;
        HistoryId := History.Id;
        States := TViewerStateModel.Create(Manager);
        try
          States.SaveOrUpdate(UserId, Id, 'fixture-viewer', '{"page":7}');
        finally
          States.Free;
        end;
        RecordAudit(Manager, aetFile, Id, aoUpdate, UserId, 'Synthetic identity audit');
      finally
        Manager.Free;
      end;
      Manager := TObjectManager.Create(Notebook.Connection);
      try
        Assert.AreEqual(Id, Manager.Find<TUsersHistory>(HistoryId).LastChild);
        Statement := Notebook.Connection.CreateStatement;
        Statement.SetSQLCommand('SELECT EntityId FROM AuditLog WHERE EntityId = ' +
          IntToStr(Id));
        Rows := Statement.ExecuteQuery;
        Assert.IsTrue(Rows.Next);
        StoredId := Rows.GetFieldValue(0);
        Assert.AreEqual(Id, StoredId);
        Rows := nil;
        Statement := nil;
        States := TViewerStateModel.Create(Manager);
        try
          Assert.IsNotNull(States.GetState(UserId, Id));
          Assert.AreEqual(Id, States.GetState(UserId, Id).FileId);
          Assert.AreEqual('{"page":7}', States.GetState(UserId, Id).StateData);
          States.DeleteForFile(Id);
          Assert.IsNull(States.GetState(UserId, Id));
        finally
          States.Free;
        end;
      finally
        Manager.Free;
      end;
    end;
  finally
    Rows := nil;
    Statement := nil;
    Notebook.Free;
    if TDirectory.Exists(Root) then TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFileIdentityTests);

end.
