unit unit_ProjectGroupModel;

interface

uses
  SysUtils,
  System.Generics.Collections,
  Aurelius.Bind.Dataset,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Types.Nullable,
  unit_TELNModel,
  unit_Project,
  unit_ProjectGroup;

type
  TProjectGroupModel = class(TELNModel)
    private
      FManager: TObjectManager;
    public
      constructor Create(Manager: TObjectManager);
      procedure OpenDataSet; override;

      function ListGroups(OwnerId: Integer): TProjectGroupList;
      function AddGroup(const Title: string; OwnerId: Integer): TProjectGroup;
      function RenameGroup(Group: TProjectGroup; const Title: string): Boolean;
      function DeleteGroup(GroupId: Integer; UserId: Integer): Boolean;
      procedure ReorderGroups(const OrderedIds: TArray<Integer>);
      procedure SetExpanded(const GroupId: Integer; State: Boolean);
      function MoveProjectToGroup(ProjectId, GroupId: Integer; UserId: Integer): Boolean;
  end;

implementation

uses
  System.StrUtils,
  Aurelius.Commands.Exceptions,
  unit_AuditHelper,
  unit_AuditLog,
  unit_ConflictHandler;

{ TProjectGroupModel }

constructor TProjectGroupModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
end;

procedure TProjectGroupModel.OpenDataSet;
begin
  // No dataset binding needed; groups are consumed as entity lists.
end;

function TProjectGroupModel.ListGroups(OwnerId: Integer): TProjectGroupList;
begin
  Result := FManager.Find<TProjectGroup>
    .Where(Linq['OwnerId'] = OwnerId)
    .OrderBy('SortOrder')
    .OrderBy('Id')
    .List;
end;

function TProjectGroupModel.AddGroup(const Title: string; OwnerId: Integer): TProjectGroup;
begin
  Result := TProjectGroup.Create;
  Result.Title := Title;
  Result.OwnerId := OwnerId;
  Result.SortOrder := 0;
  Result.Expanded := True;
  FManager.Save(Result);
  FManager.Flush(Result);
  RecordAudit(FManager, aetProjectGroup, Result.Id, aoCreate, OwnerId,
    'Created project group "' + Title + '"');
end;

function TProjectGroupModel.RenameGroup(Group: TProjectGroup; const Title: string): Boolean;
begin
  Group.Title := Title;
  FManager.Update(Group);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetProjectGroup, Group.Id, aoUpdate, Group.OwnerId,
      'Renamed project group to "' + Title + '"');
end;

function TProjectGroupModel.DeleteGroup(GroupId: Integer; UserId: Integer): Boolean;
var
  Group: TProjectGroup;
  Members: TList<TProject>;
  P: TProject;
  Title: string;
begin
  Group := FManager.Find<TProjectGroup>(GroupId);
  if not Assigned(Group) then Exit(False);
  Title := Group.Title;

  // Members return to the tree root; projects themselves are never touched
  // beyond the GroupID field.
  Members := FManager.Find<TProject>
    .Where(Linq['GroupID'] = GroupId)
    .List;
  try
    for P in Members do
    begin
      P.GroupID := SNull;
      FManager.Update(P);
    end;
  finally
    Members.Free;
  end;

  FManager.Remove(Group);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetProjectGroup, GroupId, aoDelete, UserId,
      'Deleted project group "' + Title + '" (projects moved to root)');
end;

procedure TProjectGroupModel.ReorderGroups(const OrderedIds: TArray<Integer>);
var
  I: Integer;
  Group: TProjectGroup;
begin
  for I := 0 to High(OrderedIds) do
  begin
    Group := FManager.Find<TProjectGroup>(OrderedIds[I]);
    if Assigned(Group) then
    begin
      Group.SortOrder := I + 1;
      FManager.Flush;
    end;
  end;
end;

procedure TProjectGroupModel.SetExpanded(const GroupId: Integer; State: Boolean);
var
  Group: TProjectGroup;
begin
  Group := FManager.Find<TProjectGroup>(GroupId);
  if not Assigned(Group) then Exit;
  Group.Expanded := State;
  try
    FManager.Flush;
  except
    // UI state: ignore the conflict, but reload the entity that conflicted
    // (this one, or a stale one from elsewhere). Left dirty it would fail
    // every later Flush on this shared manager (review M-1).
    on E: EVersionedConcurrencyControl do
      TConflictHandler.ReloadConflicted(FManager, E);
  end;
end;

function TProjectGroupModel.MoveProjectToGroup(ProjectId, GroupId: Integer;
  UserId: Integer): Boolean;
var
  Project: TProject;
  Group: TProjectGroup;
begin
  Project := FManager.Find<TProject>(ProjectId);
  if not Assigned(Project) then Exit(False);

  if GroupId > 0 then
  begin
    Group := FManager.Find<TProjectGroup>(GroupId);
    if not Assigned(Group) then Exit(False);
    // Single write chokepoint for grouping: a group only ever holds its
    // owner's projects.
    if (not Assigned(Project.Owner)) or (Group.OwnerId <> Project.Owner.Id) then
      Exit(False);
    Project.GroupID := GroupId;
  end
  else
    Project.GroupID := SNull;

  FManager.Update(Project);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetProject, ProjectId, aoUpdate, UserId,
      'Moved project "' + Project.Title + '" ' +
      IfThen(GroupId > 0, 'into group', 'out of its group'));
end;

end.
