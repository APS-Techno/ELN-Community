unit unit_MCPDiag;

// Diagnostics for the MCP server: a log file that actually exists, and the
// decision of what to tell the client when a tool raises.
//
// Background (incident 2026-08-09): every tool failure was reported to the
// client as the fixed string "Tool execution failed. See server log for
// details." The real exception went to stderr, which the MCP host discards,
// and TConnectionModule.LogFile pointed inside "C:\Program Files (x86)\...",
// which a non-elevated process cannot write. So the message named a log that
// did not exist and no diagnosis was possible after the fact.

interface

uses
  System.SysUtils;

{ Directory and full path of the server log. Under %LOCALAPPDATA% so a
  non-elevated process can actually write it. }
function MCPLogDir: string;
function MCPLogPath: string;

{ Append one timestamped line. Never raises: logging must not be able to
  break a tool call. }
procedure MCPLog(const Msg: string);

{ Short opaque id printed both to the log and to the client, so a user-visible
  failure can be tied to a log line without exposing internals. }
function NewCorrelationRef: string;

{ MKCOL status codes that mean "the collection exists now".
  201 Created, 200 OK, 405 Method Not Allowed (already a collection).
  Anything else - notably 409 Conflict (missing parent), 403, 507 - is a
  failure that must not be swallowed. }
function IsMkColStatusOk(StatusCode: Integer): Boolean;

{ What the client is told when a tool raises.

  Tools raise their deliberate, user-facing validation errors as the plain
  base class Exception ('Item not found: 5', 'Item is signed and cannot be
  modified.', 'WebDAV upload failed for: ...'). Those are safe and useful, so
  they are passed through verbatim.

  Anything else is an infrastructure exception - a descendant class such as
  EFDDBEngineException or EAureliusException - whose message can contain SQL
  text, connection strings or file paths. Those are replaced with a generic
  message naming only the class, the log path and the correlation ref. }
function ClientErrorMessage(E: Exception; const Ref: string): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.SyncObjs;

var
  // Serialises MCPLog across threads so two concurrent tool calls cannot
  // interleave halves of a line into the file.
  LogLock: TCriticalSection = nil;

function MCPLogDir: string;
begin
  // TPath.GetHomePath is %LOCALAPPDATA% on Windows — writable without elevation,
  // unlike the exe directory under "C:\Program Files (x86)\".
  Result := TPath.Combine(TPath.GetHomePath, 'E-LabNotebook3');
end;

function MCPLogPath: string;
begin
  Result := MCPLogDir + '\mcp-server.log';
end;

procedure MCPLog(const Msg: string);
var
  Line: string;
begin
  // Logging must never be able to break a tool call, so every failure here —
  // unwritable directory, locked file, full disk — is swallowed.
  try
    Line := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True) +
      '  ' + Msg + sLineBreak;
    if Assigned(LogLock) then
      LogLock.Enter;
    try
      if not TDirectory.Exists(MCPLogDir) then
        TDirectory.CreateDirectory(MCPLogDir);
      TFile.AppendAllText(MCPLogPath, Line, TEncoding.UTF8);
    finally
      if Assigned(LogLock) then
        LogLock.Leave;
    end;
  except
    // Deliberately ignored.
  end;
end;

function NewCorrelationRef: string;
var
  G: TGuid;
begin
  // The first 32 random bits of a v4 GUID are plenty to tie a client-visible
  // failure back to its log line.
  G := TGuid.NewGuid;
  Result := LowerCase(IntToHex(G.D1, 8));
end;

function IsMkColStatusOk(StatusCode: Integer): Boolean;
begin
  // 201 Created, 200 OK, 405 Method Not Allowed (already a collection).
  // 0 means "no status at all" (transport exception) and is a failure.
  // Written as comparisons, not "in [...]": Delphi sets only span 0..255, so
  // 405 in a set constant is a compile-time subrange violation (W1012).
  Result := (StatusCode = 200) or (StatusCode = 201) or (StatusCode = 405);
end;

function ClientErrorMessage(E: Exception; const Ref: string): string;
begin
  // Exact class match, not "is": a tool's deliberate raise Exception.Create(...)
  // is user-facing and safe; any descendant is infrastructure and its message
  // may carry SQL text, connection strings or server paths.
  if E.ClassType = Exception then
    Result := E.Message + ' [ref ' + Ref + ']'
  else
    Result := Format('Tool execution failed (%s). See %s [ref %s]',
      [E.ClassName, MCPLogPath, Ref]);
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  FreeAndNil(LogLock);

end.
