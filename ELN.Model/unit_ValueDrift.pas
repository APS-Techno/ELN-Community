unit unit_ValueDrift;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_Item;

type
  TReaderKeyValue = record
    Name: string;
    Value: Double;
  end;

  TReaderRun = record
    Succeeded: Boolean;
    FileMissing: Boolean;
    Error: string;
    ReaderId: string;
    ReaderVersion: string;
    Values: TArray<TReaderKeyValue>;
  end;

  // Hosts materialize the stored file and run the reader their extension
  // routing selects today, so the check compares against current behavior.
  IValueReaderRunner = interface
    ['{46ECB3B1-2116-4BCF-8970-BA4AF422F30A}']
    function Run(FileId: Int64): TReaderRun;
  end;

  TValueDriftFlag = (vdfValueChanged, vdfVersionChanged, vdfReaderChanged,
    vdfKeyMissing, vdfFileMissing, vdfReadFailed);
  TValueDriftFlags = set of TValueDriftFlag;

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
  unit_ItemTypes;

const
  DRIFT_RELATIVE_TOLERANCE = 1e-9;

function DriftFlagCode(Flag: TValueDriftFlag): string;
begin
  case Flag of
    vdfValueChanged: Result := 'value_changed';
    vdfVersionChanged: Result := 'reader_version_changed';
    vdfReaderChanged: Result := 'reader_changed';
    vdfKeyMissing: Result := 'key_missing';
    vdfFileMissing: Result := 'file_missing';
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
  out Value: Double): Boolean;
var
  KV: TReaderKeyValue;
begin
  for KV in Run.Values do
    if KV.Name = KeyName then
    begin
      Value := KV.Value;
      Exit(True);
    end;
  Result := False;
end;

function CompareValue(V: TValue; ItemId: Integer;
  const Run: TReaderRun): TValueDriftRow;
var
  Current: Double;
begin
  Result := Default(TValueDriftRow);
  Result.ValueId := V.Id;
  Result.ItemId := ItemId;
  Result.FileId := V.SourceFileId.Value;
  Result.KeyName := V.KeyName;
  Result.StoredReaderId := V.ReaderId;
  Result.StoredReaderVersion := V.ReaderVersion;
  Result.StoredValue := V.Value;
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
  if FindKey(Run, V.KeyName, Current) then
  begin
    Result.HasCurrentValue := True;
    Result.CurrentValue := Current;
    if ValuesDiffer(V.Value, Current) then
      Include(Result.Flags, vdfValueChanged);
  end
  else
    Include(Result.Flags, vdfKeyMissing);
end;

function CheckValueDrift(Manager: TObjectManager;
  const ItemIds: TArray<Integer>;
  const Runner: IValueReaderRunner): TValueDriftReport;
var
  Runs: TDictionary<Int64, TReaderRun>;
  Rows: TList<TValueDriftRow>;
  ItemId: Integer;
  Item: TItem;
  V: TValue;
  Run: TReaderRun;
  Row: TValueDriftRow;
begin
  if not Assigned(Runner) then
    raise EArgumentNilException.Create('A reader runner is required');
  Result := Default(TValueDriftReport);
  Runs := TDictionary<Int64, TReaderRun>.Create;
  Rows := TList<TValueDriftRow>.Create;
  try
    for ItemId in ItemIds do
    begin
      Item := Manager.Find<TItem>(ItemId);
      if not Assigned(Item) or Item.IsDeleted then
        Continue;
      for V in Item.Values do
      begin
        if (V.EffectiveSourceKind <> vskReader) or
          not V.SourceFileId.HasValue then
          Continue;
        if not Runs.TryGetValue(V.SourceFileId.Value, Run) then
        begin
          Run := Runner.Run(V.SourceFileId.Value);
          Runs.Add(V.SourceFileId.Value, Run);
        end;
        Inc(Result.Checked);
        Row := CompareValue(V, Item.Id, Run);
        if Row.Flags = [] then
          Inc(Result.Unchanged)
        else
          Rows.Add(Row);
      end;
    end;
    Result.Rows := Rows.ToArray;
  finally
    Rows.Free;
    Runs.Free;
  end;
end;

end.
