unit unit_ToolScope;

(* Empty scope adds no confinement beyond the access policy. Cross-project
   results must filter invisible rows instead of refusing the entire query.
   Missing and inaccessible subjects must share a refusal message; distinct
   messages would expose the existence of records outside the scope. *)

interface

uses
  unit_MCPTools;

function IsProjectVisible(const Context: TToolContext;
  ProjectId: Integer): Boolean;

procedure RequireProjectRead(const Context: TToolContext; ProjectId: Integer);

procedure RequireItemRead(const Context: TToolContext; ItemId: Integer);

procedure RequireFileRead(const Context: TToolContext; FileId: Int64);

/// <summary>The item's project id, or 0 when the item is missing. For
/// handlers that filter rather than raise.</summary>
function ProjectOfItem(const Context: TToolContext; ItemId: Integer): Integer;

function IsScopeActive(const Context: TToolContext): Boolean;

procedure RaiseOutOfScope;

implementation

uses
  System.SysUtils, unit_Item;

resourcestring
  SOutOfScope = 'Access denied: that record is outside this session''s ' +
    'project scope, or does not exist.';

function IsScopeActive(const Context: TToolContext): Boolean;
begin
  Result := Length(Context.ScopedProjects) > 0;
end;

procedure RaiseOutOfScope;
begin
  raise Exception.Create(SOutOfScope);
end;

function IsProjectVisible(const Context: TToolContext;
  ProjectId: Integer): Boolean;
var
  Allowed: Integer;
begin
  if (Context.AccessPolicy = nil) or (Context.User = nil) then
    Exit(False);
  if not Context.AccessPolicy.CanRead(Context.Manager, Context.User, ProjectId) then
    Exit(False);
  if Length(Context.ScopedProjects) = 0 then
    Exit(True);
  for Allowed in Context.ScopedProjects do
    if Allowed = ProjectId then
      Exit(True);
  Result := False;
end;

procedure RequireProjectRead(const Context: TToolContext; ProjectId: Integer);
begin
  if not IsProjectVisible(Context, ProjectId) then
    raise Exception.Create(SOutOfScope);
end;

function ProjectOfItem(const Context: TToolContext; ItemId: Integer): Integer;
var
  Item: TItem;
begin
  Result := 0;
  Item := Context.Manager.Find<TItem>(ItemId);
  if Item <> nil then
    Result := Item.ProjectID;
end;

procedure RequireItemRead(const Context: TToolContext; ItemId: Integer);
var
  ProjectId: Integer;
begin
  ProjectId := ProjectOfItem(Context, ItemId);
  if ProjectId = 0 then
    raise Exception.Create(SOutOfScope);
  RequireProjectRead(Context, ProjectId);
end;

procedure RequireFileRead(const Context: TToolContext; FileId: Int64);
var
  F: TFile;
  ProjectId: Integer;
begin
  ProjectId := 0;
  F := Context.Manager.Find<TFile>(FileId);
  if (F <> nil) and (F.Item <> nil) then
    ProjectId := F.Item.ProjectID;
  if ProjectId = 0 then
    raise Exception.Create(SOutOfScope);
  RequireProjectRead(Context, ProjectId);
end;

end.
