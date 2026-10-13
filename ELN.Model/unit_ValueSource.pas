unit unit_ValueSource;

interface

uses
  System.SysUtils,
  unit_ItemTypes,
  unit_Item;

type
  TValueSourceInfo = record
    Kind: TValueSourceKind;
    FileId: Int64;
    ReaderId: string;
    ReaderVersion: string;
    KeyName: string;
    Note: string;
    class function Unknown: TValueSourceInfo; static;
    class function Manual(const ANote: string = '';
      AFileId: Int64 = 0): TValueSourceInfo; static;
    class function Reader(AFileId: Int64; const AReaderId, AReaderVersion,
      AKeyName: string): TValueSourceInfo; static;
  end;

  EValueSourceError = class(Exception);

function SourceKindName(Kind: TValueSourceKind): string;
function TryParseSourceKind(const Name: string; out Kind: TValueSourceKind): Boolean;

procedure ValidateSource(const Source: TValueSourceInfo);
procedure ApplySource(Value: TValue; const Source: TValueSourceInfo);
function ReadSource(Value: TValue): TValueSourceInfo;
procedure MarkManualEdit(Value: TValue);

implementation

uses
  Aurelius.Types.Nullable;

const
  MAX_READER_ID = 100;
  MAX_READER_VERSION = 50;
  MAX_KEY_NAME = 255;
  MAX_SOURCE_NOTE = 1000;

class function TValueSourceInfo.Unknown: TValueSourceInfo;
begin
  Result := Default(TValueSourceInfo);
  Result.Kind := vskUnknown;
end;

class function TValueSourceInfo.Manual(const ANote: string;
  AFileId: Int64): TValueSourceInfo;
begin
  Result := Default(TValueSourceInfo);
  Result.Kind := vskManual;
  Result.FileId := AFileId;
  Result.Note := ANote;
end;

class function TValueSourceInfo.Reader(AFileId: Int64; const AReaderId,
  AReaderVersion, AKeyName: string): TValueSourceInfo;
begin
  Result := Default(TValueSourceInfo);
  Result.Kind := vskReader;
  Result.FileId := AFileId;
  Result.ReaderId := AReaderId;
  Result.ReaderVersion := AReaderVersion;
  Result.KeyName := AKeyName;
end;

function SourceKindName(Kind: TValueSourceKind): string;
begin
  case Kind of
    vskReader: Result := 'Reader';
    vskManual: Result := 'Manual';
  else
    Result := 'Unknown';
  end;
end;

function TryParseSourceKind(const Name: string; out Kind: TValueSourceKind): Boolean;
begin
  Result := True;
  if SameText(Name, 'Reader') then
    Kind := vskReader
  else if SameText(Name, 'Manual') then
    Kind := vskManual
  else if SameText(Name, 'Unknown') then
    Kind := vskUnknown
  else
    Result := False;
end;

procedure CheckLength(const Field, Text: string; MaxLen: Integer);
begin
  if Length(Text) > MaxLen then
    raise EValueSourceError.CreateFmt('%s exceeds %d characters', [Field, MaxLen]);
end;

procedure ValidateSource(const Source: TValueSourceInfo);
begin
  CheckLength('reader_id', Source.ReaderId, MAX_READER_ID);
  CheckLength('reader_version', Source.ReaderVersion, MAX_READER_VERSION);
  CheckLength('key_name', Source.KeyName, MAX_KEY_NAME);
  CheckLength('source_note', Source.Note, MAX_SOURCE_NOTE);
  if Source.FileId < 0 then
    raise EValueSourceError.Create('source_file_id must be positive');
  case Source.Kind of
    vskReader:
      begin
        if Source.FileId = 0 then
          raise EValueSourceError.Create('A Reader source requires source_file_id');
        if Trim(Source.ReaderId) = '' then
          raise EValueSourceError.Create('A Reader source requires reader_id');
        if Trim(Source.KeyName) = '' then
          raise EValueSourceError.Create('A Reader source requires key_name');
      end;
    vskManual:
      if (Source.ReaderId <> '') or (Source.ReaderVersion <> '') or
        (Source.KeyName <> '') then
        raise EValueSourceError.Create(
          'reader_id, reader_version and key_name apply only to a Reader source');
    vskUnknown:
      if (Source.FileId <> 0) or (Source.ReaderId <> '') or
        (Source.ReaderVersion <> '') or (Source.KeyName <> '') or
        (Source.Note <> '') then
        raise EValueSourceError.Create(
          'An Unknown source takes no source fields; use Reader or Manual');
  end;
end;

procedure ApplySource(Value: TValue; const Source: TValueSourceInfo);
begin
  ValidateSource(Source);
  Value.SourceKind := Source.Kind;
  if Source.FileId > 0 then
    Value.SourceFileId := Source.FileId
  else
    Value.SourceFileId := SNull;
  Value.ReaderId := Source.ReaderId;
  if (Source.Kind = vskReader) and (Trim(Source.ReaderVersion) = '') then
    Value.ReaderVersion := 'unknown'
  else
    Value.ReaderVersion := Source.ReaderVersion;
  Value.KeyName := Source.KeyName;
  Value.SourceNote := Source.Note;
end;

function ReadSource(Value: TValue): TValueSourceInfo;
begin
  Result := Default(TValueSourceInfo);
  Result.Kind := Value.EffectiveSourceKind;
  if Value.SourceFileId.HasValue then
    Result.FileId := Value.SourceFileId.Value;
  Result.ReaderId := Value.ReaderId;
  Result.ReaderVersion := Value.ReaderVersion;
  Result.KeyName := Value.KeyName;
  Result.Note := Value.SourceNote;
end;

procedure MarkManualEdit(Value: TValue);
var
  Previous: TValueSourceInfo;
  Note: string;
begin
  Previous := ReadSource(Value);
  if Previous.Kind = vskReader then
    Note := Format('Edited by hand; was %s %s key "%s"',
      [Previous.ReaderId, Previous.ReaderVersion, Previous.KeyName])
  else
    Note := Previous.Note;
  if Length(Note) > MAX_SOURCE_NOTE then
    SetLength(Note, MAX_SOURCE_NOTE);
  ApplySource(Value, TValueSourceInfo.Manual(Note, Previous.FileId));
end;

end.
