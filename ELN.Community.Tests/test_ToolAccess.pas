unit test_ToolAccess;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  System.Generics.Defaults,
  DUnitX.TestFramework,
  unit_LocalNotebook, unit_MCPTools;

type
  [TestFixture]
  TToolAccessTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FRegistry: TToolRegistry;
    FCalled: Boolean;
    function NewRegistry: TToolRegistry;
    function NewHandler: TToolHandler;
    procedure AddTool(const Name: string; Access: TToolAccess);
    procedure AddUnclassifiedTool(const Name: string);
    function ListedNames(Registry: TToolRegistry): TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadOnlyRefusesWriteToolBeforeHandler;
    [Test]
    procedure ReadOnlyRefusesUnclassifiedTool;
    [Test]
    procedure ReadOnlyRunsReadTool;
    [Test]
    procedure ReadWriteSessionRunsWriteTool;
    [Test]
    procedure ToolsListOmitsNonReadToolsWhenReadOnly;
    [Test]
    procedure RefusalNamesToolAndMode;
    [Test]
    procedure SharedRegistryHasNoUnclassifiedTool;
    [Test]
    procedure SharedReadAllowlistIsExact;
    [Test]
    procedure McpDeviceKinds;
  end;

implementation

uses
  System.IOUtils,
  unit_UserDevice, unit_ToolCatalog, unit_ReadToolAllowlist;

function JoinNames(const Names: TArray<string>): string;
var
  Sorted: TArray<string>;
begin
  Sorted := Copy(Names);
  TArray.Sort<string>(Sorted, TStringComparer.Ordinal);
  Result := string.Join('|', Sorted);
end;

function TToolAccessTests.NewRegistry: TToolRegistry;
var
  Context: TToolContext;
begin
  Context := Default(TToolContext);
  Context.Manager := FNotebook.Manager;
  Context.User := FNotebook.Principal;
  Context.AccessPolicy := FNotebook.AccessPolicy;
  Context.Storage := FNotebook.Storage;
  Result := TToolRegistry.Create(Context);
end;

function TToolAccessTests.NewHandler: TToolHandler;
begin
  Result :=
    function(const Params: TJSONObject; const Context: TToolContext): TJSONObject
    begin
      FCalled := True;
      Result := TJSONObject.Create;
    end;
end;

procedure TToolAccessTests.AddTool(const Name: string; Access: TToolAccess);
begin
  FRegistry.Register(Name, 'Fixture tool', TJSONObject.Create, NewHandler(),
    tscGlobalRef, Access);
end;

procedure TToolAccessTests.AddUnclassifiedTool(const Name: string);
begin
  FRegistry.Register(Name, 'Fixture tool', TJSONObject.Create, NewHandler(),
    tscGlobalRef);
end;

function TToolAccessTests.ListedNames(Registry: TToolRegistry): TArray<string>;
var
  List: TJSONArray;
  Row: TJSONValue;
begin
  Result := nil;
  List := Registry.GetToolsList;
  try
    for Row in List do
      Result := Result + [Row.GetValue<string>('name')];
  finally
    List.Free;
  end;
end;

procedure TToolAccessTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-ToolAccess-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Tool fixture', 'fixture-password');
  FRegistry := NewRegistry;
  FCalled := False;
end;

procedure TToolAccessTests.TearDown;
begin
  FreeAndNil(FRegistry);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TToolAccessTests.ReadOnlyRefusesWriteToolBeforeHandler;
begin
  AddTool('fake_write', taWrite);
  FRegistry.EnterReadOnly;
  Assert.WillRaise(
    procedure
    begin
      FRegistry.Execute('fake_write', nil).Free;
    end, EToolAccessRefused);
  Assert.IsFalse(FCalled);
end;

procedure TToolAccessTests.ReadOnlyRefusesUnclassifiedTool;
begin
  AddUnclassifiedTool('fake_unclassified');
  FRegistry.EnterReadOnly;
  Assert.WillRaise(
    procedure
    begin
      FRegistry.Execute('fake_unclassified', nil).Free;
    end, EToolAccessRefused);
  Assert.IsFalse(FCalled);
end;

procedure TToolAccessTests.ReadOnlyRunsReadTool;
begin
  AddTool('fake_read', taRead);
  FRegistry.EnterReadOnly;
  Assert.IsTrue(FRegistry.IsReadOnly);
  FRegistry.Execute('fake_read', nil).Free;
  Assert.IsTrue(FCalled);
end;

procedure TToolAccessTests.ReadWriteSessionRunsWriteTool;
begin
  AddTool('fake_write', taWrite);
  Assert.IsFalse(FRegistry.IsReadOnly);
  FRegistry.Execute('fake_write', nil).Free;
  Assert.IsTrue(FCalled);
end;

procedure TToolAccessTests.ToolsListOmitsNonReadToolsWhenReadOnly;
begin
  AddTool('fake_read', taRead);
  AddTool('fake_write', taWrite);
  AddUnclassifiedTool('fake_unclassified');
  Assert.AreEqual('fake_read|fake_unclassified|fake_write',
    JoinNames(ListedNames(FRegistry)));
  FRegistry.EnterReadOnly;
  Assert.AreEqual('fake_read', JoinNames(ListedNames(FRegistry)));
end;

procedure TToolAccessTests.RefusalNamesToolAndMode;
var
  Refusal: string;
begin
  AddTool('fake_write', taWrite);
  FRegistry.EnterReadOnly;
  Refusal := '';
  try
    FRegistry.Execute('fake_write', nil).Free;
  except
    on E: EToolAccessRefused do
      Refusal := E.Message;
  end;
  Assert.AreEqual('Tool "fake_write" is not available in a read-only session.',
    Refusal);
end;

procedure TToolAccessTests.SharedRegistryHasNoUnclassifiedTool;
var
  Shared: TToolRegistry;
  Name: string;
begin
  Shared := TToolRegistry.Create(Default(TToolContext));
  try
    RegisterAllTools(Shared);
    for Name in ListedNames(Shared) do
      Assert.AreNotEqual(Ord(taUnclassified), Ord(Shared.AccessOf(Name)), Name);
  finally
    Shared.Free;
  end;
end;

procedure TToolAccessTests.SharedReadAllowlistIsExact;
var
  Shared: TToolRegistry;
  Name: string;
  Reads, Allowed: TArray<string>;
begin
  Shared := TToolRegistry.Create(Default(TToolContext));
  try
    RegisterAllTools(Shared);
    Reads := nil;
    for Name in ListedNames(Shared) do
      if Shared.AccessOf(Name) = taRead then
        Reads := Reads + [Name];
  finally
    Shared.Free;
  end;
  Allowed := nil;
  for Name in READ_TOOL_NAMES do
    Allowed := Allowed + [Name];
  Assert.AreEqual(JoinNames(Allowed), JoinNames(Reads));
end;

procedure TToolAccessTests.McpDeviceKinds;
begin
  Assert.IsTrue(IsMcpDeviceKind('mcp'));
  Assert.IsTrue(IsMcpDeviceKind('MCP-RO'));
  Assert.IsFalse(IsMcpDeviceKind('web'));
  Assert.IsFalse(IsMcpDeviceKind(''));
  Assert.IsFalse(IsMcpDeviceKind('mcp-rw'));
  Assert.AreEqual('mcp-ro', DEVICE_KIND_MCP_READONLY);
end;

initialization
  TDUnitX.RegisterTestFixture(TToolAccessTests);

end.
