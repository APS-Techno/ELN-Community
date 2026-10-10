unit unit_MCPProtocol;

interface

uses
  System.JSON;

type
  TMCPRequest = record
    Id: TJSONValue;        // cloned — caller must free
    Method: string;
    Params: TJSONObject;   // nil for parameterless methods; NOT owned — do not free
    IsNotification: Boolean;
    RawJSON: TJSONObject;  // the parsed root object — caller must free to release Params
  end;

  TMCPProtocol = class
  public
    class function ParseRequest(const Line: string; out Req: TMCPRequest): Boolean;

    class function MakeResult(const Id: TJSONValue; const AResult: TJSONValue): string;

    class function MakeError(const Id: TJSONValue; Code: Integer; const Msg: string): string;

    class function MakeToolResult(const Id: TJSONValue; const Content: string): string;

    class function MakeToolError(const Id: TJSONValue; const ErrorMsg: string): string;

    class function MakeInitializeResult(const Id: TJSONValue): string;

    class function MakeToolsListResult(const Id: TJSONValue; const Tools: TJSONArray): string;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils;

var
  CachedVersion: string;

// Read the version resource; an unversioned executable must not claim a release.
function ServerVersionString: string;
var
  Size, Handle: DWORD;
  Buffer: TBytes;
  FixedInfo: PVSFixedFileInfo;
  InfoLen: UINT;
begin
  if CachedVersion = '' then
  begin
    CachedVersion := 'unversioned';
    Size := GetFileVersionInfoSize(PChar(ParamStr(0)), Handle);
    if Size > 0 then
    begin
      SetLength(Buffer, Size);
      if GetFileVersionInfo(PChar(ParamStr(0)), Handle, Size, @Buffer[0]) and
         VerQueryValue(@Buffer[0], '\', Pointer(FixedInfo), InfoLen) then
        CachedVersion := Format('%d.%d.%d.%d', [
          HiWord(FixedInfo.dwFileVersionMS),
          LoWord(FixedInfo.dwFileVersionMS),
          HiWord(FixedInfo.dwFileVersionLS),
          LoWord(FixedInfo.dwFileVersionLS)]);
    end;
  end;
  Result := CachedVersion;
end;


function CloneId(const Src: TJSONValue): TJSONValue;
begin
  if Src = nil then
    Result := TJSONNull.Create
  else
    Result := TJSONValue(Src.Clone);
end;

function BuildEnvelope(const Id: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if Id = nil then
    Result.AddPair(TJSONPair.Create('id', TJSONNull.Create))
  else
    Result.AddPair(TJSONPair.Create('id', TJSONValue(Id.Clone)));
end;

function SerializeAndFree(Obj: TJSONObject): string;
begin
  try
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;


class function TMCPProtocol.ParseRequest(const Line: string;
  out Req: TMCPRequest): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  IdVal: TJSONValue;
  MethodVal: TJSONValue;
  ParamsVal: TJSONValue;
begin
  Result := False;

  Req.Id := nil;
  Req.Method := '';
  Req.Params := nil;
  Req.IsNotification := False;
  Req.RawJSON := nil;

  if Line.Trim.IsEmpty then
    Exit;

  Root := TJSONObject.ParseJSONValue(Line);
  if Root = nil then
    Exit;

  if not (Root is TJSONObject) then
  begin
    Root.Free;
    Exit;
  end;

  Obj := TJSONObject(Root);

  MethodVal := Obj.FindValue('method');
  if (MethodVal = nil) or not (MethodVal is TJSONString) then
  begin
    Obj.Free;
    Exit;
  end;
  Req.Method := TJSONString(MethodVal).Value;

  // "id" — absent means notification
  IdVal := Obj.FindValue('id');
  if IdVal = nil then
  begin
    Req.IsNotification := True;
    Req.Id := nil;
  end
  else
  begin
    Req.IsNotification := False;
    Req.Id := TJSONValue(IdVal.Clone);  // independent copy
  end;

  ParamsVal := Obj.FindValue('params');
  if (ParamsVal <> nil) and (ParamsVal is TJSONObject) then
    Req.Params := TJSONObject(ParamsVal)   // owned by Obj
  else
    Req.Params := nil;

  Req.RawJSON := Obj;  // caller must free
  Result := True;
end;

class function TMCPProtocol.MakeResult(const Id: TJSONValue;
  const AResult: TJSONValue): string;
var
  Obj: TJSONObject;
begin
  Obj := BuildEnvelope(Id);
  if AResult = nil then
    Obj.AddPair(TJSONPair.Create('result', TJSONObject.Create))
  else
    Obj.AddPair(TJSONPair.Create('result', TJSONValue(AResult.Clone)));
  Result := SerializeAndFree(Obj);
end;

class function TMCPProtocol.MakeError(const Id: TJSONValue; Code: Integer;
  const Msg: string): string;
var
  Obj, ErrObj: TJSONObject;
begin
  Obj := BuildEnvelope(Id);
  ErrObj := TJSONObject.Create;
  ErrObj.AddPair('code', TJSONNumber.Create(Code));
  ErrObj.AddPair('message', Msg);
  Obj.AddPair('error', ErrObj);  // ErrObj now owned by Obj
  Result := SerializeAndFree(Obj);
end;

class function TMCPProtocol.MakeToolResult(const Id: TJSONValue;
  const Content: string): string;
var
  Obj, ResultObj, ContentItem: TJSONObject;
  ContentArr: TJSONArray;
begin
  Obj := BuildEnvelope(Id);

  ContentItem := TJSONObject.Create;
  ContentItem.AddPair('type', 'text');
  ContentItem.AddPair('text', Content);

  ContentArr := TJSONArray.Create;
  ContentArr.AddElement(ContentItem);

  ResultObj := TJSONObject.Create;
  ResultObj.AddPair('content', ContentArr);

  Obj.AddPair('result', ResultObj);
  Result := SerializeAndFree(Obj);
end;

class function TMCPProtocol.MakeToolError(const Id: TJSONValue;
  const ErrorMsg: string): string;
var
  Obj, ResultObj, ContentItem: TJSONObject;
  ContentArr: TJSONArray;
begin
  Obj := BuildEnvelope(Id);

  ContentItem := TJSONObject.Create;
  ContentItem.AddPair('type', 'text');
  ContentItem.AddPair('text', ErrorMsg);

  ContentArr := TJSONArray.Create;
  ContentArr.AddElement(ContentItem);

  ResultObj := TJSONObject.Create;
  ResultObj.AddPair('content', ContentArr);
  ResultObj.AddPair('isError', TJSONBool.Create(True));

  Obj.AddPair('result', ResultObj);
  Result := SerializeAndFree(Obj);
end;

class function TMCPProtocol.MakeInitializeResult(const Id: TJSONValue): string;
var
  Obj, ResultObj, Capabilities, ToolsCap, ServerInfo: TJSONObject;
begin
  Obj := BuildEnvelope(Id);

  ToolsCap := TJSONObject.Create;
  Capabilities := TJSONObject.Create;
  Capabilities.AddPair('tools', ToolsCap);

  ServerInfo := TJSONObject.Create;
  ServerInfo.AddPair('name', 'eln-mcp-server');
  ServerInfo.AddPair('version', ServerVersionString);

  ResultObj := TJSONObject.Create;
  ResultObj.AddPair('protocolVersion', '2024-11-05');
  ResultObj.AddPair('capabilities', Capabilities);
  ResultObj.AddPair('serverInfo', ServerInfo);

  Obj.AddPair('result', ResultObj);
  Result := SerializeAndFree(Obj);
end;

class function TMCPProtocol.MakeToolsListResult(const Id: TJSONValue;
  const Tools: TJSONArray): string;
var
  Obj, ResultObj: TJSONObject;
begin
  Obj := BuildEnvelope(Id);

  ResultObj := TJSONObject.Create;
  if Tools = nil then
    ResultObj.AddPair('tools', TJSONArray.Create)
  else
    ResultObj.AddPair(TJSONPair.Create('tools', TJSONValue(Tools.Clone)));

  Obj.AddPair('result', ResultObj);
  Result := SerializeAndFree(Obj);
end;

end.
