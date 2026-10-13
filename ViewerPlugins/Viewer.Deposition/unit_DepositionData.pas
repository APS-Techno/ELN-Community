unit unit_DepositionData;


interface

uses
  System.SysUtils, System.Classes, System.JSON,
  unit_ELNPluginTypes;

type
  // An optional numeric field from the snapshot JSON. Present=False means
  // the key was absent; Value is then 0 and must not be displayed.
  TDepoOpt = record
    Value: Double;
    Present: Boolean;
  end;

  TDepoPowerSupply = record
    Id, Model, Description: string;
    Responding: Boolean;
    Present: Boolean;
    ElnLink: string;
  end;

  TDepoSource = record
    Flange: Integer;
    Material, Format, MagnetronModel: string;
    MagnetronElnLink: string;
    Erosion: TDepoOpt;
    // Target + geometry, added by control software 1.5.0.0. All optional
    // and provenance-only (NOT fingerprinted): a fresh target of the same
    // material and format is the same reproducible condition.
    ZeroDistance: TDepoOpt;    // zeroDistanceMm - bare magnetron face to
                               // substrate at lift=0
    Lift: TDepoOpt;            // liftMm - lift gauge at run start; raising
                               // reduces the gap
    TargetThickness: TDepoOpt; // targetThicknessMm - sputterable material
    TargetBacking: TDepoOpt;   // targetBackingMm - Cu bond plate, 0 =
                               // monolithic
    TargetDistance: TDepoOpt;  // targetToSubstrateDistanceMm - effective gap,
                               // = zero - lift - (thickness + backing -
                               // erosion). May be negative when the operator
                               // enters a lift exceeding the zero distance.
    TargetLot: string;
    TargetSerial: string;
    PowerSupply: TDepoPowerSupply;
  end;

  TDepoRecipeParam = record
    Group, Name, Caption, Units, Value: string;
  end;

  TDepoMean = record
    Channel: string;
    Value: Double;
  end;

  TDepoSnapshot = class
  private
    FSchemaVer: Integer;
    FSpecimen: string;
    FFingerprint: string;
    FSignName: string;
    FSignRole: string;
    FSignIntent: string;
    FSignedAtUtc: string;
    FSoftControl: string;
    FSoftWorker: string;
    FSources: TArray<TDepoSource>;
    FRecipeName: string;
    FRecipeTitle: string;
    FRecipeScript: string;
    FRecipeParams: TArray<TDepoRecipeParam>;
    FHasOutcome: Boolean;
    FDataFileRef: string;
    FOutcomeResult: string;
    FStartedUtc: string;
    FEndedUtc: string;
    FDurationSec: Double;
    FMeans: TArray<TDepoMean>;
    FHasBasePressure: Boolean;
    FBasePressureChannel: string;
    FBasePressureUnit: string;
    FBasePressureMin: Double;

    procedure ParseRecipeXml(const Xml: string);
  public
    procedure Clear;
    function LoadFromText(const JsonText: string): Boolean;
    function LoadFromFile(const AFileName: string): Boolean;
    // MCP extraction (extract_file_data / extract_file_key_values):
    // the full snapshot as a JSON tree (caller frees), and the numeric
    // values flattened into key-value records (recipe params + erosion
    // depths = conditions; duration, base pressure, channel means =
    // results, present only for finalized runs).
    function BuildDetailedJson: TJSONObject;
    function BuildKeyValues: TArray<TPluginKeyValue>;

    property SchemaVer: Integer read FSchemaVer;
    property Specimen: string read FSpecimen;
    property Fingerprint: string read FFingerprint;
    property SignName: string read FSignName;
    property SignRole: string read FSignRole;
    property SignIntent: string read FSignIntent;
    property SignedAtUtc: string read FSignedAtUtc;
    property SoftControl: string read FSoftControl;
    property SoftWorker: string read FSoftWorker;
    property Sources: TArray<TDepoSource> read FSources;
    property RecipeName: string read FRecipeName;
    property RecipeTitle: string read FRecipeTitle;
    property RecipeScript: string read FRecipeScript;
    property RecipeParams: TArray<TDepoRecipeParam> read FRecipeParams;
    property HasOutcome: Boolean read FHasOutcome;
    property DataFileRef: string read FDataFileRef;
    property OutcomeResult: string read FOutcomeResult;
    property StartedUtc: string read FStartedUtc;
    property EndedUtc: string read FEndedUtc;
    property DurationSec: Double read FDurationSec;
    property Means: TArray<TDepoMean> read FMeans;
    property HasBasePressure: Boolean read FHasBasePressure;
    property BasePressureChannel: string read FBasePressureChannel;
    property BasePressureUnit: string read FBasePressureUnit;
    property BasePressureMin: Double read FBasePressureMin;
  end;

// Display composition for one source's target and geometry, used by the
// viewer's Overview. Pure string building, no VCL - kept here so it is
// covered by ELNTests, which cannot compile the frame.
function DepoTargetLine(const S: TDepoSource): string;
function DepoGeometryLine(const S: TDepoSource): string;

implementation

uses
  System.IOUtils, System.DateUtils, System.Variants,
  Xml.XMLDoc, Xml.XMLIntf;

// An absent key yields Present=False and Value=0; a present but non-numeric
// key yields Present=True and Value=0, matching GetValue's own default.
function ReadOpt(Obj: TJSONObject; const Name: string): TDepoOpt;
begin
  Result.Present := Obj.GetValue(Name) <> nil;
  if Result.Present then
    Result.Value := Obj.GetValue<Double>(Name, 0)
  else
    Result.Value := 0;
end;

procedure TDepoSnapshot.Clear;
begin
  FSchemaVer := 0;
  FSpecimen := '';
  FFingerprint := '';
  FSignName := '';
  FSignRole := '';
  FSignIntent := '';
  FSignedAtUtc := '';
  FSoftControl := '';
  FSoftWorker := '';
  SetLength(FSources, 0);
  FRecipeName := '';
  FRecipeTitle := '';
  FRecipeScript := '';
  SetLength(FRecipeParams, 0);
  FHasOutcome := False;
  FDataFileRef := '';
  FOutcomeResult := '';
  FStartedUtc := '';
  FEndedUtc := '';
  FDurationSec := 0;
  SetLength(FMeans, 0);
  FHasBasePressure := False;
  FBasePressureChannel := '';
  FBasePressureUnit := '';
  FBasePressureMin := 0;
end;

procedure TDepoSnapshot.ParseRecipeXml(const Xml: string);
var
  Doc: IXMLDocument;
  Root, Desc, Params, Grp, Prm, N: IXMLNode;
  G, I: Integer;
  GroupName: string;
  Rec: TDepoRecipeParam;
begin
  if Trim(Xml) = '' then Exit;
  try
    Doc := LoadXMLData(Xml);
  except
    Exit;
  end;
  Root := Doc.DocumentElement;
  if not Assigned(Root) then Exit;

  Desc := Root.ChildNodes.FindNode('Description');
  if Assigned(Desc) then
  begin
    N := Desc.ChildNodes.FindNode('Title');
    if Assigned(N) then FRecipeTitle := N.Text;
  end;

  Params := Root.ChildNodes.FindNode('Parameters');
  if Assigned(Params) then
    for G := 0 to Params.ChildNodes.Count - 1 do
    begin
      Grp := Params.ChildNodes[G];
      if not SameText(Grp.NodeName, 'Group') then Continue;
      GroupName := VarToStr(Grp.Attributes['name']);
      for I := 0 to Grp.ChildNodes.Count - 1 do
      begin
        Prm := Grp.ChildNodes[I];
        if not SameText(Prm.NodeName, 'Param') then Continue;
        Rec.Group   := GroupName;
        Rec.Name    := VarToStr(Prm.Attributes['name']);
        Rec.Caption := VarToStr(Prm.Attributes['caption']);
        Rec.Units   := VarToStr(Prm.Attributes['unit']);
        Rec.Value   := Prm.Text;
        FRecipeParams := FRecipeParams + [Rec];
      end;
    end;

  N := Root.ChildNodes.FindNode('Script');
  if Assigned(N) then
    FRecipeScript := N.Text;
end;

function TDepoSnapshot.LoadFromText(const JsonText: string): Boolean;
var
  Root, Cond, Sig, Soft, Rec, SrcObj, PsuObj: TJSONObject;
  Outc, Win, MeansObj, BaseP: TJSONObject;
  V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  P: TJSONPair;
  StartDT, EndDT: TDateTime;
begin
  Clear;
  Result := False;

  V := TJSONObject.ParseJSONValue(JsonText);
  if not (V is TJSONObject) then
  begin
    V.Free;
    Exit;
  end;
  Root := TJSONObject(V);
  try
    if Root.GetValue<string>('kind', '') <> 'deposition-snapshot' then Exit;

    FSchemaVer := Root.GetValue<Integer>('schema', 0);

    Cond := Root.GetValue<TJSONObject>('conditions', nil);
    if Assigned(Cond) then
    begin
      FFingerprint := Cond.GetValue<string>('fingerprint', '');
      FSpecimen    := Cond.GetValue<string>('specimen', '');

      Sig := Cond.GetValue<TJSONObject>('signature', nil);
      if Assigned(Sig) then
      begin
        FSignName    := Sig.GetValue<string>('name', '');
        FSignRole    := Sig.GetValue<string>('role', '');
        FSignedAtUtc := Sig.GetValue<string>('signedAtUtc', '');
        FSignIntent  := Sig.GetValue<string>('intent', '');
      end;

      Soft := Cond.GetValue<TJSONObject>('software', nil);
      if Assigned(Soft) then
      begin
        FSoftControl := Soft.GetValue<string>('control', '');
        FSoftWorker  := Soft.GetValue<string>('worker', '');
      end;

      Arr := Cond.GetValue<TJSONArray>('sources', nil);
      if Assigned(Arr) then
      begin
        SetLength(FSources, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            SrcObj := TJSONObject(Arr.Items[I]);
            FSources[I].Flange         := SrcObj.GetValue<Integer>('flange', 0);
            FSources[I].Material       := SrcObj.GetValue<string>('material', '');
            FSources[I].Format         := SrcObj.GetValue<string>('format', '');
            FSources[I].MagnetronModel := SrcObj.GetValue<string>('magnetronModel', '');
            FSources[I].MagnetronElnLink :=
              SrcObj.GetValue<string>('magnetronElnLink', '');
            FSources[I].Erosion :=
              ReadOpt(SrcObj, 'erosionDepthMm');
            FSources[I].ZeroDistance :=
              ReadOpt(SrcObj, 'zeroDistanceMm');
            FSources[I].Lift :=
              ReadOpt(SrcObj, 'liftMm');
            FSources[I].TargetThickness :=
              ReadOpt(SrcObj, 'targetThicknessMm');
            FSources[I].TargetBacking :=
              ReadOpt(SrcObj, 'targetBackingMm');
            FSources[I].TargetDistance :=
              ReadOpt(SrcObj, 'targetToSubstrateDistanceMm');
            FSources[I].TargetLot :=
              SrcObj.GetValue<string>('targetLot', '');
            FSources[I].TargetSerial :=
              SrcObj.GetValue<string>('targetSerial', '');
            PsuObj := SrcObj.GetValue<TJSONObject>('powerSupply', nil);
            FSources[I].PowerSupply.Present := Assigned(PsuObj);
            if Assigned(PsuObj) then
            begin
              FSources[I].PowerSupply.Id          := PsuObj.GetValue<string>('id', '');
              FSources[I].PowerSupply.Model       := PsuObj.GetValue<string>('model', '');
              FSources[I].PowerSupply.Description := PsuObj.GetValue<string>('description', '');
              FSources[I].PowerSupply.Responding  := PsuObj.GetValue<Boolean>('responding', False);
              FSources[I].PowerSupply.ElnLink     := PsuObj.GetValue<string>('elnLink', '');
            end;
          end;
      end;

      Rec := Cond.GetValue<TJSONObject>('recipe', nil);
      if Assigned(Rec) then
      begin
        FRecipeName := Rec.GetValue<string>('name', '');
        ParseRecipeXml(Rec.GetValue<string>('content', ''));
      end;
    end;

    // Appended at run end; absent for aborted/unfinalized runs.
    Outc := Root.GetValue<TJSONObject>('outcome', nil);
    FHasOutcome := Assigned(Outc);
    if Assigned(Outc) then
    begin
      FOutcomeResult := Outc.GetValue<string>('result', '');
      FDataFileRef   := Outc.GetValue<string>('dataFile', '');

      Win := Outc.GetValue<TJSONObject>('window', nil);
      if Assigned(Win) then
      begin
        FStartedUtc := Win.GetValue<string>('startedUtc', '');
        FEndedUtc   := Win.GetValue<string>('endedUtc', '');
        try
          StartDT := ISO8601ToDate(FStartedUtc, True);
          EndDT   := ISO8601ToDate(FEndedUtc, True);
          FDurationSec := SecondSpan(EndDT, StartDT);
        except
          FDurationSec := 0;
        end;
      end;

      MeansObj := Outc.GetValue<TJSONObject>('means', nil);
      if Assigned(MeansObj) then
      begin
        SetLength(FMeans, MeansObj.Count);
        for I := 0 to MeansObj.Count - 1 do
        begin
          P := MeansObj.Pairs[I];
          FMeans[I].Channel := P.JsonString.Value;
          if P.JsonValue is TJSONNumber then
            FMeans[I].Value := TJSONNumber(P.JsonValue).AsDouble
          else
            FMeans[I].Value := 0;
        end;
      end;

      BaseP := Outc.GetValue<TJSONObject>('basePressure', nil);
      if Assigned(BaseP) then
      begin
        FHasBasePressure     := True;
        FBasePressureChannel := BaseP.GetValue<string>('channel', '');
        FBasePressureUnit    := BaseP.GetValue<string>('unit', '');
        FBasePressureMin     := BaseP.GetValue<Double>('min', 0);
      end;
    end;

    Result := True;
  finally
    Root.Free;
  end;
end;

function TDepoSnapshot.LoadFromFile(const AFileName: string): Boolean;
var
  Text: string;
begin
  try
    Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    Exit(False);
  end;
  Result := LoadFromText(Text);
end;

// Recipe param values carry unit suffixes ('1.50mT', '350') - take the
// leading numeric part; False when there is no numeric prefix.
function TryParseLeadingFloat(const S: string; out V: Double): Boolean;
var
  T: string;
  I: Integer;
begin
  V := 0;
  T := Trim(S);
  I := 1;
  if (I <= Length(T)) and CharInSet(T[I], ['+', '-']) then Inc(I);
  while (I <= Length(T)) and CharInSet(T[I], ['0'..'9', '.']) do Inc(I);
  Result := TryStrToFloat(Copy(T, 1, I - 1), V, TFormatSettings.Invariant);
end;

function TDepoSnapshot.BuildDetailedJson: TJSONObject;
var
  JSig, JSoft, JRecipe, JSrc, JPsu, JParam: TJSONObject;
  JOutcome, JWindow, JMeans, JBase: TJSONObject;
  JSources, JParams: TJSONArray;
  Src: TDepoSource;
  P: TDepoRecipeParam;
  M: TDepoMean;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', 'deposition-snapshot');
  Result.AddPair('schema', TJSONNumber.Create(FSchemaVer));
  Result.AddPair('specimen', FSpecimen);
  Result.AddPair('fingerprint', FFingerprint);

  JSig := TJSONObject.Create;
  JSig.AddPair('name', FSignName);
  JSig.AddPair('role', FSignRole);
  JSig.AddPair('signedAtUtc', FSignedAtUtc);
  JSig.AddPair('intent', FSignIntent);
  Result.AddPair('signature', JSig);

  JSoft := TJSONObject.Create;
  JSoft.AddPair('control', FSoftControl);
  JSoft.AddPair('worker', FSoftWorker);
  Result.AddPair('software', JSoft);

  JSources := TJSONArray.Create;
  for Src in FSources do
  begin
    JSrc := TJSONObject.Create;
    JSrc.AddPair('flange', TJSONNumber.Create(Src.Flange));
    JSrc.AddPair('material', Src.Material);
    JSrc.AddPair('format', Src.Format);
    JSrc.AddPair('magnetronModel', Src.MagnetronModel);
    if Src.MagnetronElnLink <> '' then
      JSrc.AddPair('magnetronElnLink', Src.MagnetronElnLink);
    if Src.Erosion.Present then
      JSrc.AddPair('erosionDepthMm', JNum(Src.Erosion.Value));
    if Src.ZeroDistance.Present then
      JSrc.AddPair('zeroDistanceMm', JNum(Src.ZeroDistance.Value));
    if Src.Lift.Present then
      JSrc.AddPair('liftMm', JNum(Src.Lift.Value));
    if Src.TargetThickness.Present then
      JSrc.AddPair('targetThicknessMm', JNum(Src.TargetThickness.Value));
    if Src.TargetBacking.Present then
      JSrc.AddPair('targetBackingMm', JNum(Src.TargetBacking.Value));
    if Src.TargetLot <> '' then
      JSrc.AddPair('targetLot', Src.TargetLot);
    if Src.TargetSerial <> '' then
      JSrc.AddPair('targetSerial', Src.TargetSerial);
    if Src.TargetDistance.Present then
      JSrc.AddPair('targetToSubstrateDistanceMm',
        JNum(Src.TargetDistance.Value));
    if Src.PowerSupply.Present then
    begin
      JPsu := TJSONObject.Create;
      JPsu.AddPair('id', Src.PowerSupply.Id);
      JPsu.AddPair('model', Src.PowerSupply.Model);
      JPsu.AddPair('description', Src.PowerSupply.Description);
      JPsu.AddPair('responding', TJSONBool.Create(Src.PowerSupply.Responding));
      if Src.PowerSupply.ElnLink <> '' then
        JPsu.AddPair('elnLink', Src.PowerSupply.ElnLink);
      JSrc.AddPair('powerSupply', JPsu);
    end;
    JSources.AddElement(JSrc);
  end;
  Result.AddPair('sources', JSources);

  JRecipe := TJSONObject.Create;
  JRecipe.AddPair('name', FRecipeName);
  JRecipe.AddPair('title', FRecipeTitle);
  JParams := TJSONArray.Create;
  for P in FRecipeParams do
  begin
    JParam := TJSONObject.Create;
    JParam.AddPair('group', P.Group);
    JParam.AddPair('name', P.Name);
    JParam.AddPair('caption', P.Caption);
    JParam.AddPair('value', P.Value);
    JParam.AddPair('units', P.Units);
    JParams.AddElement(JParam);
  end;
  JRecipe.AddPair('params', JParams);
  JRecipe.AddPair('script', FRecipeScript);
  Result.AddPair('recipe', JRecipe);

  if FHasOutcome then
  begin
    JOutcome := TJSONObject.Create;
    JOutcome.AddPair('result', FOutcomeResult);
    if FDataFileRef <> '' then
      JOutcome.AddPair('dataFile', FDataFileRef);
    JWindow := TJSONObject.Create;
    JWindow.AddPair('startedUtc', FStartedUtc);
    JWindow.AddPair('endedUtc', FEndedUtc);
    JWindow.AddPair('durationSec', JNum(FDurationSec));
    JOutcome.AddPair('window', JWindow);
    JMeans := TJSONObject.Create;
    for M in FMeans do
      JMeans.AddPair(M.Channel, JNum(M.Value));
    JOutcome.AddPair('means', JMeans);
    if FHasBasePressure then
    begin
      JBase := TJSONObject.Create;
      JBase.AddPair('channel', FBasePressureChannel);
      JBase.AddPair('min', JNum(FBasePressureMin));
      JBase.AddPair('unit', FBasePressureUnit);
      JOutcome.AddPair('basePressure', JBase);
    end;
    Result.AddPair('outcome', JOutcome);
  end;
end;

function TDepoSnapshot.BuildKeyValues: TArray<TPluginKeyValue>;
var
  KV: TPluginKeyValue;
  P: TDepoRecipeParam;
  M: TDepoMean;
  Src: TDepoSource;
  V: Double;

  procedure Add(const AName: string; const AValue: Double;
    const AUnits, ADescription: string; ARecType: TPluginRecType;
    AIsKey: Boolean);
  begin
    KV.Name := AName;
    KV.Value := AValue;
    KV.Units := AUnits;
    KV.Description := ADescription;
    KV.RecType := ARecType;
    KV.IsKey := AIsKey;
    Result := Result + [KV];
  end;

begin
  Result := nil;

  for P in FRecipeParams do
    if TryParseLeadingFloat(P.Value, V) then
      Add(P.Group + '.' + P.Name, V, P.Units,
        P.Caption + ' (' + P.Group + ')', prCondition, True);

  for Src in FSources do
    if Src.Erosion.Present then
      Add(Format('ErosionDepth.%s.F%d', [Src.Material, Src.Flange]),
        Src.Erosion.Value, 'mm',
        Format('Target erosion depth, flange %d (%s)',
          [Src.Flange, Src.Material]), prCondition, False);

  // The effective gap is the one derived geometry number that changes the
  // film, so it is the correlate_values partner for rate calibration. Its
  // inputs (zero, lift, thickness, backing) stay in the JSON only.
  for Src in FSources do
    if Src.TargetDistance.Present then
      Add(Format('TargetDistance.%s.F%d', [Src.Material, Src.Flange]),
        Src.TargetDistance.Value, 'mm',
        Format('Target-to-substrate distance, flange %d (%s)',
          [Src.Flange, Src.Material]), prCondition, False);

  if FDurationSec > 0 then
    Add('Duration', FDurationSec, 's', 'Run duration', prResult, True);
  if FHasBasePressure then
    Add('BasePressure', FBasePressureMin, FBasePressureUnit,
      'Base pressure (' + FBasePressureChannel + ')', prResult, True);
  for M in FMeans do
    Add('Mean.' + M.Channel, M.Value, '',
      'Run-average of channel ' + M.Channel, prResult, False);
end;

// '6' not '6.000'; invariant so a comma decimal separator never leaks in.
function FmtMm(const V: Double): string;
begin
  Result := Format('%g mm', [V], TFormatSettings.Invariant);
end;

function JoinPart(const A, B, Sep: string): string;
begin
  if A = '' then Result := B
  else if B = '' then Result := A
  else Result := A + Sep + B;
end;

function DepoTargetLine(const S: TDepoSource): string;
var
  Stack: string;
begin
  Result := S.TargetSerial;
  if S.TargetLot <> '' then
    Result := JoinPart(Result, 'lot ' + S.TargetLot, ', ');

  // Thickness and backing read as one physical stack, so they join with
  // ' + ' rather than the comma used between independent facts.
  Stack := '';
  if S.TargetThickness.Present then
    Stack := FmtMm(S.TargetThickness.Value);
  if S.TargetBacking.Present then
  begin
    if S.TargetBacking.Value = 0 then
      Stack := JoinPart(Stack, 'monolithic', ', ')
    else
      Stack := JoinPart(Stack, FmtMm(S.TargetBacking.Value) + ' backing',
        ' + ');
  end;
  Result := JoinPart(Result, Stack, ', ');
end;

function DepoGeometryLine(const S: TDepoSource): string;
begin
  Result := '';
  if S.ZeroDistance.Present then
    Result := 'zero ' + FmtMm(S.ZeroDistance.Value);
  if S.Lift.Present then
    Result := JoinPart(Result, 'lift ' + FmtMm(S.Lift.Value),
      ' ' + Char($2212) + ' ');
  if S.TargetDistance.Present then
    Result := JoinPart(Result,
      Format('gap %.2f mm', [S.TargetDistance.Value],
        TFormatSettings.Invariant), ' ' + Char($2192) + ' ');
end;

end.
