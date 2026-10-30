unit unit_TextExtractors;

interface

uses
  System.SysUtils, unit_TextEmbedder;

const
  FileTextMaxBytes = 64 * 1024 * 1024;
  FileTextMaxChars = 200000;
  PdfMaxPages = 2000;
  TextSniffBytes = 8192;
  TextSliceChars = 65536;

type
  TExtractOutcome = (eoText, eoNoText, eoUnsupported, eoTooLarge, eoEncrypted, eoCorrupt, eoLimitReached, eoExtractorUnavailable);

  TExtractResult = record
    Outcome: TExtractOutcome;
    Text: string;
    Detail: string;
  end;

  ITextExtractor = interface
    ['{4B1E6C52-0F2A-4C0D-9E57-6A3D8B7F1C94}']
    function Id: string;
    function Version: Integer;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
  end;

  TTextSink = class
  private
    FBuilder: TStringBuilder;
    FMaxChars: Integer;
    FPendingBreaks: Integer;
    FPendingSeparator: Char;
    FLineHasText: Boolean;
    FBlockStart: Boolean;
    FPreviousWasCR: Boolean;
    FTruncated: Boolean;
  public
    constructor Create(MaxChars: Integer);
    destructor Destroy; override;
    procedure AppendChar(C: Char);
    procedure Append(const S: string);
    procedure AppendBuffer(S: PChar; Count: Integer);
    procedure LineBreak;
    procedure Tab;
    procedure EndBlock;
    procedure MarkTruncated;
    function Full: Boolean;
    function ToResult(const EmptyDetail: string = 'no text'): TExtractResult;
    function ToString: string; override;
  end;

  TTextExtractorBase = class(TInterfacedObject, ITextExtractor)
  protected
    FMaxChars: Integer;
  public
    constructor Create;
    function Id: string; virtual; abstract;
    function Version: Integer; virtual;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; virtual; abstract;
    property MaxChars: Integer read FMaxChars write FMaxChars;
  end;

  TPdfTextExtractor = class(TTextExtractorBase)
  private
    FLibraryPath: string;
  public
    constructor Create(const LibraryPath: string);
    function Id: string; override;
    function Version: Integer; override;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
  end;

function MakeExtractResult(Outcome: TExtractOutcome; const Text: string = ''; const Detail: string = ''): TExtractResult;

function NormalizeExtractedText(const Text: string): string;

procedure CheckExtractCancelled(const Cancelled: TCancelCheck);

function TryRejectTextBytes(const Bytes: TBytes; out Rejected: TExtractResult): Boolean;

function DecodeTextBytes(const Bytes: TBytes; CodePage: Integer = 0): string;

function CodePageForCharset(const Charset: string): Integer;

implementation

uses
  System.Character, System.SyncObjs, System.Math, unit_PdfiumApi;

const
  PdfExtractorVersion = 1;

function MakeExtractResult(Outcome: TExtractOutcome; const Text, Detail: string): TExtractResult;
begin
  Result.Outcome := Outcome;
  Result.Text := Text;
  Result.Detail := Detail;
end;

procedure CheckExtractCancelled(const Cancelled: TCancelCheck);
begin
  if Assigned(Cancelled) and Cancelled() then
    raise EOperationCancelled.Create('cancelled');
end;

constructor TTextSink.Create(MaxChars: Integer);
begin
  inherited Create;
  FBuilder := TStringBuilder.Create;
  FMaxChars := MaxChars;
end;

destructor TTextSink.Destroy;
begin
  FBuilder.Free;
  inherited;
end;

function TTextSink.Full: Boolean;
begin
  Result := FBuilder.Length > FMaxChars;
end;

procedure TTextSink.LineBreak;
begin
  FPendingSeparator := #0;
  if (FBuilder.Length = 0) or FBlockStart then
    Exit;
  Inc(FPendingBreaks);
  FLineHasText := False;
end;

procedure TTextSink.Tab;
begin
  if FLineHasText then
    FPendingSeparator := #9;
end;

procedure TTextSink.EndBlock;
begin
  if FBuilder.Length = 0 then
    Exit;
  FPendingBreaks := 2;
  FPendingSeparator := #0;
  FLineHasText := False;
  FBlockStart := True;
end;

procedure TTextSink.MarkTruncated;
begin
  FTruncated := True;
end;

procedure TTextSink.AppendChar(C: Char);
begin
  if Full or (C = #0) then
    Exit;
  if C = #13 then
  begin
    LineBreak;
    FPreviousWasCR := True;
    Exit;
  end;
  if C = #10 then
  begin
    if not FPreviousWasCR then
      LineBreak;
    FPreviousWasCR := False;
    Exit;
  end;
  FPreviousWasCR := False;
  if (C <= ' ') or C.IsWhiteSpace then
  begin
    if FLineHasText and (FPendingSeparator = #0) then
      FPendingSeparator := ' ';
    Exit;
  end;
  if FPendingBreaks > 0 then
  begin
    FBuilder.Append(#10, FPendingBreaks);
    FPendingBreaks := 0;
  end
  else if FPendingSeparator <> #0 then
    FBuilder.Append(FPendingSeparator);
  FPendingSeparator := #0;
  FBuilder.Append(C);
  FLineHasText := True;
  FBlockStart := False;
end;

procedure TTextSink.AppendBuffer(S: PChar; Count: Integer);
var
  I: Integer;
begin
  I := 0;
  while (I < Count) and not Full do
  begin
    AppendChar(S[I]);
    Inc(I);
  end;
end;

procedure TTextSink.Append(const S: string);
begin
  AppendBuffer(PChar(S), Length(S));
end;

function TTextSink.ToString: string;
begin
  Result := FBuilder.ToString;
end;

function TTextSink.ToResult(const EmptyDetail: string): TExtractResult;
var
  Text: string;
  Cut: Integer;
begin
  if FBuilder.Length = 0 then
    Exit(MakeExtractResult(eoNoText, '', EmptyDetail));
  if Full then
  begin
    Cut := FMaxChars;
    if (Cut > 0) and FBuilder.Chars[Cut - 1].IsHighSurrogate then
      Dec(Cut);
    while (Cut > 0) and ((FBuilder.Chars[Cut - 1] = #10) or (FBuilder.Chars[Cut - 1] = ' ') or
      (FBuilder.Chars[Cut - 1] = #9)) do
      Dec(Cut);
    Text := FBuilder.ToString(0, Cut);
    if Text = '' then
      Exit(MakeExtractResult(eoNoText, '', EmptyDetail));
    Exit(MakeExtractResult(eoLimitReached, Text, 'text limit reached'));
  end;
  if FTruncated then
    Result := MakeExtractResult(eoLimitReached, FBuilder.ToString, 'text limit reached')
  else
    Result := MakeExtractResult(eoText, FBuilder.ToString);
end;

function NormalizeExtractedText(const Text: string): string;
var
  Sink: TTextSink;
begin
  Sink := TTextSink.Create(MaxInt);
  try
    Sink.Append(Text);
    Result := Sink.ToString;
  finally
    Sink.Free;
  end;
end;

function HasUtf16Bom(const Bytes: TBytes): Boolean;
begin
  Result := (Length(Bytes) >= 2) and (((Bytes[0] = $FF) and (Bytes[1] = $FE)) or ((Bytes[0] = $FE) and (Bytes[1] = $FF)));
end;

function IsValidUtf8(const Bytes: TBytes; Start: Integer): Boolean;
var
  I, Need: Integer;
  B: Byte;
  Cp: Cardinal;
begin
  I := Start;
  while I < Length(Bytes) do
  begin
    B := Bytes[I];
    Inc(I);
    if B < $80 then
      Continue;
    if (B >= $C2) and (B <= $DF) then
    begin
      Need := 1;
      Cp := B and $1F;
    end
    else if (B >= $E0) and (B <= $EF) then
    begin
      Need := 2;
      Cp := B and $0F;
    end
    else if (B >= $F0) and (B <= $F4) then
    begin
      Need := 3;
      Cp := B and $07;
    end
    else
      Exit(False);
    if I + Need > Length(Bytes) then
      Exit(False);
    while Need > 0 do
    begin
      if (Bytes[I] and $C0) <> $80 then
        Exit(False);
      Cp := (Cp shl 6) or (Bytes[I] and $3F);
      Inc(I);
      Dec(Need);
    end;
    if ((B >= $E0) and (B <= $EF) and (Cp < $800)) or ((B >= $F0) and (Cp < $10000)) or
      (Cp > $10FFFF) or ((Cp >= $D800) and (Cp <= $DFFF)) then
      Exit(False);
  end;
  Result := True;
end;

function DecodeTextBytes(const Bytes: TBytes; CodePage: Integer): string;
var
  Enc: TEncoding;
begin
  if Length(Bytes) = 0 then
    Exit('');
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
  begin
    if IsValidUtf8(Bytes, 3) then
      Exit(TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3));
    Exit(TEncoding.ANSI.GetString(Bytes, 3, Length(Bytes) - 3));
  end;
  if (Length(Bytes) >= 2) and (Bytes[0] = $FF) and (Bytes[1] = $FE) then
    Exit(TEncoding.Unicode.GetString(Bytes, 2, Length(Bytes) - 2));
  if (Length(Bytes) >= 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(Bytes, 2, Length(Bytes) - 2));
  if (CodePage <> 0) and (CodePage <> 65001) then
  begin
    try
      Enc := TEncoding.GetEncoding(CodePage);
      try
        Exit(Enc.GetString(Bytes));
      finally
        Enc.Free;
      end;
    except
      on EEncodingError do
        Result := '';
    end;
  end;
  if IsValidUtf8(Bytes, 0) then
    Result := TEncoding.UTF8.GetString(Bytes)
  else
    Result := TEncoding.ANSI.GetString(Bytes);
end;

function CodePageForCharset(const Charset: string): Integer;
type
  TCharsetEntry = record
    Name: string;
    CodePage: Integer;
  end;
const
  Entries: array[0..31] of TCharsetEntry = (
    (Name: 'utf-8'; CodePage: 65001), (Name: 'utf8'; CodePage: 65001),
    (Name: 'utf-16'; CodePage: 1200), (Name: 'utf-16le'; CodePage: 1200), (Name: 'utf-16be'; CodePage: 1201),
    (Name: 'windows-1250'; CodePage: 1250), (Name: 'windows-1251'; CodePage: 1251),
    (Name: 'windows-1252'; CodePage: 1252), (Name: 'windows-1253'; CodePage: 1253),
    (Name: 'windows-1254'; CodePage: 1254), (Name: 'windows-1257'; CodePage: 1257),
    (Name: 'cp1250'; CodePage: 1250), (Name: 'cp1251'; CodePage: 1251), (Name: 'cp1252'; CodePage: 1252),
    (Name: 'iso-8859-1'; CodePage: 1252), (Name: 'latin1'; CodePage: 1252), (Name: 'us-ascii'; CodePage: 1252),
    (Name: 'ascii'; CodePage: 1252), (Name: 'iso-8859-2'; CodePage: 28592), (Name: 'iso-8859-5'; CodePage: 28595),
    (Name: 'iso-8859-15'; CodePage: 28605), (Name: 'koi8-r'; CodePage: 20866), (Name: 'koi8-u'; CodePage: 21866),
    (Name: 'gb2312'; CodePage: 936), (Name: 'gbk'; CodePage: 936), (Name: 'gb18030'; CodePage: 54936),
    (Name: 'big5'; CodePage: 950), (Name: 'shift_jis'; CodePage: 932), (Name: 'shift-jis'; CodePage: 932),
    (Name: 'windows-31j'; CodePage: 932), (Name: 'euc-jp'; CodePage: 20932), (Name: 'euc-kr'; CodePage: 51949));
var
  Key: string;
  I: Integer;
begin
  Key := LowerCase(Trim(Charset));
  for I := Low(Entries) to High(Entries) do
    if Entries[I].Name = Key then
      Exit(Entries[I].CodePage);
  Result := 0;
end;

function TryRejectTextBytes(const Bytes: TBytes; out Rejected: TExtractResult): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Length(Bytes) > FileTextMaxBytes then
    Rejected := MakeExtractResult(eoTooLarge, '', 'file is larger than the extraction limit')
  else if Length(Bytes) = 0 then
    Rejected := MakeExtractResult(eoNoText, '', 'file is empty')
  else
  begin
    Result := False;
    if not HasUtf16Bom(Bytes) then
      for I := 0 to Min(Length(Bytes), TextSniffBytes) - 1 do
        if Bytes[I] = 0 then
        begin
          Rejected := MakeExtractResult(eoUnsupported, '', 'binary content');
          Exit(True);
        end;
  end;
end;

constructor TTextExtractorBase.Create;
begin
  inherited Create;
  FMaxChars := FileTextMaxChars;
end;

function TTextExtractorBase.Version: Integer;
begin
  Result := 1;
end;

constructor TPdfTextExtractor.Create(const LibraryPath: string);
begin
  inherited Create;
  FLibraryPath := LibraryPath;
end;

function TPdfTextExtractor.Id: string;
begin
  Result := 'pdfium-text';
end;

function TPdfTextExtractor.Version: Integer;
begin
  Result := PdfExtractorVersion;
end;

function TPdfTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Api: TPdfiumApi;
  Doc: Pointer;
  Sink: TTextSink;
  PageCount, PageIndex, Err: Integer;
  PageText: string;

  function ReadPage(Index: Integer): string;
  var
    Page, TextPage: Pointer;
    Count, Written: Integer;
    Buffer: TArray<WideChar>;
  begin
    Result := '';
    Page := Api.LoadPage(Doc, Index);
    if Page = nil then
      Exit;
    try
      TextPage := Api.TextLoadPage(Page);
      if TextPage = nil then
        Exit;
      try
        Count := Api.TextCountChars(TextPage);
        if Count <= 0 then
          Exit;
        SetLength(Buffer, Count + 1);
        Written := Api.TextGetText(TextPage, 0, Count, PWideChar(Buffer));
        if Written > 1 then
          SetString(Result, PWideChar(Buffer), Written - 1);
      finally
        Api.TextClosePage(TextPage);
      end;
    finally
      Api.ClosePage(Page);
    end;
  end;

begin
  if Length(Bytes) > FileTextMaxBytes then
    Exit(MakeExtractResult(eoTooLarge, '', 'file is larger than the extraction limit'));
  if Length(Bytes) = 0 then
    Exit(MakeExtractResult(eoCorrupt, '', 'file is empty'));
  if not FileExists(FLibraryPath) then
    Exit(MakeExtractResult(eoExtractorUnavailable, '', 'PDFium not installed'));
  try
    Api := PdfiumApiFor(FLibraryPath);
  except
    on E: EPdfiumError do
      Exit(MakeExtractResult(eoExtractorUnavailable, '', 'PDFium not installed'));
  end;

  Sink := TTextSink.Create(FMaxChars);
  try
    PdfiumLock.Enter;
    try
      Doc := Api.LoadMemDocument64(@Bytes[0], Length(Bytes), nil);
      if Doc = nil then
      begin
        Err := Api.GetLastError;
        if Err = FPDF_ERR_PASSWORD then
          Exit(MakeExtractResult(eoEncrypted, '', 'password required'));
        Exit(MakeExtractResult(eoCorrupt, '', 'PDF cannot be opened'));
      end;
    finally
      PdfiumLock.Leave;
    end;
    try
      PdfiumLock.Enter;
      try
        PageCount := Api.GetPageCount(Doc);
      finally
        PdfiumLock.Leave;
      end;
      if PageCount > PdfMaxPages then
      begin
        PageCount := PdfMaxPages;
        Sink.MarkTruncated;
      end;
      PageIndex := 0;
      while (PageIndex < PageCount) and not Sink.Full do
      begin
        CheckExtractCancelled(Cancelled);
        PdfiumLock.Enter;
        try
          PageText := ReadPage(PageIndex);
        finally
          PdfiumLock.Leave;
        end;
        Sink.Append(PageText);
        Sink.EndBlock;
        Inc(PageIndex);
      end;
    finally
      PdfiumLock.Enter;
      try
        Api.CloseDocument(Doc);
      finally
        PdfiumLock.Leave;
      end;
    end;
    Result := Sink.ToResult('no text layer');
  finally
    Sink.Free;
  end;
end;

end.
