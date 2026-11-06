unit test_MCPTransportHooks;

interface

uses
  System.SysUtils, System.JSON,
  DUnitX.TestFramework,
  unit_LocalNotebook, unit_MCPTools, unit_MCPTransport;

type
  [TestFixture]
  TMCPTransportHooksTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FRegistry: TToolRegistry;
    FRecords: TArray<TToolCallRecord>;
    function NewRegistry: TToolRegistry;
    procedure AddSmallTool(const Name: string; Access: TToolAccess);
    procedure AddBigTool(const Name: string);
    function CallLine(const Name: string): string;
    function RunLine(const Line: string; MaxBytes: Integer;
      out Response: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AfterHookReportsOk;
    [Test]
    procedure AfterHookReportsRefused;
    [Test]
    procedure OversizedResultBecomesToolError;
    [Test]
    procedure ZeroCapMeansNoLimit;
    [Test]
    procedure UnknownToolReportsOutcome;
    [Test]
    procedure NotificationGivesNoResponse;
    [Test]
    procedure HookExceptionKeepsResponse;
    [Test]
    procedure OutcomeNames;
    [Test]
    procedure StderrLineHidesDetailsWhenRedacted;
  end;

implementation

uses
  System.IOUtils;

function TMCPTransportHooksTests.NewRegistry: TToolRegistry;
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

procedure TMCPTransportHooksTests.AddSmallTool(const Name: string;
  Access: TToolAccess);
begin
  FRegistry.Register(Name, 'Fixture tool', TJSONObject.Create,
    function(const Params: TJSONObject; const Context: TToolContext): TJSONObject
    begin
      Result := TJSONObject.Create;
      Result.AddPair('ok', TJSONTrue.Create);
    end, tscGlobalRef, Access);
end;

procedure TMCPTransportHooksTests.AddBigTool(const Name: string);
begin
  FRegistry.Register(Name, 'Fixture tool', TJSONObject.Create,
    function(const Params: TJSONObject; const Context: TToolContext): TJSONObject
    begin
      Result := TJSONObject.Create;
      Result.AddPair('s', StringOfChar('a', 2048));
    end, tscGlobalRef, taRead);
end;

function TMCPTransportHooksTests.CallLine(const Name: string): string;
begin
  Result := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"' +
    Name + '","arguments":{}}}';
end;

function TMCPTransportHooksTests.RunLine(const Line: string; MaxBytes: Integer;
  out Response: string): Boolean;
var
  Hooks: TToolServerHooks;
begin
  Hooks := Default(TToolServerHooks);
  Hooks.MaxResponseBytes := MaxBytes;
  Hooks.AfterToolCall :=
    procedure(const Rec: TToolCallRecord)
    begin
      FRecords := FRecords + [Rec];
    end;
  Result := HandleRequestLine(FRegistry, Line, Hooks, Response);
end;

procedure TMCPTransportHooksTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-TransportHooks-' + TGUID.NewGuid.ToString);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Tool fixture', 'fixture-password');
  FRegistry := NewRegistry;
  FRecords := nil;
end;

procedure TMCPTransportHooksTests.TearDown;
begin
  FreeAndNil(FRegistry);
  FreeAndNil(FNotebook);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TMCPTransportHooksTests.AfterHookReportsOk;
var
  Response: string;
begin
  AddSmallTool('fake_read', taRead);
  Assert.IsTrue(RunLine(CallLine('fake_read'), 0, Response));
  Assert.AreEqual<Integer>(1, Length(FRecords));
  Assert.AreEqual('fake_read', FRecords[0].ToolName);
  Assert.IsTrue(FRecords[0].Outcome = tcoOk);
  Assert.IsTrue(FRecords[0].ResponseBytes > 0);
  Assert.AreEqual('', FRecords[0].Ref);
end;

procedure TMCPTransportHooksTests.AfterHookReportsRefused;
var
  Response: string;
begin
  AddSmallTool('fake_write', taWrite);
  FRegistry.EnterReadOnly;
  Assert.IsTrue(RunLine(CallLine('fake_write'), 0, Response));
  Assert.AreEqual<Integer>(1, Length(FRecords));
  Assert.IsTrue(FRecords[0].Outcome = tcoRefused);
  Assert.AreNotEqual('', FRecords[0].Ref);
  Assert.Contains(Response, '"isError":true');
  Assert.Contains(Response, 'not available in a read-only session');
end;

procedure TMCPTransportHooksTests.OversizedResultBecomesToolError;
var
  Response: string;
begin
  AddBigTool('fake_big');
  Assert.IsTrue(RunLine(CallLine('fake_big'), 1024, Response));
  Assert.AreEqual<Integer>(1, Length(FRecords));
  Assert.IsTrue(FRecords[0].ResponseBytes > 0);
  Assert.AreNotEqual('', FRecords[0].Ref);
  Assert.IsTrue(FRecords[0].Outcome = tcoTooLarge);
  Assert.Contains(Response, '"isError":true');
  Assert.Contains(Response, 'Response too large');
end;

procedure TMCPTransportHooksTests.ZeroCapMeansNoLimit;
var
  Response: string;
begin
  AddBigTool('fake_big');
  Assert.IsTrue(RunLine(CallLine('fake_big'), 0, Response));
  Assert.AreEqual<Integer>(1, Length(FRecords));
  Assert.IsTrue(FRecords[0].Outcome = tcoOk);
end;

procedure TMCPTransportHooksTests.UnknownToolReportsOutcome;
var
  Response: string;
begin
  Assert.IsTrue(RunLine(CallLine('no_such_tool'), 0, Response));
  Assert.AreEqual<Integer>(1, Length(FRecords));
  Assert.IsTrue(FRecords[0].Outcome = tcoUnknownTool);
  Assert.Contains(Response, '-32601');
end;

procedure TMCPTransportHooksTests.NotificationGivesNoResponse;
var
  Response: string;
begin
  Assert.IsFalse(RunLine(
    '{"jsonrpc":"2.0","method":"notifications/initialized"}', 0, Response));
  Assert.AreEqual<Integer>(0, Length(FRecords));
end;

procedure TMCPTransportHooksTests.HookExceptionKeepsResponse;
var
  Hooks: TToolServerHooks;
  Response: string;
begin
  AddSmallTool('fake_read', taRead);
  Hooks := Default(TToolServerHooks);
  Hooks.AfterToolCall :=
    procedure(const Rec: TToolCallRecord)
    begin
      raise Exception.Create('hook failed');
    end;
  Assert.IsTrue(HandleRequestLine(FRegistry, CallLine('fake_read'), Hooks, Response));
  Assert.Contains(Response, '"result"');
  Assert.IsFalse(Response.Contains('"isError":true'));
end;

procedure TMCPTransportHooksTests.OutcomeNames;
begin
  Assert.AreEqual('ok', ToolCallOutcomeName(tcoOk));
  Assert.AreEqual('refused', ToolCallOutcomeName(tcoRefused));
  Assert.AreEqual('error', ToolCallOutcomeName(tcoError));
  Assert.AreEqual('too_large', ToolCallOutcomeName(tcoTooLarge));
  Assert.AreEqual('unknown_tool', ToolCallOutcomeName(tcoUnknownTool));
end;

procedure TMCPTransportHooksTests.StderrLineHidesDetailsWhenRedacted;
var
  E: Exception;
  Redacted, Full: string;
begin
  E := EInvalidOp.Create('SELECT secret FROM hidden_table');
  try
    Redacted := ToolFailureStderrLine(True, 'get_item', 'abc123', E);
    Full := ToolFailureStderrLine(False, 'get_item', 'abc123', E);
  finally
    E.Free;
  end;
  Assert.AreEqual('Tool call failed [ref abc123]', Redacted);
  Assert.Contains(Full, 'hidden_table');
  Assert.Contains(Full, 'EInvalidOp');
end;

initialization
  TDUnitX.RegisterTestFixture(TMCPTransportHooksTests);

end.
