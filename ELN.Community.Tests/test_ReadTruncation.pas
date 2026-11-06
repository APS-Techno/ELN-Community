unit test_ReadTruncation;

interface

uses
  System.SysUtils, System.JSON, System.DateUtils,
  DUnitX.TestFramework,
  unit_LocalNotebook, unit_MCPTools, unit_Project, unit_Item, unit_ItemTypes,
  unit_ValueType, unit_AuditLog;

type
  [TestFixture]
  TReadTruncationTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FProject: TProject;
    FScope: TArray<Integer>;
    FPlainType: TValueType;
    FRangedType: TValueType;
    function Run(const Tool, ParamsJson: string): TJSONObject;
    function NewValueType(const Symbol: string; Ranged: Boolean): TValueType;
    function NewItem(const Title: string): TItem;
    procedure AddValues(Item: TItem; ValueType: TValueType; RecType: TRecType;
      Count: Integer; Value: Double);
    procedure AddAudit(ItemId: Integer; SecondsAhead: Integer);
    function StatementCount(const Tool, ParamsJson: string): Integer;
    procedure CheckPage(Response: TJSONObject; const ArrayName: string;
      ExpectedRows: Integer; ExpectedTruncated: Boolean);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure QueryValuesFlagsTruncation;
    [Test]
    procedure QueryValuesExactLimitIsNotTruncated;
    [Test]
    procedure QueryValuesFlagsTruncationAcrossItems;
    [Test]
    procedure QueryValuesLaterItemsWithoutMatchAreNotTruncated;
    [Test]
    procedure QueryValuesLaterItemWithMatchingTypeIsTruncated;
    [Test]
    procedure QueryValuesProbeCostDoesNotGrowWithRemainingItems;
    [Test]
    procedure CorrelateValuesFlagsTruncation;
    [Test]
    procedure CorrelateValuesExactLimitIsNotTruncated;
    [Test]
    procedure CorrelateValuesIgnoresUnpairedRemainder;
    [Test]
    procedure CorrelateValuesLaterItemsWithoutPairAreNotTruncated;
    [Test]
    procedure CorrelateValuesLaterPairOfOtherTypeIsNotTruncated;
    [Test]
    procedure CorrelateValuesProbeCostDoesNotGrowWithRemainingItems;
    [Test]
    procedure ReportValueIssuesFlagsTruncation;
    [Test]
    procedure ReportValueIssuesExactLimitIsNotTruncated;
    [Test]
    procedure AuditLogFlagsTruncation;
    [Test]
    procedure AuditLogExactLimitIsNotTruncated;
    [Test]
    procedure AuditLogOutOfScopeEntityMatchesMissingId;
    [Test]
    procedure AuditLogFlagsVisibleOverflowAfterHiddenRows;
  end;

implementation

uses
  System.IOUtils,
  Aurelius.Engine.ObjectManager,
  unit_ProjectModel, unit_ToolsValues, unit_ToolsValueChecks,
  unit_ToolsMetadata, test_MCPCountTools;

function TReadTruncationTests.Run(const Tool, ParamsJson: string): TJSONObject;
var
  Manager: TObjectManager;
  Context: TToolContext;
  Registry: TToolRegistry;
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(ParamsJson) as TJSONObject;
  try
    Manager := TObjectManager.Create(FNotebook.Connection);
    try
      Context := Default(TToolContext);
      Context.Manager := Manager;
      Context.ScopedProjects := FScope;
      Context.User := FNotebook.Principal;
      Context.AccessPolicy := FNotebook.AccessPolicy;
      Context.Storage := FNotebook.Storage;
      Registry := TToolRegistry.Create(Context);
      try
        RegisterValueTools(Registry);
        RegisterValueCheckTools(Registry);
        RegisterMetadataTools(Registry);
        Result := Registry.Execute(Tool, Params);
      finally
        Registry.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Params.Free;
  end;
end;

function TReadTruncationTests.NewValueType(const Symbol: string;
  Ranged: Boolean): TValueType;
begin
  Result := TValueType.Create;
  Result.Symbol := Symbol;
  Result.Title := 'Type ' + Symbol;
  Result.Units := 'nm';
  Result.CreatedDate := Now;
  Result.CreatedBy := FNotebook.Principal.Id;
  if Ranged then
  begin
    Result.RangeMin := 0;
    Result.RangeMax := 10;
  end;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
end;

function TReadTruncationTests.NewItem(const Title: string): TItem;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.ProjectID := FProject.Id;
  Result.Type_ := TItemType.Other;
  Result.Level := TItemLevel.Proc;
  Result.CreatedBy := FNotebook.Principal.Id;
  Result.CreatedDate := Now;
  FNotebook.Manager.Save(Result);
  FNotebook.Manager.Flush;
end;

procedure TReadTruncationTests.AddValues(Item: TItem; ValueType: TValueType;
  RecType: TRecType; Count: Integer; Value: Double);
var
  I: Integer;
  Row: TValue;
begin
  for I := 1 to Count do
  begin
    Row := TValue.Create;
    Row.Item := Item;
    Row.ValueType := ValueType;
    Row.RecType := RecType;
    Row.Value := Value;
    Row.CreatedBy := FNotebook.Principal.Id;
    Row.CreatedDate := Now;
    Item.Values.Add(Row);
  end;
  FNotebook.Manager.Flush;
end;

procedure TReadTruncationTests.AddAudit(ItemId: Integer; SecondsAhead: Integer);
var
  Row: TAuditLog;
begin
  Row := TAuditLog.Create;
  Row.EntityType := aetItem;
  Row.EntityId := ItemId;
  Row.Operation := aoUpdate;
  Row.UserId := FNotebook.Principal.Id;
  Row.Timestamp := Now + SecondsAhead / SecsPerDay;
  Row.Description := 'Synthetic change';
  FNotebook.Manager.Save(Row);
  FNotebook.Manager.Flush;
end;

function TReadTruncationTests.StatementCount(const Tool,
  ParamsJson: string): Integer;
var
  Counter: TSqlCounter;
  Response: TJSONObject;
begin
  Counter := TSqlCounter.Create;
  try
    Response := Run(Tool, ParamsJson);
    Response.Free;
    Result := Counter.Count;
  finally
    Counter.Free;
  end;
end;

procedure TReadTruncationTests.CheckPage(Response: TJSONObject;
  const ArrayName: string; ExpectedRows: Integer; ExpectedTruncated: Boolean);
var
  Flag: TJSONValue;
begin
  Flag := Response.GetValue('truncated');
  Assert.IsTrue(Flag is TJSONBool, 'truncated is present and boolean');
  Assert.AreEqual(ExpectedTruncated, TJSONBool(Flag).AsBoolean, 'truncated');
  Assert.AreEqual(ExpectedRows, Response.GetValue<TJSONArray>(ArrayName).Count,
    'returned rows');
end;

procedure TReadTruncationTests.Setup;
var
  Projects: TProjectsModel;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-ReadTruncation-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Truncation fixture',
    'fixture-password');
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Projects.AssignUser(FNotebook.Principal);
    FProject := Projects.AddProject('Truncation', 'Synthetic',
      FNotebook.Principal);
  finally
    Projects.Free;
  end;
  FPlainType := NewValueType('PL', False);
  FRangedType := NewValueType('RG', True);
end;

procedure TReadTruncationTests.TearDown;
begin
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TReadTruncationTests.QueryValuesFlagsTruncation;
var
  Response: TJSONObject;
begin
  AddValues(NewItem('One'), FPlainType, EXP_CONDITION, 4, 1);
  Response := Run('query_values', Format('{"project_id":%d,"limit":3}',
    [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, True);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.QueryValuesExactLimitIsNotTruncated;
var
  Response: TJSONObject;
begin
  AddValues(NewItem('One'), FPlainType, EXP_CONDITION, 3, 1);
  Response := Run('query_values', Format('{"project_id":%d,"limit":3}',
    [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.QueryValuesFlagsTruncationAcrossItems;
var
  Response: TJSONObject;
begin
  AddValues(NewItem('One'), FPlainType, EXP_CONDITION, 3, 1);
  AddValues(NewItem('Two'), FPlainType, TEST_RESULT, 1, 1);
  Response := Run('query_values', Format('{"project_id":%d,"limit":3}',
    [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, True);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.QueryValuesLaterItemsWithoutMatchAreNotTruncated;
var
  Response: TJSONObject;
  I: Integer;
begin
  AddValues(NewItem('Matching'), FPlainType, EXP_CONDITION, 3, 1);
  for I := 1 to 3 do
    AddValues(NewItem('Other ' + IntToStr(I)), FRangedType, TEST_RESULT, 2, 1);
  Response := Run('query_values', Format(
    '{"project_id":%d,"limit":3,"rec_type":"EXP_CONDITION"}', [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, False);
  finally
    Response.Free;
  end;
  Response := Run('query_values', Format(
    '{"project_id":%d,"limit":3,"value_type":"PL"}', [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, False);
  finally
    Response.Free;
  end;
  Response := Run('query_values', Format(
    '{"project_id":%d,"limit":3,"value_type":"type pl"}', [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.QueryValuesLaterItemWithMatchingTypeIsTruncated;
var
  Response: TJSONObject;
begin
  AddValues(NewItem('Matching'), FPlainType, EXP_CONDITION, 3, 1);
  AddValues(NewItem('Other'), FRangedType, EXP_CONDITION, 2, 1);
  AddValues(NewItem('Later match'), FPlainType, TEST_RESULT, 1, 1);
  Response := Run('query_values', Format(
    '{"project_id":%d,"limit":3,"value_type":"PL"}', [FProject.Id]));
  try
    CheckPage(Response, 'values', 3, True);
  finally
    Response.Free;
  end;
  Response := Run('query_values', Format(
    '{"project_id":%d,"limit":3,"value_type":"pl","rec_type":"TEST_RESULT"}',
    [FProject.Id]));
  try
    CheckPage(Response, 'values', 1, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.QueryValuesProbeCostDoesNotGrowWithRemainingItems;
var
  Params: string;
  Short, Long, I: Integer;
begin
  AddValues(NewItem('First'), FPlainType, EXP_CONDITION, 2, 1);
  AddValues(NewItem('Second'), FPlainType, EXP_CONDITION, 1, 1);
  Params := Format('{"project_id":%d,"limit":2}', [FProject.Id]);
  Short := StatementCount('query_values', Params);
  for I := 1 to 5 do
    AddValues(NewItem('Later ' + IntToStr(I)), FPlainType, EXP_CONDITION, 1, 1);
  Long := StatementCount('query_values', Params);
  Assert.AreEqual(Short, Long, 'statements with more remaining items');
end;

procedure TReadTruncationTests.CorrelateValuesFlagsTruncation;
var
  Response: TJSONObject;
  I: Integer;
  Item: TItem;
begin
  for I := 1 to 3 do
  begin
    Item := NewItem('Paired ' + IntToStr(I));
    AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
    AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  end;
  Response := Run('correlate_values', Format('{"project_id":%d,"limit":2}',
    [FProject.Id]));
  try
    CheckPage(Response, 'items', 2, True);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.CorrelateValuesExactLimitIsNotTruncated;
var
  Response: TJSONObject;
  I: Integer;
  Item: TItem;
begin
  for I := 1 to 2 do
  begin
    Item := NewItem('Paired ' + IntToStr(I));
    AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
    AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  end;
  Response := Run('correlate_values', Format('{"project_id":%d,"limit":2}',
    [FProject.Id]));
  try
    CheckPage(Response, 'items', 2, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.CorrelateValuesIgnoresUnpairedRemainder;
var
  Response: TJSONObject;
  I: Integer;
  Item: TItem;
begin
  for I := 1 to 2 do
  begin
    Item := NewItem('Paired ' + IntToStr(I));
    AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
    AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  end;
  AddValues(NewItem('Condition only'), FPlainType, EXP_CONDITION, 1, 1);
  Response := Run('correlate_values', Format('{"project_id":%d,"limit":2}',
    [FProject.Id]));
  try
    CheckPage(Response, 'items', 2, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.CorrelateValuesLaterItemsWithoutPairAreNotTruncated;
var
  Response: TJSONObject;
  Item: TItem;
begin
  Item := NewItem('Paired');
  AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
  AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  AddValues(NewItem('Conditions only'), FPlainType, EXP_CONDITION, 2, 1);
  AddValues(NewItem('Results only'), FPlainType, TEST_RESULT, 2, 1);
  Response := Run('correlate_values', Format('{"project_id":%d,"limit":1}',
    [FProject.Id]));
  try
    CheckPage(Response, 'items', 1, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.CorrelateValuesLaterPairOfOtherTypeIsNotTruncated;
var
  Response: TJSONObject;
  Item: TItem;
begin
  Item := NewItem('Paired');
  AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
  AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  Item := NewItem('Paired of other type');
  AddValues(Item, FRangedType, EXP_CONDITION, 1, 1);
  AddValues(Item, FRangedType, TEST_RESULT, 1, 2);
  Response := Run('correlate_values', Format(
    '{"project_id":%d,"limit":1,"condition_type_id":%d}',
    [FProject.Id, FPlainType.Id]));
  try
    CheckPage(Response, 'items', 1, False);
  finally
    Response.Free;
  end;
  Response := Run('correlate_values', Format(
    '{"project_id":%d,"limit":1,"condition_type_id":%d,"result_type_id":%d}',
    [FProject.Id, FPlainType.Id, FPlainType.Id]));
  try
    CheckPage(Response, 'items', 1, False);
  finally
    Response.Free;
  end;
  Response := Run('correlate_values', Format('{"project_id":%d,"limit":1}',
    [FProject.Id]));
  try
    CheckPage(Response, 'items', 1, True);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.CorrelateValuesProbeCostDoesNotGrowWithRemainingItems;
var
  Params: string;
  Short, Long, I: Integer;
  Item: TItem;
begin
  for I := 1 to 2 do
  begin
    Item := NewItem('Paired ' + IntToStr(I));
    AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
    AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  end;
  Params := Format('{"project_id":%d,"limit":1}', [FProject.Id]);
  Short := StatementCount('correlate_values', Params);
  for I := 3 to 8 do
  begin
    Item := NewItem('Paired ' + IntToStr(I));
    AddValues(Item, FPlainType, EXP_CONDITION, 1, 1);
    AddValues(Item, FPlainType, TEST_RESULT, 1, 2);
  end;
  Long := StatementCount('correlate_values', Params);
  Assert.AreEqual(Short, Long, 'statements with more remaining items');
end;

procedure TReadTruncationTests.ReportValueIssuesFlagsTruncation;
var
  Response: TJSONObject;
begin
  AddValues(NewItem('One'), FRangedType, EXP_CONDITION, 3, 100);
  Response := Run('report_value_issues', Format('{"project_id":%d,"limit":2}',
    [FProject.Id]));
  try
    CheckPage(Response, 'values', 2, True);
    Assert.AreEqual(3, Response.GetValue<Integer>('total'), 'total');
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.ReportValueIssuesExactLimitIsNotTruncated;
var
  Response: TJSONObject;
begin
  AddValues(NewItem('One'), FRangedType, EXP_CONDITION, 2, 100);
  Response := Run('report_value_issues', Format('{"project_id":%d,"limit":2}',
    [FProject.Id]));
  try
    CheckPage(Response, 'values', 2, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.AuditLogFlagsTruncation;
var
  Response: TJSONObject;
  ItemId, I: Integer;
begin
  ItemId := NewItem('Audited').Id;
  for I := 1 to 3 do
    AddAudit(ItemId, I);
  Response := Run('get_audit_log', Format(
    '{"entity_type":"Item","entity_id":%d,"limit":2}', [ItemId]));
  try
    CheckPage(Response, 'audit_log', 2, True);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.AuditLogExactLimitIsNotTruncated;
var
  Response: TJSONObject;
  ItemId, I: Integer;
begin
  ItemId := NewItem('Audited').Id;
  for I := 1 to 2 do
    AddAudit(ItemId, I);
  Response := Run('get_audit_log', Format(
    '{"entity_type":"Item","entity_id":%d,"limit":2}', [ItemId]));
  try
    CheckPage(Response, 'audit_log', 2, False);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.AuditLogFlagsVisibleOverflowAfterHiddenRows;
var
  Response: TJSONObject;
  ItemId: Integer;
begin
  ItemId := NewItem('Audited').Id;
  AddAudit(ItemId, 1);
  AddAudit(ItemId + 1000, 2);
  AddAudit(ItemId + 1000, 3);
  Response := Run('get_audit_log', '{"entity_type":"Item","limit":2}');
  try
    CheckPage(Response, 'audit_log', 0, True);
  finally
    Response.Free;
  end;
end;

procedure TReadTruncationTests.AuditLogOutOfScopeEntityMatchesMissingId;
var
  Projects: TProjectsModel;
  Other: TProject;
  OtherItem: TItem;
  Hidden, Missing: TJSONObject;
begin
  Projects := TProjectsModel.Create(FNotebook.Manager, FNotebook.AccessPolicy);
  try
    Other := Projects.AddProject('Other', 'Synthetic', FNotebook.Principal);
  finally
    Projects.Free;
  end;
  OtherItem := TItem.Create;
  OtherItem.Title := 'Out of scope';
  OtherItem.ProjectID := Other.Id;
  OtherItem.Type_ := TItemType.Other;
  OtherItem.Level := TItemLevel.Proc;
  OtherItem.CreatedBy := FNotebook.Principal.Id;
  OtherItem.CreatedDate := Now;
  FNotebook.Manager.Save(OtherItem);
  FNotebook.Manager.Flush;
  AddAudit(OtherItem.Id, 1);
  AddAudit(OtherItem.Id, 2);
  FScope := [FProject.Id];
  Hidden := Run('get_audit_log', Format(
    '{"entity_type":"Item","entity_id":%d,"limit":1}', [OtherItem.Id]));
  try
    Missing := Run('get_audit_log', Format(
      '{"entity_type":"Item","entity_id":%d,"limit":1}', [OtherItem.Id + 5000]));
    try
      CheckPage(Hidden, 'audit_log', 0, False);
      Assert.AreEqual(Missing.ToJSON, Hidden.ToJSON,
        'Out-of-scope entity and missing id give the same reply');
    finally
      Missing.Free;
    end;
  finally
    Hidden.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReadTruncationTests);

end.
