unit unit_OfficeTextExtractors;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, unit_TextEmbedder,
  unit_TextExtractors, unit_XmlTextScanner, unit_OpenXmlPackage;

type
  TOpenXmlTextExtractor = class(TTextExtractorBase)
  protected
    FMaxUncompressed: Int64;
    procedure ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck); virtual; abstract;
  public
    constructor Create;
    function Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult; override;
    property MaxUncompressed: Int64 read FMaxUncompressed write FMaxUncompressed;
  end;

  TDocxTextExtractor = class(TOpenXmlTextExtractor)
  protected
    procedure ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck); override;
  public
    function Id: string; override;
  end;

  TPptxTextExtractor = class(TOpenXmlTextExtractor)
  protected
    procedure ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck); override;
  public
    function Id: string; override;
  end;

  TXlsxTextExtractor = class(TOpenXmlTextExtractor)
  protected
    procedure ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck); override;
  public
    function Id: string; override;
  end;

implementation

uses
  System.Generics.Defaults, System.Math;

const
  SharedStringsMaxChars = 8 * 1024 * 1024;
  SharedStringsMaxCount = 1000000;

type
  TPartRef = record
    Key: string;
    Index: Integer;
  end;

  TOfficeTextHandler = class(TMarkupHandler)
  private
    FSink: TTextSink;
    FSkip: Integer;
    FInText: Boolean;
  public
    constructor Create(Sink: TTextSink);
    procedure OpenTag(const Name: string); override;
    procedure CloseTag(const Name: string); override;
    procedure Text(const S: string); override;
    function Done: Boolean; override;
  end;

  TSharedStringsHandler = class(TMarkupHandler)
  private
    FStrings: TList<string>;
    FCurrent: TStringBuilder;
    FSink: TTextSink;
    FSkip: Integer;
    FInText: Boolean;
    FTotalChars: Integer;
  public
    constructor Create(Strings: TList<string>; Sink: TTextSink);
    destructor Destroy; override;
    procedure OpenTag(const Name: string); override;
    procedure CloseTag(const Name: string); override;
    procedure Text(const S: string); override;
  end;

  TSheetHandler = class(TMarkupHandler)
  private
    FSink: TTextSink;
    FStrings: TList<string>;
    FValue: TStringBuilder;
    FElement: string;
    FCellType: string;
    FSkip: Integer;
    FInValue: Boolean;
    FInInline: Boolean;
    FInInlineText: Boolean;
    procedure CommitCell;
  public
    constructor Create(Sink: TTextSink; Strings: TList<string>);
    destructor Destroy; override;
    procedure OpenTag(const Name: string); override;
    procedure Attribute(const Name, Value: string); override;
    procedure CloseTag(const Name: string); override;
    procedure Text(const S: string); override;
    function Done: Boolean; override;
  end;

  TElementAttrs = record
    Id, RelId, Target: string;
  end;

  TElementAttributes = class(TMarkupHandler)
  private
    FElement: string;
    FItems: TList<TElementAttrs>;
    FInElement: Boolean;
  public
    constructor Create(const Element: string);
    destructor Destroy; override;
    procedure OpenTag(const Name: string); override;
    procedure Attribute(const Name, Value: string); override;
    property Items: TList<TElementAttrs> read FItems;
  end;

function NaturalKey(const Name: string): string;
var
  I, Start: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(Name) do
  begin
    if (Name[I] >= '0') and (Name[I] <= '9') then
    begin
      Start := I;
      while (I <= Length(Name)) and (Name[I] >= '0') and (Name[I] <= '9') do
        Inc(I);
      Result := Result + StringOfChar('0', Max(0, 12 - (I - Start))) + Copy(Name, Start, I - Start);
    end
    else
    begin
      Result := Result + LowerCase(Name[I]);
      Inc(I);
    end;
  end;
end;

procedure SortParts(var Parts: TArray<TPartRef>);
begin
  TArray.Sort<TPartRef>(Parts, TComparer<TPartRef>.Construct(
    function(const L, R: TPartRef): Integer
    begin
      Result := CompareStr(L.Key, R.Key);
    end));
end;
constructor TOpenXmlTextExtractor.Create;
begin
  inherited Create;
  FMaxUncompressed := OpenXmlMaxUncompressed;
end;

function TOpenXmlTextExtractor.Extract(const Bytes: TBytes; const Cancelled: TCancelCheck): TExtractResult;
var
  Sink: TTextSink;
  Package: TOpenXmlPackage;
begin
  if Length(Bytes) > FileTextMaxBytes then
    Exit(MakeExtractResult(eoTooLarge, '', 'file is larger than the extraction limit'));
  if Length(Bytes) = 0 then
    Exit(MakeExtractResult(eoCorrupt, '', 'file is empty'));
  if TryClassifyCompoundFile(Bytes, Result) then
    Exit;
  if (Length(Bytes) < 4) or (Bytes[0] <> $50) or (Bytes[1] <> $4B) then
    Exit(MakeExtractResult(eoCorrupt, '', 'not an OpenXML package'));
  Sink := TTextSink.Create(FMaxChars);
  try
    try
      Package := TOpenXmlPackage.Create(Bytes, FMaxUncompressed);
      try
        ReadParts(Package, Sink, Cancelled);
      finally
        Package.Free;
      end;
    except
      on EOperationCancelled do
        raise;
      on E: EExtractLimit do
        Exit(MakeExtractResult(eoTooLarge, '', E.Message));
      on E: EExtractEncrypted do
        Exit(MakeExtractResult(eoEncrypted, '', E.Message));
      on E: Exception do
        Exit(MakeExtractResult(eoCorrupt, '', E.ClassName + ': ' + E.Message));
    end;
    Result := Sink.ToResult;
  finally
    Sink.Free;
  end;
end;

constructor TOfficeTextHandler.Create(Sink: TTextSink);
begin
  inherited Create;
  FSink := Sink;
end;

procedure TOfficeTextHandler.OpenTag(const Name: string);
var
  Local: string;
begin
  if FSkip > 0 then
  begin
    Inc(FSkip);
    Exit;
  end;
  Local := LocalName(Name);
  if Local = 'Fallback' then
    FSkip := 1
  else if Local = 't' then
    FInText := True
  else if Local = 'tab' then
    FSink.Tab
  else if (Local = 'br') or (Local = 'cr') then
    FSink.LineBreak;
end;

procedure TOfficeTextHandler.CloseTag(const Name: string);
var
  Local: string;
begin
  if FSkip > 0 then
  begin
    Dec(FSkip);
    Exit;
  end;
  Local := LocalName(Name);
  if Local = 't' then
    FInText := False
  else if Local = 'p' then
    FSink.LineBreak;
end;

procedure TOfficeTextHandler.Text(const S: string);
begin
  if FInText and (FSkip = 0) then
    FSink.Append(S);
end;

function TOfficeTextHandler.Done: Boolean;
begin
  Result := FSink.Full;
end;

constructor TSharedStringsHandler.Create(Strings: TList<string>; Sink: TTextSink);
begin
  inherited Create;
  FStrings := Strings;
  FSink := Sink;
  FCurrent := TStringBuilder.Create;
end;

destructor TSharedStringsHandler.Destroy;
begin
  FCurrent.Free;
  inherited;
end;

procedure TSharedStringsHandler.OpenTag(const Name: string);
var
  Local: string;
begin
  if FSkip > 0 then
  begin
    Inc(FSkip);
    Exit;
  end;
  Local := LocalName(Name);
  if Local = 'rPh' then
    FSkip := 1
  else if Local = 'si' then
    FCurrent.Clear
  else if Local = 't' then
    FInText := True;
end;

procedure TSharedStringsHandler.CloseTag(const Name: string);
var
  Local: string;
begin
  if FSkip > 0 then
  begin
    Dec(FSkip);
    Exit;
  end;
  Local := LocalName(Name);
  if Local = 't' then
    FInText := False
  else if Local = 'si' then
  begin
    if FStrings.Count >= SharedStringsMaxCount then
      raise EExtractLimit.Create('shared string table has too many entries');
    if FTotalChars + FCurrent.Length > SharedStringsMaxChars then
    begin
      FStrings.Add('');
      FSink.MarkTruncated;
    end
    else
    begin
      Inc(FTotalChars, FCurrent.Length);
      FStrings.Add(FCurrent.ToString);
    end;
  end;
end;

procedure TSharedStringsHandler.Text(const S: string);
begin
  if FInText and (FSkip = 0) and (FCurrent.Length < SharedStringsMaxChars) then
    FCurrent.Append(S);
end;

constructor TSheetHandler.Create(Sink: TTextSink; Strings: TList<string>);
begin
  inherited Create;
  FSink := Sink;
  FStrings := Strings;
  FValue := TStringBuilder.Create;
end;

destructor TSheetHandler.Destroy;
begin
  FValue.Free;
  inherited;
end;

procedure TSheetHandler.OpenTag(const Name: string);
var
  Local: string;
begin
  Local := LocalName(Name);
  FElement := Local;
  if FSkip > 0 then
  begin
    Inc(FSkip);
    Exit;
  end;
  if Local = 'rPh' then
    FSkip := 1
  else if Local = 'c' then
  begin
    FCellType := '';
    FValue.Clear;
    FInInline := False;
  end
  else if Local = 'v' then
    FInValue := True
  else if Local = 'is' then
    FInInline := True
  else if (Local = 't') and FInInline then
    FInInlineText := True;
end;

procedure TSheetHandler.Attribute(const Name, Value: string);
begin
  if (FElement = 'c') and (LocalName(Name) = 't') then
    FCellType := Value;
end;

procedure TSheetHandler.CommitCell;
var
  Raw, Cell: string;
  Index: Integer;
begin
  Raw := FValue.ToString;
  Cell := '';
  if FCellType = 's' then
  begin
    Index := StrToIntDef(Trim(Raw), -1);
    if (Index >= 0) and (Index < FStrings.Count) then
      Cell := FStrings[Index];
  end
  else if FCellType = 'e' then
    Cell := ''
  else if FCellType = 'b' then
  begin
    if Trim(Raw) = '1' then
      Cell := 'TRUE'
    else if Trim(Raw) = '0' then
      Cell := 'FALSE';
  end
  else
    Cell := Raw;
  if Trim(Cell) <> '' then
  begin
    FSink.Tab;
    FSink.Append(Cell);
  end;
end;

procedure TSheetHandler.CloseTag(const Name: string);
var
  Local: string;
begin
  if FSkip > 0 then
  begin
    Dec(FSkip);
    Exit;
  end;
  Local := LocalName(Name);
  if Local = 'v' then
    FInValue := False
  else if Local = 't' then
    FInInlineText := False
  else if Local = 'is' then
    FInInline := False
  else if Local = 'c' then
    CommitCell
  else if Local = 'row' then
    FSink.LineBreak;
end;

procedure TSheetHandler.Text(const S: string);
begin
  if (FSkip = 0) and (FInValue or FInInlineText) and (FValue.Length < SharedStringsMaxChars) then
    FValue.Append(S);
end;

function TSheetHandler.Done: Boolean;
begin
  Result := FSink.Full;
end;

constructor TElementAttributes.Create(const Element: string);
begin
  inherited Create;
  FElement := Element;
  FItems := TList<TElementAttrs>.Create;
end;

destructor TElementAttributes.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TElementAttributes.OpenTag(const Name: string);
begin
  FInElement := LocalName(Name) = FElement;
  if FInElement then
  begin
    if FItems.Count >= OpenXmlMaxEntries then
      raise EExtractLimit.Create('workbook part lists too many elements');
    FItems.Add(Default(TElementAttrs));
  end;
end;

procedure TElementAttributes.Attribute(const Name, Value: string);
var
  Local: string;
  Last: Integer;
  Attrs: TElementAttrs;
begin
  if not FInElement then
    Exit;
  Local := LocalName(Name);
  Last := FItems.Count - 1;
  Attrs := FItems[Last];
  if Local = 'Id' then
    Attrs.Id := Value
  else if Local = 'id' then
    Attrs.RelId := Value
  else if Local = 'Target' then
    Attrs.Target := Value
  else
    Exit;
  FItems[Last] := Attrs;
end;

function TDocxTextExtractor.Id: string;
begin
  Result := 'docx-text';
end;

procedure TDocxTextExtractor.ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck);
var
  Parts: TArray<TPartRef>;
  Handler: TOfficeTextHandler;
  I, Count: Integer;
  Name, Rest, Lower: string;
  Rank: Integer;
begin
  if Package.Find('word/document.xml') < 0 then
    raise EExtractCorrupt.Create('word/document.xml is missing');
  SetLength(Parts, Package.PartCount);
  Count := 0;
  for I := 0 to Package.PartCount - 1 do
  begin
    Name := Package.PartName(I);
    if not (SameText(Copy(Name, 1, 5), 'word/') and SameText(Copy(Name, Length(Name) - 3, 4), '.xml')) then
      Continue;
    Rest := Copy(Name, 6, MaxInt);
    if Pos('/', Rest) > 0 then
      Continue;
    Lower := LowerCase(Rest);
    if Lower = 'document.xml' then
      Rank := 0
    else if (Lower = 'footnotes.xml') or (Lower = 'endnotes.xml') then
      Rank := 1
    else if Copy(Lower, 1, 6) = 'header' then
      Rank := 2
    else if Copy(Lower, 1, 6) = 'footer' then
      Rank := 3
    else
      Continue;
    Parts[Count].Key := IntToStr(Rank) + NaturalKey(Rest);
    Parts[Count].Index := I;
    Inc(Count);
  end;
  SetLength(Parts, Count);
  SortParts(Parts);
  Handler := TOfficeTextHandler.Create(Sink);
  try
    for I := 0 to High(Parts) do
    begin
      if Sink.Full then
        Break;
      Package.Scan(Parts[I].Index, Handler, Cancelled);
      Sink.EndBlock;
    end;
  finally
    Handler.Free;
  end;
end;

function TPptxTextExtractor.Id: string;
begin
  Result := 'pptx-text';
end;

procedure TPptxTextExtractor.ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck);
var
  Parts: TArray<TPartRef>;
  Handler: TOfficeTextHandler;
  I, Count: Integer;
  Name, Rest: string;
  Rank: Integer;
begin
  SetLength(Parts, Package.PartCount);
  Count := 0;
  for I := 0 to Package.PartCount - 1 do
  begin
    Name := Package.PartName(I);
    if not SameText(Copy(Name, Length(Name) - 3, 4), '.xml') then
      Continue;
    if SameText(Copy(Name, 1, 11), 'ppt/slides/') then
    begin
      Rest := Copy(Name, 12, MaxInt);
      Rank := 0;
    end
    else if SameText(Copy(Name, 1, 16), 'ppt/notesSlides/') then
    begin
      Rest := Copy(Name, 17, MaxInt);
      Rank := 1;
    end
    else
      Continue;
    if (Pos('/', Rest) > 0) or not SameText(Copy(Rest, 1, 5), 'slide') and not SameText(Copy(Rest, 1, 10), 'notesSlide') then
      Continue;
    Parts[Count].Key := IntToStr(Rank) + NaturalKey(Rest);
    Parts[Count].Index := I;
    Inc(Count);
  end;
  if Count = 0 then
    raise EExtractCorrupt.Create('no slides found');
  SetLength(Parts, Count);
  SortParts(Parts);
  Handler := TOfficeTextHandler.Create(Sink);
  try
    for I := 0 to High(Parts) do
    begin
      if Sink.Full then
        Break;
      Package.Scan(Parts[I].Index, Handler, Cancelled);
      Sink.EndBlock;
    end;
  finally
    Handler.Free;
  end;
end;

function TXlsxTextExtractor.Id: string;
begin
  Result := 'xlsx-text';
end;

procedure TXlsxTextExtractor.ReadParts(Package: TOpenXmlPackage; Sink: TTextSink; const Cancelled: TCancelCheck);
var
  Strings: TList<string>;
  SheetIndexes: TList<Integer>;
  Targets: TDictionary<string, string>;
  Book, Rels: TElementAttributes;
  StringsHandler: TSharedStringsHandler;
  SheetHandler: TSheetHandler;
  Index, I: Integer;
  Target: string;
  Parts: TArray<TPartRef>;
  Count: Integer;
  Name: string;
begin
  Strings := TList<string>.Create;
  SheetIndexes := TList<Integer>.Create;
  try
    Index := Package.Find('xl/sharedStrings.xml');
    if Index >= 0 then
    begin
      StringsHandler := TSharedStringsHandler.Create(Strings, Sink);
      try
        Package.Scan(Index, StringsHandler, Cancelled);
      finally
        StringsHandler.Free;
      end;
    end;

    Index := Package.Find('xl/workbook.xml');
    if (Index >= 0) and (Package.Find('xl/_rels/workbook.xml.rels') >= 0) then
    begin
      Book := TElementAttributes.Create('sheet');
      Rels := TElementAttributes.Create('Relationship');
      Targets := TDictionary<string, string>.Create;
      try
        Package.Scan(Index, Book, Cancelled);
        Package.Scan(Package.Find('xl/_rels/workbook.xml.rels'), Rels, Cancelled);
        for I := 0 to Rels.Items.Count - 1 do
          Targets.AddOrSetValue(Rels.Items[I].Id, Rels.Items[I].Target);
        for I := 0 to Book.Items.Count - 1 do
        begin
          if not Targets.TryGetValue(Book.Items[I].RelId, Target) then
            Continue;
          if (Target <> '') and (Target[1] = '/') then
            Delete(Target, 1, 1)
          else
            Target := 'xl/' + Target;
          Index := Package.Find(Target);
          if Index >= 0 then
            SheetIndexes.Add(Index);
        end;
      finally
        Targets.Free;
        Rels.Free;
        Book.Free;
      end;
    end;

    if SheetIndexes.Count = 0 then
    begin
      SetLength(Parts, Package.PartCount);
      Count := 0;
      for I := 0 to Package.PartCount - 1 do
      begin
        Name := Package.PartName(I);
        if SameText(Copy(Name, 1, 13), 'xl/worksheets') and (Pos('/', Copy(Name, 14, MaxInt)) = 1) and
          (Pos('/', Copy(Name, 15, MaxInt)) = 0) and SameText(Copy(Name, Length(Name) - 3, 4), '.xml') then
        begin
          Parts[Count].Key := NaturalKey(Name);
          Parts[Count].Index := I;
          Inc(Count);
        end;
      end;
      SetLength(Parts, Count);
      SortParts(Parts);
      for I := 0 to High(Parts) do
        SheetIndexes.Add(Parts[I].Index);
    end;
    if SheetIndexes.Count = 0 then
      raise EExtractCorrupt.Create('no worksheets found');

    SheetHandler := TSheetHandler.Create(Sink, Strings);
    try
      for I := 0 to SheetIndexes.Count - 1 do
      begin
        if Sink.Full then
          Break;
        Package.Scan(SheetIndexes[I], SheetHandler, Cancelled);
        Sink.EndBlock;
      end;
    finally
      SheetHandler.Free;
    end;
  finally
    SheetIndexes.Free;
    Strings.Free;
  end;
end;

end.
