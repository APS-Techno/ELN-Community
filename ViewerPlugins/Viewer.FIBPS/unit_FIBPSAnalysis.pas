unit unit_FIBPSAnalysis;

interface

uses
  System.SysUtils, System.Types, System.JSON, unit_ELNPluginCore, unit_FIBPSData;

const
  FIBPSReaderId = 'aps.fibps';
  FIBPSReaderVersion = '3';
  FIBPSAlgorithmVersion = '1';
  FIBPSSchemaVersion = 1;
  FIBPSKeyStep = 'Step Height';
  FIBPSKeyStepStd = 'Step Height STD';
  FIBPSHeightMapMaxCells = 96;

type
  TFIBPSStepMode = (fsmAutomatic, fsmRegions);

  TFIBPSOrigin = record
    Present: Boolean;
    Revision: Integer;
    ApplyId: string;
  end;

  TFIBPSRegions = record
    RectA: TRect;
    RectB: TRect;
    PixW: Integer;
    PixH: Integer;
    FileHash: string;
    Origin: TFIBPSOrigin;
  end;

  TFIBPSStepAnalysis = record
    Available: Boolean;
    Status: string;
    Mode: TFIBPSStepMode;
    Step: TFIBPSStepResult;
    Origin: TFIBPSOrigin;
  end;

function TryParseRegions(const Json: string; out Regions: TFIBPSRegions): Boolean;
function RegionsFitMap(const Regions: TFIBPSRegions; Data: TFIBPSData): Boolean;
function RegionsToSelectionJson(const Regions: TFIBPSRegions; Revision, AppliedBy: Integer;
  const ApplyId, AppliedAt: string): string;
function BuildStepSnapshot(const Context: TAnalysisContext; Data: TFIBPSData;
  const Analysis: TFIBPSStepAnalysis): string;
function ResolveFIBPSStep(Data: TFIBPSData;
  const Context: TAnalysisContext): TFIBPSStepAnalysis;
function RegionsAnalysis(Data: TFIBPSData; const RectA, RectB: TRect;
  const Origin: TFIBPSOrigin): TFIBPSStepAnalysis;
function HeightMapJson(Data: TFIBPSData): TJSONObject;

implementation

uses
  System.Math, unit_ELNPluginTypes;

function HeightMapJson(Data: TFIBPSData): TJSONObject;
var
  W, H, Stride, Cols, Rows, I, J, X, Y, Cnt: Integer;
  PA, PB, PC, Sum, Z: Double;
  XArr, YArr, Grid, Row: TJSONArray;
begin
  W := Integer(Data.PixW);
  H := Integer(Data.PixH);
  Stride := Max(1, Ceil(Max(W, H) / FIBPSHeightMapMaxCells));
  Cols := Ceil(W / Stride);
  Rows := Ceil(H / Stride);
  Data.CalcGlobalPlane(PA, PB, PC);
  Result := TJSONObject.Create;
  Result.AddPair('pix_w', TJSONNumber.Create(W));
  Result.AddPair('pix_h', TJSONNumber.Create(H));
  Result.AddPair('stride', TJSONNumber.Create(Stride));
  Result.AddPair('units', 'um');
  Result.AddPair('levelling', 'least-squares plane of the whole map subtracted');
  XArr := TJSONArray.Create;
  Result.AddPair('x_px', XArr);
  for J := 0 to Cols - 1 do
    XArr.Add(J * Stride);
  YArr := TJSONArray.Create;
  Result.AddPair('y_px', YArr);
  for I := 0 to Rows - 1 do
    YArr.Add(I * Stride);
  Grid := TJSONArray.Create;
  Result.AddPair('z_um', Grid);
  for I := 0 to Rows - 1 do
  begin
    Row := TJSONArray.Create;
    Grid.AddElement(Row);
    for J := 0 to Cols - 1 do
    begin
      Sum := 0;
      Cnt := 0;
      for Y := I * Stride to Min(H, (I + 1) * Stride) - 1 do
        for X := J * Stride to Min(W, (J + 1) * Stride) - 1 do
        begin
          Z := Data.HeightAt(X, Y);
          if not IsNan(Z) then
          begin
            Sum := Sum + Z - (PA * X + PB * Y + PC);
            Inc(Cnt);
          end;
        end;
      if Cnt = 0 then
        Row.AddElement(TJSONNull.Create)
      else
        Row.AddElement(JNum(Sum / Cnt));
    end;
  end;
end;

const
  ModeNames: array[TFIBPSStepMode] of string = ('automatic', 'regions');

function GetNumber(Obj: TJSONObject; const Name: string; out V: Double): Boolean;
var
  Field: TJSONValue;
begin
  Field := Obj.GetValue(Name);
  Result := (Field is TJSONNumber) and
    TryStrToFloat(Field.Value, V, TFormatSettings.Invariant) and
    not IsNan(V) and not IsInfinite(V);
end;

function GetInteger(Obj: TJSONObject; const Name: string; out V: Integer): Boolean;
var
  F: Double;
begin
  Result := GetNumber(Obj, Name, F) and (Frac(F) = 0) and (Abs(F) < MaxInt);
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

function GetRect(Obj: TJSONObject; const Name: string; out R: TRect): Boolean;
var
  Field: TJSONValue;
  Arr: TJSONArray;
  V: array[0..3] of Double;
  I: Integer;
begin
  Field := Obj.GetValue(Name);
  Result := (Field is TJSONArray) and (TJSONArray(Field).Count = 4);
  if not Result then
    Exit;
  Arr := TJSONArray(Field);
  for I := 0 to 3 do
    if not (Arr.Items[I] is TJSONNumber) or
      not TryStrToFloat(Arr.Items[I].Value, V[I], TFormatSettings.Invariant) or
      (Frac(V[I]) <> 0) or (Abs(V[I]) >= MaxInt) then
      Exit(False);
  R := Rect(Trunc(V[0]), Trunc(V[1]), Trunc(V[2]), Trunc(V[3]));
end;

function RectArray(const R: TRect): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(R.Left).Add(R.Top).Add(R.Right).Add(R.Bottom);
end;

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

function ParseOptionalHeader(Obj: TJSONObject): Boolean;
var
  Schema: Integer;
  Text: string;
begin
  Result := False;
  if Obj.GetValue('schema_version') <> nil then
    if not GetInteger(Obj, 'schema_version', Schema) or (Schema <> FIBPSSchemaVersion) then
      Exit;
  if Obj.GetValue('reader_id') <> nil then
    if not GetText(Obj, 'reader_id', Text) or (Text <> FIBPSReaderId) then
      Exit;
  Result := True;
end;

function ParseRegionFields(Obj: TJSONObject; out Regions: TFIBPSRegions): Boolean;
begin
  Result := GetRect(Obj, 'rect_a', Regions.RectA) and
    GetRect(Obj, 'rect_b', Regions.RectB) and
    GetInteger(Obj, 'pix_w', Regions.PixW) and
    GetInteger(Obj, 'pix_h', Regions.PixH);
end;

function TryParseRegions(const Json: string; out Regions: TFIBPSRegions): Boolean;
var
  Obj: TJSONObject;
  Text: string;
begin
  Result := False;
  Regions := Default(TFIBPSRegions);
  Obj := ParseObject(Json);
  if Obj = nil then
    Exit(False);
  try
    Result := ParseOptionalHeader(Obj) and ParseRegionFields(Obj, Regions);
    if not Result then
      Exit;
    if Obj.GetValue('mode') <> nil then
      if not GetText(Obj, 'mode', Text) or (Text <> ModeNames[fsmRegions]) then
        Exit(False);
    if Obj.GetValue('file_hash') <> nil then
      if not GetText(Obj, 'file_hash', Regions.FileHash) then
        Exit(False);
    if GetInteger(Obj, 'revision', Regions.Origin.Revision) and
      GetText(Obj, 'apply_id', Regions.Origin.ApplyId) then
      Regions.Origin.Present := True;
  finally
    Obj.Free;
    if not Result then
      Regions := Default(TFIBPSRegions);
  end;
end;

function RectFits(const R: TRect; W, H: Integer): Boolean;
begin
  Result := (R.Left >= 0) and (R.Top >= 0) and (R.Right < W) and (R.Bottom < H) and
    (R.Left < R.Right) and (R.Top < R.Bottom);
end;

function RegionsFitMap(const Regions: TFIBPSRegions; Data: TFIBPSData): Boolean;
begin
  Result := (Regions.PixW = Integer(Data.PixW)) and (Regions.PixH = Integer(Data.PixH)) and
    RectFits(Regions.RectA, Regions.PixW, Regions.PixH) and
    RectFits(Regions.RectB, Regions.PixW, Regions.PixH);
end;

function RegionsToSelectionJson(const Regions: TFIBPSRegions; Revision, AppliedBy: Integer;
  const ApplyId, AppliedAt: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', TJSONNumber.Create(FIBPSSchemaVersion));
    Obj.AddPair('reader_id', FIBPSReaderId);
    Obj.AddPair('mode', ModeNames[fsmRegions]);
    Obj.AddPair('rect_a', RectArray(Regions.RectA));
    Obj.AddPair('rect_b', RectArray(Regions.RectB));
    Obj.AddPair('pix_w', TJSONNumber.Create(Regions.PixW));
    Obj.AddPair('pix_h', TJSONNumber.Create(Regions.PixH));
    Obj.AddPair('file_hash', Regions.FileHash);
    Obj.AddPair('apply_id', ApplyId);
    Obj.AddPair('applied_at', AppliedAt);
    Obj.AddPair('applied_by', TJSONNumber.Create(AppliedBy));
    Obj.AddPair('revision', TJSONNumber.Create(Revision));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function BuildStepSnapshot(const Context: TAnalysisContext; Data: TFIBPSData;
  const Analysis: TFIBPSStepAnalysis): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema_version', TJSONNumber.Create(FIBPSSchemaVersion));
    Obj.AddPair('reader_id', FIBPSReaderId);
    Obj.AddPair('reader_version', FIBPSReaderVersion);
    Obj.AddPair('algorithm_version', FIBPSAlgorithmVersion);
    Obj.AddPair('key_name', FIBPSKeyStep);
    Obj.AddPair('file_id', TJSONNumber.Create(Context.FileId));
    Obj.AddPair('file_hash', Context.FileHash);
    Obj.AddPair('mode', ModeNames[Analysis.Mode]);
    if Analysis.Mode = fsmRegions then
    begin
      Obj.AddPair('rect_a', RectArray(Analysis.Step.RectA));
      Obj.AddPair('rect_b', RectArray(Analysis.Step.RectB));
      Obj.AddPair('pix_w', TJSONNumber.Create(Integer(Data.PixW)));
      Obj.AddPair('pix_h', TJSONNumber.Create(Integer(Data.PixH)));
      if Analysis.Origin.Present then
      begin
        Obj.AddPair('shared_revision', TJSONNumber.Create(Analysis.Origin.Revision));
        Obj.AddPair('shared_apply_id', Analysis.Origin.ApplyId);
      end;
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function RegionsAnalysis(Data: TFIBPSData; const RectA, RectB: TRect;
  const Origin: TFIBPSOrigin): TFIBPSStepAnalysis;
begin
  Result := Default(TFIBPSStepAnalysis);
  Result.Mode := fsmRegions;
  Result.Origin := Origin;
  Result.Available := Data.CalcStepFromRects(RectA, RectB, Result.Step);
  if not Result.Available then
    Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
end;

function ResolveStored(Data: TFIBPSData; const Json: string): TFIBPSStepAnalysis;
var
  Obj: TJSONObject;
  ModeText: string;
  Regions: TFIBPSRegions;
  Schema: Integer;
begin
  Result := Default(TFIBPSStepAnalysis);
  Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
  Obj := ParseObject(Json);
  if Obj = nil then
    Exit;
  try
    if not GetInteger(Obj, 'schema_version', Schema) or (Schema <> FIBPSSchemaVersion) or
      not GetText(Obj, 'mode', ModeText) then
      Exit;
    if ModeText = ModeNames[fsmAutomatic] then
    begin
      Result.Status := '';
      Result.Mode := fsmAutomatic;
      Result.Available := Data.TryCalcStepHeightEx(Result.Step);
      Exit;
    end;
    if ModeText <> ModeNames[fsmRegions] then
      Exit;
    Regions := Default(TFIBPSRegions);
    if not ParseRegionFields(Obj, Regions) or not RegionsFitMap(Regions, Data) then
      Exit;
    if GetInteger(Obj, 'shared_revision', Regions.Origin.Revision) and
      GetText(Obj, 'shared_apply_id', Regions.Origin.ApplyId) then
      Regions.Origin.Present := True;
  finally
    Obj.Free;
  end;
  Result := RegionsAnalysis(Data, Regions.RectA, Regions.RectB, Regions.Origin);
end;

function ResolveFIBPSStep(Data: TFIBPSData;
  const Context: TAnalysisContext): TFIBPSStepAnalysis;
var
  Regions: TFIBPSRegions;
begin
  if Context.Kind = ackStoredSnapshot then
    Exit(ResolveStored(Data, Context.StoredSnapshot));
  Result := Default(TFIBPSStepAnalysis);
  if Context.SharedSelection <> '' then
  begin
    if not TryParseRegions(Context.SharedSelection, Regions) then
    begin
      Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
      Exit;
    end;
    if (Regions.FileHash <> '') and not SameText(Regions.FileHash, Context.FileHash) then
    begin
      Result.Status := ANALYSIS_STATUS_STALE_SELECTION;
      Exit;
    end;
    if not RegionsFitMap(Regions, Data) then
    begin
      Result.Status := ANALYSIS_STATUS_INTERVAL_UNUSABLE;
      Exit;
    end;
    Exit(RegionsAnalysis(Data, Regions.RectA, Regions.RectB, Regions.Origin));
  end;
  Result.Mode := fsmAutomatic;
  Result.Available := Data.TryCalcStepHeightEx(Result.Step);
end;

end.
