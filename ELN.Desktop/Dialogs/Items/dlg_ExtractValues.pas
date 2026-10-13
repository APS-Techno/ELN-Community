unit dlg_ExtractValues;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.CheckLst, Vcl.ExtCtrls,
  RzPanel, RzLabel, RzButton,
  unit_ELNPluginTypes, unit_ValueType, unit_Item, unit_ItemTypes, unit_ItemModel;

type
  TExtractedValue = record
    KV: TPluginKeyValue;
    ValueType: TValueType;   // matched or user-selected; nil = skip
  end;

  TdlgExtractValues = class(TForm)
    pnlBottom: TRzPanel;
    btnOK: TRzBitBtn;
    btnCancel: TRzBitBtn;
    pnlRight: TRzPanel;
    lblMapping: TRzLabel;
    lblCategory: TRzLabel;
    lbCategory: TListBox;
    lblValueType: TRzLabel;
    lbValueType: TListBox;
    btnNewType: TRzButton;
    pnlClient: TRzPanel;
    lblHeader: TRzLabel;
    clbValues: TCheckListBox;
    procedure clbValuesClick(Sender: TObject);
    procedure lbCategoryClick(Sender: TObject);
    procedure lbValueTypeClick(Sender: TObject);
    procedure btnNewTypeClick(Sender: TObject);
  private
    FValues: TArray<TExtractedValue>;
    FAllValueTypes: TList<TValueType>;
    FFilteredIndices: TArray<Integer>;
    procedure PopulateValueTypes;
    function GetSelectedValueType: TValueType;
    procedure SyncMappingToUI;
    procedure SyncUIToMapping;
    function ConfirmSelectedIssues(Factor: Double): Boolean;
  end;

function ShowExtractValuesDialog(
  const KeyValues: TArray<TPluginKeyValue>;
  var Item: TItem; UserId: Integer;
  FileId: Int64; const ReaderId, ReaderVersion: string): Boolean;

procedure WriteExtractedValue(Items: TItemModel; ValueType: TValueType;
  const KV: TPluginKeyValue; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string);

implementation

uses
  unit_DataModel, unit_ValueTypeModel, unit_ValueTypeCategories,
  unit_ValueSource, unit_ValueChecks, dlg_Value;

{$R *.dfm}

function FormatKV(const KV: TPluginKeyValue): string;
begin
  Result := KV.Name;
  if KV.Units <> '' then
    Result := Result + ' = ' + FormatFloat('0.####', KV.Value) + ' ' + KV.Units
  else
    Result := Result + ' = ' + FormatFloat('0.####', KV.Value);
  if KV.Description <> '' then
    Result := Result + '  [' + KV.Description + ']';
  if KV.RecType = prCondition then
    Result := Result + '  (cond)'
  else
    Result := Result + '  (result)';
end;

procedure WriteExtractedValue(Items: TItemModel; ValueType: TValueType;
  const KV: TPluginKeyValue; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string);
var
  RecType: TRecType;
begin
  if KV.RecType = prResult then
    RecType := TEST_RESULT
  else
    RecType := EXP_CONDITION;
  Items.AddValue(ValueType, RecType, KV.Value, UserId, Item, 0, KV.Description,
    TValueSourceInfo.Reader(FileId, ReaderId, ReaderVersion, KV.Name));
end;

function ShowExtractValuesDialog(
  const KeyValues: TArray<TPluginKeyValue>;
  var Item: TItem; UserId: Integer;
  FileId: Int64; const ReaderId, ReaderVersion: string): Boolean;
var
  Dlg: TdlgExtractValues;
  I, AddedCount: Integer;
  VT: TValueType;
  Factor: Double;
begin
  Result := False;
  if Length(KeyValues) = 0 then
    Exit;

  Dlg := TdlgExtractValues.Create(Application);
  try
    Dlg.FAllValueTypes := Model.ValueTypes.GetTypes;
    SetLength(Dlg.FValues, Length(KeyValues));

    Dlg.clbValues.Items.Clear;
    for I := 0 to High(KeyValues) do
    begin
      Dlg.FValues[I].KV := KeyValues[I];
      Dlg.FValues[I].ValueType := Model.ValueTypes.FindByTitleUnits(
        KeyValues[I].Name, KeyValues[I].Units);
      Dlg.clbValues.Items.Add(FormatKV(KeyValues[I]));
      Dlg.clbValues.Checked[I] := KeyValues[I].IsKey and
        (Dlg.FValues[I].ValueType <> nil);
    end;

    Dlg.lbCategory.Items.Clear;
    Dlg.lbCategory.Items.Add('(All)');
    for I := 0 to ValueTypeCategories.Count - 1 do
      Dlg.lbCategory.Items.Add(ValueTypeCategories[I]);
    Dlg.lbCategory.ItemIndex := 0;
    Dlg.PopulateValueTypes;

    if Dlg.clbValues.Count > 0 then
    begin
      Dlg.clbValues.ItemIndex := 0;
      Dlg.SyncMappingToUI;
    end;

    Factor := LoadToleranceFactor(Model.Manager);
    repeat
      if Dlg.ShowModal <> mrOK then
        Exit;
    until Dlg.ConfirmSelectedIssues(Factor);

    AddedCount := 0;
    for I := 0 to High(Dlg.FValues) do
    begin
      if not Dlg.clbValues.Checked[I] then
        Continue;
      VT := Dlg.FValues[I].ValueType;
      if VT = nil then
        Continue;

      WriteExtractedValue(Model.Items, VT, KeyValues[I], UserId, Item,
        FileId, ReaderId, ReaderVersion);
      Inc(AddedCount);
    end;

    Result := AddedCount > 0;
  finally
    Dlg.Free;
  end;
end;

function TdlgExtractValues.ConfirmSelectedIssues(Factor: Double): Boolean;
var
  I: Integer;
  VT: TValueType;
  Issues: TValueIssues;
  Lines: string;
begin
  Lines := '';
  for I := 0 to High(FValues) do
  begin
    VT := FValues[I].ValueType;
    if not clbValues.Checked[I] or (VT = nil) then
      Continue;
    Issues := CheckValue(VT, FValues[I].KV.Value, 0, Factor);
    if Issues <> [] then
      Lines := Lines + sLineBreak + '- ' + FValues[I].KV.Name + ': ' +
        DescribeValueIssues(Issues, VT, FValues[I].KV.Value, 0, Factor);
  end;
  Result := (Lines = '') or ConfirmValueIssues(
    'Some selected values need checking:' + sLineBreak + Lines + sLineBreak +
    sLineBreak + 'Store them anyway? Choose No to return to the list.');
end;


procedure TdlgExtractValues.PopulateValueTypes;
var
  VT: TValueType;
  I, CatIdx, FilterCatID: Integer;
begin
  lbValueType.Items.Clear;
  SetLength(FFilteredIndices, 0);

  CatIdx := lbCategory.ItemIndex;
  if CatIdx <= 0 then
    FilterCatID := -1
  else
    FilterCatID := CatIdx - 1;

  for I := 0 to FAllValueTypes.Count - 1 do
  begin
    VT := FAllValueTypes[I];
    if (FilterCatID >= 0) and (VT.CatID <> FilterCatID) then
      Continue;

    lbValueType.Items.Add(VT.Symbol + ' '#$2014' ' + VT.Title + ' (' + VT.Units + ')');
    SetLength(FFilteredIndices, Length(FFilteredIndices) + 1);
    FFilteredIndices[High(FFilteredIndices)] := I;
  end;
end;

function TdlgExtractValues.GetSelectedValueType: TValueType;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := lbValueType.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FFilteredIndices)) then
    Result := FAllValueTypes[FFilteredIndices[Idx]];
end;

procedure TdlgExtractValues.SyncMappingToUI;
var
  Idx, I: Integer;
  MappedVT: TValueType;
begin
  Idx := clbValues.ItemIndex;
  if (Idx < 0) or (Idx > High(FValues)) then
    Exit;

  MappedVT := FValues[Idx].ValueType;
  if MappedVT = nil then
  begin
    lbValueType.ItemIndex := -1;
    Exit;
  end;

  lbValueType.ItemIndex := -1;
  for I := 0 to High(FFilteredIndices) do
    if FAllValueTypes[FFilteredIndices[I]].Id = MappedVT.Id then
    begin
      lbValueType.ItemIndex := I;
      Break;
    end;

  if (lbValueType.ItemIndex < 0) and (lbCategory.ItemIndex > 0) then
  begin
    lbCategory.ItemIndex := 0;
    PopulateValueTypes;
    for I := 0 to High(FFilteredIndices) do
      if FAllValueTypes[FFilteredIndices[I]].Id = MappedVT.Id then
      begin
        lbValueType.ItemIndex := I;
        Break;
      end;
  end;
end;

procedure TdlgExtractValues.SyncUIToMapping;
var
  Idx: Integer;
  VT: TValueType;
begin
  Idx := clbValues.ItemIndex;
  if (Idx < 0) or (Idx > High(FValues)) then
    Exit;

  VT := GetSelectedValueType;
  FValues[Idx].ValueType := VT;

  if VT <> nil then
    clbValues.Checked[Idx] := True;
end;

procedure TdlgExtractValues.clbValuesClick(Sender: TObject);
begin
  SyncMappingToUI;
end;

procedure TdlgExtractValues.lbCategoryClick(Sender: TObject);
begin
  PopulateValueTypes;
end;

procedure TdlgExtractValues.lbValueTypeClick(Sender: TObject);
begin
  SyncUIToMapping;
end;

procedure TdlgExtractValues.btnNewTypeClick(Sender: TObject);
var
  Idx: Integer;
  KV: TPluginKeyValue;
  Values: array[0..2] of string;
begin
  Idx := clbValues.ItemIndex;
  if (Idx < 0) or (Idx > High(FValues)) then
    Exit;

  KV := FValues[Idx].KV;

  Values[1] := KV.Name;    
  Values[2] := KV.Units;   
  Values[0] := '';          
  if Length(Values[1]) > 0 then
    Values[0] := UpperCase(Values[1][1]);

  if not InputQuery('New ValueType',
    ['Symbol (1-2 chars):', 'Title:', 'Units:'], Values) then
    Exit;

  Model.ValueTypes.AddType(Values[0], Values[1], Values[2], 0);
  FAllValueTypes := Model.ValueTypes.GetTypes;
  PopulateValueTypes;

  FValues[Idx].ValueType := Model.ValueTypes.FindByTitleUnits(Values[1], Values[2]);
  SyncMappingToUI;
  clbValues.Checked[Idx] := True;
end;

end.
