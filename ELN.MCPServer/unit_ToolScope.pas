unit unit_ToolScope;

(* Project confinement for MCP tool handlers.

   A session is confined when its device row carries a ProjectScope. An empty
   scope adds no confinement. The injected access policy still decides which
   projects the authenticated user can read.

   Three subject shapes cover every project-owned read in the server, so there
   are three Require* guards:

     project_id parameter -> RequireProjectRead
     item_id parameter    -> RequireItemRead   (TItem.ProjectID is
                                                denormalised, so this is one
                                                field read, not a tree walk)
     file_id parameter    -> RequireFileRead   (TFile -> Item -> ProjectID)

   Handlers that return cross-project result sets (search, list_projects,
   query_values, correlate_values, the audit log) must FILTER with
   IsProjectVisible instead of raising, or a confined caller would just get an
   error whenever any row it cannot see happens to match.

   Refusal and "not found" deliberately produce the SAME message. Distinct
   messages would turn the guards into an existence oracle: a caller could
   walk item ids and learn which ones exist outside its scope. *)

interface

uses
  unit_MCPTools;

/// <summary>True when both the access policy and session scope allow this
/// project.</summary>
function IsProjectVisible(const Context: TToolContext;
  ProjectId: Integer): Boolean;

/// <summary>Raises unless the session may touch this project.</summary>
procedure RequireProjectRead(const Context: TToolContext; ProjectId: Integer);

/// <summary>Resolves the item's project and applies RequireProjectRead. Raises
/// the same way for a missing item as for an out-of-scope one.</summary>
procedure RequireItemRead(const Context: TToolContext; ItemId: Integer);

/// <summary>Resolves the file's item, then its project. Same refusal shape.
/// </summary>
procedure RequireFileRead(const Context: TToolContext; FileId: Int64);

/// <summary>The item's project id, or 0 when the item is missing. For
/// handlers that filter rather than raise.</summary>
function ProjectOfItem(const Context: TToolContext; ItemId: Integer): Integer;

/// <summary>True when this session is confined to a project scope.</summary>
function IsScopeActive(const Context: TToolContext): Boolean;

/// <summary>Raises the uniform refusal unconditionally. For handlers whose
/// subject cannot be resolved to a project at all (e.g. a missing folder)
/// while a scope is active - the "not found" branch must not read
/// differently from the out-of-scope branch.</summary>
procedure RaiseOutOfScope;

implementation

uses
  System.SysUtils, unit_Item;

resourcestring
  // One message for every refusal. See the unit header: separate wording for
  // "does not exist" would let a caller enumerate ids it cannot read.
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
  if not Context.AccessPolicy.CanRead(Context.Manager, Context.User, ProjectId) then
    Exit(False);
  // An empty scope adds no restriction to the policy's decision.
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
  // A missing item and an out-of-scope item are indistinguishable on purpose.
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
