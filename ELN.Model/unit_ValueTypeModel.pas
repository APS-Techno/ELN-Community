unit unit_ValueTypeModel;

interface

uses
  SysUtils, Classes,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  System.Generics.Collections,
  unit_ValueType,
  unit_ValueTypeCategories,
  unit_Item,
  unit_TELNModel,
  unit_ELNDB_Dictionary;

  function FormatSIValue(AValue: double; const Units: string): string;
  function FormatValuesInline(Values: TValues): string;

type

  TValueTypeModel = class(TELNModel)
    private
      FDic: TValueTypeDictionary;
      FManager: TObjectManager;
    protected
      function GetDataSet: TAureliusDataset; override;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;

      procedure CreateDefaultData;
      procedure AddType(const Symbol, Title, Units: string; Group: integer);
      function GetType(const ID: integer): TValueType;
      function GetTypes: TList<TValueType>;
      function FindByTitleUnits(const ATitle, AUnits: string): TValueType;
      function CanDelete(ID: Integer): string;
      procedure LoadCategories(APersistMissing: Boolean);
      procedure SaveCategories;
      procedure MoveToCategory(ValueTypeID, NewCatID: Integer);
  end;


implementation

uses
  System.JSON, System.Variants, Aurelius.Criteria.Projections,
  unit_DBSetting, unit_DBSettingsModel,
  unit_TimeHelper;

const
  KEY_VT_CATEGORIES = 'ValueTypeCategories';

function FormatSIValue(AValue: double; const Units: string): string;
var
  AbsVal: double;
  Prefix: string;
  Scaled: double;
begin
  AbsVal := Abs(AValue);

  // Skip SI prefix scaling for zero, no units, values already in displayable
  // range, or compound units (containing / or ·) where prefixing is wrong
  if (AValue = 0) or (Units = '') or ((AbsVal >= 0.1) and (AbsVal < 1000))
    or (Pos('/', Units) > 0) or (Pos(#$00B7, Units) > 0) then
  begin
    Result := Format('%.4g', [AValue]);
    if Units <> '' then
      Result := Result + ' ' + Units;
    Exit;
  end;

  if      AbsVal >= 1e9  then begin Prefix := 'G';    Scaled := AValue / 1e9;  end
  else if AbsVal >= 1e6  then begin Prefix := 'M';    Scaled := AValue / 1e6;  end
  else if AbsVal >= 1e3  then begin Prefix := 'k';    Scaled := AValue / 1e3;  end
  else if AbsVal >= 1    then begin Prefix := '';      Scaled := AValue;        end
  else if AbsVal >= 1e-3 then begin Prefix := 'm';    Scaled := AValue * 1e3;  end
  else if AbsVal >= 1e-6 then begin Prefix := #$00B5; Scaled := AValue * 1e6;  end
  else if AbsVal >= 1e-9 then begin Prefix := 'n';    Scaled := AValue * 1e9;  end
  else                        begin Prefix := 'p';    Scaled := AValue * 1e12; end;

  Result := Format('%.4g %s%s', [Scaled, Prefix, Units]);
end;

function FormatValuesInline(Values: TValues): string;
var
  Val: TValue;
begin
  Result := '';
  for Val in Values do
  begin
    if Result <> '' then
      Result := Result + ';  ';
    Result := Result + Val.ValueType.Symbol + ' = ' +
      FormatSIValue(Val.Value, Val.ValueType.Units);
    if Val.Description <> '' then
      Result := Result + ' [' + Val.Description + ']';
  end;
end;

{ TValueTypeModel }

procedure TValueTypeModel.AddType(const Symbol, Title, Units: string; Group: integer);
var
  AType: TValueType;
begin
  AType := TValueType.Create;

  AType.Symbol  := Symbol;
  AType.Title   := Title;
  AType.Units   := Units;
  AType.CatID   := Group;
  AType.CreatedDate := UTCNow;
  AType.CreatedBy := 1;
  FManager.Save(AType);
end;

constructor TValueTypeModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TValueTypeDictionary.Create;
end;

procedure TValueTypeModel.CreateDefaultData;
var
  CSVPath: string;
  Lines: TStringList;
  Parts: TStringList;
  I: Integer;
begin
  CSVPath := ExtractFilePath(ParamStr(0)) + 'CSV' + PathDelim + 'ValueTypes.csv';
  if not FileExists(CSVPath) then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(CSVPath, TEncoding.UTF8);
    for I := 1 to Lines.Count - 1 do  // skip header
    begin
      if Trim(Lines[I]) = '' then
        Continue;
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ',';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := Lines[I];
        if Parts.Count >= 4 then
          AddType(Parts[0], Parts[1], Parts[2], StrToIntDef(Parts[3], 0));
      finally
        Parts.Free;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

destructor TValueTypeModel.Destroy;
begin

  inherited;
end;

function TValueTypeModel.GetDataSet: TAureliusDataset;
begin
  OpenDataSet;
  Result := FDataSet;
end;

function TValueTypeModel.GetType(const ID: integer): TValueType;
begin
  Result := FManager.Find<TValueType>(ID);
end;

function TValueTypeModel.GetTypes: TList<TValueType>;
begin
  Result := FManager.Find<TValueType>.List;
end;

procedure TValueTypeModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FManager.Find<TValueType>);
  FDataSet.Open;
end;

function TValueTypeModel.FindByTitleUnits(const ATitle, AUnits: string): TValueType;
var
  VTDic: TValueTypeDictionary;
  List: TList<TValueType>;
begin
  Result := nil;
  VTDic := TValueTypeDictionary.Create;
  try
    List := FManager.Find<TValueType>
      .Where(VTDic.Title.ILike(ATitle) and VTDic.Units.ILike(AUnits))
      .List;
    try
      if List.Count > 0 then
        Result := FManager.Find<TValueType>(List[0].Id);
    finally
      List.Free;
    end;
  finally
    VTDic.Free;
  end;
end;

function TValueTypeModel.CanDelete(ID: Integer): string;
var
  ValDic: TValueDictionary;
  ValCount: Integer;
begin
  Result := '';
  ValDic := TValueDictionary.Create;
  try
    ValCount := FManager.Find<TValue>.Where(ValDic.Typeid.Id = ID).List.Count;
    if ValCount > 0 then
      Result := Format('Cannot delete: used by %d value(s).', [ValCount]);
  finally
    ValDic.Free;
  end;
end;

procedure TValueTypeModel.LoadCategories(APersistMissing: Boolean);
var
  Setting: TDBSetting;
  JArr: TJSONArray;
  I, MaxCatID: Integer;
  Maximum: TCriteriaResult;
  NeedSave: Boolean;
begin
  ResetValueTypeCategories;
  Setting := FManager.Find<TDBSetting>(KEY_VT_CATEGORIES);
  if Assigned(Setting) and (Setting.SettingValue <> '') then
  begin
    JArr := TJSONObject.ParseJSONValue(Setting.SettingValue) as TJSONArray;
    if JArr <> nil then
    try
      ValueTypeCategories.Clear;
      for I := 0 to JArr.Count - 1 do
        ValueTypeCategories.Add(JArr.Items[I].Value);
    finally
      JArr.Free;
    end;
  end;

  // Scan DB for CatIDs beyond the known list and pad with placeholders
  NeedSave := not Assigned(Setting);
  MaxCatID := ValueTypeCategories.Count - 1;
  Maximum := FManager.Find<TValueType>
    .Select(TProjections.Max('CatID').As_('MaxCategoryId')).UniqueValue;
  try
    if Assigned(Maximum) and not VarIsNull(Maximum.Values['MaxCategoryId']) then
      if Integer(Maximum.Values['MaxCategoryId']) > MaxCatID then
        MaxCatID := Integer(Maximum.Values['MaxCategoryId']);
  finally
    Maximum.Free;
  end;
  if MaxCatID >= ValueTypeCategories.Count then
    NeedSave := True;
  while ValueTypeCategories.Count <= MaxCatID do
    ValueTypeCategories.Add('Category ' + IntToStr(ValueTypeCategories.Count));

  if NeedSave and APersistMissing then
    SaveCategories;
end;

procedure TValueTypeModel.SaveCategories;
var
  JArr: TJSONArray;
  I: Integer;
begin
  JArr := TJSONArray.Create;
  try
    for I := 0 to ValueTypeCategories.Count - 1 do
      JArr.Add(ValueTypeCategories[I]);
    TDBSettingsModel.StoreValue(FManager, KEY_VT_CATEGORIES, JArr.ToJSON);
  finally
    JArr.Free;
  end;
end;

procedure TValueTypeModel.MoveToCategory(ValueTypeID, NewCatID: Integer);
var
  VT: TValueType;
begin
  VT := FManager.Find<TValueType>(ValueTypeID);
  if VT = nil then
    Exit;
  VT.CatID := NewCatID;
  FManager.Update(VT);
  FManager.Flush;
end;

end.
