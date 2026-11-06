unit unit_ToolsSeries;

interface

uses
  System.JSON,
  System.SysUtils,
  unit_MCPTools;

procedure RegisterSeriesTools(Registry: TToolRegistry);

function HandleListSeries(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleGetSeriesTable(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleCreateSeries(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleUpdateSeriesPlan(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

implementation

uses
  Aurelius.Engine.ObjectManager,
  unit_ItemTypes,
  unit_JSONCompact,
  unit_Series,
  unit_SeriesColumn,
  unit_SeriesSlot,
  unit_SeriesTable,
  unit_SeriesModel,
  unit_ToolScope,
  unit_ToolsWrite,
  unit_ValueType;

const
  STATUS_NAMES: array[TSeriesStatus] of string = ('Draft', 'Active', 'Closed', 'Abandoned');
  ROLE_NAMES: array[TSeriesColumnRole] of string = ('Shown', 'Hidden', 'Varied', 'Response', 'Fixed');
  REC_TYPE_NAMES: array[TRecType] of string = ('EXP_CONDITION', 'TEST_RESULT');
  STATE_NAMES: array[TSeriesRowState] of string = ('Planned', 'Deposited', 'Measured', 'Failed');
  ORIGIN_NAMES: array[TSeriesSlotOrigin] of string = ('Planned', 'Added');

function RunSeriesTool(const Body: TFunc<TJSONObject>): TJSONObject;
begin
  try
    Result := Body();
  except
    on E: ESeriesAccess do
      raise Exception.Create(E.Message);
    on E: ESeriesError do
      raise Exception.CreateFmt('%s [refusal]', [E.Message]);
  end;
end;

function DoListSeries(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Pid: Integer;
  Model: TSeriesModel;
  Rows: TArray<TSeriesSummary>;
  Row: TSeriesSummary;
  Arr: TJSONArray;
  O: TJSONObject;
begin
  Pid := GetReqInt(Params, 'project_id');
  RequireProjectRead(Context, Pid);
  Model := TSeriesModel.Create(Context.Manager, Context.AccessPolicy);
  try
    Rows := Model.ListSeries(Context.User, Pid);
  finally
    Model.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('project_id', TJSONNumber.Create(Pid));
  Arr := TJSONArray.Create;
  Result.AddPair('series', Arr);
  for Row in Rows do
  begin
    O := TJSONObject.Create;
    O.AddPair('id', TJSONNumber.Create(Row.Id));
    O.AddPair('title', Row.Title);
    O.AddPair('purpose', Row.Purpose);
    O.AddPair('status', STATUS_NAMES[Row.Status]);
    O.AddPair('member_count', TJSONNumber.Create(Row.MemberCount));
    Arr.AddElement(O);
  end;
end;

function HandleListSeries(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunSeriesTool(
    function: TJSONObject
    begin
      Result := DoListSeries(Params, Context);
    end);
end;

function ColumnJSON(const C: TSeriesTableColumn): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('rec_type', REC_TYPE_NAMES[C.RecType]);
  Result.AddPair('value_type_id', TJSONNumber.Create(C.ValueTypeId));
  Result.AddPair('caption', C.Caption);
  Result.AddPair('units', C.Units);
  Result.AddPair('source_key', C.SourceKey);
  Result.AddPair('role', ROLE_NAMES[C.Role]);
end;

function CellJSON(const Cell: TSeriesCell): TJSONArray;
var
  Hit: TSeriesHit;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Hit in Cell.Hits do
  begin
    O := TJSONObject.Create;
    O.AddPair('value', ExactNum(Hit.Value));
    O.AddPair('tol', ExactNum(Hit.Tol));
    O.AddPair('value_id', TJSONNumber.Create(Hit.ValueId));
    O.AddPair('item_id', TJSONNumber.Create(Hit.ItemId));
    O.AddPair('source_key', Hit.SourceKey);
    if Hit.Planned then
      O.AddPair('planned', TJSONBool.Create(True));
    Result.AddElement(O);
  end;
end;

function CellMarkJSON(const Cell: TSeriesCell): TJSONObject;
begin
  Result := TJSONObject.Create;
  if Cell.HasPlanned then
    Result.AddPair('planned_value', ExactNum(Cell.PlannedValue));
  if Cell.Deviation then
    Result.AddPair('deviation', TJSONBool.Create(True));
end;

function ValueTypeText(const Context: TToolContext; AId: Integer;
  out ATitle, AUnits: string): Boolean;
var
  VT: TValueType;
begin
  VT := Context.Manager.Find<TValueType>(AId);
  Result := VT <> nil;
  if Result then
  begin
    ATitle := VT.Title;
    AUnits := VT.Units;
  end
  else
  begin
    ATitle := '';
    AUnits := '';
  end;
end;

function PlanJSON(const Context: TToolContext; const Plan: TSeriesPlan): TJSONObject;
var
  Factors, Fixed, Responses: TJSONArray;
  F: TSeriesFactorSpec;
  X: TSeriesFixedSpec;
  R: TSeriesResponseSpec;
  O: TJSONObject;
  Title, Units: string;

  procedure Describe(AO: TJSONObject; AId: Integer; const AEntryLabel: string);
  begin
    ValueTypeText(Context, AId, Title, Units);
    AO.AddPair('value_type_id', TJSONNumber.Create(AId));
    AO.AddPair('title', Title);
    AO.AddPair('units', Units);
    AO.AddPair('label', AEntryLabel);
  end;
begin
  Result := TJSONObject.Create;
  Factors := TJSONArray.Create;
  Result.AddPair('factors', Factors);
  for F in Plan.Factors do
  begin
    O := TJSONObject.Create;
    Describe(O, F.ValueTypeId, F.EntryLabel);
    if F.RangeMin.HasValue then
      O.AddPair('range_min', ExactNum(F.RangeMin.Value))
    else
      O.AddPair('range_min', TJSONNull.Create);
    if F.RangeMax.HasValue then
      O.AddPair('range_max', ExactNum(F.RangeMax.Value))
    else
      O.AddPair('range_max', TJSONNull.Create);
    Factors.AddElement(O);
  end;
  Fixed := TJSONArray.Create;
  Result.AddPair('fixed', Fixed);
  for X in Plan.Fixed do
  begin
    O := TJSONObject.Create;
    Describe(O, X.ValueTypeId, X.EntryLabel);
    O.AddPair('value', ExactNum(X.Value));
    O.AddPair('tol', ExactNum(X.Tol));
    Fixed.AddElement(O);
  end;
  Responses := TJSONArray.Create;
  Result.AddPair('responses', Responses);
  for R in Plan.Responses do
  begin
    O := TJSONObject.Create;
    Describe(O, R.ValueTypeId, R.EntryLabel);
    Responses.AddElement(O);
  end;
  Result.AddPair('target_folder_id', TJSONNumber.Create(Plan.TargetFolderId));
end;

function DoGetSeriesTable(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Id: Integer;
  Model: TSeriesModel;
  Summary: TSeriesSummary;
  Table: TSeriesTable;
  PlanInfo: TSeriesPlanInfo;
  Cols, Rows, Cells, Marks, Excluded: TJSONArray;
  Col: TSeriesTableColumn;
  Row: TSeriesTableRow;
  Cell: TSeriesCell;
  RowObj: TJSONObject;
  ItemId: Integer;
begin
  Id := GetReqInt(Params, 'series_id');
  Model := TSeriesModel.Create(Context.Manager, Context.AccessPolicy);
  try
    try
      Summary := Model.Get(Context.User, Id);
    except
      on ESeriesError do
        RaiseOutOfScope;
    end;
    RequireProjectRead(Context, Summary.ProjectId);
    Table := Model.BuildTable(Context.User, Id,
      GetOptBool(Params, 'include_failed', False));
    PlanInfo := Model.GetPlan(Context.User, Id);
  finally
    Model.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('series_id', TJSONNumber.Create(Id));
  Result.AddPair('project_id', TJSONNumber.Create(Summary.ProjectId));
  Result.AddPair('title', Summary.Title);
  Result.AddPair('status', STATUS_NAMES[Summary.Status]);
  Result.AddPair('plan', PlanJSON(Context, PlanInfo.Plan));
  Cols := TJSONArray.Create;
  Result.AddPair('columns', Cols);
  for Col in Table.Columns do
    Cols.AddElement(ColumnJSON(Col));
  Rows := TJSONArray.Create;
  Result.AddPair('rows', Rows);
  for Row in Table.Rows do
  begin
    RowObj := TJSONObject.Create;
    RowObj.AddPair('item_id', TJSONNumber.Create(Row.ItemId));
    RowObj.AddPair('slot_id', TJSONNumber.Create(Row.SlotId));
    RowObj.AddPair('title', Row.Title);
    RowObj.AddPair('state', STATE_NAMES[Row.State]);
    RowObj.AddPair('origin', ORIGIN_NAMES[Row.Origin]);
    Cells := TJSONArray.Create;
    RowObj.AddPair('cells', Cells);
    Marks := TJSONArray.Create;
    RowObj.AddPair('cell_marks', Marks);
    for Cell in Row.Cells do
    begin
      Cells.AddElement(CellJSON(Cell));
      Marks.AddElement(CellMarkJSON(Cell));
    end;
    Rows.AddElement(RowObj);
  end;
  Excluded := TJSONArray.Create;
  Result.AddPair('excluded_item_ids', Excluded);
  for ItemId in Table.Excluded do
    Excluded.Add(ItemId);
end;

function HandleGetSeriesTable(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunSeriesTool(
    function: TJSONObject
    begin
      Result := DoGetSeriesTable(Params, Context);
    end);
end;

function ParseNumber(AValue: TJSONValue; const AWhat: string): Double;
begin
  if not (AValue is TJSONNumber) then
    raise ESeriesError.CreateFmt('%s must be a number.', [AWhat]);
  Result := TJSONNumber(AValue).AsDouble;
end;

function ParseArray(const Params: TJSONObject; const AKey: string;
  out AArr: TJSONArray): Boolean;
var
  V: TJSONValue;
begin
  V := Params.FindValue(AKey);
  Result := (V <> nil) and not (V is TJSONNull);
  if not Result then
    Exit;
  if not (V is TJSONArray) then
    raise ESeriesError.CreateFmt('%s must be an array.', [AKey]);
  AArr := TJSONArray(V);
end;

function EntryObject(AValue: TJSONValue; const AWhat: string): TJSONObject;
begin
  if not (AValue is TJSONObject) then
    raise ESeriesError.CreateFmt('Each %s entry must be an object.', [AWhat]);
  Result := TJSONObject(AValue);
end;

function WholeId(AValue: TJSONValue; const AWhat: string): Integer;
var
  D: Double;
begin
  D := ParseNumber(AValue, AWhat);
  if (Frac(D) <> 0) or (D < 1) or (D > MaxInt) then
    raise ESeriesError.CreateFmt('%s must be a whole number id.', [AWhat]);
  Result := Trunc(D);
end;

function EntryTypeId(AEntry: TJSONObject; const AWhat: string): Integer;
begin
  Result := WholeId(AEntry.FindValue('value_type_id'), AWhat + ' value_type_id');
end;

function EntryLabelOf(AEntry: TJSONObject): string;
var
  V: TJSONValue;
begin
  V := AEntry.FindValue('label');
  if (V = nil) or (V is TJSONNull) then
    Exit('');
  if not (V is TJSONString) then
    raise ESeriesError.Create('label must be a string.');
  Result := Trim(V.Value);
end;

function ParseFactors(AArr: TJSONArray): TArray<TSeriesFactorSpec>;
var
  I: Integer;
  O: TJSONObject;
begin
  SetLength(Result, AArr.Count);
  for I := 0 to AArr.Count - 1 do
  begin
    O := EntryObject(AArr.Items[I], 'factors');
    Result[I] := Default(TSeriesFactorSpec);
    Result[I].ValueTypeId := EntryTypeId(O, 'A factor');
    Result[I].EntryLabel := EntryLabelOf(O);
    if (O.FindValue('range_min') <> nil) and not (O.FindValue('range_min') is TJSONNull) then
      Result[I].RangeMin := ParseNumber(O.FindValue('range_min'), 'range_min');
    if (O.FindValue('range_max') <> nil) and not (O.FindValue('range_max') is TJSONNull) then
      Result[I].RangeMax := ParseNumber(O.FindValue('range_max'), 'range_max');
  end;
end;

function ParseFixed(AArr: TJSONArray): TArray<TSeriesFixedSpec>;
var
  I: Integer;
  O: TJSONObject;
begin
  SetLength(Result, AArr.Count);
  for I := 0 to AArr.Count - 1 do
  begin
    O := EntryObject(AArr.Items[I], 'fixed');
    Result[I] := Default(TSeriesFixedSpec);
    Result[I].ValueTypeId := EntryTypeId(O, 'A fixed condition');
    Result[I].EntryLabel := EntryLabelOf(O);
    Result[I].Value := ParseNumber(O.FindValue('value'), 'A fixed value');
    if (O.FindValue('tol') <> nil) and not (O.FindValue('tol') is TJSONNull) then
      Result[I].Tol := ParseNumber(O.FindValue('tol'), 'tol');
  end;
end;

function ParseResponses(AArr: TJSONArray): TArray<TSeriesResponseSpec>;
var
  I: Integer;
  O: TJSONObject;
begin
  SetLength(Result, AArr.Count);
  for I := 0 to AArr.Count - 1 do
  begin
    O := EntryObject(AArr.Items[I], 'responses');
    Result[I] := Default(TSeriesResponseSpec);
    Result[I].ValueTypeId := EntryTypeId(O, 'A response');
    Result[I].EntryLabel := EntryLabelOf(O);
  end;
end;

function ParsePoints(AArr: TJSONArray): TArray<TSeriesPoint>;
var
  I, J: Integer;
  Pt: TJSONArray;
begin
  SetLength(Result, AArr.Count);
  for I := 0 to AArr.Count - 1 do
  begin
    if not (AArr.Items[I] is TJSONArray) then
      raise ESeriesError.Create('A point must be an array of numbers.');
    Pt := TJSONArray(AArr.Items[I]);
    SetLength(Result[I], Pt.Count);
    for J := 0 to Pt.Count - 1 do
      Result[I][J] := ParseNumber(Pt.Items[J], 'A level');
  end;
end;

function DoCreateSeries(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Pid: Integer;
  Title, Purpose: string;
  Plan: TSeriesPlan;
  Points: TArray<TSeriesPoint>;
  Arr: TJSONArray;
  Folder, SeriesId: Integer;
  Model: TSeriesModel;
begin
  Pid := GetReqInt(Params, 'project_id');
  CheckProjectWriteAccess(Context, Pid);
  Title := GetReqStr(Params, 'title');
  if not GetOptStr(Params, 'purpose', Purpose) then
    Purpose := '';
  Plan := Default(TSeriesPlan);
  Points := nil;
  if ParseArray(Params, 'factors', Arr) then
    Plan.Factors := ParseFactors(Arr);
  if ParseArray(Params, 'fixed', Arr) then
    Plan.Fixed := ParseFixed(Arr);
  if ParseArray(Params, 'responses', Arr) then
    Plan.Responses := ParseResponses(Arr);
  if ParseArray(Params, 'points', Arr) then
    Points := ParsePoints(Arr);
  if GetOptInt(Params, 'target_folder_id', Folder) then
    Plan.TargetFolderId := Folder;
  Model := TSeriesModel.Create(Context.Manager, Context.AccessPolicy, scvMcp);
  try
    SeriesId := Model.CreateSeries(Context.User, Pid, Title, Purpose, Plan, Points);
  finally
    Model.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('series_id', TJSONNumber.Create(SeriesId));
  Result.AddPair('status', STATUS_NAMES[ssDraft]);
end;

function HandleCreateSeries(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunSeriesTool(
    function: TJSONObject
    begin
      Result := DoCreateSeries(Params, Context);
    end);
end;

function DoUpdateSeriesPlan(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Id, Folder: Integer;
  Model: TSeriesModel;
  Summary: TSeriesSummary;
  NewPlan: TSeriesPlan;
  Purpose, Reason: string;
  Arr: TJSONArray;
  Points: TArray<TSeriesPoint>;
  HasPurpose, HasPlan: Boolean;
  Added: TArray<Integer>;
  Slot: Integer;
  AddedArr: TJSONArray;
begin
  Id := GetReqInt(Params, 'series_id');
  Model := TSeriesModel.Create(Context.Manager, Context.AccessPolicy, scvMcp);
  try
    try
      Summary := Model.Get(Context.User, Id);
    except
      on ESeriesError do
        RaiseOutOfScope;
    end;
    CheckProjectWriteAccess(Context, Summary.ProjectId);
    if not (Summary.Status in [ssDraft, ssActive]) then
      raise ESeriesError.Create('Only a Draft or Active series can be changed.');
    NewPlan := Model.GetPlan(Context.User, Id).Plan;
    HasPlan := False;
    HasPurpose := GetOptStr(Params, 'purpose', Purpose);
    if ParseArray(Params, 'factors', Arr) then
    begin
      NewPlan.Factors := ParseFactors(Arr);
      HasPlan := True;
    end;
    if ParseArray(Params, 'fixed', Arr) then
    begin
      NewPlan.Fixed := ParseFixed(Arr);
      HasPlan := True;
    end;
    if ParseArray(Params, 'responses', Arr) then
    begin
      NewPlan.Responses := ParseResponses(Arr);
      HasPlan := True;
    end;
    if GetOptInt(Params, 'target_folder_id', Folder) then
    begin
      NewPlan.TargetFolderId := Folder;
      HasPlan := True;
    end;
    Points := nil;
    if ParseArray(Params, 'add_points', Arr) then
      Points := ParsePoints(Arr);
    if not GetOptStr(Params, 'reason', Reason) then
      Reason := '';
    Added := Model.UpdatePlanAndPoints(Context.User, Id, HasPurpose, Purpose,
      HasPlan, NewPlan, Points, Reason);
  finally
    Model.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('series_id', TJSONNumber.Create(Id));
  AddedArr := TJSONArray.Create;
  Result.AddPair('added_slot_ids', AddedArr);
  for Slot in Added do
    AddedArr.Add(Slot);
end;

function HandleUpdateSeriesPlan(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunSeriesTool(
    function: TJSONObject
    begin
      Result := DoUpdateSeriesPlan(Params, Context);
    end);
end;

function Prop(const AType, ADesc: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  Result.AddPair('description', ADesc);
end;

function Schema(const ANames: array of string; const AProps: array of TJSONObject;
  const ARequired: array of string): TJSONObject;
var
  Props: TJSONObject;
  Req: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  for I := 0 to High(ANames) do
    Props.AddPair(ANames[I], AProps[I]);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  for I := 0 to High(ARequired) do
    Req.Add(ARequired[I]);
  Result.AddPair('required', Req);
end;

const
  FACTORS_HELP = 'Array of {value_type_id, label, range_min, range_max}; the order is ' +
    'the column order of a point. label (optional) says which parameter it is, ' +
    'for example "Mo layer"';
  FIXED_HELP = 'Array of {value_type_id, label, value, tol} held constant for every point';
  RESPONSES_HELP = 'Array of {value_type_id, label} measured as results';
  POINTS_HELP = 'Array of points; a point is an array with one number per factor';

procedure RegisterSeriesTools(Registry: TToolRegistry);
begin
  Registry.Register('list_series',
    'List the experiment series of a project: id, title, purpose, status ' +
    '(Draft, Active, Closed, Abandoned) and member_count.',
    Schema(['project_id'], [Prop('integer', 'Project id')], ['project_id']),
    HandleListSeries, tscProjectScoped, taRead);

  Registry.Register('get_series_table',
    'The table of one experiment series: the plan (factors, fixed conditions, ' +
    'responses, target folder), every column (also Hidden ones) with its role ' +
    '(Shown, Hidden, Varied, Response, Fixed), and one row per planned point or ' +
    'member item. A row has slot_id, state (Planned, Deposited, Measured, Failed) ' +
    'and origin (Planned, Added). Each cell is a list of hits (value, tol, ' +
    'value_id, item_id, source_key, planned when the value is still a planned ' +
    'value): empty = missing, 2 or more = ambiguous. cell_marks has one object ' +
    'per cell with planned_value (the plan''s number) and deviation (true when ' +
    'the made value is outside the plan) when they apply. Failed members are ' +
    'left out unless include_failed is true; excluded_item_ids lists members ' +
    'that are not in the table.',
    Schema(['series_id', 'include_failed'],
      [Prop('integer', 'Series id'),
       Prop('boolean', 'Also show members marked failed (default false)')],
      ['series_id']),
    HandleGetSeriesTable, tscProjectScoped, taRead);

  Registry.Register('create_series',
    'Create an experiment series in Draft status with its plan. A human starts the ' +
    'series in the desktop; this tool cannot start it. Returns series_id and status.',
    Schema(['project_id', 'title', 'purpose', 'factors', 'fixed', 'responses',
      'points', 'target_folder_id'],
      [Prop('integer', 'Project id'), Prop('string', 'Series title'),
       Prop('string', 'Purpose of the series'), Prop('array', FACTORS_HELP),
       Prop('array', FIXED_HELP), Prop('array', RESPONSES_HELP),
       Prop('array', POINTS_HELP),
       Prop('integer', 'Folder where depositions of the series are made')],
      ['project_id', 'title']),
    HandleCreateSeries, tscProjectScoped, taWrite);

  Registry.Register('update_series_plan',
    'Change the plan of a Draft or Active series. Only the fields you pass change; ' +
    'factors, fixed and responses replace the whole list. add_points appends points; ' +
    'reason is optional. On an Active series only purpose and add_points can change: ' +
    'a change to factors, fixed, responses or target_folder_id is refused, because ' +
    'the plan of an Active series is changed in the desktop. ' +
    'The call changes everything or nothing.',
    Schema(['series_id', 'purpose', 'factors', 'fixed', 'responses',
      'target_folder_id', 'add_points', 'reason'],
      [Prop('integer', 'Series id'), Prop('string', 'New purpose'),
       Prop('array', FACTORS_HELP), Prop('array', FIXED_HELP),
       Prop('array', RESPONSES_HELP),
       Prop('integer', 'Folder where depositions are made; 0 clears it'),
       Prop('array', POINTS_HELP), Prop('string', 'Why the points are added')],
      ['series_id']),
    HandleUpdateSeriesPlan, tscProjectScoped, taWrite);
end;

end.
