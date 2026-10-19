unit unit_ZRWAnalysis;

interface

uses
  System.SysUtils, unit_ELNPluginCore, unit_ZRWData, unit_ZRWPlateau;

const
  ZRWReaderId = ZRWSelectionReaderId;
  ZRWReaderVersion = '2';
  ZRWAlgorithmVersion = '3';
  ZRWKeyCof = 'COF';
  ZRWKeyCofStd = 'COF STD';

type
  TZRWAnalysis = record
    Available: Boolean;
    Status: string;
    Interval: TZRWInterval;
    Mode: TZRWSelectionMode;
    Stats: TZRWStats;
    Snapshot: string;
  end;

function ResolveZRWAnalysis(const Curve: TZRWCurve;
  const Context: TAnalysisContext): TZRWAnalysis;

implementation

uses
  System.JSON;

type
  TSharedOrigin = record
    Present: Boolean;
    Revision: Integer;
    ApplyId: string;
  end;

function BuildSnapshot(const Context: TAnalysisContext; Mode: TZRWSelectionMode;
  const Interval: TZRWInterval; Count: Integer;
  const Shared: TSharedOrigin): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', TJSONNumber.Create(ZRWSelectionSchemaVersion));
    Obj.AddPair('reader_id', ZRWReaderId);
    Obj.AddPair('reader_version', ZRWReaderVersion);
    Obj.AddPair('algorithm_version', ZRWAlgorithmVersion);
    Obj.AddPair('key_name', ZRWKeyCof);
    Obj.AddPair('file_id', TJSONNumber.Create(Context.FileId));
    Obj.AddPair('file_hash', Context.FileHash);
    Obj.AddPair('mode', SelectionModeName(Mode));
    Obj.AddPair('start', TJSONNumber.Create(NumberText(Interval.StartCycle)));
    Obj.AddPair('end', TJSONNumber.Create(NumberText(Interval.EndCycle)));
    Obj.AddPair('through_end', TJSONBool.Create(Interval.ThroughEnd));
    if Mode = zsmAutomatic then
    begin
      Obj.AddPair('min_duration', TJSONNumber.Create(NumberText(MinDurationFraction)));
      Obj.AddPair('band', TJSONNumber.Create(NumberText(BandFraction)));
      Obj.AddPair('coverage', TJSONNumber.Create(NumberText(CoverageFraction)));
      Obj.AddPair('window', TJSONNumber.Create(NumberText(WindowFraction)));
      Obj.AddPair('truncation', TJSONNumber.Create(NumberText(TruncationFraction)));
      Obj.AddPair('local_window', TJSONNumber.Create(NumberText(LocalMinimumFraction)));
    end;
    Obj.AddPair('count', TJSONNumber.Create(Count));
    if Shared.Present then
    begin
      Obj.AddPair('shared_revision', TJSONNumber.Create(Shared.Revision));
      Obj.AddPair('shared_apply_id', Shared.ApplyId);
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function TryParseStoredSnapshot(const Json: string; out Mode: TZRWSelectionMode;
  out Interval: TZRWInterval; out Shared: TSharedOrigin): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Item: TJSONValue;
  ModeText, ApplyId: string;
  Revision, SchemaVersion: Double;

  function GetNum(const Name: string; out V: Double): Boolean;
  var
    Field: TJSONValue;
  begin
    Field := Obj.GetValue(Name);
    Result := (Field is TJSONNumber) and
      TryStrToFloat(Field.ToString, V, TFormatSettings.Invariant);
  end;

begin
  Mode := zsmAutomatic;
  Interval := Default(TZRWInterval);
  Shared := Default(TSharedOrigin);
  Result := False;
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(Json);
    except
      Root := nil;
    end;
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    if not GetNum('schema_version', SchemaVersion) or
      (SchemaVersion <> ZRWSelectionSchemaVersion) then
      Exit;
    Item := Obj.GetValue('mode');
    if not (Item is TJSONString) then
      Exit;
    ModeText := TJSONString(Item).Value;
    if not TryParseSelectionMode(ModeText, Mode) then
      Exit;
    if not (GetNum('start', Interval.StartCycle) and
      GetNum('end', Interval.EndCycle)) then
      Exit;
    Item := Obj.GetValue('through_end');
    if not (Item is TJSONBool) then
      Exit;
    Interval.ThroughEnd := TJSONBool(Item).AsBoolean;
    if GetNum('shared_revision', Revision) and (Frac(Revision) = 0) then
    begin
      Item := Obj.GetValue('shared_apply_id');
      if Item is TJSONString then
      begin
        ApplyId := TJSONString(Item).Value;
        Shared.Present := True;
        Shared.Revision := Trunc(Revision);
        Shared.ApplyId := ApplyId;
      end;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function ResolveZRWAnalysis(const Curve: TZRWCurve;
  const Context: TAnalysisContext): TZRWAnalysis;
var
  Selection: TZRWSelection;
  Shared: TSharedOrigin;
begin
  Result := Default(TZRWAnalysis);
  Shared := Default(TSharedOrigin);
  if Context.Kind = ackStoredSnapshot then
  begin
    if not TryParseStoredSnapshot(Context.StoredSnapshot, Result.Mode,
      Result.Interval, Shared) then
    begin
      Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
      Exit;
    end;
  end
  else if Context.SharedSelection <> '' then
  begin
    if not TryParseSelection(Context.SharedSelection, Selection) then
    begin
      Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
      Exit;
    end;
    if not SameText(Selection.FileHash, Context.FileHash) then
    begin
      Result.Status := ANALYSIS_STATUS_STALE_SELECTION;
      Exit;
    end;
    Result.Mode := Selection.Mode;
    Result.Interval := Selection.Interval;
    Shared.Present := True;
    Shared.Revision := Selection.Revision;
    Shared.ApplyId := Selection.ApplyId;
  end
  else
  begin
    if DetectPlateau(Curve, Result.Interval) <> zdrFound then
    begin
      Result.Status := ANALYSIS_STATUS_NO_PLATEAU;
      Exit;
    end;
    Result.Mode := zsmAutomatic;
  end;
  try
    Result.Stats := IntervalStats(Curve, Result.Interval);
  except
    on EZRWFormatError do
    begin
      Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
      Exit;
    end;
  end;
  Result.Snapshot := BuildSnapshot(Context, Result.Mode, Result.Interval,
    Result.Stats.Count, Shared);
  Result.Available := True;
end;

end.
