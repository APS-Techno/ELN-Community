unit unit_ValueChecks;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Types.Nullable,
  unit_ValueType,
  unit_Item;

const
  KEY_VALUE_TOLERANCE_FACTOR = 'VALUE_TOLERANCE_FACTOR';
  DEFAULT_TOLERANCE_FACTOR = 1e3;

type
  TValueIssue = (viBelowRange, viAboveRange, viToleranceExceedsValue,
    viToleranceTooSmall);
  TValueIssues = set of TValueIssue;

  TValueIssueRow = record
    ValueId: Integer;
    ItemId: Integer;
    ItemTitle: string;
    ProjectId: Integer;
    TypeId: Integer;
    TypeTitle: string;
    Units: string;
    Value: Double;
    Tolerance: Double;
    RangeMin: Nullable<Double>;
    RangeMax: Nullable<Double>;
    Issues: TValueIssues;
  end;

  EValueCheckRefused = class(Exception);

// Range: refuse below RangeMin or above RangeMax when set.
// Tolerance (only when Tolerance > 0): refuse when Tolerance > |Value|, or
// when Tolerance < |Value| / Factor, i.e. tolerance and value are on scales
// that differ by more than Factor.
function CheckValue(ValueType: TValueType; AValue, ATolerance,
  Factor: Double): TValueIssues;
function IssueCode(Issue: TValueIssue): string;
function DescribeValueIssues(Issues: TValueIssues; ValueType: TValueType;
  AValue, ATolerance, Factor: Double): string;

function LoadToleranceFactor(Manager: TObjectManager): Double;
procedure StoreToleranceFactor(Manager: TObjectManager; Factor: Double);
function IsValidToleranceFactor(Factor: Double): Boolean;

function FindValueIssues(Manager: TObjectManager; ProjectId: Integer;
  const IsProjectVisible: TFunc<Integer, Boolean>;
  Factor: Double): TArray<TValueIssueRow>;

implementation

uses
  System.Math,
  Aurelius.Criteria.Linq,
  unit_DBSettingsModel;

function CheckValue(ValueType: TValueType; AValue, ATolerance,
  Factor: Double): TValueIssues;
var
  Magnitude: Double;
begin
  Result := [];
  if Assigned(ValueType) then
  begin
    if ValueType.RangeMin.HasValue and (AValue < ValueType.RangeMin.Value) then
      Include(Result, viBelowRange);
    if ValueType.RangeMax.HasValue and (AValue > ValueType.RangeMax.Value) then
      Include(Result, viAboveRange);
  end;
  if ATolerance <= 0 then
    Exit;
  Magnitude := Abs(AValue);
  if ATolerance > Magnitude then
    Include(Result, viToleranceExceedsValue)
  else if ATolerance < Magnitude / Factor then
    Include(Result, viToleranceTooSmall);
end;

function IssueCode(Issue: TValueIssue): string;
begin
  case Issue of
    viBelowRange: Result := 'below_range';
    viAboveRange: Result := 'above_range';
    viToleranceExceedsValue: Result := 'tolerance_exceeds_value';
  else
    Result := 'tolerance_scale_mismatch';
  end;
end;

function Num(const V: Double): string;
begin
  Result := FloatToStrF(V, ffGeneral, 7, 0, TFormatSettings.Invariant);
end;

function DescribeValueIssues(Issues: TValueIssues; ValueType: TValueType;
  AValue, ATolerance, Factor: Double): string;
var
  Parts: TList<string>;
  Units: string;
begin
  Units := '';
  if Assigned(ValueType) and (ValueType.Units <> '') then
    Units := ' ' + ValueType.Units;
  Parts := TList<string>.Create;
  try
    if viBelowRange in Issues then
      Parts.Add(Format('value %s%s is below the plausible minimum %s%s',
        [Num(AValue), Units, Num(ValueType.RangeMin.Value), Units]));
    if viAboveRange in Issues then
      Parts.Add(Format('value %s%s is above the plausible maximum %s%s',
        [Num(AValue), Units, Num(ValueType.RangeMax.Value), Units]));
    if viToleranceExceedsValue in Issues then
      Parts.Add(Format('tolerance %s is larger than the value magnitude %s',
        [Num(ATolerance), Num(Abs(AValue))]));
    if viToleranceTooSmall in Issues then
      Parts.Add(Format(
        'tolerance %s is more than %s times smaller than the value %s',
        [Num(ATolerance), Num(Factor), Num(AValue)]));
    Result := string.Join('; ', Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

function IsValidToleranceFactor(Factor: Double): Boolean;
begin
  Result := not IsNan(Factor) and not IsInfinite(Factor) and (Factor > 1);
end;

function LoadToleranceFactor(Manager: TObjectManager): Double;
var
  Settings: TDBSettingsModel;
  Text: string;
begin
  Settings := TDBSettingsModel.Create(Manager);
  try
    Text := Settings.GetValue(KEY_VALUE_TOLERANCE_FACTOR, '');
  finally
    Settings.Free;
  end;
  if not TryStrToFloat(Text, Result, TFormatSettings.Invariant) or
    not IsValidToleranceFactor(Result) then
    Result := DEFAULT_TOLERANCE_FACTOR;
end;

procedure StoreToleranceFactor(Manager: TObjectManager; Factor: Double);
begin
  if not IsValidToleranceFactor(Factor) then
    raise EArgumentException.Create('The tolerance factor must be greater than 1');
  TDBSettingsModel.StoreValue(Manager, KEY_VALUE_TOLERANCE_FACTOR,
    FloatToStr(Factor, TFormatSettings.Invariant));
end;

function FindValueIssues(Manager: TObjectManager; ProjectId: Integer;
  const IsProjectVisible: TFunc<Integer, Boolean>;
  Factor: Double): TArray<TValueIssueRow>;
var
  Criteria: TLinqExpression;
  Items: TList<TItem>;
  Item: TItem;
  V: TValue;
  Issues: TValueIssues;
  Row: TValueIssueRow;
  Rows: TList<TValueIssueRow>;
begin
  Criteria := Linq['IsDeleted'] = False;
  if ProjectId > 0 then
    Criteria := Criteria and (Linq['ProjectID'] = ProjectId);
  Rows := TList<TValueIssueRow>.Create;
  try
    Items := Manager.Find<TItem>.Where(Criteria).OrderBy('Id').List;
    try
      for Item in Items do
      begin
        if Assigned(IsProjectVisible) and not IsProjectVisible(Item.ProjectID) then
          Continue;
        for V in Item.Values do
        begin
          Issues := CheckValue(V.ValueType, V.Value, V.Tol, Factor);
          if Issues = [] then
            Continue;
          Row := Default(TValueIssueRow);
          Row.ValueId := V.Id;
          Row.ItemId := Item.Id;
          Row.ItemTitle := Item.Title;
          Row.ProjectId := Item.ProjectID;
          if Assigned(V.ValueType) then
          begin
            Row.TypeId := V.ValueType.Id;
            Row.TypeTitle := V.ValueType.Title;
            Row.Units := V.ValueType.Units;
            Row.RangeMin := V.ValueType.RangeMin;
            Row.RangeMax := V.ValueType.RangeMax;
          end;
          Row.Value := V.Value;
          Row.Tolerance := V.Tol;
          Row.Issues := Issues;
          Rows.Add(Row);
        end;
      end;
    finally
      Items.Free;
    end;
    Result := Rows.ToArray;
  finally
    Rows.Free;
  end;
end;

end.
