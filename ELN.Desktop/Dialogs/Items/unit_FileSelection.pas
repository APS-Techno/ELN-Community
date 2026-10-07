unit unit_FileSelection;

interface

uses
  unit_FileType;

function ResolveFileType(const APath: string; ATypes: TFileTypes): TFileType;
function CollectRelevantFileTypes(AAllTypes, AActionTypes: TFileTypes): TFileTypes;
function ValidateFileSelection(const APath, AName: string;
  AType: TFileType; out AError: string): Boolean;

implementation

uses
  System.SysUtils, unit_ViewerExtMatch;

function ResolveFileType(const APath: string; ATypes: TFileTypes): TFileType;
var
  FT: TFileType;
  Score, BestScore: Integer;
begin
  Result := nil;
  BestScore := 0;
  if not Assigned(ATypes) then Exit;
  for FT in ATypes do
    if Assigned(FT) then
    begin
      Score := ExtMatchScore(APath, FT.Ext);
      if Score > BestScore then
      begin
        BestScore := Score;
        Result := FT;
      end;
    end;
end;

function CollectRelevantFileTypes(AAllTypes, AActionTypes: TFileTypes): TFileTypes;
const
  GeneralExtensions: array[0..2] of string = ('.opju', '.pdf', '.xlsx');
var
  FT: TFileType;
  Ext: string;
  Source: TFileTypes;
begin
  Result := TFileTypes.Create;
  try
    Source := AActionTypes;
    if not Assigned(Source) or (Source.Count = 0) then
      Source := AAllTypes;
    if Assigned(Source) then
      for FT in Source do
        if Assigned(FT) and not Result.Contains(FT) then
          Result.Add(FT);
    if Assigned(AAllTypes) then
      for Ext in GeneralExtensions do
        for FT in AAllTypes do
          if Assigned(FT) and SameText(FT.Ext, Ext) and
            not Result.Contains(FT) then
            Result.Add(FT);
  except
    Result.Free;
    raise;
  end;
end;

function ValidateFileSelection(const APath, AName: string;
  AType: TFileType; out AError: string): Boolean;
begin
  AError := '';
  if not FileExists(APath) then
    AError := Format('Source file does not exist: %s', [APath])
  else if Trim(AName) = '' then
    AError := Format('Enter a display name for: %s', [APath])
  else if not Assigned(AType) then
    AError := Format('Choose a registered file type for: %s', [APath]);
  Result := AError = '';
end;

end.
