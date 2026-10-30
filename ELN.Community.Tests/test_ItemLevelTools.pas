unit test_ItemLevelTools;

interface

procedure RunItemLevelTests;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  System.Variants,
  Aurelius.Engine.ObjectManager, Aurelius.Criteria.Linq, Aurelius.Drivers.Interfaces,
  unit_AuthorizationTestSupport,
  unit_MCPTools, unit_ToolsWrite, unit_FilePaths,
  unit_Project, unit_Item, unit_ItemTypes, unit_AuditLog, unit_FileType,
  unit_Hypothesis, unit_HypothesisRun, unit_Signature;

type
  TStoredItem = record
    Level: TItemLevel;
    Parent: Integer;
    Version: Integer;
    Title: string;
    Modified: Variant;
  end;

procedure Prepare;
begin
  Context.Storage := Notebook.Storage;
  FreeAndNil(Registry);
  Registry := TToolRegistry.Create(Context);
  RegisterWriteTools(Registry);
end;

procedure ExecSQL(const Command: string);
var
  Statement: IDBStatement;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(Command);
  Statement.Execute;
end;

function RowCount(const Query: string): Integer;
var
  Statement: IDBStatement;
  Rows: IDBResultSet;
begin
  Statement := Notebook.Connection.CreateStatement;
  Statement.SetSQLCommand(Query);
  Rows := Statement.ExecuteQuery;
  Check(Rows.Next, 'A count query returns one row');
  Result := StrToInt(VarToStr(Rows.GetFieldValue(0)));
end;

function NewItem(Project: TProject; ParentId: Integer; Level: TItemLevel;
  const Title: string): Integer;
var
  Item: TItem;
begin
  Item := TItem.Create;
  Item.Title := Title;
  Item.ProjectID := Project.Id;
  Item.Parent := ParentId;
  Item.Type_ := TItemType.Measurement;
  Item.Level := Level;
  Item.CreatedBy := Notebook.Principal.Id;
  Item.CreatedDate := Now;
  Notebook.Manager.Save(Item);
  Notebook.Manager.Flush;
  Result := Item.Id;
end;

function Stored(ItemId: Integer): TStoredItem;
var
  Observer: TObjectManager;
  Item: TItem;
begin
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Item := Observer.Find<TItem>(ItemId);
    Result.Level := Item.Level;
    Result.Parent := Item.Parent;
    Result.Version := Item.Version;
    Result.Title := Item.Title;
    if Item.ModifiedDate.HasValue then
      Result.Modified := Item.ModifiedDate.Value
    else
      Result.Modified := Null;
  finally
    Observer.Free;
  end;
end;

function ItemAudits(ItemId: Integer): TArray<string>;
var
  Observer: TObjectManager;
  Rows: TList<TAuditLog>;
  Row: TAuditLog;
begin
  Result := nil;
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Rows := Observer.Find<TAuditLog>.Where((Linq['EntityType'] = Ord(aetItem)) and
      (Linq['EntityId'] = ItemId)).OrderBy('Id').List;
    try
      for Row in Rows do
        Result := Result + [Row.Description];
    finally
      Rows.Free;
    end;
  finally
    Observer.Free;
  end;
end;

procedure ExpectRefused(const Tool, JSON, Fragment: string);
var
  Response: TJSONObject;
  Message: string;
begin
  Message := '';
  try
    Response := Call(Tool, JSON);
    Response.Free;
  except
    on E: Exception do
    begin
      if E.ClassType <> Exception then
        raise;
      Message := E.Message;
    end;
  end;
  Check(Message <> '', Tool + ' must be refused: ' + JSON);
  Check(Pos(Fragment, Message) > 0,
    Format('%s refusal must mention "%s": %s', [Tool, Fragment, Message]));
end;

function UpdateLevel(ItemId: Integer; const Extra: string): TJSONObject;
begin
  Result := Call('update_item', Format('{"item_id":%d,%s}', [ItemId, Extra]));
end;

procedure CheckUnchanged(ItemId: Integer; const Before: TStoredItem; AuditCount: Integer);
var
  After: TStoredItem;
begin
  After := Stored(ItemId);
  Check(After.Level = Before.Level, 'A refused call keeps the level');
  Check(After.Version = Before.Version, 'A refused call keeps the version');
  Check(Length(ItemAudits(ItemId)) = AuditCount, 'A refused call writes no audit row');
end;

procedure TestProcUnderParentBecomesAction;
var
  Project: TProject;
  ParentId, ItemId: Integer;
  Before, After: TStoredItem;
  Response: TJSONObject;
  Audits: TArray<string>;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ParentId := NewItem(Project, 0, TItemLevel.Proc, 'Run');
  ItemId := NewItem(Project, ParentId, TItemLevel.Proc, 'Indentation');
  Before := Stored(ItemId);
  Response := UpdateLevel(ItemId, '"level":"Action"');
  try
    Check(Response.GetValue<string>('level') = 'Action', 'The response reports the new level');
    Check(Response.GetValue<Boolean>('changed'), 'A level change reports changed');
  finally
    Response.Free;
  end;
  After := Stored(ItemId);
  Check(After.Level = TItemLevel.Action, 'The level is stored');
  Check(After.Version = Before.Version + 1, 'The version increments once');
  Check(After.Parent = ParentId, 'The parent stays');
  Audits := ItemAudits(ItemId);
  Check(Length(Audits) = 1, 'A level-only change writes exactly one audit row');
  Check(Audits[0] = 'MCP: Updated item level "Indentation": Proc -> Action',
    'The audit row names the old and new level: ' + Audits[0]);
end;

procedure TestSameLevelIsNoOp;
var
  Project: TProject;
  ItemId, HypId: Integer;
  Before, After: TStoredItem;
  Response: TJSONObject;
  H: THypothesis;
  Run: THypothesisRun;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ItemId := NewItem(Project, 0, TItemLevel.Action, 'Locked action');
  H := AddHypothesis(Project);
  H.Status := hsAccepted;
  Notebook.Manager.Flush;
  HypId := H.Id;
  Run := THypothesisRun.Create;
  Run.HypothesisId := HypId;
  Run.ItemId := ItemId;
  Run.Role := hrrRun;
  Run.AddedBy := Notebook.Principal.Id;
  Run.AddedDate := Now;
  Notebook.Manager.Save(Run);
  Notebook.Manager.Flush;
  Before := Stored(ItemId);
  Response := UpdateLevel(ItemId, '"level":"action"');
  try
    Check(not Response.GetValue<Boolean>('changed'), 'The same level is a no-op');
    Check(Response.GetValue<string>('level') = 'Action', 'The no-op reports the level');
  finally
    Response.Free;
  end;
  After := Stored(ItemId);
  Check(After.Version = Before.Version, 'A no-op keeps the version');
  Check(VarSameValue(After.Modified, Before.Modified), 'A no-op keeps ModifiedDate');
  Check(Length(ItemAudits(ItemId)) = 0, 'A no-op writes no audit row');
  ExpectRefused('update_item', Format('{"item_id":%d,"level":"Item"}', [ItemId]),
    'hypothesis');
  CheckUnchanged(ItemId, Before, 0);
end;

procedure TestLevelRefusals;
var
  Project: TProject;
  RootId, ChildId, FolderId, SignedId: Integer;
  Before: TStoredItem;
  Signature: TSignature;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  RootId := NewItem(Project, 0, TItemLevel.Action, 'Root action');
  ChildId := NewItem(Project, RootId, TItemLevel.Action, 'Child action');
  FolderId := NewItem(Project, 0, TItemLevel.Folder, 'Folder item');

  Before := Stored(RootId);
  ExpectRefused('update_item', Format('{"item_id":%d,"level":"Folder"}', [RootId]), 'Folder');
  CheckUnchanged(RootId, Before, 0);
  ExpectRefused('update_item', Format('{"item_id":%d,"level":"Bogus"}', [RootId]),
    'Invalid level: Bogus');
  CheckUnchanged(RootId, Before, 0);

  Before := Stored(FolderId);
  ExpectRefused('update_item', Format('{"item_id":%d,"level":"Proc"}', [FolderId]), 'Folder');
  CheckUnchanged(FolderId, Before, 0);

  Before := Stored(ChildId);
  ExpectRefused('update_item', Format('{"item_id":%d,"level":"Proc"}', [ChildId]),
    'A Proc cannot have a parent');
  CheckUnchanged(ChildId, Before, 0);

  SignedId := NewItem(Project, 0, TItemLevel.Action, 'Signed action');
  Signature := TSignature.Create;
  Signature.ItemId := SignedId;
  Signature.UserId := Notebook.Principal.Id;
  Signature.UserName := 'Synthetic Scientist';
  Signature.SignedDate := Now;
  Signature.Meaning := 'Reviewed';
  Signature.ContentHash := StringOfChar('0', 64);
  Notebook.Manager.Save(Signature);
  Notebook.Manager.Flush;
  Before := Stored(SignedId);
  ExpectRefused('update_item', Format('{"item_id":%d,"level":"Item"}', [SignedId]), 'signed');
  CheckUnchanged(SignedId, Before, 0);
end;

procedure TestRootAndCaseAndChildren;
var
  Project: TProject;
  ProcId, ChildId, RootId: Integer;
  Response: TJSONObject;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ProcId := NewItem(Project, 0, TItemLevel.Proc, 'Root proc');
  ChildId := NewItem(Project, ProcId, TItemLevel.Item, 'Child item');
  Response := UpdateLevel(ProcId, '"level":"Action"');
  Response.Free;
  Check(Stored(ProcId).Level = TItemLevel.Action, 'A root Proc becomes an Action');
  Check(Stored(ChildId).Level = TItemLevel.Item, 'Children keep their level');
  Check(Stored(ChildId).Parent = ProcId, 'Children keep their parent');

  RootId := NewItem(Project, 0, TItemLevel.Action, 'Root action');
  Response := UpdateLevel(RootId, '"level":"proc"');
  try
    Check(Response.GetValue<string>('level') = 'Proc', 'Lower case level is accepted');
  finally
    Response.Free;
  end;
end;

procedure TestTitleAndLevelWriteTwoRows;
var
  Project: TProject;
  ItemId: Integer;
  Audits: TArray<string>;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ItemId := NewItem(Project, 0, TItemLevel.Proc, 'Old title');
  UpdateLevel(ItemId, '"title":"New title","level":"Action"').Free;
  Check(Stored(ItemId).Title = 'New title', 'The title changes');
  Check(Stored(ItemId).Level = TItemLevel.Action, 'The level changes');
  Audits := ItemAudits(ItemId);
  Check(Length(Audits) = 2, 'Title and level write two audit rows');
  Check(Audits[0] = 'Updated item "New title"', 'The field row stays: ' + Audits[0]);
  Check(Audits[1] = 'MCP: Updated item level "New title": Proc -> Action',
    'The level row follows: ' + Audits[1]);
end;

procedure TestAuditFailureRollsBackLevel;
var
  Project: TProject;
  ItemId: Integer;
  Before: TStoredItem;
  Raised: Boolean;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ItemId := NewItem(Project, 0, TItemLevel.Proc, 'Audit target');
  Before := Stored(ItemId);
  ExecSQL('CREATE TRIGGER RejectAudit BEFORE INSERT ON AuditLog BEGIN ' +
    'SELECT RAISE(ABORT, ''synthetic audit failure''); END');
  Raised := False;
  try
    try
      UpdateLevel(ItemId, '"level":"Action"').Free;
    except
      Raised := True;
    end;
  finally
    ExecSQL('DROP TRIGGER RejectAudit');
  end;
  Check(Raised, 'A failed audit insert fails the call');
  CheckUnchanged(ItemId, Before, 0);
end;

procedure TestFilesStayInPlace;
var
  Project: TProject;
  ItemId, FileTypeId: Integer;
  FileType: TFileType;
  Dir, Path, Relative: string;
  FileId: Int64;
  Observer: TObjectManager;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ItemId := NewItem(Project, 0, TItemLevel.Proc, 'With file');
  FileType := TFileType.Create;
  FileType.Ext := '.bin';
  FileType.CreatedDate := Now;
  Notebook.Manager.Save(FileType);
  Notebook.Manager.Flush;
  FileTypeId := FileType.Id;
  Dir := TPath.Combine(TPath.GetTempPath, 'ELN-ItemLevel-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    Path := TPath.Combine(Dir, 'input.bin');
    System.IOUtils.TFile.WriteAllText(Path, 'abc');
    FileId := AttachFileToItem(Context, ItemId, Path, FileTypeId, 'data').Id;
  finally
    TDirectory.Delete(Dir, True);
  end;
  Observer := TObjectManager.Create(Notebook.Connection);
  try
    Relative := AttachmentRelativePath(Project.FileFolder,
      Observer.Find<TItem>(ItemId).FolderName,
      Observer.Find<unit_Item.TFile>(FileId).FullName);
  finally
    Observer.Free;
  end;
  Check(Notebook.Storage.Exists(Relative), 'The fixture file is stored');
  UpdateLevel(ItemId, '"level":"Action"').Free;
  Check(Notebook.Storage.Exists(Relative), 'A level change moves no bytes');
end;

procedure TestCreateItemProcParent;
var
  Project: TProject;
  ParentId, Before: Integer;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  ParentId := NewItem(Project, 0, TItemLevel.Proc, 'Parent');
  Before := RowCount('SELECT COUNT(*) FROM Items');
  ExpectRefused('create_item', Format('{"project_id":%d,"folder_id":0,"title":"P",' +
    '"item_type":"Testing","level":"Proc","parent_id":%d}', [Project.Id, ParentId]),
    'A Proc cannot have a parent');
  ExpectRefused('create_item', Format('{"project_id":%d,"folder_id":0,"title":"N",' +
    '"item_type":"Testing","level":"Action","parent_id":-1}', [Project.Id]),
    'parent_id must be 0');
  Check(RowCount('SELECT COUNT(*) FROM Items') = Before, 'Refusals create no row');
  Call('create_item', Format('{"project_id":%d,"folder_id":0,"title":"Root",' +
    '"item_type":"Testing","level":"Proc"}', [Project.Id])).Free;
  Call('create_item', Format('{"project_id":%d,"folder_id":0,"title":"Child",' +
    '"item_type":"Testing","level":"Action","parent_id":%d}', [Project.Id, ParentId])).Free;
  Check(RowCount('SELECT COUNT(*) FROM Items') = Before + 2,
    'A root Proc and a child Action are created');
end;

procedure TestReparentProc;
var
  Project: TProject;
  TargetId, ProcId, ActionId: Integer;
begin
  Prepare;
  Project := AddProject(Notebook.Principal);
  TargetId := NewItem(Project, 0, TItemLevel.Proc, 'Target');
  ProcId := NewItem(Project, 0, TItemLevel.Proc, 'Root proc');
  ExpectRefused('reparent_item', Format('{"item_id":%d,"new_parent_id":%d}',
    [ProcId, TargetId]), 'a Proc cannot have a parent');
  Check(Stored(ProcId).Parent = 0, 'A refused reparent keeps the parent');
  Call('reparent_item', Format('{"item_id":%d,"new_parent_id":0}', [ProcId])).Free;
  ActionId := NewItem(Project, 0, TItemLevel.Action, 'Root action');
  Call('reparent_item', Format('{"item_id":%d,"new_parent_id":%d}',
    [ActionId, TargetId])).Free;
  Check(Stored(ActionId).Parent = TargetId, 'An Action can take a parent');
end;

procedure RunItemLevelTests;
begin
  RunTest('update_item changes a Proc with a parent to Action with one audit row',
    TestProcUnderParentBecomesAction);
  RunTest('update_item same level is a no-op even on a locked item; a change is refused',
    TestSameLevelIsNoOp);
  RunTest('update_item refuses Folder, Folder items, Proc with parent, bad and signed',
    TestLevelRefusals);
  RunTest('update_item accepts root and lower-case levels and keeps children',
    TestRootAndCaseAndChildren);
  RunTest('update_item title and level write two audit rows', TestTitleAndLevelWriteTwoRows);
  RunTest('update_item audit failure rolls back the level', TestAuditFailureRollsBackLevel);
  RunTest('update_item level change moves no bytes', TestFilesStayInPlace);
  RunTest('create_item refuses a Proc with a parent and a negative parent',
    TestCreateItemProcParent);
  RunTest('reparent_item refuses a Proc under a parent', TestReparentProc);
end;

end.
