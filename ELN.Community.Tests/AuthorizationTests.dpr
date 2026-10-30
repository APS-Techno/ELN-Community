program AuthorizationTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq,
  unit_AuthorizationTestSupport,
  test_ValueSourceTools,
  test_ItemLevelTools,
  unit_ToolsWrite, unit_User, unit_Item, unit_ItemTypes, unit_Tag, unit_AuditLog, unit_ValueType;


procedure TestLocalForeignTagWrite;
begin
  Context.User := AddUser('foreign-admin', dbAdmin);
  SetRegistry;
  ExpectTagRefusal;
end;
procedure TestMissingTagPolicy;
begin
  Context.AccessPolicy := nil;
  SetRegistry;
  ExpectTagRefusal;
end;


procedure TestCommittedLocalArchive;
var
  Observer: TObjectManager;
begin
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Observer.Find<TUser>(Notebook.Principal.Id).IsArchived := True;
    Observer.Flush;
    Check(not Context.User.IsArchived, 'Host principal is a stale active snapshot');
    ExpectTagRefusal;
  finally
    Observer.Free;
  end;
end;



procedure TestLocalScientistTagWrite;
var
  Response: TJSONObject;
  Stored: TTag;
begin
  Response := Call('create_tag', '{"name":"local-tag","color_rgb":"#123456"}');
  try
    Stored := Notebook.Manager.Find<TTag>(Response.GetValue<Integer>('id'));
    Check(Assigned(Stored) and (Stored.Color = '#563412'), 'Local scientist persists correct tag');
    Check(Notebook.Principal.Role = dbUser, 'Local scientist must not become Admin');
  finally
    Response.Free;
  end;
end;


procedure TestDeviceScope;
var
  Own, Other: TItem;
  Response: TJSONObject;
begin
  Own := AddItem(AddProject(Notebook.Principal));
  Other := AddItem(AddProject(Notebook.Principal));
  AddLink(Own.Id, Other.Id);
  AddAudit(aetProject, Other.ProjectID);
  Response := Call('get_item_links', Format('{"item_id":%d}', [Own.Id]));
  try
    Check(Response.GetValue<TJSONArray>('links').Count = 1,
      'Policy-visible cross-project link retained without scope');
  finally
    Response.Free;
  end;
  Context.ScopedProjects := [Own.ProjectID];
  SetRegistry;
  Response := Call('get_item_links', Format('{"item_id":%d}', [Own.Id]));
  try
    Check(Response.GetValue<TJSONArray>('links').Count = 0,
      'Device scope additionally confines policy-visible links');
  finally
    Response.Free;
  end;
  Response := Call('get_audit_log', '{"operation":"Update"}');
  try
    Check(Response.GetValue<TJSONArray>('audit_log').Count = 0,
      'Device scope additionally confines policy-visible audit');
  finally
    Response.Free;
  end;
end;


procedure TestLocalValueWritePersistsOwner;
const
  ExpectedValue: Double = 1.25e-8;
  ExpectedTolerance: Double = 1e-10;
var
  Item: TItem;
  ValueType: TValueType;
  Response: TJSONObject;
  ValueId: Integer;
  Observer: TObjectManager;
  Stored: unit_Item.TValue;
  Audit: TList<TAuditLog>;
begin
  Item := AddItem(AddProject(Notebook.Principal));
  ValueType := TValueType.Create;
  ValueType.Symbol := 'd';
  ValueType.Title := 'Synthetic thickness';
  ValueType.Units := 'm';
  ValueType.CreatedDate := Now;
  ValueType.CreatedBy := Notebook.Principal.Id;
  Notebook.Manager.Save(ValueType);
  Notebook.Manager.Flush;
  RegisterWriteTools(Registry);
  Response := Call('add_value', Format(
    '{"item_id":%d,"value_type_id":%d,"value":1.25e-8,' +
    '"tolerance":1e-10,"rec_type":"EXP_CONDITION","description":"Synthetic input"}',
    [Item.Id, ValueType.Id]));
  try
    ValueId := Response.GetValue<Integer>('id');
  finally
    Response.Free;
  end;
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Stored := Observer.Find<unit_Item.TValue>(ValueId);
    Check(Assigned(Stored) and Assigned(Stored.Item), 'Value must persist its owner');
    Check(Stored.Item.Id = Item.Id, 'Value must belong to the authorized item');
    Check(Stored.ValueType.Id = ValueType.Id, 'Value must retain its dictionary type');
    Check(Stored.Value = ExpectedValue, 'Scientific input must round-trip through the database');
    Check(Stored.Tol = ExpectedTolerance, 'Tolerance must round-trip through the database');
    Check(Stored.RecType = EXP_CONDITION, 'Experimental condition category must persist');
    Check(Stored.Description = 'Synthetic input', 'Value description must persist');
    Check(Stored.CreatedBy.HasValue and
      (Stored.CreatedBy.Value = Notebook.Principal.Id), 'Value actor must remain local scientist');
    Audit := Observer.Find<TAuditLog>.Where(
      (Linq['EntityType'] = Ord(aetValue)) and (Linq['EntityId'] = ValueId)).List;
    try
      Check((Audit.Count = 1) and (Audit[0].UserId = Notebook.Principal.Id) and
        (Audit[0].Operation = aoCreate), 'Value creation must have an attributed audit row');
    finally
      Audit.Free;
    end;
  finally
    Observer.Free;
  end;
  Check(Notebook.Principal.Role = dbUser, 'Successful value write must not promote identity');
end;


begin
  RunTest('local foreign Admin tag write refused', TestLocalForeignTagWrite);
  RunTest('missing tag policy fails closed', TestMissingTagPolicy);
  RunTest('local tag policy reads committed archive', TestCommittedLocalArchive);
  RunTest('local scientist retains tag creation', TestLocalScientistTagWrite);
  RunTest('linked-item policy without device scope', TestLinkedVisibility);
  RunTest('audit project lookup without device scope', TestAuditVisibility);
  RunTest('device scope confines policy-visible metadata', TestDeviceScope);
  RunTest('local value write persists owning item and actor', TestLocalValueWritePersistsOwner);
  RunValueSourceTests;
  RunItemLevelTests;
  WriteLn('Passed: ', Passed, '; Failed: ', Failed);
  if Failed <> 0 then ExitCode := 1;
end.
