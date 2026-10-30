unit test_SearchDoubles;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, unit_SearchPassages,
  unit_TextEmbedder, unit_TextExtractors, unit_CrossEncoder, unit_HybridSearch,
  unit_SemanticSearchApi, Aurelius.Engine.ObjectManager, Aurelius.Criteria.Base, unit_User,
  unit_Project, unit_Hypothesis, unit_ProjectAccessPolicy;

const
  StoreDim = 8;

type
  TCountingExtractor = class(TInterfacedObject, ITextExtractor)
  private
    FVersion: Integer;
  public
    Calls: Integer;
    DelayMs: Cardinal;
    Unavailable: Boolean;
    RaiseOnce: Boolean;
    OnCall: TProc<Integer>;
    constructor Create;
    function Id: string;
    function Version: Integer;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
    property CurrentVersion: Integer read FVersion write FVersion;
  end;

  TMemoryFileReader = class(TInterfacedObject, IFileContentReader)
  private
    FFiles: TDictionary<string, TBytes>;
    FSizes: TDictionary<string, Int64>;
    FWrites: TDictionary<string, Int64>;
    FUnreadable: TDictionary<string, Boolean>;
    FClock: Int64;
    FReads: Integer;
    FReadDelayMs: Cardinal;
    FNoStamps: Boolean;
    procedure Touch(const Path: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const Path: string; const Bytes: TBytes);
    procedure PutSize(const Path: string; Size: Int64);
    procedure MakeUnreadable(const Path: string);
    function ReadFile(const RelativePath: string; MaxBytes: Int64; out Bytes: TBytes;
      out Size: Int64): Boolean;
    function TryGetStamp(const RelativePath: string; out Size, LastWrite: Int64): Boolean;
    property Reads: Integer read FReads;
    property ReadDelayMs: Cardinal read FReadDelayMs write FReadDelayMs;
    property NoStamps: Boolean read FNoStamps write FNoStamps;
  end;

  TFakeCrossEncoder = class(TInterfacedObject, ICrossEncoder)
  public
    Calls: Integer;
    Inputs: TArray<string>;
    Queries: TArray<string>;
    DelayMs: Cardinal;
    IgnoreCancel: Boolean;
    Ascending: Boolean;
    OnScore: TProc;
    constructor Create;
    function Score(const Query: string; const Passages: TArray<string>;
      const Cancelled: TCancelCheck): TArray<Single>;
    function Identity: string;
  end;

  TUnrestrictedPolicy = class(TInterfacedObject, IProjectAccessPolicy)
  private
    FInner: IProjectAccessPolicy;
    FReturnNil: Boolean;
  public
    constructor Create(const AInner: IProjectAccessPolicy; AReturnNil: Boolean);
    function CheckWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectWriteVerdict;
    function CanWrite(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function CanRead(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): Boolean;
    function RemoveProject(AManager: TObjectManager; AUser: TUser;
      AProject: TProject): Boolean;
    function CanPassGate(AManager: TObjectManager; AUser: TUser;
      AHypothesis: THypothesis; AGate: THypothesisGate;
      out AReason: string): Boolean;
    function CreateGateEligibility(AManager: TObjectManager;
      AUser: TUser): TGateEligibility;
    function ProjectList(AManager: TObjectManager; AUser: TUser): TList<TProject>;
    function GetProjectAccess(AManager: TObjectManager; AUser: TUser;
      AProjectId: Integer): TProjectAccess;
    function ProjectDataSetCriteria(AManager: TObjectManager;
      AUser: TUser): TCriteria<TProject>;
    function VisibleProjectIds(AManager: TObjectManager;
      AUser: TUser): TDictionary<Integer, Boolean>;
    function CanReviewProtocol(AManager: TObjectManager; AUser: TUser;
      AProjectId, AAuthorId: Integer): Boolean;
    function CanBrowseAllProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateProjects(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanCreateTags(AManager: TObjectManager; AUser: TUser): Boolean;
    function CanEditReferenceData(AManager: TObjectManager; AUser: TUser): Boolean;
  end;

  TFakeEmbedder = class(TInterfacedObject, ITextEmbedder)
  private
    FIdentity: string;
    FEncoded: Integer;
    FMaxQueryChars: Integer;
    FBatchDelayMs: Cardinal;
    function Embed(const Text: string): TEmbedding;
  public
    constructor Create(const Identity: string);
    function Identity: string;
    function Dimension: Integer;
    function MaxTokens: Integer;
    function EncodeQuery(const Text: string): TEmbedding;
    function EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
      const Cancelled: TCancelCheck = nil): TArray<TEmbedding>;
    property Encoded: Integer read FEncoded write FEncoded;
    property MaxQueryChars: Integer read FMaxQueryChars write FMaxQueryChars;
    property BatchDelayMs: Cardinal read FBatchDelayMs write FBatchDelayMs;
  end;

  TFakeSemanticSearch = class(TInterfacedObject, ISemanticSearch)
  public
    Remote: Boolean;
    Reranker: Boolean;
    Outcome: TSemanticSearchResult;
    Current: TSemanticSearchStatus;
    Failure: string;
    DelayMs: Cardinal;
    Requests: TArray<TSemanticSearchRequest>;
    SearchThreads: TArray<TThreadID>;
    Finished: Integer;
    function Search(const Request: TSemanticSearchRequest;
      const Cancelled: TCancelCheck): TSemanticSearchResult;
    function Status: TSemanticSearchStatus;
    function RerankerAvailable: Boolean;
    function IsRemote: Boolean;
  end;

function SnapshotOf(const Passages: TSearchPassages): TSearchSnapshot;
function FakeGroup(ItemId, ProjectId: Integer; const Snippet: string): THybridGroup;

implementation

uses
  System.Hash, System.SyncObjs;

constructor TCountingExtractor.Create;
begin
  inherited Create;
  FVersion := 1;
end;

function TCountingExtractor.Id: string;
begin
  Result := 'dbl';
end;

function TCountingExtractor.Version: Integer;
begin
  Result := FVersion;
end;

function TCountingExtractor.Extract(const Bytes: TBytes;
  const Cancelled: TCancelCheck): TExtractResult;
var
  Text: string;
begin
  Inc(Calls);
  if Assigned(OnCall) then
    OnCall(Calls);
  if DelayMs > 0 then
    Sleep(DelayMs);
  if RaiseOnce then
  begin
    RaiseOnce := False;
    raise EOutOfMemory.Create('simulated');
  end;
  if Unavailable then
    Exit(MakeExtractResult(eoExtractorUnavailable, '', 'not installed'));
  Text := TEncoding.UTF8.GetString(Bytes);
  if Text.StartsWith('LIMIT') then
    Result := MakeExtractResult(eoLimitReached, Text, 'text limit reached')
  else if Text.StartsWith('BAD') then
    Result := MakeExtractResult(eoCorrupt, '', 'bad content')
  else
    Result := MakeExtractResult(eoText, Text);
end;

constructor TMemoryFileReader.Create;
begin
  inherited Create;
  FFiles := TDictionary<string, TBytes>.Create;
  FSizes := TDictionary<string, Int64>.Create;
  FWrites := TDictionary<string, Int64>.Create;
  FUnreadable := TDictionary<string, Boolean>.Create;
end;

destructor TMemoryFileReader.Destroy;
begin
  FUnreadable.Free;
  FWrites.Free;
  FSizes.Free;
  FFiles.Free;
  inherited;
end;

procedure TMemoryFileReader.Touch(const Path: string);
begin
  Inc(FClock);
  FWrites.AddOrSetValue(Path, FClock);
end;

procedure TMemoryFileReader.Put(const Path: string; const Bytes: TBytes);
begin
  FFiles.AddOrSetValue(Path, Bytes);
  Touch(Path);
end;

procedure TMemoryFileReader.PutSize(const Path: string; Size: Int64);
begin
  FSizes.AddOrSetValue(Path, Size);
  Touch(Path);
end;

procedure TMemoryFileReader.MakeUnreadable(const Path: string);
begin
  FUnreadable.AddOrSetValue(Path, True);
end;

function TMemoryFileReader.ReadFile(const RelativePath: string; MaxBytes: Int64;
  out Bytes: TBytes; out Size: Int64): Boolean;
begin
  Inc(FReads);
  if FReadDelayMs > 0 then
    Sleep(FReadDelayMs);
  Bytes := nil;
  Size := 0;
  if FUnreadable.ContainsKey(RelativePath) then
    raise EInOutError.Create('file is locked');
  if FSizes.TryGetValue(RelativePath, Size) then
    Exit(True);
  Result := FFiles.TryGetValue(RelativePath, Bytes);
  if Result then
  begin
    Size := Length(Bytes);
    if Size > MaxBytes then
      Bytes := nil;
  end;
end;

function TMemoryFileReader.TryGetStamp(const RelativePath: string;
  out Size, LastWrite: Int64): Boolean;
var
  Bytes: TBytes;
begin
  Size := 0;
  LastWrite := 0;
  Result := False;
  if FNoStamps then
    Exit;
  if FSizes.TryGetValue(RelativePath, Size) then
    Result := True
  else if FFiles.TryGetValue(RelativePath, Bytes) then
  begin
    Size := Length(Bytes);
    Result := True;
  end;
  if Result then
    FWrites.TryGetValue(RelativePath, LastWrite);
end;

constructor TFakeCrossEncoder.Create;
begin
  inherited Create;
  Ascending := True;
end;

function TFakeCrossEncoder.Identity: string;
begin
  Result := 'fake-cross-encoder';
end;

function TFakeCrossEncoder.Score(const Query: string; const Passages: TArray<string>;
  const Cancelled: TCancelCheck): TArray<Single>;
var
  Waited: Cardinal;
  I: Integer;
begin
  Inc(Calls);
  Inputs := Passages;
  Queries := Queries + [Query];
  if Assigned(OnScore) then
    OnScore();
  Waited := 0;
  while Waited < DelayMs do
  begin
    Sleep(10);
    Inc(Waited, 10);
    if not IgnoreCancel and Assigned(Cancelled) and Cancelled() then
      raise EOperationCancelled.Create('cancelled');
  end;
  SetLength(Result, Length(Passages));
  for I := 0 to High(Passages) do
    if Ascending then
      Result[I] := I
    else
      Result[I] := -I;
end;

function TUnrestrictedPolicy.CheckWrite(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): TProjectWriteVerdict;
begin
  Result := FInner.CheckWrite(AManager, AUser, AProjectId);
end;

function TUnrestrictedPolicy.CanWrite(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): Boolean;
begin
  Result := FInner.CanWrite(AManager, AUser, AProjectId);
end;

function TUnrestrictedPolicy.CanRead(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): Boolean;
begin
  Result := FInner.CanRead(AManager, AUser, AProjectId);
end;

function TUnrestrictedPolicy.RemoveProject(AManager: TObjectManager; AUser: TUser;
  AProject: TProject): Boolean;
begin
  Result := FInner.RemoveProject(AManager, AUser, AProject);
end;

function TUnrestrictedPolicy.CanPassGate(AManager: TObjectManager; AUser: TUser;
  AHypothesis: THypothesis; AGate: THypothesisGate; out AReason: string): Boolean;
begin
  Result := FInner.CanPassGate(AManager, AUser, AHypothesis, AGate, AReason);
end;

function TUnrestrictedPolicy.CreateGateEligibility(AManager: TObjectManager;
  AUser: TUser): TGateEligibility;
begin
  Result := FInner.CreateGateEligibility(AManager, AUser);
end;

function TUnrestrictedPolicy.ProjectList(AManager: TObjectManager;
  AUser: TUser): TList<TProject>;
begin
  Result := FInner.ProjectList(AManager, AUser);
end;

function TUnrestrictedPolicy.GetProjectAccess(AManager: TObjectManager; AUser: TUser;
  AProjectId: Integer): TProjectAccess;
begin
  Result := FInner.GetProjectAccess(AManager, AUser, AProjectId);
end;

function TUnrestrictedPolicy.ProjectDataSetCriteria(AManager: TObjectManager;
  AUser: TUser): TCriteria<TProject>;
begin
  Result := FInner.ProjectDataSetCriteria(AManager, AUser);
end;

function TUnrestrictedPolicy.VisibleProjectIds(AManager: TObjectManager;
  AUser: TUser): TDictionary<Integer, Boolean>;
begin
  if FReturnNil then
    Result := nil
  else
    Result := TDictionary<Integer, Boolean>.Create;
end;

function TUnrestrictedPolicy.CanReviewProtocol(AManager: TObjectManager; AUser: TUser;
  AProjectId, AAuthorId: Integer): Boolean;
begin
  Result := FInner.CanReviewProtocol(AManager, AUser, AProjectId, AAuthorId);
end;

function TUnrestrictedPolicy.CanBrowseAllProjects(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanBrowseAllProjects(AManager, AUser);
end;

function TUnrestrictedPolicy.CanCreateProjects(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanCreateProjects(AManager, AUser);
end;

function TUnrestrictedPolicy.CanCreateTags(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanCreateTags(AManager, AUser);
end;

function TUnrestrictedPolicy.CanEditReferenceData(AManager: TObjectManager;
  AUser: TUser): Boolean;
begin
  Result := FInner.CanEditReferenceData(AManager, AUser);
end;

constructor TUnrestrictedPolicy.Create(const AInner: IProjectAccessPolicy;
  AReturnNil: Boolean);
begin
  inherited Create;
  FInner := AInner;
  FReturnNil := AReturnNil;
end;

constructor TFakeEmbedder.Create(const Identity: string);
begin
  inherited Create;
  FIdentity := Identity;
end;

function TFakeEmbedder.Identity: string;
begin
  Result := FIdentity;
end;

function TFakeEmbedder.Dimension: Integer;
begin
  Result := StoreDim;
end;

function TFakeEmbedder.MaxTokens: Integer;
begin
  Result := E5MaxTokens;
end;

function TFakeEmbedder.Embed(const Text: string): TEmbedding;
var
  Bytes: TBytes;
  I: Integer;
  Norm: Double;
begin
  Bytes := THashSHA2.GetHashBytes(Text);
  SetLength(Result.Vector, StoreDim);
  Norm := 0;
  for I := 0 to StoreDim - 1 do
  begin
    Result.Vector[I] := Bytes[I] - 127.5;
    Norm := Norm + Sqr(Double(Result.Vector[I]));
  end;
  Norm := Sqrt(Norm);
  for I := 0 to StoreDim - 1 do
    Result.Vector[I] := Result.Vector[I] / Norm;
  Result.TokenCount := 1;
  Result.SourceTokenCount := 1;
  Result.Truncated := False;
end;

function TFakeEmbedder.EncodeQuery(const Text: string): TEmbedding;
begin
  if (FMaxQueryChars > 0) and (Length(Text) > FMaxQueryChars) then
    raise ETextTooLong.Create('query too long');
  Result := Embed(Text);
end;

function TFakeEmbedder.EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
  const Cancelled: TCancelCheck): TArray<TEmbedding>;
var
  I: Integer;
begin
  if FBatchDelayMs > 0 then
    Sleep(FBatchDelayMs);
  SetLength(Result, Length(Texts));
  for I := 0 to High(Texts) do
    Result[I] := Embed(Texts[I]);
  Inc(FEncoded, Length(Texts));
end;

function SnapshotOf(const Passages: TSearchPassages): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
  Result.Passages := Passages;
end;

function TFakeSemanticSearch.Search(const Request: TSemanticSearchRequest;
  const Cancelled: TCancelCheck): TSemanticSearchResult;
begin
  Requests := Requests + [Request];
  SearchThreads := SearchThreads + [TThread.CurrentThread.ThreadID];
  try
    if DelayMs > 0 then
      Sleep(DelayMs);
    if Failure <> '' then
      raise ESemanticSearchUnavailable.Create(Failure);
    Result := Outcome;
  finally
    TInterlocked.Increment(Finished);
  end;
end;

function TFakeSemanticSearch.Status: TSemanticSearchStatus;
begin
  Result := Current;
end;

function TFakeSemanticSearch.RerankerAvailable: Boolean;
begin
  Result := Reranker;
end;

function TFakeSemanticSearch.IsRemote: Boolean;
begin
  Result := Remote;
end;

function FakeGroup(ItemId, ProjectId: Integer; const Snippet: string): THybridGroup;
var
  Hit: THybridHit;
begin
  Hit := Default(THybridHit);
  Hit.Key := 'fake-' + IntToStr(ItemId);
  Hit.ItemId := ItemId;
  Hit.ProjectId := ProjectId;
  Hit.Field := pfItemDescription;
  Hit.Score := 0.5;
  Hit.Sources := [hsVector, hsWords];
  Hit.Snippet := Snippet;
  Result := Default(THybridGroup);
  Result.ItemId := ItemId;
  Result.ProjectId := ProjectId;
  Result.Score := 0.5;
  Result.Sources := Hit.Sources;
  Result.Passages := [Hit];
end;

end.
