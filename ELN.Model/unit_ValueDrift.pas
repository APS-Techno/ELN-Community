unit unit_ValueDrift;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_Item,
  unit_ItemTypes;

const
  DRIFT_STATUS_INTERVAL_UNUSABLE = 'interval_unusable';

type
  TReaderKeyValue = record
    Name: string;
    Value: Double;
    Units: string;
  end;

  TReaderRun = record
    Succeeded: Boolean;
    FileMissing: Boolean;
    Error: string;
    ReaderId: string;
    ReaderVersion: string;
    Values: TArray<TReaderKeyValue>;
    CurrentFileHash: string;
    AnalysisStatus: string;
    SnapshotKeys: TArray<string>;
  end;

  // Hosts materialize the stored file and run the reader their extension
  // routing selects today, so the check compares against current behavior.
  IValueReaderRunner = interface
    ['{46ECB3B1-2116-4BCF-8970-BA4AF422F30A}']
    function Run(FileId: Int64; const AnalysisSnapshot: string): TReaderRun;
  end;

  TValueDriftFlag = (vdfValueChanged, vdfVersionChanged, vdfReaderChanged,
    vdfKeyMissing, vdfFileMissing, vdfReadFailed, vdfUnitsChanged,
    vdfSourceChanged, vdfSelectionChanged, vdfIntervalUnusable,
    vdfFormulaVersionChanged, vdfFormulaVersionMismatch, vdfInputMissing,
    vdfInputChanged, vdfNotFullyRerunnable, vdfDependencyCycle);
  TValueDriftFlags = set of TValueDriftFlag;

  TValueDriftInput = record
    Role: string;
    ValueId: Integer;
    SourceKind: TValueSourceKind;
    UsedValue: Double;
    HasCurrentValue: Boolean;
    CurrentValue: Double;
    Status: string;
  end;

  TValueDriftRow = record
    ValueId: Integer;
    ItemId: Integer;
    FileId: Int64;
    KeyName: string;
    StoredReaderId: string;
    StoredReaderVersion: string;
    CurrentReaderId: string;
    CurrentReaderVersion: string;
    StoredValue: Double;
    HasCurrentValue: Boolean;
    CurrentValue: Double;
    Flags: TValueDriftFlags;
    Message: string;
    SourceKind: TValueSourceKind;
    FormulaId: string;
    StoredFormulaVersion: Integer;
    CurrentFormulaVersion: Integer;
    Inputs: TArray<TValueDriftInput>;
  end;

  TValueDriftReport = record
    Checked: Integer;
    Unchanged: Integer;
    Rows: TArray<TValueDriftRow>;
  end;

function DriftFlagCode(Flag: TValueDriftFlag): string;
function DriftFlagsText(Flags: TValueDriftFlags): string;

function CheckValueDrift(Manager: TObjectManager;
  const ItemIds: TArray<Integer>;
  const Runner: IValueReaderRunner): TValueDriftReport;

implementation

uses
  System.Math,
  System.JSON,
  unit_AnalysisSettingsModel,
  unit_DerivedFormulas;

const
  DRIFT_RELATIVE_TOLERANCE = 1e-9;

type
  TAnalysisInterval = record
    Mode: string;
    HasStart: Boolean;
    Start: Double;
    HasStop: Boolean;
    Stop: Double;
    HasThroughEnd: Boolean;
    ThroughEnd: Boolean;
    FileHash: string;
  end;

function DriftFlagCode(Flag: TValueDriftFlag): string;
begin
  case Flag of
    vdfValueChanged: Result := 'value_changed';
    vdfVersionChanged: Result := 'reader_version_changed';
    vdfReaderChanged: Result := 'reader_changed';
    vdfKeyMissing: Result := 'key_missing';
    vdfFileMissing: Result := 'file_missing';
    vdfUnitsChanged: Result := 'reader_units_changed';
    vdfSourceChanged: Result := 'source_changed';
    vdfSelectionChanged: Result := 'selection_changed';
    vdfIntervalUnusable: Result := 'interval_unusable';
    vdfFormulaVersionChanged: Result := 'formula_version_changed';
    vdfFormulaVersionMismatch: Result := 'formula_version_mismatch';
    vdfInputMissing: Result := 'input_missing';
    vdfInputChanged: Result := 'input_changed';
    vdfNotFullyRerunnable: Result := 'not_fully_rerunnable';
    vdfDependencyCycle: Result := 'dependency_cycle';
  else
    Result := 'read_failed';
  end;
end;

function DriftFlagsText(Flags: TValueDriftFlags): string;
var
  Flag: TValueDriftFlag;
begin
  Result := '';
  for Flag := Low(TValueDriftFlag) to High(TValueDriftFlag) do
    if Flag in Flags then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + DriftFlagCode(Flag);
    end;
end;

function ValuesDiffer(A, B: Double): Boolean;
begin
  Result := not SameValue(A, B,
    Max(Abs(A), Abs(B)) * DRIFT_RELATIVE_TOLERANCE);
end;

function FindKey(const Run: TReaderRun; const KeyName: string;
  out Value: Double; out Units: string): Boolean;
var
  KV: TReaderKeyValue;
begin
  for KV in Run.Values do
    if KV.Name = KeyName then
    begin
      Value := KV.Value;
      Units := KV.Units;
      Exit(True);
    end;
  Result := False;
end;

function HasCurrentSnapshot(const Run: TReaderRun; const KeyName: string): Boolean;
var
  Key: string;
begin
  for Key in Run.SnapshotKeys do
    if Key = KeyName then
      Exit(True);
  Result := False;
end;

function ParseInterval(const Json: string; out Interval: TAnalysisInterval): Boolean;
var
  Root: TJSONValue;
  Field: TJSONValue;
begin
  Interval := Default(TAnalysisInterval);
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Result := Root is TJSONObject;
    if not Result then
      Exit;
    Field := TJSONObject(Root).GetValue('mode');
    if Field is TJSONString then
      Interval.Mode := Field.Value;
    Field := TJSONObject(Root).GetValue('file_hash');
    if Field is TJSONString then
      Interval.FileHash := Field.Value;
    Field := TJSONObject(Root).GetValue('start');
    Interval.HasStart := (Field is TJSONNumber) and
      TryStrToFloat(Field.Value, Interval.Start, TFormatSettings.Invariant);
    Field := TJSONObject(Root).GetValue('end');
    Interval.HasStop := (Field is TJSONNumber) and
      TryStrToFloat(Field.Value, Interval.Stop, TFormatSettings.Invariant);
    Field := TJSONObject(Root).GetValue('through_end');
    Interval.HasThroughEnd := Field is TJSONBool;
    if Interval.HasThroughEnd then
      Interval.ThroughEnd := TJSONBool(Field).AsBoolean;
  finally
    Root.Free;
  end;
end;

function SameInterval(const A, B: TAnalysisInterval): Boolean;
begin
  Result := (A.Mode = B.Mode) and
    (A.HasStart = B.HasStart) and (not A.HasStart or (A.Start = B.Start)) and
    (A.HasStop = B.HasStop) and (not A.HasStop or (A.Stop = B.Stop)) and
    (A.HasThroughEnd = B.HasThroughEnd) and
    (not A.HasThroughEnd or (A.ThroughEnd = B.ThroughEnd));
end;

function SelectionChanged(Settings: TAnalysisSettingsModel; V: TValue;
  const Stored: TAnalysisInterval): Boolean;
var
  SelectionJson: string;
  Shared: TAnalysisInterval;
begin
  if not Settings.LoadSelection(V.ReaderId, V.SourceFileId.Value,
    SelectionJson) then
    Exit(not SameText(Stored.Mode, 'automatic'));
  Result := not ParseInterval(SelectionJson, Shared) or
    not SameInterval(Stored, Shared);
end;

function ReadProvenance(const Json: string; out Revision: Int64;
  out ApplyId: string): Boolean;
var
  Root: TJSONValue;
  RevField, IdField: TJSONValue;
begin
  Revision := 0;
  ApplyId := '';
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Result := False;
    if not (Root is TJSONObject) then
      Exit;
    RevField := TJSONObject(Root).GetValue('shared_revision');
    if RevField = nil then
      RevField := TJSONObject(Root).GetValue('revision');
    IdField := TJSONObject(Root).GetValue('shared_apply_id');
    if IdField = nil then
      IdField := TJSONObject(Root).GetValue('apply_id');
    Result := (RevField is TJSONNumber) and (IdField is TJSONString) and
      TryStrToInt64(RevField.Value, Revision);
    if Result then
      ApplyId := IdField.Value;
  finally
    Root.Free;
  end;
end;

function ProvenanceChanged(Settings: TAnalysisSettingsModel; V: TValue;
  const SnapshotJson: string): Boolean;
var
  Root: TJSONValue;
  Tagged: Boolean;
  SnapRevision, SharedRevision: Int64;
  SnapApplyId, SharedApplyId, SelectionJson: string;
begin
  Root := TJSONObject.ParseJSONValue(SnapshotJson);
  try
    Tagged := (Root is TJSONObject) and
      (TJSONObject(Root).GetValue('shared_revision') <> nil) and
      (TJSONObject(Root).GetValue('shared_apply_id') <> nil);
  finally
    Root.Free;
  end;
  if not Tagged then
    Exit(False);
  if not ReadProvenance(SnapshotJson, SnapRevision, SnapApplyId) then
    Exit(True);
  if not Settings.LoadSelection(V.ReaderId, V.SourceFileId.Value,
    SelectionJson) then
    Exit(True);
  Result := not ReadProvenance(SelectionJson, SharedRevision, SharedApplyId) or
    (SharedRevision <> SnapRevision) or (SharedApplyId <> SnapApplyId);
end;

function CompareValue(V: TValue; ItemId: Integer; const Run: TReaderRun;
  const SnapshotJson: string; Settings: TAnalysisSettingsModel): TValueDriftRow;
var
  Current: Double;
  Units: string;
  Stored: TAnalysisInterval;
  HasSnapshot: Boolean;
  IsInterval: Boolean;
begin
  Result := Default(TValueDriftRow);
  Result.ValueId := V.Id;
  Result.ItemId := ItemId;
  Result.FileId := V.SourceFileId.Value;
  Result.KeyName := V.KeyName;
  Result.StoredReaderId := V.ReaderId;
  Result.StoredReaderVersion := V.ReaderVersion;
  Result.StoredValue := V.Value;
  Result.SourceKind := vskReader;
  if not Run.Succeeded then
  begin
    if Run.FileMissing then
      Include(Result.Flags, vdfFileMissing)
    else
      Include(Result.Flags, vdfReadFailed);
    Result.Message := Run.Error;
    Exit;
  end;
  Result.CurrentReaderId := Run.ReaderId;
  Result.CurrentReaderVersion := Run.ReaderVersion;
  if not SameText(Run.ReaderId, V.ReaderId) then
    Include(Result.Flags, vdfReaderChanged)
  else if Run.ReaderVersion <> V.ReaderVersion then
    Include(Result.Flags, vdfVersionChanged);
  HasSnapshot := (SnapshotJson <> '') and ParseInterval(SnapshotJson, Stored);
  IsInterval := HasSnapshot and Stored.HasStart and Stored.HasStop;
  if HasSnapshot then
  begin
    if (Stored.FileHash <> '') and
      not SameText(Stored.FileHash, Run.CurrentFileHash) then
      Include(Result.Flags, vdfSourceChanged);
    if IsInterval then
    begin
      if SelectionChanged(Settings, V, Stored) then
        Include(Result.Flags, vdfSelectionChanged);
    end
    else if ProvenanceChanged(Settings, V, SnapshotJson) then
      Include(Result.Flags, vdfSelectionChanged);
    if Run.AnalysisStatus = DRIFT_STATUS_INTERVAL_UNUSABLE then
    begin
      Include(Result.Flags, vdfIntervalUnusable);
      Result.Message := 'The stored analysis interval cannot be used for the current file';
      Exit;
    end;
  end
  else if HasCurrentSnapshot(Run, V.KeyName) then
  begin
    Include(Result.Flags, vdfIntervalUnusable);
    Result.Message := 'The value has no stored calculation context';
    Exit;
  end;
  if FindKey(Run, V.KeyName, Current, Units) then
  begin
    if V.ReaderUnits.HasValue and (Units <> V.ReaderUnits.Value) then
    begin
      Include(Result.Flags, vdfUnitsChanged);
      Result.Message := 'Reader output unit differs from the saved source unit';
      Exit;
    end;
    if V.ConversionFactor.HasValue then
      Current := Current * V.ConversionFactor.Value;
    Result.HasCurrentValue := True;
    Result.CurrentValue := Current;
    if ValuesDiffer(V.Value, Current) then
      Include(Result.Flags, vdfValueChanged);
  end
  else
    Include(Result.Flags, vdfKeyMissing);
end;

type
  TDerivedEvaluation = record
    HasValue: Boolean;
    Value: Double;
    Rerunnable: Boolean;
    Flags: TValueDriftFlags;
    Problem: string;
  end;

  TDriftChecker = class
  private
    FManager: TObjectManager;
    FRunner: IValueReaderRunner;
    FRuns: TDictionary<string, TReaderRun>;
    FSettings: TAnalysisSettingsModel;
    function ReaderRow(V: TValue; ItemId: Integer): TValueDriftRow;
    function CurrentNumber(V: TValue; Visiting: TList<Integer>): TDerivedEvaluation;
    function EvaluateDerived(V: TValue; Visiting: TList<Integer>): TDerivedEvaluation;
  public
    constructor Create(Manager: TObjectManager; const Runner: IValueReaderRunner);
    destructor Destroy; override;
    function DerivedRow(V: TValue; ItemId: Integer): TValueDriftRow;
    function IsReaderValue(V: TValue): Boolean;
    function CheckReader(V: TValue; ItemId: Integer): TValueDriftRow;
  end;

function LinksOf(V: TValue; const Role: string): TArray<TDerivedValueInput>;
var
  Link: TDerivedValueInput;
begin
  Result := nil;
  for Link in V.DerivedInputs do
    if Link.Role = Role then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Link;
    end;
end;

procedure AddProblem(var Text: string; const Problem: string);
begin
  if Problem = '' then
    Exit;
  if Text <> '' then
    Text := Text + '; ';
  Text := Text + Problem;
end;

constructor TDriftChecker.Create(Manager: TObjectManager;
  const Runner: IValueReaderRunner);
begin
  inherited Create;
  FManager := Manager;
  FRunner := Runner;
  FRuns := TDictionary<string, TReaderRun>.Create;
  FSettings := TAnalysisSettingsModel.Create(Manager);
end;

destructor TDriftChecker.Destroy;
begin
  FSettings.Free;
  FRuns.Free;
  inherited;
end;

function TDriftChecker.IsReaderValue(V: TValue): Boolean;
begin
  Result := (V.EffectiveSourceKind = vskReader) and V.SourceFileId.HasValue;
end;

function TDriftChecker.ReaderRow(V: TValue; ItemId: Integer): TValueDriftRow;
var
  SnapshotJson, RunKey: string;
  Run: TReaderRun;
begin
  if not FSettings.LoadSnapshot(V, SnapshotJson) then
    SnapshotJson := '';
  RunKey := IntToStr(V.SourceFileId.Value) + '|' + SnapshotJson;
  if not FRuns.TryGetValue(RunKey, Run) then
  begin
    Run := FRunner.Run(V.SourceFileId.Value, SnapshotJson);
    FRuns.Add(RunKey, Run);
  end;
  Result := CompareValue(V, ItemId, Run, SnapshotJson, FSettings);
end;

function TDriftChecker.CheckReader(V: TValue; ItemId: Integer): TValueDriftRow;
begin
  Result := ReaderRow(V, ItemId);
end;

function TDriftChecker.CurrentNumber(V: TValue;
  Visiting: TList<Integer>): TDerivedEvaluation;
var
  Row: TValueDriftRow;
begin
  Result := Default(TDerivedEvaluation);
  Result.Rerunnable := True;
  if IsReaderValue(V) then
  begin
    Row := ReaderRow(V, 0);
    Result.HasValue := Row.HasCurrentValue;
    Result.Value := Row.CurrentValue;
    if not Row.HasCurrentValue then
    begin
      Include(Result.Flags, vdfReadFailed);
      Result.Problem := Format('Reader input value %d cannot be re-read (%s)',
        [V.Id, DriftFlagsText(Row.Flags)]);
      if Row.Message <> '' then
        Result.Problem := Result.Problem + ': ' + Row.Message;
    end;
  end
  else if V.EffectiveSourceKind = vskDerived then
    Result := EvaluateDerived(V, Visiting)
  else
  begin
    Result.HasValue := True;
    Result.Value := V.Value;
    Result.Rerunnable := False;
  end;
end;

function TDriftChecker.EvaluateDerived(V: TValue;
  Visiting: TList<Integer>): TDerivedEvaluation;
var
  Formula: TDerivedFormula;
  Role: TDerivedFormulaRole;
  Link: TDerivedValueInput;
  Input: TValue;
  Nested: TDerivedEvaluation;
  Numbers: TArray<Double>;
  I: Integer;
  Links: TArray<TDerivedValueInput>;
  Sum: Double;
begin
  Result := Default(TDerivedEvaluation);
  Result.Rerunnable := True;
  if Visiting.Contains(V.Id) then
  begin
    Include(Result.Flags, vdfDependencyCycle);
    Result.Problem := Format('Derived value %d depends on itself', [V.Id]);
    Exit;
  end;
  if not V.FormulaId.HasValue or not V.FormulaVersion.HasValue or
    not TryGetDerivedFormula(V.FormulaId.Value, V.FormulaVersion.Value, Formula) then
  begin
    Include(Result.Flags, vdfFormulaVersionMismatch);
    Result.Problem := Format('Derived input value %d uses formula %s version %d, ' +
      'which is not available', [V.Id, V.FormulaId.ValueOrDefault,
      V.FormulaVersion.ValueOrDefault]);
    Exit;
  end;
  Visiting.Add(V.Id);
  try
    SetLength(Numbers, Length(Formula.Roles));
    for I := 0 to High(Formula.Roles) do
    begin
      Role := Formula.Roles[I];
      Links := LinksOf(V, Role.Name);
      if Length(Links) = 0 then
      begin
        Include(Result.Flags, vdfInputMissing);
        AddProblem(Result.Problem, Format('Input for role %s of Derived value %d is missing',
          [Role.Name, V.Id]));
        Exit;
      end;
      Sum := 0;
      for Link in Links do
      begin
        Input := FManager.Find<TValue>(Link.InputValueId);
        if Input = nil then
        begin
          Include(Result.Flags, vdfInputMissing);
          AddProblem(Result.Problem, Format('Input for role %s of Derived value %d is missing',
            [Role.Name, V.Id]));
          Exit;
        end;
        Nested := CurrentNumber(Input, Visiting);
        Result.Flags := Result.Flags + Nested.Flags;
        Result.Rerunnable := Result.Rerunnable and Nested.Rerunnable;
        AddProblem(Result.Problem, Nested.Problem);
        if not Nested.HasValue then
          Exit;
        Sum := Sum + Nested.Value;
      end;
      Numbers[I] := Sum / Length(Links);
    end;
    try
      Result.Value := Formula.Evaluate(Numbers);
      Result.HasValue := True;
    except
      on E: EDerivedValueError do
      begin
        Include(Result.Flags, vdfReadFailed);
        AddProblem(Result.Problem, Format('Derived value %d cannot be recomputed: %s',
          [V.Id, E.Message]));
      end;
    end;
  finally
    Visiting.Remove(V.Id);
  end;
end;

function TDriftChecker.DerivedRow(V: TValue; ItemId: Integer): TValueDriftRow;
var
  Formula, Current: TDerivedFormula;
  Inputs: TList<TValueDriftInput>;
  Entry: TValueDriftInput;
  Role: TDerivedFormulaRole;
  Link: TDerivedValueInput;
  Input: TValue;
  Eval: TDerivedEvaluation;
  Visiting: TList<Integer>;
  Numbers: TArray<Double>;
  Complete, RoleComplete: Boolean;
  Links: TArray<TDerivedValueInput>;
  Sum: Double;
  ManualRoles: string;
  I: Integer;
begin
  Result := Default(TValueDriftRow);
  Result.ValueId := V.Id;
  Result.ItemId := ItemId;
  Result.StoredValue := V.Value;
  Result.SourceKind := vskDerived;
  Result.FormulaId := V.FormulaId.ValueOrDefault;
  Result.StoredFormulaVersion := V.FormulaVersion.ValueOrDefault;
  Result.KeyName := Result.FormulaId;
  Result.StoredReaderId := Result.FormulaId;
  Result.StoredReaderVersion := IntToStr(Result.StoredFormulaVersion);
  if TryGetCurrentDerivedFormula(Result.FormulaId, Current) then
  begin
    Result.CurrentFormulaVersion := Current.Version;
    Result.CurrentReaderId := Current.Id;
    Result.CurrentReaderVersion := IntToStr(Current.Version);
  end;
  if not TryGetDerivedFormula(Result.FormulaId, Result.StoredFormulaVersion, Formula) then
  begin
    Include(Result.Flags, vdfFormulaVersionMismatch);
    if Result.CurrentFormulaVersion > 0 then
      Result.Message := Format('Formula %s version %d is not available (available: ' +
        'version %d); the value was not recomputed',
        [Result.FormulaId, Result.StoredFormulaVersion, Result.CurrentFormulaVersion])
    else
      Result.Message := Format('Formula %s version %d is not available; the value ' +
        'was not recomputed', [Result.FormulaId, Result.StoredFormulaVersion]);
    Exit;
  end;
  if Result.CurrentFormulaVersion > Formula.Version then
  begin
    Include(Result.Flags, vdfFormulaVersionChanged);
    AddProblem(Result.Message, Format('Formula %s has version %d; the value was ' +
      'recomputed with its saved version %d',
      [Formula.Id, Result.CurrentFormulaVersion, Formula.Version]));
  end;
  Inputs := TList<TValueDriftInput>.Create;
  Visiting := TList<Integer>.Create;
  try
    Visiting.Add(V.Id);
    SetLength(Numbers, Length(Formula.Roles));
    Complete := True;
    ManualRoles := '';
    for I := 0 to High(Formula.Roles) do
    begin
      Role := Formula.Roles[I];
      Links := LinksOf(V, Role.Name);
      if Length(Links) = 0 then
      begin
        Entry := Default(TValueDriftInput);
        Entry.Role := Role.Name;
        Entry.Status := 'missing';
        Include(Result.Flags, vdfInputMissing);
        AddProblem(Result.Message, Format('Input value %d (role %s) is missing',
          [Entry.ValueId, Role.Name]));
        Inputs.Add(Entry);
        Complete := False;
        Continue;
      end;
      Sum := 0;
      RoleComplete := True;
      for Link in Links do
      begin
        Entry := Default(TValueDriftInput);
        Entry.Role := Role.Name;
        Entry.ValueId := Link.InputValueId;
        Entry.UsedValue := Link.InputValue;
        Input := FManager.Find<TValue>(Link.InputValueId);
        if Input = nil then
        begin
          Entry.Status := 'missing';
          Include(Result.Flags, vdfInputMissing);
          AddProblem(Result.Message, Format('Input value %d (role %s) is missing',
            [Entry.ValueId, Role.Name]));
          Inputs.Add(Entry);
          RoleComplete := False;
          Continue;
        end;
        Entry.SourceKind := Input.EffectiveSourceKind;
        if not RoleMatches(Input, Role) then
        begin
          Entry.Status := 'changed';
          Include(Result.Flags, vdfInputChanged);
          AddProblem(Result.Message, Format('Input value %d (role %s) no longer has ' +
            'value type %s (%s)', [Input.Id, Role.Name, Role.TypeTitle, Role.Units]));
          Inputs.Add(Entry);
          RoleComplete := False;
          Continue;
        end;
        Eval := CurrentNumber(Input, Visiting);
        Result.Flags := Result.Flags + Eval.Flags;
        AddProblem(Result.Message, Eval.Problem);
        Entry.HasCurrentValue := Eval.HasValue;
        Entry.CurrentValue := Eval.Value;
        if not Eval.HasValue then
        begin
          Entry.Status := 'unavailable';
          RoleComplete := False;
        end
        else if ValuesDiffer(Link.InputValue, Eval.Value) then
        begin
          Entry.Status := 'changed';
          Include(Result.Flags, vdfInputChanged);
        end
        else
          Entry.Status := 'unchanged';
        if not Eval.Rerunnable then
        begin
          Include(Result.Flags, vdfNotFullyRerunnable);
          if Entry.Status = 'unchanged' then
            Entry.Status := 'not_rerunnable';
          if Pos(Role.Name, ManualRoles) = 0 then
          begin
            if ManualRoles <> '' then
              ManualRoles := ManualRoles + ', ';
            ManualRoles := ManualRoles + Role.Name;
          end;
        end;
        Sum := Sum + Eval.Value;
        Inputs.Add(Entry);
      end;
      if RoleComplete then
        Numbers[I] := Sum / Length(Links)
      else
        Complete := False;
    end;
    Result.Inputs := Inputs.ToArray;
    if ManualRoles <> '' then
      AddProblem(Result.Message, 'Not fully re-runnable: a Manual or Unknown value ' +
        'is in the input tree of ' + ManualRoles);
    if Complete then
      try
        Result.CurrentValue := Formula.Evaluate(Numbers);
        Result.HasCurrentValue := True;
        if ValuesDiffer(V.Value, Result.CurrentValue) then
          Include(Result.Flags, vdfValueChanged);
      except
        on E: EDerivedValueError do
        begin
          Include(Result.Flags, vdfReadFailed);
          AddProblem(Result.Message, 'The value cannot be recomputed: ' + E.Message);
        end;
      end;
  finally
    Visiting.Free;
    Inputs.Free;
  end;
end;

function CheckValueDrift(Manager: TObjectManager;
  const ItemIds: TArray<Integer>;
  const Runner: IValueReaderRunner): TValueDriftReport;
var
  Checker: TDriftChecker;
  Rows: TList<TValueDriftRow>;
  ItemId: Integer;
  Item: TItem;
  V: TValue;
  Row: TValueDriftRow;
begin
  if not Assigned(Runner) then
    raise EArgumentNilException.Create('A reader runner is required');
  Result := Default(TValueDriftReport);
  Rows := TList<TValueDriftRow>.Create;
  Checker := TDriftChecker.Create(Manager, Runner);
  try
    for ItemId in ItemIds do
    begin
      Item := Manager.Find<TItem>(ItemId);
      if not Assigned(Item) or Item.IsDeleted then
        Continue;
      for V in Item.Values do
      begin
        if Checker.IsReaderValue(V) then
          Row := Checker.CheckReader(V, Item.Id)
        else if V.EffectiveSourceKind = vskDerived then
          Row := Checker.DerivedRow(V, Item.Id)
        else
          Continue;
        Inc(Result.Checked);
        if Row.Flags = [] then
          Inc(Result.Unchanged)
        else
          Rows.Add(Row);
      end;
    end;
    Result.Rows := Rows.ToArray;
  finally
    Checker.Free;
    Rows.Free;
  end;
end;

end.
