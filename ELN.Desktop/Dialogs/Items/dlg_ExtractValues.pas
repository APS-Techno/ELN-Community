unit dlg_ExtractValues;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.CheckLst, Vcl.ExtCtrls,
  RzPanel, RzLabel, RzButton,
  unit_ELNPluginTypes, unit_ELNPluginCore, unit_ValueType, unit_Item,
  unit_ItemTypes, unit_ItemModel, unit_ReaderValueMappingModel,
  unit_ReaderValueStatistics;

type
  TExtractedValue = record
    KV: TPluginKeyValue;
    Mapping: TReaderValueResolution;
    Chosen: Boolean;
  end;

  TExtractChoice = record
    Name: string;
    Units: string;
    Occurrence: Integer;
    Mapping: TReaderValueResolution;
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
    chkRemember: TCheckBox;
    procedure clbValuesClick(Sender: TObject);
    procedure lbCategoryClick(Sender: TObject);
    procedure lbValueTypeClick(Sender: TObject);
    procedure btnNewTypeClick(Sender: TObject);
  private
    FValues: TArray<TExtractedValue>;
    FAllValueTypes: TList<TValueType>;
    FFilteredIndices: TArray<Integer>;
    FResolver: TReaderValueMappingModel;
    FReaderId: string;
    FStatistics: TArray<TReaderValueStatistics>;
    procedure UpdateValueDisplay(Index: Integer);
    procedure PopulateValueTypes;
    function GetSelectedValueType: TValueType;
    procedure SyncMappingToUI;
    procedure SyncUIToMapping;
    function ConfirmSelectedIssues(Factor: Double): Boolean;
    function ChosenMapping(const KV: TPluginKeyValue; VT: TValueType): TReaderValueResolution;
    function RememberChoices: string;
  end;

function ChooseExtractValues(const KeyValues: TArray<TPluginKeyValue>;
  const ReaderId, Caption: string; const Analysis: IAnalysisKeyValueProvider;
  out Choices: TArray<TExtractChoice>): Boolean;

function WriteChosenValues(const Choices: TArray<TExtractChoice>;
  const KeyValues: TArray<TPluginKeyValue>; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider; SkipIssues: Boolean;
  ToleranceFactor: Double; out Skipped: Integer): Integer;

function ShowExtractValuesDialog(
  const KeyValues: TArray<TPluginKeyValue>;
  var Item: TItem; UserId: Integer;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider): Boolean;

procedure WriteExtractedValue(Items: TItemModel; const Mapping: TReaderValueResolution;
  const KV: TPluginKeyValue; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion, AnalysisSnapshot: string;
  Occurrence: Integer);

function TryWriteAutomaticExtractedValue(Items: TItemModel;
  const Mapping: TReaderValueResolution; const KV: TPluginKeyValue;
  UserId: Integer; var Item: TItem; FileId: Int64;
  const ReaderId, ReaderVersion, AnalysisSnapshot: string;
  ToleranceFactor: Double; Occurrence: Integer): Boolean;

function WriteAutomaticExtractedValues(Items: TItemModel; Resolver: TReaderValueMappingModel;
  const KeyValues: TArray<TPluginKeyValue>; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider;
  ToleranceFactor: Double; out Warnings: string): Integer;

implementation

uses
  unit_DataModel, unit_ValueTypeModel, unit_ValueTypeCategories,
  unit_ValueSource, unit_ValueChecks, unit_AnalysisSettingsModel, unit_UnitConverter,
  unit_ElnAnalysisSettings, dlg_Value;

{$R *.dfm}

function FormatKV(const KV: TPluginKeyValue): string;
begin
  Result := KV.Name;
  if KV.Units <> '' then
    Result := Result + ' = ' + Format('%.8g', [KV.Value]) + ' ' + KV.Units
  else
    Result := Result + ' = ' + Format('%.8g', [KV.Value]);
  if KV.Description <> '' then
    Result := Result + '  [' + KV.Description + ']';
  if KV.RecType = prCondition then
    Result := Result + '  (cond)'
  else
    Result := Result + '  (result)';
end;

function UnitText(const Units: string): string;
begin
  if Units = '' then
    Result := '(no units)'
  else
    Result := '"' + Units + '"';
end;

function LabelSuffix(const LabelText: string): string;
begin
  if LabelText = '' then
    Result := ''
  else
    Result := ', label "' + LabelText + '"';
end;

function SnapshotFor(const Analysis: IAnalysisKeyValueProvider;
  const KeyName: string): string;
begin
  if Analysis = nil then
    Result := ''
  else
    Result := Analysis.GetAnalysisSnapshot(KeyName);
end;

function KeyOccurrence(const KeyValues: TArray<TPluginKeyValue>;
  const Statistics: TArray<TReaderValueStatistics>; Index: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to Index - 1 do
    if not Statistics[J].IsStandardDeviation and
      (KeyValues[J].Name = KeyValues[Index].Name) then
      Inc(Result);
end;

procedure StoreConvertedExtractedValue(Items: TItemModel;
  const Mapping: TReaderValueResolution; const KV: TPluginKeyValue;
  Converted: Double; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion, AnalysisSnapshot: string;
  Occurrence: Integer);
var
  RecType: TRecType;
  Tolerance: Double;
  Warning: string;
  Source: TValueSourceInfo;
begin
  if KV.RecType = prResult then
    RecType := TEST_RESULT
  else
    RecType := EXP_CONDITION;
  if Mapping.ValueType = nil then
    raise EArgumentException.Create('An extracted value requires a resolved mapping');
  if Mapping.Statistics.IsStandardDeviation then Exit;
  Tolerance := ConvertedReaderTolerance(Mapping.Statistics, Mapping.Factor, Warning);
  Source := TValueSourceInfo.Reader(FileId, ReaderId, ReaderVersion, KV.Name,
    KV.Units, Mapping.Factor);
  Items.PutReaderValue(Mapping.ValueType, RecType, Converted, UserId, Item,
    Tolerance, Mapping.Description(KV.Description), Source, AnalysisSnapshot,
    Occurrence);
end;

procedure WriteExtractedValue(Items: TItemModel; const Mapping: TReaderValueResolution;
  const KV: TPluginKeyValue; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion, AnalysisSnapshot: string;
  Occurrence: Integer);
begin
  StoreConvertedExtractedValue(Items, Mapping, KV, KV.Value * Mapping.Factor,
    UserId, Item, FileId, ReaderId, ReaderVersion, AnalysisSnapshot, Occurrence);
end;

function TryWriteAutomaticExtractedValue(Items: TItemModel;
  const Mapping: TReaderValueResolution; const KV: TPluginKeyValue;
  UserId: Integer; var Item: TItem; FileId: Int64;
  const ReaderId, ReaderVersion, AnalysisSnapshot: string;
  ToleranceFactor: Double; Occurrence: Integer): Boolean;
var
  Converted, Tolerance: Double;
  Warning: string;
begin
  Result := False;
  if (Mapping.ValueType = nil) or not KV.IsKey or Mapping.Statistics.IsStandardDeviation then Exit;
  Converted := KV.Value * Mapping.Factor;
  Tolerance := ConvertedReaderTolerance(Mapping.Statistics, Mapping.Factor, Warning);
  if CheckValue(Mapping.ValueType, Converted, Tolerance, ToleranceFactor) <> [] then Exit;
  StoreConvertedExtractedValue(Items, Mapping, KV, Converted,
    UserId, Item, FileId, ReaderId, ReaderVersion, AnalysisSnapshot, Occurrence);
  Result := True;
end;

function WriteAutomaticExtractedValues(Items: TItemModel; Resolver: TReaderValueMappingModel;
  const KeyValues: TArray<TPluginKeyValue>; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider;
  ToleranceFactor: Double; out Warnings: string): Integer;
var
  Inputs: TArray<TReaderStatisticInput>;
  Statistics: TArray<TReaderValueStatistics>;
  Mapping: TReaderValueResolution;
  I: Integer;
  Warning: string;
begin
  Result := 0;
  Warnings := '';
  SetLength(Inputs, Length(KeyValues));
  for I := 0 to High(KeyValues) do
  begin
    Inputs[I].Name := KeyValues[I].Name;
    Inputs[I].Units := KeyValues[I].Units;
    Inputs[I].Value := KeyValues[I].Value;
  end;
  Statistics := AnalyzeReaderStatistics(Inputs);
  for I := 0 to High(KeyValues) do
  begin
    Warning := Statistics[I].Warning;
    if not Statistics[I].IsStandardDeviation and KeyValues[I].IsKey then
    begin
      Mapping := Resolver.Resolve(ReaderId, KeyValues[I].Name, KeyValues[I].Units);
      Mapping.Statistics := Statistics[I];
      ConvertedReaderTolerance(Statistics[I], Mapping.Factor, Warning);
      if Mapping.ValueType = nil then
        Warning := Warning + ' ' + KeyValues[I].Name + ': ' + Mapping.Reason
      else if not TryWriteAutomaticExtractedValue(Items, Mapping, KeyValues[I],
        UserId, Item, FileId, ReaderId, ReaderVersion,
        SnapshotFor(Analysis, KeyValues[I].Name), ToleranceFactor,
        KeyOccurrence(KeyValues, Statistics, I)) then
        Inc(Result);
    end;
    if Warning <> '' then Warnings := Warnings + Warning + sLineBreak;
  end;
  if Analysis <> nil then
    Warnings := Warnings + AnalysisStatusText(Analysis.GetAnalysisStatus);
end;

function ChooseExtractValues(const KeyValues: TArray<TPluginKeyValue>;
  const ReaderId, Caption: string; const Analysis: IAnalysisKeyValueProvider;
  out Choices: TArray<TExtractChoice>): Boolean;
var
  Dlg: TdlgExtractValues;
  I, J, Count: Integer;
  Inputs: TArray<TReaderStatisticInput>;
  Statistics: TArray<TReaderValueStatistics>;
  Factor: Double;
  Warnings, Warning: string;
begin
  Result := False;
  Choices := nil;
  if Length(KeyValues) = 0 then
    Exit;

  Dlg := TdlgExtractValues.Create(Application);
  try
    if Caption <> '' then
      Dlg.Caption := Caption;
    Dlg.FAllValueTypes := Model.ValueTypes.GetTypes;
    Dlg.FReaderId := ReaderId;
    Dlg.FResolver := TReaderValueMappingModel.Create(Model.Manager);
    if ReaderId = '' then
      Dlg.chkRemember.Hint := 'This file reader has no ID, so choices cannot be remembered'
    else if not Model.Access.CanEditReferenceData(Model.Manager, Model.User) then
      Dlg.chkRemember.Hint := 'Saving Reader mappings needs permission to edit reference data';
    if Dlg.chkRemember.Hint <> '' then
    begin
      Dlg.chkRemember.Checked := False;
      Dlg.chkRemember.Enabled := False;
    end;
    SetLength(Dlg.FValues, Length(KeyValues));
    SetLength(Inputs, Length(KeyValues));
    for I := 0 to High(KeyValues) do
    begin
      Inputs[I].Name := KeyValues[I].Name;
      Inputs[I].Units := KeyValues[I].Units;
      Inputs[I].Value := KeyValues[I].Value;
    end;
    Statistics := AnalyzeReaderStatistics(Inputs);
    SetLength(Dlg.FStatistics, Length(KeyValues));
    J := 0;
    Warnings := '';

    Dlg.clbValues.Items.Clear;
    for I := 0 to High(KeyValues) do
    begin
      if Statistics[I].IsStandardDeviation then
      begin
        if Statistics[I].Warning <> '' then
          Warnings := Warnings + Statistics[I].Warning + sLineBreak;
        Continue;
      end;
      Dlg.FValues[J].KV := KeyValues[I];
      Dlg.FStatistics[J] := Statistics[I];
      Dlg.FValues[J].Mapping := Dlg.FResolver.Resolve(ReaderId,
        KeyValues[I].Name, KeyValues[I].Units);
      Dlg.FValues[J].Mapping.Statistics := Statistics[I];
      ConvertedReaderTolerance(Statistics[I], Dlg.FValues[J].Mapping.Factor, Warning);
      if Warning <> '' then Warnings := Warnings + KeyValues[I].Name + ': ' + Warning + sLineBreak;
      Dlg.clbValues.Items.Add('');
      Dlg.UpdateValueDisplay(J);
      Dlg.clbValues.Checked[J] := KeyValues[I].IsKey and
        (Dlg.FValues[J].Mapping.ValueType <> nil);
      Inc(J);
    end;
    SetLength(Dlg.FValues, J);
    SetLength(Dlg.FStatistics, J);
    if Analysis <> nil then
      Warnings := Warnings + AnalysisStatusText(Analysis.GetAnalysisStatus);
    if Warnings <> '' then MessageDlg(Warnings, mtWarning, [mbOK], 0);

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

    if Dlg.chkRemember.Checked then
      Warnings := Dlg.RememberChoices
    else
      Warnings := '';

    SetLength(Choices, Length(Dlg.FValues));
    Count := 0;
    for I := 0 to High(Dlg.FValues) do
    begin
      if not Dlg.clbValues.Checked[I] or (Dlg.FValues[I].Mapping.ValueType = nil) then
        Continue;
      Choices[Count].Name := Dlg.FValues[I].KV.Name;
      Choices[Count].Units := Dlg.FValues[I].KV.Units;
      Choices[Count].Mapping := Dlg.FValues[I].Mapping;
      Choices[Count].Occurrence := 0;
      for J := 0 to I - 1 do
        if (Dlg.FValues[J].KV.Name = Choices[Count].Name) and
          (Dlg.FValues[J].KV.Units = Choices[Count].Units) then
          Inc(Choices[Count].Occurrence);
      Inc(Count);
    end;
    SetLength(Choices, Count);

    Result := True;
    if Warnings <> '' then
      MessageDlg('Some choices were not remembered:' + sLineBreak + Warnings,
        mtWarning, [mbOK], 0);
  finally
    Dlg.FResolver.Free;
    Dlg.FAllValueTypes.Free;
    Dlg.Free;
  end;
end;

function WriteChosenValues(const Choices: TArray<TExtractChoice>;
  const KeyValues: TArray<TPluginKeyValue>; UserId: Integer; var Item: TItem;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider; SkipIssues: Boolean;
  ToleranceFactor: Double; out Skipped: Integer): Integer;
var
  Inputs: TArray<TReaderStatisticInput>;
  Statistics: TArray<TReaderValueStatistics>;
  Mapping: TReaderValueResolution;
  I, K, Seen: Integer;
  Found: Boolean;
  Warning: string;
  Converted, Tolerance: Double;
begin
  Result := 0;
  Skipped := 0;
  SetLength(Inputs, Length(KeyValues));
  for I := 0 to High(KeyValues) do
  begin
    Inputs[I].Name := KeyValues[I].Name;
    Inputs[I].Units := KeyValues[I].Units;
    Inputs[I].Value := KeyValues[I].Value;
  end;
  Statistics := AnalyzeReaderStatistics(Inputs);
  for I := 0 to High(Choices) do
  begin
    Found := False;
    Seen := 0;
    for K := 0 to High(KeyValues) do
      if not Statistics[K].IsStandardDeviation and
        (KeyValues[K].Name = Choices[I].Name) and
        (KeyValues[K].Units = Choices[I].Units) then
      begin
        if Seen = Choices[I].Occurrence then
        begin
          Found := True;
          Break;
        end;
        Inc(Seen);
      end;
    if not Found then
    begin
      Inc(Skipped);
      Continue;
    end;
    Mapping := Choices[I].Mapping;
    Mapping.Statistics := Statistics[K];
    if SkipIssues then
    begin
      Converted := KeyValues[K].Value * Mapping.Factor;
      Tolerance := ConvertedReaderTolerance(Mapping.Statistics, Mapping.Factor, Warning);
      if CheckValue(Mapping.ValueType, Converted, Tolerance, ToleranceFactor) <> [] then
      begin
        Inc(Skipped);
        Continue;
      end;
    end;
    WriteExtractedValue(Model.Items, Mapping, KeyValues[K], UserId, Item,
      FileId, ReaderId, ReaderVersion, SnapshotFor(Analysis, KeyValues[K].Name),
      KeyOccurrence(KeyValues, Statistics, K));
    Inc(Result);
  end;
end;

function ShowExtractValuesDialog(
  const KeyValues: TArray<TPluginKeyValue>;
  var Item: TItem; UserId: Integer;
  FileId: Int64; const ReaderId, ReaderVersion: string;
  const Analysis: IAnalysisKeyValueProvider): Boolean;
var
  Choices: TArray<TExtractChoice>;
  Skipped: Integer;
begin
  Result := False;
  if not ChooseExtractValues(KeyValues, ReaderId, '', Analysis, Choices) then
    Exit;
  Result := WriteChosenValues(Choices, KeyValues, UserId, Item, FileId,
    ReaderId, ReaderVersion, Analysis, False, 0, Skipped) > 0;
end;

function TdlgExtractValues.ConfirmSelectedIssues(Factor: Double): Boolean;
var
  I: Integer;
  VT: TValueType;
  Issues: TValueIssues;
  Lines: string;
  Tolerance: Double;
  Warning: string;
begin
  Lines := '';
  for I := 0 to High(FValues) do
  begin
    VT := FValues[I].Mapping.ValueType;
    if not clbValues.Checked[I] or (VT = nil) then
      Continue;
    Tolerance := ConvertedReaderTolerance(FValues[I].Mapping.Statistics,
      FValues[I].Mapping.Factor, Warning);
    Issues := CheckValue(VT, FValues[I].KV.Value * FValues[I].Mapping.Factor, Tolerance, Factor);
    if Issues <> [] then
      Lines := Lines + sLineBreak + '- ' + FValues[I].KV.Name + ': ' +
        DescribeValueIssues(Issues, VT, FValues[I].KV.Value * FValues[I].Mapping.Factor, Tolerance, Factor);
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

procedure TdlgExtractValues.UpdateValueDisplay(Index: Integer);
var
  Entry: TExtractedValue;
  Text, Warning: string;
  Tolerance: Double;
begin
  Entry := FValues[Index];
  Text := FormatKV(Entry.KV);
  if Entry.Mapping.ValueType = nil then
    Text := Text + ' [' + Entry.Mapping.Reason + ']'
  else
  begin
    Text := Text + ' -> ' + Format('%.8g', [Entry.KV.Value * Entry.Mapping.Factor]);
    Tolerance := ConvertedReaderTolerance(Entry.Mapping.Statistics, Entry.Mapping.Factor, Warning);
    if Entry.Mapping.Statistics.HasStandardDeviation and (Warning = '') then
      Text := Text + ' +/- ' + Format('%.8g', [Tolerance]);
    Text := Text + ' ' + Entry.Mapping.ValueType.Units + ' (' + Entry.Mapping.ValueType.Title + ')';
  end;
  if Warning = '' then Warning := Entry.Mapping.Statistics.Warning;
  if Warning <> '' then Text := Text + ' [' + Warning + ']';
  clbValues.Items[Index] := Text;
end;

procedure TdlgExtractValues.SyncMappingToUI;
var
  Idx, I: Integer;
  MappedVT: TValueType;
begin
  Idx := clbValues.ItemIndex;
  if (Idx < 0) or (Idx > High(FValues)) then
    Exit;

  MappedVT := FValues[Idx].Mapping.ValueType;
  if MappedVT = nil then
    lblMapping.Caption := FValues[Idx].Mapping.Reason
  else
    lblMapping.Caption := UnitText(FValues[Idx].KV.Units) + ' -> ' +
      UnitText(MappedVT.Units) + ', factor ' + FloatToStr(FValues[Idx].Mapping.Factor) +
      LabelSuffix(FValues[Idx].Mapping.LabelText);
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
  FValues[Idx].Mapping := FResolver.Resolve(FReaderId,
    FValues[Idx].KV.Name, FValues[Idx].KV.Units);
  FValues[Idx].Chosen := False;
  if (VT <> nil) and (FValues[Idx].Mapping.ValueType <> VT) then
  begin
    FValues[Idx].Mapping := ChosenMapping(FValues[Idx].KV, VT);
    FValues[Idx].Chosen := FValues[Idx].Mapping.ValueType <> nil;
  end;
  FValues[Idx].Mapping.Statistics := FStatistics[Idx];
  UpdateValueDisplay(Idx);
  clbValues.Checked[Idx] := FValues[Idx].Mapping.ValueType <> nil;
  SyncMappingToUI;
end;

function TdlgExtractValues.ChosenMapping(const KV: TPluginKeyValue;
  VT: TValueType): TReaderValueResolution;
begin
  Result := Default(TReaderValueResolution);
  if TUnitConverter.TryFactor(KV.Units, VT.Units, Result.Factor) then
    Result.ValueType := VT
  else
  begin
    Result.Factor := 1;
    Result.Reason := 'No automatic conversion from ' + UnitText(KV.Units) +
      ' to ' + UnitText(VT.Units);
  end;
end;

function TdlgExtractValues.RememberChoices: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FValues) do
    if clbValues.Checked[I] and FValues[I].Chosen and
      (FValues[I].Mapping.ValueType <> nil) then
    try
      FResolver.Remember(FReaderId, FValues[I].KV.Name, FValues[I].KV.Units,
        FValues[I].Mapping.ValueType, FValues[I].Mapping.Factor);
    except
      on E: EArgumentException do
        Result := Result + FValues[I].KV.Name + ': ' + E.Message + sLineBreak;
    end;
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
  VT: TValueType;
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
  FAllValueTypes.Free;
  FAllValueTypes := Model.ValueTypes.GetTypes;
  PopulateValueTypes;

  VT := Model.ValueTypes.FindByTitleUnits(Values[1], Values[2]);
  if VT = nil then
    Exit;
  FValues[Idx].Mapping := ChosenMapping(KV, VT);
  FValues[Idx].Chosen := FValues[Idx].Mapping.ValueType <> nil;
  FValues[Idx].Mapping.Statistics := FStatistics[Idx];
  UpdateValueDisplay(Idx);
  SyncMappingToUI;
  clbValues.Checked[Idx] := FValues[Idx].Mapping.ValueType <> nil;
end;

end.
