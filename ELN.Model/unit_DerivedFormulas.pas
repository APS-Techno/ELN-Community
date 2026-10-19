unit unit_DerivedFormulas;

interface

uses
  System.SysUtils,
  unit_Item;

type
  EDerivedValueError = class(Exception);

  TDerivedFormulaRole = record
    Name: string;
    TypeTitle: string;
    Units: string;
    Mean: Boolean;
    AllowZero: Boolean;
  end;

  TDerivedFormulaCompute = reference to function(const Inputs: TArray<Double>): Double;

  TDerivedFormula = record
    Id: string;
    Version: Integer;
    Title: string;
    Expression: string;
    Roles: TArray<TDerivedFormulaRole>;
    ResultTitle: string;
    ResultUnits: string;
    Compute: TDerivedFormulaCompute;
    function RoleIndex(const Role: string): Integer;
    function Evaluate(const Inputs: TArray<Double>): Double;
  end;

const
  WEAR_RATE_FORMULA_ID = 'wear_rate_reciprocating';

procedure RegisterDerivedFormula(const Formula: TDerivedFormula);
procedure UnregisterDerivedFormula(const Id: string; Version: Integer);
function CurrentDerivedFormulas: TArray<TDerivedFormula>;
function TryGetDerivedFormula(const Id: string; Version: Integer;
  out Formula: TDerivedFormula): Boolean;
function TryGetCurrentDerivedFormula(const Id: string;
  out Formula: TDerivedFormula): Boolean;
function WearRateFormula: TDerivedFormula;
function RoleMatches(Value: TValue; const Role: TDerivedFormulaRole): Boolean;

implementation

uses
  System.Math,
  System.Generics.Collections;

var
  Registry: TList<TDerivedFormula>;

function TDerivedFormula.RoleIndex(const Role: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Roles) do
    if Roles[I].Name = Role then
      Exit(I);
  Result := -1;
end;

function RoleMatches(Value: TValue; const Role: TDerivedFormulaRole): Boolean;
begin
  Result := Assigned(Value.ValueType) and
    SameText(Value.ValueType.Title, Role.TypeTitle) and
    (Value.ValueType.Units = Role.Units);
end;

function TDerivedFormula.Evaluate(const Inputs: TArray<Double>): Double;
var
  I: Integer;
begin
  if Length(Inputs) <> Length(Roles) then
    raise EDerivedValueError.CreateFmt('Formula %s needs %d inputs, received %d',
      [Id, Length(Roles), Length(Inputs)]);
  for I := 0 to High(Roles) do
  begin
    if IsNan(Inputs[I]) or IsInfinite(Inputs[I]) then
      raise EDerivedValueError.CreateFmt('Input for role %s is not a finite number',
        [Roles[I].Name]);
    if Inputs[I] < 0 then
      raise EDerivedValueError.CreateFmt('Input for role %s is negative (%g)',
        [Roles[I].Name, Inputs[I]]);
    if (Inputs[I] = 0) and not Roles[I].AllowZero then
      raise EDerivedValueError.CreateFmt('Input for role %s must be positive',
        [Roles[I].Name]);
  end;
  Result := Compute(Inputs);
  if IsNan(Result) or IsInfinite(Result) then
    raise EDerivedValueError.CreateFmt('Formula %s gave a non-finite result', [Id]);
end;

function WearRateFormula: TDerivedFormula;
begin
  Result := Default(TDerivedFormula);
  Result.Id := WEAR_RATE_FORMULA_ID;
  Result.Version := 1;
  Result.Title := 'Reciprocating wear rate';
  Result.Expression := 'K = A / (2 ' + #$00B7 + ' F ' + #$00B7 + ' N)';
  SetLength(Result.Roles, 3);
  Result.Roles[0].Name := 'area';
  Result.Roles[0].TypeTitle := 'Wear area';
  Result.Roles[0].Units := 'mm' + #$00B2;
  Result.Roles[0].AllowZero := True;
  Result.Roles[0].Mean := True;
  Result.Roles[1].Name := 'normal_force';
  Result.Roles[1].TypeTitle := 'Normal force';
  Result.Roles[1].Units := 'N';
  Result.Roles[2].Name := 'cycles';
  Result.Roles[2].TypeTitle := 'Cycles';
  Result.Roles[2].Units := '';
  Result.ResultTitle := 'Wear rate';
  Result.ResultUnits := 'mm' + #$00B3 + '/(N' + #$00B7 + 'mm)';
  Result.Compute :=
    function(const Inputs: TArray<Double>): Double
    begin
      Result := Inputs[0] / (2 * Inputs[1] * Inputs[2]);
    end;
end;

procedure RegisterDerivedFormula(const Formula: TDerivedFormula);
var
  Existing: TDerivedFormula;
begin
  if (Trim(Formula.Id) = '') or (Formula.Version <= 0) or
    not Assigned(Formula.Compute) or (Length(Formula.Roles) = 0) then
    raise EArgumentException.Create('A formula needs an ID, a positive version, roles and a compute function');
  if TryGetDerivedFormula(Formula.Id, Formula.Version, Existing) then
    raise EArgumentException.CreateFmt('Formula %s version %d is already registered',
      [Formula.Id, Formula.Version]);
  Registry.Add(Formula);
end;

procedure UnregisterDerivedFormula(const Id: string; Version: Integer);
var
  I: Integer;
begin
  for I := Registry.Count - 1 downto 0 do
    if (Registry[I].Id = Id) and (Registry[I].Version = Version) then
      Registry.Delete(I);
end;

function TryGetDerivedFormula(const Id: string; Version: Integer;
  out Formula: TDerivedFormula): Boolean;
var
  F: TDerivedFormula;
begin
  for F in Registry do
    if (F.Id = Id) and (F.Version = Version) then
    begin
      Formula := F;
      Exit(True);
    end;
  Formula := Default(TDerivedFormula);
  Result := False;
end;

function TryGetCurrentDerivedFormula(const Id: string;
  out Formula: TDerivedFormula): Boolean;
var
  F: TDerivedFormula;
begin
  Result := False;
  Formula := Default(TDerivedFormula);
  for F in Registry do
    if (F.Id = Id) and (not Result or (F.Version > Formula.Version)) then
    begin
      Formula := F;
      Result := True;
    end;
end;

function CurrentDerivedFormulas: TArray<TDerivedFormula>;
var
  F, Current: TDerivedFormula;
  Ids: TList<string>;
  Found: TList<TDerivedFormula>;
begin
  Ids := TList<string>.Create;
  Found := TList<TDerivedFormula>.Create;
  try
    for F in Registry do
      if not Ids.Contains(F.Id) then
      begin
        Ids.Add(F.Id);
        TryGetCurrentDerivedFormula(F.Id, Current);
        Found.Add(Current);
      end;
    Result := Found.ToArray;
  finally
    Found.Free;
    Ids.Free;
  end;
end;

initialization
  Registry := TList<TDerivedFormula>.Create;
  RegisterDerivedFormula(WearRateFormula);

finalization
  Registry.Free;

end.
