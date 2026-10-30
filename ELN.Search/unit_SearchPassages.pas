unit unit_SearchPassages;

interface

uses
  System.SysUtils, System.Generics.Collections, unit_TextEmbedder;

type
  TPassageField = (pfItemTitle, pfItemDescription, pfItemProperties, pfItemTags,
    pfEntryTitle, pfProtocolForm, pfValueDescription, pfFileName, pfFileText);

  TSearchPassage = record
    Key: string;
    ProjectId: Integer;
    ItemId: Integer;
    FileId: Int64;
    Field: TPassageField;
    Text: string;
    Context: string;
    ContentHash: string;
  end;

  TSearchPassages = TArray<TSearchPassage>;

  TFileTextRequest = record
    FileId: Int64;
    ItemId, ProjectId: Integer;
    Ext, RelativePath, Context: string;
  end;

  TItemContextEntry = record
    ItemId: Integer;
    PartsJson: string;
    class function Make(ItemId: Integer; const PartsJson: string): TItemContextEntry; static;
  end;

  TSearchSnapshot = record
    Passages: TSearchPassages;
    Files: TArray<TFileTextRequest>;
    ItemContexts: TArray<TItemContextEntry>;
  end;

  IFileContentReader = interface
    ['{C3D1A6E4-5B2F-4F0A-8E97-2D6B9A41F7C5}']
    function ReadFile(const RelativePath: string; MaxBytes: Int64; out Bytes: TBytes;
      out Size: Int64): Boolean;
    function TryGetStamp(const RelativePath: string; out Size, LastWrite: Int64): Boolean;
  end;

  ISearchDocumentSource = interface
    ['{5B0E6C1A-3D7F-4E52-9A41-8C2F6D1E7B30}']
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

  TPassageSnapshotSource = class(TInterfacedObject, ISearchDocumentSource)
  private
    FPassages: TSearchPassages;
  public
    constructor Create(const Passages: TSearchPassages);
    function ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
    function IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
  end;

const
  PassageMaxChars = 1200;
  PassageOverlapChars = 150;

procedure AppendTextPassages(Target: TList<TSearchPassage>; const KeyBase: string;
  ProjectId, ItemId: Integer; FileId: Int64; Field: TPassageField; const Text, Context: string);
function FoldSearchText(const S: string): string;
function ChunkText(const Text: string; MaxChars, OverlapChars: Integer): TArray<string>;
function PassageHash(const Text: string): string;
function PassageContentHash(const Context, Text: string): string;
function PassageEmbedText(const Passage: TSearchPassage): string;

implementation

uses
  System.Character, System.Hash;

class function TItemContextEntry.Make(ItemId: Integer; const PartsJson: string): TItemContextEntry;
begin
  Result.ItemId := ItemId;
  Result.PartsJson := PartsJson;
end;

function FoldSearchText(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    case Result[I] of
      'ё': Result[I] := 'е';
      'Ё': Result[I] := 'Е';
    end;
end;

function PassageHash(const Text: string): string;
var
  Hasher: THashSHA2;
begin
  Hasher := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  Hasher.Update(TEncoding.UTF8.GetBytes(Text));
  Result := UpperCase(Hasher.HashAsString);
end;

function PassageContentHash(const Context, Text: string): string;
begin
  if Context = '' then
    Result := PassageHash(Text)
  else
    Result := PassageHash(Context + #10 + Text);
end;

function PassageEmbedText(const Passage: TSearchPassage): string;
begin
  if Passage.Context = '' then
    Result := Passage.Text
  else
    Result := Passage.Context + #10 + Passage.Text;
end;

constructor TPassageSnapshotSource.Create(const Passages: TSearchPassages);
begin
  inherited Create;
  FPassages := Passages;
end;

function TPassageSnapshotSource.ReadSnapshot(const Cancelled: TCancelCheck): TSearchSnapshot;
begin
  Result := Default(TSearchSnapshot);
  Result.Passages := FPassages;
end;

function TPassageSnapshotSource.IsItemLive(ItemId: Integer; out ProjectId: Integer): Boolean;
begin
  raise ENotSupportedException.Create('A passage snapshot cannot tell whether an item is live');
end;

function IsLineBreak(C: Char): Boolean;
begin
  Result := (C = #10) or (C = #13);
end;

function IsBlankLineAt(const Text: string; Index: Integer): Boolean;
var
  P: Integer;
begin
  if not IsLineBreak(Text[Index]) then Exit(False);
  P := Index;
  if (Text[P] = #13) and (P < Length(Text)) and (Text[P + 1] = #10) then Inc(P);
  Inc(P);
  while (P <= Length(Text)) and ((Text[P] = ' ') or (Text[P] = #9)) do Inc(P);
  Result := (P <= Length(Text)) and IsLineBreak(Text[P]);
end;

function FindBlankLineEnd(const Text: string; Pos, Limit: Integer): Integer;
var
  I: Integer;
begin
  for I := Limit downto Pos + 1 do
    if IsBlankLineAt(Text, I) then Exit(I);
  Result := 0;
end;

function FindLineBreakEnd(const Text: string; Pos, Limit: Integer): Integer;
var
  I: Integer;
begin
  for I := Limit downto Pos + 1 do
    if IsLineBreak(Text[I]) then Exit(I);
  Result := 0;
end;

function FindSentenceEnd(const Text: string; Pos, Limit: Integer): Integer;
var
  I: Integer;
begin
  for I := Limit downto Pos + 1 do
    if (Text[I] = ' ') and CharInSet(Text[I - 1], ['.', '!', '?']) then Exit(I);
  Result := 0;
end;

function FindSpaceEnd(const Text: string; Pos, Limit: Integer): Integer;
var
  I: Integer;
begin
  for I := Limit downto Pos + 1 do
    if (Text[I] = ' ') or (Text[I] = #9) then Exit(I);
  Result := 0;
end;

function SkipWhitespace(const Text: string; Index: Integer): Integer;
begin
  Result := Index;
  while (Result <= Length(Text)) and Text[Result].IsWhiteSpace do Inc(Result);
end;

function ChunkText(const Text: string; MaxChars, OverlapChars: Integer): TArray<string>;
var
  Source, Piece: string;
  Pos, Limit, Cut, Next: Integer;
  Overlapped: Boolean;
  Count: Integer;

  procedure Emit(const Chunk: string);
  begin
    Piece := Chunk.Trim;
    if Piece = '' then Exit;
    if Count = Length(Result) then SetLength(Result, Count * 2 + 4);
    Result[Count] := Piece;
    Inc(Count);
  end;

begin
  if (MaxChars < 1) or (OverlapChars < 0) or (OverlapChars >= MaxChars) then
    raise EArgumentException.Create('Invalid chunk size or overlap');
  Result := nil;
  Count := 0;
  Source := Text.Trim;
  Pos := 1;
  while Pos <= Length(Source) do
  begin
    if Length(Source) - Pos + 1 <= MaxChars then
    begin
      Emit(Copy(Source, Pos, MaxInt));
      Break;
    end;
    Limit := Pos + MaxChars;
    Overlapped := False;
    Cut := FindBlankLineEnd(Source, Pos, Limit);
    if Cut = 0 then Cut := FindLineBreakEnd(Source, Pos, Limit);
    if Cut = 0 then Cut := FindSentenceEnd(Source, Pos, Limit);
    if Cut = 0 then
    begin
      Cut := FindSpaceEnd(Source, Pos, Limit);
      Overlapped := True;
    end;
    if Cut = 0 then
    begin
      Cut := Limit;
      if Source[Cut - 1].IsHighSurrogate and (Cut - 1 > Pos) then Dec(Cut);
      Overlapped := True;
    end;
    Emit(Copy(Source, Pos, Cut - Pos));
    if Overlapped then
    begin
      Next := Cut - OverlapChars;
      if (Next > Pos) and Source[Next].IsLowSurrogate then Inc(Next);
      if Next <= Pos then Next := SkipWhitespace(Source, Cut);
    end
    else
      Next := SkipWhitespace(Source, Cut);
    Pos := Next;
  end;
  SetLength(Result, Count);
end;

procedure AppendTextPassages(Target: TList<TSearchPassage>; const KeyBase: string;
  ProjectId, ItemId: Integer; FileId: Int64; Field: TPassageField; const Text, Context: string);
var
  Chunks: TArray<string>;
  Passage: TSearchPassage;
  I: Integer;
begin
  if Text.Trim = '' then Exit;
  Chunks := ChunkText(FoldSearchText(Text), PassageMaxChars, PassageOverlapChars);
  for I := 0 to High(Chunks) do
  begin
    Passage.Key := KeyBase + '#' + IntToStr(I);
    Passage.ProjectId := ProjectId;
    Passage.ItemId := ItemId;
    Passage.FileId := FileId;
    Passage.Field := Field;
    Passage.Text := Chunks[I];
    Passage.Context := Context;
    Passage.ContentHash := PassageContentHash(Context, Chunks[I]);
    Target.Add(Passage);
  end;
end;

end.
