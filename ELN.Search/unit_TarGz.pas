unit unit_TarGz;

interface

uses
  System.SysUtils, unit_TextEmbedder;

procedure ExtractTarGzEntries(const ArchivePath: string; const Wanted: TArray<string>;
  const TargetOf: TFunc<string, string>; const Cancelled: TCancelCheck);

implementation

uses
  System.Classes, System.IOUtils, System.ZLib, System.Generics.Collections, unit_SearchArtifacts;

const
  BlockSize = 512;
  GzipWindowBits = 15 + 16;
  CopyBufferSize = 256 * 1024;
  MaxLongNameBytes = 65536;
  NameOffset = 0;
  NameLength = 100;
  SizeOffset = 124;
  SizeLength = 12;
  ChecksumOffset = 148;
  ChecksumLength = 8;
  TypeOffset = 156;
  MagicOffset = 257;
  PrefixOffset = 345;
  PrefixLength = 155;

type
  TTarReader = class
  private
    FSource: TStream;
    FCancelled: TCancelCheck;
    function ReadFully(var Buffer; Count: Integer): Integer;
    procedure Discard(Count: Int64);
  public
    constructor Create(const Source: TStream; const Cancelled: TCancelCheck);
    procedure CheckCancelled;
    function ReadBlock(var Block: TBytes): Boolean;
    function ReadLongName(Size: Int64): string;
    procedure Skip(Size: Int64);
    procedure CopyTo(Dest: TStream; Size: Int64);
  end;

function PaddedSize(Size: Int64): Int64;
begin
  Result := (Size + BlockSize - 1) div BlockSize * BlockSize;
end;

function NormalizeEntryName(const Name: string): string;
begin
  Result := Name.Replace('\', '/');
  while Result.StartsWith('./') do
    Result := Result.Substring(2);
end;

function CStringAt(const Block: TBytes; Offset, MaxLength: Integer): string;
var
  Len: Integer;
begin
  Len := 0;
  while (Len < MaxLength) and (Block[Offset + Len] <> 0) do
    Inc(Len);
  Result := TEncoding.UTF8.GetString(Block, Offset, Len);
end;

function OctalAt(const Block: TBytes; Offset, Count: Integer): Int64;
var
  I, Digit: Integer;
  Seen: Boolean;
begin
  Result := 0;
  Seen := False;
  for I := Offset to Offset + Count - 1 do
  begin
    if (Block[I] = 0) or (Block[I] = Ord(' ')) then
    begin
      if Seen then
        Break;
      Continue;
    end;
    Digit := Block[I] - Ord('0');
    if (Digit < 0) or (Digit > 7) then
      raise ESearchArtifactError.Create('Tar archive has a malformed header');
    Seen := True;
    Result := Result * 8 + Digit;
  end;
end;

function HeaderChecksumValid(const Block: TBytes): Boolean;
var
  I: Integer;
  Sum: Int64;
begin
  Sum := 0;
  for I := 0 to BlockSize - 1 do
    if (I >= ChecksumOffset) and (I < ChecksumOffset + ChecksumLength) then
      Inc(Sum, Ord(' '))
    else
      Inc(Sum, Block[I]);
  Result := Sum = OctalAt(Block, ChecksumOffset, ChecksumLength);
end;

function IsZeroBlock(const Block: TBytes): Boolean;
var
  B: Byte;
begin
  for B in Block do
    if B <> 0 then
      Exit(False);
  Result := True;
end;

function HeaderName(const Block: TBytes): string;
var
  Prefix: string;
begin
  Result := CStringAt(Block, NameOffset, NameLength);
  if CStringAt(Block, MagicOffset, 5) = 'ustar' then
  begin
    Prefix := CStringAt(Block, PrefixOffset, PrefixLength);
    if Prefix <> '' then
      Result := Prefix + '/' + Result;
  end;
end;

procedure RequireSafeName(const Name: string);
var
  Segment: string;
begin
  if (Name = '') or Name.StartsWith('/') or Name.Contains(':') then
    raise ESearchArtifactError.CreateFmt('Tar entry has an unsafe name: "%s"', [Name]);
  for Segment in Name.Split(['/']) do
    if Segment = '..' then
      raise ESearchArtifactError.CreateFmt('Tar entry has an unsafe name: "%s"', [Name]);
end;

{ TTarReader }

constructor TTarReader.Create(const Source: TStream; const Cancelled: TCancelCheck);
begin
  inherited Create;
  FSource := Source;
  FCancelled := Cancelled;
end;

procedure TTarReader.CheckCancelled;
begin
  if Assigned(FCancelled) and FCancelled() then
    raise EOperationCancelled.Create('Search artifact installation was cancelled');
end;

function TTarReader.ReadFully(var Buffer; Count: Integer): Integer;
var
  Got: Integer;
begin
  Result := 0;
  while Result < Count do
  begin
    Got := FSource.Read(PByte(@Buffer)[Result], Count - Result);
    if Got <= 0 then
      Break;
    Inc(Result, Got);
  end;
end;

function TTarReader.ReadBlock(var Block: TBytes): Boolean;
var
  Got: Integer;
begin
  SetLength(Block, BlockSize);
  Got := ReadFully(Block[0], BlockSize);
  if Got = 0 then
    Exit(False);
  if Got < BlockSize then
    raise ESearchArtifactError.Create('Tar archive is truncated');
  Result := True;
end;

function TTarReader.ReadLongName(Size: Int64): string;
var
  Buffer: TBytes;
  Padded, Len: Integer;
begin
  if (Size < 0) or (Size > MaxLongNameBytes) then
    raise ESearchArtifactError.Create('Tar archive has an invalid long name entry');
  Padded := Integer(PaddedSize(Size));
  SetLength(Buffer, Padded);
  if (Padded > 0) and (ReadFully(Buffer[0], Padded) < Padded) then
    raise ESearchArtifactError.Create('Tar archive is truncated');
  Len := 0;
  while (Len < Size) and (Buffer[Len] <> 0) do
    Inc(Len);
  Result := TEncoding.UTF8.GetString(Buffer, 0, Len);
end;

procedure TTarReader.Discard(Count: Int64);
var
  Chunk: Integer;
  Buffer: TBytes;
begin
  SetLength(Buffer, CopyBufferSize);
  while Count > 0 do
  begin
    CheckCancelled;
    if Count > Length(Buffer) then
      Chunk := Length(Buffer)
    else
      Chunk := Integer(Count);
    if ReadFully(Buffer[0], Chunk) < Chunk then
      raise ESearchArtifactError.Create('Tar archive is truncated');
    Dec(Count, Chunk);
  end;
end;

procedure TTarReader.Skip(Size: Int64);
begin
  Discard(PaddedSize(Size));
end;

procedure TTarReader.CopyTo(Dest: TStream; Size: Int64);
var
  Remaining: Int64;
  Chunk: Integer;
  Buffer: TBytes;
begin
  Remaining := Size;
  SetLength(Buffer, CopyBufferSize);
  while Remaining > 0 do
  begin
    CheckCancelled;
    if Remaining > Length(Buffer) then
      Chunk := Length(Buffer)
    else
      Chunk := Integer(Remaining);
    if ReadFully(Buffer[0], Chunk) < Chunk then
      raise ESearchArtifactError.Create('Tar archive is truncated');
    Dest.WriteBuffer(Buffer[0], Chunk);
    Dec(Remaining, Chunk);
  end;
  Discard(PaddedSize(Size) - Size);
end;

procedure WriteEntry(Reader: TTarReader; const Target: string; Size: Int64);
var
  Dest: TFileStream;
begin
  TDirectory.CreateDirectory(ExtractFileDir(Target));
  Dest := TFileStream.Create(Target, fmCreate);
  try
    try
      Reader.CopyTo(Dest, Size);
    finally
      Dest.Free;
    end;
  except
    on Exception do
    begin
      if TFile.Exists(Target) then
        TFile.Delete(Target);
      raise;
    end;
  end;
end;

procedure ExtractEntries(Reader: TTarReader; Pending: TDictionary<string, Boolean>;
  const TargetOf: TFunc<string, string>);
var
  Block: TBytes;
  Name, LongName: string;
  TypeFlag: Char;
  Size: Int64;
  HasLongName: Boolean;
begin
  HasLongName := False;
  while (Pending.Count > 0) and Reader.ReadBlock(Block) do
  begin
    Reader.CheckCancelled;
    if IsZeroBlock(Block) then
      Break;
    if not HeaderChecksumValid(Block) then
      raise ESearchArtifactError.Create('Tar archive has a corrupt header');
    Size := OctalAt(Block, SizeOffset, SizeLength);
    TypeFlag := Char(Block[TypeOffset]);
    if TypeFlag = 'L' then
    begin
      LongName := Reader.ReadLongName(Size);
      HasLongName := True;
      Continue;
    end;
    if HasLongName then
      Name := LongName
    else
      Name := HeaderName(Block);
    HasLongName := False;
    Name := NormalizeEntryName(Name);
    if ((TypeFlag = '0') or (TypeFlag = #0)) and Pending.ContainsKey(Name) then
    begin
      RequireSafeName(Name);
      WriteEntry(Reader, TargetOf(Name), Size);
      Pending.Remove(Name);
    end
    else
      Reader.Skip(Size);
  end;
end;

procedure ExtractTarGzEntries(const ArchivePath: string; const Wanted: TArray<string>;
  const TargetOf: TFunc<string, string>; const Cancelled: TCancelCheck);
var
  Pending: TDictionary<string, Boolean>;
  Name: string;
  FileStream: TFileStream;
  Gzip: TZDecompressionStream;
  Reader: TTarReader;
begin
  Pending := TDictionary<string, Boolean>.Create;
  try
    for Name in Wanted do
      Pending.AddOrSetValue(NormalizeEntryName(Name), True);
    FileStream := TFileStream.Create(ArchivePath, fmOpenRead or fmShareDenyWrite);
    try
      Gzip := TZDecompressionStream.Create(FileStream, GzipWindowBits);
      try
        Reader := TTarReader.Create(Gzip, Cancelled);
        try
          try
            ExtractEntries(Reader, Pending, TargetOf);
          except
            on E: EZLibError do
              raise ESearchArtifactError.CreateFmt('Tar archive cannot be decompressed: %s', [E.Message]);
          end;
        finally
          Reader.Free;
        end;
      finally
        Gzip.Free;
      end;
    finally
      FileStream.Free;
    end;
    for Name in Pending.Keys do
      raise ESearchArtifactError.CreateFmt('Archive does not contain: %s', [Name]);
  finally
    Pending.Free;
  end;
end;

end.
