unit unit_ToolDownloads;

interface

uses
  unit_MCPTools;

// The caller must apply RequireFileRead before downloading. The returned path
// is owned by the caller and must be passed to DeleteLocalDownload in finally.
// Each download has its own directory and keeps the stored name, including
// compound extensions used to select scientific viewer plugins.
function DownloadFileToLocal(const Context: TToolContext;
  FileId: Integer): string;
// Use only with paths returned by DownloadFileToLocal. This removes the owned
// directory and any files created there by the plugin.
procedure DeleteLocalDownload(const LocalPath: string);

implementation

uses
  System.SysUtils, System.IOUtils,
  Aurelius.Engine.ObjectManager,
  unit_Item, unit_Project, unit_FilePaths;

procedure DeleteLocalDownload(const LocalPath: string);
begin
  if LocalPath = '' then Exit;
  try
    if TDirectory.Exists(ExtractFileDir(LocalPath)) then
      TDirectory.Delete(ExtractFileDir(LocalPath), True);
  except
    on E: Exception do
      raise Exception.CreateFmt(
        'Could not remove temporary download "%s": %s: %s',
        [LocalPath, E.ClassName, E.Message]);
  end;
end;

function DownloadFileToLocal(const Context: TToolContext;
  FileId: Integer): string;
var
  F: unit_Item.TFile;
  Item: TItem;
  Project: TProject;
  RelativePath, TempDir: string;
  Id: TGUID;
  Stored: Boolean;
begin
  F := Context.Manager.Find<unit_Item.TFile>(FileId);
  if not Assigned(F) then
    raise Exception.CreateFmt('File not found: %d', [FileId]);
  Item := F.Item;
  if Assigned(Item) then
    Project := Context.Manager.Find<TProject>(Item.ProjectID)
  else
    Project := nil;
  if not Assigned(Project) or not Assigned(F.FileType) then
    raise Exception.CreateFmt(
      'File path could not be resolved for file %d', [FileId]);

  RelativePath := Format('Projects/%s/%s/%s',
    [CleanFileName(Project.FileFolder), CleanFileName(Item.FolderName),
     F.FullName]);
  if Context.Storage = nil then
    raise Exception.Create('Notebook storage is not configured');

  try
    Stored := Context.Storage.Exists(RelativePath);
  except
    on E: Exception do
      raise Exception.CreateFmt(
        'Could not read notebook storage for file %d. Path: %s. %s: %s',
        [FileId, RelativePath, E.ClassName, E.Message]);
  end;
  if not Stored then
    raise Exception.CreateFmt(
      'File %d not found in notebook storage. The database has a file ' +
      'record but nothing is stored at %s - it was likely never uploaded ' +
      'or has been removed.', [FileId, RelativePath]);

  CreateGUID(Id);
  TempDir := TPath.Combine(TPath.GetTempPath, 'ELN-MCP-' + GUIDToString(Id));
  Result := TPath.Combine(TempDir, F.FullName);
  try
    TDirectory.CreateDirectory(TempDir);
    // CopyOut lets the backend stream binary data directly to disk.
    Context.Storage.CopyOut(RelativePath, Result);
  except
    on E: Exception do
    begin
      try
        DeleteLocalDownload(Result);
      except
        on CleanupError: Exception do
          raise Exception.CreateFmt(
            'Failed to download file %d from notebook storage. Path: %s. ' +
            '%s: %s. Temporary file cleanup failed: %s',
            [FileId, RelativePath, E.ClassName, E.Message,
             CleanupError.Message]);
      end;
      raise Exception.CreateFmt(
        'Failed to download file %d from notebook storage. Path: %s. %s: %s',
        [FileId, RelativePath, E.ClassName, E.Message]);
    end;
  end;
end;

end.
