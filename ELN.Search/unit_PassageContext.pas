unit unit_PassageContext;

interface

uses
  System.SysUtils, unit_SearchPassages;

type
  TPassageContextMode = (pcmNone, pcmItem, pcmFull);

  TPassageContextParts = record
    ProjectTitle: string;
    FolderPath: TArray<string>;
    ItemTitle, ItemKind, ParentTitle, ActionType: string;
  end;

const
  PassageContextPartChars = 80;
  PassageContextTotalChars = 240;
  DefaultPassageContextMode = pcmNone;

function BuildPassageContext(const Parts: TPassageContextParts; Field: TPassageField): string;
function PassageContextFor(Mode: TPassageContextMode; const Parts: TPassageContextParts;
  Field: TPassageField): string;
function PassageContextPartsToJson(const Parts: TPassageContextParts): string;
function TryParsePassageContextParts(const Json: string; out Parts: TPassageContextParts): Boolean;

implementation

uses
  System.Character, System.JSON, System.Generics.Collections;

function CutPart(const Value: string; MaxChars: Integer): string;
var
  I, Count: Integer;
  Blank: Boolean;
begin
  SetLength(Result, Length(Value));
  Count := 0;
  Blank := True;
  for I := 1 to Length(Value) do
    if (Value[I] = ' ') or (Value[I] = #9) or (Value[I] = #10) or (Value[I] = #13) then
    begin
      if not Blank then
      begin
        Inc(Count);
        Result[Count] := ' ';
      end;
      Blank := True;
    end
    else
    begin
      Inc(Count);
      Result[Count] := Value[I];
      Blank := False;
    end;
  SetLength(Result, Count);
  Result := Result.TrimRight;
  if Length(Result) > MaxChars then
  begin
    if Result[MaxChars].IsHighSurrogate then Dec(MaxChars);
    Result := Copy(Result, 1, MaxChars).TrimRight;
  end;
end;

procedure Join(var Target: string; const Part, Separator: string);
begin
  if Part = '' then Exit;
  if Target <> '' then Target := Target + Separator;
  Target := Target + Part;
end;

function BuildPassageContext(const Parts: TPassageContextParts; Field: TPassageField): string;
var
  Path, Segment, Folder: string;
begin
  Path := CutPart(Parts.ProjectTitle, PassageContextPartChars);
  for Folder in Parts.FolderPath do
    Join(Path, CutPart(Folder, PassageContextPartChars), ' > ');
  Result := '';
  Join(Result, Path, ' | ');
  if Field <> pfItemTitle then
  begin
    Segment := CutPart(Parts.ItemTitle, PassageContextPartChars);
    if Segment <> '' then Join(Result, 'Item: ' + Segment, ' | ');
  end;
  Join(Result, CutPart(Parts.ItemKind, PassageContextPartChars), ' | ');
  Join(Result, CutPart(Parts.ActionType, PassageContextPartChars), ' | ');
  Segment := CutPart(Parts.ParentTitle, PassageContextPartChars);
  if Segment <> '' then Join(Result, 'Parent: ' + Segment, ' | ');
  Result := CutPart(Result, PassageContextTotalChars);
end;

function PassageContextFor(Mode: TPassageContextMode; const Parts: TPassageContextParts;
  Field: TPassageField): string;
var
  Reduced: TPassageContextParts;
begin
  case Mode of
    pcmItem:
      begin
        Reduced := Default(TPassageContextParts);
        Reduced.ProjectTitle := Parts.ProjectTitle;
        Reduced.ItemTitle := Parts.ItemTitle;
        Result := BuildPassageContext(Reduced, Field);
      end;
    pcmFull:
      Result := BuildPassageContext(Parts, Field);
  else
    Result := '';
  end;
end;

function PassageContextPartsToJson(const Parts: TPassageContextParts): string;
var
  Obj: TJSONObject;
  Folders: TJSONArray;
  Folder: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('project', Parts.ProjectTitle);
    Folders := TJSONArray.Create;
    Obj.AddPair('folders', Folders);
    for Folder in Parts.FolderPath do
      Folders.Add(Folder);
    Obj.AddPair('title', Parts.ItemTitle);
    Obj.AddPair('kind', Parts.ItemKind);
    Obj.AddPair('parent', Parts.ParentTitle);
    Obj.AddPair('action', Parts.ActionType);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TryParsePassageContextParts(const Json: string; out Parts: TPassageContextParts): Boolean;
var
  Value: TJSONValue;
  Obj: TJSONObject;
  Folders: TJSONArray;
  I: Integer;
begin
  Parts := Default(TPassageContextParts);
  Result := False;
  if Json = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(Json);
  if Value = nil then
    Exit;
  try
    if not (Value is TJSONObject) then
      Exit;
    Obj := TJSONObject(Value);
    Obj.TryGetValue<string>('project', Parts.ProjectTitle);
    Obj.TryGetValue<string>('title', Parts.ItemTitle);
    Obj.TryGetValue<string>('kind', Parts.ItemKind);
    Obj.TryGetValue<string>('parent', Parts.ParentTitle);
    Obj.TryGetValue<string>('action', Parts.ActionType);
    if Obj.TryGetValue<TJSONArray>('folders', Folders) then
      for I := 0 to Folders.Count - 1 do
        Parts.FolderPath := Parts.FolderPath + [Folders.Items[I].Value];
    Result := True;
  finally
    Value.Free;
  end;
end;

end.
