unit unit_StorageCheck;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager,
  unit_NotebookStorage,
  unit_Item;

type
  TStorageCheckStatus = (scsOk, scsMissing, scsContentMismatch, scsNoHash,
    scsError);

  TStorageCheckRow = record
    FileId: Int64;
    ItemId: Integer;
    ProjectId: Integer;
    FileName: string;
    RelativePath: string;
    StoredHash: string;
    ActualHash: string;
    Status: TStorageCheckStatus;
    Message: string;
  end;

function StorageCheckStatusCode(Status: TStorageCheckStatus): string;
function TryParseStorageCheckStatus(const Code: string;
  out Status: TStorageCheckStatus): Boolean;

// Reads the stored bytes and compares their MD5 with Files.Hash. Never writes.
function CheckStoredFile(Manager: TObjectManager;
  const Storage: INotebookStorage; F: unit_Item.TFile): TStorageCheckRow;

implementation

uses
  System.IOUtils,
  System.Hash,
  unit_Project,
  unit_FilePaths;

function StorageCheckStatusCode(Status: TStorageCheckStatus): string;
begin
  case Status of
    scsOk: Result := 'ok';
    scsMissing: Result := 'missing';
    scsContentMismatch: Result := 'content_mismatch';
    scsNoHash: Result := 'no_hash';
  else
    Result := 'error';
  end;
end;

function TryParseStorageCheckStatus(const Code: string;
  out Status: TStorageCheckStatus): Boolean;
var
  S: TStorageCheckStatus;
begin
  for S := Low(TStorageCheckStatus) to High(TStorageCheckStatus) do
    if SameText(Code, StorageCheckStatusCode(S)) then
    begin
      Status := S;
      Exit(True);
    end;
  Result := False;
end;

function StoredContentHash(const Storage: INotebookStorage;
  const RelativePath: string): string;
var
  TempDir, TempPath: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath,
    'ELN-StorageCheck-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TempDir);
  try
    TempPath := TPath.Combine(TempDir, 'content.bin');
    Storage.CopyOut(RelativePath, TempPath);
    Result := THashMD5.GetHashStringFromFile(TempPath);
  finally
    TDirectory.Delete(TempDir, True);
  end;
end;

function CheckStoredFile(Manager: TObjectManager;
  const Storage: INotebookStorage; F: unit_Item.TFile): TStorageCheckRow;
var
  Item: TItem;
  Project: TProject;
begin
  Result := Default(TStorageCheckRow);
  Result.FileId := F.Id;
  Result.StoredHash := F.Hash;
  Result.Status := scsError;
  Item := F.Item;
  if Assigned(Item) then
  begin
    Result.ItemId := Item.Id;
    Result.ProjectId := Item.ProjectID;
  end;
  if not Assigned(Item) or not Assigned(F.FileType) then
  begin
    Result.Message := 'The file record has no item or file type';
    Exit;
  end;
  Result.FileName := F.FullName;
  Project := Manager.Find<TProject>(Item.ProjectID);
  if not Assigned(Project) then
  begin
    Result.Message := 'The owning project does not exist';
    Exit;
  end;
  Result.RelativePath := AttachmentRelativePath(Project.FileFolder,
    Item.FolderName, F.FullName);
  try
    if not Storage.Exists(Result.RelativePath) then
    begin
      Result.Status := scsMissing;
      Exit;
    end;
    Result.ActualHash := StoredContentHash(Storage, Result.RelativePath);
  except
    on E: Exception do
    begin
      Result.Message := E.ClassName + ': ' + E.Message;
      Exit;
    end;
  end;
  if Trim(F.Hash) = '' then
    Result.Status := scsNoHash
  else if SameText(Trim(F.Hash), Result.ActualHash) then
    Result.Status := scsOk
  else
    Result.Status := scsContentMismatch;
end;

end.
