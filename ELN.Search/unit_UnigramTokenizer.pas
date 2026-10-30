unit unit_UnigramTokenizer;

interface

uses
  System.SysUtils, System.JSON;

type
  ETokenizerError = class(Exception);

  TSpecialToken = record
    Content: string;
    Id: Integer;
  end;
  { Executes a Hugging Face tokenizer.json of the XLM-RoBERTa family:
    Precompiled normalizer followed by a space-run collapse, Metaspace
    pre-tokenizer, Unigram model and a <s> A </s> template. Other
    configurations are refused. }
  TUnigramTokenizer = class
  private
    FCharsmapTrie: TArray<Cardinal>;
    FCharsmapNormalized: TBytes;
    FScores: TArray<Double>;
    FNodeLabel: TArray<Byte>;
    FNodeChild: TArray<Integer>;
    FNodeSibling: TArray<Integer>;
    FNodeValue: TArray<Integer>;
    FNodeCount: Integer;
    FRootChild: array[Byte] of Integer;
    FSpecialTokens: TArray<TSpecialToken>;
    FUnkId: Integer;
    FBosId: Integer;
    FEosId: Integer;
    FPadId: Integer;
    FMinScore: Double;
    FSha256: string;
    FSpaceId: Int64;
    procedure LoadNormalizer(Normalizer: TJSONObject);
    procedure LoadPreTokenizer(PreTokenizer: TJSONObject);
    procedure LoadModel(Model: TJSONObject);
    procedure LoadAddedTokens(Added: TJSONArray);
    procedure LoadPostProcessor(Post: TJSONObject);
    function NewNode(Lbl: Byte): Integer;
    procedure AddPiece(const Piece: UTF8String; Id: Integer);
    function CharsmapLookup(const Data: TBytes; Start, Count: Integer; out Value: Integer): Boolean;
    procedure AppendNormalized(var Output: TBytes; var Len: Integer; Value: Integer);
    function Normalize(const Text: string): TBytes;
    procedure EncodeWord(const Bytes: TBytes; Start, Stop: Integer; var Ids: TArray<Int64>; var Count: Integer);
    function PairContent(const Text: string; MaxTokens: Integer): TArray<Int64>;
    procedure EncodeSegment(const Text: string; var Ids: TArray<Int64>; var Count: Integer);
  public
    constructor CreateFromFile(const Path: string);
    function EncodeContent(const Text: string): TArray<Int64>;
    function Encode(const Text: string): TArray<Int64>;
    function EncodePair(const A, B: string; MaxTokens: Integer): TArray<Int64>;
    property UnkId: Integer read FUnkId;
    property BosId: Integer read FBosId;
    property EosId: Integer read FEosId;
    property PadId: Integer read FPadId;
    property Sha256: string read FSha256;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Character, System.NetEncoding, System.Hash, System.Math,
  System.Generics.Collections;

const
  UnknownPenalty = 10.0;
  PairSpecialTokens = 4;
  PairFirstMaxTokens = 64;
  MetaspaceByte0 = $E2;
  MetaspaceByte1 = $96;
  MetaspaceByte2 = $81;

function RequireObject(Parent: TJSONObject; const Name: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := Parent.GetValue(Name);
  if not (V is TJSONObject) then
    raise ETokenizerError.CreateFmt('tokenizer.json: "%s" is missing or is not an object', [Name]);
  Result := TJSONObject(V);
end;

function RequireString(Parent: TJSONObject; const Name: string): string;
var
  V: TJSONValue;
begin
  V := Parent.GetValue(Name);
  if not (V is TJSONString) then
    raise ETokenizerError.CreateFmt('tokenizer.json: "%s" is missing or is not a string', [Name]);
  Result := TJSONString(V).Value;
end;

function OptionalBool(Parent: TJSONObject; const Name: string; Default: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := Parent.GetValue(Name);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    Result := Default;
end;

procedure Unsupported(const What: string);
begin
  raise ETokenizerError.CreateFmt('Unsupported tokenizer configuration: %s', [What]);
end;

function Utf8Length(Lead: Byte): Integer;
begin
  if Lead < $80 then
    Result := 1
  else if Lead >= $F0 then
    Result := 4
  else if Lead >= $E0 then
    Result := 3
  else if Lead >= $C0 then
    Result := 2
  else
    Result := 1;
end;

function EncodeUtf8(CodePoint: Cardinal; var Buffer: array of Byte): Integer;
begin
  if CodePoint < $80 then
  begin
    Buffer[0] := CodePoint;
    Result := 1;
  end
  else if CodePoint < $800 then
  begin
    Buffer[0] := $C0 or (CodePoint shr 6);
    Buffer[1] := $80 or (CodePoint and $3F);
    Result := 2;
  end
  else if CodePoint < $10000 then
  begin
    Buffer[0] := $E0 or (CodePoint shr 12);
    Buffer[1] := $80 or ((CodePoint shr 6) and $3F);
    Buffer[2] := $80 or (CodePoint and $3F);
    Result := 3;
  end
  else
  begin
    Buffer[0] := $F0 or (CodePoint shr 18);
    Buffer[1] := $80 or ((CodePoint shr 12) and $3F);
    Buffer[2] := $80 or ((CodePoint shr 6) and $3F);
    Buffer[3] := $80 or (CodePoint and $3F);
    Result := 4;
  end;
end;

function DecodeCodePoints(const Text: string): TArray<Cardinal>;
var
  I, N: Integer;
  C: Char;
begin
  SetLength(Result, Length(Text));
  N := 0;
  I := 1;
  while I <= Length(Text) do
  begin
    C := Text[I];
    if C.IsHighSurrogate and (I < Length(Text)) and Text[I + 1].IsLowSurrogate then
    begin
      Result[N] := Char.ConvertToUtf32(C, Text[I + 1]);
      Inc(I, 2);
    end
    else
    begin
      if C.IsSurrogate then
        Result[N] := $FFFD
      else
        Result[N] := Ord(C);
      Inc(I);
    end;
    Inc(N);
  end;
  SetLength(Result, N);
end;

type
  TGraphemeClass = (gcOther, gcCR, gcLF, gcControl, gcExtend, gcSpacingMark, gcPrepend);

{ Approximation of UAX #29 with Delphi RTL categories. Hangul, regional
  indicator and emoji rules and part of the Prepend set are missing; they
  mostly affect clusters of 6 or more UTF-8 bytes, which the Precompiled
  normalizer maps per code point. Parity is checked by the reference fixtures. }
function GraphemeClass(CodePoint: Cardinal): TGraphemeClass;
begin
  case CodePoint of
    $0D: Exit(gcCR);
    $0A: Exit(gcLF);
    $200C, $200D, $FF9E, $FF9F, $1F3FB..$1F3FF, $E0020..$E007F: Exit(gcExtend);
    $0600..$0605, $06DD, $070F, $0890..$0891, $08E2, $110BD, $110CD: Exit(gcPrepend);
  end;
  case Char.GetUnicodeCategory(UCS4Char(CodePoint)) of
    TUnicodeCategory.ucControl, TUnicodeCategory.ucFormat,
    TUnicodeCategory.ucLineSeparator, TUnicodeCategory.ucParagraphSeparator:
      Result := gcControl;
    TUnicodeCategory.ucNonSpacingMark, TUnicodeCategory.ucEnclosingMark:
      Result := gcExtend;
    TUnicodeCategory.ucCombiningMark:
      Result := gcSpacingMark;
  else
    Result := gcOther;
  end;
end;

function IsGraphemeBreak(Prev, Next: TGraphemeClass): Boolean;
begin
  if (Prev = gcCR) and (Next = gcLF) then
    Exit(False);
  if Prev in [gcCR, gcLF, gcControl] then
    Exit(True);
  if Next in [gcCR, gcLF, gcControl] then
    Exit(True);
  if Next in [gcExtend, gcSpacingMark] then
    Exit(False);
  Result := Prev <> gcPrepend;
end;

{ TUnigramTokenizer }

constructor TUnigramTokenizer.CreateFromFile(const Path: string);
var
  Data: TBytes;
  Root: TJSONValue;
  Obj: TJSONObject;
  Hash: THashSHA2;
  V: TJSONValue;
  Ids: TArray<Int64>;
begin
  inherited Create;
  if not TFile.Exists(Path) then
    raise ETokenizerError.CreateFmt('Tokenizer file not found: %s', [Path]);
  Data := TFile.ReadAllBytes(Path);
  Hash := THashSHA2.Create;
  Hash.Update(Data);
  FSha256 := UpperCase(Hash.HashAsString);
  Root := TJSONObject.ParseJSONValue(Data, 0, True);
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    raise ETokenizerError.CreateFmt('Tokenizer file is not a JSON object: %s', [Path]);
  end;
  try
    Obj := TJSONObject(Root);
    V := Obj.GetValue('truncation');
    if (V <> nil) and not (V is TJSONNull) then
      Unsupported('truncation must be null; length policy belongs to the embedder');
    LoadModel(RequireObject(Obj, 'model'));
    LoadNormalizer(RequireObject(Obj, 'normalizer'));
    LoadPreTokenizer(RequireObject(Obj, 'pre_tokenizer'));
    V := Obj.GetValue('added_tokens');
    if not (V is TJSONArray) then
      Unsupported('added_tokens missing');
    LoadAddedTokens(TJSONArray(V));
    LoadPostProcessor(RequireObject(Obj, 'post_processor'));
  finally
    Root.Free;
  end;
  FSpaceId := -1;
  Ids := EncodeContent(' ');
  if Length(Ids) = 1 then
    FSpaceId := Ids[0];
end;

procedure TUnigramTokenizer.LoadNormalizer(Normalizer: TJSONObject);
var
  Items: TJSONValue;
  First, Second, Pattern: TJSONObject;
  Blob: TBytes;
  TrieBytes: Cardinal;
begin
  if RequireString(Normalizer, 'type') <> 'Sequence' then
    Unsupported('normalizer must be a Sequence');
  Items := Normalizer.GetValue('normalizers');
  if not (Items is TJSONArray) or (TJSONArray(Items).Count <> 2) then
    Unsupported('normalizer must be Sequence[Precompiled, Replace]');
  if not (TJSONArray(Items).Items[0] is TJSONObject) or not (TJSONArray(Items).Items[1] is TJSONObject) then
    Unsupported('normalizer entries must be objects');
  First := TJSONObject(TJSONArray(Items).Items[0]);
  Second := TJSONObject(TJSONArray(Items).Items[1]);
  if RequireString(First, 'type') <> 'Precompiled' then
    Unsupported('first normalizer must be Precompiled');
  if (RequireString(Second, 'type') <> 'Replace') or (RequireString(Second, 'content') <> ' ') then
    Unsupported('second normalizer must replace runs of spaces with one space');
  Pattern := RequireObject(Second, 'pattern');
  if (Pattern.GetValue('Regex') = nil) or (RequireString(Pattern, 'Regex') <> ' {2,}') then
    Unsupported('second normalizer pattern must be the regex " {2,}"');

  Blob := TNetEncoding.Base64.DecodeStringToBytes(RequireString(First, 'precompiled_charsmap'));
  if Length(Blob) < 4 then
    raise ETokenizerError.Create('precompiled_charsmap is truncated');
  Move(Blob[0], TrieBytes, 4);
  if (TrieBytes mod 4 <> 0) or (TrieBytes = 0) or (Int64(TrieBytes) + 4 > Length(Blob)) then
    raise ETokenizerError.Create('precompiled_charsmap has an invalid trie size');
  SetLength(FCharsmapTrie, TrieBytes div 4);
  Move(Blob[4], FCharsmapTrie[0], TrieBytes);
  FCharsmapNormalized := Copy(Blob, 4 + TrieBytes, Length(Blob) - 4 - Integer(TrieBytes));
end;

procedure TUnigramTokenizer.LoadPreTokenizer(PreTokenizer: TJSONObject);
var
  V: TJSONValue;
begin
  if RequireString(PreTokenizer, 'type') <> 'Metaspace' then
    Unsupported('pre_tokenizer must be Metaspace');
  if RequireString(PreTokenizer, 'replacement') <> #$2581 then
    Unsupported('Metaspace replacement must be U+2581');
  V := PreTokenizer.GetValue('prepend_scheme');
  if V <> nil then
  begin
    if not (V is TJSONString) or (TJSONString(V).Value <> 'always') then
      Unsupported('Metaspace prepend_scheme must be "always"');
  end
  else if not OptionalBool(PreTokenizer, 'add_prefix_space', False) then
    Unsupported('Metaspace add_prefix_space must be true');
  if not OptionalBool(PreTokenizer, 'split', True) then
    Unsupported('Metaspace split must be true');
end;

function TUnigramTokenizer.NewNode(Lbl: Byte): Integer;
begin
  if FNodeCount = Length(FNodeLabel) then
  begin
    SetLength(FNodeLabel, FNodeCount * 2);
    SetLength(FNodeChild, FNodeCount * 2);
    SetLength(FNodeSibling, FNodeCount * 2);
    SetLength(FNodeValue, FNodeCount * 2);
  end;
  Result := FNodeCount;
  FNodeLabel[Result] := Lbl;
  FNodeChild[Result] := -1;
  FNodeSibling[Result] := -1;
  FNodeValue[Result] := -1;
  Inc(FNodeCount);
end;

procedure TUnigramTokenizer.AddPiece(const Piece: UTF8String; Id: Integer);
var
  Node, Child, I: Integer;
  B: Byte;
begin
  B := Byte(Piece[1]);
  Node := FRootChild[B];
  if Node < 0 then
  begin
    Node := NewNode(B);
    FRootChild[B] := Node;
  end;
  for I := 2 to Length(Piece) do
  begin
    B := Byte(Piece[I]);
    Child := FNodeChild[Node];
    while (Child >= 0) and (FNodeLabel[Child] <> B) do
      Child := FNodeSibling[Child];
    if Child < 0 then
    begin
      Child := NewNode(B);
      FNodeSibling[Child] := FNodeChild[Node];
      FNodeChild[Node] := Child;
    end;
    Node := Child;
  end;
  if FNodeValue[Node] < 0 then
    FNodeValue[Node] := Id;
end;

procedure TUnigramTokenizer.LoadModel(Model: TJSONObject);
var
  Vocab, Entry: TJSONValue;
  Pair: TJSONArray;
  Piece: string;
  I: Integer;
  V: TJSONValue;
begin
  if RequireString(Model, 'type') <> 'Unigram' then
    Unsupported('model must be Unigram');
  if OptionalBool(Model, 'byte_fallback', False) then
    Unsupported('Unigram byte_fallback is not supported');
  V := Model.GetValue('unk_id');
  if not (V is TJSONNumber) then
    Unsupported('Unigram unk_id is required');
  FUnkId := TJSONNumber(V).AsInt;
  Vocab := Model.GetValue('vocab');
  if not (Vocab is TJSONArray) or (TJSONArray(Vocab).Count = 0) then
    Unsupported('Unigram vocab is missing');
  if (FUnkId < 0) or (FUnkId >= TJSONArray(Vocab).Count) then
    Unsupported('Unigram unk_id is outside the vocabulary');

  for I := Low(FRootChild) to High(FRootChild) do
    FRootChild[I] := -1;
  FNodeCount := 0;
  SetLength(FNodeLabel, 1 shl 20);
  SetLength(FNodeChild, 1 shl 20);
  SetLength(FNodeSibling, 1 shl 20);
  SetLength(FNodeValue, 1 shl 20);
  SetLength(FScores, TJSONArray(Vocab).Count);
  FMinScore := Infinity;
  for I := 0 to TJSONArray(Vocab).Count - 1 do
  begin
    Entry := TJSONArray(Vocab).Items[I];
    if not (Entry is TJSONArray) or (TJSONArray(Entry).Count <> 2) or
      not (TJSONArray(Entry).Items[0] is TJSONString) or not (TJSONArray(Entry).Items[1] is TJSONNumber) then
      raise ETokenizerError.CreateFmt('Unigram vocab entry %d is malformed', [I]);
    Pair := TJSONArray(Entry);
    Piece := TJSONString(Pair.Items[0]).Value;
    FScores[I] := TJSONNumber(Pair.Items[1]).AsDouble;
    if FScores[I] < FMinScore then
      FMinScore := FScores[I];
    if Piece <> '' then
      AddPiece(UTF8String(Piece), I);
  end;
end;

procedure TUnigramTokenizer.LoadAddedTokens(Added: TJSONArray);
var
  I: Integer;
  Token: TJSONObject;
  Special: TSpecialToken;
  V: TJSONValue;
begin
  for I := 0 to Added.Count - 1 do
  begin
    if not (Added.Items[I] is TJSONObject) then
      Unsupported('added token is not an object');
    Token := TJSONObject(Added.Items[I]);
    if not OptionalBool(Token, 'special', False) then
      Unsupported('non-special added tokens');
    if OptionalBool(Token, 'normalized', True) or OptionalBool(Token, 'lstrip', False) or
      OptionalBool(Token, 'rstrip', False) or OptionalBool(Token, 'single_word', False) then
      Unsupported('added token flags other than special, not normalized and not stripped');
    V := Token.GetValue('id');
    if not (V is TJSONNumber) or (TJSONNumber(V).AsInt < 0) or (TJSONNumber(V).AsInt >= Length(FScores)) then
      Unsupported('added token id outside the vocabulary');
    Special.Id := TJSONNumber(V).AsInt;
    Special.Content := RequireString(Token, 'content');
    if Special.Content = '' then
      Unsupported('empty added token');
    FSpecialTokens := FSpecialTokens + [Special];
  end;
end;

procedure TUnigramTokenizer.LoadPostProcessor(Post: TJSONObject);
var
  Single: TJSONValue;
  Items: TJSONArray;
  Specials: TJSONObject;

  function SpecialId(Item: TJSONValue): Integer;
  var
    Name: string;
    Spec: TJSONObject;
    Ids: TJSONValue;
  begin
    if not (Item is TJSONObject) or (TJSONObject(Item).GetValue('SpecialToken') = nil) then
      Unsupported('post_processor single template must be <s> A </s>');
    Name := RequireString(RequireObject(TJSONObject(Item), 'SpecialToken'), 'id');
    Spec := RequireObject(Specials, Name);
    Ids := Spec.GetValue('ids');
    if not (Ids is TJSONArray) or (TJSONArray(Ids).Count <> 1) or not (TJSONArray(Ids).Items[0] is TJSONNumber) then
      Unsupported('post_processor special token must map to one id');
    Result := TJSONNumber(TJSONArray(Ids).Items[0]).AsInt;
  end;

var
  I: Integer;
begin
  if RequireString(Post, 'type') <> 'TemplateProcessing' then
    Unsupported('post_processor must be TemplateProcessing');
  Single := Post.GetValue('single');
  if not (Single is TJSONArray) or (TJSONArray(Single).Count <> 3) then
    Unsupported('post_processor single template must be <s> A </s>');
  Items := TJSONArray(Single);
  Specials := RequireObject(Post, 'special_tokens');
  if not (Items.Items[1] is TJSONObject) or (TJSONObject(Items.Items[1]).GetValue('Sequence') = nil) then
    Unsupported('post_processor single template must be <s> A </s>');
  FBosId := SpecialId(Items.Items[0]);
  FEosId := SpecialId(Items.Items[2]);
  FPadId := -1;
  for I := 0 to High(FSpecialTokens) do
    if FSpecialTokens[I].Content = '<pad>' then
      FPadId := FSpecialTokens[I].Id;
  if FPadId < 0 then
    Unsupported('no <pad> token');
end;

function TUnigramTokenizer.CharsmapLookup(const Data: TBytes; Start, Count: Integer; out Value: Integer): Boolean;
var
  NodePos: Cardinal;
  U: Cardinal;
  I: Integer;
  C: Byte;

  function UnitOffset(X: Cardinal): Cardinal; inline;
  begin
    Result := (X shr 10) shl ((X and (1 shl 9)) shr 6);
  end;

  function UnitAt(Pos: Cardinal): Cardinal;
  begin
    if Pos >= Cardinal(Length(FCharsmapTrie)) then
      raise ETokenizerError.Create('precompiled_charsmap trie index out of range');
    Result := FCharsmapTrie[Pos];
  end;

begin
  Result := False;
  Value := -1;
  U := UnitAt(0);
  NodePos := UnitOffset(U);
  for I := Start to Start + Count - 1 do
  begin
    C := Data[I];
    if C = 0 then
      Exit;
    NodePos := NodePos xor C;
    U := UnitAt(NodePos);
    if (U and ($80000000 or $FF)) <> C then
      Exit;
    NodePos := NodePos xor UnitOffset(U);
    if ((U shr 8) and 1) = 1 then
    begin
      Value := Integer(UnitAt(NodePos) and $7FFFFFFF);
      Exit(True);
    end;
  end;
end;

procedure EnsureCapacity(var Output: TBytes; Needed: Integer);
begin
  if Needed > Length(Output) then
    SetLength(Output, Needed * 2 + 16);
end;

procedure TUnigramTokenizer.AppendNormalized(var Output: TBytes; var Len: Integer; Value: Integer);
var
  Stop: Integer;
begin
  if (Value < 0) or (Value > Length(FCharsmapNormalized)) then
    raise ETokenizerError.Create('precompiled_charsmap value out of range');
  Stop := Value;
  while (Stop < Length(FCharsmapNormalized)) and (FCharsmapNormalized[Stop] <> 0) do
    Inc(Stop);
  EnsureCapacity(Output, Len + Stop - Value);
  if Stop > Value then
    Move(FCharsmapNormalized[Value], Output[Len], Stop - Value);
  Inc(Len, Stop - Value);
end;

function TUnigramTokenizer.Normalize(const Text: string): TBytes;
var
  CodePoints: TArray<Cardinal>;
  Classes: TArray<TGraphemeClass>;
  Utf8: TBytes;
  Offsets: TArray<Integer>;
  Buffer: array[0..3] of Byte;
  I, J, N, Len, ClusterStart, ClusterStop, ClusterBytes, Value, W, R: Integer;
  Collapsed: TBytes;
begin
  CodePoints := DecodeCodePoints(Text);
  N := Length(CodePoints);
  SetLength(Classes, N);
  SetLength(Offsets, N + 1);
  SetLength(Utf8, N * 4);
  Len := 0;
  for I := 0 to N - 1 do
  begin
    Classes[I] := GraphemeClass(CodePoints[I]);
    Offsets[I] := Len;
    J := EncodeUtf8(CodePoints[I], Buffer);
    Move(Buffer[0], Utf8[Len], J);
    Inc(Len, J);
  end;
  Offsets[N] := Len;

  SetLength(Result, Len + 16);
  Len := 0;
  ClusterStart := 0;
  while ClusterStart < N do
  begin
    ClusterStop := ClusterStart + 1;
    while (ClusterStop < N) and not IsGraphemeBreak(Classes[ClusterStop - 1], Classes[ClusterStop]) do
      Inc(ClusterStop);
    ClusterBytes := Offsets[ClusterStop] - Offsets[ClusterStart];
    if (ClusterBytes < 6) and CharsmapLookup(Utf8, Offsets[ClusterStart], ClusterBytes, Value) then
      AppendNormalized(Result, Len, Value)
    else
      for I := ClusterStart to ClusterStop - 1 do
        if CharsmapLookup(Utf8, Offsets[I], Offsets[I + 1] - Offsets[I], Value) then
          AppendNormalized(Result, Len, Value)
        else
        begin
          EnsureCapacity(Result, Len + 4);
          Move(Utf8[Offsets[I]], Result[Len], Offsets[I + 1] - Offsets[I]);
          Inc(Len, Offsets[I + 1] - Offsets[I]);
        end;
    ClusterStart := ClusterStop;
  end;

  SetLength(Collapsed, Len);
  W := 0;
  R := 0;
  while R < Len do
  begin
    Collapsed[W] := Result[R];
    Inc(W);
    if Result[R] = $20 then
      while (R + 1 < Len) and (Result[R + 1] = $20) do
        Inc(R);
    Inc(R);
  end;
  SetLength(Collapsed, W);
  Result := Collapsed;
end;

procedure TUnigramTokenizer.EncodeWord(const Bytes: TBytes; Start, Stop: Integer; var Ids: TArray<Int64>;
  var Count: Integer);
var
  Size, Pos, CharLen, KeyPos, Node, I, EndsAt, From, PendingUnk: Integer;
  BestScore: TArray<Double>;
  BestFrom: TArray<Integer>;
  BestId: TArray<Integer>;
  Base, Candidate, UnkScore: Double;
  HasSingle: Boolean;
  Path: TArray<Integer>;
  PathLen: Integer;
begin
  Size := Stop - Start;
  if Size <= 0 then
    Exit;
  SetLength(BestScore, Size + 1);
  SetLength(BestFrom, Size + 1);
  SetLength(BestId, Size + 1);
  for I := 0 to Size do
    BestFrom[I] := -1;
  BestScore[0] := 0;
  UnkScore := FMinScore - UnknownPenalty;
  Pos := 0;
  while Pos < Size do
  begin
    Base := BestScore[Pos];
    CharLen := Utf8Length(Bytes[Start + Pos]);
    if Pos + CharLen > Size then
      CharLen := Size - Pos;
    HasSingle := False;
    Node := FRootChild[Bytes[Start + Pos]];
    KeyPos := Pos + 1;
    while Node >= 0 do
    begin
      if FNodeValue[Node] >= 0 then
      begin
        Candidate := FScores[FNodeValue[Node]] + Base;
        if (BestFrom[KeyPos] < 0) or (Candidate > BestScore[KeyPos]) then
        begin
          BestScore[KeyPos] := Candidate;
          BestFrom[KeyPos] := Pos;
          BestId[KeyPos] := FNodeValue[Node];
        end;
        if KeyPos - Pos = CharLen then
          HasSingle := True;
      end;
      if KeyPos >= Size then
        Break;
      Node := FNodeChild[Node];
      while (Node >= 0) and (FNodeLabel[Node] <> Bytes[Start + KeyPos]) do
        Node := FNodeSibling[Node];
      Inc(KeyPos);
    end;
    if not HasSingle then
    begin
      Candidate := UnkScore + Base;
      if (BestFrom[Pos + CharLen] < 0) or (Candidate > BestScore[Pos + CharLen]) then
      begin
        BestScore[Pos + CharLen] := Candidate;
        BestFrom[Pos + CharLen] := Pos;
        BestId[Pos + CharLen] := FUnkId;
      end;
    end;
    Inc(Pos, CharLen);
  end;

  SetLength(Path, Size);
  PathLen := 0;
  EndsAt := Size;
  PendingUnk := 0;
  while EndsAt > 0 do
  begin
    From := BestFrom[EndsAt];
    if From < 0 then
      raise ETokenizerError.Create('Unigram lattice has no path');
    if BestId[EndsAt] = FUnkId then
      Inc(PendingUnk)
    else
    begin
      if PendingUnk > 0 then
      begin
        Path[PathLen] := FUnkId;
        Inc(PathLen);
        PendingUnk := 0;
      end;
      Path[PathLen] := BestId[EndsAt];
      Inc(PathLen);
    end;
    EndsAt := From;
  end;
  if PendingUnk > 0 then
  begin
    Path[PathLen] := FUnkId;
    Inc(PathLen);
  end;

  if Count + PathLen > Length(Ids) then
    SetLength(Ids, (Count + PathLen) * 2);
  for I := PathLen - 1 downto 0 do
  begin
    Ids[Count] := Path[I];
    Inc(Count);
  end;
end;

procedure TUnigramTokenizer.EncodeSegment(const Text: string; var Ids: TArray<Int64>; var Count: Integer);
var
  Normalized, Spaced: TBytes;
  I, Len, WordStart: Integer;
begin
  Normalized := Normalize(Text);
  if Length(Normalized) = 0 then
    Exit;
  SetLength(Spaced, Length(Normalized) * 3 + 3);
  Len := 0;
  if not ((Length(Normalized) >= 3) and (Normalized[0] = MetaspaceByte0) and
    (Normalized[1] = MetaspaceByte1) and (Normalized[2] = MetaspaceByte2)) and (Normalized[0] <> $20) then
  begin
    Spaced[0] := MetaspaceByte0;
    Spaced[1] := MetaspaceByte1;
    Spaced[2] := MetaspaceByte2;
    Len := 3;
  end;
  for I := 0 to High(Normalized) do
    if Normalized[I] = $20 then
    begin
      Spaced[Len] := MetaspaceByte0;
      Spaced[Len + 1] := MetaspaceByte1;
      Spaced[Len + 2] := MetaspaceByte2;
      Inc(Len, 3);
    end
    else
    begin
      Spaced[Len] := Normalized[I];
      Inc(Len);
    end;

  WordStart := 0;
  I := 3;
  while I + 2 < Len do
  begin
    if (Spaced[I] = MetaspaceByte0) and (Spaced[I + 1] = MetaspaceByte1) and (Spaced[I + 2] = MetaspaceByte2) then
    begin
      EncodeWord(Spaced, WordStart, I, Ids, Count);
      WordStart := I;
      Inc(I, 3);
    end
    else
      Inc(I);
  end;
  EncodeWord(Spaced, WordStart, Len, Ids, Count);
end;

function TUnigramTokenizer.EncodeContent(const Text: string): TArray<Int64>;
var
  Count, Pos, BestPos, BestLen, BestId, I: Integer;
  NextPos: TArray<Integer>;
begin
  SetLength(Result, Length(Text) + 8);
  SetLength(NextPos, Length(FSpecialTokens));
  Count := 0;
  Pos := 1;
  while Pos <= Length(Text) do
  begin
    BestPos := 0;
    BestLen := 0;
    BestId := -1;
    for I := 0 to High(FSpecialTokens) do
    begin
      if NextPos[I] < Pos then
      begin
        NextPos[I] := System.Pos(FSpecialTokens[I].Content, Text, Pos);
        if NextPos[I] = 0 then
          NextPos[I] := MaxInt;
      end;
      if (NextPos[I] <> MaxInt) and ((BestPos = 0) or (NextPos[I] < BestPos) or
        ((NextPos[I] = BestPos) and (Length(FSpecialTokens[I].Content) > BestLen))) then
      begin
        BestPos := NextPos[I];
        BestLen := Length(FSpecialTokens[I].Content);
        BestId := FSpecialTokens[I].Id;
      end;
    end;
    if BestPos = 0 then
    begin
      EncodeSegment(Copy(Text, Pos, MaxInt), Result, Count);
      Break;
    end;
    if BestPos > Pos then
      EncodeSegment(Copy(Text, Pos, BestPos - Pos), Result, Count);
    if Count + 1 > Length(Result) then
      SetLength(Result, (Count + 1) * 2);
    Result[Count] := BestId;
    Inc(Count);
    Pos := BestPos + BestLen;
  end;
  SetLength(Result, Count);
end;

function TUnigramTokenizer.Encode(const Text: string): TArray<Int64>;
begin
  Result := [Int64(FBosId)] + EncodeContent(Text) + [Int64(FEosId)];
end;

function TUnigramTokenizer.PairContent(const Text: string; MaxTokens: Integer): TArray<Int64>;
begin
  Result := EncodeContent(Text);
  if (Length(Result) > 0) and (Result[High(Result)] = FSpaceId) then
    SetLength(Result, Length(Result) - 1);
  if Length(Result) > MaxTokens then
    SetLength(Result, MaxTokens);
end;

function TUnigramTokenizer.EncodePair(const A, B: string; MaxTokens: Integer): TArray<Int64>;
var
  First, Second: TArray<Int64>;
begin
  if MaxTokens < PairSpecialTokens + 1 then
    raise ETokenizerError.CreateFmt('A pair needs at least %d tokens', [PairSpecialTokens + 1]);
  First := PairContent(A, Min(PairFirstMaxTokens, MaxTokens - PairSpecialTokens));
  Second := PairContent(B, MaxTokens - PairSpecialTokens - Length(First));
  Result := [Int64(FBosId)] + First + [Int64(FEosId), Int64(FEosId)] + Second + [Int64(FEosId)];
end;

end.
