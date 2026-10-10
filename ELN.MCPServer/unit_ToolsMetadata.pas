unit unit_ToolsMetadata;

interface

uses
  System.JSON,
  unit_MCPTools;

procedure RegisterMetadataTools(Registry: TToolRegistry);

function HandleListTags(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleListUsers(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleGetAuditLog(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.TypInfo,
  System.DateUtils, System.Rtti,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_Item, unit_Project, unit_ItemTypes, unit_ELNDB_Dictionary,
  unit_Tag, unit_ItemLink, unit_Equipment, unit_EquipmentType,
  unit_ActionType, unit_Protocol, unit_LabEntry,
  unit_ProtocolStatusChange, unit_AuditLog, unit_Comment,
  unit_Signature, unit_User, unit_AuditRule, unit_FileType, unit_ValueType,
  Aurelius.Criteria.Base, Aurelius.Criteria.Projections,
  unit_ToolScope, unit_Hypothesis, unit_HypothesisModel, unit_ToolsWrite;

const
  // Upper bound on AuditLog rows scanned for a project's recent-activity list.
  // The project-membership filter runs in Pascal, so we cannot LIMIT to the 10
  // results directly; this caps the in-memory window instead of loading the
  // whole table.
  PROJECT_ACTIVITY_SCAN_LIMIT = 500;


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


function ActionKindToStr(AKind: TActionKind): string;
begin
  Result := TRttiEnumerationType.GetName<TActionKind>(AKind);
end;

function ItemTypeToStr(AType: TItemType): string;
begin
  Result := TRttiEnumerationType.GetName<TItemType>(AType);
end;

function ProtocolTypeToStr(AType: TProtocolType): string;
begin
  Result := TRttiEnumerationType.GetName<TProtocolType>(AType);
end;

function ValidationStatusToStr(AStatus: TValidationStatus): string;
begin
  Result := TRttiEnumerationType.GetName<TValidationStatus>(AStatus);
end;


function HandleListTags(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Tags: TList<TTag>;
  Tag: TTag;
  ItemTags: TList<TItemTag>;
  ItemTagDic: TItemTagDictionary;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Tags := Context.Manager.Find<TTag>.List;
  try
    ItemTagDic := TItemTagDictionary.Create;
    try
      Arr := TJSONArray.Create;
      try
        for Tag in Tags do
        begin
          ItemTags := Context.Manager.Find<TItemTag>
            .Where(ItemTagDic.TagId = Tag.Id)
            .List;
          try
            Obj := TJSONObject.Create;
            Obj.AddPair('id', TJSONNumber.Create(Tag.Id));
            Obj.AddPair('name', Tag.Name);
            Obj.AddPair('color', Tag.Color);
            Obj.AddPair('item_count', TJSONNumber.Create(ItemTags.Count));
            Arr.AddElement(Obj);
          finally
            ItemTags.Free;
          end;
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('tags', Arr);
    finally
      ItemTagDic.Free;
    end;
  finally
    Tags.Free;
  end;
end;


function HandleGetItemLinks(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  LinkDic: TItemLinkDictionary;
  OutLinks, InLinks: TList<TItemLink>;
  Link: TItemLink;
  LinkedItem: TItem;
  Arr: TJSONArray;
  Obj: TJSONObject;
  LinkedTitle: string;
begin
  ItemId := GetReqInt(Params, 'item_id');
  // Refuse missing or unreadable items. The per-link filter below checks
  // the OTHER end against the access policy and any additional session scope.
  RequireItemRead(Context, ItemId);

  LinkDic := TItemLinkDictionary.Create;
  try
    OutLinks := Context.Manager.Find<TItemLink>
      .Where(LinkDic.SourceItemId = ItemId)
      .List;
    try
      InLinks := Context.Manager.Find<TItemLink>
        .Where(LinkDic.TargetItemId = ItemId)
        .List;
      try
        Arr := TJSONArray.Create;
        try
          for Link in OutLinks do
          begin
            LinkedItem := Context.Manager.Find<TItem>(Link.TargetItemId);
            // Never expose an unreadable or dangling endpoint, even without
            // a device scope. An unresolved project is also invisible.
            if not Assigned(LinkedItem) then
              Continue;
            if (LinkedItem.ProjectID = 0) or
               not IsProjectVisible(Context, LinkedItem.ProjectID) or
               not Assigned(Context.Manager.Find<TProject>(LinkedItem.ProjectID)) then
              Continue;
            LinkedTitle := LinkedItem.Title;

            Obj := TJSONObject.Create;
            Obj.AddPair('link_id', TJSONNumber.Create(Link.Id));
            Obj.AddPair('direction', 'outgoing');
            Obj.AddPair('linked_item_id', TJSONNumber.Create(Link.TargetItemId));
            Obj.AddPair('linked_item_title', LinkedTitle);
            // Read the relation from this item's perspective: source uses forward text.
            if Assigned(Link.LinkType) then
              Obj.AddPair('relation', Link.LinkType.ForwardText)
            else
              Obj.AddPair('relation', Link.Label_);
            Obj.AddPair('notes', Link.Notes);
            Obj.AddPair('created_by', TJSONNumber.Create(Link.CreatedBy));
            Obj.AddPair('created_date', DateToISO(Link.CreatedDate));
            Arr.AddElement(Obj);
          end;

          for Link in InLinks do
          begin
            LinkedItem := Context.Manager.Find<TItem>(Link.SourceItemId);
            if not Assigned(LinkedItem) then
              Continue;
            if (LinkedItem.ProjectID = 0) or
               not IsProjectVisible(Context, LinkedItem.ProjectID) or
               not Assigned(Context.Manager.Find<TProject>(LinkedItem.ProjectID)) then
              Continue;
            LinkedTitle := LinkedItem.Title;

            Obj := TJSONObject.Create;
            Obj.AddPair('link_id', TJSONNumber.Create(Link.Id));
            Obj.AddPair('direction', 'incoming');
            Obj.AddPair('linked_item_id', TJSONNumber.Create(Link.SourceItemId));
            Obj.AddPair('linked_item_title', LinkedTitle);
            // This item is the target, so use the reverse relation text.
            if Assigned(Link.LinkType) then
              Obj.AddPair('relation', Link.LinkType.ReverseText)
            else
              Obj.AddPair('relation', Link.Label_);
            Obj.AddPair('notes', Link.Notes);
            Obj.AddPair('created_by', TJSONNumber.Create(Link.CreatedBy));
            Obj.AddPair('created_date', DateToISO(Link.CreatedDate));
            Arr.AddElement(Obj);
          end;
        except
          Arr.Free;
          raise;
        end;

        Result := TJSONObject.Create;
        Result.AddPair('links', Arr);
      finally
        InLinks.Free;
      end;
    finally
      OutLinks.Free;
    end;
  finally
    LinkDic.Free;
  end;
end;


function HandleListEquipment(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  EquipTypeId: Integer;
  HasTypeFilter: Boolean;
  EquipDic: TEquipmentDictionary;
  Equipments: TList<TEquipment>;
  Equip: TEquipment;
  Arr: TJSONArray;
  Obj: TJSONObject;
  TypeName: string;
begin
  HasTypeFilter := GetOptInt(Params, 'equipment_type_id', EquipTypeId);

  EquipDic := TEquipmentDictionary.Create;
  try
    if HasTypeFilter then
      Equipments := Context.Manager.Find<TEquipment>
        .Where(EquipDic.Equipmenttypeid.Id = EquipTypeId)
        .List
    else
      Equipments := Context.Manager.Find<TEquipment>.List;

    try
      Arr := TJSONArray.Create;
      try
        for Equip in Equipments do
        begin
          if Assigned(Equip.EquipmentType) then
            TypeName := Equip.EquipmentType.Type_
          else
            TypeName := '';

          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(Equip.Id));
          Obj.AddPair('model', Equip.Model);
          Obj.AddPair('manufacturer', Equip.Manufacturer);
          Obj.AddPair('location', Equip.Location);
          Obj.AddPair('urls', Equip.BookingUrl + ' ' + Equip.InfoUrl);
          Obj.AddPair('equipment_type', TypeName);
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('equipment', Arr);
    finally
      Equipments.Free;
    end;
  finally
    EquipDic.Free;
  end;
end;


function HandleListActionTypes(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  KindStr: string;
  HasKind: Boolean;
  Kind: TActionKind;
  V: Integer;
  ActionTypeDic: TActionTypeDictionary;
  ActionTypes: TList<TActionType>;
  AT: TActionType;
  Arr: TJSONArray;
  Obj: TJSONObject;
  EquipTypeName, EquipName: string;
begin
  Kind := TActionKind(0);
  HasKind := GetOptStr(Params, 'kind', KindStr);

  if HasKind then
  begin
    V := GetEnumValue(TypeInfo(TActionKind), KindStr);
    if V < 0 then
      raise Exception.CreateFmt('Invalid kind: %s', [KindStr]);
    Kind := TActionKind(V);
  end;

  ActionTypeDic := TActionTypeDictionary.Create;
  try
    if HasKind then
      ActionTypes := Context.Manager.Find<TActionType>
        .Where(ActionTypeDic.Kind = Ord(Kind))
        .List
    else
      ActionTypes := Context.Manager.Find<TActionType>.List;

    try
      Arr := TJSONArray.Create;
      try
        for AT in ActionTypes do
        begin
          if Assigned(AT.EquipmentType) then
            EquipTypeName := AT.EquipmentType.Type_
          else
            EquipTypeName := '';

          if Assigned(AT.Equipment) then
            EquipName := AT.Equipment.Model
          else
            EquipName := '';

          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(AT.Id));
          Obj.AddPair('kind', ActionKindToStr(AT.Kind));
          Obj.AddPair('item_type', ItemTypeToStr(AT.ItemType));
          Obj.AddPair('title', AT.Title);
          Obj.AddPair('description', AT.Description);
          Obj.AddPair('equipment_type', EquipTypeName);
          Obj.AddPair('equipment', EquipName);
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('action_types', Arr);
    finally
      ActionTypes.Free;
    end;
  finally
    ActionTypeDic.Free;
  end;
end;


function HandleGetProtocols(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  Item: TItem;
  E: TLabEntry;
  P: TProtocol;
  PSCDic: TProtocolStatusChangeDictionary;
  StatusChanges: TList<TProtocolStatusChange>;
  SC: TProtocolStatusChange;
  Arr, HistArr: TJSONArray;
  Obj, HistObj: TJSONObject;
  ProtTypeStr: string;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  Item := Context.Manager.Find<TItem>(ItemId);
  if not Assigned(Item) then
    raise Exception.CreateFmt('Item not found: %d', [ItemId]);

  PSCDic := TProtocolStatusChangeDictionary.Create;
  try
    Arr := TJSONArray.Create;
    try
      for E in Item.Entries do
      begin
        if not (E is TProtocol) then
          Continue;

        P := TProtocol(E);

        if P.ProtocolType.HasValue then
          ProtTypeStr := ProtocolTypeToStr(P.ProtocolType.Value)
        else
          ProtTypeStr := '';

        StatusChanges := Context.Manager.Find<TProtocolStatusChange>
          .Where(PSCDic.ProtocolId = P.Id)
          .List;
        try
          HistArr := TJSONArray.Create;
          for SC in StatusChanges do
          begin
            HistObj := TJSONObject.Create;
            HistObj.AddPair('old_status', ValidationStatusToStr(SC.OldStatus));
            HistObj.AddPair('new_status', ValidationStatusToStr(SC.NewStatus));
            HistObj.AddPair('changed_by', TJSONNumber.Create(SC.ChangedBy));
            HistObj.AddPair('changed_date', DateToISO(SC.ChangedDate));
            HistObj.AddPair('comment', SC.Comment);
            HistArr.AddElement(HistObj);
          end;
        finally
          StatusChanges.Free;
        end;

        Obj := TJSONObject.Create;
        Obj.AddPair('id', TJSONNumber.Create(P.Id));
        Obj.AddPair('title', P.Title);
        Obj.AddPair('protocol_type', ProtTypeStr);
        Obj.AddPair('validation_status', ValidationStatusToStr(P.ValidationStatus));
        Obj.AddPair('form_data', P.FormData);
        Obj.AddPair('equip_model', P.EquipModel);
        Obj.AddPair('equip_manufacturer', P.EquipManufacturer);
        Obj.AddPair('equip_location', P.EquipLocation);
        Obj.AddPair('created_date', DateToISO(P.CreatedDate));
        Obj.AddPair('modified_date', NullableDateToJSON(P.ModifiedDate));
        Obj.AddPair('status_history', HistArr);
        Arr.AddElement(Obj);
      end;
    except
      Arr.Free;
      raise;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('protocols', Arr);
  finally
    PSCDic.Free;
  end;
end;


// The project an audit row belongs to, or 0 when it cannot be resolved:
// aetFolder, aetProtocol and aetNote have no queryable FK back to their owner
// (the parent side owns those associations), and a deleted entity resolves to
// nothing. aetSetting (global settings/approval policy, e.g.
// HYPOTHESIS_APPROVAL_POLICY) is the same: those rows are not project-scoped
// at all, so they get the identical treatment. Unresolvable rows are always
// dropped, including without a device scope: project 0 must not inherit a
// privileged policy's permission to read all projects.
// aetHypothesis DOES belong to a project (THypothesis.ProjectId is a plain
// required column). HypothesisProjects is a HypothesisId->ProjectId map built
// once per get_audit_log call for every distinct hypothesis id on the current
// page (see HandleGetAuditLog) - one query for the whole page, not one
// Find<THypothesis> per row.
function AuditRowProject(const Context: TToolContext; Log: TAuditLog;
  HypothesisProjects: TDictionary<Integer, Integer>): Integer;
var
  F: unit_Item.TFile;
  V: TValue;
  Sig: TSignature;
begin
  Result := 0;
  case Log.EntityType of
    aetProject:
      Result := Log.EntityId;
    aetItem:
      Result := ProjectOfItem(Context, Log.EntityId);
    aetFile:
      begin
        F := Context.Manager.Find<unit_Item.TFile>(Log.EntityId);
        if Assigned(F) and Assigned(F.Item) then
          Result := F.Item.ProjectID;
      end;
    aetValue:
      begin
        V := Context.Manager.Find<TValue>(Log.EntityId);
        if Assigned(V) and Assigned(V.Item) then
          Result := V.Item.ProjectID;
      end;
    aetSignature:
      begin
        Sig := Context.Manager.Find<TSignature>(Log.EntityId);
        if Assigned(Sig) then
          Result := ProjectOfItem(Context, Sig.ItemId);
      end;
    aetHypothesis:
      if Assigned(HypothesisProjects) then
        HypothesisProjects.TryGetValue(Log.EntityId, Result);
    aetSetting:
      Result := 0; // global, no project - see comment above
  end;
end;

function HandleGetAuditLog(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  EntityTypeStr, OperationStr, DateFromStr, DateToStr: string;
  HasEntityType, HasEntityId, HasOperation, HasUserId: Boolean;
  HasDateFrom, HasDateTo, HasLimit: Boolean;
  EntityId: Int64;
  UserId, Limit: Integer;
  EntityTypeVal: TAuditEntityType;
  OperationVal: TAuditOperation;
  DateFrom, DateTo: TDateTime;
  V: Integer;
  AuditDic: TAuditLogDictionary;
  Criteria: TLinqExpression;
  HasCriteria: Boolean;
  Logs: TList<TAuditLog>;
  Log: TAuditLog;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, Count, ProjectId: Integer;
  HypIds: TList<Integer>;
  HypProjects: TDictionary<Integer, Integer>;
  Chunk: TArray<Variant>;
  Rows: TObjectList<TCriteriaResult>;
  Row: TCriteriaResult;
begin
  EntityTypeVal := TAuditEntityType(0);
  OperationVal := TAuditOperation(0);
  DateFrom := 0;
  DateTo := 0;

  HasEntityType := GetOptStr(Params, 'entity_type', EntityTypeStr);
  HasEntityId := GetOptInt64(Params, 'entity_id', EntityId);
  HasOperation := GetOptStr(Params, 'operation', OperationStr);
  HasUserId := GetOptInt(Params, 'user_id', UserId);
  HasDateFrom := GetOptStr(Params, 'date_from', DateFromStr);
  HasDateTo := GetOptStr(Params, 'date_to', DateToStr);
  HasLimit := GetOptInt(Params, 'limit', Limit);
  if not HasLimit then
    Limit := 100;
  // Hard cap — a client passing limit=9999999 would otherwise re-materialize
  // the entire ever-growing AuditLog table over the wire in one response,
  // stalling the single-threaded MCP loop for all concurrent callers.
  if Limit > 5000 then
    Limit := 5000
  else if Limit < 1 then
    Limit := 1;

  if HasEntityType then
  begin
    V := GetEnumValue(TypeInfo(TAuditEntityType), 'aet' + EntityTypeStr);
    if V < 0 then
      raise Exception.CreateFmt('Invalid entity_type: %s', [EntityTypeStr]);
    EntityTypeVal := TAuditEntityType(V);
  end;

  if HasOperation then
  begin
    V := GetEnumValue(TypeInfo(TAuditOperation), 'ao' + OperationStr);
    if V < 0 then
      raise Exception.CreateFmt('Invalid operation: %s', [OperationStr]);
    OperationVal := TAuditOperation(V);
  end;

  if HasDateFrom then
    DateFrom := ISO8601ToDate(DateFromStr, False);
  if HasDateTo then
    DateTo := ISO8601ToDate(DateToStr, False);

  AuditDic := TAuditLogDictionary.Create;
  try
    HasCriteria := False;

    if HasEntityType then
    begin
      Criteria := AuditDic.EntityType = Ord(EntityTypeVal);
      HasCriteria := True;
    end;

    if HasEntityId then
    begin
      if HasCriteria then
        Criteria := Criteria and (AuditDic.EntityId = EntityId)
      else
      begin
        Criteria := AuditDic.EntityId = EntityId;
        HasCriteria := True;
      end;
    end;

    if HasOperation then
    begin
      if HasCriteria then
        Criteria := Criteria and (AuditDic.Operation = Ord(OperationVal))
      else
      begin
        Criteria := AuditDic.Operation = Ord(OperationVal);
        HasCriteria := True;
      end;
    end;

    if HasUserId then
    begin
      if HasCriteria then
        Criteria := Criteria and (AuditDic.UserId = UserId)
      else
      begin
        Criteria := AuditDic.UserId = UserId;
        HasCriteria := True;
      end;
    end;

    if HasDateFrom then
    begin
      if HasCriteria then
        Criteria := Criteria and (AuditDic.Timestamp >= DateFrom)
      else
      begin
        Criteria := AuditDic.Timestamp >= DateFrom;
        HasCriteria := True;
      end;
    end;

    if HasDateTo then
    begin
      if HasCriteria then
        Criteria := Criteria and (AuditDic.Timestamp <= DateTo)
      else
      begin
        Criteria := AuditDic.Timestamp <= DateTo;
        HasCriteria := True;
      end;
    end;

    // Push the limit into SQL. Without Take, the whole AuditLog table (the one
    // table guaranteed to grow without bound) was materialized over the wire
    // and truncated to Limit only while building JSON.
    if HasCriteria then
      Logs := Context.Manager.Find<TAuditLog>
        .Where(Criteria)
        .OrderBy(AuditDic.Timestamp, False)
        .Take(Limit)
        .List
    else
      Logs := Context.Manager.Find<TAuditLog>
        .OrderBy(AuditDic.Timestamp, False)
        .Take(Limit)
        .List;

    HypProjects := nil;
    try
      // Batch-resolve hypothesis projects for this page BEFORE the row loop:
      // one query for every distinct hypothesis id on the page, not one
      // Find<THypothesis> per audit row (DM-8/U30), with or without a scope.
      HypIds := TList<Integer>.Create;
      try
        for I := 0 to Logs.Count - 1 do
          if (Logs[I].EntityType = aetHypothesis) and
             (not HypIds.Contains(Logs[I].EntityId)) then
            HypIds.Add(Logs[I].EntityId);

        // IN lists of 500 ids (a page has up to 5000; one OR term per id
        // overflows SQLite's parser). A projection: the shared session
        // manager does not load and keep the hypotheses.
        HypProjects := TDictionary<Integer, Integer>.Create;
        for Chunk in IdChunks(HypIds.ToArray) do
        begin
          Rows := Context.Manager.Find<THypothesis>
            .Select(TProjections.ProjectionList
              .Add(TProjections.Prop('Id').As_('Id'))
              .Add(TProjections.Prop('ProjectId').As_('ProjectId')))
            .Where(Linq['Id']._In(Chunk))
            .ListValues;
          try
            for Row in Rows do
              HypProjects.AddOrSetValue(Integer(Row.Values['Id']),
                Integer(Row.Values['ProjectId']));
          finally
            Rows.Free;
          end;
        end;
      finally
        HypIds.Free;
      end;

      Arr := TJSONArray.Create;
      try
        Count := Logs.Count;
        if Count > Limit then
          Count := Limit;

        for I := 0 to Count - 1 do
        begin
          Log := Logs[I];

          // Apply policy visibility and additional session scope to every row.
          // Unknown subjects and deleted projects fail closed, including for
          // privileged policies. Filtering may return fewer than Limit rows.
          ProjectId := AuditRowProject(Context, Log, HypProjects);
          if (ProjectId = 0) or
             not IsProjectVisible(Context, ProjectId) or
             not Assigned(Context.Manager.Find<TProject>(ProjectId)) then
            Continue;

          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(Log.Id));
          Obj.AddPair('entity_type', AuditEntityTypeNames[Log.EntityType]);
          Obj.AddPair('entity_id', TJSONNumber.Create(Log.EntityId));
          Obj.AddPair('operation', AuditOperationNames[Log.Operation]);
          Obj.AddPair('user_id', TJSONNumber.Create(Log.UserId));
          Obj.AddPair('timestamp', DateToISO(Log.Timestamp));
          Obj.AddPair('description', Log.Description);
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('audit_log', Arr);
    finally
      Logs.Free;
      HypProjects.Free;
    end;
  finally
    AuditDic.Free;
  end;
end;


function HandleGetComments(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  CommentDic: TCommentDictionary;
  Comments: TList<TComment>;
  C: TComment;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  CommentDic := TCommentDictionary.Create;
  try
    Comments := Context.Manager.Find<TComment>
      .Where(CommentDic.ItemId = ItemId)
      .List;
    try
      Arr := TJSONArray.Create;
      try
        for C in Comments do
        begin
          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(C.Id));
          Obj.AddPair('user_name', C.UserName);
          Obj.AddPair('text', C.Text);
          Obj.AddPair('created_date', DateToISO(C.CreatedDate));
          Obj.AddPair('modified_date', NullableDateToJSON(C.ModifiedDate));
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('comments', Arr);
    finally
      Comments.Free;
    end;
  finally
    CommentDic.Free;
  end;
end;


function HandleGetSignatures(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ItemId: Integer;
  SigDic: TSignatureDictionary;
  Signatures: TList<TSignature>;
  S: TSignature;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);

  SigDic := TSignatureDictionary.Create;
  try
    Signatures := Context.Manager.Find<TSignature>
      .Where(SigDic.ItemId = ItemId)
      .List;
    try
      Arr := TJSONArray.Create;
      try
        for S in Signatures do
        begin
          Obj := TJSONObject.Create;
          Obj.AddPair('id', TJSONNumber.Create(S.Id));
          Obj.AddPair('user_name', S.UserName);
          Obj.AddPair('signed_date', DateToISO(S.SignedDate));
          Obj.AddPair('meaning', S.Meaning);
          Obj.AddPair('comment', S.Comment);
          Obj.AddPair('content_hash', S.ContentHash);
          Arr.AddElement(Obj);
        end;
      except
        Arr.Free;
        raise;
      end;

      Result := TJSONObject.Create;
      Result.AddPair('signatures', Arr);
    finally
      Signatures.Free;
    end;
  finally
    SigDic.Free;
  end;
end;

{ --- Tool 9: list_users --- }

function HandleListUsers(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Users: TList<TUser>;
  U: TUser;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  RequireToolPrincipal(Context);
  Users := Context.Manager.Find<TUser>.List;
  try
    Arr := TJSONArray.Create;
    try
      for U in Users do
      begin
        // A confined session must not enumerate other laboratory accounts.
        if (Length(Context.ScopedProjects) > 0) and
           ((Context.User = nil) or (U.Id <> Context.User.Id)) then
          Continue;

        Obj := TJSONObject.Create;
        Obj.AddPair('id', TJSONNumber.Create(U.Id));
        Obj.AddPair('username', U.Username);
        Obj.AddPair('first_name', U.FirstName);
        Obj.AddPair('last_name', U.LastName);
        Obj.AddPair('email', U.Email);
        Obj.AddPair('role', U.RoleString);
        Arr.AddElement(Obj);
      end;
    except
      Arr.Free;
      raise;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('users', Arr);
  finally
    Users.Free;
  end;
end;


function HandleGetProjectStats(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  ProjectId: Integer;
  Project: TProject;
  ItemDic: TItemDictionary;
  AuditDic: TAuditLogDictionary;
  Items: TList<TItem>;
  Item: TItem;
  FileCount, ValueCount, ProtocolCount, TagCount: Integer;
  E: TLabEntry;
  ItemTagDic: TItemTagDictionary;
  ItemTags: TList<TItemTag>;
  TagIds: TList<Integer>;
  AuditLogs: TList<TAuditLog>;
  Log: TAuditLog;
  ItemIds: TList<Integer>;
  ActivityArr: TJSONArray;
  Obj: TJSONObject;
  I, Count: Integer;
begin
  ProjectId := GetReqInt(Params, 'project_id');
  RequireProjectRead(Context, ProjectId);

  Project := Context.Manager.Find<TProject>(ProjectId);
  if not Assigned(Project) then
    raise Exception.CreateFmt('Project not found: %d', [ProjectId]);

  ItemDic := TItemDictionary.Create;
  try
    Items := Context.Manager.Find<TItem>
      .Where((ItemDic.ProjectID = ProjectId) and (ItemDic.IsDeleted = False))
      .List;
    try
      FileCount := 0;
      ValueCount := 0;
      ProtocolCount := 0;

      for Item in Items do
      begin
        FileCount := FileCount + Item.Files.Count;
        ValueCount := ValueCount + Item.Values.Count;
        for E in Item.Entries do
        begin
          if E is TProtocol then
            Inc(ProtocolCount);
        end;
      end;

      ItemTagDic := TItemTagDictionary.Create;
      try
        TagIds := TList<Integer>.Create;
        try
          for Item in Items do
          begin
            ItemTags := Context.Manager.Find<TItemTag>
              .Where(ItemTagDic.ItemId = Item.Id)
              .List;
            try
              for I := 0 to ItemTags.Count - 1 do
              begin
                if not TagIds.Contains(ItemTags[I].TagId) then
                  TagIds.Add(ItemTags[I].TagId);
              end;
            finally
              ItemTags.Free;
            end;
          end;
          TagCount := TagIds.Count;
        finally
          TagIds.Free;
        end;
      finally
        ItemTagDic.Free;
      end;

      ItemIds := TList<Integer>.Create;
      try
        for Item in Items do
          ItemIds.Add(Item.Id);

        // Get last 10 audit entries scoped to this project. The project filter
        // runs in Pascal, so we scan a bounded recent window rather than the
        // whole (unbounded) AuditLog table — generous enough to almost always
        // contain 10 project-scoped rows.
        AuditDic := TAuditLogDictionary.Create;
        try
          AuditLogs := Context.Manager.Find<TAuditLog>
            .OrderBy(AuditDic.Timestamp, False)
            .Take(PROJECT_ACTIVITY_SCAN_LIMIT)
            .List;
          try
            ActivityArr := TJSONArray.Create;
            Count := 0;

            for I := 0 to AuditLogs.Count - 1 do
            begin
              if Count >= 10 then
                Break;

              Log := AuditLogs[I];

              if (Log.EntityType = aetProject) and (Log.EntityId = ProjectId) then
              begin
              end
              else if (Log.EntityType = aetItem) and ItemIds.Contains(Log.EntityId) then
              begin
              end
              else
                Continue;

              Obj := TJSONObject.Create;
              Obj.AddPair('id', TJSONNumber.Create(Log.Id));
              Obj.AddPair('entity_type', AuditEntityTypeNames[Log.EntityType]);
              Obj.AddPair('operation', AuditOperationNames[Log.Operation]);
              Obj.AddPair('timestamp', DateToISO(Log.Timestamp));
              Obj.AddPair('description', Log.Description);
              ActivityArr.AddElement(Obj);
              Inc(Count);
            end;
          finally
            AuditLogs.Free;
          end;
        finally
          AuditDic.Free;
        end;
      finally
        ItemIds.Free;
      end;

      Result := TJSONObject.Create;
      try
        Result.AddPair('project_title', Project.Title);
        Result.AddPair('item_count', TJSONNumber.Create(Items.Count));
        Result.AddPair('file_count', TJSONNumber.Create(FileCount));
        Result.AddPair('value_count', TJSONNumber.Create(ValueCount));
        Result.AddPair('protocol_count', TJSONNumber.Create(ProtocolCount));
        Result.AddPair('tag_count', TJSONNumber.Create(TagCount));
        Result.AddPair('recent_activity', ActivityArr);
      except
        Result.Free;
        raise;
      end;
    finally
      Items.Free;
    end;
  finally
    ItemDic.Free;
  end;
end;


function HandleListAuditRules(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Rules: TList<TAuditRule>;
  Rule: TAuditRule;
  RuleFile: TAuditRuleFile;
  RuleValue: TAuditRuleValue;
  Arr, FilesArr, ValuesArr: TJSONArray;
  Obj, FileObj, ValueObj: TJSONObject;
  SeverityStr: string;
begin
  Rules := Context.Manager.Find<TAuditRule>.List;
  try
    Arr := TJSONArray.Create;
    try
      for Rule in Rules do
      begin
        case Rule.Severity of
          asError:   SeverityStr := 'Error';
          asWarning: SeverityStr := 'Warning';
        else
          SeverityStr := 'Unknown';
        end;

        Obj := TJSONObject.Create;
        Obj.AddPair('id', TJSONNumber.Create(Rule.Id));
        Obj.AddPair('title', Rule.Title);
        Obj.AddPair('is_active', TJSONBool.Create(Rule.IsActive));
        Obj.AddPair('severity', SeverityStr);
        Obj.AddPair('description', Rule.Description);

        if Assigned(Rule.ActionType) then
        begin
          Obj.AddPair('action_type_id', TJSONNumber.Create(Rule.ActionType.Id));
          Obj.AddPair('action_type', Rule.ActionType.Title);
        end
        else
        begin
          Obj.AddPair('action_type_id', TJSONNull.Create);
          Obj.AddPair('action_type', TJSONNull.Create);
        end;

        if Assigned(Rule.Equipment) then
        begin
          Obj.AddPair('equipment_id', TJSONNumber.Create(Rule.Equipment.Id));
          Obj.AddPair('equipment', Rule.Equipment.Model);
        end
        else
        begin
          Obj.AddPair('equipment_id', TJSONNull.Create);
          Obj.AddPair('equipment', TJSONNull.Create);
        end;

        FilesArr := TJSONArray.Create;
        for RuleFile in Rule.RequiredFiles do
        begin
          if Assigned(RuleFile.FileType) then
          begin
            FileObj := TJSONObject.Create;
            FileObj.AddPair('id', TJSONNumber.Create(RuleFile.FileType.Id));
            FileObj.AddPair('ext', RuleFile.FileType.Ext);
            FileObj.AddPair('description', RuleFile.FileType.Description);
            FilesArr.AddElement(FileObj);
          end;
        end;
        Obj.AddPair('required_files', FilesArr);

        ValuesArr := TJSONArray.Create;
        for RuleValue in Rule.RequiredValues do
        begin
          if Assigned(RuleValue.ValueType) then
          begin
            ValueObj := TJSONObject.Create;
            ValueObj.AddPair('id', TJSONNumber.Create(RuleValue.ValueType.Id));
            ValueObj.AddPair('symbol', RuleValue.ValueType.Symbol);
            ValueObj.AddPair('title', RuleValue.ValueType.Title);
            ValueObj.AddPair('units', RuleValue.ValueType.Units);
            ValuesArr.AddElement(ValueObj);
          end;
        end;
        Obj.AddPair('required_values', ValuesArr);

        Arr.AddElement(Obj);
      end;

      Result := TJSONObject.Create;
      Result.AddPair('rules', Arr);
    except
      Arr.Free;
      raise;
    end;
  finally
    Rules.Free;
  end;
end;


function MakeEmptySchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', TJSONObject.Create);
end;

function MakeItemIdSchema(const Desc: string): TJSONObject;
var
  Props, ItemId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ItemId := TJSONObject.Create;
  ItemId.AddPair('type', 'integer');
  ItemId.AddPair('description', Desc);
  Props.AddPair('item_id', ItemId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('item_id');
  Result.AddPair('required', Req);
end;

function MakeListEquipmentSchema: TJSONObject;
var
  Props, EquipTypeId: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  EquipTypeId := TJSONObject.Create;
  EquipTypeId.AddPair('type', 'integer');
  EquipTypeId.AddPair('description', 'Filter by equipment type ID');
  Props.AddPair('equipment_type_id', EquipTypeId);
  Result.AddPair('properties', Props);
end;

function MakeListActionTypesSchema: TJSONObject;
var
  Props, KindProp: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  KindProp := TJSONObject.Create;
  KindProp.AddPair('type', 'string');
  KindProp.AddPair('description',
    'Filter by kind: Synthesys, Testing, Measurement, Analysis, Simulation, Other');
  Props.AddPair('kind', KindProp);
  Result.AddPair('properties', Props);
end;

function MakeGetAuditLogSchema: TJSONObject;
var
  Props, P: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description',
    'Filter by entity type: Project, Folder, Item, File, Protocol, Note, Value, Signature');
  Props.AddPair('entity_type', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Filter by entity ID');
  Props.AddPair('entity_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Filter by operation: Create, Update, Delete');
  Props.AddPair('operation', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description', 'Filter by user ID');
  Props.AddPair('user_id', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Start date filter (ISO 8601)');
  Props.AddPair('date_from', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'End date filter (ISO 8601)');
  Props.AddPair('date_to', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'integer');
  P.AddPair('description',
    'Max audit rows to examine (default: 100, capped at 5000). ' +
    'Rows outside visible projects or with unresolved subjects are omitted.');
  Props.AddPair('limit', P);

  Result.AddPair('properties', Props);
end;

function MakeProjectIdSchema: TJSONObject;
var
  Props, ProjId: TJSONObject;
  Req: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  ProjId := TJSONObject.Create;
  ProjId.AddPair('type', 'integer');
  ProjId.AddPair('description', 'Project ID');
  Props.AddPair('project_id', ProjId);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('project_id');
  Result.AddPair('required', Req);
end;


procedure RegisterMetadataTools(Registry: TToolRegistry);
begin
  Registry.Register('list_tags',
    'List all tags with item counts. Returns tag name, color, and ' +
    'number of items using each tag.',
    MakeEmptySchema, HandleListTags, tscGlobalRef);

  Registry.Register('get_item_links',
    'Get bidirectional links for an item. Returns only links to existing ' +
    'items in visible projects, with linked item titles. The "relation" field is the ' +
    'relationship phrase as read FROM THE QUERIED ITEM: an outgoing link ' +
    'uses the type''s forward caption ("derived from"), an incoming link its ' +
    'reverse caption ("precursor of"), so it always reads correctly.',
    MakeItemIdSchema('Item ID to get links for'), HandleGetItemLinks,
    tscProjectScoped);

  Registry.Register('list_equipment',
    'List equipment with type grouping. Optionally filter by equipment type.',
    MakeListEquipmentSchema, HandleListEquipment, tscGlobalRef);

  Registry.Register('list_action_types',
    'List action types. Optionally filter by kind ' +
    '(Synthesys, Testing, Measurement, Analysis, Simulation, Other).',
    MakeListActionTypesSchema, HandleListActionTypes, tscGlobalRef);

  Registry.Register('get_protocols',
    'Get protocols for an item including type, validation status, ' +
    'form data, equipment info, and status change history.',
    MakeItemIdSchema('Item ID to get protocols for'), HandleGetProtocols,
    tscProjectScoped);

  Registry.Register('get_audit_log',
    'Query audit trail with optional filters for entity type, entity ID, ' +
    'operation, user, and date range. Returns entries ordered by timestamp desc. ' +
    'Only rows with existing subjects in visible projects are returned; ' +
    'global or unresolved rows are omitted, so fewer than limit may be returned.',
    MakeGetAuditLogSchema, HandleGetAuditLog, tscProjectScoped);

  Registry.Register('get_comments',
    'Get comments for an item. Returns comment text, author, and dates.',
    MakeItemIdSchema('Item ID to get comments for'), HandleGetComments,
    tscProjectScoped);

  Registry.Register('get_signatures',
    'Get electronic signatures for an item. Returns signer, date, ' +
    'meaning, comment, and content hash.',
    MakeItemIdSchema('Item ID to get signatures for'), HandleGetSignatures,
    tscProjectScoped);

  Registry.Register('list_users',
    'List all users with roles. Returns username, name, email, and role. ' +
    'Password hashes are never exposed.',
    MakeEmptySchema, HandleListUsers, tscProjectScoped);

  Registry.Register('get_project_stats',
    'Get summary statistics for a project including item, file, value, ' +
    'protocol, and tag counts, plus recent audit activity.',
    MakeProjectIdSchema, HandleGetProjectStats, tscProjectScoped);

  Registry.Register('list_audit_rules',
    'List all audit rules with their required file types and value types. ' +
    'Shows rule matching criteria (action type + equipment) and requirements.',
    MakeEmptySchema, HandleListAuditRules, tscGlobalRef);
end;

end.
