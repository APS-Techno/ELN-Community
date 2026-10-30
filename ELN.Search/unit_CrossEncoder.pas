unit unit_CrossEncoder;

interface

uses
  System.SysUtils, unit_OnnxRuntimeApi, unit_UnigramTokenizer, unit_TextEmbedder, unit_SearchArtifacts;

type
  ECrossEncoderError = class(Exception);

  ICrossEncoder = interface
    ['{3C1D5F0A-7B52-4E8B-9A1F-52E04C7D6B91}']
    function Score(const Query: string; const Passages: TArray<string>; const Cancelled: TCancelCheck): TArray<Single>;
    function Identity: string;
  end;

  TCrossEncoderFactory = reference to function: ICrossEncoder;

  TCrossEncoderConfig = record
    ModelPath: string;
    TokenizerPath: string;
    RuntimeLibrary: string;
    ModelName: string;
    Revision: string;
    BatchSize: Integer;
    IntraOpThreads: Integer;
    class function FromManifest(const Manifest: TSearchArtifactManifest;
      const ArtifactRoot: string): TCrossEncoderConfig; static;
  end;

  { Scores (query, passage) pairs with a cross-encoder of the XLM-R family.
    A score is a raw logit. It orders the pairs of one call and has no other
    meaning. The 8-bit model quantizes activations per batch, so the same pair
    can score slightly differently in another batch. The default batch is one
    pair, so a pair scores the same in every call. }
  TCrossEncoder = class(TInterfacedObject, ICrossEncoder)
  private
    FRuntime: TOrtRuntime;
    FSession: TOrtSession;
    FTokenizer: TUnigramTokenizer;
    FBatchSize: Integer;
    FHasTokenTypes: Boolean;
    FIdentity: string;
    procedure ValidateModel;
    procedure ScoreBatch(const Tokens: TArray<TArray<Int64>>; var Scores: TArray<Single>; First: Integer);
  public
    constructor Create(const Config: TCrossEncoderConfig);
    destructor Destroy; override;
    function Score(const Query: string; const Passages: TArray<string>; const Cancelled: TCancelCheck): TArray<Single>;
    function Identity: string;
  end;

const
  CrossEncoderMaxTokens = 512;
  CrossEncoderBatchSize = 1;

function CreateCrossEncoder(const ArtifactRoot: string; const Manifest: TSearchArtifactManifest): ICrossEncoder;

function CrossEncoderInstalled(const ArtifactRoot: string): Boolean;

function CrossEncoderFactory(const ArtifactRoot: string): TCrossEncoderFactory;

implementation

uses
  System.IOUtils, System.Math;

function FindFile(const Model: TArtifactModel; const FileName: string; out Found: TArtifactFile): Boolean;
var
  F: TArtifactFile;
begin
  for F in Model.Files do
    if SameText(TPath.GetFileName(F.RelativePath.Replace('\', '/')), FileName) then
    begin
      Found := F;
      Exit(True);
    end;
  Found := Default(TArtifactFile);
  Result := False;
end;

function FindOnnxFile(const Model: TArtifactModel; out Found: TArtifactFile): Boolean;
var
  F: TArtifactFile;
begin
  for F in Model.Files do
    if SameText(TPath.GetExtension(F.RelativePath), '.onnx') then
    begin
      Found := F;
      Exit(True);
    end;
  Found := Default(TArtifactFile);
  Result := False;
end;

{ TCrossEncoderConfig }

class function TCrossEncoderConfig.FromManifest(const Manifest: TSearchArtifactManifest;
  const ArtifactRoot: string): TCrossEncoderConfig;
var
  Reranker, Embedder: TArtifactModel;
  ModelFile, TokenizerFile: TArtifactFile;
begin
  if not Manifest.FindModel(mrReranker, Reranker) then
    raise ECrossEncoderError.Create('The search artifact manifest has no reranker model');
  if not Manifest.FindModel(mrEmbedder, Embedder) then
    raise ECrossEncoderError.Create('The search artifact manifest has no embedder model');
  if not FindOnnxFile(Reranker, ModelFile) then
    raise ECrossEncoderError.CreateFmt('The manifest entry %s has no .onnx file', [Reranker.Name]);
  if not FindFile(Embedder, 'tokenizer.json', TokenizerFile) then
    raise ECrossEncoderError.CreateFmt('The manifest entry %s has no tokenizer.json', [Embedder.Name]);
  Result.ModelPath := TPath.Combine(ArtifactRoot, ModelFile.RelativePath);
  Result.TokenizerPath := TPath.Combine(ArtifactRoot, TokenizerFile.RelativePath);
  Result.RuntimeLibrary := TE5EmbedderConfig.FromArtifactRoot(ArtifactRoot).RuntimeLibrary;
  Result.ModelName := Reranker.Name;
  Result.Revision := Reranker.Revision;
  Result.BatchSize := CrossEncoderBatchSize;
  Result.IntraOpThreads := 0;
end;

{ TCrossEncoder }

constructor TCrossEncoder.Create(const Config: TCrossEncoderConfig);
begin
  inherited Create;
  if Config.BatchSize < 1 then
    raise ECrossEncoderError.Create('Batch size must be at least 1');
  FBatchSize := Config.BatchSize;
  if not TFile.Exists(Config.ModelPath) then
    raise ECrossEncoderError.CreateFmt('Reranker model not found: %s', [Config.ModelPath]);
  FTokenizer := TUnigramTokenizer.CreateFromFile(Config.TokenizerPath);
  FRuntime := TOrtRuntime.Create(Config.RuntimeLibrary);
  FSession := TOrtSession.Create(FRuntime, Config.ModelPath, Config.IntraOpThreads);
  ValidateModel;
  FIdentity := Format('%s@%s;model-bytes=%d;tokenizer-sha256=%s;pair=xlmr;max-tokens=%d;batch=%d',
    [Config.ModelName, Config.Revision, TFile.GetSize(Config.ModelPath), FTokenizer.Sha256,
    CrossEncoderMaxTokens, FBatchSize]);
end;

destructor TCrossEncoder.Destroy;
begin
  FSession.Free;
  FRuntime.Free;
  FTokenizer.Free;
  inherited;
end;

procedure TCrossEncoder.ValidateModel;
var
  I: Integer;
  HasIds, HasMask, HasLogits: Boolean;
  OutInfo: TOrtTensorInfo;
begin
  OutInfo := Default(TOrtTensorInfo);
  HasIds := False;
  HasMask := False;
  FHasTokenTypes := False;
  for I := 0 to High(FSession.InputNames) do
  begin
    if FSession.InputInfo[I].ElementType <> OrtElementInt64 then
      raise ECrossEncoderError.CreateFmt('Incompatible reranker model: input %s is not int64',
        [FSession.InputNames[I]]);
    if FSession.InputNames[I] = 'input_ids' then
      HasIds := True
    else if FSession.InputNames[I] = 'attention_mask' then
      HasMask := True
    else if FSession.InputNames[I] = 'token_type_ids' then
      FHasTokenTypes := True
    else
      raise ECrossEncoderError.CreateFmt('Incompatible reranker model: unexpected input %s',
        [FSession.InputNames[I]]);
  end;
  if not (HasIds and HasMask) then
    raise ECrossEncoderError.Create('Incompatible reranker model: input_ids and attention_mask inputs are required');
  HasLogits := False;
  for I := 0 to High(FSession.OutputNames) do
    if FSession.OutputNames[I] = 'logits' then
    begin
      OutInfo := FSession.OutputInfo[I];
      HasLogits := True;
    end;
  if not HasLogits then
    raise ECrossEncoderError.Create('Incompatible reranker model: no logits output');
  if (OutInfo.ElementType <> OrtElementFloat) or (Length(OutInfo.Dimensions) <> 2) or
    (OutInfo.Dimensions[1] <> 1) then
    raise ECrossEncoderError.Create('Incompatible reranker model: logits must be float [batch, 1]');
end;

function TCrossEncoder.Identity: string;
begin
  Result := FIdentity;
end;

procedure TCrossEncoder.ScoreBatch(const Tokens: TArray<TArray<Int64>>; var Scores: TArray<Single>; First: Integer);
var
  Rows, Width, R: Integer;
  Inputs: TArray<TOrtInt64Input>;
  Output: TOrtFloatOutput;
begin
  Rows := Length(Tokens);
  if FHasTokenTypes then
    SetLength(Inputs, 3)
  else
    SetLength(Inputs, 2);
  Inputs[0].Name := 'input_ids';
  Inputs[1].Name := 'attention_mask';
  PadTokenBatch(Tokens, FTokenizer.PadId, Inputs[0].Data, Inputs[1].Data, Width);
  Inputs[0].Shape := [Rows, Width];
  Inputs[1].Shape := [Rows, Width];
  if FHasTokenTypes then
  begin
    Inputs[2].Name := 'token_type_ids';
    SetLength(Inputs[2].Data, Rows * Width);
    Inputs[2].Shape := [Rows, Width];
  end;

  Output := FSession.Run(Inputs, 'logits');
  if (Length(Output.Shape) <> 2) or (Output.Shape[0] <> Rows) or (Output.Shape[1] <> 1) then
    raise ECrossEncoderError.Create('The reranker model returned an unexpected logits shape');
  for R := 0 to Rows - 1 do
  begin
    if IsNan(Output.Data[R]) or IsInfinite(Output.Data[R]) then
      raise ECrossEncoderError.Create('The reranker model returned a non-finite score');
    Scores[First + R] := Output.Data[R];
  end;
end;

function TCrossEncoder.Score(const Query: string; const Passages: TArray<string>;
  const Cancelled: TCancelCheck): TArray<Single>;
var
  Tokens: TArray<TArray<Int64>>;
  I, First, Count: Integer;
begin
  if Trim(Query) = '' then
    raise ECrossEncoderError.Create('Query text is empty');
  SetLength(Result, Length(Passages));
  SetLength(Tokens, Length(Passages));
  for I := 0 to High(Passages) do
    Tokens[I] := FTokenizer.EncodePair(Query, Passages[I], CrossEncoderMaxTokens);
  First := 0;
  while First < Length(Passages) do
  begin
    if Assigned(Cancelled) and Cancelled() then
      raise EOperationCancelled.Create('Reranking was cancelled');
    Count := Min(FBatchSize, Length(Passages) - First);
    ScoreBatch(Copy(Tokens, First, Count), Result, First);
    Inc(First, Count);
  end;
end;

function CreateCrossEncoder(const ArtifactRoot: string; const Manifest: TSearchArtifactManifest): ICrossEncoder;
var
  Config: TCrossEncoderConfig;
begin
  Config := TCrossEncoderConfig.FromManifest(Manifest, ArtifactRoot);
  if not OptionalPartReady(Manifest, ArtifactRoot, Config.ModelName) then
    raise ECrossEncoderError.CreateFmt('The reranker model %s is not installed in %s',
      [Config.ModelName, ArtifactRoot]);
  Result := TCrossEncoder.Create(Config);
end;

function LoadDefaultManifest: TSearchArtifactManifest;
var
  ManifestPath: string;
begin
  ManifestPath := TSearchArtifactManifest.DefaultPath;
  if not TFile.Exists(ManifestPath) then
    raise ECrossEncoderError.CreateFmt('Search artifact manifest not found: %s', [ManifestPath]);
  Result := TSearchArtifactManifest.LoadFromFile(ManifestPath);
end;

function CrossEncoderInstalled(const ArtifactRoot: string): Boolean;
var
  Manifest: TSearchArtifactManifest;
begin
  try
    Manifest := LoadDefaultManifest;
    Result := OptionalPartReady(Manifest, ArtifactRoot,
      TCrossEncoderConfig.FromManifest(Manifest, ArtifactRoot).ModelName);
  except
    on Exception do
      Result := False;
  end;
end;

function CrossEncoderFactory(const ArtifactRoot: string): TCrossEncoderFactory;
begin
  Result :=
    function: ICrossEncoder
    begin
      Result := CreateCrossEncoder(ArtifactRoot, LoadDefaultManifest);
    end;
end;

end.
