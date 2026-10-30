unit unit_FileTextStage;

interface

uses
  System.SysUtils, unit_SearchPassages, unit_SearchIndexStore, unit_SearchIndexer,
  unit_TextEmbedder, unit_TextExtractors, unit_TextExtractorRegistry;

type
  TFileTextStage = class
  private
    FStore: TSearchIndexStore;
    FRegistry: TTextExtractorRegistry;
    FEnterStore: TProc;
    FLeaveStore: TProc;
    function ResolveFile(const Request: TFileTextRequest; const Extractor: ITextExtractor;
      const Reader: IFileContentReader; const Cancelled: TCancelCheck;
      out Outcome: TExtractOutcome; out Text: string): Boolean;
    procedure ReadCache(FileId: Int64; out Found: Boolean; out Md5, Extractor: string;
      out Outcome: TExtractOutcome; out Text: string; out Size, LastWrite: Int64);
  public
    constructor Create(Store: TSearchIndexStore; Registry: TTextExtractorRegistry);
    function BuildFilePassages(const Files: TArray<TFileTextRequest>;
      const Reader: IFileContentReader; const Cancelled: TCancelCheck;
      const Progress: TSyncProgress): TSearchPassages;
    function CachedFilePassages(const Files: TArray<TFileTextRequest>): TSearchPassages;
    property EnterStore: TProc read FEnterStore write FEnterStore;
    property LeaveStore: TProc read FLeaveStore write FLeaveStore;
  end;

implementation

uses
  System.Generics.Collections, System.Hash;

constructor TFileTextStage.Create(Store: TSearchIndexStore; Registry: TTextExtractorRegistry);
begin
  inherited Create;
  if (Store = nil) or (Registry = nil) then
    raise EArgumentNilException.Create('Store and registry are required');
  FStore := Store;
  FRegistry := Registry;
end;

function ContentMd5(const Bytes: TBytes): string;
var
  Hasher: THashMD5;
begin
  Hasher := THashMD5.Create;
  if Length(Bytes) > 0 then
    Hasher.Update(Bytes);
  Result := UpperCase(Hasher.HashAsString);
end;

procedure RaiseIfCancelled(const Cancelled: TCancelCheck);
begin
  if Assigned(Cancelled) and Cancelled() then
    raise EOperationCancelled.Create('File text extraction was cancelled');
end;

procedure TFileTextStage.ReadCache(FileId: Int64; out Found: Boolean; out Md5, Extractor: string;
  out Outcome: TExtractOutcome; out Text: string; out Size, LastWrite: Int64);
begin
  if Assigned(FEnterStore) then FEnterStore();
  try
    Found := FStore.ReadFileText(FileId, Md5, Extractor, Outcome, Text, Size, LastWrite);
  finally
    if Assigned(FLeaveStore) then FLeaveStore();
  end;
end;

function TFileTextStage.CachedFilePassages(const Files: TArray<TFileTextRequest>): TSearchPassages;
var
  Passages: TList<TSearchPassage>;
  Request: TFileTextRequest;
  Found: Boolean;
  Md5, Extractor, Text: string;
  Outcome: TExtractOutcome;
  Size, LastWrite: Int64;
begin
  Passages := TList<TSearchPassage>.Create;
  try
    for Request in Files do
    begin
      ReadCache(Request.FileId, Found, Md5, Extractor, Outcome, Text, Size, LastWrite);
      if Found and (Outcome in [eoText, eoLimitReached]) then
        AppendTextPassages(Passages, 'file:' + IntToStr(Request.FileId) + ':text',
          Request.ProjectId, Request.ItemId, Request.FileId, pfFileText, Text, Request.Context);
    end;
    Result := Passages.ToArray;
  finally
    Passages.Free;
  end;
end;

function TryReadFile(const Reader: IFileContentReader; const RelativePath: string;
  out Bytes: TBytes; out Size: Int64): Boolean;
begin
  try
    Result := Reader.ReadFile(RelativePath, FileTextMaxBytes, Bytes, Size);
  except
    on Exception do
    begin
      Bytes := nil;
      Result := False;
    end;
  end;
end;

function TryGetStamp(const Reader: IFileContentReader; const RelativePath: string;
  out Size, LastWrite: Int64): Boolean;
begin
  try
    Result := Reader.TryGetStamp(RelativePath, Size, LastWrite);
  except
    on Exception do
      Result := False;
  end;
  if not Result then
  begin
    Size := -1;
    LastWrite := 0;
  end;
end;

function TFileTextStage.ResolveFile(const Request: TFileTextRequest;
  const Extractor: ITextExtractor; const Reader: IFileContentReader;
  const Cancelled: TCancelCheck; out Outcome: TExtractOutcome; out Text: string): Boolean;
var
  Bytes: TBytes;
  Size, StampSize, StampWrite, CachedSize, CachedWrite: Int64;
  Md5, ExtractorKey, CachedMd5, CachedExtractor, CachedText, Detail: string;
  CachedOutcome: TExtractOutcome;
  Found, HaveStamp, Cacheable: Boolean;
  Extracted: TExtractResult;
begin
  Outcome := eoNoText;
  Text := '';
  ExtractorKey := Extractor.Id + ':' + IntToStr(Extractor.Version);
  HaveStamp := TryGetStamp(Reader, Request.RelativePath, StampSize, StampWrite);
  ReadCache(Request.FileId, Found, CachedMd5, CachedExtractor, CachedOutcome, CachedText,
    CachedSize, CachedWrite);
  if HaveStamp and Found and (CachedExtractor = ExtractorKey) and
    (CachedSize = StampSize) and (CachedWrite = StampWrite) then
  begin
    Outcome := CachedOutcome;
    Text := CachedText;
    Exit(True);
  end;
  if not TryReadFile(Reader, Request.RelativePath, Bytes, Size) then
    Exit(False);
  if Size > FileTextMaxBytes then
    Md5 := 'size:' + IntToStr(Size)
  else
    Md5 := ContentMd5(Bytes);
  if Found and (CachedMd5 = Md5) and (CachedExtractor = ExtractorKey) then
  begin
    Outcome := CachedOutcome;
    Text := CachedText;
    if HaveStamp then
    begin
      if Assigned(FEnterStore) then FEnterStore();
      try
        FStore.UpdateFileStamp(Request.FileId, StampSize, StampWrite);
      finally
        if Assigned(FLeaveStore) then FLeaveStore();
      end;
    end;
    Exit(True);
  end;
  Detail := '';
  Cacheable := True;
  if Size > FileTextMaxBytes then
  begin
    Outcome := eoTooLarge;
    Detail := 'file is larger than the read limit';
  end
  else
  begin
    try
      Extracted := Extractor.Extract(Bytes, Cancelled);
      Outcome := Extracted.Outcome;
      Detail := Extracted.Detail;
      if Outcome in [eoText, eoLimitReached] then
        Text := Extracted.Text;
      Cacheable := Outcome <> eoExtractorUnavailable;
    except
      on EOperationCancelled do
        raise;
      on Exception do
      begin
        Cacheable := False;
        Outcome := eoNoText;
      end;
    end;
  end;
  if Cacheable then
  begin
    if Assigned(FEnterStore) then FEnterStore();
    try
      FStore.WriteFileText(Request.FileId, Md5, ExtractorKey, Outcome, Detail, Text,
        StampSize, StampWrite);
    finally
      if Assigned(FLeaveStore) then FLeaveStore();
    end;
  end;
  Result := True;
end;

function TFileTextStage.BuildFilePassages(const Files: TArray<TFileTextRequest>;
  const Reader: IFileContentReader; const Cancelled: TCancelCheck;
  const Progress: TSyncProgress): TSearchPassages;
var
  Passages: TList<TSearchPassage>;
  LiveIds: TArray<Int64>;
  Request: TFileTextRequest;
  Extractor: ITextExtractor;
  Text: string;
  Outcome: TExtractOutcome;
  Done, I: Integer;
begin
  if (Reader = nil) and (Length(Files) > 0) then
    raise EArgumentNilException.Create('A file content reader is required');
  Passages := TList<TSearchPassage>.Create;
  try
    SetLength(LiveIds, Length(Files));
    for I := 0 to High(Files) do
      LiveIds[I] := Files[I].FileId;
    Done := 0;
    for Request in Files do
    begin
      RaiseIfCancelled(Cancelled);
      Extractor := FRegistry.ForExtension(Request.Ext);
      if (Extractor <> nil) and
        ResolveFile(Request, Extractor, Reader, Cancelled, Outcome, Text) and
        (Outcome in [eoText, eoLimitReached]) then
        AppendTextPassages(Passages, 'file:' + IntToStr(Request.FileId) + ':text',
          Request.ProjectId, Request.ItemId, Request.FileId, pfFileText, Text, Request.Context);
      Inc(Done);
      if Assigned(Progress) then Progress(Done, Length(Files));
    end;
    RaiseIfCancelled(Cancelled);
    if Assigned(FEnterStore) then FEnterStore();
    try
      FStore.DeleteFileTextExcept(LiveIds);
    finally
      if Assigned(FLeaveStore) then FLeaveStore();
    end;
    Result := Passages.ToArray;
  finally
    Passages.Free;
  end;
end;

end.
