unit unit_FilePaths;

interface

function CleanFileName(const Input: string): string;

implementation

uses
  System.IOUtils;

function CleanFileName(const Input: string): string;
var
  I: Integer;
begin
  Result := Input;
  for I := 1 to Length(Result) do
    if not TPath.IsValidFileNameChar(Result[I]) then
      Result[I] := '-';
end;

end.
