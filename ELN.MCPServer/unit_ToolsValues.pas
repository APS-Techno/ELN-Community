unit unit_ToolsValues;

interface

uses
  unit_MCPTools;

procedure RegisterValueTools(Registry: TToolRegistry);

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections, System.TypInfo,
  System.DateUtils, System.Rtti, System.Variants,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Criteria.Base, Aurelius.Criteria.Projections,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_ItemTypes, unit_ELNDB_Dictionary,
  unit_ValueType, unit_JSONCompact, unit_ToolScope, unit_ToolHelpers,
  unit_ValueChecks, unit_ToolsWrite;


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
    Result.AddPair('source', ValueSourceJSON(V));
  except
    Result.Free;
    raise;
  end;
end;


function HandleGetValues(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  Item: TItem;
  V: TValue;
  VT: TValueType;
  CondArr, ResArr: TJSONArray;
  Obj: TJSONObject;
  Chains: TDictionary<Integer, TAncestorChain>;
  Chain: TAncestorChain;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  Chains := AncestorChains(Context.Manager, [ItemId]);
  try
    Chain := Chains[ItemId];
  finally
    Chains.Free;
  end;

  CondArr := TJSONArray.Create;
  ResArr := TJSONArray.Create;
  try
    for V in Item.Values do
    begin
      Obj := TJSONObject.Create;
      case V.RecType of
        EXP_CONDITION: CondArr.AddElement(Obj);
      else
        ResArr.AddElement(Obj);
      end;
      Obj.AddPair('id', TJSONNumber.Create(V.Id));

      VT := V.ValueType;
      if Assigned(VT) then
      begin
        Obj.AddPair('type_id', TJSONNumber.Create(VT.Id));
        Obj.AddPair('type_symbol', VT.Symbol);
        Obj.AddPair('type_title', VT.Title);
        Obj.AddPair('units', VT.Units);
      end
      else
      begin
        Obj.AddPair('type_id', TJSONNull.Create);
        Obj.AddPair('type_symbol', '');
        Obj.AddPair('type_title', '');
        Obj.AddPair('units', '');
      end;

      Obj.AddPair('rec_type', RecTypeToStr(V.RecType));
      Obj.AddPair('value', ExactNum(V.Value));
      Obj.AddPair('tolerance', ExactNum(V.Tol));
      Obj.AddPair('description', V.Description);
      Obj.AddPair('source', ValueSourceJSON(V));
    end;
  except
    CondArr.Free;
    ResArr.Free;
    raise;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('item_id', TJSONNumber.Create(ItemId));
  Result.AddPair('project_id', TJSONNumber.Create(Item.ProjectID));
  Result.AddPair('ancestor_ids', AncestorIdsJSON(Chain));
  if Chain.Incomplete then
    Result.AddPair('ancestors_incomplete', TJSONBool.Create(True));
  Result.AddPair('conditions', CondArr);
  Result.AddPair('results', ResArr);
end;

function RemainingItemExpr(const Context: TToolContext; Items: TList<TItem>;
  FromIndex: Integer; HasDateFrom: Boolean; DateFrom: TDateTime;
  HasDateTo: Boolean; DateTo: TDateTime; out Expr: TLinqExpression): Boolean;
var
  Seen: TDictionary<Integer, Boolean>;
  Projects: TList<Variant>;
  I: Integer;
  Visible: Boolean;
begin
  Seen := TDictionary<Integer, Boolean>.Create;
  Projects := TList<Variant>.Create;
  try
    for I := FromIndex to Items.Count - 1 do
      if not Seen.TryGetValue(Items[I].ProjectID, Visible) then
      begin
        Visible := IsProjectVisible(Context, Items[I].ProjectID);
        Seen.Add(Items[I].ProjectID, Visible);
        if Visible then
          Projects.Add(Items[I].ProjectID);
      end;
    Result := Projects.Count > 0;
    if not Result then
      Exit;
    Expr := (Linq['i.IsDeleted'] = False) and
      (Linq['i.Id'] >= Items[FromIndex].Id) and
      Linq['i.ProjectID']._In(Projects.ToArray);
    if HasDateFrom then
      Expr := Expr and (Linq['i.CreatedDate'] >= VarFromDateTime(DateFrom));
    if HasDateTo then
      Expr := Expr and (Linq['i.CreatedDate'] <= VarFromDateTime(DateTo));
  finally
    Projects.Free;
    Seen.Free;
  end;
end;

function HasMoreValues(Manager: TObjectManager; const ItemExpr: TLinqExpression;
  HasRecType: Boolean; RecType: TRecType; HasValueType: Boolean;
  const ValueTypeName: string): Boolean;
var
  Expr: TLinqExpression;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  Result := False;
  Expr := ItemExpr;
  if HasRecType then
    Expr := Expr and (Linq['RecType'] = Ord(RecType));
  if HasValueType then
    Rows := Manager.Find<TValue>
      .CreateAlias('Item', 'i')
      .CreateAlias('ValueType', 'vt')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Group('vt.Title').As_('Title'))
        .Add(TProjections.Group('vt.Symbol').As_('Symbol')))
      .Where(Expr)
      .ListValues
  else
    Rows := Manager.Find<TValue>
      .CreateAlias('Item', 'i')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Prop('Id').As_('Id')))
      .Where(Expr)
      .Take(1)
      .ListValues;
  try
    if not HasValueType then
      Exit(Rows.Count > 0);
    for Row in Rows do
      if ValueTypeNameMatches(VarToStr(Row.Values['Title']),
        VarToStr(Row.Values['Symbol']), ValueTypeName) then
        Exit(True);
  finally
    Rows.Free;
  end;
end;

function HasMorePairs(Manager: TObjectManager; const ItemExpr: TLinqExpression;
  HasCondType: Boolean; CondTypeId: Integer; HasResType: Boolean;
  ResTypeId: Integer): Boolean;
var
  CondExpr, ResExpr, Expr: TLinqExpression;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  Result := False;
  CondExpr := Linq['RecType'] = Ord(EXP_CONDITION);
  if HasCondType then
    CondExpr := CondExpr and (Linq['vt.Id'] = CondTypeId);
  ResExpr := Linq['RecType'] = Ord(TEST_RESULT);
  if HasResType then
    ResExpr := ResExpr and (Linq['vt.Id'] = ResTypeId);
  Expr := ItemExpr and (CondExpr or ResExpr);
  if HasCondType or HasResType then
    Rows := Manager.Find<TValue>
      .CreateAlias('Item', 'i')
      .CreateAlias('ValueType', 'vt')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Group('i.Id').As_('ItemId'))
        .Add(TProjections.Min('RecType').As_('MinRec'))
        .Add(TProjections.Max('RecType').As_('MaxRec')))
      .Where(Expr)
      .ListValues
  else
    Rows := Manager.Find<TValue>
      .CreateAlias('Item', 'i')
      .Select(TProjections.ProjectionList
        .Add(TProjections.Group('i.Id').As_('ItemId'))
        .Add(TProjections.Min('RecType').As_('MinRec'))
        .Add(TProjections.Max('RecType').As_('MaxRec')))
      .Where(Expr)
      .ListValues;
  try
    for Row in Rows do
      if (Integer(Row.Values['MinRec']) = Ord(EXP_CONDITION)) and
         (Integer(Row.Values['MaxRec']) = Ord(TEST_RESULT)) then
        Exit(True);
  finally
    Rows.Free;
  end;
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
  ProjectTitles: TDictionary<Integer, string>;
  ProjectTitle: string;
  RowItems: TList<TPair<TJSONObject, Integer>>;
  RowItem: TPair<TJSONObject, Integer>;
  ItemIds: TList<Integer>;
  Chains: TDictionary<Integer, TAncestorChain>;
  Chain: TAncestorChain;
  Truncated: Boolean;
  Idx: Integer;
  ItemExpr: TLinqExpression;
begin
  Truncated := False;
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
      .OrderBy('Id')
      .List;
  finally
    ItemDic.Free;
  end;

  Arr := TJSONArray.Create;
  ProjectTitles := TDictionary<Integer, string>.Create;
  RowItems := TList<TPair<TJSONObject, Integer>>.Create;
  ItemIds := TList<Integer>.Create;
  try
    try
      try
        for Idx := 0 to Items.Count - 1 do
        begin
          Item := Items[Idx];
          if Arr.Count >= Limit then
          begin
            if RemainingItemExpr(Context, Items, Idx, HasDateFrom, DateFrom,
              HasDateTo, DateTo, ItemExpr) then
              Truncated := HasMoreValues(Context.Manager, ItemExpr, HasRecType,
                FilterRecType, HasValueType, ValueTypeStr);
            Break;
          end;

          // Scope filter: rows from invisible projects are dropped, not
          // refused - this tool reaches across projects by design.
          if not IsProjectVisible(Context, Item.ProjectID) then
            Continue;

          if not ProjectTitles.TryGetValue(Item.ProjectID, ProjectTitle) then
          begin
            Project := Context.Manager.Find<TProject>(Item.ProjectID);
            if Assigned(Project) then
              ProjectTitle := Project.Title
            else
              ProjectTitle := '';
            ProjectTitles.Add(Item.ProjectID, ProjectTitle);
          end;

          for V in Item.Values do
          begin
            if HasRecType and (V.RecType <> FilterRecType) then
              Continue;

            VT := V.ValueType;
            if HasValueType then
            begin
              MatchesType := False;
              if Assigned(VT) then
                MatchesType := ValueTypeNameMatches(VT.Title, VT.Symbol, ValueTypeStr);
              if not MatchesType then
                Continue;
            end;

            if Arr.Count >= Limit then
            begin
              Truncated := True;
              Break;
            end;

            Obj := TJSONObject.Create;
            Arr.AddElement(Obj);
            Obj.AddPair('value_id', TJSONNumber.Create(V.Id));
            Obj.AddPair('item_id', TJSONNumber.Create(Item.Id));
            Obj.AddPair('item_title', Item.Title);
            Obj.AddPair('project_id', TJSONNumber.Create(Item.ProjectID));
            Obj.AddPair('project_title', ProjectTitle);

            if Assigned(VT) then
            begin
              Obj.AddPair('type_id', TJSONNumber.Create(VT.Id));
              Obj.AddPair('type_symbol', VT.Symbol);
              Obj.AddPair('type_title', VT.Title);
              Obj.AddPair('units', VT.Units);
            end
            else
            begin
              Obj.AddPair('type_id', TJSONNull.Create);
              Obj.AddPair('type_symbol', '');
              Obj.AddPair('type_title', '');
              Obj.AddPair('units', '');
            end;

            Obj.AddPair('value', ExactNum(V.Value));
            Obj.AddPair('tolerance', ExactNum(V.Tol));
            Obj.AddPair('rec_type', RecTypeToStr(V.RecType));
            Obj.AddPair('created_date', DateToISO(V.CreatedDate));
            Obj.AddPair('source', ValueSourceJSON(V));
            RowItems.Add(TPair<TJSONObject, Integer>.Create(Obj, Item.Id));
            if not ItemIds.Contains(Item.Id) then
              ItemIds.Add(Item.Id);
          end;

          if Truncated then
            Break;
        end;
      finally
        Items.Free;
      end;

      Chains := AncestorChains(Context.Manager, ItemIds.ToArray);
      try
        for RowItem in RowItems do
        begin
          Chain := Chains[RowItem.Value];
          RowItem.Key.AddPair('ancestor_ids', AncestorIdsJSON(Chain));
          if Chain.Incomplete then
            RowItem.Key.AddPair('ancestors_incomplete', TJSONBool.Create(True));
        end;
      finally
        Chains.Free;
      end;
    except
      Arr.Free;
      raise;
    end;
  finally
    ItemIds.Free;
    RowItems.Free;
    ProjectTitles.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('values', Arr);
  Result.AddPair('limit', TJSONNumber.Create(Limit));
  Result.AddPair('truncated', TJSONBool.Create(Truncated));
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
      if TryStrToInt(CategoryStr, CategoryId) then
        Types := Context.Manager.Find<TValueType>
          .Where(VTDic.CatID = CategoryId)
          .List
      else
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
        Obj.AddPair('range_min', NullableNumJSON(VT.RangeMin));
        Obj.AddPair('range_max', NullableNumJSON(VT.RangeMax));
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
  Result.AddPair('tolerance_factor',
    TJSONNumber.Create(LoadToleranceFactor(Context.Manager)));
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
  Truncated: Boolean;
  Idx: Integer;
  ItemExpr: TLinqExpression;
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

  if not HasProject and not HasCondType and not HasResType then
    raise Exception.Create('At least one of project_id, condition_type_id, ' +
      'or result_type_id must be provided');

  ItemDic := TItemDictionary.Create;
  try
    Criteria := (ItemDic.IsDeleted = False);
    if HasProject then
      Criteria := Criteria and (ItemDic.ProjectID = ProjectId);

    Items := Context.Manager.Find<TItem>
      .Where(Criteria)
      .OrderBy('Id')
      .List;
  finally
    ItemDic.Free;
  end;

  Arr := TJSONArray.Create;
  Count := 0;
  Truncated := False;
  try
    try
      for Idx := 0 to Items.Count - 1 do
      begin
        Item := Items[Idx];
        if Count >= Limit then
        begin
          if RemainingItemExpr(Context, Items, Idx, False, 0, False, 0,
            ItemExpr) then
            Truncated := HasMorePairs(Context.Manager, ItemExpr, HasCondType,
              CondTypeId, HasResType, ResTypeId);
          Break;
        end;

        if not IsProjectVisible(Context, Item.ProjectID) then
          Continue;

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
  Result.AddPair('truncated', TJSONBool.Create(Truncated));
end;


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


procedure RegisterValueTools(Registry: TToolRegistry);
begin
  Registry.Register('get_values',
    'Get all recorded values for an item, grouped by type: experimental ' +
    'conditions (inputs) and test results (outputs). Each value includes ' +
    'its type symbol, title, units, tolerance, description and source ' +
    '(kind Reader, Manual or Unknown, with file_id, reader_id, ' +
    'reader_version, key_name and note when recorded).',
    MakeGetValuesSchema, HandleGetValues, tscProjectScoped, taRead);

  Registry.Register('query_values',
    'Search for values across items with optional filters by project, ' +
    'value type (title or symbol), record type (EXP_CONDITION or ' +
    'TEST_RESULT), and date range. Returns value details with item and ' +
    'project context and the value source. truncated is true when more ' +
    'rows matched than limit.',
    MakeQueryValuesSchema, HandleQueryValues, tscProjectScoped, taRead);

  Registry.Register('list_value_types',
    'List all defined value types (measurement parameters). Each type has ' +
    'a symbol (e.g. W for power), title, units, category and plausible ' +
    'range (range_min/range_max in the type units, null = no limit). ' +
    'tolerance_factor is the notebook limit for the tolerance check: a ' +
    'tolerance must not exceed |value| and must not be smaller than ' +
    '|value| / tolerance_factor. Optionally filter by category ID.',
    MakeListValueTypesSchema, HandleListValueTypes, tscGlobalRef, taRead);

  Registry.Register('correlate_values',
    'Find correlations between experimental conditions and test results. ' +
    'Returns items that have both condition and result values, paired for ' +
    'analysis. At least one of project_id, condition_type_id, or ' +
    'result_type_id must be provided. This is the primary analytical tool ' +
    'for discovering relationships between inputs and outputs. truncated ' +
    'is true when more rows matched than limit.',
    MakeCorrelateValuesSchema, HandleCorrelateValues, tscProjectScoped, taRead);
end;

end.
