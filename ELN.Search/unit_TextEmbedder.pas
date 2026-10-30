unit unit_TextEmbedder;

interface

uses
  System.SysUtils, unit_OnnxRuntimeApi, unit_UnigramTokenizer;

type
  ETextEmbedderError = class(Exception);
  ETextTooLong = class(ETextEmbedderError);

  TEmbeddingVector = TArray<Single>;

  TOverlengthPolicy = (olReject, olTruncate);

  TEmbedding = record
    Vector: TEmbeddingVector;
    TokenCount: Integer;
    SourceTokenCount: Integer;
    Truncated: Boolean;
  end;

  TCancelCheck = reference to function: Boolean;

  ITextEmbedder = interface
    ['{6E0B7C0B-8E37-4E1B-9C64-3A9B5B1F7D21}']
    function Identity: string;
    function Dimension: Integer;
    function MaxTokens: Integer;
    function EncodeQuery(const Text: string): TEmbedding;
    function EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
      const Cancelled: TCancelCheck = nil): TArray<TEmbedding>;
  end;

  TE5EmbedderConfig = record
    ModelDirectory: string;
    RuntimeLibrary: string;
    BatchSize: Integer;
    IntraOpThreads: Integer;
    class function FromArtifactRoot(const Root: string): TE5EmbedderConfig; static;
    class function DefaultArtifactRoot: string; static;
  end;

  { intfloat/multilingual-e5-small: "query: " / "passage: " prefixes, mean
    pooling over the attention mask, L2 normalization. }
  TE5TextEmbedder = class(TInterfacedObject, ITextEmbedder)
  private
    FRuntime: TOrtRuntime;
    FSession: TOrtSession;
    FTokenizer: TUnigramTokenizer;
    FDimension: Integer;
    FBatchSize: Integer;
    FHasTokenTypes: Boolean;
    FIdentity: string;
    procedure ValidateModel;
    function Tokenize(const Text, Subject: string; Policy: TOverlengthPolicy;
      out Embedding: TEmbedding): TArray<Int64>;
    procedure EmbedBatch(const Tokens: TArray<TArray<Int64>>; var Results: TArray<TEmbedding>; First: Integer);
  public
    constructor Create(const Config: TE5EmbedderConfig);
    destructor Destroy; override;
    function Identity: string;
    function Dimension: Integer;
    function MaxTokens: Integer;
    function EncodeQuery(const Text: string): TEmbedding;
    function EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
      const Cancelled: TCancelCheck = nil): TArray<TEmbedding>;
    function RuntimeVersion: string;
  end;

const
  E5MaxTokens = 512;
  E5QueryPrefix = 'query: ';
  E5PassagePrefix = 'passage: ';

procedure PadTokenBatch(const Tokens: TArray<TArray<Int64>>; PadId: Int64; out Ids, Mask: TArray<Int64>;
  out Width: Integer);

implementation

uses
  System.IOUtils, System.JSON, System.Math;

const
  ModelRevision = '614241f622f53c4eeff9890bdc4f31cfecc418b3';
{$IFDEF MSWINDOWS}
  RuntimeRelativePath = 'onnxruntime\onnxruntime-win-x64-1.31.1\lib\onnxruntime.dll';
{$ELSE}
  RuntimeRelativePath = 'onnxruntime/onnxruntime-linux-x64-1.31.1/lib/libonnxruntime.so.1.31.1';
{$ENDIF}
  ModelFolder = 'multilingual-e5-small';

{ TE5EmbedderConfig }

class function TE5EmbedderConfig.DefaultArtifactRoot: string;
var
  DataRoot: string;
begin
  Result := GetEnvironmentVariable('ELN_SEARCH_ARTIFACTS');
  if Result <> '' then
    Exit;
{$IFDEF MSWINDOWS}
  DataRoot := GetEnvironmentVariable('LOCALAPPDATA');
{$ELSE}
  DataRoot := GetEnvironmentVariable('XDG_DATA_HOME');
  if DataRoot = '' then
    DataRoot := TPath.Combine(TPath.Combine(GetEnvironmentVariable('HOME'), '.local'), 'share');
{$ENDIF}
  Result := TPath.Combine(TPath.Combine(DataRoot, 'APS-ELN'), 'search-artifacts');
end;

class function TE5EmbedderConfig.FromArtifactRoot(const Root: string): TE5EmbedderConfig;
begin
  Result.ModelDirectory := TPath.Combine(Root, ModelFolder);
  Result.RuntimeLibrary := TPath.Combine(Root, RuntimeRelativePath);
  Result.BatchSize := 8;
  Result.IntraOpThreads := 0;
end;

function ReadHiddenSize(const ConfigPath: string): Integer;
var
  Root: TJSONValue;
  V: TJSONValue;
begin
  if not TFile.Exists(ConfigPath) then
    raise ETextEmbedderError.CreateFmt('Model configuration not found: %s', [ConfigPath]);
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllBytes(ConfigPath), 0, True);
  try
    if not (Root is TJSONObject) then
      raise ETextEmbedderError.CreateFmt('Model configuration is not a JSON object: %s', [ConfigPath]);
    V := TJSONObject(Root).GetValue('hidden_size');
    if not (V is TJSONNumber) or (TJSONNumber(V).AsInt <= 0) then
      raise ETextEmbedderError.CreateFmt('Model configuration has no valid hidden_size: %s', [ConfigPath]);
    Result := TJSONNumber(V).AsInt;
  finally
    Root.Free;
  end;
end;

{ TE5TextEmbedder }

constructor TE5TextEmbedder.Create(const Config: TE5EmbedderConfig);
var
  ModelPath: string;
begin
  inherited Create;
  if Config.BatchSize < 1 then
    raise ETextEmbedderError.Create('Batch size must be at least 1');
  FBatchSize := Config.BatchSize;
  ModelPath := TPath.Combine(Config.ModelDirectory, 'model.onnx');
  if not TFile.Exists(ModelPath) then
    raise ETextEmbedderError.CreateFmt('Embedding model not found: %s (run tools\Get-SearchArtifacts.ps1)',
      [ModelPath]);
  FDimension := ReadHiddenSize(TPath.Combine(Config.ModelDirectory, 'config.json'));
  FTokenizer := TUnigramTokenizer.CreateFromFile(TPath.Combine(Config.ModelDirectory, 'tokenizer.json'));
  FRuntime := TOrtRuntime.Create(Config.RuntimeLibrary);
  FSession := TOrtSession.Create(FRuntime, ModelPath, Config.IntraOpThreads);
  ValidateModel;
  FIdentity := Format('multilingual-e5-small@%s;model-bytes=%d;tokenizer-sha256=%s;prefix=e5;' +
    'pooling=mean;norm=l2;dim=%d;max-tokens=%d', [ModelRevision, TFile.GetSize(ModelPath),
    FTokenizer.Sha256, FDimension, E5MaxTokens]);
end;

destructor TE5TextEmbedder.Destroy;
begin
  FSession.Free;
  FRuntime.Free;
  FTokenizer.Free;
  inherited;
end;

function TE5TextEmbedder.RuntimeVersion: string;
begin
  Result := FRuntime.Version;
end;

procedure TE5TextEmbedder.ValidateModel;
var
  I: Integer;
  HasIds, HasMask: Boolean;
  OutInfo: TOrtTensorInfo;
  Found: Boolean;
begin
  HasIds := False;
  HasMask := False;
  FHasTokenTypes := False;
  for I := 0 to High(FSession.InputNames) do
  begin
    if FSession.InputInfo[I].ElementType <> OrtElementInt64 then
      raise ETextEmbedderError.CreateFmt('Incompatible model: input %s is not int64', [FSession.InputNames[I]]);
    if FSession.InputNames[I] = 'input_ids' then
      HasIds := True
    else if FSession.InputNames[I] = 'attention_mask' then
      HasMask := True
    else if FSession.InputNames[I] = 'token_type_ids' then
      FHasTokenTypes := True
    else
      raise ETextEmbedderError.CreateFmt('Incompatible model: unexpected input %s', [FSession.InputNames[I]]);
  end;
  if not (HasIds and HasMask) then
    raise ETextEmbedderError.Create('Incompatible model: input_ids and attention_mask inputs are required');
  Found := False;
  for I := 0 to High(FSession.OutputNames) do
    if FSession.OutputNames[I] = 'last_hidden_state' then
    begin
      OutInfo := FSession.OutputInfo[I];
      Found := True;
    end;
  if not Found then
    raise ETextEmbedderError.Create('Incompatible model: no last_hidden_state output');
  if (OutInfo.ElementType <> OrtElementFloat) or (Length(OutInfo.Dimensions) <> 3) or
    (OutInfo.Dimensions[2] <> FDimension) then
    raise ETextEmbedderError.CreateFmt('Incompatible model: last_hidden_state must be float [batch, tokens, %d]',
      [FDimension]);
end;

function TE5TextEmbedder.Identity: string;
begin
  Result := FIdentity;
end;

function TE5TextEmbedder.Dimension: Integer;
begin
  Result := FDimension;
end;

function TE5TextEmbedder.MaxTokens: Integer;
begin
  Result := E5MaxTokens;
end;

function TE5TextEmbedder.Tokenize(const Text, Subject: string; Policy: TOverlengthPolicy;
  out Embedding: TEmbedding): TArray<Int64>;
begin
  Result := FTokenizer.Encode(Text);
  Embedding.SourceTokenCount := Length(Result);
  Embedding.Truncated := False;
  if Length(Result) > E5MaxTokens then
  begin
    if Policy = olReject then
      raise ETextTooLong.CreateFmt('%s has %d tokens; the model accepts %d',
        [Subject, Length(Result), E5MaxTokens]);
    SetLength(Result, E5MaxTokens);
    Result[E5MaxTokens - 1] := FTokenizer.EosId;
    Embedding.Truncated := True;
  end;
  Embedding.TokenCount := Length(Result);
end;

procedure PadTokenBatch(const Tokens: TArray<TArray<Int64>>; PadId: Int64; out Ids, Mask: TArray<Int64>;
  out Width: Integer);
var
  R, T: Integer;
begin
  Width := 0;
  for R := 0 to High(Tokens) do
    Width := Max(Width, Length(Tokens[R]));
  SetLength(Ids, Length(Tokens) * Width);
  SetLength(Mask, Length(Tokens) * Width);
  for R := 0 to High(Tokens) do
    for T := 0 to Width - 1 do
      if T < Length(Tokens[R]) then
      begin
        Ids[R * Width + T] := Tokens[R][T];
        Mask[R * Width + T] := 1;
      end
      else
      begin
        Ids[R * Width + T] := PadId;
        Mask[R * Width + T] := 0;
      end;
end;

procedure TE5TextEmbedder.EmbedBatch(const Tokens: TArray<TArray<Int64>>; var Results: TArray<TEmbedding>;
  First: Integer);
var
  Rows, Width, R, T, D: Integer;
  Inputs: TArray<TOrtInt64Input>;
  Output: TOrtFloatOutput;
  Sums: TArray<Double>;
  Norm: Double;
  Base: NativeInt;
  Vector: TEmbeddingVector;
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

  Output := FSession.Run(Inputs, 'last_hidden_state');
  if (Length(Output.Shape) <> 3) or (Output.Shape[0] <> Rows) or (Output.Shape[1] <> Width) or
    (Output.Shape[2] <> FDimension) then
    raise ETextEmbedderError.Create('Model returned an unexpected last_hidden_state shape');

  SetLength(Sums, FDimension);
  for R := 0 to Rows - 1 do
  begin
    for D := 0 to FDimension - 1 do
      Sums[D] := 0;
    for T := 0 to Length(Tokens[R]) - 1 do
    begin
      Base := (NativeInt(R) * Width + T) * FDimension;
      for D := 0 to FDimension - 1 do
        Sums[D] := Sums[D] + Output.Data[Base + D];
    end;
    Norm := 0;
    for D := 0 to FDimension - 1 do
    begin
      Sums[D] := Sums[D] / Length(Tokens[R]);
      Norm := Norm + Sqr(Sums[D]);
    end;
    Norm := Sqrt(Norm);
    if not (Norm > 0) or IsInfinite(Norm) then
      raise ETextEmbedderError.Create('Model returned a zero or non-finite vector');
    SetLength(Vector, FDimension);
    for D := 0 to FDimension - 1 do
      Vector[D] := Sums[D] / Norm;
    Results[First + R].Vector := Vector;
    Vector := nil;
  end;
end;

function TE5TextEmbedder.EncodeQuery(const Text: string): TEmbedding;
var
  Results: TArray<TEmbedding>;
begin
  if Trim(Text) = '' then
    raise ETextEmbedderError.Create('Query text is empty');
  SetLength(Results, 1);
  EmbedBatch([Tokenize(E5QueryPrefix + Text, 'Query', olReject, Results[0])], Results, 0);
  Result := Results[0];
end;

function TE5TextEmbedder.EncodePassages(const Texts: TArray<string>; Policy: TOverlengthPolicy;
  const Cancelled: TCancelCheck): TArray<TEmbedding>;
var
  Tokens: TArray<TArray<Int64>>;
  I, First, Count: Integer;
begin
  for I := 0 to High(Texts) do
    if Trim(Texts[I]) = '' then
      raise ETextEmbedderError.CreateFmt('Passage %d is empty', [I]);
  SetLength(Result, Length(Texts));
  SetLength(Tokens, Length(Texts));
  for I := 0 to High(Texts) do
    Tokens[I] := Tokenize(E5PassagePrefix + Texts[I], Format('Passage %d', [I]), Policy, Result[I]);
  First := 0;
  while First < Length(Texts) do
  begin
    if Assigned(Cancelled) and Cancelled() then
      raise EOperationCancelled.Create('Passage encoding was cancelled');
    Count := Min(FBatchSize, Length(Texts) - First);
    EmbedBatch(Copy(Tokens, First, Count), Result, First);
    Inc(First, Count);
  end;
end;

end.
