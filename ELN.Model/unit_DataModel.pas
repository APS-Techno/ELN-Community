{*
  unit_DataModel.pas — Application-level data model (TDataModel / global Model)

  TDataModel is the single aggregation point for all domain model objects.
  It owns one TObjectManager on an injected connection and creates every
  sub-model with that shared manager so they all participate in the same Aurelius
  unit-of-work session.

  Sub-models owned
  ----------------
    Authors, Projects, Folders, Items, Files,
    ActionTypes, EquipmentTypes, Equipments, FileTypes, ValueTypes, History

  Global singleton
  ----------------
  The `Model: TDataModel` var is created in frm_Main and is accessible from all units
  in the implementation section via `unit_DataModel` in their uses clause.

  User history (LastProject/LastFolder/LastItem/LastChild)
  --------------------------------------------------------
  Thin read/write wrappers over FHistory.UserRecord fields.
  Saved to the database on application exit via SaveUserHistory.

  GetFileName(ID)
  ---------------
  Builds the relative storage path for a file attachment:
    Projects\<Project.FileFolder>\<Item.FolderName>\<FileName>
  Used by BtnAddFileClick to determine where to copy the source file.

*}
unit unit_DataModel;

interface
uses
  System.SysUtils,
  System.Classes,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  unit_AuthorModel,
  unit_ProjectAccessPolicy,
  unit_NotebookStorage,
  unit_Types,
  unit_ProjectModel,
  unit_FolderModel,
  unit_ItemModel,
  unit_Item,
  unit_User,
  unit_ActionTypeModel,
  unit_UserHistoryModel,
  unit_TreeStateModel,
  unit_EquipmentTypeModel,
  unit_EquipmentModel,
  unit_FileTypeModel,
  unit_UsersHistory,
  unit_FileModel,
  unit_ValueTypeModel,
  unit_ProtocolTemplateModel,
  unit_ProtocolStatusModel,
  unit_AuditLogModel,
  unit_AuditLog,
  unit_SignatureModel,
  unit_FavoritesModel,
  unit_ProjectGroupModel,
  unit_TagModel,
  unit_CommentModel,
  unit_ExperimentTemplateModel,
  unit_RecycleBinModel,
  unit_DBSettingsModel,
  unit_SearchModel,
  unit_ItemLinkModel,
  unit_LinkTypeModel,
  unit_ViewerStateModel,
  unit_AuditModel;

type

  TDataModel = class
    private
      FAuthors: TAuthorModel;
      FProjects: TProjectsModel;
      FFolders: TFolderModel;
      FItems: TItemModel;
      FFiles: TFileModel;

      FActionTypes: TActionTypeModel;
      FValueTypes: TValueTypeModel;
      FEquipmentTypes: TEquipmentTypeModel;
      FEquipments : TEquipmentModel;
      FFileTypes: TFileTypeModel;
      FHistory : TUserHistoryModel;
      FTreeState: TTreeStateModel;
      FTemplates: TTemplateModel;
      FProtocolStatus: TProtocolStatusModel;
      FAuditLog: TAuditLogModel;
      FSignatures: TSignatureModel;
      FFavorites: TFavoritesModel;
      FProjectGroups: TProjectGroupModel;
      FTags: TTagModel;
      FComments: TCommentModel;
      FExperimentTemplates: TExperimentTemplateModel;
      FRecycleBin: TRecycleBinModel;
      FDBSettings: TDBSettingsModel;
      FSearch: TSearchModel;
      FItemLinks: TItemLinkModel;
      FLinkTypes: TLinkTypeModel;
      FViewerStates: TViewerStateModel;
      FAuditRules: TAuditModel;

      FUser: TUser;
      FManager: TObjectManager;
      FConnection: IDBConnection;
      FAccess: IProjectAccessPolicy;
      FStorage: INotebookStorage;
      FRelocator: IFileRelocator;

      function getLastFolder: integer;
      function getLastProject: integer;
      function getLastItem: integer;
      function getLastChild: integer;
      procedure SetLastFolder(const Value: integer);
      procedure SetLastProject(const Value: integer);
      procedure SetLastItem(const Value: integer);
      procedure SetLastChild(const Value: integer);
    protected
      function CreateAuthorModel(AUserId: Integer): TAuthorModel; virtual;
      procedure BindPrincipal(AUser: TUser);
    public
      constructor Create(AConnection: IDBConnection; APrincipalId: Integer;
        const AAccess: IProjectAccessPolicy; const AStorage: INotebookStorage);
      destructor Destroy; override;
      procedure ReplaceStorage(const Storage: INotebookStorage);
      property User: TUser read FUser;
      property Authors: TAuthorModel read FAuthors;
      property Access: IProjectAccessPolicy read FAccess;
      property Storage: INotebookStorage read FStorage;
      property Relocator: IFileRelocator read FRelocator;
      property Connection: IDBConnection read FConnection;
      property Projects: TProjectsModel read FProjects;
      property Folders: TFolderModel read FFolders;
      property Items: TItemModel read FItems;
      property FileTypes: TFileTypeModel read FFileTypes;
      property ActionTypes: TActionTypeModel read FActionTypes;
      property EquipmentTypes: TEquipmentTypeModel read FEquipmentTypes;
      property Equipments: TEquipmentModel read FEquipments;
      property History: TUserHistoryModel read FHistory;
      /// Per-user expanded state of the desktop trees; its own manager.
      property TreeState: TTreeStateModel read FTreeState;
      property ValueTypes: TValueTypeModel read FValueTypes;
      property Templates: TTemplateModel read FTemplates;
      property ProtocolStatus: TProtocolStatusModel read FProtocolStatus;
      property AuditLog: TAuditLogModel read FAuditLog;
      property Signatures: TSignatureModel read FSignatures;
      property Favorites: TFavoritesModel read FFavorites;
      property ProjectGroups: TProjectGroupModel read FProjectGroups;
      property Tags: TTagModel read FTags;
      property Comments: TCommentModel read FComments;
      property ExperimentTemplates: TExperimentTemplateModel read FExperimentTemplates;
      property RecycleBin: TRecycleBinModel read FRecycleBin;
      property DBSettings: TDBSettingsModel read FDBSettings;
      property Search: TSearchModel read FSearch;
      property ItemLinks: TItemLinkModel read FItemLinks;
      property LinkTypes: TLinkTypeModel read FLinkTypes;
      property ViewerStates: TViewerStateModel read FViewerStates;
      property AuditRules: TAuditModel read FAuditRules;

      procedure RecordAudit(AEntityType: TAuditEntityType;
        AEntityId: Integer; AOperation: TAuditOperation;
        const ADescription: string);

      property LastProject: integer read getLastProject write SetLastProject;
      property LastFolder: integer read getLastFolder write SetLastFolder;
      property LastItem: integer read getLastItem write SetLastItem;
      property LastChild: integer read getLastChild write SetLastChild;

      property Manager: TObjectManager read FManager;
      procedure SetupDateFormat;
      function GetFileName(const ID: integer): string;
      { GetFilePathDAV — same path as GetFileName but using forward slashes,
        suitable as a relative path appended to a WebDAV base URL.
        Returns e.g. 'files/Projects/JohnSmith/Project1/[0001]Item/[0001]file.pdf' }
      function GetFilePathDAV(const ID: integer): string;
      { GetFileItemId — ID of the item owning the file, 0 when the file
        (or its item) cannot be resolved. }
      function GetFileItemId(const ID: integer): Integer;
  end;

  function CleanFileName(const Input: string): string;

var
  Model: TDataModel;

implementation

uses
  System.IOUtils,
  Aurelius.Sql.SQLite,
  Aurelius.Sql.Register,
  unit_Project,
  unit_ActionType,
  unit_LabEntry,
  unit_Protocol,
  unit_FileType,
  unit_FilePaths,
  unit_FileRelocator,
  unit_AuditHelper;


{Helpers}
// Replace non-valid file name characters with spaces
function CleanFileName(const Input: string): string;
begin
  Result := unit_FilePaths.CleanFileName(Input);
end;


{ TDataModel }

constructor TDataModel.Create(AConnection: IDBConnection; APrincipalId: Integer;
  const AAccess: IProjectAccessPolicy; const AStorage: INotebookStorage);
begin
  inherited Create;
  if (AConnection = nil) or (AAccess = nil) or (AStorage = nil) then
    raise EArgumentException.Create('Notebook connection, access policy and storage are required');
  FConnection := AConnection;
  FAccess := AAccess;
  FStorage := AStorage;
  SetupDateFormat;

  // Reset the mass-teardown latch: a prior session's Destroy sets
  // ManagerShuttingDown := True (to skip per-entity proxy DestroyValue during
  // FManager.Clear) and never clears it. Without this reset the first logout
  // would leave it True for the rest of the process, leaking proxy list values
  // on every ordinary single-entity Evict/Free in later sessions.
  ManagerShuttingDown := False;

  FManager := TObjectManager.Create(FConnection);

  FAuthors := CreateAuthorModel(APrincipalId);
  FProjects := TProjectsModel.Create(FManager, FAccess);
  FFolders := TFolderModel.Create(FManager);
  FItems := TItemModel.Create(FManager);
  FHistory := TUserHistoryModel.Create(FManager);
  // Own manager: a failed tree-state write must never leave FManager dirty.
  FTreeState := TTreeStateModel.Create(TObjectManager.Create(FConnection));
  FActionTypes := TActionTypeModel.Create(FManager);
  FEquipmentTypes := TEquipmentTypeModel.Create(FManager);
  FEquipments := TEquipmentModel.Create(FManager);
  FFileTypes := TFileTypeModel.Create(FManager);
  FFiles := TFileModel.Create(FManager);
  FValueTypes := TValueTypeModel.Create(FManager);
  FTemplates := TTemplateModel.Create(FManager);
  FProtocolStatus := TProtocolStatusModel.Create(FManager, FAccess);
  FAuditLog := TAuditLogModel.Create(FManager);
  FSignatures := TSignatureModel.Create(FManager);
  FFavorites := TFavoritesModel.Create(FManager);
  FProjectGroups := TProjectGroupModel.Create(FManager);
  FTags := TTagModel.Create(FManager);
  FComments := TCommentModel.Create(FManager);
  FExperimentTemplates := TExperimentTemplateModel.Create(FManager, FAccess);
  FRecycleBin := TRecycleBinModel.Create(FManager);
  FDBSettings := TDBSettingsModel.Create(FManager);
  FSearch := TSearchModel.Create(FManager, FAccess);
  FItemLinks := TItemLinkModel.Create(FManager);
  FLinkTypes := TLinkTypeModel.Create(FManager);
  FViewerStates := TViewerStateModel.Create(FManager);
  FAuditRules := TAuditModel.Create(FManager);
  ReplaceStorage(FStorage);
  if APrincipalId > 0 then
    BindPrincipal(FAuthors.CurrentUser);
end;

procedure TDataModel.RecordAudit(AEntityType: TAuditEntityType;
  AEntityId: Integer; AOperation: TAuditOperation;
  const ADescription: string);
begin
  if Assigned(FUser) then
    unit_AuditHelper.RecordAudit(FManager, AEntityType, AEntityId,
      AOperation, FUser.Id, ADescription);
end;

function TDataModel.CreateAuthorModel(AUserId: Integer): TAuthorModel;
begin
  Result := TAuthorModel.Create(FManager, AUserId);
end;

procedure TDataModel.ReplaceStorage(const Storage: INotebookStorage);
var
  Relocator: IFileRelocator;
begin
  Relocator := TNotebookFileRelocator.Create(Storage);
  FStorage := Storage;
  FRelocator := Relocator;
end;

destructor TDataModel.Destroy;
var
  PriorShutdown: Boolean;
begin
  FreeAndNil(FTreeState);
  FreeAndNil(FAuditRules);
  FreeAndNil(FViewerStates);
  FreeAndNil(FLinkTypes);
  FreeAndNil(FItemLinks);
  FreeAndNil(FSearch);
  FreeAndNil(FRecycleBin);
  FreeAndNil(FExperimentTemplates);
  FreeAndNil(FComments);
  FreeAndNil(FTags);
  FreeAndNil(FProjectGroups);
  FreeAndNil(FFavorites);
  FreeAndNil(FSignatures);
  FreeAndNil(FAuditLog);
  FreeAndNil(FProtocolStatus);
  FreeAndNil(FTemplates);
  FreeAndNil(FValueTypes);
  FreeAndNil(FFiles);
  FreeAndNil(FFileTypes);
  FreeAndNil(FEquipments);
  FreeAndNil(FEquipmentTypes);
  FreeAndNil(FActionTypes);
  FreeAndNil(FHistory);
  FreeAndNil(FItems);
  FreeAndNil(FFolders);
  FreeAndNil(FProjects);
  FreeAndNil(FAuthors);
  FreeAndNil(FDBSettings);
  // TObjectManager.Destroy frees FObjects before FOwnership. FOwnership uses
  // doOwnsKeys=True so its Clear/Free frees entity objects. If any entity
  // cleanup accesses the already-freed FObjects, it corrupts the heap and
  // later entity frees crash with EInvalidPointer.
  // Fix: Call Clear first (empties FOwnership while FObjects is still alive),
  // then Destroy runs on empty sets without touching any entities.
  if Assigned(FManager) then
  begin
    PriorShutdown := ManagerShuttingDown;
    ManagerShuttingDown := True;
    try
      try
        FManager.Clear;
      finally
        FreeAndNil(FManager);
      end;
    finally
      ManagerShuttingDown := PriorShutdown;
    end;
  end;
  FRelocator := nil;
  FStorage := nil;
  FAccess := nil;
  FConnection := nil;
  inherited;
end;

function TDataModel.GetFileName(const ID: integer): string;
var
  F: unit_Item.TFile;
  Item: TItem;
  Project: TProject;
begin
  Result := '';
  F := FFiles.GetFile(ID);
  if not Assigned(F) then Exit;

  Item := F.Item;
  if not Assigned(Item) then Exit;

  Project := FProjects.GetProject(Item.ProjectID);
  if not Assigned(Project) then Exit;

  Result := Format('Projects\%s\%s\%s',
    [CleanFileName(Project.FileFolder),
     CleanFileName(Item.FolderName), FFiles.GetFileName(ID)]);
end;

function TDataModel.GetFilePathDAV(const ID: integer): string;
var
  F: unit_Item.TFile;
  Item: TItem;
  Project: TProject;
begin
  Result := '';
  F := FFiles.GetFile(ID);
  if not Assigned(F) then Exit;

  Item := F.Item;
  if not Assigned(Item) then Exit;

  Project := FProjects.GetProject(Item.ProjectID);
  if not Assigned(Project) then Exit;

  Result := Format('files/Projects/%s/%s/%s',
    [CleanFileName(Project.FileFolder),
     CleanFileName(Item.FolderName), FFiles.GetFileName(ID)]);
end;

function TDataModel.GetFileItemId(const ID: integer): Integer;
var
  F: unit_Item.TFile;
begin
  Result := 0;
  F := FFiles.GetFile(ID);
  if Assigned(F) and Assigned(F.Item) then
    Result := F.Item.Id;
end;

function TDataModel.getLastFolder: integer;
begin
  Result := FHistory.UserRecord.LastFolder;
end;

function TDataModel.getLastItem: integer;
begin
  Result := FHistory.UserRecord.LastItem;
end;

function TDataModel.getLastChild: integer;
begin
  Result := FHistory.UserRecord.LastChild;
end;

function TDataModel.getLastProject: integer;
begin
  Result := FHistory.UserRecord.LastProject;
end;

procedure TDataModel.BindPrincipal(AUser: TUser);
begin
  if (AUser = nil) or AUser.IsArchived then
    raise EArgumentException.Create('An active notebook principal is required');
  FUser := AUser;
  FProjects.AssignUser(FUser);
  FSearch.AssignUser(FUser);
  FProjects.OpenDataSet;
  FFolders.OpenDataSet;
  FItems.OpenDataSet;
  FHistory.OpenDataSet;
end;

procedure TDataModel.SetLastFolder(const Value: integer);
begin
  FHistory.UserRecord.LastFolder := Value;
end;

procedure TDataModel.SetLastItem(const Value: integer);
begin
  FHistory.UserRecord.LastItem := Value;
end;

procedure TDataModel.SetLastChild(const Value: integer);
begin
  FHistory.UserRecord.LastChild := Value;
end;

procedure TDataModel.SetLastProject(const Value: integer);
begin
  FHistory.UserRecord.LastProject := Value;
end;

procedure TDataModel.SetupDateFormat;
Var
 SQLiteGenerator: TSQLiteSQLGenerator;
begin
  SQLiteGenerator := TSQLiteSQLGenerator.Create;
  SQLiteGenerator.DateType := TSQLiteDateType.Text;
  TSQLGeneratorRegister.GetInstance.RegisterGenerator(SQLiteGenerator)
end;

end.
