unit unit_MCPTools;

interface

uses
  System.JSON, System.SysUtils, System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_PluginHost,
  unit_NotebookStorage,
  unit_ProjectAccessPolicy,
  unit_User;

type
  // Unclassified tools fail closed under a scope; new tools need an explicit classification.
  TToolScoping = (
    tscUnclassified,
    /// Reads or writes project-owned data and enforces the scope itself,
    /// through the unit_ToolScope guards.
    tscProjectScoped,
    /// Touches only global reference data with no project dimension
    /// (equipment, action types, value types, file types, audit rules).
    tscGlobalRef);

  TToolContext = record
    Manager: TObjectManager;
    StorageRoot: string;
    PluginHost: TPluginHost;
    Storage: INotebookStorage;
    AccessPolicy: IProjectAccessPolicy;
    User: TUser;
    UploadRoot: string;
    /// <summary>Projects this session may touch. Empty means unrestricted.
    /// Hosts set the scope before serving requests.</summary>
    ScopedProjects: TArray<Integer>;
    /// <summary>Optional session attribution id, or zero for a local session.
    /// Recorded on hypotheses and their history.</summary>
    DeviceId: Integer;
  end;

  TToolHandler = reference to function(const Params: TJSONObject;
    const Context: TToolContext): TJSONObject;

  TToolDef = record
    Name: string;
    Description: string;
    InputSchema: TJSONObject;  // JSON Schema for parameters - owned by TToolDef
    Handler: TToolHandler;
    Scoping: TToolScoping;
  end;

  TToolRegistry = class
  private
    FTools: TList<TToolDef>;
    FContext: TToolContext;
  public
    constructor Create(const AContext: TToolContext);
    destructor Destroy; override;
    procedure Register(const Name, Description: string;
      InputSchema: TJSONObject; Handler: TToolHandler;
      Scoping: TToolScoping = tscUnclassified);
    // Replaces one existing definition and takes ownership of the new schema.
    procedure Replace(const Name, Description: string;
      InputSchema: TJSONObject; Handler: TToolHandler;
      Scoping: TToolScoping = tscUnclassified);
    function GetToolsList: TJSONArray;
    function Execute(const ToolName: string; const Params: TJSONObject): TJSONObject;
    function HasTool(const Name: string): Boolean;
    // The registry copies the context. Replacing the caller's User cannot update
    // handlers after manager Clear destroys the old principal.
    procedure SetUser(AUser: TUser);
    // Update the registry's context copy, not just the caller's scope.
    procedure SetScope(const AScope: TArray<Integer>);
    function IsScoped: Boolean;
    function ScopingOf(const Name: string): TToolScoping;
  end;

// Applies to global tools as well as project-scoped handlers.
procedure RequireToolPrincipal(const Context: TToolContext);

implementation

procedure RequireToolPrincipal(const Context: TToolContext);
begin
  if (Context.User = nil) or (Context.AccessPolicy = nil) then
    raise Exception.Create('Access denied: no valid MCP session identity.');
  if (Context.User.Id <= 0) or Context.User.IsArchived or
     not IsKnownRole(Context.User.Role) then
    raise Exception.Create('Access denied: no valid MCP session identity.');
end;


constructor TToolRegistry.Create(const AContext: TToolContext);
begin
  inherited Create;
  FContext := AContext;
  FTools := TList<TToolDef>.Create;
end;

destructor TToolRegistry.Destroy;
var
  I: Integer;
begin
  for I := 0 to FTools.Count - 1 do
    FTools[I].InputSchema.Free;
  FTools.Free;
  inherited Destroy;
end;

procedure TToolRegistry.SetUser(AUser: TUser);
begin
  FContext.User := AUser;
end;

procedure TToolRegistry.SetScope(const AScope: TArray<Integer>);
begin
  FContext.ScopedProjects := AScope;
end;

function TToolRegistry.IsScoped: Boolean;
begin
  Result := Length(FContext.ScopedProjects) > 0;
end;

procedure TToolRegistry.Register(const Name, Description: string;
  InputSchema: TJSONObject; Handler: TToolHandler; Scoping: TToolScoping);
var
  Def: TToolDef;
begin
  Def.Name := Name;
  Def.Description := Description;
  Def.InputSchema := InputSchema;
  Def.Handler := Handler;
  Def.Scoping := Scoping;
  FTools.Add(Def);
end;

procedure TToolRegistry.Replace(const Name, Description: string;
  InputSchema: TJSONObject; Handler: TToolHandler; Scoping: TToolScoping);
var
  I: Integer;
  Def: TToolDef;
begin
  for I := 0 to FTools.Count - 1 do
    if FTools[I].Name = Name then
    begin
      Def := FTools[I];
      Def.InputSchema.Free;
      Def.Description := Description;
      Def.InputSchema := InputSchema;
      Def.Handler := Handler;
      Def.Scoping := Scoping;
      FTools[I] := Def;
      Exit;
    end;
  InputSchema.Free;
  raise Exception.CreateFmt('Tool not found: %s', [Name]);
end;

function TToolRegistry.GetToolsList: TJSONArray;
var
  I: Integer;
  ToolObj: TJSONObject;
  Def: TToolDef;
begin
  Result := TJSONArray.Create;
  for I := 0 to FTools.Count - 1 do
  begin
    Def := FTools[I];
    ToolObj := TJSONObject.Create;
    ToolObj.AddPair('name', Def.Name);
    ToolObj.AddPair('description', Def.Description);
    ToolObj.AddPair(TJSONPair.Create('inputSchema',
      TJSONValue(Def.InputSchema.Clone)));
    Result.AddElement(ToolObj);
  end;
end;

function TToolRegistry.Execute(const ToolName: string;
  const Params: TJSONObject): TJSONObject;
var
  I: Integer;
  Def: TToolDef;
begin
  RequireToolPrincipal(FContext);
  for I := 0 to FTools.Count - 1 do
  begin
    Def := FTools[I];
    if Def.Name = ToolName then
    begin
  // Refuse unclassified tools rather than expose another project's data.
      if IsScoped and (Def.Scoping = tscUnclassified) then
        raise Exception.CreateFmt(
          'Tool "%s" has not been classified for confined operation and is ' +
          'refused. Classify it where it is registered: its Registry.Register ' +
          'call in the tool group''s unit_ToolsXxx (groups are listed in ' +
          'unit_ToolCatalog.RegisterAllTools).', [ToolName]);
      Exit(Def.Handler(Params, FContext));
    end;
  end;
  raise Exception.CreateFmt('Tool not found: %s', [ToolName]);
end;

function TToolRegistry.ScopingOf(const Name: string): TToolScoping;
var
  I: Integer;
begin
  for I := 0 to FTools.Count - 1 do
    if FTools[I].Name = Name then
      Exit(FTools[I].Scoping);
  raise Exception.CreateFmt('Tool not found: %s', [Name]);
end;

function TToolRegistry.HasTool(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to FTools.Count - 1 do
    if FTools[I].Name = Name then
      Exit(True);
  Result := False;
end;

end.
