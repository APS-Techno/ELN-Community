unit unit_FileRelocator;

interface

uses
  unit_NotebookStorage;

type
  TNotebookFileRelocator = class(TInterfacedObject, IFileRelocator)
  private
    FStorage: INotebookStorage;
    function StoragePath(const Path: string): string;
  public
    constructor Create(const Storage: INotebookStorage);
    procedure MoveFile(const OldPath, NewPath: string);
  end;

  function BuildItemFileRemotePath(const ProjectFileFolder, ItemFolderName,
    FileFullName: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  unit_FilePaths;

function BuildItemFileRemotePath(const ProjectFileFolder, ItemFolderName,
  FileFullName: string): string;
begin
  Result := Format('files/Projects/%s/%s/%s', [
    CleanFileName(ProjectFileFolder),
    CleanFileName(ItemFolderName),
    FileFullName]);
end;

constructor TNotebookFileRelocator.Create(const Storage: INotebookStorage);
begin
  inherited Create;
  if Storage = nil then
    raise EArgumentException.Create('A notebook storage backend is required');
  FStorage := Storage;
end;

function TNotebookFileRelocator.StoragePath(const Path: string): string;
var
  Normalized: string;
begin
  Normalized := Path.Replace('\', '/');
  if not StartsStr('files/Projects/', Normalized) then
    raise EArgumentException.Create('Expected a virtual attachment path under files/Projects');
  Result := Copy(Normalized, Length('files/') + 1, MaxInt);
end;

procedure TNotebookFileRelocator.MoveFile(const OldPath, NewPath: string);
begin
  FStorage.MoveFile(StoragePath(OldPath), StoragePath(NewPath));
end;

end.
