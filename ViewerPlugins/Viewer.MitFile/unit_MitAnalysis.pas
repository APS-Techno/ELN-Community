unit unit_MitAnalysis;

interface

uses
  System.SysUtils, unit_ELNPluginCore, unit_ELNPluginTypes, unit_MitFileParser;

const
  MitReaderId = 'aps.mit';
  MitReaderVersion = '2';
  MitAlgorithmVersion = '1';
  MitSchemaVersion = 1;
  MitKeyHardness = 'Hardness';
  MitKeyModulus = 'Modulus';
  MitKeyReducedModulus = 'Reduced Modulus';
  MitKeyContactDepth = 'Contact Depth';
  MitKeyMaxForce = 'Max Force';
  MitKeyIndentCount = 'Indent Count';
  MitKeyIndentsExcluded = 'Indents Excluded';

type
  TMitSelectionMode = (msmAutomatic, msmIndents);

  TMitOrigin = record
    Present: Boolean;
    Revision: Integer;
    ApplyId: string;
  end;

  TMitSelection = record
    Mode: TMitSelectionMode;
    Checked: TArray<Integer>;
    FileHash: string;
    Origin: TMitOrigin;
  end;

  TMitStat = record
    Mean: Double;
    Std: Double;
  end;

  TMitAnalysis = record
    Available: Boolean;
    Status: string;
    Mode: TMitSelectionMode;
    Origin: TMitOrigin;
    Used: TArray<Integer>;
    Excluded: Integer;
    HasModulus: Boolean;
    Instrument: Boolean;
    Hardness: TMitStat;
    Modulus: TMitStat;
    ReducedModulus: TMitStat;
    ContactDepth: TMitStat;
    MaxForce: TMitStat;
  end;

function TryParseMitSelection(const Json: string; out Selection: TMitSelection): Boolean;
function MitSelectionToJson(const Selection: TMitSelection; Revision, AppliedBy: Integer;
  const ApplyId, AppliedAt: string): string;
function MitSelectionOf(const Analysis: TMitAnalysis; const FileHash: string): TMitSelection;
function MitAnalysisFromChecked(MitFile: TMitFile; const Checked: TArray<Integer>;
  const Origin: TMitOrigin): TMitAnalysis;
function MitSelectionFits(MitFile: TMitFile; const Selection: TMitSelection): Boolean;
function ResolveMitAnalysis(MitFile: TMitFile;
  const Context: TAnalysisContext): TMitAnalysis;
function MitKeyHasSnapshot(const KeyName: string): Boolean;
function BuildMitSnapshot(const Context: TAnalysisContext; const KeyName: string;
  const Analysis: TMitAnalysis): string;
function MitKeyValues(const Analysis: TMitAnalysis): TArray<TPluginKeyValue>;

implementation

uses
  System.JSON, System.Math, System.Generics.Collections;

const
  ModeNames: array[TMitSelectionMode] of string = ('automatic', 'indents');
  SnapshotKeys: array[0..4] of string = (MitKeyHardness, MitKeyModulus,
    MitKeyReducedModulus, MitKeyContactDepth, MitKeyMaxForce);

function ParseObject(const Json: string): TJSONObject;
var
  Root: TJSONValue;
begin
  try
    Root := TJSONObject.ParseJSONValue(Json);
  except
    Root := nil;
  end;
  if Root is TJSONObject then
    Result := TJSONObject(Root)
  else
  begin
    Root.Free;
    Result := nil;
  end;
end;

function GetInteger(Obj: TJSONObject; const Name: string; out V: Integer): Boolean;
var
  Field: TJSONValue;
  F: Double;
begin
  Field := Obj.GetValue(Name);
  Result := (Field is TJSONNumber) and
    TryStrToFloat(Field.Value, F, TFormatSettings.Invariant) and
    not IsNan(F) and not IsInfinite(F) and (Frac(F) = 0) and (Abs(F) < MaxInt);
  if Result then
    V := Trunc(F);
end;

function GetText(Obj: TJSONObject; const Name: string; out V: string): Boolean;
var
  Field: TJSONValue;
begin
  Field := Obj.GetValue(Name);
  Result := (Field is TJSONString) and not (Field is TJSONNumber);
  if Result then
    V := Field.Value;
end;

function GetIntegers(Obj: TJSONObject; const Name: string;
  out Values: TArray<Integer>): Boolean;
var
  Field: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  V: Double;
begin
  Values := nil;
  Field := Obj.GetValue(Name);
  if not (Field is TJSONArray) then
    Exit(False);
  Arr := TJSONArray(Field);
  SetLength(Values, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    if not (Arr.Items[I] is TJSONNumber) or
      not TryStrToFloat(Arr.Items[I].Value, V, TFormatSettings.Invariant) or
      (Frac(V) <> 0) or (Abs(V) >= MaxInt) then
    begin
      Values := nil;
      Exit(False);
    end;
    Values[I] := Trunc(V);
  end;
  Result := True;
end;

function ModeFromText(const Text: string; out Mode: TMitSelectionMode): Boolean;
var
  M: TMitSelectionMode;
begin
  for M := Low(TMitSelectionMode) to High(TMitSelectionMode) do
    if Text = ModeNames[M] then
    begin
      Mode := M;
      Exit(True);
    end;
  Result := False;
end;

function ParseHeader(Obj: TJSONObject; Required: Boolean): Boolean;
var
  Schema: Integer;
  Text: string;
begin
  Result := False;
  if Required or (Obj.GetValue('schema_version') <> nil) then
    if not GetInteger(Obj, 'schema_version', Schema) or (Schema <> MitSchemaVersion) then
      Exit;
  if Obj.GetValue('reader_id') <> nil then
    if not GetText(Obj, 'reader_id', Text) or (Text <> MitReaderId) then
      Exit;
  Result := True;
end;

function ParseModeFields(Obj: TJSONObject; var Selection: TMitSelection): Boolean;
var
  Text: string;
begin
  Result := GetText(Obj, 'mode', Text) and ModeFromText(Text, Selection.Mode);
  if Result and (Selection.Mode = msmIndents) then
    Result := GetIntegers(Obj, 'checked', Selection.Checked);
end;

procedure ReadOrigin(Obj: TJSONObject; const RevisionName, ApplyName: string;
  var Origin: TMitOrigin);
begin
  if GetInteger(Obj, RevisionName, Origin.Revision) and
    GetText(Obj, ApplyName, Origin.ApplyId) then
    Origin.Present := True
  else
    Origin := Default(TMitOrigin);
end;

function TryParseMitSelection(const Json: string; out Selection: TMitSelection): Boolean;
var
  Obj: TJSONObject;
begin
  Selection := Default(TMitSelection);
  Result := False;
  Obj := ParseObject(Json);
  if Obj = nil then
    Exit;
  try
    Result := ParseHeader(Obj, False) and ParseModeFields(Obj, Selection);
    if Result and (Obj.GetValue('file_hash') <> nil) then
      Result := GetText(Obj, 'file_hash', Selection.FileHash);
    if Result then
      ReadOrigin(Obj, 'revision', 'apply_id', Selection.Origin);
  finally
    Obj.Free;
    if not Result then
      Selection := Default(TMitSelection);
  end;
end;

function TryParseStored(const Json: string; out Selection: TMitSelection): Boolean;
var
  Obj: TJSONObject;
begin
  Selection := Default(TMitSelection);
  Result := False;
  Obj := ParseObject(Json);
  if Obj = nil then
    Exit;
  try
    Result := ParseHeader(Obj, True) and ParseModeFields(Obj, Selection);
    if Result then
      ReadOrigin(Obj, 'shared_revision', 'shared_apply_id', Selection.Origin);
  finally
    Obj.Free;
    if not Result then
      Selection := Default(TMitSelection);
  end;
end;

function MitSelectionToJson(const Selection: TMitSelection; Revision, AppliedBy: Integer;
  const ApplyId, AppliedAt: string): string;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  N: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', TJSONNumber.Create(MitSchemaVersion));
    Obj.AddPair('reader_id', MitReaderId);
    Obj.AddPair('mode', ModeNames[Selection.Mode]);
    if Selection.Mode = msmIndents then
    begin
      Arr := TJSONArray.Create;
      Obj.AddPair('checked', Arr);
      for N in Selection.Checked do
        Arr.Add(N);
    end;
    Obj.AddPair('file_hash', Selection.FileHash);
    Obj.AddPair('apply_id', ApplyId);
    Obj.AddPair('applied_at', AppliedAt);
    Obj.AddPair('applied_by', TJSONNumber.Create(AppliedBy));
    Obj.AddPair('revision', TJSONNumber.Create(Revision));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function MitSelectionOf(const Analysis: TMitAnalysis; const FileHash: string): TMitSelection;
begin
  Result := Default(TMitSelection);
  Result.Mode := Analysis.Mode;
  if Analysis.Mode = msmIndents then
    Result.Checked := Analysis.Used;
  Result.FileHash := FileHash;
end;

function StatOf(const V: TArray<Double>): TMitStat;
var
  Sum, Dev: Double;
  I: Integer;
begin
  Result := Default(TMitStat);
  if Length(V) = 0 then
    Exit;
  Sum := 0;
  for I := 0 to High(V) do
    Sum := Sum + V[I];
  Result.Mean := Sum / Length(V);
  if Length(V) > 1 then
  begin
    Dev := 0;
    for I := 0 to High(V) do
      Dev := Dev + Sqr(V[I] - Result.Mean);
    Result.Std := Sqrt(Dev / (Length(V) - 1));
  end;
end;

function UsableNumbers(MitFile: TMitFile): TArray<Integer>;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to MitFile.RecordCount - 1 do
    if MitFile.Indent(I).Usable then
      Result := Result + [I + 1];
end;

function ValidateChecked(MitFile: TMitFile; const Checked: TArray<Integer>;
  out Numbers: TArray<Integer>): Boolean;
var
  Seen: TArray<Boolean>;
  N, I: Integer;
begin
  Numbers := nil;
  if Length(Checked) = 0 then
    Exit(False);
  SetLength(Seen, MitFile.RecordCount);
  for N in Checked do
  begin
    if (N < 1) or (N > MitFile.RecordCount) or Seen[N - 1] or
      not MitFile.Indent(N - 1).Usable then
      Exit(False);
    Seen[N - 1] := True;
  end;
  for I := 0 to High(Seen) do
    if Seen[I] then
      Numbers := Numbers + [I + 1];
  Result := True;
end;

function Evaluate(MitFile: TMitFile; Mode: TMitSelectionMode;
  const Numbers: TArray<Integer>; const Origin: TMitOrigin): TMitAnalysis;
var
  H, E, Er, Hc, F: TArray<Double>;
  I: Integer;
  Item: TMitIndent;
  Rec: TMitRecord;
begin
  Result := Default(TMitAnalysis);
  Result.Mode := Mode;
  Result.Origin := Origin;
  Result.Used := Numbers;
  Result.Excluded := MitFile.ExcludedCount;
  Result.Instrument := MitFile.Source = msInstrument;
  if Length(Numbers) = 0 then
    Exit;
  SetLength(H, Length(Numbers));
  SetLength(E, Length(Numbers));
  SetLength(Er, Length(Numbers));
  SetLength(Hc, Length(Numbers));
  SetLength(F, Length(Numbers));
  for I := 0 to High(Numbers) do
  begin
    Item := MitFile.Indent(Numbers[I] - 1);
    Rec := MitFile.GetRecord(Numbers[I] - 1);
    H[I] := Item.H_GPa;
    E[I] := Item.E_GPa;
    Er[I] := Item.Er_GPa;
    Hc[I] := Rec.HcNm;
    F[I] := Rec.FmaxMN;
  end;
  Result.Hardness := StatOf(H);
  Result.ReducedModulus := StatOf(Er);
  Result.ContactDepth := StatOf(Hc);
  Result.MaxForce := StatOf(F);
  Result.HasModulus := Result.Instrument;
  if Result.HasModulus then
    Result.Modulus := StatOf(E);
  Result.Available := True;
end;

function MitAnalysisFromChecked(MitFile: TMitFile; const Checked: TArray<Integer>;
  const Origin: TMitOrigin): TMitAnalysis;
var
  Numbers, All: TArray<Integer>;
  N: Integer;
begin
  Numbers := nil;
  for N in Checked do
    if (N >= 1) and (N <= MitFile.RecordCount) and MitFile.Indent(N - 1).Usable then
      Numbers := Numbers + [N];
  All := UsableNumbers(MitFile);
  if (Length(Numbers) > 0) and (Length(Numbers) = Length(All)) then
    Result := Evaluate(MitFile, msmAutomatic, All, Origin)
  else
    Result := Evaluate(MitFile, msmIndents, Numbers, Origin);
end;

function MitSelectionFits(MitFile: TMitFile; const Selection: TMitSelection): Boolean;
var
  Numbers: TArray<Integer>;
begin
  Result := (Selection.Mode = msmAutomatic) or
    ValidateChecked(MitFile, Selection.Checked, Numbers);
end;

function EvaluateSelection(MitFile: TMitFile;
  const Selection: TMitSelection): TMitAnalysis;
var
  Numbers: TArray<Integer>;
begin
  if Selection.Mode = msmAutomatic then
    Exit(Evaluate(MitFile, msmAutomatic, UsableNumbers(MitFile), Selection.Origin));
  if not ValidateChecked(MitFile, Selection.Checked, Numbers) then
  begin
    Result := Default(TMitAnalysis);
    Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
    Exit;
  end;
  Result := Evaluate(MitFile, msmIndents, Numbers, Selection.Origin);
end;

function ResolveMitAnalysis(MitFile: TMitFile;
  const Context: TAnalysisContext): TMitAnalysis;
var
  Selection: TMitSelection;
begin
  if Context.Kind = ackStoredSnapshot then
  begin
    if not TryParseStored(Context.StoredSnapshot, Selection) then
    begin
      Result := Default(TMitAnalysis);
      Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
      Exit;
    end;
    Exit(EvaluateSelection(MitFile, Selection));
  end;
  if Context.SharedSelection = '' then
    Exit(Evaluate(MitFile, msmAutomatic, UsableNumbers(MitFile), Default(TMitOrigin)));
  Result := Default(TMitAnalysis);
  if not TryParseMitSelection(Context.SharedSelection, Selection) then
  begin
    Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
    Exit;
  end;
  if (Selection.FileHash <> '') and not SameText(Selection.FileHash, Context.FileHash) then
  begin
    Result.Status := ANALYSIS_STATUS_STALE_SELECTION;
    Exit;
  end;
  Result := EvaluateSelection(MitFile, Selection);
end;

function MitKeyHasSnapshot(const KeyName: string): Boolean;
var
  Base: string;
begin
  if KeyName = MitKeyIndentCount then
    Exit(True);
  for Base in SnapshotKeys do
    if (KeyName = Base) or (KeyName = Base + ' STD') then
      Exit(True);
  Result := False;
end;

function BuildMitSnapshot(const Context: TAnalysisContext; const KeyName: string;
  const Analysis: TMitAnalysis): string;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  N: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', TJSONNumber.Create(MitSchemaVersion));
    Obj.AddPair('reader_id', MitReaderId);
    Obj.AddPair('reader_version', MitReaderVersion);
    Obj.AddPair('algorithm_version', MitAlgorithmVersion);
    Obj.AddPair('key_name', KeyName);
    Obj.AddPair('file_id', TJSONNumber.Create(Context.FileId));
    Obj.AddPair('file_hash', Context.FileHash);
    Obj.AddPair('mode', ModeNames[Analysis.Mode]);
    if Analysis.Mode = msmIndents then
    begin
      Arr := TJSONArray.Create;
      Obj.AddPair('checked', Arr);
      for N in Analysis.Used do
        Arr.Add(N);
    end;
    if Analysis.Origin.Present then
    begin
      Obj.AddPair('shared_revision', TJSONNumber.Create(Analysis.Origin.Revision));
      Obj.AddPair('shared_apply_id', Analysis.Origin.ApplyId);
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function MitKeyValues(const Analysis: TMitAnalysis): TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  Count: Integer;
  Basis, Source: string;

  procedure Add(const AName: string; AValue: Double; const AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean; const ADescription: string);
  var
    KV: TPluginKeyValue;
  begin
    KV.Name := AName;
    KV.Value := AValue;
    KV.Units := AUnits;
    KV.RecType := ARecType;
    KV.IsKey := AIsKey;
    KV.Description := ADescription;
    List.Add(KV);
  end;

begin
  Result := nil;
  if not Analysis.Available then
    Exit;
  Count := Length(Analysis.Used);
  Basis := Format('Mean of %d indents', [Count]);
  if Analysis.Instrument then
    Source := 'instrument'
  else
    Source := 'computed from the measured peak force';
  List := TList<TPluginKeyValue>.Create;
  try
    Add(MitKeyHardness, Analysis.Hardness.Mean, 'GPa', prResult, True,
      Format('%s; hardness H (%s)', [Basis, Source]));
    if Analysis.HasModulus then
      Add(MitKeyModulus, Analysis.Modulus.Mean, 'GPa', prResult, True,
        Format('%s; sample modulus E (instrument)', [Basis]));
    Add(MitKeyReducedModulus, Analysis.ReducedModulus.Mean, 'GPa', prResult, False,
      Format('%s; reduced modulus Er', [Basis]));
    Add(MitKeyContactDepth, Analysis.ContactDepth.Mean, 'nm', prResult, False, Basis);
    Add(MitKeyMaxForce, Analysis.MaxForce.Mean, 'mN', prCondition, True,
      Format('%s; measured peak force', [Basis]));
    if Count > 1 then
    begin
      Add(MitKeyHardness + ' STD', Analysis.Hardness.Std, 'GPa', prResult, False,
        'Sample standard deviation over the indents');
      if Analysis.HasModulus then
        Add(MitKeyModulus + ' STD', Analysis.Modulus.Std, 'GPa', prResult, False,
          'Sample standard deviation over the indents');
      Add(MitKeyReducedModulus + ' STD', Analysis.ReducedModulus.Std, 'GPa', prResult,
        False, 'Sample standard deviation over the indents');
      Add(MitKeyContactDepth + ' STD', Analysis.ContactDepth.Std, 'nm', prResult,
        False, 'Sample standard deviation over the indents');
      Add(MitKeyMaxForce + ' STD', Analysis.MaxForce.Std, 'mN', prCondition, False,
        'Sample standard deviation over the indents');
    end;
    Add(MitKeyIndentCount, Count, '', prCondition, False, 'Indents used');
    Add(MitKeyIndentsExcluded, Analysis.Excluded, '', prCondition, False,
      'Indents of the file not usable: estimated depth or unphysical unloading fit');
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
