unit unit_XRCProjectOutput;

interface

uses
  System.SysUtils, unit_ELNPluginTypes, unit_XRCProject;

function BuildXRCDetailedInfo(const P: TXRCProject): string;
function BuildXRCKeyValues(const P: TXRCProject): TArray<TPluginKeyValue>;

implementation

uses
  System.JSON, System.Generics.Collections, unit_LayerSequence;

const
  ParamName: array[TXRCParam] of string = ('thickness', 'roughness', 'density');
  ParamLabel: array[TXRCParam] of string = ('Thickness', 'Roughness', 'Density');
  ParamUnits: array[TXRCParam] of string = ('A', 'A', 'g/cm3');
  SourceName: array[TXRCModelSource] of string =
    ('none', 'project_tree', 'legacy_json', 'legacy_bin');
  RoleName: array[TXRCCurveRole] of string = ('calculated', 'measured', 'unknown');
  FitModeName: array[TXRCFitMode] of string = ('irregular', 'periodic', 'profile');
  ProfileKindName: array[TXRCProfileKind] of string = ('none', 'polynomial', 'table');

function StackPeriod(const Stack: TXRCStack): Double;
var
  L: Integer;
begin
  Result := 0;
  for L := 0 to High(Stack.Layers) do
    Result := Result + Stack.Layers[L].Value[xpThickness];
end;

function LayerJSON(const Layer: TXRCLayer; Index: Integer): TJSONObject;
var
  Par: TXRCParam;
  Fit, Prof, Item: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(Index));
  Result.AddPair('material', Layer.Material);
  Result.AddPair('thickness_A', JNum(Layer.Value[xpThickness]));
  Result.AddPair('roughness_A', JNum(Layer.Value[xpRoughness]));
  Result.AddPair('density_gcm3', JNum(Layer.Value[xpDensity]));
  if Layer.HasFit then
  begin
    Fit := TJSONObject.Create;
    Result.AddPair('fit', Fit);
    for Par := Low(TXRCParam) to High(TXRCParam) do
    begin
      Item := TJSONObject.Create;
      Fit.AddPair(ParamName[Par], Item);
      Item.AddPair('fixed', TJSONBool.Create(Layer.Fit[Par].Fixed));
      Item.AddPair('paired', TJSONBool.Create(Layer.Fit[Par].Paired));
      Item.AddPair('min', JNum(Layer.Fit[Par].Min));
      Item.AddPair('max', JNum(Layer.Fit[Par].Max));
    end;
  end;
  Prof := nil;
  for Par := Low(TXRCParam) to High(TXRCParam) do
  begin
    if Layer.Profile[Par].Kind = pkNone then
      Continue;
    if Prof = nil then
    begin
      Prof := TJSONObject.Create;
      Result.AddPair('profile', Prof);
    end;
    Item := TJSONObject.Create;
    Prof.AddPair(ParamName[Par], Item);
    Item.AddPair('kind', ProfileKindName[Layer.Profile[Par].Kind]);
    Arr := TJSONArray.Create;
    if Layer.Profile[Par].Kind = pkPolynomial then
    begin
      Item.AddPair('coefficients', Arr);
      for I := 0 to High(Layer.Profile[Par].Coefficients) do
        Arr.AddElement(JNum(Layer.Profile[Par].Coefficients[I]));
    end
    else
    begin
      Item.AddPair('values', Arr);
      for I := 0 to High(Layer.Profile[Par].Values) do
        Arr.AddElement(JNum(Layer.Profile[Par].Values[I]));
    end;
  end;
end;

function CalculationJSON(const C: TXRCCalculation): TJSONValue;
var
  O: TJSONObject;
begin
  if not C.Present then
    Exit(TJSONNull.Create);
  O := TJSONObject.Create;
  if C.Mode = cmWavelength then
    O.AddPair('mode', 'wavelength')
  else
    O.AddPair('mode', 'theta');
  O.AddPair('wavelength_A', JNum(C.WavelengthA));
  O.AddPair('resolution_deg', JNum(C.ResolutionDeg));
  if C.Mode = cmTheta then
  begin
    O.AddPair('theta_min_deg', JNum(C.ThetaMinDeg));
    O.AddPair('theta_max_deg', JNum(C.ThetaMaxDeg));
  end;
  O.AddPair('points', TJSONNumber.Create(C.Points));
  if C.PolarizationSP then
    O.AddPair('polarization', 'sp')
  else
    O.AddPair('polarization', 's');
  Result := O;
end;

function FitSettingsJSON(const F: TXRCFitSettings): TJSONValue;
var
  O, Chi: TJSONObject;
begin
  if not F.Present then
    Exit(TJSONNull.Create);
  O := TJSONObject.Create;
  O.AddPair('mode', FitModeName[F.Mode]);
  O.AddPair('poly_order', TJSONNumber.Create(F.PolyOrder));
  O.AddPair('iterations', TJSONNumber.Create(F.Iterations));
  O.AddPair('population', TJSONNumber.Create(F.Population));
  O.AddPair('tolerance', JNum(F.Tolerance));
  O.AddPair('free_period', TJSONBool.Create(F.FreePeriod));
  O.AddPair('period_window_pct', JNum(F.PeriodWindowPct));
  O.AddPair('solve_scale', TJSONBool.Create(F.SolveScale));
  O.AddPair('scale_window', JNum(F.ScaleWindow));
  Chi := TJSONObject.Create;
  O.AddPair('chi2', Chi);
  Chi.AddPair('theta_weight', TJSONNumber.Create(F.ThetaWeight));
  Chi.AddPair('point_weight', TJSONBool.Create(F.PointWeight));
  Chi.AddPair('window', JNum(F.Window));
  Result := O;
end;

function FitResultJSON(const R: TXRCFitResult): TJSONValue;
var
  O: TJSONObject;
begin
  if not R.Present then
    Exit(TJSONNull.Create);
  O := TJSONObject.Create;
  O.AddPair('chi2', JNum(R.Chi2));
  O.AddPair('chi2_plain', JNum(R.Chi2Plain));
  O.AddPair('chi2_scale', R.Chi2Scale);
  O.AddPair('scale_ratio', JNum(R.ScaleRatio));
  O.AddPair('scale_clamped', TJSONBool.Create(R.ScaleClamped));
  O.AddPair('mode', R.Mode);
  O.AddPair('date', R.Date);
  O.AddPair('seed', TJSONNumber.Create(R.Seed));
  O.AddPair('app_version', R.AppVersion);
  Result := O;
end;

function CurveJSON(const C: TXRCCurve; AngleScale: Double): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', C.FileName);
  Result.AddPair('role', RoleName[C.Role]);
  if C.Title <> '' then
    Result.AddPair('title', C.Title);
  if C.Role = crMeasured then
    Result.AddPair('linked', TJSONBool.Create(C.Linked));
  Result.AddPair('points', TJSONNumber.Create(Length(C.X)));
  if Length(C.X) > 0 then
  begin
    Result.AddPair('theta_min_deg', JNum(C.X[0] * AngleScale));
    Result.AddPair('theta_max_deg', JNum(C.X[High(C.X)] * AngleScale));
  end;
end;

function BuildXRCDetailedInfo(const P: TXRCProject): string;
var
  J, Obj, Stack: TJSONObject;
  Arr, Layers: TJSONArray;
  S, L, I: Integer;
begin
  J := TJSONObject.Create;
  try
    J.AddPair('format_version', TJSONNumber.Create(P.FormatVersion));
    J.AddPair('order', 'surface_to_substrate');
    Obj := TJSONObject.Create;
    J.AddPair('units', Obj);
    Obj.AddPair('length', 'A');
    Obj.AddPair('density', 'g/cm3');
    Obj.AddPair('angle', 'deg_theta');

    Obj := TJSONObject.Create;
    J.AddPair('model', Obj);
    Obj.AddPair('title', P.Model.Title);
    Obj.AddPair('source', SourceName[P.Model.Source]);

    Arr := TJSONArray.Create;
    J.AddPair('stacks', Arr);
    for S := 0 to High(P.Model.Stacks) do
    begin
      Stack := TJSONObject.Create;
      Arr.AddElement(Stack);
      Stack.AddPair('index', TJSONNumber.Create(S));
      Stack.AddPair('title', P.Model.Stacks[S].Title);
      Stack.AddPair('N', TJSONNumber.Create(P.Model.Stacks[S].N));
      if P.Model.Stacks[S].N > 1 then
        Stack.AddPair('period_A', JNum(StackPeriod(P.Model.Stacks[S])));
      Layers := TJSONArray.Create;
      Stack.AddPair('layers', Layers);
      for L := 0 to High(P.Model.Stacks[S].Layers) do
        Layers.AddElement(LayerJSON(P.Model.Stacks[S].Layers[L], L));
    end;

    Obj := TJSONObject.Create;
    J.AddPair('substrate', Obj);
    Obj.AddPair('material', P.Model.SubsMaterial);
    Obj.AddPair('roughness_A', JNum(P.Model.SubsSigma));
    Obj.AddPair('density_gcm3', JNum(P.Model.SubsRho));
    if P.FormatVersion <= 7 then
      Obj.AddPair('density_used', 'henke_bulk')
    else
      Obj.AddPair('density_used', 'stored');

    J.AddPair('calculation', CalculationJSON(P.Calculation));
    J.AddPair('fit_settings', FitSettingsJSON(P.FitSettings));
    J.AddPair('fit_result', FitResultJSON(P.FitResult));

    Arr := TJSONArray.Create;
    J.AddPair('curves', Arr);
    for I := 0 to High(P.Curves) do
      if P.CurvesInTwoTheta then
        Arr.AddElement(CurveJSON(P.Curves[I], 0.5))
      else
        Arr.AddElement(CurveJSON(P.Curves[I], 1));

    Arr := TJSONArray.Create;
    J.AddPair('inverted_ranges', Arr);
    for I := 0 to High(P.InvertedRanges) do
    begin
      Obj := TJSONObject.Create;
      Arr.AddElement(Obj);
      Obj.AddPair('stack', TJSONNumber.Create(P.InvertedRanges[I].Stack));
      Obj.AddPair('layer', TJSONNumber.Create(P.InvertedRanges[I].Layer));
      Obj.AddPair('parameter', ParamName[P.InvertedRanges[I].Param]);
    end;

    J.AddPair('layer_sequence', BuildLayerSequenceJSON(P.Model));
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

function BuildXRCKeyValues(const P: TXRCProject): TArray<TPluginKeyValue>;
var
  List: TList<TPluginKeyValue>;
  Seen: TDictionary<string, Integer>;
  S, L, Best, LastStack: Integer;
  Par: TXRCParam;
  Name, Suffix: string;

  procedure Add(const AName: string; AValue: Double; const AUnits: string;
    ARecType: TPluginRecType; AIsKey: Boolean);
  var
    KV: TPluginKeyValue;
  begin
    KV := Default(TPluginKeyValue);
    KV.Name := AName;
    KV.Value := AValue;
    KV.Units := AUnits;
    KV.RecType := ARecType;
    KV.IsKey := AIsKey;
    List.Add(KV);
  end;

begin
  Result := nil;
  if not P.Model.Valid then
    Exit;
  List := TList<TPluginKeyValue>.Create;
  Seen := TDictionary<string, Integer>.Create;
  try
    if Length(P.Model.Stacks) > 0 then
    begin
      Best := 0;
      for S := 1 to High(P.Model.Stacks) do
        if P.Model.Stacks[S].N > P.Model.Stacks[Best].N then
          Best := S;
      Add('Period', StackPeriod(P.Model.Stacks[Best]), 'A', prResult, True);
    end;
    if P.FitResult.Present then
      Add('Chi2', P.FitResult.Chi2, '', prResult, True);

    for S := 0 to High(P.Model.Stacks) do
      for L := 0 to High(P.Model.Stacks[S].Layers) do
      begin
        Name := P.Model.Stacks[S].Layers[L].Material;
        if not Seen.TryGetValue(Name, LastStack) then
          Suffix := ''
        else if LastStack = S then
          Suffix := Format(' (stack %d layer %d)', [S + 1, L + 1])
        else
          Suffix := Format(' (stack %d)', [S + 1]);
        Seen.AddOrSetValue(Name, S);
        for Par := Low(TXRCParam) to High(TXRCParam) do
          Add(Name + ' ' + ParamLabel[Par] + Suffix,
            P.Model.Stacks[S].Layers[L].Value[Par], ParamUnits[Par], prResult, False);
      end;

    Add('Substrate Roughness', P.Model.SubsSigma, 'A', prCondition, False);
    if P.Calculation.Present then
    begin
      Add('Wavelength', P.Calculation.WavelengthA, 'A', prCondition, False);
      Add('Resolution', P.Calculation.ResolutionDeg, 'deg', prCondition, False);
      if P.Calculation.Mode = cmTheta then
      begin
        Add('Theta Min', P.Calculation.ThetaMinDeg, 'deg', prCondition, False);
        Add('Theta Max', P.Calculation.ThetaMaxDeg, 'deg', prCondition, False);
      end;
    end;
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

end.
