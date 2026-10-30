unit unit_OpenXmlPackage;

interface

uses
  System.SysUtils, System.Classes, System.Zip, System.Generics.Collections, unit_TextEmbedder,
  unit_TextExtractors, unit_XmlTextScanner;

const
  OpenXmlMaxUncompressed = 256 * 1024 * 1024;
  OpenXmlMaxEntries = 10000;

type
  EExtractLimit = class(Exception);
  EExtractEncrypted = class(Exception);
  EExtractCorrupt = class(Exception);

  TOpenXmlPackage = class
  private
    FStream: TBytesStream;
    FZip: TZipFile;
    FNames: TArray<string>;
    FLookup: TDictionary<string, Integer>;
    FRead: Int64;
    FMaxUncompressed: Int64;
  public
    constructor Create(const Bytes: TBytes; MaxUncompressed: Int64);
    destructor Destroy; override;
    function PartCount: Integer;
    function PartName(Index: Integer): string;
    function Find(const Name: string): Integer;
    procedure Scan(Index: Integer; Handler: TMarkupHandler; const Cancelled: TCancelCheck);
  end;

function TryClassifyCompoundFile(const Bytes: TBytes; out Rejected: TExtractResult): Boolean;

implementation

uses
  System.Generics.Defaults, System.Math, unit_TextStreamDecoder;

const
  ReadBlockBytes = 65536;
  CompoundFileSignature: array[0..7] of Byte = ($D0, $CF, $11, $E0, $A1, $B1, $1A, $E1);

function ReadFull(Stream: TStream; var Buffer: TBytes): Integer;
var
  N: Integer;
begin
  Result := 0;
  while Result < Length(Buffer) do
  begin
    N := Stream.Read(Buffer[Result], Length(Buffer) - Result);
    if N <= 0 then
      Break;
    Inc(Result, N);
  end;
end;

procedure CheckEntryCount(const Bytes: TBytes);
var
  I, Count: Integer;
begin
  for I := Length(Bytes) - 22 downto Max(0, Length(Bytes) - 22 - 65535) do
    if (Bytes[I] = $50) and (Bytes[I + 1] = $4B) and (Bytes[I + 2] = 5) and (Bytes[I + 3] = 6) then
    begin
      Count := Bytes[I + 10] or (Bytes[I + 11] shl 8);
      if (Count = $FFFF) or (Count > OpenXmlMaxEntries) then
        raise EExtractLimit.Create('package has too many entries');
      Exit;
    end;
end;

constructor TOpenXmlPackage.Create(const Bytes: TBytes; MaxUncompressed: Int64);
var
  Infos: TArray<TZipHeader>;
  I: Integer;
  Total: UInt64;
  Name: string;
begin
  inherited Create;
  FMaxUncompressed := MaxUncompressed;
  CheckEntryCount(Bytes);
  FStream := TBytesStream.Create(Bytes);
  FZip := TZipFile.Create;
  FZip.Open(FStream, zmRead);
  if FZip.FileCount > OpenXmlMaxEntries then
    raise EExtractLimit.Create('package has too many entries');
  Infos := FZip.FileInfos;
  Total := 0;
  for I := 0 to High(Infos) do
  begin
    Inc(Total, Infos[I].UncompressedSize64);
    if Total > UInt64(FMaxUncompressed) then
      raise EExtractLimit.Create('package declares too much uncompressed data');
  end;
  FLookup := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  SetLength(FNames, Length(Infos));
  for I := 0 to High(Infos) do
  begin
    Name := StringReplace(FZip.FileName[I], '\', '/', [rfReplaceAll]);
    while (Name <> '') and (Name[1] = '/') do
      Delete(Name, 1, 1);
    FNames[I] := Name;
    FLookup.AddOrSetValue(Name, I);
  end;
end;

destructor TOpenXmlPackage.Destroy;
begin
  FLookup.Free;
  FZip.Free;
  FStream.Free;
  inherited;
end;

function TOpenXmlPackage.PartCount: Integer;
begin
  Result := Length(FNames);
end;

function TOpenXmlPackage.PartName(Index: Integer): string;
begin
  Result := FNames[Index];
end;

function TOpenXmlPackage.Find(const Name: string): Integer;
begin
  if not FLookup.TryGetValue(Name, Result) then
    Result := -1;
end;

procedure TOpenXmlPackage.Scan(Index: Integer; Handler: TMarkupHandler; const Cancelled: TCancelCheck);
var
  Stream: TStream;
  Header: TZipHeader;
  Buffer: TBytes;
  Scanner: TMarkupScanner;
  Decoder: TTextStreamDecoder;
  N: Integer;
  First: Boolean;
begin
  if FZip.FileInfo[Index].IsEncrypted then
    raise EExtractEncrypted.Create('package entry is encrypted');
  FZip.Read(Index, Stream, Header);
  try
    Scanner := TMarkupScanner.Create(Handler, False);
    Decoder := TTextStreamDecoder.Create;
    try
      SetLength(Buffer, ReadBlockBytes);
      First := True;
      while not Handler.Done do
      begin
        CheckExtractCancelled(Cancelled);
        N := ReadFull(Stream, Buffer);
        if N = 0 then
          Break;
        Inc(FRead, N);
        if FRead > FMaxUncompressed then
          raise EExtractLimit.Create('package inflates beyond the limit');
        Scanner.Feed(Decoder.Decode(Buffer, N, First));
        First := False;
        if N < Length(Buffer) then
          Break;
      end;
      Scanner.Finish;
    finally
      Decoder.Free;
      Scanner.Free;
    end;
  finally
    Stream.Free;
  end;
end;

function IsCompoundFile(const Bytes: TBytes): Boolean;
var
  I: Integer;
begin
  Result := Length(Bytes) >= Length(CompoundFileSignature);
  if Result then
    for I := 0 to High(CompoundFileSignature) do
      if Bytes[I] <> CompoundFileSignature[I] then
        Exit(False);
end;

function HasEncryptedPackageStream(const Bytes: TBytes): Boolean;
var
  Pattern: TBytes;
  I, J: Integer;
begin
  Pattern := TEncoding.Unicode.GetBytes('EncryptedPackage');
  for I := 0 to Length(Bytes) - Length(Pattern) do
    if Bytes[I] = Pattern[0] then
    begin
      J := 1;
      while (J < Length(Pattern)) and (Bytes[I + J] = Pattern[J]) do
        Inc(J);
      if J = Length(Pattern) then
        Exit(True);
    end;
  Result := False;
end;

function TryClassifyCompoundFile(const Bytes: TBytes; out Rejected: TExtractResult): Boolean;
begin
  Result := IsCompoundFile(Bytes);
  if not Result then
    Exit;
  if HasEncryptedPackageStream(Bytes) then
    Rejected := MakeExtractResult(eoEncrypted, '', 'password required')
  else
    Rejected := MakeExtractResult(eoUnsupported, '', 'legacy binary Office file');
end;

end.
