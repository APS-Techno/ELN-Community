unit unit_MarkupTextExtractors;

interface

uses
  System.SysUtils, unit_TextEmbedder, unit_TextExtractors;

type
  TPlainTextExtractor = class(TTextExtractorBase)
  private
    FId: string;
  public
    constructor Create(const Id: string);
    function Id: string; override;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
  end;

  THtmlTextExtractor = class(TTextExtractorBase)
  public
    function Id: string; override;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
  end;

  TXmlTextExtractor = class(TTextExtractorBase)
  public
    function Id: string; override;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
  end;

implementation

uses
  System.Math, System.Character, unit_XmlTextScanner;

const
  CharsetSniffBytes = 4096;
  BlockTags = '|p|div|li|ul|ol|tr|table|tbody|thead|tfoot|caption|h1|h2|h3|h4|h5|h6|section|article|header|' +
    'footer|nav|aside|blockquote|pre|hr|form|fieldset|dl|dt|dd|address|figure|figcaption|main|title|body|head|' +
    'html|details|summary|';

type
  TBreakingTextHandler = class(TMarkupHandler)
  protected
    FSink: TTextSink;
    FBreakPending: Boolean;
    procedure AppendText(const S: string);
  public
    constructor Create(Sink: TTextSink);
    procedure Text(const S: string); override;
    function Done: Boolean; override;
  end;

  THtmlHandler = class(TBreakingTextHandler)
  public
    procedure OpenTag(const Name: string); override;
    procedure CloseTag(const Name: string); override;
  end;

  TXmlHandler = class(TBreakingTextHandler)
  public
    procedure OpenTag(const Name: string); override;
    procedure Attribute(const Name, Value: string); override;
    procedure CloseTag(const Name: string); override;
  end;

function HasContent(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if (C > ' ') and not C.IsWhiteSpace then
      Exit(True);
  Result := False;
end;

procedure AppendSliced(Sink: TTextSink; const Text: string; const Cancelled: TCancelCheck);
var
  Start: Integer;
begin
  Start := 1;
  while (Start <= Length(Text)) and not Sink.Full do
  begin
    CheckExtractCancelled(Cancelled);
    Sink.AppendBuffer(@Text[Start], Min(TextSliceChars, Length(Text) - Start + 1));
    Inc(Start, TextSliceChars);
  end;
end;

function ScanMarkup(const Text: string; Handler: TMarkupHandler; Html: Boolean; const Cancelled: TCancelCheck): Integer;
var
  Scanner: TMarkupScanner;
  Start: Integer;
begin
  Scanner := TMarkupScanner.Create(Handler, Html);
  try
    Start := 1;
    while (Start <= Length(Text)) and not Handler.Done do
    begin
      CheckExtractCancelled(Cancelled);
      Scanner.Feed(@Text[Start], Min(TextSliceChars, Length(Text) - Start + 1));
      Inc(Start, TextSliceChars);
    end;
    Scanner.Finish;
    Result := Scanner.ElementCount;
  finally
    Scanner.Free;
  end;
end;

function SniffCharset(const Bytes: TBytes; const Keyword: string; Limit: Integer): Integer;
var
  Head: string;
  I, P, Start: Integer;
begin
  Result := 0;
  SetLength(Head, Min(Length(Bytes), Limit));
  for I := 1 to Length(Head) do
    if Bytes[I - 1] < 128 then
      Head[I] := Char(Bytes[I - 1])
    else
      Head[I] := '?';
  Head := LowerCase(Head);
  P := Pos(Keyword, Head);
  if P = 0 then
    Exit;
  Inc(P, Length(Keyword));
  while (P <= Length(Head)) and (Head[P] = ' ') do
    Inc(P);
  if (P > Length(Head)) or (Head[P] <> '=') then
    Exit;
  Inc(P);
  while (P <= Length(Head)) and ((Head[P] = ' ') or (Head[P] = '"') or (Head[P] = '''')) do
    Inc(P);
  Start := P;
  while (P <= Length(Head)) and (CharInSet(Head[P], ['a'..'z', '0'..'9', '-', '_', ':', '.'])) do
    Inc(P);
  Result := CodePageForCharset(Copy(Head, Start, P - Start));
end;

constructor TBreakingTextHandler.Create(Sink: TTextSink);
begin
  inherited Create;
  FSink := Sink;
end;

procedure TBreakingTextHandler.AppendText(const S: string);
begin
  if FBreakPending and HasContent(S) then
  begin
    FSink.LineBreak;
    FBreakPending := False;
  end;
  FSink.Append(S);
end;

procedure TBreakingTextHandler.Text(const S: string);
begin
  AppendText(S);
end;

function TBreakingTextHandler.Done: Boolean;
begin
  Result := FSink.Full;
end;

procedure THtmlHandler.OpenTag(const Name: string);
begin
  if Name = 'br' then
    FSink.LineBreak
  else if (Name = 'td') or (Name = 'th') then
    FSink.Tab
  else if Pos('|' + Name + '|', BlockTags) > 0 then
    FBreakPending := True;
end;

procedure THtmlHandler.CloseTag(const Name: string);
begin
  if Pos('|' + Name + '|', BlockTags) > 0 then
    FBreakPending := True;
end;

procedure TXmlHandler.OpenTag(const Name: string);
begin
  FBreakPending := True;
end;

procedure TXmlHandler.Attribute(const Name, Value: string);
begin
  if HasContent(Value) then
  begin
    FSink.LineBreak;
    FSink.Append(Value);
    FBreakPending := True;
  end;
end;

procedure TXmlHandler.CloseTag(const Name: string);
begin
  FBreakPending := True;
end;

constructor TPlainTextExtractor.Create(const Id: string);
begin
  inherited Create;
  FId := Id;
end;

function TPlainTextExtractor.Id: string;
begin
  Result := FId;
end;

function TPlainTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Sink: TTextSink;
begin
  if TryRejectTextBytes(Bytes, Result) then
    Exit;
  Sink := TTextSink.Create(FMaxChars);
  try
    AppendSliced(Sink, DecodeTextBytes(Bytes), Cancelled);
    Result := Sink.ToResult;
  finally
    Sink.Free;
  end;
end;

function THtmlTextExtractor.Id: string;
begin
  Result := 'html-text';
end;

function THtmlTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Sink: TTextSink;
  Handler: THtmlHandler;
  CodePage: Integer;
begin
  if TryRejectTextBytes(Bytes, Result) then
    Exit;
  Sink := TTextSink.Create(FMaxChars);
  try
    Handler := THtmlHandler.Create(Sink);
    try
      CodePage := SniffCharset(Bytes, 'charset', CharsetSniffBytes);
      if (CodePage = 1200) or (CodePage = 1201) then
        CodePage := 65001;
      ScanMarkup(DecodeTextBytes(Bytes, CodePage), Handler, True, Cancelled);
    finally
      Handler.Free;
    end;
    Result := Sink.ToResult;
  finally
    Sink.Free;
  end;
end;

function TXmlTextExtractor.Id: string;
begin
  Result := 'xml-text';
end;

function TXmlTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Sink: TTextSink;
  Handler: TXmlHandler;
  Elements: Integer;
begin
  if TryRejectTextBytes(Bytes, Result) then
    Exit;
  Sink := TTextSink.Create(FMaxChars);
  try
    Handler := TXmlHandler.Create(Sink);
    try
      Elements := ScanMarkup(DecodeTextBytes(Bytes, SniffCharset(Bytes, 'encoding', 200)), Handler, False, Cancelled);
    finally
      Handler.Free;
    end;
    if Elements = 0 then
      Exit(MakeExtractResult(eoCorrupt, '', 'no XML elements'));
    Result := Sink.ToResult;
  finally
    Sink.Free;
  end;
end;

end.
