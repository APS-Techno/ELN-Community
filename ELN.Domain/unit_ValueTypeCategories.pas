unit unit_ValueTypeCategories;

interface

uses
  System.Classes, System.SysUtils;

var
  ValueTypeCategories: TStringList;

function CategoryNameByID(CatID: Integer): string;
function CategoryIDByName(const Name: string): Integer;
function AddCategory(const Name: string): Integer;
procedure RenameCategory(CatID: Integer; const NewName: string);
procedure ResetValueTypeCategories;

implementation

const
  DefaultCategories: array[0..7] of string = (
    'Geometry', 'Optics', 'Deposition', 'Process',
    'Tribology', 'Other', 'Chemistry', 'Electrical'
  );

function CategoryNameByID(CatID: Integer): string;
begin
  if (CatID >= 0) and (CatID < ValueTypeCategories.Count) then
    Result := ValueTypeCategories[CatID]
  else
    Result := IntToStr(CatID);
end;

function CategoryIDByName(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to ValueTypeCategories.Count - 1 do
    if SameText(Name, ValueTypeCategories[I]) then
      Exit(I);
  Result := -1;
end;

function AddCategory(const Name: string): Integer;
begin
  Result := CategoryIDByName(Name);
  if Result < 0 then
    Result := ValueTypeCategories.Add(Name);
end;

procedure RenameCategory(CatID: Integer; const NewName: string);
begin
  if (CatID >= 0) and (CatID < ValueTypeCategories.Count) then
    ValueTypeCategories[CatID] := NewName;
end;

procedure ResetValueTypeCategories;
begin
  ValueTypeCategories.Clear;
  for var S in DefaultCategories do
    ValueTypeCategories.Add(S);
end;

initialization
  ValueTypeCategories := TStringList.Create;
  ResetValueTypeCategories;

finalization
  ValueTypeCategories.Free;

end.
