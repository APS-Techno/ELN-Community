unit unit_UnitConverter;

interface

type
  TUnitDef = record
    Symbol: string;
    Category: string;
    Factor: Double;    // multiply input by Factor to get base unit value
    Offset: Double;    // added to input BEFORE multiplying (for temperature)
    IsOffset: Boolean; // True = use offset formula
  end;

  TUnitConverter = class
  private
    class var FUnits: TArray<TUnitDef>;
    class var FInitialized: Boolean;
    class procedure Initialize;
    class function FindUnit(const Symbol: string; out Def: TUnitDef): Boolean;
  public
    class function Convert(Value: Double; const FromUnit, ToUnit: string): Double;
    class function GetCategories: TArray<string>;
    class function GetUnits(const Category: string): TArray<string>;
    class function GetCategoryForUnit(const UnitSymbol: string): string;
    class function UnitExists(const Symbol: string): Boolean;
  end;

  function ParseSIInput(const Input, BaseUnit: string; out Value: Double): Boolean;

implementation

uses
  System.SysUtils, System.Generics.Collections;

{ TUnitConverter }

class procedure TUnitConverter.Initialize;
const
  // Unicode constants
  Micro = #$00B5; // µ
  Angstrom = #$00C5; // Å
  Degree = #$00B0; // °
var
  Defs: TArray<TUnitDef>;

  procedure Add(const Symbol, Category: string; Factor, Offset: Double;
    IsOffset: Boolean = False);
  var
    Def: TUnitDef;
    Len: Integer;
  begin
    Def.Symbol := Symbol;
    Def.Category := Category;
    Def.Factor := Factor;
    Def.Offset := Offset;
    Def.IsOffset := IsOffset;
    Len := Length(Defs);
    SetLength(Defs, Len + 1);
    Defs[Len] := Def;
  end;

begin
  if FInitialized then
    Exit;

  SetLength(Defs, 0);

  // Length — base: m
  Add('m',                'Length', 1.0,               0.0);
  Add('mm',               'Length', 1.0e-3,             0.0);
  Add(Micro + 'm',        'Length', 1.0e-6,             0.0);
  Add('nm',               'Length', 1.0e-9,             0.0);
  Add(Angstrom,           'Length', 1.0e-10,            0.0);
  Add('pm',               'Length', 1.0e-12,            0.0);
  Add('cm',               'Length', 1.0e-2,             0.0);

  // Energy — base: J
  Add('J',                'Energy', 1.0,                0.0);
  Add('kJ',               'Energy', 1.0e3,              0.0);
  Add('eV',               'Energy', 1.602176634e-19,    0.0);
  Add('keV',              'Energy', 1.602176634e-16,    0.0);
  Add('MeV',              'Energy', 1.602176634e-13,    0.0);
  Add('meV',              'Energy', 1.602176634e-22,    0.0);

  // Temperature — base: K (offset formula: Base = (Input + Offset) * Factor)
  Add('K',                'Temperature', 1.0,           0.0);
  Add(Degree + 'C',       'Temperature', 1.0,           273.15,  True);
  Add(Degree + 'F',       'Temperature', 5.0 / 9.0,    459.67,  True);

  // Pressure — base: Pa
  Add('Pa',               'Pressure', 1.0,              0.0);
  Add('kPa',              'Pressure', 1.0e3,            0.0);
  Add('MPa',              'Pressure', 1.0e6,            0.0);
  Add('GPa',              'Pressure', 1.0e9,            0.0);
  Add('mbar',             'Pressure', 100.0,            0.0);
  Add('bar',              'Pressure', 1.0e5,            0.0);
  Add('Torr',             'Pressure', 133.322368,       0.0);
  Add('atm',              'Pressure', 101325.0,         0.0);

  // Current — base: A
  Add('A',                'Current', 1.0,               0.0);
  Add('mA',               'Current', 1.0e-3,            0.0);
  Add(Micro + 'A',        'Current', 1.0e-6,            0.0);
  Add('nA',               'Current', 1.0e-9,            0.0);

  // Voltage — base: V
  Add('V',                'Voltage', 1.0,               0.0);
  Add('mV',               'Voltage', 1.0e-3,            0.0);
  Add('kV',               'Voltage', 1.0e3,             0.0);

  // Power — base: W
  Add('W',                'Power',   1.0,               0.0);
  Add('mW',               'Power',   1.0e-3,            0.0);
  Add('kW',               'Power',   1.0e3,             0.0);
  Add('MW',               'Power',   1.0e6,             0.0);

  // Mass — base: kg
  Add('kg',               'Mass',    1.0,               0.0);
  Add('g',                'Mass',    1.0e-3,            0.0);
  Add('mg',               'Mass',    1.0e-6,            0.0);
  Add(Micro + 'g',        'Mass',    1.0e-9,            0.0);

  // Volume — base: L
  Add('L',                'Volume',  1.0,               0.0);
  Add('mL',               'Volume',  1.0e-3,            0.0);
  Add(Micro + 'L',        'Volume',  1.0e-6,            0.0);

  // Concentration — base: mol/L
  Add('mol/L',            'Concentration', 1.0,         0.0);
  Add('mmol/L',           'Concentration', 1.0e-3,      0.0);
  Add('mg/mL',            'Concentration', 1.0,         0.0);  // numerically equal to g/L; distinct label

  // Time — base: s
  Add('s',                'Time',    1.0,               0.0);
  Add('ms',               'Time',    1.0e-3,            0.0);
  Add(Micro + 's',        'Time',    1.0e-6,            0.0);
  Add('ns',               'Time',    1.0e-9,            0.0);
  Add('min',              'Time',    60.0,              0.0);
  Add('h',                'Time',    3600.0,            0.0);

  // Frequency — base: Hz
  Add('Hz',               'Frequency', 1.0,             0.0);
  Add('kHz',              'Frequency', 1.0e3,           0.0);
  Add('MHz',              'Frequency', 1.0e6,           0.0);
  Add('GHz',              'Frequency', 1.0e9,           0.0);
  Add('THz',              'Frequency', 1.0e12,          0.0);

  FUnits := Defs;
  FInitialized := True;
end;

class function TUnitConverter.FindUnit(const Symbol: string;
  out Def: TUnitDef): Boolean;
var
  I: Integer;
begin
  Initialize;
  for I := 0 to High(FUnits) do
    if FUnits[I].Symbol = Symbol then
    begin
      Def := FUnits[I];
      Exit(True);
    end;
  Result := False;
end;

class function TUnitConverter.Convert(Value: Double;
  const FromUnit, ToUnit: string): Double;
var
  FromDef, ToDef: TUnitDef;
  BaseValue: Double;
begin
  if not FindUnit(FromUnit, FromDef) then
    raise EArgumentException.CreateFmt('Unknown unit: "%s"', [FromUnit]);
  if not FindUnit(ToUnit, ToDef) then
    raise EArgumentException.CreateFmt('Unknown unit: "%s"', [ToUnit]);
  if FromDef.Category <> ToDef.Category then
    raise EArgumentException.CreateFmt(
      'Cannot convert between categories "%s" and "%s"',
      [FromDef.Category, ToDef.Category]);

  // Convert input to base unit
  if FromDef.IsOffset then
    BaseValue := (Value + FromDef.Offset) * FromDef.Factor
  else
    BaseValue := Value * FromDef.Factor;

  // Convert base unit to target unit
  if ToDef.IsOffset then
    Result := (BaseValue / ToDef.Factor) - ToDef.Offset
  else
    Result := BaseValue / ToDef.Factor;
end;

class function TUnitConverter.GetCategories: TArray<string>;
var
  Seen: TList<string>;
  I: Integer;
  Cat: string;
  Found: Boolean;
  J: Integer;
begin
  Initialize;
  Seen := TList<string>.Create;
  try
    for I := 0 to High(FUnits) do
    begin
      Cat := FUnits[I].Category;
      Found := False;
      for J := 0 to Seen.Count - 1 do
        if Seen[J] = Cat then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Seen.Add(Cat);
    end;
    Result := Seen.ToArray;
  finally
    Seen.Free;
  end;
end;

class function TUnitConverter.GetUnits(const Category: string): TArray<string>;
var
  Matches: TList<string>;
  I: Integer;
begin
  Initialize;
  Matches := TList<string>.Create;
  try
    for I := 0 to High(FUnits) do
      if FUnits[I].Category = Category then
        Matches.Add(FUnits[I].Symbol);
    Result := Matches.ToArray;
  finally
    Matches.Free;
  end;
end;

class function TUnitConverter.GetCategoryForUnit(
  const UnitSymbol: string): string;
var
  Def: TUnitDef;
begin
  if FindUnit(UnitSymbol, Def) then
    Result := Def.Category
  else
    Result := '';
end;

class function TUnitConverter.UnitExists(const Symbol: string): Boolean;
var
  Def: TUnitDef;
begin
  Result := FindUnit(Symbol, Def);
end;

{ ParseSIInput }

function ParseSIInput(const Input, BaseUnit: string; out Value: Double): Boolean;
var
  S, NumStr, UnitStr: string;
  I: Integer;
  RawValue: Double;
begin
  Result := False;
  S := Trim(Input);
  if S = '' then
    Exit;

  // Try parsing entire input as a plain number (handles "2e-8", "0.005", etc.)
  if TryStrToFloat(S, Value) then
    Exit(True);

  // Split into number + unit suffix by scanning backwards from end
  I := Length(S);
  while (I > 0) and not CharInSet(S[I], ['0'..'9', '.', ',', ' ']) do
    Dec(I);

  NumStr := Trim(Copy(S, 1, I));
  UnitStr := Trim(Copy(S, I + 1, MaxInt));

  if (NumStr = '') or (UnitStr = '') then
    Exit;

  if not TryStrToFloat(NumStr, RawValue) then
    Exit;

  if TUnitConverter.UnitExists(UnitStr) then
  begin
    try
      Value := TUnitConverter.Convert(RawValue, UnitStr, BaseUnit);
      Result := True;
    except
      // Category mismatch — treat as base value
      Value := RawValue;
      Result := True;
    end;
  end
  else
  begin
    // Unrecognized unit — treat as base value
    Value := RawValue;
    Result := True;
  end;
end;

end.
