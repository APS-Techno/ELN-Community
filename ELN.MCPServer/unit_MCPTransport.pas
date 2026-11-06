unit unit_MCPTransport;

interface

uses
  System.SysUtils,
  unit_MCPTools;

type
  TBeforeToolCall = reference to procedure;

  TToolCallOutcome = (tcoOk, tcoRefused, tcoError, tcoTooLarge, tcoUnknownTool);

  TToolCallRecord = record
    ToolName: string;
    Outcome: TToolCallOutcome;
    ElapsedMs: Int64;
    ResponseBytes: Integer;
    Ref: string;
  end;

  TAfterToolCall = reference to procedure(const Rec: TToolCallRecord);

  TToolServerHooks = record
    BeforeToolCall: TBeforeToolCall;
    AfterToolCall: TAfterToolCall;
    MaxResponseBytes: Integer;
    RedactStderr: Boolean;
  end;

function ToolFailureStderrLine(Redact: Boolean; const ToolName, Ref: string;
  E: Exception): string;

function ToolCallOutcomeName(O: TToolCallOutcome): string;

function HandleRequestLine(Registry: TToolRegistry; const Line: string;
  const Hooks: TToolServerHooks; out Response: string): Boolean;

// Borrows the registry and its providers. The caller owns their full lifecycle.
procedure RunToolServer(Registry: TToolRegistry; const Hooks: TToolServerHooks);

implementation

uses
  System.JSON, System.Diagnostics,
  unit_MCPProtocol, unit_MCPDiag;

function ToolCallOutcomeName(O: TToolCallOutcome): string;
begin
  case O of
    tcoOk: Result := 'ok';
    tcoRefused: Result := 'refused';
    tcoError: Result := 'error';
    tcoTooLarge: Result := 'too_large';
    tcoUnknownTool: Result := 'unknown_tool';
  end;
end;

function ToolFailureStderrLine(Redact: Boolean; const ToolName, Ref: string;
  E: Exception): string;
begin
  if Redact then
    Result := Format('Tool call failed [ref %s]', [Ref])
  else
    Result := Format('Tool %s failed [ref %s]: %s: %s',
      [ToolName, Ref, E.ClassName, E.Message]);
end;

function HandleRequestLine(Registry: TToolRegistry; const Line: string;
  const Hooks: TToolServerHooks; out Response: string): Boolean;
var
  Req: TMCPRequest;
  ToolResult, ToolArgs: TJSONObject;
  ToolsList: TJSONArray;
  ToolName, Ref, Json: string;
  Outcome: TToolCallOutcome;
  Watch: TStopwatch;
  Bytes: Integer;
  Rec: TToolCallRecord;
begin
  Response := '';
  Result := False;
  if Line.Trim.IsEmpty then
    Exit;
  if not TMCPProtocol.ParseRequest(Line, Req) then
  begin
    WriteLn(ErrOutput, 'ELN MCP Server: failed to parse request: ' + Line);
    Flush(ErrOutput);
    Exit;
  end;
  try
    // Includes initialized and cancellation notifications: the serial
    // transport never sends a response to a notification.
    if Req.IsNotification then
      Exit;
    if Req.Method = 'initialize' then
      Response := TMCPProtocol.MakeInitializeResult(Req.Id)
    else if Req.Method = 'tools/list' then
    begin
      ToolsList := Registry.GetToolsList;
      try
        Response := TMCPProtocol.MakeToolsListResult(Req.Id, ToolsList);
      finally
        ToolsList.Free;
      end;
    end
    else if Req.Method = 'tools/call' then
    begin
      ToolName := '';
      Ref := '';
      Outcome := tcoOk;
      Watch := TStopwatch.StartNew;
      try
        if (Req.Params = nil) or (Req.Params.FindValue('name') = nil) then
          raise Exception.Create('Missing params.name');
        ToolName := Req.Params.GetValue<string>('name');
        ToolArgs := nil;
        if Req.Params.FindValue('arguments') is TJSONObject then
          ToolArgs := TJSONObject(Req.Params.FindValue('arguments'));
        if not Registry.HasTool(ToolName) then
        begin
          Outcome := tcoUnknownTool;
          Response := TMCPProtocol.MakeError(Req.Id, -32601,
            'Tool not found: ' + ToolName);
        end
        else
        begin
          if Assigned(Hooks.BeforeToolCall) then
            Hooks.BeforeToolCall();
          ToolResult := Registry.Execute(ToolName, ToolArgs);
          try
            Json := ToolResult.ToJSON;
          finally
            ToolResult.Free;
          end;
          Bytes := TEncoding.UTF8.GetByteCount(Json);
          if (Hooks.MaxResponseBytes > 0) and (Bytes > Hooks.MaxResponseBytes) then
          begin
            Outcome := tcoTooLarge;
            Ref := NewCorrelationRef;
            MCPLog(Format('Tool %s response too large [ref %s]: %d bytes, limit %d',
              [ToolName, Ref, Bytes, Hooks.MaxResponseBytes]));
            Response := TMCPProtocol.MakeToolError(Req.Id, Format(
              'Response too large: %d bytes exceeds the limit of %d bytes. ' +
              'Narrow the request (limit, project_id, item_id or columns).',
              [Bytes, Hooks.MaxResponseBytes]));
          end
          else
            Response := TMCPProtocol.MakeToolResult(Req.Id, Json);
        end;
      except
        on E: Exception do
        begin
          if E is EToolAccessRefused then
            Outcome := tcoRefused
          else
            Outcome := tcoError;
          Ref := NewCorrelationRef;
          MCPLog(Format('Tool %s failed [ref %s]: %s: %s',
            [ToolName, Ref, E.ClassName, E.Message]));
          WriteLn(ErrOutput, ToolFailureStderrLine(Hooks.RedactStderr, ToolName,
            Ref, E));
          Flush(ErrOutput);
          Response := TMCPProtocol.MakeToolError(Req.Id,
            ClientErrorMessage(E, Ref));
        end;
      end;
      if Assigned(Hooks.AfterToolCall) then
      begin
        Rec.ToolName := ToolName;
        Rec.Outcome := Outcome;
        Rec.ElapsedMs := Watch.ElapsedMilliseconds;
        Rec.ResponseBytes := TEncoding.UTF8.GetByteCount(Response);
        Rec.Ref := Ref;
        try
          Hooks.AfterToolCall(Rec);
        except
          on E: Exception do
            MCPLog(Format('AfterToolCall hook failed for %s: %s: %s',
              [ToolName, E.ClassName, E.Message]));
        end;
      end;
    end
    else
      Response := TMCPProtocol.MakeError(Req.Id, -32601, 'Method not found');
    Result := True;
  finally
    Req.RawJSON.Free;
    Req.Id.Free;
  end;
end;

procedure RunToolServer(Registry: TToolRegistry; const Hooks: TToolServerHooks);
var
  Line, Response: string;
begin
  SetTextCodePage(Input, 65001);
  SetTextCodePage(Output, 65001);
  WriteLn(ErrOutput, 'ELN MCP Server: entering main loop.');
  Flush(ErrOutput);
  while not EOF(Input) do
  begin
    ReadLn(Input, Line);
    if HandleRequestLine(Registry, Line, Hooks, Response) then
    begin
      WriteLn(Output, Response);
      Flush(Output);
    end;
  end;
  WriteLn(ErrOutput, 'ELN MCP Server: EOF reached, shutting down.');
  Flush(ErrOutput);
end;

end.
