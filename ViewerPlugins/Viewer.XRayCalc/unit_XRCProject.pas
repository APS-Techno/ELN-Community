unit unit_XRCProject;

interface

uses
  System.SysUtils;

type
  TXRCParam = (xpThickness, xpRoughness, xpDensity);

  TXRCFitFlags = record
    Fixed, Paired: Boolean;
    Min, Max: Double;
  end;

  TXRCProfileKind = (pkNone, pkPolynomial, pkTable);

  TXRCProfile = record
    Kind: TXRCProfileKind;
    Coefficients: TArray<Double>;
    Values: TArray<Single>;
  end;

  TXRCLayer = record
    Material: string;
    Value: array[TXRCParam] of Double;
    Fit: array[TXRCParam] of TXRCFitFlags;
    HasFit: Boolean;
    Profile: array[TXRCParam] of TXRCProfile;
  end;

  TXRCStack = record
    Title: string;
    N: Integer;
    Layers: TArray<TXRCLayer>;
  end;

  TXRCModelSource = (msNone, msProjectTree, msLegacyJson, msLegacyBin);

  TXRCModel = record
    Valid: Boolean;
    Source: TXRCModelSource;
    Title: string;
    Stacks: TArray<TXRCStack>;
    SubsMaterial: string;
    SubsSigma, SubsRho: Double;
  end;

  TXRCCurveRole = (crCalculated, crMeasured, crUnknown);

  TXRCCurve = record
    FileName, Title: string;
    Role: TXRCCurveRole;
    Linked: Boolean;
    X, Y: TArray<Double>;
  end;

  TXRCCalcMode = (cmTheta, cmWavelength);

  TXRCCalculation = record
    Present: Boolean;
    Mode: TXRCCalcMode;
    WavelengthA, ResolutionDeg, ThetaMinDeg, ThetaMaxDeg: Double;
    Points: Integer;
    PolarizationSP: Boolean;
  end;

  TXRCFitMode = (fmIrregular, fmPeriodic, fmProfile);

  TXRCFitSettings = record
    Present: Boolean;
    Mode: TXRCFitMode;
    PolyOrder, Iterations, Population: Integer;
    Tolerance: Double;
    FreePeriod: Boolean;
    PeriodWindowPct: Double;
    SolveScale: Boolean;
    ScaleWindow: Double;
    ThetaWeight: Integer;
    PointWeight: Boolean;
    Window: Double;
  end;

  TXRCFitResult = record
    Present: Boolean;
    Chi2, Chi2Plain, ScaleRatio: Double;
    Chi2Scale, Mode, Date, AppVersion: string;
    Seed: Int64;
    ScaleClamped: Boolean;
  end;

  TXRCInvertedRange = record
    Stack, Layer: Integer;
    Param: TXRCParam;
  end;

  TXRCProject = record
    FormatVersion: Integer;
    ChartLogScale: Boolean;
    ChartMinLimit: Double;
    Calculation: TXRCCalculation;
    FitSettings: TXRCFitSettings;
    FitResult: TXRCFitResult;
    Model: TXRCModel;
    Curves: TArray<TXRCCurve>;
    CurvesInTwoTheta: Boolean;
    InvertedRanges: TArray<TXRCInvertedRange>;
  end;

function LoadXRCProject(const FileName: string): TXRCProject;
function XRCProfileValue(const Layer: TXRCLayer; Param: TXRCParam; Period: Integer): Double;

implementation

uses
  System.Classes, System.Zip, System.IniFiles, System.JSON, System.Character,
  System.Generics.Collections;

type
  EXRCFormat = class(Exception);

  TTreeRecord = record
    Loaded: Boolean;
    Parent: Integer;
    ID: Integer;
    Title: string;
    RowType, Group, Enabled, ExtType, Form, Subj: Byte;
    LayerID, StackID: Integer;
    Coefs: TArray<Single>;
    Data: string;
  end;

const
  ChunkNode = 1;
  ChunkBase = 2;
  ChunkCaption = 3;
  ChunkUser = 4;
  BaseChunkBody = 19;
  RowItem = 1;
  RowExtension = 3;
  GroupModel = 0;
  GroupData = 1;
  ExtFunction = 1;
  FormPoly = 1;
  ParamKey: array[TXRCParam] of string = ('H', 's', 'r');
  ParamFlag: array[TXRCParam] of string = ('H', 'S', 'R');

function ParseFloat(const S: string; out V: Double): Boolean;
begin
  Result := TryStrToFloat(StringReplace(Trim(S), ',', '.', []), V, TFormatSettings.Invariant);
end;

function IniFloat(Ini: TMemIniFile; const Section, Key: string; Default: Double): Double;
begin
  if not ParseFloat(Ini.ReadString(Section, Key, ''), Result) then
    Result := Default;
end;

function IniBool(Ini: TMemIniFile; const Section, Key: string; Default: Boolean): Boolean;
var
  S: string;
begin
  S := LowerCase(Trim(Ini.ReadString(Section, Key, '')));
  if (S = '1') or (S = 'true') or (S = 'yes') then
    Result := True
  else if (S = '0') or (S = 'false') or (S = 'no') then
    Result := False
  else
    Result := Default;
end;

function IniInt(Ini: TMemIniFile; const Section, Key: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(Trim(Ini.ReadString(Section, Key, '')), Default);
end;

procedure ReadParams(const Bytes: TBytes; var P: TXRCProject;
  out ActiveID, LinkedID: Integer);
var
  Ini: TMemIniFile;
  List: TStringList;
  Mode, Offset: Integer;
  Lo, Hi: Double;
  Encoding: TEncoding;
begin
  List := TStringList.Create;
  Ini := TMemIniFile.Create('');
  try
    Encoding := nil;
    Offset := TEncoding.GetBufferEncoding(Bytes, Encoding, TEncoding.UTF8);
    List.Text := Encoding.GetString(Bytes, Offset, Length(Bytes) - Offset);
    Ini.SetStrings(List);

    P.FormatVersion := IniInt(Ini, 'INFO', 'Version', 0);
    ActiveID := IniInt(Ini, 'STATE', 'ActiveModel', -1);
    LinkedID := IniInt(Ini, 'STATE', 'LinkedData', -1);
    P.ChartLogScale := IniBool(Ini, 'STATE', 'LogScale', True);
    P.ChartMinLimit := IniFloat(Ini, 'PARAMS', 'MinLimit', 1E-7);

    P.Calculation.Present := True;
    if IniInt(Ini, 'PARAMS', 'Mode', 0) = 1 then
      P.Calculation.Mode := cmWavelength
    else
      P.Calculation.Mode := cmTheta;
    P.Calculation.WavelengthA := IniFloat(Ini, 'ANGLE', 'lambbda', 1.54043);
    P.Calculation.ResolutionDeg := IniFloat(Ini, 'ANGLE', 'width', 0);
    Lo := IniFloat(Ini, 'ANGLE', 'Start', 0);
    Hi := IniFloat(Ini, 'ANGLE', 'End', 0);
    P.CurvesInTwoTheta := IniBool(Ini, 'ANGLE', '2teta', False);
    if P.CurvesInTwoTheta then
    begin
      Lo := Lo / 2;
      Hi := Hi / 2;
    end;
    P.Calculation.ThetaMinDeg := Lo;
    P.Calculation.ThetaMaxDeg := Hi;
    P.Calculation.Points := IniInt(Ini, 'PARAMS', 'N', 1000);
    P.Calculation.PolarizationSP := IniInt(Ini, 'PARAMS', 'Polarisation', 0) = 1;

    P.FitSettings.Present := True;
    Mode := IniInt(Ini, 'FIT', 'Mode', -1);
    case Mode of
      0: P.FitSettings.Mode := fmIrregular;
      1: P.FitSettings.Mode := fmPeriodic;
      2: P.FitSettings.Mode := fmProfile;
    else
      if IniBool(Ini, 'FIT', 'Poly', False) then
        P.FitSettings.Mode := fmProfile
      else if IniBool(Ini, 'FIT', 'Periodic', False) then
        P.FitSettings.Mode := fmPeriodic
      else
        P.FitSettings.Mode := fmIrregular;
    end;
    P.FitSettings.PolyOrder := IniInt(Ini, 'FIT', 'PolyOrder', 1);
    P.FitSettings.Iterations := IniInt(Ini, 'FIT', 'Namx', 100);
    P.FitSettings.Population := IniInt(Ini, 'FIT', 'Pop', 1000);
    P.FitSettings.Tolerance := IniFloat(Ini, 'FIT', 'Tol', 0.005);
    P.FitSettings.FreePeriod := IniBool(Ini, 'FIT', 'FreePeriod', False);
    P.FitSettings.PeriodWindowPct := IniFloat(Ini, 'FIT', 'PeriodWindow', 10);
    P.FitSettings.SolveScale := IniBool(Ini, 'FIT', 'SolveScale', True);
    P.FitSettings.ScaleWindow := IniFloat(Ini, 'FIT', 'ScaleWindow', 0.2);
    P.FitSettings.ThetaWeight := IniInt(Ini, 'FIT', 'TWChi', 0);
    P.FitSettings.PointWeight := IniBool(Ini, 'FIT', 'PWChi', True);
    P.FitSettings.Window := IniFloat(Ini, 'FIT', 'Window', 0.05);

    P.FitResult.Present := Ini.SectionExists('FITRESULT');
    if P.FitResult.Present then
    begin
      P.FitResult.Chi2 := IniFloat(Ini, 'FITRESULT', 'chiSquared', 0);
      P.FitResult.Chi2Plain := IniFloat(Ini, 'FITRESULT', 'chiSquaredPlain', 0);
      P.FitResult.ScaleRatio := IniFloat(Ini, 'FITRESULT', 'scaleRatio', 1);
      P.FitResult.Chi2Scale := Ini.ReadString('FITRESULT', 'chi2Scale', '');
      P.FitResult.Mode := Ini.ReadString('FITRESULT', 'fittingMode', '');
      P.FitResult.Date := Ini.ReadString('FITRESULT', 'fitDate', '');
      P.FitResult.AppVersion := Ini.ReadString('FITRESULT', 'version', '');
      P.FitResult.Seed := StrToInt64Def(Trim(Ini.ReadString('FITRESULT', 'seed', '')), 0);
      P.FitResult.ScaleClamped := IniBool(Ini, 'FITRESULT', 'scaleClamped', False);
    end;
  finally
    Ini.Free;
    List.Free;
  end;
end;

procedure Need(Pos, Count, Limit: Integer); inline;
begin
  if (Count < 0) or (Pos < 0) or (Pos > Limit) or (Count > Limit - Pos) then
    raise EXRCFormat.Create('project.dsc truncated');
end;

function TreeInt(const B: TBytes; var Pos: Integer; Limit: Integer): Integer;
begin
  Need(Pos, 4, Limit);
  Move(B[Pos], Result, 4);
  Inc(Pos, 4);
end;

function TreeByte(const B: TBytes; var Pos: Integer; Limit: Integer): Byte;
begin
  Need(Pos, 1, Limit);
  Result := B[Pos];
  Inc(Pos);
end;

function TreeStr(const B: TBytes; var Pos: Integer; Limit: Integer): string;
var
  Size: Integer;
begin
  Size := TreeInt(B, Pos, Limit);
  if (Size < 1) or not Odd(Size) then
    raise EXRCFormat.Create('bad string size');
  Need(Pos, Size, Limit);
  if Size > 1 then
    Result := TEncoding.Unicode.GetString(B, Pos, Size - 1)
  else
    Result := '';
  Inc(Pos, Size);
end;

procedure ReadUserChunk(const B: TBytes; Pos, Limit: Integer; var R: TTreeRecord);
var
  Order, I: Integer;
  F: Single;
begin
  R.ID := TreeInt(B, Pos, Limit);
  R.Title := TreeStr(B, Pos, Limit);
  R.RowType := TreeByte(B, Pos, Limit);
  R.Group := TreeByte(B, Pos, Limit);
  TreeByte(B, Pos, Limit);
  TreeByte(B, Pos, Limit);
  TreeStr(B, Pos, Limit);
  TreeInt(B, Pos, Limit);
  R.Enabled := TreeByte(B, Pos, Limit);
  R.ExtType := TreeByte(B, Pos, Limit);
  R.LayerID := TreeInt(B, Pos, Limit);
  R.StackID := TreeInt(B, Pos, Limit);
  R.Form := TreeByte(B, Pos, Limit);
  R.Subj := TreeByte(B, Pos, Limit);
  if (R.Group = GroupModel) and (R.RowType = RowExtension) then
  begin
    Order := TreeInt(B, Pos, Limit);
    if (Order < 0) or (Order > 9) then
      raise EXRCFormat.Create('bad extension order');
    SetLength(R.Coefs, Order);
    for I := 0 to Order - 1 do
    begin
      Need(Pos, 4, Limit);
      Move(B[Pos], F, 4);
      R.Coefs[I] := F;
      Inc(Pos, 4);
    end;
  end
  else if (R.Group = GroupModel) and (R.RowType = RowItem) then
    R.Data := TreeStr(B, Pos, Limit);
  R.Loaded := True;
end;

function ReadTreeNode(const B: TBytes; Pos, Limit, Parent: Integer;
  Records: TList<TTreeRecord>): Integer;
var
  Kind, Size, NodeEnd, BaseEnd, Children, Child, I, Idx, ChunkEnd: Integer;
  R: TTreeRecord;
begin
  Kind := TreeInt(B, Pos, Limit);
  Size := TreeInt(B, Pos, Limit);
  if (Kind <> ChunkNode) or (Size < 0) then
    raise EXRCFormat.Create('node chunk expected');
  Need(Pos, Size, Limit);
  NodeEnd := Pos + Size;

  Kind := TreeInt(B, Pos, NodeEnd);
  Size := TreeInt(B, Pos, NodeEnd);
  if (Kind <> ChunkBase) or (Size < BaseChunkBody) then
    raise EXRCFormat.Create('base chunk expected');
  Need(Pos, Size, NodeEnd);
  BaseEnd := Pos + Size;
  Children := TreeInt(B, Pos, BaseEnd);
  Child := Pos - 4 + BaseChunkBody;

  R := Default(TTreeRecord);
  R.Parent := Parent;
  Idx := Records.Add(R);
  for I := 1 to Children do
    Child := ReadTreeNode(B, Child, BaseEnd, Idx, Records);
  if Child <> BaseEnd then
    raise EXRCFormat.Create('children size mismatch');

  Pos := BaseEnd;
  while Pos < NodeEnd do
  begin
    Kind := TreeInt(B, Pos, NodeEnd);
    Size := TreeInt(B, Pos, NodeEnd);
    if ((Kind <> ChunkCaption) and (Kind <> ChunkUser)) or (Size < 0) then
      raise EXRCFormat.Create('caption or user chunk expected');
    Need(Pos, Size, NodeEnd);
    ChunkEnd := Pos + Size;
    if Kind = ChunkUser then
    begin
      R := Records[Idx];
      ReadUserChunk(B, Pos, ChunkEnd, R);
      Records[Idx] := R;
    end;
    Pos := ChunkEnd;
  end;
  Result := NodeEnd;
end;

function ReadTree(const B: TBytes): TArray<TTreeRecord>;
const
  Magic: string = #$2045'VT'#3' '#$2046;
var
  M: TBytes;
  Records: TList<TTreeRecord>;
  Pos, Count, I: Integer;
begin
  M := TEncoding.Unicode.GetBytes(Magic);
  if (Length(B) < Length(M) + 4) or not CompareMem(@B[0], @M[0], Length(M)) then
    raise EXRCFormat.Create('not a VirtualTreeView stream');
  Pos := Length(M);
  Count := TreeInt(B, Pos, Length(B));
  Records := TList<TTreeRecord>.Create;
  try
    for I := 1 to Count do
      Pos := ReadTreeNode(B, Pos, Length(B), -1, Records);
    if Pos <> Length(B) then
      raise EXRCFormat.Create('bytes after tree');
    Result := Records.ToArray;
  finally
    Records.Free;
  end;
end;

function ParseProfileTable(const S: string): TArray<Single>;
var
  Part: string;
  V: Double;
  Count: Integer;
  Parts: TArray<string>;
begin
  Result := nil;
  if Trim(S) = '' then
    Exit;
  Parts := S.Split([';']);
  SetLength(Result, Length(Parts));
  Count := 0;
  for Part in Parts do
    if ParseFloat(Part, V) then
    begin
      Result[Count] := V;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function JsonFloat(Obj: TJSONObject; const Key: string; out V: Double): Boolean;
var
  J: TJSONValue;
begin
  J := Obj.Values[Key];
  Result := False;
  if J is TJSONNumber then
  begin
    V := TJSONNumber(J).AsDouble;
    Result := True;
  end
  else if J is TJSONString then
    Result := ParseFloat(TJSONString(J).Value, V);
end;

function JsonBool(Obj: TJSONObject; const Key: string): Boolean;
var
  J: TJSONValue;
begin
  J := Obj.Values[Key];
  Result := (J is TJSONBool) and TJSONBool(J).AsBoolean;
end;

function JsonStr(Obj: TJSONObject; const Key: string): string;
var
  J: TJSONValue;
begin
  J := Obj.Values[Key];
  if J is TJSONString then
    Result := TJSONString(J).Value
  else
    Result := '';
end;

function JsonRange(Obj: TJSONObject; const Upper, Lower: string; out V: Double): Boolean;
begin
  Result := JsonFloat(Obj, Upper, V) or JsonFloat(Obj, Lower, V);
end;

function ParseLayer(Obj: TJSONObject): TXRCLayer;
const
  TableKeys: array[TXRCParam, 0..1] of string =
    (('ProfileH', 'ProfileH'), ('Profiles', 'ProfileS'), ('Profiler', 'ProfileR'));
var
  P: TXRCParam;
  V: Double;
  Table: TArray<Single>;
begin
  Result := Default(TXRCLayer);
  Result.Material := JsonStr(Obj, 'M');
  Result.HasFit := True;
  for P := Low(TXRCParam) to High(TXRCParam) do
  begin
    if JsonFloat(Obj, ParamKey[P], V) then
      Result.Value[P] := V;
    Result.Fit[P].Fixed := JsonBool(Obj, ParamFlag[P] + 'F');
    Result.Fit[P].Paired := JsonBool(Obj, ParamFlag[P] + 'P');
    if not JsonRange(Obj, ParamFlag[P] + 'min', ParamKey[P] + 'min', Result.Fit[P].Min) then
      Result.Fit[P].Min := Result.Value[P];
    if not JsonRange(Obj, ParamFlag[P] + 'max', ParamKey[P] + 'max', Result.Fit[P].Max) then
      Result.Fit[P].Max := Result.Value[P];
    Table := ParseProfileTable(JsonStr(Obj, TableKeys[P, 0]));
    if Table = nil then
      Table := ParseProfileTable(JsonStr(Obj, TableKeys[P, 1]));
    if Table <> nil then
    begin
      Result.Profile[P].Kind := pkTable;
      Result.Profile[P].Values := Table;
    end;
  end;
end;

function ParseModelJson(const Json: string; out Model: TXRCModel): Boolean;
var
  Root: TJSONValue;
  Obj, JS, Subs: TJSONObject;
  Stacks, Layers: TJSONArray;
  S, L: Integer;
  V: Double;
begin
  Model := Default(TXRCModel);
  Result := False;
  Root := TJSONObject.ParseJSONValue(Json);
  try
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    if not (Obj.Values['Stacks'] is TJSONArray) then
      Exit;
    Stacks := TJSONArray(Obj.Values['Stacks']);
    SetLength(Model.Stacks, Stacks.Count);
    for S := 0 to Stacks.Count - 1 do
    begin
      if not (Stacks.Items[S] is TJSONObject) then
        Exit;
      JS := TJSONObject(Stacks.Items[S]);
      Model.Stacks[S].Title := JsonStr(JS, 'T');
      if JsonFloat(JS, 'N', V) then
        Model.Stacks[S].N := Round(V)
      else
        Model.Stacks[S].N := 1;
      if not (JS.Values['Layers'] is TJSONArray) then
        Exit;
      Layers := TJSONArray(JS.Values['Layers']);
      SetLength(Model.Stacks[S].Layers, Layers.Count);
      for L := 0 to Layers.Count - 1 do
      begin
        if not (Layers.Items[L] is TJSONObject) then
          Exit;
        Model.Stacks[S].Layers[L] := ParseLayer(TJSONObject(Layers.Items[L]));
      end;
    end;
    if Obj.Values['Subs'] is TJSONObject then
    begin
      Subs := TJSONObject(Obj.Values['Subs']);
      Model.SubsMaterial := JsonStr(Subs, 'M');
      if JsonFloat(Subs, 's', V) then
        Model.SubsSigma := V;
      if JsonFloat(Subs, 'r', V) then
        Model.SubsRho := V;
    end;
    Model.Valid := True;
    Result := True;
  finally
    Root.Free;
  end;
end;

function ScanFirstJson(const B: TBytes): string;
var
  I, Start, Depth, Len: Integer;
begin
  Result := '';
  Len := Length(B);
  Start := -1;
  for I := 0 to Len - 6 do
    if (B[I] = $7B) and (B[I + 1] = 0) and (B[I + 2] = $22) and (B[I + 3] = 0) and
       (B[I + 4] = $53) and (B[I + 5] = 0) then
    begin
      Start := I;
      Break;
    end;
  if Start < 0 then
    Exit;
  Depth := 0;
  I := Start;
  while I < Len - 1 do
  begin
    if (B[I] = $7B) and (B[I + 1] = 0) then
      Inc(Depth)
    else if (B[I] = $7D) and (B[I + 1] = 0) then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(TEncoding.Unicode.GetString(B, Start, I - Start + 2));
    end;
    Inc(I, 2);
  end;
end;

procedure ApplyExtension(var Model: TXRCModel; const R: TTreeRecord);
var
  P: TXRCParam;
  I: Integer;
begin
  if (R.Enabled = 0) or (R.ExtType <> ExtFunction) or (R.Form <> FormPoly) then
    Exit;
  if (Integer(R.Subj) > Ord(High(TXRCParam))) or (Length(R.Coefs) = 0) then
    Exit;
  if (R.StackID < 0) or (R.StackID > High(Model.Stacks)) then
    Exit;
  if (R.LayerID < 0) or (R.LayerID > High(Model.Stacks[R.StackID].Layers)) then
    Exit;
  P := TXRCParam(R.Subj);
  with Model.Stacks[R.StackID].Layers[R.LayerID].Profile[P] do
  begin
    Kind := pkPolynomial;
    Values := nil;
    SetLength(Coefficients, Length(R.Coefs));
    for I := 0 to High(R.Coefs) do
      Coefficients[I] := R.Coefs[I];
  end;
end;

procedure ReadModelFromTree(const Records: TArray<TTreeRecord>; ActiveID: Integer;
  var Model: TXRCModel);
var
  I, Active: Integer;
begin
  Active := -1;
  for I := 0 to High(Records) do
    if Records[I].Loaded and (Records[I].Group = GroupModel) and
       (Records[I].RowType = RowItem) and (Records[I].Data <> '') then
    begin
      if Active < 0 then
        Active := I;
      if Records[I].ID = ActiveID then
      begin
        Active := I;
        Break;
      end;
    end;
  if Active < 0 then
    Exit;
  if not ParseModelJson(Records[Active].Data, Model) then
    Exit;
  Model.Source := msProjectTree;
  Model.Title := Records[Active].Title;
  for I := 0 to High(Records) do
    if Records[I].Loaded and (Records[I].Parent = Active) and
       (Records[I].Group = GroupModel) and (Records[I].RowType = RowExtension) then
      ApplyExtension(Model, Records[I]);
end;

procedure ReadModelFromBin(const Bytes: TBytes; var Model: TXRCModel);

  function ReadWStr(var Pos: Integer): string;
  var
    Sz: Cardinal;
  begin
    Result := '';
    if Pos + 4 > Length(Bytes) then
      Exit;
    Sz := PCardinal(@Bytes[Pos])^;
    Inc(Pos, 4);
    if (Sz < 1) or (Sz > 200) or (Pos + Integer(Sz) > Length(Bytes)) then
    begin
      Pos := Length(Bytes);
      Exit;
    end;
    if Bytes[Pos + Integer(Sz) - 1] = 0 then
      Result := TEncoding.Unicode.GetString(Bytes, Pos, Integer(Sz) - 1);
    Inc(Pos, Integer(Sz));
  end;

const
  rtStack = 0;
  rtLayer = 1;
  rtSubstrate = 2;
var
  I, Pos, Len, ChunkType, ChunkSize, N: Integer;
  NodeText, NodeH, NodeS, NodeR: string;
  RowType: Byte;
  V: Double;
  Pending: TList<TXRCLayer>;
  Stacks: TList<TXRCStack>;
  Layer: TXRCLayer;
  Stack: TXRCStack;
begin
  Model := Default(TXRCModel);
  Len := Length(Bytes);
  if Len < 20 then
    Exit;
  Pending := TList<TXRCLayer>.Create;
  Stacks := TList<TXRCStack>.Create;
  try
    I := 0;
    while I < Len - 12 do
    begin
      ChunkType := PInteger(@Bytes[I])^;
      ChunkSize := PInteger(@Bytes[I + 4])^;
      if (ChunkType <> ChunkUser) or (ChunkSize < 10) or (ChunkSize > 500) or
         (I + 8 + ChunkSize > Len) then
      begin
        Inc(I);
        Continue;
      end;
      Pos := I + 8;
      NodeText := ReadWStr(Pos);
      if (Pos >= Len) or (NodeText = '') then
      begin
        Inc(I);
        Continue;
      end;
      RowType := Bytes[Pos];
      Inc(Pos);
      if RowType > rtSubstrate then
      begin
        Inc(I);
        Continue;
      end;
      NodeH := ReadWStr(Pos);
      NodeS := ReadWStr(Pos);
      NodeR := ReadWStr(Pos);
      if Pos + 4 > Len then
      begin
        Inc(I);
        Continue;
      end;
      N := PInteger(@Bytes[Pos])^;
      Inc(Pos, 4);
      case RowType of
        rtLayer:
          begin
            if not ParseFloat(NodeH, V) then
            begin
              Inc(I);
              Continue;
            end;
            Layer := Default(TXRCLayer);
            Layer.Material := NodeText;
            Layer.Value[xpThickness] := V;
            if ParseFloat(NodeS, V) then
              Layer.Value[xpRoughness] := V;
            if ParseFloat(NodeR, V) then
              Layer.Value[xpDensity] := V;
            Pending.Add(Layer);
          end;
        rtStack:
          begin
            if N > 10000 then
            begin
              Inc(I);
              Continue;
            end;
            Stack := Default(TXRCStack);
            Stack.Title := NodeText;
            Stack.N := N;
            Stack.Layers := Pending.ToArray;
            Pending.Clear;
            Stacks.Add(Stack);
          end;
        rtSubstrate:
          begin
            Model.SubsMaterial := NodeText;
            if ParseFloat(NodeS, V) then
              Model.SubsSigma := V;
            if ParseFloat(NodeR, V) then
              Model.SubsRho := V;
          end;
      end;
      I := Pos;
    end;
    Model.Stacks := Stacks.ToArray;
    Model.Valid := Stacks.Count > 0;
    if Model.Valid then
      Model.Source := msLegacyBin;
  finally
    Stacks.Free;
    Pending.Free;
  end;
end;

procedure ReadCurve(const Bytes: TBytes; var Curve: TXRCCurve);
var
  Lines: TStringList;
  I, Count: Integer;
  Parts: TArray<string>;
  Line: string;
  X, Y, MinPos: Double;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := TEncoding.ANSI.GetString(Bytes);
    if (Lines.Count > 0) and (Pos('Sample', Lines[0]) > 0) then
      for I := 1 to 21 do
        if Lines.Count > 0 then
          Lines.Delete(0);
    SetLength(Curve.X, Lines.Count);
    SetLength(Curve.Y, Lines.Count);
    Count := 0;
    MinPos := 1000;
    for Line in Lines do
    begin
      if Line.Contains(#9) then
        Parts := Line.Split([#9], TStringSplitOptions.ExcludeEmpty)
      else
        Parts := Line.Split([' '], TStringSplitOptions.ExcludeEmpty);
      if Length(Parts) < 2 then
        Continue;
      if not (Parts[0].Chars[0].IsNumber and Parts[1].Chars[0].IsNumber) then
        Continue;
      if not (ParseFloat(Parts[0], X) and ParseFloat(Parts[1], Y)) then
        Continue;
      if (Y > 0) and (Y < MinPos) then
        MinPos := Y;
      if Y = 0 then
        Y := MinPos;
      Curve.X[Count] := X;
      Curve.Y[Count] := Y;
      Inc(Count);
    end;
    SetLength(Curve.X, Count);
    SetLength(Curve.Y, Count);
  finally
    Lines.Free;
  end;
end;

function DataNodeID(const EntryName: string; out ID: Integer): Boolean;
var
  Base: string;
begin
  Base := LowerCase(ChangeFileExt(ExtractFileName(EntryName), ''));
  Result := Base.StartsWith('data_') and TryStrToInt(Copy(Base, 6, MaxInt), ID);
end;

procedure ReadInvertedRanges(var P: TXRCProject);
var
  S, L: Integer;
  Par: TXRCParam;
  R: TXRCInvertedRange;
  List: TList<TXRCInvertedRange>;
begin
  List := TList<TXRCInvertedRange>.Create;
  try
    for S := 0 to High(P.Model.Stacks) do
      for L := 0 to High(P.Model.Stacks[S].Layers) do
        if P.Model.Stacks[S].Layers[L].HasFit then
          for Par := Low(TXRCParam) to High(TXRCParam) do
            if P.Model.Stacks[S].Layers[L].Fit[Par].Min > P.Model.Stacks[S].Layers[L].Fit[Par].Max then
            begin
              R.Stack := S;
              R.Layer := L;
              R.Param := Par;
              List.Add(R);
            end;
    P.InvertedRanges := List.ToArray;
  finally
    List.Free;
  end;
end;

function LoadXRCProject(const FileName: string): TXRCProject;
var
  Zip: TZipFile;
  Names: TArray<string>;
  Name: string;
  Bytes, ProjectBytes: TBytes;
  ActiveID, LinkedID, ID, I: Integer;
  Records: TArray<TTreeRecord>;
  DataTitles: TDictionary<Integer, string>;
  Curves: TList<TXRCCurve>;
  Curve: TXRCCurve;
  HaveProject, TreeOk: Boolean;
begin
  Result := Default(TXRCProject);
  Result.ChartLogScale := True;
  Result.ChartMinLimit := 1E-7;
  ActiveID := -1;
  LinkedID := -1;
  ProjectBytes := nil;
  HaveProject := False;
  Records := nil;
  DataTitles := TDictionary<Integer, string>.Create;
  Curves := TList<TXRCCurve>.Create;
  Zip := TZipFile.Create;
  try
    Zip.Open(FileName, zmRead);
    Names := Zip.FileNames;

    for Name in Names do
      if SameText(Name, 'params.dsc') then
      begin
        Zip.Read(Name, Bytes);
        ReadParams(Bytes, Result, ActiveID, LinkedID);
        Break;
      end;

    for Name in Names do
      if SameText(Name, 'project.dsc') then
      begin
        Zip.Read(Name, ProjectBytes);
        HaveProject := True;
        Break;
      end;

    if HaveProject then
    begin
      TreeOk := False;
      if Result.FormatVersion >= 6 then
        try
          Records := ReadTree(ProjectBytes);
          TreeOk := True;
        except
          on EXRCFormat do
            Records := nil;
        end;
      if TreeOk then
      begin
        for I := 0 to High(Records) do
          if Records[I].Loaded and (Records[I].Group = GroupData) and
             (Records[I].RowType = RowItem) then
            DataTitles.AddOrSetValue(Records[I].ID, Records[I].Title);
        ReadModelFromTree(Records, ActiveID, Result.Model);
      end
      else if ParseModelJson(ScanFirstJson(ProjectBytes), Result.Model) then
        Result.Model.Source := msLegacyJson;
    end;

    if not Result.Model.Valid then
      for Name in Names do
        if Name.StartsWith('model_') and SameText(ExtractFileExt(Name), '.bin') then
        begin
          Zip.Read(Name, Bytes);
          ReadModelFromBin(Bytes, Result.Model);
          if Result.Model.Valid then
            Break;
        end;

    for Name in Names do
      if SameText(ExtractFileExt(Name), '.dat') then
      begin
        Curve := Default(TXRCCurve);
        Curve.FileName := Name;
        if SameText(ExtractFileName(Name), 'calc.dat') then
          Curve.Role := crCalculated
        else if DataNodeID(Name, ID) then
        begin
          Curve.Role := crMeasured;
          DataTitles.TryGetValue(ID, Curve.Title);
          Curve.Linked := ID = LinkedID;
        end
        else
          Curve.Role := crUnknown;
        Zip.Read(Name, Bytes);
        ReadCurve(Bytes, Curve);
        Curves.Add(Curve);
      end;
    Result.Curves := Curves.ToArray;
    ReadInvertedRanges(Result);
  finally
    Zip.Free;
    Curves.Free;
    DataTitles.Free;
  end;
end;

function XRCProfileValue(const Layer: TXRCLayer; Param: TXRCParam; Period: Integer): Double;
var
  K: Integer;
  X, Term: Double;
begin
  Result := Layer.Value[Param];
  case Layer.Profile[Param].Kind of
    pkPolynomial:
      begin
        X := Period - 1;
        Term := 1;
        for K := 0 to High(Layer.Profile[Param].Coefficients) do
        begin
          Term := Term * X;
          Result := Result + Layer.Profile[Param].Coefficients[K] * Term;
        end;
      end;
    pkTable:
      if (Period >= 1) and (Period <= Length(Layer.Profile[Param].Values)) then
        Result := Layer.Profile[Param].Values[Period - 1];
  end;
end;

end.
