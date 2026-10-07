unit unit_AuthorizationTestSupport;

interface

uses
  System.SysUtils, System.JSON,
  unit_LocalNotebook, unit_MCPTools,
  unit_User, unit_Project, unit_Item, unit_Hypothesis, unit_AuditLog;

var
  Notebook: TLocalNotebook;
  Context: TToolContext;
  Registry: TToolRegistry;
  Passed, Failed: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
function Call(const Name, JSON: string): TJSONObject;
function AddUser(const Name: string; Role: TDBRole): TUser;
function AddProject(Owner: TUser): TProject;
function AddItem(Project: TProject): TItem;
procedure AddLink(Source, Target: Integer);
procedure AddAudit(EntityType: TAuditEntityType; EntityId: Integer);
function AddHypothesis(Project: TProject): THypothesis;
procedure SetRegistry;
procedure ExpectTagRefusal;
procedure TestLinkedVisibility;
procedure TestAuditVisibility;
procedure RunTest(const Name: string; Test: TProc);

implementation

uses
  System.IOUtils, System.Generics.Collections,
  Aurelius.Criteria.Linq,
  unit_ProjectModel, unit_ToolsTags, unit_ToolsMetadata,
  unit_ItemTypes, unit_ItemLink, unit_Tag;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function Call(const Name, JSON: string): TJSONObject;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
  try
    Result := Registry.Execute(Name, Params);
  finally
    Params.Free;
  end;
end;

function AddUser(const Name: string; Role: TDBRole): TUser;
begin
  Result := TUser.Create;
  Result.Username := Name;
  Result.Password := Notebook.Principal.Password;
  Result.FirstName := 'Synthetic';
  Result.LastName := Name;
  Result.Role := Role;
  Result.CreatedDate := Now;
  Notebook.Manager.Save(Result);
  Notebook.Manager.Flush;
end;

function AddProject(Owner: TUser): TProject;
var
  Projects: TProjectsModel;
begin
  Projects := TProjectsModel.Create(Notebook.Manager, Notebook.AccessPolicy);
  try
    Projects.AssignUser(Notebook.Principal);
    Result := Projects.AddProject('Synthetic project ' + Owner.Username, '', Owner);
  finally
    Projects.Free;
  end;
end;

function AddItem(Project: TProject): TItem;
begin
  Result := TItem.Create;
  Result.Title := 'Synthetic item ' + Project.Title;
  Result.ProjectID := Project.Id;
  Result.Type_ := TItemType.Specimen;
  Result.Level := TItemLevel.Item;
  Result.CreatedBy := Notebook.Principal.Id;
  Result.CreatedDate := Now;
  Notebook.Manager.Save(Result);
  Notebook.Manager.Flush;
end;

procedure AddLink(Source, Target: Integer);
var
  Link: TItemLink;
begin
  Link := TItemLink.Create;
  Link.SourceItemId := Source;
  Link.TargetItemId := Target;
  Link.Label_ := 'Synthetic relationship';
  Link.Notes := 'Synthetic private notes';
  Link.CreatedBy := Notebook.Principal.Id;
  Link.CreatedDate := Now;
  Notebook.Manager.Save(Link);
  Notebook.Manager.Flush;
end;

procedure AddAudit(EntityType: TAuditEntityType; EntityId: Integer);
var
  Log: TAuditLog;
begin
  Log := TAuditLog.Create;
  Log.EntityType := EntityType;
  Log.EntityId := EntityId;
  Log.Operation := aoUpdate;
  Log.UserId := Notebook.Principal.Id;
  Log.Timestamp := Now;
  Log.Description := 'Synthetic audit';
  Notebook.Manager.Save(Log);
  Notebook.Manager.Flush;
end;

function AddHypothesis(Project: TProject): THypothesis;
begin
  Result := THypothesis.Create;
  Result.ProjectId := Project.Id;
  Result.Title := 'Synthetic expectation';
  Result.Statement := 'Synthetic statement';
  Result.CreatedBy := Notebook.Principal.Id;
  Result.CreatedDate := Now;
  Notebook.Manager.Save(Result);
  Notebook.Manager.Flush;
end;

procedure SetRegistry;
begin
  FreeAndNil(Registry);
  Registry := TToolRegistry.Create(Context);
  RegisterTagTools(Registry);
  RegisterMetadataTools(Registry);
end;

procedure ExpectTagRefusal;
var
  Response: TJSONObject;
  Refused: Boolean;
  Tags: TList<TTag>;
begin
  Refused := False;
  try
    Response := Call('create_tag', '{"name":"denied-tag","color_rgb":"#123456"}');
    Response.Free;
  except
    on E: Exception do
    begin
      if E.ClassType <> Exception then
        raise;
      Refused := True;
    end;
  end;
  Check(Refused, 'Unauthorized create_tag must be refused');
  Tags := Notebook.Manager.Find<TTag>.Where(Linq['Name'] = 'denied-tag').List;
  try
    Check(Tags.Count = 0, 'Refusal must not persist a tag');
  finally
    Tags.Free;
  end;
end;

procedure TestLinkedVisibility;
var
  Own, Peer, Hidden: TItem;
  Response: TJSONObject;
  Arr: TJSONArray;
  Scoped: Boolean;
begin
  Own := AddItem(AddProject(Notebook.Principal));
  Peer := AddItem(Notebook.Manager.Find<TProject>(Own.ProjectID));
  Hidden := AddItem(AddProject(AddUser('hidden-owner', dbUser)));
  AddLink(Own.Id, Peer.Id);
  AddLink(Peer.Id, Own.Id);
  AddLink(Own.Id, Hidden.Id);
  AddLink(Hidden.Id, Own.Id);
  AddLink(Own.Id, 999999);
  AddLink(999999, Own.Id);
  for Scoped in [False, True] do
  begin
    if Scoped then Context.ScopedProjects := [Own.ProjectID];
    SetRegistry;
    Response := Call('get_item_links', Format('{"item_id":%d}', [Own.Id]));
    try
      Arr := Response.GetValue<TJSONArray>('links');
      Check(Arr.Count = 2, 'Only visible incoming and outgoing links may be returned');
      Check((Arr.Items[0] as TJSONObject).GetValue<Integer>('linked_item_id') = Peer.Id,
        'Visible outgoing link retained');
      Check((Arr.Items[1] as TJSONObject).GetValue<Integer>('linked_item_id') = Peer.Id,
        'Visible incoming link retained');
    finally
      Response.Free;
    end;
  end;
end;

procedure TestAuditVisibility;
var
  Own, Hidden: TProject;
  OwnHyp, HiddenHyp: THypothesis;
  Response: TJSONObject;
  Arr: TJSONArray;
  Row: TJSONValue;
  Scoped: Boolean;
  SeenProject, SeenHypothesis: Boolean;
begin
  Own := AddProject(Notebook.Principal);
  Hidden := AddProject(AddUser('hidden-owner', dbUser));
  OwnHyp := AddHypothesis(Own);
  HiddenHyp := AddHypothesis(Hidden);
  AddAudit(aetProject, Own.Id);
  AddAudit(aetProject, Hidden.Id);
  AddAudit(aetHypothesis, OwnHyp.Id);
  AddAudit(aetHypothesis, HiddenHyp.Id);
  AddAudit(aetHypothesis, 999999);
  AddAudit(aetSetting, 999999);
  for Scoped in [False, True] do
  begin
    if Scoped then Context.ScopedProjects := [Own.Id];
    SetRegistry;
    Response := Call('get_audit_log', '{"operation":"Update"}');
    try
      Arr := Response.GetValue<TJSONArray>('audit_log');
      Check(Arr.Count = 2, 'Only resolvable visible audit rows may be returned');
      SeenProject := False;
      SeenHypothesis := False;
      for Row in Arr do
      begin
        if (Row as TJSONObject).GetValue<string>('entity_type') = 'Project' then
          SeenProject := (Row as TJSONObject).GetValue<Integer>('entity_id') = Own.Id;
        if (Row as TJSONObject).GetValue<string>('entity_type') = 'Hypothesis' then
          SeenHypothesis := (Row as TJSONObject).GetValue<Integer>('entity_id') = OwnHyp.Id;
      end;
      Check(SeenProject and SeenHypothesis, 'Visible project and hypothesis audit retained');
    finally
      Response.Free;
    end;
  end;
end;

procedure RunTest(const Name: string; Test: TProc);
var
  Id: TGUID;
  FixtureDir: string;
begin
  CreateGUID(Id);
  FixtureDir := TPath.Combine(TPath.GetTempPath, 'ELN-Authorization-' + GUIDToString(Id));
  Notebook := nil;
  Registry := nil;
  Context := Default(TToolContext);
  try
    ForceDirectories(FixtureDir);
    try
      Notebook := TLocalNotebook.CreateNew(TPath.Combine(FixtureDir, 'notebook.sqlite'),
        TPath.Combine(FixtureDir, 'attachments'), 'Synthetic', 'Scientist', 'Synthetic-Only!');
      Context.Manager := Notebook.Manager;
      Context.AccessPolicy := Notebook.AccessPolicy;
      Context.User := Notebook.Principal;
      SetRegistry;
      Test();
      Inc(Passed);
      WriteLn('PASS ', Name);
    except
      on E: Exception do
      begin
        Inc(Failed);
        WriteLn('FAIL ', Name, ': ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    FreeAndNil(Registry);
    Context := Default(TToolContext);
    FreeAndNil(Notebook);
    if DirectoryExists(FixtureDir) then TDirectory.Delete(FixtureDir, True);
  end;
end;

end.
