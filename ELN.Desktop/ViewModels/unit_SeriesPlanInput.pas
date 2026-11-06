unit unit_SeriesPlanInput;

interface

uses
  System.SysUtils,
  unit_SeriesTable;

const
  LEVEL_LIST_SEPARATOR = '|';

function SeriesNumberText(AValue: Double): string;
function TryParsePlanNumber(const AText: string; const AUser: TFormatSettings;
  out AValue: Double): Boolean;
function TryParsePlanQuantity(const AText, AUnits: string; ADifference: Boolean;
  const AUser: TFormatSettings; out AValue: Double; out AError: string): Boolean;
function PlanQuantityHasOtherUnit(const AText, AUnits: string;
  const AUser: TFormatSettings): Boolean;
function TryParseLevels(const AText, AUnits: string; const AUser: TFormatSettings;
  out ALevels: TArray<Double>; out AError: string): Boolean;
function JoinLevelLists(const ALists: array of string): string;
function BuildPlanPoints(const ALevelsText: string; const AUnits: TArray<string>;
  const AExisting: TArray<TSeriesPoint>; const AUser: TFormatSettings;
  out APoints: TArray<TSeriesPoint>; out AError: string): Boolean;
function FormatPointText(const ALevels: TSeriesPoint;
  const AUnits: TArray<string>): string;

implementation

uses
  System.Math,
  unit_UnitConverter;

const
  REL_EPS = 1e-9;

function PointOf(const ALevels: array of Double): TSeriesPoint;
var
  I: Integer;
begin
  SetLength(Result, Length(ALevels));
  for I := 0 to High(ALevels) do
    Result[I] := ALevels[I];
end;

function SameLevel(A, B: Double): Boolean;
begin
  Result := Abs(A - B) <= REL_EPS * Max(1.0, Max(Abs(A), Abs(B)));
end;

function SamePoint(const A, B: TSeriesPoint): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for I := 0 to High(A) do
      if not SameLevel(A[I], B[I]) then
        Exit(False);
end;

function SeriesNumberText(AValue: Double): string;
begin
  Result := FloatToStrF(AValue, ffGeneral, 10, 0);
end;

function TryParsePlanNumber(const AText: string; const AUser: TFormatSettings;
  out AValue: Double): Boolean;
var
  S: string;
  C: Char;
  Separators: Integer;
begin
  AValue := 0;
  S := Trim(AText);
  if S = '' then
    Exit(False);
  Separators := 0;
  for C in S do
    if CharInSet(C, ['0'..'9', '+', '-', 'e', 'E']) then
      Continue
    else if (C = '.') or (C = AUser.DecimalSeparator) then
      Inc(Separators)
    else
      Exit(False);
  if Separators > 1 then
    Exit(False);
  S := S.Replace(AUser.DecimalSeparator, '.');
  Result := TryStrToFloat(S, AValue, TFormatSettings.Invariant)
    and not IsNan(AValue) and not IsInfinite(AValue);
  if not Result then
    AValue := 0;
end;

procedure SplitQuantity(const AText: string; const AUser: TFormatSettings;
  out ANumber, AUnit: string);
var
  S: string;
  I, N: Integer;

  function IsDigit(AIndex: Integer): Boolean;
  begin
    Result := (AIndex <= N) and CharInSet(S[AIndex], ['0'..'9']);
  end;

begin
  S := Trim(AText);
  N := Length(S);
  I := 1;
  while I <= N do
  begin
    if CharInSet(S[I], ['0'..'9', '.']) or (S[I] = AUser.DecimalSeparator) then
      Inc(I)
    else if CharInSet(S[I], ['+', '-']) and
      ((I = 1) or CharInSet(S[I - 1], ['e', 'E'])) then
      Inc(I)
    else if CharInSet(S[I], ['e', 'E']) and (I > 1) and (IsDigit(I + 1) or
      ((I + 1 <= N) and CharInSet(S[I + 1], ['+', '-']) and IsDigit(I + 2))) then
      Inc(I)
    else
      Break;
  end;
  ANumber := Copy(S, 1, I - 1);
  AUnit := Trim(Copy(S, I, MaxInt));
end;

function TryParsePlanQuantity(const AText, AUnits: string; ADifference: Boolean;
  const AUser: TFormatSettings; out AValue: Double; out AError: string): Boolean;
var
  NumText, UnitText: string;
  Factor: Double;
begin
  AError := '';
  SplitQuantity(AText, AUser, NumText, UnitText);
  if not TryParsePlanNumber(NumText, AUser, AValue) then
  begin
    AError := Format('"%s" is not a number.', [Trim(AText)]);
    Exit(False);
  end;
  if (UnitText = '') or (UnitText = AUnits) then
    Exit(True);
  Result := False;
  if not TUnitConverter.UnitExists(UnitText) then
    AError := Format('"%s" is not a unit that the ELN knows.', [UnitText])
  else if AUnits = '' then
    AError := Format('This value type has no unit, so "%s" cannot be used.', [UnitText])
  else if not TUnitConverter.UnitExists(AUnits) or
    (TUnitConverter.GetCategoryForUnit(UnitText) <>
    TUnitConverter.GetCategoryForUnit(AUnits)) then
    AError := Format('A value in %s cannot be converted to %s.', [UnitText, AUnits])
  else if ADifference then
  begin
    if TUnitConverter.TryFactor(UnitText, AUnits, Factor) then
    begin
      AValue := AValue * Factor;
      Result := True;
    end
    else
      AError := Format('A tolerance in %s cannot be converted to %s. Enter it in %s.',
        [UnitText, AUnits, AUnits]);
  end
  else
  begin
    AValue := TUnitConverter.Convert(AValue, UnitText, AUnits);
    Result := True;
  end;
  if Result and (IsNan(AValue) or IsInfinite(AValue)) then
  begin
    AError := Format('"%s" is not a number.', [Trim(AText)]);
    Result := False;
  end;
  if not Result then
    AValue := 0;
end;

function PlanQuantityHasOtherUnit(const AText, AUnits: string;
  const AUser: TFormatSettings): Boolean;
var
  NumText, UnitText: string;
begin
  SplitQuantity(AText, AUser, NumText, UnitText);
  Result := (UnitText <> '') and (UnitText <> AUnits);
end;

function TryParseLevels(const AText, AUnits: string; const AUser: TFormatSettings;
  out ALevels: TArray<Double>; out AError: string): Boolean;
var
  Part, Token: string;
  Value: Double;
  I: Integer;
begin
  ALevels := nil;
  AError := '';
  for Part in AText.Split([';', #13, #10]) do
  begin
    Token := Trim(Part);
    if Token = '' then
      Continue;
    if not TryParsePlanQuantity(Token, AUnits, False, AUser, Value, AError) then
    begin
      ALevels := nil;
      Exit(False);
    end;
    for I := 0 to High(ALevels) do
      if SameLevel(ALevels[I], Value) then
      begin
        AError := Format('The level %s is listed twice.', [Token]);
        ALevels := nil;
        Exit(False);
      end;
    ALevels := ALevels + [Value];
  end;
  Result := True;
end;

function JoinLevelLists(const ALists: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ALists) do
  begin
    if I > 0 then
      Result := Result + LEVEL_LIST_SEPARATOR;
    Result := Result + ALists[I];
  end;
end;

function BuildPlanPoints(const ALevelsText: string; const AUnits: TArray<string>;
  const AExisting: TArray<TSeriesPoint>; const AUser: TFormatSettings;
  out APoints: TArray<TSeriesPoint>; out AError: string): Boolean;
var
  Segments: TArray<string>;
  Lists: TArray<TArray<Double>>;
  Candidates: TArray<TSeriesPoint>;
  Point: TSeriesPoint;
  Known: TSeriesPoint;
  I, J: Integer;
  Skip: Boolean;
  FactorCount: Integer;
begin
  APoints := nil;
  AError := '';
  FactorCount := Length(AUnits);
  if (FactorCount < 1) or (FactorCount > 2) then
    Exit(True);
  Segments := ALevelsText.Split([LEVEL_LIST_SEPARATOR]);
  if Length(Segments) = 0 then
    Segments := [''];
  if (FactorCount = 2) and (Length(Segments) = 1) and (Trim(Segments[0]) = '') then
    Segments := ['', ''];
  if Length(Segments) <> FactorCount then
  begin
    AError := 'Enter the levels of each factor.';
    Exit(False);
  end;
  SetLength(Lists, FactorCount);
  for I := 0 to FactorCount - 1 do
    if not TryParseLevels(Segments[I], AUnits[I], AUser, Lists[I], AError) then
      Exit(False);

  if FactorCount = 1 then
    for I := 0 to High(Lists[0]) do
      Candidates := Candidates + [PointOf([Lists[0][I]])]
  else
  begin
    if (Length(Lists[0]) = 0) <> (Length(Lists[1]) = 0) then
    begin
      AError := 'Enter levels for both factors, or leave both empty.';
      Exit(False);
    end;
    for I := 0 to High(Lists[0]) do
      for J := 0 to High(Lists[1]) do
        Candidates := Candidates + [PointOf([Lists[0][I], Lists[1][J]])];
  end;

  for Point in Candidates do
  begin
    Skip := False;
    for Known in AExisting do
      if SamePoint(Known, Point) then
      begin
        Skip := True;
        Break;
      end;
    if not Skip then
      APoints := APoints + [Point];
  end;
  Result := True;
end;

function FormatPointText(const ALevels: TSeriesPoint;
  const AUnits: TArray<string>): string;
var
  I: Integer;
  Part: string;
begin
  Result := '';
  for I := 0 to High(ALevels) do
  begin
    Part := SeriesNumberText(ALevels[I]);
    if (I <= High(AUnits)) and (AUnits[I] <> '') then
      Part := Part + ' ' + AUnits[I];
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Part;
  end;
end;

end.
