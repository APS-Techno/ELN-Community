unit unit_RemoteSemanticSearch;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Diagnostics, unit_TextEmbedder,
  unit_SemanticSearchApi;

type
  TRemoteHttpResponse = record
    StatusCode: Integer;
    Body: string;
  end;

  IRemoteSearchTransport = interface
    ['{9D2E4B71-3C58-4F0A-B6E2-71A8C5D30F94}']
    function Send(const Method, Url, Token, Body: string;
      TimeoutMs: Integer): TRemoteHttpResponse;
  end;

  TRemoteSemanticSearch = class(TInterfacedObject, ISemanticSearch)
  private
    FBaseUrl: string;
    FGetToken: TFunc<string>;
    FTimeoutMs: Integer;
    FIntervalMs: Integer;
    FTransport: IRemoteSearchTransport;
    FLock: TCriticalSection;
    FWake: TEvent;
    FRefresher: TThread;
    FClock: TStopwatch;
    FStatus: TSemanticSearchStatus;
    FReranker: Boolean;
    FDropped: Integer;
    FUpdated: Boolean;
    FUpdatedAt: Int64;
    FRefreshing: Boolean;
    function SendOnce(const Method, Url, Token, Body: string;
      TimeoutMs: Integer): TRemoteHttpResponse;
    function Exchange(const Method, Path, Body: string): TRemoteHttpResponse;
    function Store(const Fresh: TSemanticSearchStatus; Dropped: Integer): TSemanticSearchStatus;
    procedure MarkFailed(const Text: string);
    function RefreshDue: Boolean;
    procedure RefreshStatus;
  public
    constructor Create(const BaseUrl: string; const GetToken: TFunc<string>;
      TimeoutMs: Integer); overload;
    constructor Create(const BaseUrl: string; const GetToken: TFunc<string>;
      TimeoutMs: Integer; const Transport: IRemoteSearchTransport;
      StatusIntervalMs: Integer); overload;
    destructor Destroy; override;
    function Search(const Request: TSemanticSearchRequest;
      const Cancelled: TCancelCheck): TSemanticSearchResult;
    function Status: TSemanticSearchStatus;
    function RerankerAvailable: Boolean;
    function IsRemote: Boolean;
  end;

const
  DefaultStatusIntervalMs = 10000;

implementation

uses
  System.JSON, System.Generics.Collections, System.Net.URLClient,
  System.Net.HttpClient, unit_SearchPassages, unit_HybridSearch, unit_NativeLibrary;

const
  SearchPath = '/search/semantic';
  StatusPath = '/search/status';
  MaxMessageChars = 300;
  TimeoutToleranceMs = 50;

  SBadUrl = 'The search server address must start with http:// or https://.';
  SNoToken = 'A token callback is required.';
  SBadTimeout = 'The timeout must be a positive number of milliseconds.';
  SBadInterval = 'The status interval must be a positive number of milliseconds.';
  SNoTransport = 'A transport is required.';
  STimedOut = 'The search server %s did not answer within %d ms.';
  SNotReachable = 'The search server %s is not reachable: %s';
  SNotTrusted = 'The certificate of the search server %s is not trusted by this computer (%s). ' +
    'Install the server certificate or its authority in the trust store of the operating system.';
  SUnavailable = 'The search server is not available: %s';
  SHttpError = 'The search server returned HTTP %d: %s';
  SNoMessage = 'HTTP %d without a message';
  STokenRejected = 'The search server did not accept the access token: %s';
  SRefused = 'The search server refused access: %s';
  SInvalidResponse = 'The search server returned an invalid response: %s';
  SDeadlinePassed = 'The request was cancelled at its deadline.';
  SMissing = '"%s" is missing.';
  SNotNumber = '"%s" must be a number.';
  SNotBoolean = '"%s" must be true or false.';
  SNotString = '"%s" must be a string.';
  SNotArray = '"%s" must be an array.';
  SNotObject = '"%s" must be an object.';
  SUnknownName = '"%s" is not a known %s.';
  SNoPassages = 'Item %d has no passages.';

type
  ERemoteFormat = class(Exception);

  TStatusRefresher = class(TThread)
  private
    FOwner: TRemoteSemanticSearch;
  protected
    procedure Execute; override;
  public
    constructor Create(Owner: TRemoteSemanticSearch);
  end;

  THttpSearchTransport = class(TInterfacedObject, IRemoteSearchTransport)
  public
    function Send(const Method, Url, Token, Body: string;
      TimeoutMs: Integer): TRemoteHttpResponse;
  end;

function Member(const Obj: TJSONObject; const Key: string): TJSONValue;
begin
  Result := Obj.GetValue(Key);
  if Result = nil then
    raise ERemoteFormat.CreateFmt(SMissing, [Key]);
end;

function NumberOf(const Obj: TJSONObject; const Key: string): TJSONNumber;
var
  Value: TJSONValue;
begin
  Value := Member(Obj, Key);
  if not (Value is TJSONNumber) then
    raise ERemoteFormat.CreateFmt(SNotNumber, [Key]);
  Result := TJSONNumber(Value);
end;

function BoolOf(const Obj: TJSONObject; const Key: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := Member(Obj, Key);
  if not (Value is TJSONBool) then
    raise ERemoteFormat.CreateFmt(SNotBoolean, [Key]);
  Result := TJSONBool(Value).AsBoolean;
end;

function TextOf(const Value: TJSONValue; const Key: string): string;
begin
  if not (Value is TJSONString) or (Value is TJSONNumber) then
    raise ERemoteFormat.CreateFmt(SNotString, [Key]);
  Result := Value.Value;
end;

function ArrayOf(const Obj: TJSONObject; const Key: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Value := Member(Obj, Key);
  if not (Value is TJSONArray) then
    raise ERemoteFormat.CreateFmt(SNotArray, [Key]);
  Result := TJSONArray(Value);
end;

function ObjectOf(const Value: TJSONValue; const Key: string): TJSONObject;
begin
  if not (Value is TJSONObject) then
    raise ERemoteFormat.CreateFmt(SNotObject, [Key]);
  Result := TJSONObject(Value);
end;

function ParseRoot(const Text: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(Text);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise ERemoteFormat.Create('The body is not a JSON object.');
  end;
  Result := TJSONObject(Value);
end;

function FieldNamed(const Name: string): TPassageField;
var
  Field: TPassageField;
begin
  for Field := Low(TPassageField) to High(TPassageField) do
    if PassageFieldNames[Field] = Name then
      Exit(Field);
  raise ERemoteFormat.CreateFmt(SUnknownName, [Name, 'passage field']);
end;

function SourceNamed(const Name: string): TSearchHitSource;
var
  Source: TSearchHitSource;
begin
  for Source := Low(TSearchHitSource) to High(TSearchHitSource) do
    if HitSourceNames[Source] = Name then
      Exit(Source);
  raise ERemoteFormat.CreateFmt(SUnknownName, [Name, 'source']);
end;

function ParseGroup(const Obj: TJSONObject): THybridGroup;
var
  Node: TJSONValue;
  Passages: TJSONArray;
  Passage: TJSONObject;
  Hit: THybridHit;
  I: Integer;
begin
  Result := Default(THybridGroup);
  Result.ItemId := NumberOf(Obj, 'item_id').AsInt;
  Result.ProjectId := NumberOf(Obj, 'project_id').AsInt;
  Result.Score := NumberOf(Obj, 'score').AsDouble;
  for Node in ArrayOf(Obj, 'sources') do
    Include(Result.Sources, SourceNamed(TextOf(Node, 'sources')));
  Passages := ArrayOf(Obj, 'passages');
  if Passages.Count = 0 then
    raise ERemoteFormat.CreateFmt(SNoPassages, [Result.ItemId]);
  SetLength(Result.Passages, Passages.Count);
  for I := 0 to Passages.Count - 1 do
  begin
    Passage := ObjectOf(Passages.Items[I], 'passages');
    Hit := Default(THybridHit);
    Hit.ItemId := Result.ItemId;
    Hit.ProjectId := Result.ProjectId;
    Hit.Field := FieldNamed(TextOf(Member(Passage, 'field'), 'field'));
    Hit.FileId := NumberOf(Passage, 'file_id').AsInt64;
    Hit.Snippet := TextOf(Member(Passage, 'snippet'), 'snippet');
    Hit.Score := NumberOf(Passage, 'score').AsDouble;
    Result.Passages[I] := Hit;
  end;
  Result.FileId := Result.Passages[0].FileId;
end;

function ParseIndex(const Obj: TJSONObject): TSemanticSearchStatus;
begin
  Result := Default(TSemanticSearchStatus);
  Result.State := ssIdle;
  Result.Phase := spIdle;
  Result.LastSyncComplete := BoolOf(Obj, 'complete');
  Result.IndexedPassages := NumberOf(Obj, 'indexed_passages').AsInt;
  Result.PendingPassages := NumberOf(Obj, 'pending_passages').AsInt;
  Result.FilesTotal := NumberOf(Obj, 'files_pending').AsInt;
  Result.FilesDone := 0;
end;

function IsVisible(const Visible: TArray<Integer>; ProjectId: Integer): Boolean;
var
  Id: Integer;
begin
  for Id in Visible do
    if Id = ProjectId then
      Exit(True);
  Result := False;
end;

function ParseSearchResponse(const Text: string; const Visible: TArray<Integer>;
  out Dropped: Integer): TSemanticSearchResult;
var
  Root: TJSONObject;
  Node: TJSONValue;
  Group: THybridGroup;
  Kept: TList<THybridGroup>;
begin
  Result := Default(TSemanticSearchResult);
  Dropped := 0;
  Root := nil;
  Kept := TList<THybridGroup>.Create;
  try
    try
      Root := ParseRoot(Text);
      for Node in ArrayOf(Root, 'groups') do
      begin
        Group := ParseGroup(ObjectOf(Node, 'groups'));
        if IsVisible(Visible, Group.ProjectId) then
          Kept.Add(Group)
        else
          Inc(Dropped);
      end;
      Result.Groups := Kept.ToArray;
      Result.Reranked := BoolOf(Root, 'reranked');
      Result.IndexStatus := ParseIndex(ObjectOf(Member(Root, 'index'), 'index'));
      Node := Root.GetValue('filters_applied');
      if (Node <> nil) and not (Node is TJSONNull) then
        Result.FiltersApplied := ObjectOf(Node, 'filters_applied').ToJSON;
    except
      on E: Exception do
        raise ESemanticSearchUnavailable.CreateFmt(SInvalidResponse, [E.Message]);
    end;
  finally
    Kept.Free;
    Root.Free;
  end;
end;

function ParseStatusResponse(const Text: string; out Reranker: Boolean): TSemanticSearchStatus;
var
  Root: TJSONObject;
begin
  Root := nil;
  try
    try
      Root := ParseRoot(Text);
      Result := ParseIndex(ObjectOf(Member(Root, 'index'), 'index'));
      Reranker := BoolOf(Root, 'reranker_available');
    except
      on E: Exception do
        raise ESemanticSearchUnavailable.CreateFmt(SInvalidResponse, [E.Message]);
    end;
  finally
    Root.Free;
  end;
end;

function ServerMessage(const Response: TRemoteHttpResponse): string;
var
  Value, Text: TJSONValue;
begin
  Result := '';
  Value := TJSONObject.ParseJSONValue(Response.Body);
  try
    if Value is TJSONObject then
    begin
      Text := TJSONObject(Value).GetValue('message');
      if (Text is TJSONString) and not (Text is TJSONNumber) then
        Result := Text.Value.Trim;
    end;
  finally
    Value.Free;
  end;
  if Result = '' then
    Result := Copy(Response.Body.Trim, 1, MaxMessageChars);
  if Result = '' then
    Result := Format(SNoMessage, [Response.StatusCode]);
end;

function StringsJson(const Names: TArray<string>): TJSONArray;
var
  Name: string;
begin
  Result := TJSONArray.Create;
  for Name in Names do
    Result.Add(Name);
end;

function FilterJson(const Filter: TSemanticSearchFilter): TJSONObject;
const
  DateFieldNames: array[TSemanticDateField] of string = ('', 'created', 'modified');
var
  Entries: TJSONArray;
  Entry: TJSONObject;
  Limit: TValueConstraint;
begin
  Result := TJSONObject.Create;
  try
    if Filter.FolderId > 0 then
      Result.AddPair('folder_id', TJSONNumber.Create(Filter.FolderId));
    if Length(Filter.ItemTypes) > 0 then
      Result.AddPair('item_types', StringsJson(Filter.ItemTypes));
    if Length(Filter.Levels) > 0 then
      Result.AddPair('levels', StringsJson(Filter.Levels));
    if Filter.ActionTypeId > 0 then
      Result.AddPair('action_type_id', TJSONNumber.Create(Filter.ActionTypeId));
    if Filter.DateField <> sdfNone then
    begin
      Result.AddPair('date_field', DateFieldNames[Filter.DateField]);
      if Filter.DateFrom > 0 then
        Result.AddPair('date_from', FormatDateTime('yyyy-mm-dd', Filter.DateFrom));
      if Filter.DateTo > 0 then
        Result.AddPair('date_to', FormatDateTime('yyyy-mm-dd', Filter.DateTo));
    end;
    if Length(Filter.Values) > 0 then
    begin
      Entries := TJSONArray.Create;
      Result.AddPair('values', Entries);
      for Limit in Filter.Values do
      begin
        Entry := TJSONObject.Create;
        Entries.AddElement(Entry);
        Entry.AddPair('value_type', Limit.ValueType);
        if Limit.HasMin then
          Entry.AddPair('min', TJSONNumber.Create(Limit.Min));
        if Limit.HasMax then
          Entry.AddPair('max', TJSONNumber.Create(Limit.Max));
        if Limit.UnitSymbol <> '' then
          Entry.AddPair('unit', Limit.UnitSymbol);
        if Limit.RecType <> '' then
          Entry.AddPair('rec_type', Limit.RecType);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function RequestBody(const Request: TSemanticSearchRequest): string;
var
  Body: TJSONObject;
  Ids: TJSONArray;
  Id: Integer;
begin
  Body := TJSONObject.Create;
  try
    Body.AddPair('query', Request.Query);
    Body.AddPair('top_k', TJSONNumber.Create(Request.TopK));
    Ids := TJSONArray.Create;
    Body.AddPair('project_ids', Ids);
    for Id in Request.VisibleProjectIds do
      Ids.Add(Id);
    Body.AddPair('filters', FilterJson(Request.Filter));
    Body.AddPair('rerank', TJSONBool.Create(Request.Rerank));
    Result := Body.ToJSON;
  finally
    Body.Free;
  end;
end;

{ TStatusRefresher }

constructor TStatusRefresher.Create(Owner: TRemoteSemanticSearch);
begin
  inherited Create(False);
  FOwner := Owner;
end;

procedure TStatusRefresher.Execute;
begin
  while not Terminated do
  begin
    FOwner.FWake.WaitFor(INFINITE);
    if not Terminated then
      FOwner.RefreshStatus;
  end;
end;

{ THttpSearchTransport }

function THttpSearchTransport.Send(const Method, Url, Token, Body: string;
  TimeoutMs: Integer): TRemoteHttpResponse;
var
  Client: THTTPClient;
  Request: IHTTPRequest;
  Response: IHTTPResponse;
  Source: TStringStream;
  Headers: TNetHeaders;
  Done: TEvent;
  Watchdog: TThread;
  Expired: Boolean;
begin
  Source := nil;
  Done := nil;
  Watchdog := nil;
  Expired := False;
  Client := THTTPClient.Create;
  try
    Client.HandleRedirects := False;
    Client.ConnectionTimeout := TimeoutMs;
    Client.SendTimeout := TimeoutMs;
    Client.ResponseTimeout := TimeoutMs;
    Request := Client.GetRequest(Method, Url);
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + Token),
      TNetHeader.Create('Accept', 'application/json')];
    if Method = 'POST' then
    begin
      Source := TStringStream.Create(Body, TEncoding.UTF8, False);
      Request.SourceStream := Source;
      Headers := Headers + [TNetHeader.Create('Content-Type', 'application/json; charset=utf-8')];
    end;
    if HttpDeadlineNeedsCancel then
    begin
      Done := TEvent.Create(nil, True, False, '');
      Watchdog := TThread.CreateAnonymousThread(
        procedure
        begin
          if Done.WaitFor(TimeoutMs) = wrTimeout then
          begin
            Expired := True;
            Request.Cancel;
          end;
        end);
      Watchdog.FreeOnTerminate := False;
      Watchdog.Start;
    end;
    try
      Response := Client.Execute(Request, nil, Headers);
    finally
      if Watchdog <> nil then
      begin
        Done.SetEvent;
        Watchdog.WaitFor;
      end;
    end;
    if Expired then
      raise Exception.Create(SDeadlinePassed);
    Result.StatusCode := Response.StatusCode;
    Result.Body := Response.ContentAsString(TEncoding.UTF8);
  finally
    Watchdog.Free;
    Done.Free;
    Response := nil;
    Request := nil;
    Client.Free;
    Source.Free;
  end;
end;

{ TRemoteSemanticSearch }

constructor TRemoteSemanticSearch.Create(const BaseUrl: string; const GetToken: TFunc<string>;
  TimeoutMs: Integer);
begin
  Create(BaseUrl, GetToken, TimeoutMs, THttpSearchTransport.Create, DefaultStatusIntervalMs);
end;

constructor TRemoteSemanticSearch.Create(const BaseUrl: string; const GetToken: TFunc<string>;
  TimeoutMs: Integer; const Transport: IRemoteSearchTransport; StatusIntervalMs: Integer);
var
  Url: string;
begin
  inherited Create;
  Url := BaseUrl.Trim;
  while Url.EndsWith('/') do
    Url := Url.Substring(0, Url.Length - 1);
  if not ((Url.StartsWith('http://', True) and (Url.Length > 7)) or
    (Url.StartsWith('https://', True) and (Url.Length > 8))) then
    raise EArgumentException.Create(SBadUrl);
  if not Assigned(GetToken) then
    raise EArgumentException.Create(SNoToken);
  if TimeoutMs <= 0 then
    raise EArgumentException.Create(SBadTimeout);
  if StatusIntervalMs <= 0 then
    raise EArgumentException.Create(SBadInterval);
  if Transport = nil then
    raise EArgumentException.Create(SNoTransport);
  FBaseUrl := Url;
  FGetToken := GetToken;
  FTimeoutMs := TimeoutMs;
  FIntervalMs := StatusIntervalMs;
  FTransport := Transport;
  FStatus := Default(TSemanticSearchStatus);
  FClock := TStopwatch.StartNew;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FRefresher := TStatusRefresher.Create(Self);
end;

destructor TRemoteSemanticSearch.Destroy;
begin
  if FRefresher <> nil then
  begin
    FRefresher.Terminate;
    FWake.SetEvent;
    FRefresher.WaitFor;
    FRefresher.Free;
  end;
  FWake.Free;
  FLock.Free;
  inherited;
end;

function TRemoteSemanticSearch.SendOnce(const Method, Url, Token, Body: string;
  TimeoutMs: Integer): TRemoteHttpResponse;
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  try
    Result := FTransport.Send(Method, Url, Token, Body, TimeoutMs);
  except
    on E: ENetHTTPCertificateException do
      raise ESemanticSearchUnavailable.CreateFmt(SNotTrusted, [FBaseUrl, E.Message]);
    on E: Exception do
      if Watch.ElapsedMilliseconds + TimeoutToleranceMs >= TimeoutMs then
        raise ESemanticSearchUnavailable.CreateFmt(STimedOut, [FBaseUrl, FTimeoutMs])
      else
        raise ESemanticSearchUnavailable.CreateFmt(SNotReachable, [FBaseUrl, E.Message]);
  end;
end;

function TRemoteSemanticSearch.Exchange(const Method, Path, Body: string): TRemoteHttpResponse;
var
  Url: string;
  Watch: TStopwatch;
  Remaining: Int64;
begin
  Url := FBaseUrl + Path;
  Watch := TStopwatch.StartNew;
  Result := SendOnce(Method, Url, FGetToken(), Body, FTimeoutMs);
  if Result.StatusCode = 401 then
  begin
    Remaining := FTimeoutMs - Watch.ElapsedMilliseconds;
    if Remaining <= 0 then
      raise ESemanticSearchUnavailable.CreateFmt(STimedOut, [FBaseUrl, FTimeoutMs]);
    Result := SendOnce(Method, Url, FGetToken(), Body, Remaining);
  end;
  case Result.StatusCode of
    200..299:
      ;
    400:
      raise ESemanticFilterError.Create(ServerMessage(Result));
    401:
      raise ESemanticSearchAccessDenied.CreateFmt(STokenRejected, [ServerMessage(Result)]);
    403:
      raise ESemanticSearchAccessDenied.CreateFmt(SRefused, [ServerMessage(Result)]);
    503:
      raise ESemanticSearchUnavailable.CreateFmt(SUnavailable, [ServerMessage(Result)]);
  else
    raise ESemanticSearchUnavailable.CreateFmt(SHttpError,
      [Result.StatusCode, ServerMessage(Result)]);
  end;
end;

function TRemoteSemanticSearch.Store(const Fresh: TSemanticSearchStatus;
  Dropped: Integer): TSemanticSearchStatus;
begin
  FLock.Enter;
  try
    Inc(FDropped, Dropped);
    Result := Fresh;
    Result.DroppedGroups := FDropped;
    FStatus := Result;
    FUpdated := True;
    FUpdatedAt := FClock.ElapsedMilliseconds;
  finally
    FLock.Leave;
  end;
end;

procedure TRemoteSemanticSearch.MarkFailed(const Text: string);
begin
  FLock.Enter;
  try
    FStatus.State := ssFailed;
    FStatus.LastError := Text;
    FUpdated := True;
    FUpdatedAt := FClock.ElapsedMilliseconds;
  finally
    FLock.Leave;
  end;
end;

function TRemoteSemanticSearch.RefreshDue: Boolean;
begin
  Result := not FRefreshing and
    (not FUpdated or (FClock.ElapsedMilliseconds - FUpdatedAt >= FIntervalMs));
  if Result then
    FRefreshing := True;
end;

procedure TRemoteSemanticSearch.RefreshStatus;
var
  Response: TRemoteHttpResponse;
  Fresh: TSemanticSearchStatus;
  Reranker: Boolean;
begin
  try
    Response := Exchange('GET', StatusPath, '');
    Fresh := ParseStatusResponse(Response.Body, Reranker);
    Store(Fresh, 0);
    FLock.Enter;
    try
      FReranker := Reranker;
    finally
      FLock.Leave;
    end;
  except
    on E: Exception do
      MarkFailed(E.Message);
  end;
  FLock.Enter;
  try
    FRefreshing := False;
  finally
    FLock.Leave;
  end;
end;

function TRemoteSemanticSearch.Search(const Request: TSemanticSearchRequest;
  const Cancelled: TCancelCheck): TSemanticSearchResult;
var
  Response: TRemoteHttpResponse;
  Dropped: Integer;
begin
  if Length(Request.VisibleProjectIds) = 0 then
  begin
    Result := Default(TSemanticSearchResult);
    FLock.Enter;
    try
      Result.IndexStatus := FStatus;
    finally
      FLock.Leave;
    end;
    Exit;
  end;
  try
    Response := Exchange('POST', SearchPath, RequestBody(Request));
    Result := ParseSearchResponse(Response.Body, Request.VisibleProjectIds, Dropped);
  except
    on E: ESemanticSearchUnavailable do
    begin
      MarkFailed(E.Message);
      raise;
    end;
  end;
  Result.IndexStatus := Store(Result.IndexStatus, Dropped);
end;

function TRemoteSemanticSearch.Status: TSemanticSearchStatus;
var
  Due: Boolean;
begin
  FLock.Enter;
  try
    Result := FStatus;
    Due := RefreshDue;
  finally
    FLock.Leave;
  end;
  if Due then
    FWake.SetEvent;
end;

function TRemoteSemanticSearch.RerankerAvailable: Boolean;
var
  Due: Boolean;
begin
  FLock.Enter;
  try
    Result := FReranker;
    Due := RefreshDue;
  finally
    FLock.Leave;
  end;
  if Due then
    FWake.SetEvent;
end;

function TRemoteSemanticSearch.IsRemote: Boolean;
begin
  Result := True;
end;

end.
