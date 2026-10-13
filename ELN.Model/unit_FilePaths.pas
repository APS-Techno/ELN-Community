unit unit_FilePaths;

interface

function CleanFileName(const Input: string): string;
function FileFormatExtension(const FileName, StoredExtension: string): string;
function AttachmentRelativePath(const ProjectFileFolder, ItemFolderName,
  FileFullName: string): string;

implementation

uses
  System.IOUtils, System.StrUtils;

function CleanFileName(const Input: string): string;
var
  I: Integer;
begin
  Result := Input;
  for I := 1 to Length(Result) do
    if not TPath.IsValidFileNameChar(Result[I]) then
      Result[I] := '-';
end;

function FileFormatExtension(const FileName, StoredExtension: string): string;
begin
  if EndsText('.depo.json', FileName) then
    Result := '.depo.json'
  else if EndsText('.process.log', FileName) then
    Result := '.process.log'
  else
    Result := StoredExtension;
end;

function AttachmentRelativePath(const ProjectFileFolder, ItemFolderName,
  FileFullName: string): string;
begin
  Result := 'Projects/' + CleanFileName(ProjectFileFolder) + '/' +
    CleanFileName(ItemFolderName) + '/' + FileFullName;
end;

end.
