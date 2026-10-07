unit unit_MCPTransport;

interface

uses
  unit_MCPTools;

type
  TBeforeToolCall = reference to procedure;

// Borrows the registry and its providers. The caller owns their full lifecycle.
procedure RunToolServer(Registry: TToolRegistry;
  const BeforeToolCall: TBeforeToolCall = nil);

implementation

uses
  System.SysUtils, System.JSON,
  unit_MCPProtocol, unit_MCPDiag;

procedure RunToolServer(Registry: TToolRegistry;
  const BeforeToolCall: TBeforeToolCall);
var
  Line, Response, ToolName, Ref: string;
  Req: TMCPRequest;
  ToolResult, ToolArgs: TJSONObject;
  ToolsList: TJSONArray;
begin
  SetTextCodePage(Input, 65001);
  SetTextCodePage(Output, 65001);
  WriteLn(ErrOutput, 'ELN MCP Server: entering main loop.');
  Flush(ErrOutput);
  while not EOF(Input) do
  begin
    ReadLn(Input, Line);
    if Line.Trim.IsEmpty then
      Continue;
    if not TMCPProtocol.ParseRequest(Line, Req) then
    begin
      WriteLn(ErrOutput, 'ELN MCP Server: failed to parse request: ' + Line);
      Flush(ErrOutput);
      Continue;
    end;
    try
      // Includes initialized and cancellation notifications: the serial
      // transport never sends a response to a notification.
      if Req.IsNotification then
        Continue;
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
        try
          if (Req.Params = nil) or (Req.Params.FindValue('name') = nil) then
            raise Exception.Create('Missing params.name');
          ToolName := Req.Params.GetValue<string>('name');
          ToolArgs := nil;
          if Req.Params.FindValue('arguments') is TJSONObject then
            ToolArgs := TJSONObject(Req.Params.FindValue('arguments'));
          if not Registry.HasTool(ToolName) then
            Response := TMCPProtocol.MakeError(Req.Id, -32601,
              'Tool not found: ' + ToolName)
          else
          begin
            if Assigned(BeforeToolCall) then
              BeforeToolCall();
            ToolResult := Registry.Execute(ToolName, ToolArgs);
            try
              Response := TMCPProtocol.MakeToolResult(Req.Id, ToolResult.ToJSON);
            finally
              ToolResult.Free;
            end;
          end;
        except
          on E: Exception do
          begin
            Ref := NewCorrelationRef;
            MCPLog(Format('Tool %s failed [ref %s]: %s: %s',
              [ToolName, Ref, E.ClassName, E.Message]));
            WriteLn(ErrOutput, Format('Tool %s failed [ref %s]: %s: %s',
              [ToolName, Ref, E.ClassName, E.Message]));
            Flush(ErrOutput);
            Response := TMCPProtocol.MakeToolError(Req.Id,
              ClientErrorMessage(E, Ref));
          end;
        end;
      end
      else
        Response := TMCPProtocol.MakeError(Req.Id, -32601, 'Method not found');
      WriteLn(Output, Response);
      Flush(Output);
    finally
      Req.RawJSON.Free;
      Req.Id.Free;
    end;
  end;
  WriteLn(ErrOutput, 'ELN MCP Server: EOF reached, shutting down.');
  Flush(ErrOutput);
end;

end.
