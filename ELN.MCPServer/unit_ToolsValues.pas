unit unit_ToolsValues;

interface

uses
  unit_MCPTools;

procedure RegisterValueTools(Registry: TToolRegistry);

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections, System.TypInfo,
  System.DateUtils, System.Rtti,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_ItemTypes, unit_ELNDB_Dictionary,
  unit_ValueType, unit_JSONCompact, unit_ToolScope;

{ Helpers - same patterns as unit_ToolsNavigation }

function DateToISO(const DT: TDateTime): string;
begin
  Result := DateToISO8601(DT, False);
end;

function NullableDateToJSON(const Value: Nullable<TDateTime>): TJSONValue;
begin
  if Value.HasValue then
    Result := TJSONString.Create(DateToISO(Value.Value))
  else
    Result := TJSONNull.Create;
end;

function ItemTypeToStr(AType: TItemType): string;
begin
  Result := TRttiEnumerationType.GetName<TItemType>(AType);
end;

function RecTypeToStr(AType: TRecType): string;
begin
  Result := TRttiEnumerationType.GetName<TRecType>(AType);
end;

function StrToRecType(const S: string; out AType: TRecType): Boolean;
var
  V: Integer;
begin
  V := GetEnumValue(TypeInfo(TRecType), S);
  Result := V >= 0;
  if Result then
    AType := TRecType(V);
end;

function GetOptBool(const Params: TJSONObject; const Key: string;
  Default: Boolean): Boolean;
begin
  Result := Default;
  if (Params <> nil) and (Params.FindValue(Key) <> nil) then
    Result := Params.GetValue<Boolean>(Key);
end;

function GetOptInt(const Params: TJSONObject; const Key: string;
  out Value: Integer): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil);
  if Result then
    Value := Params.GetValue<Integer>(Key);
end;

function GetOptStr(const Params: TJSONObject; const Key: string;
  out Value: string): Boolean;
begin
  Result := (Params <> nil) and (Params.FindValue(Key) <> nil) and
            not (Params.FindValue(Key) is TJSONNull);
  if Result then
    Value := Params.GetValue<string>(Key);
end;

function GetReqInt(const Params: TJSONObject; const Key: string): Integer;
begin
  if (Params = nil) or (Params.FindValue(Key) = nil) then
    raise Exception.CreateFmt('Missing required parameter: %s', [Key]);
  Result := Params.GetValue<Integer>(Key);
end;

{ Helper: Build a JSON object for a single TValue record }

function ValueToJSON(V: TValue): TJSONObject;
var
  VT: TValueType;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('id', TJSONNumber.Create(V.Id));
    Result.AddPair('value', SmartNum(V.Value));
    Result.AddPair('tolerance', SmartNum(V.Tol));
    Result.AddPair('description', V.Description);
    Result.AddPair('rec_type', RecTypeToStr(V.RecType));

    VT := V.ValueType;
    if Assigned(VT) then
    begin
      Result.AddPair('type_id', TJSONNumber.Create(VT.Id));
      Result.AddPair('type_symbol', VT.Symbol);
      Result.AddPair('type_title', VT.Title);
      Result.AddPair('units', VT.Units);
    end
    else
    begin
      Result.AddPair('type_id', TJSONNull.Create);
      Result.AddPair('type_symbol', '');
      Result.AddPair('type_title', '');
      Result.AddPair('units', '');
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ --- Tool handlers --- }

function HandleGetValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  Item: TItem;
  V: TValue;
  VT: TValueType;
  CondArr, ResArr: TJSONArray;
  Obj: TJSONObject;
begin
  ItemId := GetReqInt(Params, 'item_id');
  // Uniform refusal for out-of-scope and missing-under-scope; inert without
  // a scope, where the plain "Item not found" below still applies.
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  CondArr := TJSONArray.Create;
  ResArr := TJSONArray.Create;
  try
    for V in Item.Values do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', TJSONNumber.Create(V.Id));

      VT := V.ValueType;
      if Assigned(VT) then
      begin
        Obj.AddPair('type_symbol', VT.Symbol);
        Obj.AddPair('type_title', VT.Title);
        Obj.AddPair('units', VT.Units);
      end
      else
      begin
        Obj.AddPair('type_symbol', '');
        Obj.AddPair('type_title', '');
        Obj.AddPair('units', '');
      end;

      Obj.AddPair('value', SmartNum(V.Value));
      Obj.AddPair('tolerance', SmartNum(V.Tol));
      Obj.AddPair('description', V.Description);

      case V.RecType of
        EXP_CONDITION: CondArr.AddElement(Obj);
        TEST_RESULT:   ResArr.AddElement(Obj);
      else
        // Unknown rec type - add to results by default
        ResArr.AddElement(Obj);
      end;
    end;
  except
    CondArr.Free;
    ResArr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('conditions', CondArr);
  Result.AddPair('results', ResArr);
end;

function HandleQueryValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId: Integer;
  HasProject: Boolean;
  Limit: Integer;
  ValueTypeStr, RecTypeStr, DateFromStr, DateToStr: string;
  HasValueType, HasRecType, HasDateFrom, HasDateTo: Boolean;
  FilterRecType: TRecType;
  DateFrom, DateTo: TDateTime;
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  Item: TItem;
  V: TValue;
  VT: TValueType;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Criteria: TLinqExpression;
  MatchesType: Boolean;
  Project: TProject;
  ProjectTitle: string;
begin
  DateFrom := 0;
  DateTo := 0;
  HasProject := GetOptInt(Params, 'project_id', ProjectId);
  HasValueType := GetOptStr(Params, 'value_type', ValueTypeStr);
  HasRecType := GetOptStr(Params, 'rec_type', RecTypeStr);
  HasDateFrom := GetOptStr(Params, 'date_from', DateFromStr);
  HasDateTo := GetOptStr(Params, 'date_to', DateToStr);

  if not GetOptInt(Params, 'limit', Limit) then
    Limit := 1000;
  // Hard cap — a client passing limit=9999999 would otherwise load every
  // matching item and every attached value into memory in one response,
  // stalling the single-threaded MCP loop for all concurrent callers.
  if Limit > 5000 then
    Limit := 5000
  else if Limit < 1 then
    Limit := 1;

  if HasRecType and not StrToRecType(RecTypeStr, FilterRecType) then
    raise Exception.CreateFmt('Invalid rec_type: %s (use EXP_CONDITION or TEST_RESULT)', [RecTypeStr]);

  if HasDateFrom then
    DateFrom := ISO8601ToDate(DateFromStr, False);
  if HasDateTo then
    DateTo := ISO8601ToDate(DateToStr, False);

  // Query items (with optional project and date filters)
  ItemDic := TItemDictionary.Create;
  try
    Criteria := (ItemDic.IsDeleted = False);

    if HasProject then
      Criteria := Criteria and (ItemDic.ProjectID = ProjectId);
    if HasDateFrom then
      Criteria := Criteria and (ItemDic.CreatedDate >= DateFrom);
    if HasDateTo then
      Criteria := Criteria and (ItemDic.CreatedDate <= DateTo);

    Items := Context.Manager.Find<TItem>
      .Where(Criteria)
      .List;
  finally
    ItemDic.Free;
  end;

  Arr := TJSONArray.Create;
  try
    try
      for Item in Items do
      begin
        // Scope filter: rows from invisible projects are dropped, not
        // refused - this tool reaches across projects by design.
        if not IsProjectVisible(Context, Item.ProjectID) then
          Continue;

        // Cache project title
        Project := Context.Manager.Find<TProject>(Item.ProjectID);
        if Assigned(Project) then
          ProjectTitle := Project.Title
        else
          ProjectTitle := '';

        for V in Item.Values do
        begin
          // Filter by rec_type if specified
          if HasRecType and (V.RecType <> FilterRecType) then
            Continue;

          // Filter by value_type (match title or symbol)
          VT := V.ValueType;
          if HasValueType then
          begin
            MatchesType := False;
            if Assigned(VT) then
              MatchesType := SameText(VT.Title, ValueTypeStr) or
                             SameText(VT.Symbol, ValueTypeStr);
            if not MatchesType then
              Continue;
          end;

          Obj := TJSONObject.Create;
          Obj.AddPair('value_id', TJSONNumber.Create(V.Id));
          Obj.AddPair('item_id', TJSONNumber.Create(Item.Id));
          Obj.AddPair('item_title', Item.Title);
          Obj.AddPair('project_id', TJSONNumber.Create(Item.ProjectID));
          Obj.AddPair('project_title', ProjectTitle);

          if Assigned(VT) then
          begin
            Obj.AddPair('type_symbol', VT.Symbol);
            Obj.AddPair('type_title', VT.Title);
            Obj.AddPair('units', VT.Units);
          end
          else
          begin
            Obj.AddPair('type_symbol', '');
            Obj.AddPair('type_title', '');
            Obj.AddPair('units', '');
          end;

          Obj.AddPair('value', SmartNum(V.Value));
          Obj.AddPair('tolerance', SmartNum(V.Tol));
          Obj.AddPair('rec_type', RecTypeToStr(V.RecType));
          Obj.AddPair('created_date', DateToISO(V.CreatedDate));

          Arr.AddElement(Obj);

          if Arr.Count >= Limit then
            Break;
        end;

        if Arr.Count >= Limit then
          Break;
      end;
    finally
      Items.Free;
    end;
  except
    Arr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('values', Arr);
  Result.AddPair('limit', TJSONNumber.Create(Limit));
end;

function HandleListValueTypes(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  CategoryStr: string;
  HasCategory: Boolean;
  CategoryId: Integer;
  VTDic: TValueTypeDictionary;
  Types: TList<TValueType>;
  VT: TValueType;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  HasCategory := GetOptStr(Params, 'category', CategoryStr);

  VTDic := TValueTypeDictionary.Create;
  try
    if HasCategory then
    begin
      // CatID is an integer - try to parse the category as an integer
      if TryStrToInt(CategoryStr, CategoryId) then
        Types := Context.Manager.Find<TValueType>
          .Where(VTDic.CatID = CategoryId)
          .List
      else
        // If not an integer, list all (category is stored as CatID integer)
        Types := Context.Manager.Find<TValueType>.List;
    end
    else
      Types := Context.Manager.Find<TValueType>.List;
  finally
    VTDic.Free;
  end;

  Arr := TJSONArray.Create;
  try
    try
      for VT in Types do
      begin
        Obj := TJSONObject.Create;
        Obj.AddPair('id', TJSONNumber.Create(VT.Id));
        Obj.AddPair('symbol', VT.Symbol);
        Obj.AddPair('title', VT.Title);
        Obj.AddPair('units', VT.Units);
        Obj.AddPair('category', TJSONNumber.Create(VT.CatID));
        Obj.AddPair('description', VT.Description);
        Arr.AddElement(Obj);
      end;
    finally
      Types.Free;
    end;
  except
    Arr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('value_types', Arr);
end;

function HandleCorrelateValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId, CondTypeId, ResTypeId, Limit: Integer;
  HasProject, HasCondType, HasResType: Boolean;
  ItemDic: TItemDictionary;
  Items: TList<TItem>;
  Item: TItem;
  V: TValue;
  VT: TValueType;
  Arr: TJSONArray;
  ItemObj, ValObj: TJSONObject;
  CondArr, ResArr: TJSONArray;
  HasCond, HasRes: Boolean;
  Criteria: TLinqExpression;
  Count: Integer;
begin
  HasProject := GetOptInt(Params, 'project_id', ProjectId);
  HasCondType := GetOptInt(Params, 'condition_type_id', CondTypeId);
  HasResType := GetOptInt(Params, 'result_type_id', ResTypeId);

  if not GetOptInt(Params, 'limit', Limit) then
    Limit := 500;
  // Same hard cap as query_values — correlate_values fans out into per-item
  // value lookups, so a huge limit is even more expensive here.
  if Limit > 5000 then
    Limit := 5000
  else if Limit < 1 then
    Limit := 1;

  // Validate: at least one filter must be provided
  if not HasProject and not HasCondType and not HasResType then
    raise Exception.Create('At least one of project_id, condition_type_id, ' +
      'or result_type_id must be provided');

  // Query items
  ItemDic := TItemDictionary.Create;
  try
    Criteria := (ItemDic.IsDeleted = False);
    if HasProject then
      Criteria := Criteria and (ItemDic.ProjectID = ProjectId);

    Items := Context.Manager.Find<TItem>
      .Where(Criteria)
      .List;
  finally
    ItemDic.Free;
  end;

  Arr := TJSONArray.Create;
  Count := 0;
  try
    try
      for Item in Items do
      begin
        if Count >= Limit then
          Break;

        // Same scope filter as query_values.
        if not IsProjectVisible(Context, Item.ProjectID) then
          Continue;

        // Build condition and result arrays for this item
        CondArr := TJSONArray.Create;
        ResArr := TJSONArray.Create;
        HasCond := False;
        HasRes := False;

        try
          for V in Item.Values do
          begin
            VT := V.ValueType;

            case V.RecType of
              EXP_CONDITION:
              begin
                // Filter by condition_type_id if specified
                if HasCondType then
                begin
                  if not Assigned(VT) or (VT.Id <> CondTypeId) then
                    Continue;
                end;

                ValObj := TJSONObject.Create;
                if Assigned(VT) then
                begin
                  ValObj.AddPair('type_id', TJSONNumber.Create(VT.Id));
                  ValObj.AddPair('type_symbol', VT.Symbol);
                  ValObj.AddPair('units', VT.Units);
                end
                else
                begin
                  ValObj.AddPair('type_id', TJSONNull.Create);
                  ValObj.AddPair('type_symbol', '');
                  ValObj.AddPair('units', '');
                end;
                ValObj.AddPair('value', SmartNum(V.Value));
                CondArr.AddElement(ValObj);
                HasCond := True;
              end;

              TEST_RESULT:
              begin
                // Filter by result_type_id if specified
                if HasResType then
                begin
                  if not Assigned(VT) or (VT.Id <> ResTypeId) then
                    Continue;
                end;

                ValObj := TJSONObject.Create;
                if Assigned(VT) then
                begin
                  ValObj.AddPair('type_id', TJSONNumber.Create(VT.Id));
                  ValObj.AddPair('type_symbol', VT.Symbol);
                  ValObj.AddPair('units', VT.Units);
                end
                else
                begin
                  ValObj.AddPair('type_id', TJSONNull.Create);
                  ValObj.AddPair('type_symbol', '');
                  ValObj.AddPair('units', '');
                end;
                ValObj.AddPair('value', SmartNum(V.Value));
                ResArr.AddElement(ValObj);
                HasRes := True;
              end;
            end;
          end;

          // Only include items that have at least one condition AND one result
          if HasCond and HasRes then
          begin
            ItemObj := TJSONObject.Create;
            ItemObj.AddPair('item_id', TJSONNumber.Create(Item.Id));
            ItemObj.AddPair('item_title', Item.Title);
            ItemObj.AddPair('item_type', ItemTypeToStr(Item.Type_));
            ItemObj.AddPair('conditions', CondArr);
            ItemObj.AddPair('results', ResArr);
            Arr.AddElement(ItemObj);
            Inc(Count);
          end
          else
          begin
            CondArr.Free;
            ResArr.Free;
          end;
        except
          // If we haven't handed off ownership yet, free them
          if not (HasCond and HasRes) then
          begin
            CondArr.Free;
            ResArr.Free;
          end;
          raise;
        end;
      end;
    finally
      Items.Free;
    end;
  except
    Arr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('items', Arr);
  Result.AddPair('count', TJSONNumber.Create(Count));
  Result.AddPair('limit', TJSONNumber.Create(Limit));
end;

{ --- Schema builders --- }

function MakeGetValuesSchema: TJSONObject;
var
  Props, ItemId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ItemId := TJSONObject.Create;
  ItemId.AddPair('type', 'integer');
  ItemId.AddPair('description', 'Item ID to get values for');
  Props.AddPair('item_id', ItemId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;

function MakeQueryValuesSchema: TJSONObject;
var
  Props, ProjId, VType, RType, DFrom, DTo, Lim: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Filter by project ID');
  Props.AddPair('project_id', ProjId);

  VType := TJSONObject.Create;
  VType.AddPair('type', 'string');
  VType.AddPair('description', 'Filter by value type title or symbol');
  Props.AddPair('value_type', VType);

  RType := TJSONObject.Create;
  RType.AddPair('type', 'string');
  RType.AddPair('description', 'Filter by record type: EXP_CONDITION or TEST_RESULT');
  Props.AddPair('rec_type', RType);

  DFrom := TJSONObject.Create;
  DFrom.AddPair('type', 'string');
  DFrom.AddPair('description', 'Filter from date (ISO 8601 format)');
  Props.AddPair('date_from', DFrom);

  DTo := TJSONObject.Create;
  DTo.AddPair('type', 'string');
  DTo.AddPair('description', 'Filter to date (ISO 8601 format)');
  Props.AddPair('date_to', DTo);

  Lim := TJSONObject.Create;
  Lim.AddPair('type', 'integer');
  Lim.AddPair('description', 'Maximum number of values to return (default: 1000)');
  Props.AddPair('limit', Lim);

  Result.AddPair('properties', Props);
end;

function MakeListValueTypesSchema: TJSONObject;
var
  Props, Cat: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  Cat := TJSONObject.Create;
  Cat.AddPair('type', 'string');
  Cat.AddPair('description', 'Filter by category ID');
  Props.AddPair('category', Cat);
  Result.AddPair('properties', Props);
end;

function MakeCorrelateValuesSchema: TJSONObject;
var
  Props, ProjId, CondId, ResId, Lim: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Filter items by project ID');
  Props.AddPair('project_id', ProjId);

  CondId := TJSONObject.Create;
  CondId.AddPair('type', 'integer');
  CondId.AddPair('description', 'Filter conditions by value type ID');
  Props.AddPair('condition_type_id', CondId);

  ResId := TJSONObject.Create;
  ResId.AddPair('type', 'integer');
  ResId.AddPair('description', 'Filter results by value type ID');
  Props.AddPair('result_type_id', ResId);

  Lim := TJSONObject.Create;
  Lim.AddPair('type', 'integer');
  Lim.AddPair('description', 'Maximum number of items to return (default: 500)');
  Props.AddPair('limit', Lim);

  Result.AddPair('properties', Props);
end;

{ --- Registration --- }

procedure RegisterValueTools(Registry: TToolRegistry);
begin
  Registry.Register('get_values',
    'Get all recorded values for an item, grouped by type: experimental ' +
    'conditions (inputs) and test results (outputs). Each value includes ' +
    'its type symbol, title, units, tolerance, and description.',
    MakeGetValuesSchema, HandleGetValues, tscProjectScoped);

  Registry.Register('query_values',
    'Search for values across items with optional filters by project, ' +
    'value type (title or symbol), record type (EXP_CONDITION or ' +
    'TEST_RESULT), and date range. Returns value details with item and ' +
    'project context.',
    MakeQueryValuesSchema, HandleQueryValues, tscProjectScoped);

  Registry.Register('list_value_types',
    'List all defined value types (measurement parameters). Each type has ' +
    'a symbol (e.g. W for power), title, units, and category. Optionally ' +
    'filter by category ID.',
    MakeListValueTypesSchema, HandleListValueTypes, tscGlobalRef);

  Registry.Register('correlate_values',
    'Find correlations between experimental conditions and test results. ' +
    'Returns items that have both condition and result values, paired for ' +
    'analysis. At least one of project_id, condition_type_id, or ' +
    'result_type_id must be provided. This is the primary analytical tool ' +
    'for discovering relationships between inputs and outputs.',
    MakeCorrelateValuesSchema, HandleCorrelateValues, tscProjectScoped);
end;

end.
