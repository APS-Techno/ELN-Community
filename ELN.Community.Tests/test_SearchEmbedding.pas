unit test_SearchEmbedding;

interface

uses
  System.SysUtils, System.JSON, DUnitX.TestFramework,
  unit_UnigramTokenizer, unit_TextEmbedder, unit_VectorSearch, unit_SearchArtifacts, unit_CrossEncoder;

type
  [TestFixture]
  TTokenizerParityTests = class
  private
    FTokenizer: TUnigramTokenizer;
    FReference: TJSONObject;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Test]
    procedure TokenIdsMatchReferenceCases;
    [Test]
    procedure SpecialTokenIdsFollowTemplate;
    [Test]
    procedure PaddedBatchMatchesReference;
    [Test]
    procedure MissingTokenizerFileIsRefused;
    [Test]
    procedure UnsupportedTokenizerModelIsRefused;
    [Test]
    procedure ManySpecialTokensTokenizeInLinearTime;
  end;

  [TestFixture]
  TEmbedderTests = class
  private
    FEmbedder: ITextEmbedder;
    function Encode(const PrefixedText: string): TEmbedding;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Test]
    procedure VectorsMatchReference;
    [Test]
    procedure BatchedPassagesMatchSingleEncoding;
    [Test]
    procedure VectorsAreNormalizedWithModelDimension;
    [Test]
    procedure RepeatedQueriesAreIdentical;
    [Test]
    procedure OverlengthPassageIsRejectedOrTruncatedByPolicy;
    [Test]
    procedure OverlengthQueryIsRejected;
    [Test]
    procedure OverlengthPassageErrorNamesThePassage;
    [Test]
    procedure TruncatedPassageMatchesReference;
    [Test]
    procedure EmptyTextIsRefused;
    [Test]
    procedure CancelledEncodingStops;
    [Test]
    procedure IdentityNamesModelRevisionAndPreprocessing;
  end;

  [TestFixture]
  TEmbedderArtifactTests = class
  public
    [Test]
    procedure MissingModelDirectoryIsRefused;
    [Test]
    procedure MissingRuntimeLibraryIsRefused;
    [Test]
    procedure IncompatibleModelIsRefused;
    [Test]
    procedure ModelWithoutInputsIsRefused;
{$IFDEF MSWINDOWS}
    [Test]
    procedure RepeatedCreateAndFreeReleasesRuntime;
{$ENDIF}
    [Test]
    procedure UnloadableRuntimeLibraryIsRefused;
    [Test]
    procedure NativeLoaderReportsTheCause;
    [Test]
    procedure ModelPathWithNonAsciiCharactersLoads;
    [Test]
    procedure RuntimeLibraryIsListedInThePlatformManifest;
    [Test]
    procedure DefaultArtifactRootFollowsThePlatform;
  end;

  [TestFixture]
  TPairEncodingTests = class
  private
    FTokenizer: TUnigramTokenizer;
    FReference: TJSONObject;
    function Cases: TJSONArray;
    function CaseNamed(const Name: string): TJSONObject;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Test]
    procedure PairIdsMatchReference;
    [Test]
    procedure TruncationKeepsTheQuery;
    [Test]
    procedure LongQueryIsCutToSixtyFourTokens;
    [Test]
    procedure TrailingWhitespaceIsNotTokenized;
    [Test]
    procedure TooSmallLimitIsRefused;
  end;

  [TestFixture]
  TCrossEncoderTests = class
  private
    FManifest: TSearchArtifactManifest;
    FRoot: string;
    FReference: TJSONObject;
    function SyntheticConfig(const FileName: string): TCrossEncoderConfig;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Test]
    procedure PathsComeFromTheManifest;
    [Test]
    procedure LogitsMatchReference;
    [Test]
    procedure IdentityNamesModelRevisionAndPairTemplate;
    [Test]
    procedure EmptyPassageListReturnsNothing;
    [Test]
    procedure EmptyQueryIsRefused;
    [Test]
    procedure WrongOutputShapeIsRefused;
    [Test]
    procedure MissingModelFilesAreRefused;
    [Test]
    procedure ScoresKeepPassageOrderAcrossBatches;
    [Test]
    procedure CancelStopsBetweenBatches;
    [Test]
    procedure NilCancelCheckIsAllowed;
    [Test]
    procedure ScoresDoNotDependOnTheOtherPairs;
    [Test]
    procedure DefaultBatchIsOnePair;
  end;

  [TestFixture]
  TExactVectorIndexTests = class
  public
    [Test]
    procedure RanksByCosineWithStableTieBreak;
    [Test]
    procedure OnlyEligibleScopesAreReturned;
    [Test]
    procedure EmptyEligibleSetReturnsNothing;
    [Test]
    procedure ItemFilterRestrictsBeforeTopK;
    [Test]
    procedure ActiveEmptyItemFilterReturnsNothing;
    [Test]
    procedure InactiveItemFilterIgnoresItemIds;
    [Test]
    procedure ItemFilterStaysInsideEligibleScopes;
    [Test]
    procedure InvalidVectorsAreRefused;
    [Test]
    procedure NonFiniteVectorsAreRefused;
  end;

  [TestFixture]
  TFixtureRetrievalTests = class
  public
    [Test]
    procedure ExpectedDocumentsRankInTopThree;
  end;

implementation

uses
  System.IOUtils, System.Math, System.Diagnostics, System.Generics.Collections,
  unit_OnnxRuntimeApi, unit_NativeLibrary, unit_SearchTestSupport;

const
  VectorTolerance = 1e-4;

function LoadJson(const Name: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(TFile.ReadAllBytes(SearchFixturePath(Name)), 0, True);
  if not (V is TJSONObject) then
  begin
    V.Free;
    raise Exception.CreateFmt('Fixture %s is not a JSON object', [Name]);
  end;
  Result := TJSONObject(V);
end;

function JsonInt64Array(Value: TJSONValue): TArray<Int64>;
var
  A: TJSONArray;
  I: Integer;
begin
  A := Value as TJSONArray;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
    Result[I] := (A.Items[I] as TJSONNumber).AsInt64;
end;

function JsonSingleArray(Value: TJSONValue): TArray<Single>;
var
  A: TJSONArray;
  I: Integer;
begin
  A := Value as TJSONArray;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
    Result[I] := (A.Items[I] as TJSONNumber).AsDouble;
end;

function IdsText(const Ids: TArray<Int64>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Ids) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(Ids[I]);
  end;
end;

function MaxAbsDiff(const A, B: TArray<Single>): Double;
var
  I: Integer;
begin
  Assert.AreEqual<NativeInt>(Length(A), Length(B), 'vector lengths');
  Result := 0;
  for I := 0 to High(A) do
    Result := Max(Result, Abs(Double(A[I]) - B[I]));
end;

function DefaultConfig: TE5EmbedderConfig;
begin
  Result := TE5EmbedderConfig.FromArtifactRoot(TE5EmbedderConfig.DefaultArtifactRoot);
end;

function TempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'eln-search-test-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Result);
end;

function UnitVector(const Values: array of Single): TArray<Single>;
var
  I: Integer;
  Norm: Double;
begin
  SetLength(Result, Length(Values));
  Norm := 0;
  for I := 0 to High(Values) do
    Norm := Norm + Sqr(Double(Values[I]));
  Norm := Sqrt(Norm);
  for I := 0 to High(Values) do
    Result[I] := Values[I] / Norm;
end;

{ TTokenizerParityTests }

procedure TTokenizerParityTests.SetupFixture;
begin
  FTokenizer := TUnigramTokenizer.CreateFromFile(TPath.Combine(DefaultConfig.ModelDirectory, 'tokenizer.json'));
  FReference := LoadJson('tokenizer_reference.json');
end;

procedure TTokenizerParityTests.TearDownFixture;
begin
  FReference.Free;
  FTokenizer.Free;
end;

procedure TTokenizerParityTests.TokenIdsMatchReferenceCases;
var
  Cases: TJSONArray;
  Item: TJSONObject;
  I, J: Integer;
  Mismatches: string;
  Expected, Actual, Mask: TArray<Int64>;
begin
  Assert.AreEqual(UpperCase((FReference.GetValue('provenance') as TJSONObject).GetValue<string>('tokenizer_json_sha256')),
    FTokenizer.Sha256, 'fixture was generated from a different tokenizer.json');
  Cases := FReference.GetValue('cases') as TJSONArray;
  Mismatches := '';
  for I := 0 to Cases.Count - 1 do
  begin
    Item := Cases.Items[I] as TJSONObject;
    Expected := JsonInt64Array(Item.GetValue('ids'));
    Mask := JsonInt64Array(Item.GetValue('attention_mask'));
    Actual := FTokenizer.Encode(Item.GetValue<string>('text'));
    Assert.AreEqual<NativeInt>(Length(Expected), Length(Mask), 'reference mask length');
    for J := 0 to High(Mask) do
      Assert.AreEqual<Int64>(1, Mask[J], 'unpadded reference mask');
    if IdsText(Expected) <> IdsText(Actual) then
      Mismatches := Mismatches + Format('%s %s: expected [%s] actual [%s]', [sLineBreak,
        Item.GetValue<string>('name'), IdsText(Expected), IdsText(Actual)]);
  end;
  Assert.AreEqual('', Mismatches, 'tokenizer cases that differ from the reference');
end;

procedure TTokenizerParityTests.SpecialTokenIdsFollowTemplate;
begin
  Assert.AreEqual(0, FTokenizer.BosId);
  Assert.AreEqual(2, FTokenizer.EosId);
  Assert.AreEqual(1, FTokenizer.PadId);
  Assert.AreEqual(3, FTokenizer.UnkId);
  Assert.AreEqual('0,2', IdsText(FTokenizer.Encode('')));
end;

procedure TTokenizerParityTests.PaddedBatchMatchesReference;
var
  Batch: TJSONArray;
  Tokens: TArray<TArray<Int64>>;
  ExpectedIds, ExpectedMask, Ids, Mask, Row: TArray<Int64>;
  I, Width: Integer;
begin
  Batch := FReference.GetValue('padded_batch') as TJSONArray;
  SetLength(Tokens, Batch.Count);
  ExpectedIds := nil;
  ExpectedMask := nil;
  for I := 0 to Batch.Count - 1 do
  begin
    Tokens[I] := FTokenizer.Encode((Batch.Items[I] as TJSONObject).GetValue<string>('text'));
    Row := JsonInt64Array((Batch.Items[I] as TJSONObject).GetValue('ids'));
    ExpectedIds := ExpectedIds + Row;
    ExpectedMask := ExpectedMask + JsonInt64Array((Batch.Items[I] as TJSONObject).GetValue('attention_mask'));
  end;
  PadTokenBatch(Tokens, FTokenizer.PadId, Ids, Mask, Width);
  Assert.AreEqual(IdsText(ExpectedIds), IdsText(Ids), 'padded ids');
  Assert.AreEqual(IdsText(ExpectedMask), IdsText(Mask), 'attention mask');
end;

procedure TTokenizerParityTests.MissingTokenizerFileIsRefused;
begin
  Assert.WillRaise(
    procedure
    begin
      TUnigramTokenizer.CreateFromFile(TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString + '.json')).Free;
    end, ETokenizerError);
end;

procedure TTokenizerParityTests.UnsupportedTokenizerModelIsRefused;
var
  Dir, Path: string;
begin
  Dir := TempDir;
  try
    Path := TPath.Combine(Dir, 'tokenizer.json');
    TFile.WriteAllText(Path, '{"truncation":null,"model":{"type":"BPE","vocab":{},"merges":[]}}',
      TEncoding.UTF8);
    Assert.WillRaise(
      procedure
      begin
        TUnigramTokenizer.CreateFromFile(Path).Free;
      end, ETokenizerError);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTokenizerParityTests.ManySpecialTokensTokenizeInLinearTime;
var
  Builder: TStringBuilder;
  Text: string;
  I: Integer;
  Ids: TArray<Int64>;
  Watch: TStopwatch;
begin
  Builder := TStringBuilder.Create;
  try
    for I := 1 to 20000 do
      Builder.Append('<s>x</s> ');
    Text := Builder.ToString;
  finally
    Builder.Free;
  end;
  Watch := TStopwatch.StartNew;
  Ids := FTokenizer.EncodeContent(Text);
  Watch.Stop;
  Assert.AreEqual<NativeInt>(80000, Length(Ids), 'four tokens per <s>x</s> unit');
  Assert.AreEqual('0,1022,2,6,0', IdsText(Copy(Ids, 0, 5)));
  Assert.IsTrue(Watch.ElapsedMilliseconds < 500,
    Format('20000 special-token units took %d ms', [Watch.ElapsedMilliseconds]));
end;

{ TEmbedderTests }

procedure TEmbedderTests.SetupFixture;
var
  Config: TE5EmbedderConfig;
begin
  Config := DefaultConfig;
  Config.BatchSize := 4;
  FEmbedder := TE5TextEmbedder.Create(Config);
end;

procedure TEmbedderTests.TearDownFixture;
begin
  FEmbedder := nil;
end;

function TEmbedderTests.Encode(const PrefixedText: string): TEmbedding;
begin
  if PrefixedText.StartsWith(E5QueryPrefix) then
    Result := FEmbedder.EncodeQuery(PrefixedText.Substring(Length(E5QueryPrefix)))
  else if PrefixedText.StartsWith(E5PassagePrefix) then
    Result := FEmbedder.EncodePassages([PrefixedText.Substring(Length(E5PassagePrefix))], olReject)[0]
  else
    raise Exception.CreateFmt('Reference text has no E5 prefix: %s', [PrefixedText]);
end;

procedure TEmbedderTests.VectorsMatchReference;
var
  Reference: TJSONObject;
  Cases: TJSONArray;
  I: Integer;
  Item: TJSONObject;
  Expected: TArray<Single>;
  Actual: TEmbedding;
  Diff, Cosine: Double;
  D: Integer;
begin
  Reference := LoadJson('embedding_reference.json');
  try
    Cases := Reference.GetValue('cases') as TJSONArray;
    for I := 0 to Cases.Count - 1 do
    begin
      Item := Cases.Items[I] as TJSONObject;
      Expected := JsonSingleArray(Item.GetValue('vector'));
      Actual := Encode(Item.GetValue<string>('text'));
      Diff := MaxAbsDiff(Expected, Actual.Vector);
      Cosine := 0;
      for D := 0 to High(Expected) do
        Cosine := Cosine + Double(Expected[D]) * Actual.Vector[D];
      Assert.IsTrue(Diff <= VectorTolerance, Format('case %d max abs diff %.3e', [I, Diff]));
      Assert.IsTrue(Cosine >= 0.9999, Format('case %d cosine %.6f', [I, Cosine]));
    end;
  finally
    Reference.Free;
  end;
end;

procedure TEmbedderTests.BatchedPassagesMatchSingleEncoding;
var
  Corpus: TJSONObject;
  Docs: TJSONArray;
  Texts: TArray<string>;
  Batched: TArray<TEmbedding>;
  I: Integer;
  Alone: TEmbedding;
begin
  Corpus := LoadJson('corpus.json');
  try
    Docs := Corpus.GetValue('documents') as TJSONArray;
    Texts := ['x'];
    for I := 0 to 5 do
      Texts := Texts + [(Docs.Items[I] as TJSONObject).GetValue<string>('text')];
  finally
    Corpus.Free;
  end;
  Batched := FEmbedder.EncodePassages(Texts, olReject);
  for I := 0 to High(Texts) do
  begin
    Alone := FEmbedder.EncodePassages([Texts[I]], olReject)[0];
    Assert.IsTrue(MaxAbsDiff(Alone.Vector, Batched[I].Vector) <= VectorTolerance,
      Format('passage %d differs between padded batch and single encoding', [I]));
  end;
end;

procedure TEmbedderTests.VectorsAreNormalizedWithModelDimension;
var
  E: TEmbedding;
begin
  Assert.AreEqual(384, FEmbedder.Dimension);
  E := FEmbedder.EncodeQuery('vacuum leak');
  Assert.AreEqual<NativeInt>(384, Length(E.Vector));
  Assert.IsTrue(Abs(VectorNorm(E.Vector) - 1) < 1e-5, 'query vector norm');
end;

procedure TEmbedderTests.RepeatedQueriesAreIdentical;
var
  First, Next: TEmbedding;
  I: Integer;
begin
  First := FEmbedder.EncodeQuery('XRR roughness of interfaces');
  for I := 1 to 20 do
  begin
    Next := FEmbedder.EncodeQuery('XRR roughness of interfaces');
    Assert.IsTrue(MaxAbsDiff(First.Vector, Next.Vector) <= 1e-6, Format('call %d differs', [I]));
  end;
end;

procedure TEmbedderTests.OverlengthPassageIsRejectedOrTruncatedByPolicy;
var
  Text: string;
  I: Integer;
  E: TEmbedding;
begin
  Text := '';
  for I := 1 to 120 do
    Text := Text + 'Thin film deposition parameters were recorded. ';
  Assert.WillRaise(
    procedure
    begin
      FEmbedder.EncodePassages([Text], olReject);
    end, ETextTooLong);
  E := FEmbedder.EncodePassages([Text], olTruncate)[0];
  Assert.IsTrue(E.Truncated, 'truncation flag');
  Assert.AreEqual(512, E.TokenCount);
  Assert.IsTrue(E.SourceTokenCount > 512, 'source token count');
  Assert.IsTrue(Abs(VectorNorm(E.Vector) - 1) < 1e-5, 'truncated vector norm');
end;

procedure TEmbedderTests.OverlengthQueryIsRejected;
var
  Text: string;
  I: Integer;
begin
  Text := '';
  for I := 1 to 120 do
    Text := Text + 'Thin film deposition parameters were recorded. ';
  Assert.WillRaise(
    procedure
    begin
      FEmbedder.EncodeQuery(Text);
    end, ETextTooLong);
end;

procedure TEmbedderTests.OverlengthPassageErrorNamesThePassage;
var
  Text: string;
  I: Integer;
begin
  Text := '';
  for I := 1 to 120 do
    Text := Text + 'Thin film deposition parameters were recorded. ';
  try
    FEmbedder.EncodePassages(['short passage', Text], olReject);
    Assert.Fail('overlength passage was accepted');
  except
    on E: ETextTooLong do
      Assert.Contains(E.Message, 'Passage 1 ', 'error names the passage index');
  end;
end;

procedure TEmbedderTests.TruncatedPassageMatchesReference;
var
  Reference, Item: TJSONObject;
  E: TEmbedding;
  Diff: Double;
begin
  Reference := LoadJson('embedding_reference.json');
  try
    Item := Reference.GetValue('truncated_case') as TJSONObject;
    E := FEmbedder.EncodePassages([Item.GetValue<string>('text').Substring(Length(E5PassagePrefix))], olTruncate)[0];
    Assert.AreEqual(Item.GetValue<Integer>('token_count'), E.TokenCount, 'token count after truncation');
    Assert.AreEqual(Item.GetValue<Integer>('source_token_count'), E.SourceTokenCount, 'source token count');
    Diff := MaxAbsDiff(JsonSingleArray(Item.GetValue('vector')), E.Vector);
    Assert.IsTrue(Diff <= VectorTolerance, Format('truncated vector max abs diff %.3e', [Diff]));
  finally
    Reference.Free;
  end;
end;

procedure TEmbedderTests.EmptyTextIsRefused;
begin
  Assert.WillRaise(
    procedure
    begin
      FEmbedder.EncodeQuery('   ');
    end, ETextEmbedderError);
  Assert.WillRaise(
    procedure
    begin
      FEmbedder.EncodePassages(['valid text', #9#13#10], olTruncate);
    end, ETextEmbedderError);
end;

procedure TEmbedderTests.CancelledEncodingStops;
var
  Calls: Integer;
begin
  Calls := 0;
  Assert.WillRaise(
    procedure
    begin
      FEmbedder.EncodePassages(['one', 'two', 'three', 'four', 'five', 'six'], olReject,
        function: Boolean
        begin
          Inc(Calls);
          Result := Calls > 1;
        end);
    end, EOperationCancelled);
  Assert.AreEqual(2, Calls, 'cancellation is checked before each batch');
end;

procedure TEmbedderTests.IdentityNamesModelRevisionAndPreprocessing;
begin
  Assert.Contains(FEmbedder.Identity, '614241f622f53c4eeff9890bdc4f31cfecc418b3');
  Assert.Contains(FEmbedder.Identity, 'tokenizer-sha256=0B44A9D7B51C3C62626640CDA0E2C2F70FDACDC25BBBD68038369D14EBDF4C39');
  Assert.Contains(FEmbedder.Identity, 'pooling=mean;norm=l2;dim=384');
end;

{ TEmbedderArtifactTests }

procedure TEmbedderArtifactTests.MissingModelDirectoryIsRefused;
var
  Config: TE5EmbedderConfig;
begin
  Config := TE5EmbedderConfig.FromArtifactRoot(TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString));
  Assert.WillRaise(
    procedure
    begin
      TE5TextEmbedder.Create(Config).Free;
    end, ETextEmbedderError);
end;

procedure TEmbedderArtifactTests.MissingRuntimeLibraryIsRefused;
var
  Config: TE5EmbedderConfig;
  Error: string;
begin
  Config := DefaultConfig;
  Config.RuntimeLibrary := TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString + '.dll');
  Error := RaisedError(
    procedure
    begin
      TE5TextEmbedder.Create(Config).Free;
    end);
  Assert.StartsWith('EOnnxRuntimeError: ONNX Runtime is not installed', Error);
  Assert.Contains(Error, Config.RuntimeLibrary);
end;

procedure TEmbedderArtifactTests.IncompatibleModelIsRefused;
var
  Dir: string;
  Config: TE5EmbedderConfig;
begin
  Dir := TempDir;
  try
    Config := DefaultConfig;
    TFile.Copy(SearchFixturePath('incompatible_model.onnx'), TPath.Combine(Dir, 'model.onnx'));
    TFile.Copy(TPath.Combine(Config.ModelDirectory, 'config.json'), TPath.Combine(Dir, 'config.json'));
    TFile.Copy(TPath.Combine(Config.ModelDirectory, 'tokenizer.json'), TPath.Combine(Dir, 'tokenizer.json'));
    Config.ModelDirectory := Dir;
    Assert.WillRaise(
      procedure
      begin
        TE5TextEmbedder.Create(Config).Free;
      end, ETextEmbedderError, 'incompatible');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TEmbedderArtifactTests.ModelWithoutInputsIsRefused;
var
  Dir: string;
  Config: TE5EmbedderConfig;
begin
  Dir := TempDir;
  try
    Config := DefaultConfig;
    TFile.Copy(SearchFixturePath('zero_input_model.onnx'), TPath.Combine(Dir, 'model.onnx'));
    TFile.Copy(TPath.Combine(Config.ModelDirectory, 'config.json'), TPath.Combine(Dir, 'config.json'));
    TFile.Copy(TPath.Combine(Config.ModelDirectory, 'tokenizer.json'), TPath.Combine(Dir, 'tokenizer.json'));
    Config.ModelDirectory := Dir;
    Assert.WillRaise(
      procedure
      begin
        TE5TextEmbedder.Create(Config).Free;
      end, ETextEmbedderError);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{$IFDEF MSWINDOWS}
procedure TEmbedderArtifactTests.RepeatedCreateAndFreeReleasesRuntime;
var
  Config: TE5EmbedderConfig;
  I: Integer;
  Embedder: ITextEmbedder;
begin
  Config := DefaultConfig;
  for I := 1 to 3 do
  begin
    Embedder := TE5TextEmbedder.Create(Config);
    Assert.AreEqual<NativeInt>(384, Length(Embedder.EncodeQuery('cycle').Vector));
    Assert.IsTrue(NativeLibraryLoaded(Config.RuntimeLibrary), 'runtime loaded while in use');
    Embedder := nil;
    Assert.IsFalse(NativeLibraryLoaded(Config.RuntimeLibrary),
      Format('runtime library still loaded after cycle %d', [I]));
  end;
end;
{$ENDIF}

procedure TEmbedderArtifactTests.UnloadableRuntimeLibraryIsRefused;
var
  Dir, Path, Error: string;
begin
  Dir := TempDir;
  try
    Path := TPath.Combine(Dir, 'onnxruntime-broken.bin');
    TFile.WriteAllBytes(Path, TEncoding.ASCII.GetBytes(#127'ELF this is not a library'));
    Error := RaisedError(
      procedure
      begin
        TOrtRuntime.Create(Path).Free;
      end);
    Assert.StartsWith('EOnnxRuntimeError: ONNX Runtime is not installed correctly', Error);
    Assert.Contains(Error, Path);
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TEmbedderArtifactTests.NativeLoaderReportsTheCause;
var
  Dir, Path: string;
  Handle: NativeUInt;
begin
  Dir := TempDir;
  try
    Path := TPath.Combine(Dir, 'broken.bin');
    Assert.AreEqual<NativeUInt>(0, LoadNativeLibrary(Path));
    Assert.AreNotEqual('', NativeLoadError, 'missing file');
    TFile.WriteAllBytes(Path, TEncoding.ASCII.GetBytes(#127'ELF this is not a library'));
    Assert.AreEqual<NativeUInt>(0, LoadNativeLibrary(Path));
    Assert.AreNotEqual('', NativeLoadError, 'not a library');
  finally
    TDirectory.Delete(Dir, True);
  end;
  Handle := LoadNativeLibrary(DefaultConfig.RuntimeLibrary);
  Assert.AreNotEqual<NativeUInt>(0, Handle, NativeLoadError);
  try
    Assert.IsNotNull(NativeSymbol(Handle, 'OrtGetApiBase'));
    Assert.IsNull(NativeSymbol(Handle, 'OrtNoSuchExport'));
    Assert.AreNotEqual('', NativeLoadError, 'missing export');
  finally
    FreeNativeLibrary(Handle);
  end;
end;

procedure TEmbedderArtifactTests.ModelPathWithNonAsciiCharactersLoads;
var
  Root, Dir, ModelPath: string;
  Runtime: TOrtRuntime;
  Session: TOrtSession;
begin
  Root := TempDir;
  try
    Dir := TPath.Combine(Root, #$041C#$043E#$0434#$0435#$043B#$044C' '#$00E9);
    TDirectory.CreateDirectory(Dir);
    ModelPath := TPath.Combine(Dir, 'model.onnx');
    TFile.Copy(SearchFixturePath('crossencoder_token_count.onnx'), ModelPath);
    Runtime := TOrtRuntime.Create(DefaultConfig.RuntimeLibrary);
    try
      Session := TOrtSession.Create(Runtime, ModelPath, 1);
      try
        Assert.IsTrue(Length(Session.InputNames) > 0, 'session has inputs');
      finally
        Session.Free;
      end;
    finally
      Runtime.Free;
    end;
  finally
    TDirectory.Delete(Root, True);
  end;
end;

procedure TEmbedderArtifactTests.RuntimeLibraryIsListedInThePlatformManifest;
var
  Manifest: TSearchArtifactManifest;
  Root, Runtime: string;
  Archive: TArtifactArchive;
  F: TArtifactFile;
  Found: Boolean;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'artifact-root');
  Runtime := TE5EmbedderConfig.FromArtifactRoot(Root).RuntimeLibrary;
  Manifest := TSearchArtifactManifest.LoadFromFile(PlatformManifestPath);
  Found := False;
  for Archive in Manifest.Archives do
    if not Archive.Optional then
      for F in Archive.Files do
        if TPath.Combine(Root, F.RelativePath) = Runtime then
          Found := True;
  Assert.IsTrue(Found, Runtime + ' is not a required file of ' + PlatformManifestPath);
end;

procedure TEmbedderArtifactTests.DefaultArtifactRootFollowsThePlatform;
const
  BaseVariable = {$IFDEF MSWINDOWS}'LOCALAPPDATA'{$ELSE}'XDG_DATA_HOME'{$ENDIF};
var
  SavedArtifacts, SavedBase, Base: string;
begin
  SavedArtifacts := GetEnvironmentVariable('ELN_SEARCH_ARTIFACTS');
  SavedBase := GetEnvironmentVariable(BaseVariable);
  Base := TPath.Combine(TPath.GetTempPath, 'eln-data-' + TGUID.NewGuid.ToString);
  try
    SetEnvironmentValue('ELN_SEARCH_ARTIFACTS', '');
    SetEnvironmentValue(BaseVariable, Base);
    Assert.AreEqual(TPath.Combine(TPath.Combine(Base, 'APS-ELN'), 'search-artifacts'),
      TE5EmbedderConfig.DefaultArtifactRoot);
{$IFNDEF MSWINDOWS}
    SetEnvironmentValue(BaseVariable, '');
    Assert.AreEqual(TPath.Combine(TPath.Combine(TPath.Combine(TPath.Combine(GetEnvironmentVariable('HOME'),
      '.local'), 'share'), 'APS-ELN'), 'search-artifacts'), TE5EmbedderConfig.DefaultArtifactRoot);
{$ENDIF}
    SetEnvironmentValue('ELN_SEARCH_ARTIFACTS', Base);
    Assert.AreEqual(Base, TE5EmbedderConfig.DefaultArtifactRoot);
  finally
    SetEnvironmentValue('ELN_SEARCH_ARTIFACTS', SavedArtifacts);
    SetEnvironmentValue(BaseVariable, SavedBase);
  end;
end;

{ TPairEncodingTests }

procedure TPairEncodingTests.SetupFixture;
begin
  FTokenizer := TUnigramTokenizer.CreateFromFile(TPath.Combine(DefaultConfig.ModelDirectory, 'tokenizer.json'));
  FReference := LoadJson('pair_reference.json');
end;

procedure TPairEncodingTests.TearDownFixture;
begin
  FReference.Free;
  FTokenizer.Free;
end;

function TPairEncodingTests.Cases: TJSONArray;
begin
  Result := FReference.GetValue('cases') as TJSONArray;
end;

function TPairEncodingTests.CaseNamed(const Name: string): TJSONObject;
var
  I: Integer;
begin
  for I := 0 to Cases.Count - 1 do
    if (Cases.Items[I] as TJSONObject).GetValue<string>('name') = Name then
      Exit(Cases.Items[I] as TJSONObject);
  raise Exception.CreateFmt('Pair reference case %s not found', [Name]);
end;

procedure TPairEncodingTests.PairIdsMatchReference;
var
  I: Integer;
  Item: TJSONObject;
  Expected, Actual: TArray<Int64>;
begin
  Assert.AreEqual<NativeInt>(40, Cases.Count, 'reference pairs');
  for I := 0 to Cases.Count - 1 do
  begin
    Item := Cases.Items[I] as TJSONObject;
    Expected := JsonInt64Array(Item.GetValue('ids'));
    Actual := FTokenizer.EncodePair(Item.GetValue<string>('query'), Item.GetValue<string>('passage'),
      FReference.GetValue<Integer>('max_tokens'));
    Assert.AreEqual(IdsText(Expected), IdsText(Actual), Item.GetValue<string>('name'));
  end;
end;

procedure TPairEncodingTests.TruncationKeepsTheQuery;
const
  Names: array[0..4] of string = ('boundary_513', 'long_passage_en', 'long_passage_ru',
    'long_passage_with_context', 'long_query_long_passage');
var
  Name: string;
  Item: TJSONObject;
  Ids, Query: TArray<Int64>;
  I: Integer;
begin
  for Name in Names do
  begin
    Item := CaseNamed(Name);
    Ids := FTokenizer.EncodePair(Item.GetValue<string>('query'), Item.GetValue<string>('passage'), 512);
    Assert.AreEqual<NativeInt>(512, Length(Ids), Name + ' length');
    Assert.AreEqual<Int64>(FTokenizer.BosId, Ids[0], Name + ' first');
    Assert.AreEqual<Int64>(FTokenizer.EosId, Ids[High(Ids)], Name + ' last');
    Query := FTokenizer.EncodeContent(Item.GetValue<string>('query'));
    if Length(Query) > 64 then
      SetLength(Query, 64);
    for I := 0 to High(Query) do
      Assert.AreEqual<Int64>(Query[I], Ids[1 + I], Format('%s query token %d', [Name, I]));
    Assert.AreEqual<Int64>(FTokenizer.EosId, Ids[1 + Length(Query)], Name + ' first separator');
    Assert.AreEqual<Int64>(FTokenizer.EosId, Ids[2 + Length(Query)], Name + ' second separator');
  end;
end;

procedure TPairEncodingTests.LongQueryIsCutToSixtyFourTokens;
var
  Ids: TArray<Int64>;
begin
  Ids := FTokenizer.EncodePair(CaseNamed('query_65_tokens').GetValue<string>('query'), 'x', 512);
  Assert.AreEqual<Int64>(FTokenizer.EosId, Ids[65], 'first separator after 64 query tokens');
  Assert.AreEqual<Int64>(FTokenizer.EosId, Ids[66], 'second separator');
  Ids := FTokenizer.EncodePair(CaseNamed('query_exactly_64_tokens').GetValue<string>('query'), 'x', 512);
  Assert.AreEqual<Int64>(FTokenizer.EosId, Ids[65], 'a query of exactly 64 tokens stays whole');
  Assert.AreEqual<NativeInt>(64 + 5, Length(Ids), 'length with one passage token');
end;

procedure TPairEncodingTests.TrailingWhitespaceIsNotTokenized;
begin
  Assert.AreEqual(IdsText(FTokenizer.EncodePair('abc', 'def', 512)),
    IdsText(FTokenizer.EncodePair('abc  ', 'def'#10#10, 512)));
  Assert.AreEqual(IdsText(FTokenizer.EncodePair('abc', '', 512)), IdsText(FTokenizer.EncodePair('abc', '   ', 512)));
end;

procedure TPairEncodingTests.TooSmallLimitIsRefused;
begin
  Assert.WillRaise(
    procedure
    begin
      FTokenizer.EncodePair('a', 'b', 4);
    end, ETokenizerError);
  Assert.AreEqual<NativeInt>(5, Length(FTokenizer.EncodePair('a', 'b', 5)));
end;

{ TCrossEncoderTests }

procedure TCrossEncoderTests.SetupFixture;
begin
  FManifest := TSearchArtifactManifest.LoadFromFile(PlatformManifestPath);
  FRoot := TE5EmbedderConfig.DefaultArtifactRoot;
  FReference := LoadJson('pair_reference.json');
end;

procedure TCrossEncoderTests.TearDownFixture;
begin
  FReference.Free;
end;

function TCrossEncoderTests.SyntheticConfig(const FileName: string): TCrossEncoderConfig;
begin
  Result := TCrossEncoderConfig.FromManifest(FManifest, FRoot);
  Result.ModelPath := SearchFixturePath(FileName);
end;

procedure TCrossEncoderTests.PathsComeFromTheManifest;
var
  Config: TCrossEncoderConfig;
begin
  Config := TCrossEncoderConfig.FromManifest(FManifest, 'Root');
  Assert.AreEqual(TPath.Combine('Root', TPath.Combine('mmarco-mMiniLMv2-L12-H384-v1',
    TPath.Combine('onnx', 'model_quint8_avx2.onnx'))), Config.ModelPath);
  Assert.AreEqual(TPath.Combine('Root', TPath.Combine('multilingual-e5-small', 'tokenizer.json')),
    Config.TokenizerPath);
  Assert.AreEqual('cross-encoder/mmarco-mMiniLMv2-L12-H384-v1', Config.ModelName);
  Assert.AreEqual('1427fd652930e4ba29e8149678df786c240d8825', Config.Revision);
  Assert.AreEqual<Integer>(CrossEncoderBatchSize, Config.BatchSize);
  Assert.AreEqual<Integer>(1, Config.BatchSize);
end;

procedure TCrossEncoderTests.LogitsMatchReference;
var
  Group: TJSONObject;
  Texts: TJSONArray;
  Passages: TArray<string>;
  Expected, Actual: TArray<Single>;
  Config: TCrossEncoderConfig;
  Encoder: ICrossEncoder;
  I: Integer;
begin
  Group := FReference.GetValue('logit_group') as TJSONObject;
  Texts := Group.GetValue('passages') as TJSONArray;
  SetLength(Passages, Texts.Count);
  for I := 0 to Texts.Count - 1 do
    Passages[I] := (Texts.Items[I] as TJSONString).Value;
  Expected := JsonSingleArray(Group.GetValue('logits'));
  Config := TCrossEncoderConfig.FromManifest(FManifest, FRoot);
  Config.BatchSize := Length(Passages);
  Encoder := TCrossEncoder.Create(Config);
  Actual := Encoder.Score(Group.GetValue<string>('query'), Passages, nil);
  Assert.AreEqual<NativeInt>(10, Length(Actual), 'scores');
  Assert.IsTrue(MaxAbsDiff(Actual, Expected) < VectorTolerance,
    Format('max abs diff %g against Python ONNX Runtime', [MaxAbsDiff(Actual, Expected)]));
end;

procedure TCrossEncoderTests.ScoresDoNotDependOnTheOtherPairs;
var
  Group: TJSONObject;
  Texts: TJSONArray;
  Passages: TArray<string>;
  Query: string;
  Encoder: ICrossEncoder;
  Together, Alone: TArray<Single>;
  I: Integer;
begin
  Group := FReference.GetValue('logit_group') as TJSONObject;
  Texts := Group.GetValue('passages') as TJSONArray;
  SetLength(Passages, Texts.Count);
  for I := 0 to Texts.Count - 1 do
    Passages[I] := (Texts.Items[I] as TJSONString).Value;
  Query := Group.GetValue<string>('query');
  Encoder := CreateCrossEncoder(FRoot, FManifest);
  Together := Encoder.Score(Query, Passages, nil);
  for I := 0 to High(Passages) do
  begin
    Alone := Encoder.Score(Query, [Passages[I]], nil);
    Assert.AreEqual(Double(Together[I]), Double(Alone[0]), 0.0, 'pair ' + IntToStr(I));
  end;
  Alone := Encoder.Score(Query, [Passages[3], Passages[1]], nil);
  Assert.AreEqual(Double(Together[3]), Double(Alone[0]), 0.0);
  Assert.AreEqual(Double(Together[1]), Double(Alone[1]), 0.0);
end;

procedure TCrossEncoderTests.IdentityNamesModelRevisionAndPairTemplate;
var
  Identity: string;
begin
  Identity := CreateCrossEncoder(FRoot, FManifest).Identity;
  Assert.Contains(Identity, 'cross-encoder/mmarco-mMiniLMv2-L12-H384-v1@1427fd652930e4ba29e8149678df786c240d8825');
  Assert.Contains(Identity, 'tokenizer-sha256=0B44A9D7B51C3C62626640CDA0E2C2F70FDACDC25BBBD68038369D14EBDF4C39');
  Assert.Contains(Identity, 'pair=xlmr;max-tokens=512;batch=1');
end;

procedure TCrossEncoderTests.EmptyPassageListReturnsNothing;
var
  Encoder: ICrossEncoder;
begin
  Encoder := TCrossEncoder.Create(SyntheticConfig('crossencoder_token_count.onnx'));
  Assert.AreEqual<NativeInt>(0, Length(Encoder.Score('query', nil, nil)));
end;

procedure TCrossEncoderTests.EmptyQueryIsRefused;
var
  Encoder: ICrossEncoder;
begin
  Encoder := TCrossEncoder.Create(SyntheticConfig('crossencoder_token_count.onnx'));
  Assert.WillRaise(
    procedure
    begin
      Encoder.Score('   ', ['passage'], nil);
    end, ECrossEncoderError);
end;

procedure TCrossEncoderTests.WrongOutputShapeIsRefused;
var
  Config: TCrossEncoderConfig;
begin
  Config := SyntheticConfig('crossencoder_wrong_shape.onnx');
  Assert.WillRaise(
    procedure
    begin
      TCrossEncoder.Create(Config).Free;
    end, ECrossEncoderError, 'logits');
end;

procedure TCrossEncoderTests.MissingModelFilesAreRefused;
var
  Root: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, TGUID.NewGuid.ToString);
  Assert.WillRaise(
    procedure
    begin
      CreateCrossEncoder(Root, FManifest);
    end, ECrossEncoderError, 'not installed');
end;

procedure TCrossEncoderTests.ScoresKeepPassageOrderAcrossBatches;
var
  Encoder: ICrossEncoder;
  Config: TCrossEncoderConfig;
  Tokenizer: TUnigramTokenizer;
  Passages: TArray<string>;
  Scores: TArray<Single>;
  I: Integer;
begin
  SetLength(Passages, 45);
  for I := 0 to High(Passages) do
    Passages[I] := StringOfChar('x', 1 + (I * 7) mod 13) + ' ' + IntToStr(I);
  Tokenizer := TUnigramTokenizer.CreateFromFile(TPath.Combine(DefaultConfig.ModelDirectory, 'tokenizer.json'));
  try
    Config := SyntheticConfig('crossencoder_token_count.onnx');
    Config.BatchSize := 20;
    Encoder := TCrossEncoder.Create(Config);
    Scores := Encoder.Score('hardness', Passages, nil);
    Assert.AreEqual<NativeInt>(45, Length(Scores));
    for I := 0 to High(Passages) do
      Assert.AreEqual(Double(Length(Tokenizer.EncodePair('hardness', Passages[I], 512))), Double(Scores[I]), 0.0,
        'token count of passage ' + IntToStr(I));
  finally
    Tokenizer.Free;
  end;
end;

procedure TCrossEncoderTests.CancelStopsBetweenBatches;
var
  Encoder: ICrossEncoder;
  Config: TCrossEncoderConfig;
  Passages: TArray<string>;
  Checks: Integer;
  I: Integer;
begin
  SetLength(Passages, 45);
  for I := 0 to High(Passages) do
    Passages[I] := 'passage ' + IntToStr(I);
  Config := SyntheticConfig('crossencoder_token_count.onnx');
  Config.BatchSize := 20;
  Encoder := TCrossEncoder.Create(Config);
  Checks := 0;
  Assert.WillRaise(
    procedure
    begin
      Encoder.Score('query', Passages,
        function: Boolean
        begin
          Inc(Checks);
          Result := Checks >= 2;
        end);
    end, EOperationCancelled);
  Assert.AreEqual<Integer>(2, Checks, 'the check runs before each batch and stops the second one');
end;

procedure TCrossEncoderTests.DefaultBatchIsOnePair;
var
  Encoder: ICrossEncoder;
  Passages: TArray<string>;
  Checks, I: Integer;
begin
  SetLength(Passages, 7);
  for I := 0 to High(Passages) do
    Passages[I] := 'passage ' + IntToStr(I);
  Encoder := TCrossEncoder.Create(SyntheticConfig('crossencoder_token_count.onnx'));
  Checks := 0;
  Assert.AreEqual<NativeInt>(7, Length(Encoder.Score('query', Passages,
    function: Boolean
    begin
      Inc(Checks);
      Result := False;
    end)));
  Assert.AreEqual(7, Checks, 'the cancel check runs before each pair');
end;

procedure TCrossEncoderTests.NilCancelCheckIsAllowed;
var
  Encoder: ICrossEncoder;
  Scores: TArray<Single>;
begin
  Encoder := TCrossEncoder.Create(SyntheticConfig('crossencoder_token_count.onnx'));
  Scores := Encoder.Score('query', ['a', 'b'], nil);
  Assert.AreEqual<NativeInt>(2, Length(Scores));
end;

{ TExactVectorIndexTests }

procedure TExactVectorIndexTests.RanksByCosineWithStableTieBreak;
var
  Index: TExactVectorIndex;
  Hits: TArray<TVectorHit>;
begin
  Index := TExactVectorIndex.Create(3);
  try
    Index.Add('c', 'S', 1, UnitVector([1, 1, 0]));
    Index.Add('b', 'S', 1, UnitVector([1, 0, 0]));
    Index.Add('a', 'S', 1, UnitVector([1, 0, 0]));
    Index.Add('d', 'S', 1, UnitVector([0, 0, 1]));
    Hits := Index.Search(UnitVector([1, 0, 0]), 3, ['S'], Default(TItemFilter));
    Assert.AreEqual<NativeInt>(3, Length(Hits));
    Assert.AreEqual('a', Hits[0].SourceId);
    Assert.AreEqual('b', Hits[1].SourceId);
    Assert.AreEqual('c', Hits[2].SourceId);
    Assert.AreEqual(Double(1), Hits[0].Score, 1e-6);
    Assert.AreEqual(Sqrt(0.5), Hits[2].Score, 1e-6);
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.OnlyEligibleScopesAreReturned;
var
  Index: TExactVectorIndex;
  Hits: TArray<TVectorHit>;
  Hit: TVectorHit;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('best-but-hidden', 'P-SECRET', 1, UnitVector([1, 0]));
    Index.Add('visible-1', 'P-OPEN', 2, UnitVector([1, 1]));
    Index.Add('visible-2', 'P-OTHER', 3, UnitVector([0, 1]));
    Hits := Index.Search(UnitVector([1, 0]), 10, ['P-OPEN', 'P-OTHER'], Default(TItemFilter));
    Assert.AreEqual<NativeInt>(2, Length(Hits));
    for Hit in Hits do
      Assert.AreNotEqual('P-SECRET', Hit.Scope);
    Assert.AreEqual('visible-1', Hits[0].SourceId);
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.EmptyEligibleSetReturnsNothing;
var
  Index: TExactVectorIndex;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('a', 'P', 1, UnitVector([1, 0]));
    Assert.AreEqual<NativeInt>(0, Length(Index.Search(UnitVector([1, 0]), 5, [], Default(TItemFilter))));
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.ItemFilterRestrictsBeforeTopK;
var
  Index: TExactVectorIndex;
  Hits: TArray<TVectorHit>;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('near-1', 'P', 1, UnitVector([1, 0]));
    Index.Add('near-2', 'P', 2, UnitVector([1, 0.1]));
    Index.Add('far', 'P', 3, UnitVector([0, 1]));
    Hits := Index.Search(UnitVector([1, 0]), 1, ['P'], TItemFilter.Only([3]));
    Assert.AreEqual<NativeInt>(1, Length(Hits));
    Assert.AreEqual('far', Hits[0].SourceId);
    Hits := Index.Search(UnitVector([1, 0]), 10, ['P'], TItemFilter.Only([2, 3]));
    Assert.AreEqual<NativeInt>(2, Length(Hits));
    Assert.AreEqual('near-2', Hits[0].SourceId);
    Assert.AreEqual('far', Hits[1].SourceId);
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.ActiveEmptyItemFilterReturnsNothing;
var
  Index: TExactVectorIndex;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('a', 'P', 1, UnitVector([1, 0]));
    Assert.AreEqual<NativeInt>(0, Length(Index.Search(UnitVector([1, 0]), 5, ['P'], TItemFilter.Only([]))));
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.InactiveItemFilterIgnoresItemIds;
var
  Index: TExactVectorIndex;
  Filter: TItemFilter;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('a', 'P', 1, UnitVector([1, 0]));
    Index.Add('b', 'P', 2, UnitVector([0, 1]));
    Filter := TItemFilter.Only([2]);
    Filter.Active := False;
    Assert.AreEqual<NativeInt>(2, Length(Index.Search(UnitVector([1, 0]), 5, ['P'], Filter)));
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.ItemFilterStaysInsideEligibleScopes;
var
  Index: TExactVectorIndex;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('hidden', 'P-SECRET', 7, UnitVector([1, 0]));
    Index.Add('open', 'P-OPEN', 8, UnitVector([0, 1]));
    Assert.AreEqual<NativeInt>(0, Length(Index.Search(UnitVector([1, 0]), 5, ['P-OPEN'], TItemFilter.Only([7]))));
    Assert.AreEqual<NativeInt>(1, Length(Index.Search(UnitVector([1, 0]), 5, ['P-OPEN'], TItemFilter.Only([7, 8]))));
  finally
    Index.Free;
  end;
end;

procedure TExactVectorIndexTests.InvalidVectorsAreRefused;
var
  Index: TExactVectorIndex;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('a', 'P', 1, UnitVector([1, 0]));
    Assert.WillRaise(procedure begin Index.Add('a', 'P', 1, UnitVector([0, 1])); end, EVectorSearchError);
    Assert.WillRaise(procedure begin Index.Add('b', 'P', 1, [1, 1]); end, EVectorSearchError);
    Assert.WillRaise(procedure begin Index.Add('c', 'P', 1, UnitVector([1, 0, 0])); end, EVectorSearchError);
    Assert.WillRaise(procedure begin Index.Search([2, 0], 1, ['P'], Default(TItemFilter)); end, EVectorSearchError);
  finally
    Index.Free;
  end;
end;

function HitsContain(const Hits: TArray<TVectorHit>; const SourceId: string): Boolean;
var
  Hit: TVectorHit;
begin
  for Hit in Hits do
    if Hit.SourceId = SourceId then
      Exit(True);
  Result := False;
end;

procedure TExactVectorIndexTests.NonFiniteVectorsAreRefused;
var
  Index: TExactVectorIndex;
begin
  Index := TExactVectorIndex.Create(2);
  try
    Index.Add('a', 'P', 1, UnitVector([1, 0]));
    Assert.WillRaise(procedure begin Index.Add('nan', 'P', 1, [NaN, 0]); end, EVectorSearchError);
    Assert.WillRaise(procedure begin Index.Search([NaN, 0], 1, ['P'], Default(TItemFilter)); end, EVectorSearchError);
    Assert.AreEqual(1, Index.Count);
  finally
    Index.Free;
  end;
end;

{ TFixtureRetrievalTests }

procedure TFixtureRetrievalTests.ExpectedDocumentsRankInTopThree;
var
  Corpus: TJSONObject;
  Docs, Queries, Relevant, ScopeList: TJSONArray;
  Embedder: ITextEmbedder;
  Index: TExactVectorIndex;
  Texts, AllScopes, Scopes: TArray<string>;
  Embeddings: TArray<TEmbedding>;
  I, J: Integer;
  Failures: string;
  Query: TJSONObject;
  Hits: TArray<TVectorHit>;
  Kind, Line: string;
  Found, Asserted: Boolean;
  ScopeSet: TDictionary<string, Boolean>;
begin
  Corpus := LoadJson('corpus.json');
  Index := nil;
  ScopeSet := TDictionary<string, Boolean>.Create;
  try
    Embedder := TE5TextEmbedder.Create(DefaultConfig);
    Docs := Corpus.GetValue('documents') as TJSONArray;
    SetLength(Texts, Docs.Count);
    for I := 0 to Docs.Count - 1 do
    begin
      Texts[I] := (Docs.Items[I] as TJSONObject).GetValue<string>('text');
      ScopeSet.AddOrSetValue((Docs.Items[I] as TJSONObject).GetValue<string>('scope'), True);
    end;
    AllScopes := ScopeSet.Keys.ToArray;
    Embeddings := Embedder.EncodePassages(Texts, olReject);
    Index := TExactVectorIndex.Create(Embedder.Dimension);
    for I := 0 to Docs.Count - 1 do
      Index.Add((Docs.Items[I] as TJSONObject).GetValue<string>('id'),
        (Docs.Items[I] as TJSONObject).GetValue<string>('scope'), I + 1, Embeddings[I].Vector);

    Queries := Corpus.GetValue('queries') as TJSONArray;
    Failures := '';
    for I := 0 to Queries.Count - 1 do
    begin
      Query := Queries.Items[I] as TJSONObject;
      Kind := Query.GetValue<string>('kind');
      Scopes := AllScopes;
      if Query.GetValue('scope') is TJSONArray then
      begin
        ScopeList := TJSONArray(Query.GetValue('scope'));
        SetLength(Scopes, ScopeList.Count);
        for J := 0 to ScopeList.Count - 1 do
          Scopes[J] := ScopeList.Items[J].Value;
      end;
      Hits := Index.Search(Embedder.EncodeQuery(Query.GetValue<string>('text')).Vector, 3, Scopes, Default(TItemFilter));
      for J := 0 to High(Hits) do
        Assert.IsTrue(TArray.IndexOf<string>(Scopes, Hits[J].Scope) >= 0,
          Format('%s returned %s outside its eligible scopes', [Query.GetValue<string>('id'), Hits[J].SourceId]));
      Relevant := Query.GetValue('relevant') as TJSONArray;
      Found := Relevant.Count = 0;
      for J := 0 to Relevant.Count - 1 do
        if not Found then
          Found := (Length(Hits) > 0) and HitsContain(Hits, Relevant.Items[J].Value);
      Asserted := (Kind <> 'negation') and (Kind <> 'exact-identifier');
      Line := Format('%s [%s]:', [Query.GetValue<string>('id'), Kind]);
      for J := 0 to High(Hits) do
        Line := Line + Format(' %s=%.4f', [Hits[J].SourceId, Hits[J].Score]);
      if Asserted and not Found then
        Failures := Failures + sLineBreak + Line;
    end;
    Assert.AreEqual('', Failures, 'queries without a relevant document in the top 3');
  finally
    Index.Free;
    ScopeSet.Free;
    Corpus.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTokenizerParityTests);
  TDUnitX.RegisterTestFixture(TEmbedderTests);
  TDUnitX.RegisterTestFixture(TEmbedderArtifactTests);
  TDUnitX.RegisterTestFixture(TPairEncodingTests);
  TDUnitX.RegisterTestFixture(TCrossEncoderTests);
  TDUnitX.RegisterTestFixture(TExactVectorIndexTests);
  TDUnitX.RegisterTestFixture(TFixtureRetrievalTests);

end.
