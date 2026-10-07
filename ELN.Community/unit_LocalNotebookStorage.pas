unit unit_LocalNotebookStorage;

interface

uses
  System.SysUtils,
  System.Classes,
  unit_NotebookStorage;

type
  // Windows filesystem backend. Every notebook path is relative to FRoot;
  // junctions/symlinks and ambiguous Windows path aliases are refused.
  TLocalNotebookStorage = class(TInterfacedObject, INotebookStorage, IFileRelocator,
    INotebookStorageInspection)
  private
    FRoot: string;
    procedure RejectReparsePoints(const FullPath: string);
    procedure EnsureParent(const FullPath: string);
    procedure ValidateRelativePath(const RelativePath: string);
    procedure WriteStream(const RelativePath: string; Source: TStream);
  public
    constructor Create(const Root: string);
    function ResolvePath(const RelativePath: string): string;
    function ReadBytes(const RelativePath: string): TBytes;
    procedure WriteBytes(const RelativePath: string; const Data: TBytes);
    procedure CopyIn(const SourcePath, RelativePath: string);
    procedure CopyOut(const RelativePath, TargetPath: string);
    procedure MoveFile(const OldPath, NewPath: string);
    function Exists(const RelativePath: string): Boolean;
    procedure DeleteFile(const RelativePath: string);
    function TryGetFileInfo(const RelativePath: string;
      out StatusCode: Integer; out ContentLength: Int64): Boolean;
    function ListCollection(const RelativePath: string;
      out Names: TArray<string>): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows;

function IsAbsolutePath(const Path: string): Boolean;
begin
  Result := ((Length(Path) >= 3) and (Path[2] = ':') and
    CharInSet(Path[3], ['\', '/'])) or StartsStr('\\', Path);
end;

function IsDeviceName(const Name: string): Boolean;
var
  Base: string;
  Dot: Integer;
begin
  Dot := Pos('.', Name);
  if Dot > 0 then
    Base := UpperCase(Copy(Name, 1, Dot - 1))
  else
    Base := UpperCase(Name);
  Result := (Base = 'CON') or (Base = 'PRN') or (Base = 'AUX') or
    (Base = 'NUL') or (Base = 'CONIN$') or (Base = 'CONOUT$') or
    ((Length(Base) = 4) and
     ((Copy(Base, 1, 3) = 'COM') or (Copy(Base, 1, 3) = 'LPT')) and
     CharInSet(Base[4], ['1'..'9', #$00B9, #$00B2, #$00B3]));
end;

constructor TLocalNotebookStorage.Create(const Root: string);
begin
  inherited Create;
  if (Trim(Root) = '') or not IsAbsolutePath(Root) or
    StartsStr('\\?\', Root) or StartsStr('\\.\', Root) then
    raise EArgumentException.Create('Notebook storage requires an absolute directory');
  FRoot := TPath.GetFullPath(Root);
  RejectReparsePoints(FRoot);
  if System.IOUtils.TFile.Exists(FRoot) then
    raise EArgumentException.Create('Notebook storage root is a file');
end;

procedure TLocalNotebookStorage.ValidateRelativePath(const RelativePath: string);
var
  Part, Normalized: string;
  C: Char;
begin
  if (RelativePath = '') or CharInSet(RelativePath[1], ['\', '/']) or
    (Pos(':', RelativePath) > 0) then
    raise EArgumentException.Create('A notebook path must be relative');
  Normalized := RelativePath.Replace('/', '\');
  for Part in Normalized.Split(['\']) do
  begin
    if (Part = '') or (Part = '.') or (Part = '..') then
      raise EArgumentException.Create('Empty or traversal path component');
    if CharInSet(Part[Length(Part)], [' ', '.']) or IsDeviceName(Part) then
      raise EArgumentException.Create('Ambiguous or reserved Windows filename');
    for C in Part do
      if not TPath.IsValidFileNameChar(C) then
        raise EArgumentException.Create('Invalid notebook filename');
  end;
end;

procedure TLocalNotebookStorage.RejectReparsePoints(const FullPath: string);
var
  Current, Parent: string;
  Attributes, ErrorCode: DWORD;
begin
  Current := FullPath;
  while Current <> '' do
  begin
    Attributes := GetFileAttributes(PChar(Current));
    if Attributes <> INVALID_FILE_ATTRIBUTES then
    begin
      if (Attributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        raise EArgumentException.Create('Notebook storage cannot traverse a reparse point');
    end
    else
    begin
      ErrorCode := GetLastError;
      if not (ErrorCode in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
        RaiseLastOSError(ErrorCode);
    end;
    Parent := ExtractFileDir(Current);
    if SameText(Parent, Current) then
      Break;
    Current := Parent;
  end;
end;

function TLocalNotebookStorage.ResolvePath(const RelativePath: string): string;
var
  Prefix: string;
begin
  ValidateRelativePath(RelativePath);
  Result := TPath.GetFullPath(TPath.Combine(FRoot, RelativePath.Replace('/', '\')));
  Prefix := IncludeTrailingPathDelimiter(FRoot);
  if not StartsText(Prefix, Result) then
    raise EArgumentException.Create('Notebook path escapes its storage root');
  RejectReparsePoints(Result);
end;

procedure TLocalNotebookStorage.EnsureParent(const FullPath: string);
var
  Parent: string;
begin
  Parent := ExtractFileDir(FullPath);
  RejectReparsePoints(Parent);
  if not ForceDirectories(Parent) then
    raise EInOutError.Create('Could not create notebook storage directory');
  RejectReparsePoints(Parent);
end;

function TLocalNotebookStorage.Exists(const RelativePath: string): Boolean;
begin
  Result := System.IOUtils.TFile.Exists(ResolvePath(RelativePath));
end;

function TLocalNotebookStorage.ReadBytes(const RelativePath: string): TBytes;
begin
  Result := System.IOUtils.TFile.ReadAllBytes(ResolvePath(RelativePath));
end;

procedure TLocalNotebookStorage.WriteBytes(const RelativePath: string;
  const Data: TBytes);
var
  Source: TBytesStream;
begin
  Source := TBytesStream.Create(Data);
  try
    WriteStream(RelativePath, Source);
  finally
    Source.Free;
  end;
end;

procedure TLocalNotebookStorage.WriteStream(const RelativePath: string;
  Source: TStream);
var
  Target, Temporary: string;
  Id: TGUID;
  Stream: TFileStream;
  Buffer: array[0..65535] of Byte;
  Count: Integer;
begin
  Target := ResolvePath(RelativePath);
  EnsureParent(Target);
  CreateGUID(Id);
  Temporary := TPath.Combine(ExtractFileDir(Target), '.eln-' + GUIDToString(Id) + '.tmp');
  try
    Stream := TFileStream.Create(Temporary, fmCreate);
    try
      repeat
        Count := Source.Read(Buffer, SizeOf(Buffer));
        if Count > 0 then
          Stream.WriteBuffer(Buffer, Count);
      until Count = 0;
      if not FlushFileBuffers(Stream.Handle) then
        RaiseLastOSError;
    finally
      Stream.Free;
    end;
    RejectReparsePoints(Target);
    if not MoveFileEx(PChar(Temporary), PChar(Target),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  finally
    if System.IOUtils.TFile.Exists(Temporary) then
      System.IOUtils.TFile.Delete(Temporary);
  end;
end;

procedure TLocalNotebookStorage.CopyIn(const SourcePath, RelativePath: string);
var
  Source: TFileStream;
begin
  if not IsAbsolutePath(SourcePath) then
    raise EArgumentException.Create('Copy source must be absolute');
  // Validate destination before reading a potentially large source file.
  ResolvePath(RelativePath);
  Source := TFileStream.Create(SourcePath, fmOpenRead or fmShareDenyWrite);
  try
    WriteStream(RelativePath, Source);
  finally
    Source.Free;
  end;
end;

procedure TLocalNotebookStorage.CopyOut(const RelativePath, TargetPath: string);
var
  Source, Target: string;
begin
  if not IsAbsolutePath(TargetPath) then
    raise EArgumentException.Create('Copy destination must be absolute');
  Source := ResolvePath(RelativePath);
  if not System.IOUtils.TFile.Exists(Source) then
    raise EFileNotFoundException.Create('Notebook attachment to export does not exist');
  Target := TPath.GetFullPath(TargetPath);
  if SameText(Source, Target) then
    Exit;
  if not ForceDirectories(ExtractFileDir(Target)) then
    raise EInOutError.Create('Could not create copy destination');
  System.IOUtils.TFile.Copy(Source, Target, True);
end;

procedure TLocalNotebookStorage.MoveFile(const OldPath, NewPath: string);
var
  Source, Target: string;
begin
  Source := ResolvePath(OldPath);
  Target := ResolvePath(NewPath);
  if not System.IOUtils.TFile.Exists(Source) then
    raise EFileNotFoundException.Create('Notebook attachment to move does not exist');
  if SameText(Source, Target) then
    Exit;
  if System.IOUtils.TFile.Exists(Target) or TDirectory.Exists(Target) then
    raise EInOutError.Create('Notebook move destination already exists');
  EnsureParent(Target);
  System.IOUtils.TFile.Move(Source, Target);
end;

procedure TLocalNotebookStorage.DeleteFile(const RelativePath: string);
var
  Path: string;
  ErrorCode: DWORD;
begin
  Path := ResolvePath(RelativePath);
  if not Winapi.Windows.DeleteFile(PChar(Path)) then
  begin
    ErrorCode := GetLastError;
    if not (ErrorCode in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
      RaiseLastOSError(ErrorCode);
  end;
end;

function TLocalNotebookStorage.TryGetFileInfo(const RelativePath: string;
  out StatusCode: Integer; out ContentLength: Int64): Boolean;
var
  Path: string;
  Data: TWin32FileAttributeData;
  ErrorCode: DWORD;
begin
  StatusCode := 0;
  ContentLength := 0;
  Path := ResolvePath(RelativePath);
  Result := GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Data);
  if not Result then
  begin
    ErrorCode := GetLastError;
    if ErrorCode in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND] then
      StatusCode := 404
    else
      RaiseLastOSError(ErrorCode);
    Exit;
  end;
  if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
    raise EInOutError.Create('Notebook attachment path is a directory');
  ContentLength := (Int64(Data.nFileSizeHigh) shl 32) or Data.nFileSizeLow;
  StatusCode := 200;
end;

function TLocalNotebookStorage.ListCollection(const RelativePath: string;
  out Names: TArray<string>): Boolean;
var
  Path, Name: string;
  Search: TSearchRec;
  Code, Count: Integer;
  Attributes: DWORD;
begin
  Names := nil;
  Path := ResolvePath(RelativePath);
  Attributes := GetFileAttributes(PChar(Path));
  if Attributes = INVALID_FILE_ATTRIBUTES then
  begin
    Code := GetLastError;
    if Code in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND] then
      Exit(True);
    RaiseLastOSError(Code);
  end;
  if (Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
    raise EInOutError.Create('Notebook collection path is not a directory');
  Count := 0;
  Code := FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, Search);
  if Code = 0 then
  try
    repeat
      Name := Search.Name;
      if (Name <> '.') and (Name <> '..') then
      begin
        // Validate each returned child before exposing it to a repair hunt.
        ResolvePath(RelativePath + '/' + Name);
        if Count = Length(Names) then
          SetLength(Names, Count + 16);
        Names[Count] := Name;
        Inc(Count);
      end;
      Code := FindNext(Search);
    until Code <> 0;
  finally
    System.SysUtils.FindClose(Search);
  end;
  if not (Code in [ERROR_NO_MORE_FILES, ERROR_FILE_NOT_FOUND]) then
    RaiseLastOSError(Code);
  SetLength(Names, Count);
  Result := True;
end;

end.
