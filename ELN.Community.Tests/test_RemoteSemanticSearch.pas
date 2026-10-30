unit test_RemoteSemanticSearch;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  System.Diagnostics, System.JSON, DUnitX.TestFramework, unit_HybridSearch,
  unit_SearchPassages, unit_SemanticSearchApi, unit_RemoteSemanticSearch;

type
  TFakeCall = record
    Method, Url, Token, Body: string;
    TimeoutMs: Integer;
    ThreadId: TThreadID;
  end;

  TFakeHandler = reference to function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse;

  TFakeTransport = class(TInterfacedObject, IRemoteSearchTransport)
  private
    FLock: TCriticalSection;
    FCalls: TList<TFakeCall>;
  public
    Handler: TFakeHandler;
    constructor Create;
    destructor Destroy; override;
    function Send(const Method, Url, Token, Body: string;
      TimeoutMs: Integer): TRemoteHttpResponse;
    function Calls: TArray<TFakeCall>;
    function CallCount(const Method: string): Integer;
  end;

  [TestFixture]
  TRemoteSemanticSearchTests = class
  private
    FTransport: TFakeTransport;
    FTransportRef: IRemoteSearchTransport;
    FTokenCalls: Integer;
    function NextToken: string;
    function NewSearch(TimeoutMs: Integer = 2000; IntervalMs: Integer = 60000): ISemanticSearch;
    function Capture(const Search: ISemanticSearch; const Request: TSemanticSearchRequest;
      out Message: string; out ElapsedMs: Int64): ExceptClass;
    function WaitUntil(const Condition: TFunc<Boolean>; TimeoutMs: Integer): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HappyPathMapsEveryField;
    [Test]
    procedure RequestBodyCarriesTheQueryScopeAndEveryFilter;
    [Test]
    procedure EmptyFilterSendsAnEmptyFiltersObjectAndTheScope;
    [Test]
    procedure EmptyScopeSendsNoRequestAndReturnsNoGroups;
    [Test]
    procedure UnauthorizedRefreshesTheTokenOnceAndRetries;
    [Test]
    procedure SecondUnauthorizedIsAnAccessError;
    [Test]
    procedure ForbiddenIsAnAccessErrorWithTheServerMessage;
    [Test]
    procedure BadRequestIsAFilterErrorWithTheServerMessage;
    [Test]
    procedure ServiceUnavailableRaisesUnavailableWithinTheTimeout;
    [Test]
    procedure TimeoutRaisesUnavailableWithinTheTimeout;
    [Test]
    procedure RetryAfterUnauthorizedGetsOnlyTheRemainingTime;
    [Test]
    procedure InvalidResponseIsUnavailable;
    [Test]
    procedure GroupWithoutPassagesIsAnInvalidResponse;
    [Test]
    procedure GroupOutsideTheVisibleSetIsDropped;
    [Test]
    procedure UntrustedCertificateNamesTheServer;
    [Test]
    procedure InvalidArgumentsAreRejectedAtCreation;
    [Test]
    procedure StatusReturnsCachedStateWithoutWaiting;
    [Test]
    procedure StatusRefreshIsRateLimited;
    [Test]
    procedure SearchResponseRefreshesTheCachedStatus;
    [Test]
    procedure UnreachableStatusIsReportedAsFailed;
    [Test]
    procedure RealTransportTimesOutOnASilentServer;
  end;

implementation

uses
  System.DateUtils, System.Net.Socket, System.Net.HttpClient;

type
  ENothingRaised = class(Exception);

const
  BaseUrl = 'https://search.lab.test:8443/eln/';
  SearchUrl = 'https://search.lab.test:8443/eln/search/semantic';
  StatusUrl = 'https://search.lab.test:8443/eln/search/status';
  FullResponse =
    '{"groups":[' +
    '{"item_id":101,"project_id":3,"score":0.0325,"sources":["vector","trigram"],' +
    '"item_title":"not read by the client",' +
    '"passages":[{"field":"file_text","file_id":5000000001,' +
    '"snippet":"Ni/C period 2.5 nm \u2013 \u00e5ngstr\u00f6m","score":0.0325},' +
    '{"field":"title","file_id":0,"snippet":"Ni/C mirror","score":0.0161}]},' +
    '{"item_id":102,"project_id":5,"score":0.0161,"sources":["words"],' +
    '"passages":[{"field":"value_description","file_id":0,"snippet":"thickness","score":0.0161}]}],' +
    '"reranked":true,' +
    '"index":{"complete":false,"indexed_passages":481,"pending_passages":7,"files_pending":2},' +
    '"filters_applied":{"folder_id":12,"item_types":["Measurement"],' +
    '"values":[{"value_type":"Period","value_type_id":4,"unit":"nm","min":2,' +
    '"rec_type":"TEST_RESULT","requested_unit":"A"}]}}';
  EmptyResponse =
    '{"groups":[],"reranked":false,' +
    '"index":{"complete":true,"indexed_passages":10,"pending_passages":0,"files_pending":0}}';
  StatusResponse =
    '{"index":{"complete":true,"indexed_passages":11,"pending_passages":0,"files_pending":0},' +
    '"reranker_available":true}';

function Reply(StatusCode: Integer; const Body: string): TRemoteHttpResponse;
begin
  Result.StatusCode := StatusCode;
  Result.Body := Body;
end;

function GroupJson(ItemId, ProjectId: Integer): string;
begin
  Result := Format('{"item_id":%d,"project_id":%d,"score":0.5,"sources":["vector"],' +
    '"passages":[{"field":"title","file_id":0,"snippet":"s","score":0.5}]}', [ItemId, ProjectId]);
end;

function GroupsResponse(const Groups: array of string): string;
begin
  Result := '{"groups":[' + string.Join(',', Groups) + '],"reranked":false,' +
    '"index":{"complete":true,"indexed_passages":10,"pending_passages":0,"files_pending":0}}';
end;

function RequestFor(const Query: string; const Visible: TArray<Integer>): TSemanticSearchRequest;
begin
  Result := Default(TSemanticSearchRequest);
  Result.Query := Query;
  Result.VisibleProjectIds := Visible;
  Result.TopK := 10;
  Result.Rerank := True;
end;

function ParseObject(const Text: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(Text);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise Exception.Create('Not a JSON object: ' + Text);
  end;
  Result := TJSONObject(Value);
end;

function ProjectIdsOf(const Body: string): string;
var
  Value: TJSONObject;
  Ids: TJSONValue;
begin
  Value := ParseObject(Body);
  try
    Ids := Value.GetValue('project_ids');
    if Ids = nil then
      Exit('(missing)');
    Result := Ids.ToJSON;
  finally
    Value.Free;
  end;
end;

function Canonical(const Text: string): string;
var
  Value: TJSONObject;
begin
  Value := ParseObject(Text);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

{ TFakeTransport }

constructor TFakeTransport.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FCalls := TList<TFakeCall>.Create;
end;

destructor TFakeTransport.Destroy;
begin
  FCalls.Free;
  FLock.Free;
  inherited;
end;

function TFakeTransport.Send(const Method, Url, Token, Body: string;
  TimeoutMs: Integer): TRemoteHttpResponse;
var
  Call: TFakeCall;
  Index: Integer;
begin
  Call.Method := Method;
  Call.Url := Url;
  Call.Token := Token;
  Call.Body := Body;
  Call.TimeoutMs := TimeoutMs;
  Call.ThreadId := TThread.CurrentThread.ThreadID;
  FLock.Enter;
  try
    Index := FCalls.Count;
    FCalls.Add(Call);
  finally
    FLock.Leave;
  end;
  Result := Handler(Call, Index);
end;

function TFakeTransport.Calls: TArray<TFakeCall>;
begin
  FLock.Enter;
  try
    Result := FCalls.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TFakeTransport.CallCount(const Method: string): Integer;
var
  Call: TFakeCall;
begin
  Result := 0;
  for Call in Calls do
    if Call.Method = Method then
      Inc(Result);
end;

{ TRemoteSemanticSearchTests }

procedure TRemoteSemanticSearchTests.Setup;
begin
  FTransport := TFakeTransport.Create;
  FTransportRef := FTransport;
  FTokenCalls := 0;
end;

procedure TRemoteSemanticSearchTests.TearDown;
begin
  FTransportRef := nil;
  FTransport := nil;
end;

function TRemoteSemanticSearchTests.NextToken: string;
begin
  Inc(FTokenCalls);
  Result := 'tok-' + IntToStr(FTokenCalls);
end;

function TRemoteSemanticSearchTests.NewSearch(TimeoutMs, IntervalMs: Integer): ISemanticSearch;
begin
  Result := TRemoteSemanticSearch.Create(BaseUrl, NextToken, TimeoutMs, FTransportRef, IntervalMs);
end;

function TRemoteSemanticSearchTests.Capture(const Search: ISemanticSearch;
  const Request: TSemanticSearchRequest; out Message: string; out ElapsedMs: Int64): ExceptClass;
var
  Watch: TStopwatch;
begin
  Result := ENothingRaised;
  Message := '';
  Watch := TStopwatch.StartNew;
  try
    Search.Search(Request, nil);
  except
    on E: Exception do
    begin
      Result := ExceptClass(E.ClassType);
      Message := E.Message;
    end;
  end;
  ElapsedMs := Watch.ElapsedMilliseconds;
end;

function TRemoteSemanticSearchTests.WaitUntil(const Condition: TFunc<Boolean>;
  TimeoutMs: Integer): Boolean;
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  repeat
    if Condition() then
      Exit(True);
    Sleep(10);
  until Watch.ElapsedMilliseconds > TimeoutMs;
  Result := Condition();
end;

procedure TRemoteSemanticSearchTests.HappyPathMapsEveryField;
var
  Search: ISemanticSearch;
  Outcome: TSemanticSearchResult;
  Calls: TArray<TFakeCall>;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, FullResponse);
    end;
  Search := NewSearch;
  Assert.IsTrue(Search.IsRemote);
  Outcome := Search.Search(RequestFor('nickel carbon period', [3, 5]), nil);

  Calls := FTransport.Calls;
  Assert.AreEqual<NativeInt>(1, Length(Calls));
  Assert.AreEqual('POST', Calls[0].Method);
  Assert.AreEqual(SearchUrl, Calls[0].Url);
  Assert.AreEqual('tok-1', Calls[0].Token);
  Assert.AreEqual(2000, Calls[0].TimeoutMs);
  Assert.AreEqual(1, FTokenCalls);

  Assert.AreEqual<NativeInt>(2, Length(Outcome.Groups));
  Assert.AreEqual(101, Outcome.Groups[0].ItemId);
  Assert.AreEqual(3, Outcome.Groups[0].ProjectId);
  Assert.AreEqual(0.0325, Outcome.Groups[0].Score, 1e-12);
  Assert.IsTrue(Outcome.Groups[0].Sources = [hsVector, hsTrigram]);
  Assert.AreEqual(Int64(5000000001), Outcome.Groups[0].FileId);
  Assert.AreEqual<NativeInt>(2, Length(Outcome.Groups[0].Passages));
  Assert.IsTrue(Outcome.Groups[0].Passages[0].Field = pfFileText);
  Assert.AreEqual(Int64(5000000001), Outcome.Groups[0].Passages[0].FileId);
  Assert.AreEqual('Ni/C period 2.5 nm ' + #$2013 + ' ' + #$00E5 + 'ngstr' + #$00F6 + 'm',
    Outcome.Groups[0].Passages[0].Snippet);
  Assert.AreEqual(0.0325, Outcome.Groups[0].Passages[0].Score, 1e-12);
  Assert.AreEqual(101, Outcome.Groups[0].Passages[0].ItemId);
  Assert.AreEqual(3, Outcome.Groups[0].Passages[0].ProjectId);
  Assert.IsTrue(Outcome.Groups[0].Passages[1].Field = pfItemTitle);
  Assert.AreEqual('Ni/C mirror', Outcome.Groups[0].Passages[1].Snippet);
  Assert.AreEqual(102, Outcome.Groups[1].ItemId);
  Assert.AreEqual(5, Outcome.Groups[1].ProjectId);
  Assert.IsTrue(Outcome.Groups[1].Sources = [hsWords]);
  Assert.IsTrue(Outcome.Groups[1].Passages[0].Field = pfValueDescription);

  Assert.IsTrue(Outcome.Reranked);
  Assert.AreEqual(481, Outcome.IndexStatus.IndexedPassages);
  Assert.AreEqual(7, Outcome.IndexStatus.PendingPassages);
  Assert.AreEqual(2, Outcome.IndexStatus.FilesTotal);
  Assert.AreEqual(0, Outcome.IndexStatus.FilesDone);
  Assert.AreEqual(0, Outcome.IndexStatus.DroppedGroups);
  Assert.IsFalse(Outcome.IndexStatus.IsComplete);
  Assert.AreEqual(Ord(ssIdle), Ord(Outcome.IndexStatus.State));
  Assert.AreEqual(Canonical('{"folder_id":12,"item_types":["Measurement"],' +
    '"values":[{"value_type":"Period","value_type_id":4,"unit":"nm","min":2,' +
    '"rec_type":"TEST_RESULT","requested_unit":"A"}]}'), Canonical(Outcome.FiltersApplied));
end;

procedure TRemoteSemanticSearchTests.RequestBodyCarriesTheQueryScopeAndEveryFilter;
var
  Search: ISemanticSearch;
  Request: TSemanticSearchRequest;
  Body, Filters, Entry: TJSONObject;
  Values: TJSONArray;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, EmptyResponse);
    end;
  Request := RequestFor('reflectivity of Ni/C', [3, 5]);
  Request.TopK := 7;
  Request.Rerank := False;
  Request.Filter.FolderId := 12;
  Request.Filter.ItemTypes := ['Measurement', 'Testing'];
  Request.Filter.Levels := ['Proc'];
  Request.Filter.ActionTypeId := 4;
  Request.Filter.DateField := sdfModified;
  Request.Filter.DateFrom := EncodeDate(2026, 1, 31);
  Request.Filter.DateTo := EncodeDate(2026, 2, 28);
  SetLength(Request.Filter.Values, 2);
  Request.Filter.Values[0].ValueType := 'Period';
  Request.Filter.Values[0].HasMin := True;
  Request.Filter.Values[0].Min := 2;
  Request.Filter.Values[0].HasMax := True;
  Request.Filter.Values[0].Max := 3.5;
  Request.Filter.Values[0].UnitSymbol := 'nm';
  Request.Filter.Values[0].RecType := 'TEST_RESULT';
  Request.Filter.Values[1].ValueType := 'Density';
  Search := NewSearch;
  Search.Search(Request, nil);

  Body := ParseObject(FTransport.Calls[0].Body);
  try
    Assert.AreEqual('reflectivity of Ni/C', Body.GetValue<string>('query'));
    Assert.AreEqual(7, Body.GetValue<Integer>('top_k'));
    Assert.IsFalse(Body.GetValue<Boolean>('rerank'));
    Assert.AreEqual('[3,5]', Body.GetValue<TJSONArray>('project_ids').ToJSON);
    Filters := Body.GetValue<TJSONObject>('filters');
    Assert.AreEqual(12, Filters.GetValue<Integer>('folder_id'));
    Assert.AreEqual('["Measurement","Testing"]', Filters.GetValue<TJSONArray>('item_types').ToJSON);
    Assert.AreEqual('["Proc"]', Filters.GetValue<TJSONArray>('levels').ToJSON);
    Assert.AreEqual(4, Filters.GetValue<Integer>('action_type_id'));
    Assert.AreEqual('modified', Filters.GetValue<string>('date_field'));
    Assert.AreEqual('2026-01-31', Filters.GetValue<string>('date_from'));
    Assert.AreEqual('2026-02-28', Filters.GetValue<string>('date_to'));
    Values := Filters.GetValue<TJSONArray>('values');
    Assert.AreEqual(2, Values.Count);
    Entry := Values.Items[0] as TJSONObject;
    Assert.AreEqual('Period', Entry.GetValue<string>('value_type'));
    Assert.AreEqual(2.0, Entry.GetValue<Double>('min'), 1e-12);
    Assert.AreEqual(3.5, Entry.GetValue<Double>('max'), 1e-12);
    Assert.AreEqual('nm', Entry.GetValue<string>('unit'));
    Assert.AreEqual('TEST_RESULT', Entry.GetValue<string>('rec_type'));
    Entry := Values.Items[1] as TJSONObject;
    Assert.AreEqual('{"value_type":"Density"}', Entry.ToJSON);
  finally
    Body.Free;
  end;
end;

procedure TRemoteSemanticSearchTests.EmptyFilterSendsAnEmptyFiltersObjectAndTheScope;
var
  Search: ISemanticSearch;
  Outcome: TSemanticSearchResult;
  Body: TJSONObject;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, GroupsResponse([GroupJson(1, 7)]));
    end;
  Search := NewSearch;
  Outcome := Search.Search(RequestFor('anything', [7]), nil);
  Body := ParseObject(FTransport.Calls[0].Body);
  try
    Assert.AreEqual('[7]', Body.GetValue<TJSONArray>('project_ids').ToJSON);
    Assert.AreEqual('{}', Body.GetValue<TJSONObject>('filters').ToJSON);
  finally
    Body.Free;
  end;
  Assert.AreEqual<NativeInt>(1, Length(Outcome.Groups));
  Assert.AreEqual('', Outcome.FiltersApplied);
  Assert.AreEqual(0, Outcome.IndexStatus.DroppedGroups);
end;

procedure TRemoteSemanticSearchTests.EmptyScopeSendsNoRequestAndReturnsNoGroups;
var
  Search: ISemanticSearch;
  Request: TSemanticSearchRequest;
  Outcome: TSemanticSearchResult;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, GroupsResponse([GroupJson(1, 3), GroupJson(2, 9)]));
    end;
  Search := NewSearch;
  Request := RequestFor('anything', nil);
  Request.Filter.FolderId := 12;
  Outcome := Search.Search(Request, nil);
  Assert.AreEqual<NativeInt>(0, Length(FTransport.Calls), 'no request was sent');
  Assert.AreEqual(0, FTokenCalls, 'no token was asked for');
  Assert.AreEqual<NativeInt>(0, Length(Outcome.Groups));
  Assert.IsFalse(Outcome.Reranked);
  Assert.AreEqual('', Outcome.FiltersApplied);
  Assert.AreEqual(0, Outcome.IndexStatus.DroppedGroups);
end;

procedure TRemoteSemanticSearchTests.UnauthorizedRefreshesTheTokenOnceAndRetries;
var
  Search: ISemanticSearch;
  Outcome: TSemanticSearchResult;
  Calls: TArray<TFakeCall>;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      if Index = 0 then
        Result := Reply(401, '{"code":"unauthorized","message":"Token expired."}')
      else
        Result := Reply(200, GroupsResponse([GroupJson(1, 3)]));
    end;
  Search := NewSearch;
  Outcome := Search.Search(RequestFor('anything', [3]), nil);
  Calls := FTransport.Calls;
  Assert.AreEqual<NativeInt>(2, Length(Calls));
  Assert.AreEqual('tok-1', Calls[0].Token);
  Assert.AreEqual('tok-2', Calls[1].Token);
  Assert.AreEqual(Calls[0].Body, Calls[1].Body);
  Assert.AreEqual(2, FTokenCalls);
  Assert.AreEqual<NativeInt>(1, Length(Outcome.Groups));
end;

procedure TRemoteSemanticSearchTests.SecondUnauthorizedIsAnAccessError;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(401, '{"code":"unauthorized","message":"Token expired."}');
    end;
  Search := NewSearch;
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticSearchAccessDenied, 'class ' + Raised.ClassName);
  Assert.IsTrue(Message.Contains('Token expired.'), Message);
  Assert.AreEqual<NativeInt>(2, Length(FTransport.Calls));
  Assert.AreEqual(2, FTokenCalls);
end;

procedure TRemoteSemanticSearchTests.ForbiddenIsAnAccessErrorWithTheServerMessage;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(403, '{"code":"forbidden","message":"This device may not search."}');
    end;
  Search := NewSearch;
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticSearchAccessDenied, 'class ' + Raised.ClassName);
  Assert.IsTrue(Message.Contains('refused access'), Message);
  Assert.IsTrue(Message.Contains('This device may not search.'), Message);
  Assert.AreEqual<NativeInt>(1, Length(FTransport.Calls));
  Assert.AreEqual(1, FTokenCalls);
  Assert.AreEqual(Ord(ssIdle), Ord(Search.Status.State), 'access errors do not mark the server failed');
end;

procedure TRemoteSemanticSearchTests.BadRequestIsAFilterErrorWithTheServerMessage;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(400, '{"code":"invalid_filter","message":"Unit \"furlong\" is not known."}');
    end;
  Search := NewSearch;
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticFilterError, 'class ' + Raised.ClassName);
  Assert.AreEqual('Unit "furlong" is not known.', Message);
end;

procedure TRemoteSemanticSearchTests.ServiceUnavailableRaisesUnavailableWithinTheTimeout;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
  Status: TSemanticSearchStatus;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(503, '{"code":"unavailable","message":"The index is loading."}');
    end;
  Search := NewSearch(800);
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticSearchUnavailable, 'class ' + Raised.ClassName);
  Assert.IsTrue(Message.Contains('The index is loading.'), Message);
  Assert.IsTrue(Elapsed < 800 + 1000, 'raised after ' + IntToStr(Elapsed) + ' ms');
  Status := Search.Status;
  Assert.AreEqual(Ord(ssFailed), Ord(Status.State));
  Assert.IsTrue(Status.LastError.Contains('The index is loading.'), Status.LastError);
end;

procedure TRemoteSemanticSearchTests.TimeoutRaisesUnavailableWithinTheTimeout;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Sleep(Call.TimeoutMs);
      raise Exception.Create('The operation timed out (fake).');
    end;
  Search := NewSearch(800);
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticSearchUnavailable, 'class ' + Raised.ClassName);
  Assert.AreEqual(800, FTransport.Calls[0].TimeoutMs);
  Assert.IsTrue(Message.Contains('800 ms'), Message);
  Assert.IsTrue(Elapsed < 800 + 1000, 'raised after ' + IntToStr(Elapsed) + ' ms');
end;

procedure TRemoteSemanticSearchTests.RetryAfterUnauthorizedGetsOnlyTheRemainingTime;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
  Calls: TArray<TFakeCall>;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      if Index = 0 then
      begin
        Sleep(500);
        Exit(Reply(401, '{"code":"unauthorized","message":"Token expired."}'));
      end;
      Sleep(Call.TimeoutMs);
      raise Exception.Create('The operation timed out (fake).');
    end;
  Search := NewSearch(800);
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Calls := FTransport.Calls;
  Assert.IsTrue(Raised = ESemanticSearchUnavailable, 'class ' + Raised.ClassName);
  Assert.AreEqual<NativeInt>(2, Length(Calls));
  Assert.IsTrue((Calls[1].TimeoutMs > 0) and (Calls[1].TimeoutMs <= 300),
    'retry timeout ' + IntToStr(Calls[1].TimeoutMs));
  Assert.IsTrue(Elapsed < 800 + 1000, 'raised after ' + IntToStr(Elapsed) + ' ms');
end;

procedure TRemoteSemanticSearchTests.InvalidResponseIsUnavailable;
const
  Bodies: array[0..4] of string = (
    'not json',
    '[1,2]',
    '{"groups":[],"index":{"complete":true,"indexed_passages":1,"pending_passages":0,"files_pending":0}}',
    '{"groups":[{"item_id":1,"project_id":3,"score":0.5,"sources":["vector"],' +
      '"passages":[{"field":"abstract","file_id":0,"snippet":"s","score":0.5}]}],"reranked":false,' +
      '"index":{"complete":true,"indexed_passages":1,"pending_passages":0,"files_pending":0}}',
    '{"groups":[],"reranked":false,"filters_applied":"folder 12",' +
      '"index":{"complete":true,"indexed_passages":1,"pending_passages":0,"files_pending":0}}');
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
  Current: string;
  Body: string;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, Current);
    end;
  Search := NewSearch;
  for Body in Bodies do
  begin
    Current := Body;
    Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
    Assert.IsTrue(Raised = ESemanticSearchUnavailable, Body);
    Assert.IsTrue(Message.Contains('invalid response'), Message);
  end;
end;

procedure TRemoteSemanticSearchTests.GroupWithoutPassagesIsAnInvalidResponse;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, GroupsResponse(
        ['{"item_id":1,"project_id":3,"score":0.5,"sources":["vector"],"passages":[]}']));
    end;
  Search := NewSearch;
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticSearchUnavailable, 'class ' + Raised.ClassName);
  Assert.IsTrue(Message.Contains('invalid response'), Message);
end;

procedure TRemoteSemanticSearchTests.GroupOutsideTheVisibleSetIsDropped;
var
  Search: ISemanticSearch;
  Outcome: TSemanticSearchResult;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      if Index = 0 then
        Result := Reply(200, GroupsResponse([GroupJson(1, 3), GroupJson(2, 9), GroupJson(3, 3)]))
      else
        Result := Reply(200, GroupsResponse([GroupJson(4, 7), GroupJson(5, 8)]));
    end;
  Search := NewSearch;
  Outcome := Search.Search(RequestFor('anything', [3, 5]), nil);
  Assert.AreEqual('[3,5]', ProjectIdsOf(FTransport.Calls[0].Body), 'the scope is always sent');
  Assert.AreEqual<NativeInt>(2, Length(Outcome.Groups));
  Assert.AreEqual(1, Outcome.Groups[0].ItemId);
  Assert.AreEqual(3, Outcome.Groups[1].ItemId);
  Assert.AreEqual(1, Outcome.IndexStatus.DroppedGroups);
  Assert.AreEqual(1, Search.Status.DroppedGroups);

  Outcome := Search.Search(RequestFor('anything', [3, 5]), nil);
  Assert.AreEqual<NativeInt>(0, Length(Outcome.Groups));
  Assert.AreEqual(3, Outcome.IndexStatus.DroppedGroups);
  Assert.AreEqual(3, Search.Status.DroppedGroups);
end;

procedure TRemoteSemanticSearchTests.UntrustedCertificateNamesTheServer;
var
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      raise ENetHTTPCertificateException.Create('Server Certificate Invalid or not present');
    end;
  Search := NewSearch;
  Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
  Assert.IsTrue(Raised = ESemanticSearchUnavailable, 'class ' + Raised.ClassName);
  Assert.IsTrue(Message.Contains('https://search.lab.test:8443/eln'), Message);
  Assert.IsTrue(Message.Contains('not trusted'), Message);
  Assert.IsTrue(Message.Contains('trust store'), Message);
  Assert.AreEqual(Ord(ssFailed), Ord(Search.Status.State));
end;

procedure TRemoteSemanticSearchTests.InvalidArgumentsAreRejectedAtCreation;

  function Refused(const Url: string; const GetToken: TFunc<string>;
    TimeoutMs: Integer): Boolean;
  var
    Search: ISemanticSearch;
  begin
    try
      Search := TRemoteSemanticSearch.Create(Url, GetToken, TimeoutMs, FTransportRef, 1000);
      Result := False;
    except
      on E: Exception do
        Result := E.ClassType = EArgumentException;
    end;
  end;

begin
  Assert.IsFalse(Refused(BaseUrl, NextToken, 1000), 'valid arguments');
  Assert.IsTrue(Refused('ftp://search.lab.test', NextToken, 1000), 'scheme');
  Assert.IsTrue(Refused('https://', NextToken, 1000), 'no host');
  Assert.IsTrue(Refused(BaseUrl, nil, 1000), 'no token callback');
  Assert.IsTrue(Refused(BaseUrl, NextToken, 0), 'timeout');
end;

procedure TRemoteSemanticSearchTests.StatusReturnsCachedStateWithoutWaiting;
var
  Search: ISemanticSearch;
  Release: TEvent;
  Watch: TStopwatch;
  Status: TSemanticSearchStatus;
  Available: Boolean;
  Calls: TArray<TFakeCall>;
begin
  Release := TEvent.Create(nil, True, False, '');
  try
    FTransport.Handler :=
      function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
      begin
        Release.WaitFor(10000);
        Result := Reply(200, StatusResponse);
      end;
    Search := NewSearch;
    try
      Search.Status;
      Assert.IsTrue(WaitUntil(
        function: Boolean
        begin
          Result := FTransport.CallCount('GET') = 1;
        end, 5000), 'the status refresh started');
      Watch := TStopwatch.StartNew;
      Status := Search.Status;
      Available := Search.RerankerAvailable;
      Assert.IsTrue(Watch.ElapsedMilliseconds < 1000,
        'returned after ' + IntToStr(Watch.ElapsedMilliseconds) + ' ms');
      Assert.AreEqual(0, Status.IndexedPassages);
      Assert.IsFalse(Available);
      Calls := FTransport.Calls;
      Assert.AreEqual(StatusUrl, Calls[0].Url);
      Assert.AreEqual('tok-1', Calls[0].Token);
      Assert.IsTrue(TThread.CurrentThread.ThreadID <> Calls[0].ThreadId, 'refreshed off the caller thread');
      Release.SetEvent;
      Assert.IsTrue(WaitUntil(
        function: Boolean
        begin
          Result := Search.Status.IndexedPassages = 11;
        end, 5000), 'the cache took the server status');
      Assert.IsTrue(Search.Status.IsComplete);
      Assert.IsTrue(Search.RerankerAvailable);
      Assert.AreEqual(1, FTransport.CallCount('GET'));
    finally
      Release.SetEvent;
      Search := nil;
    end;
  finally
    Release.Free;
  end;
end;

procedure TRemoteSemanticSearchTests.StatusRefreshIsRateLimited;
var
  Search: ISemanticSearch;
  I: Integer;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      Result := Reply(200, StatusResponse);
    end;
  Search := NewSearch(2000, 1500);
  Search.Status;
  Assert.IsTrue(WaitUntil(
    function: Boolean
    begin
      Result := Search.Status.IndexedPassages = 11;
    end, 5000));
  for I := 1 to 20 do
  begin
    Search.Status;
    Search.RerankerAvailable;
    Sleep(10);
  end;
  Sleep(100);
  Assert.AreEqual(1, FTransport.CallCount('GET'), 'one refresh inside the interval');
  Sleep(1600);
  Search.Status;
  Assert.IsTrue(WaitUntil(
    function: Boolean
    begin
      Result := FTransport.CallCount('GET') = 2;
    end, 5000), 'a refresh after the interval');
  Sleep(100);
  Assert.AreEqual(2, FTransport.CallCount('GET'));
end;

procedure TRemoteSemanticSearchTests.SearchResponseRefreshesTheCachedStatus;
var
  Search: ISemanticSearch;
  Status: TSemanticSearchStatus;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      if Call.Method = 'GET' then
        Result := Reply(200, StatusResponse)
      else
        Result := Reply(200, FullResponse);
    end;
  Search := NewSearch;
  Search.Search(RequestFor('anything', [3, 5]), nil);
  Status := Search.Status;
  Sleep(200);
  Assert.AreEqual(0, FTransport.CallCount('GET'), 'the search response is fresh');
  Assert.AreEqual(481, Status.IndexedPassages);
  Assert.AreEqual(7, Status.PendingPassages);
  Assert.AreEqual(2, Status.FilesTotal);
end;

procedure TRemoteSemanticSearchTests.UnreachableStatusIsReportedAsFailed;
var
  Search: ISemanticSearch;
begin
  FTransport.Handler :=
    function(const Call: TFakeCall; Index: Integer): TRemoteHttpResponse
    begin
      raise Exception.Create('Connection refused (fake).');
    end;
  Search := NewSearch;
  Search.Status;
  Assert.IsTrue(WaitUntil(
    function: Boolean
    begin
      Result := Search.Status.State = ssFailed;
    end, 5000));
  Assert.IsTrue(Search.Status.LastError.Contains('Connection refused (fake).'),
    Search.Status.LastError);
  Assert.IsFalse(Search.RerankerAvailable);
end;

procedure TRemoteSemanticSearchTests.RealTransportTimesOutOnASilentServer;
var
  Listener: TSocket;
  Search: ISemanticSearch;
  Raised: ExceptClass;
  Message: string;
  Elapsed: Int64;
begin
  Listener := TSocket.Create(TSocketType.TCP);
  try
    Listener.Listen('127.0.0.1', '', 0);
    Search := TRemoteSemanticSearch.Create(Format('http://127.0.0.1:%d', [Listener.LocalPort]),
      NextToken, 1000);
    Raised := Capture(Search, RequestFor('anything', [3]), Message, Elapsed);
    Search := nil;
  finally
    Listener.Close(True);
    Listener.Free;
  end;
  Assert.IsTrue(Raised = ESemanticSearchUnavailable, 'class ' + Raised.ClassName + ': ' + Message);
  Assert.IsTrue(Message.Contains('1000 ms'), Message);
  Assert.IsTrue((Elapsed >= 900) and (Elapsed < 1000 + 1000),
    'raised after ' + IntToStr(Elapsed) + ' ms: ' + Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TRemoteSemanticSearchTests);

end.
