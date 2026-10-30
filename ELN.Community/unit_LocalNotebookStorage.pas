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
    INotebookStorageInspection, INotebookStorageStamp, INotebookStorageUpdates)
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
    function TryGetFileStamp(const RelativePath: string;
      out Size, LastWrite: Int64): Boolean;
    function BeginFileUpdate(const RelativePath: string): INotebookFileUpdate;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows;

type
  TLocalFileUpdate = class(TInterfacedObject, INotebookFileUpdate)
  private
    FStorage: TLocalNotebookStorage;
    FStorageRef: INotebookStorage;
    FTarget, FOriginalPath, FInstalledPath: string;
    FOriginal, FInstalled: THandle;
    FDirectories: TArray<THandle>;
    FFinished: Boolean;
    procedure RenameHandle(Handle: THandle; const Target: string);
    procedure PinDirectories;
    procedure ReleaseHandles;
  public
    constructor Create(Storage: TLocalNotebookStorage; const RelativePath: string);
    destructor Destroy; override;
    function Exists: Boolean;
    function OpenRead: TStream;
    procedure CopyOut(const TargetPath: string);
    procedure InstallFrom(const SourcePath: string);
    procedure Rollback;
    procedure Commit;
  end;

  // FILE_RENAME_INFORMATION layout, with ReplaceIfExists=False (zero DWORD).
  // Native alignment is required for the pointer-sized RootDirectory field.
  PLocalRenameInfo = ^TLocalRenameInfo;
  TLocalRenameInfo = record
    ReplaceIfExists: DWORD;
    RootDirectory: THandle;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;

  TLocalIoStatusBlock = record
    StatusOrPointer: NativeUInt;
    Information: NativeUInt;
  end;

function SetNativeFileInformation(Handle: THandle;
  out IoStatus: TLocalIoStatusBlock; Information: Pointer;
  BufferSize: DWORD; InformationClass: Integer): LongInt; stdcall;
  external 'ntdll.dll' name 'NtSetInformationFile';

function NativeStatusToDosError(Status: LongInt): DWORD; stdcall;
  external 'ntdll.dll' name 'RtlNtStatusToDosError';

function SetLocalFileInformation(Handle: THandle; InformationClass: Integer;
  Information: Pointer; BufferSize: DWORD): BOOL; stdcall;
  external kernel32 name 'SetFileInformationByHandle';

function IsAbsolutePath(const Path: string): Boolean; forward;

function NewUpdatePath(const Target: string): string;
var
  Id: TGUID;
begin
  CreateGUID(Id);
  Result := TPath.Combine(ExtractFileDir(Target), '.eln-' + GUIDToString(Id) + '.tmp');
end;

procedure RaiseGuardError(const Operation, Path: string; Code: DWORD);
var
  Error: EOSError;
begin
  Error := EOSError.CreateFmt('%s "%s": %s (Win32 %d)',
    [Operation, Path, SysErrorMessage(Code), Code]);
  Error.ErrorCode := Code;
  raise Error;
end;

constructor TLocalFileUpdate.Create(Storage: TLocalNotebookStorage;
  const RelativePath: string);
var
  Code: DWORD;
  Info: TByHandleFileInformation;
begin
  inherited Create;
  FOriginal := INVALID_HANDLE_VALUE;
  FInstalled := INVALID_HANDLE_VALUE;
  FStorage := Storage;
  FStorageRef := Storage;
  FTarget := Storage.ResolvePath(RelativePath);
  PinDirectories;
  FOriginal := CreateFile(PChar(FTarget), GENERIC_READ or Winapi.Windows._DELETE, 0, nil,
    OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, 0);
  if FOriginal = INVALID_HANDLE_VALUE then
  begin
    Code := GetLastError;
    if Code = ERROR_FILE_NOT_FOUND then Exit;
    RaiseGuardError('Open guarded attachment', FTarget, Code);
  end;
  if not GetFileInformationByHandle(FOriginal, Info) then RaiseLastOSError;
  if (Info.dwFileAttributes and (FILE_ATTRIBUTE_REPARSE_POINT or FILE_ATTRIBUTE_DIRECTORY)) <> 0 then
    raise EArgumentException.Create('A guarded attachment must be a regular file');
end;

procedure TLocalFileUpdate.PinDirectories;
var
  Path, Parent: string;
  Paths: TStringList;
  Handle: THandle;
  Info: TByHandleFileInformation;
  I: Integer;
  Code: DWORD;
begin
  Paths := TStringList.Create;
  try
    Path := ExtractFileDir(FTarget);
    while Path <> '' do
    begin
      Paths.Add(Path);
      Parent := ExtractFileDir(Path);
      if SameText(Parent, Path) then Break;
      Path := Parent;
    end;
    SetLength(FDirectories, Paths.Count);
    for I := 0 to High(FDirectories) do FDirectories[I] := INVALID_HANDLE_VALUE;
    // Pin root to leaf. A child is inspected or created only after its parent
    // is protected, so no unpinned ancestor can redirect subsequent opens.
    // Deny write as well as delete: an empty directory can otherwise be
    // converted to a junction in place while its name remains pinned.
    for I := Paths.Count - 1 downto 0 do
    begin
      Path := Paths[I];
      Handle := CreateFile(PChar(Path), FILE_LIST_DIRECTORY or FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ, nil, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT, 0);
      if Handle = INVALID_HANDLE_VALUE then
      begin
        Code := GetLastError;
        if not (Code in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
          RaiseGuardError('Pin directory', Path, Code);
        // Unlike ForceDirectories, this creates one child of a pinned parent.
        if not CreateDirectory(PChar(Path), nil) then
        begin
          Code := GetLastError;
          if Code <> ERROR_ALREADY_EXISTS then
            RaiseGuardError('Create guarded directory', Path, Code);
        end;
        Handle := CreateFile(PChar(Path), FILE_LIST_DIRECTORY or FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ, nil, OPEN_EXISTING,
          FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OPEN_REPARSE_POINT, 0);
        if Handle = INVALID_HANDLE_VALUE then
          RaiseGuardError('Pin newly created directory', Path, GetLastError);
      end;
      FDirectories[I] := Handle;
      if not GetFileInformationByHandle(Handle, Info) then RaiseLastOSError;
      if (Info.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        raise EArgumentException.Create('Notebook storage cannot traverse a reparse point');
      if (Info.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
        raise EArgumentException.Create('Notebook storage parent must be a directory');
    end;
  finally
    Paths.Free;
  end;
end;

procedure TLocalFileUpdate.ReleaseHandles;
var
  Handle: THandle;
  DeleteOnClose: BOOL;
begin
  // Mark only owned retired handles for deletion, before closing them. There
  // is no close/delete-by-name race that could remove another writer's file.
  // Cleanup never raises after DB commit; failure leaves a recovery file.
  DeleteOnClose := True;
  if FOriginal <> INVALID_HANDLE_VALUE then
  begin
    if FFinished and (FOriginalPath <> '') then
      SetLocalFileInformation(FOriginal, 4, @DeleteOnClose, SizeOf(DeleteOnClose));
    CloseHandle(FOriginal);
    FOriginal := INVALID_HANDLE_VALUE;
  end;
  if FInstalled <> INVALID_HANDLE_VALUE then
  begin
    if FInstalledPath <> '' then
      SetLocalFileInformation(FInstalled, 4, @DeleteOnClose, SizeOf(DeleteOnClose));
    CloseHandle(FInstalled);
    FInstalled := INVALID_HANDLE_VALUE;
  end;
  for Handle in FDirectories do
    if Handle <> INVALID_HANDLE_VALUE then CloseHandle(Handle);
  FDirectories := nil;
end;

destructor TLocalFileUpdate.Destroy;
begin
  ReleaseHandles;
  inherited Destroy;
end;

function TLocalFileUpdate.Exists: Boolean;
begin
  Result := (FOriginal <> INVALID_HANDLE_VALUE) or
    ((FInstalled <> INVALID_HANDLE_VALUE) and (FInstalledPath = ''));
end;

function TLocalFileUpdate.OpenRead: TStream;
var
  Handle: THandle;
begin
  if (FInstalled <> INVALID_HANDLE_VALUE) and (FInstalledPath = '') then
    Handle := FInstalled
  else
    Handle := FOriginal;
  if Handle = INVALID_HANDLE_VALUE then
    raise EFileNotFoundException.Create('Notebook attachment does not exist');
  Result := THandleStream.Create(Handle);
  try
    Result.Position := 0;
  except
    Result.Free;
    raise;
  end;
end;

procedure TLocalFileUpdate.CopyOut(const TargetPath: string);
var
  Source: TStream;
  Target: TFileStream;
begin
  if not IsAbsolutePath(TargetPath) then
    raise EArgumentException.Create('Copy destination must be absolute');
  Source := OpenRead;
  try
    if not ForceDirectories(ExtractFileDir(TargetPath)) then
      raise EInOutError.Create('Could not create backup directory');
    Target := TFileStream.Create(TargetPath, fmCreate);
    try
      Target.CopyFrom(Source, 0);
      if not FlushFileBuffers(Target.Handle) then RaiseLastOSError;
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TLocalFileUpdate.RenameHandle(Handle: THandle; const Target: string);
var
  Info: PLocalRenameInfo;
  Size: DWORD;
  Name: string;
  IoStatus: TLocalIoStatusBlock;
  Status: LongInt;
begin
  if not IsAbsolutePath(Target) or
    not SameText(ExtractFileDir(Target), ExtractFileDir(FTarget)) then
    raise EArgumentException.Create('Guarded rename must remain in the pinned directory');
  FStorage.RejectReparsePoints(Target);
  Name := ExtractFileName(Target);
  Size := SizeOf(TLocalRenameInfo) + Length(Name) * SizeOf(WideChar);
  GetMem(Info, Size);
  try
    FillChar(Info^, Size, 0);
    Info.FileNameLength := Length(Name) * SizeOf(WideChar);
    Move(PChar(Name)^, Info.FileName[0], Info.FileNameLength);
    // Native FileRenameInformation=10, NULL root and basename means the
    // source handle's own directory, never the process working directory.
    // Unlike the Win32 wrapper, this does not reopen the parent for writing.
    // Keep ReplaceIfExists=False, including during compensation.
    Status := SetNativeFileInformation(Handle, IoStatus, Info, Size, 10);
    if Status < 0 then
      RaiseGuardError('Rename guarded file to', Target, NativeStatusToDosError(Status));
  finally
    FreeMem(Info);
  end;
end;

procedure TLocalFileUpdate.InstallFrom(const SourcePath: string);
var
  Source: TFileStream;
  Target: THandleStream;
  RetiredPath: string;
begin
  if not IsAbsolutePath(SourcePath) then
    raise EArgumentException.Create('Copy source must be absolute');
  if FFinished or (FInstalled <> INVALID_HANDLE_VALUE) then
    raise EInvalidOperation.Create('This file update has already been installed');
  Source := TFileStream.Create(SourcePath, fmOpenRead or fmShareDenyWrite);
  try
    FInstalledPath := NewUpdatePath(FTarget);
    FInstalled := CreateFile(PChar(FInstalledPath),
      GENERIC_READ or GENERIC_WRITE or Winapi.Windows._DELETE, 0, nil, CREATE_NEW,
      FILE_ATTRIBUTE_NORMAL or FILE_FLAG_WRITE_THROUGH, 0);
    if FInstalled = INVALID_HANDLE_VALUE then
    begin
      RaiseGuardError('Create staged attachment', FInstalledPath, GetLastError);
    end;
    Target := THandleStream.Create(FInstalled);
    try
      Target.CopyFrom(Source, 0);
      if not FlushFileBuffers(FInstalled) then
        RaiseGuardError('Flush staged attachment', FInstalledPath, GetLastError);
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
  if FOriginal <> INVALID_HANDLE_VALUE then
  begin
    RetiredPath := NewUpdatePath(FTarget);
    RenameHandle(FOriginal, RetiredPath);
    FOriginalPath := RetiredPath;
  end;
  // The complete new file is already exclusively held before it gets the
  // canonical name. An external creation in the gap wins; we never overwrite it.
  RenameHandle(FInstalled, FTarget);
  FInstalledPath := '';
end;

procedure TLocalFileUpdate.Rollback;
var
  RetiredPath: string;
begin
  if FFinished then Exit;
  try
    if (FInstalled <> INVALID_HANDLE_VALUE) and (FInstalledPath = '') then
    begin
      RetiredPath := NewUpdatePath(FTarget);
      RenameHandle(FInstalled, RetiredPath);
      FInstalledPath := RetiredPath;
    end;
    if FOriginalPath <> '' then
    begin
      RenameHandle(FOriginal, FTarget);
      FOriginalPath := '';
    end;
    FFinished := True;
    ReleaseHandles;
  except
    on E: Exception do
      raise EInOutError.Create(E.Message + '; original file retained at ' + FOriginalPath);
  end;
end;

procedure TLocalFileUpdate.Commit;
begin
  FFinished := True;
  ReleaseHandles;
end;

function TLocalNotebookStorage.BeginFileUpdate(
  const RelativePath: string): INotebookFileUpdate;
begin
  Result := TLocalFileUpdate.Create(Self, RelativePath);
end;

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

function TLocalNotebookStorage.TryGetFileStamp(const RelativePath: string;
  out Size, LastWrite: Int64): Boolean;
var
  Data: TWin32FileAttributeData;
begin
  Size := 0;
  LastWrite := 0;
  Result := GetFileAttributesEx(PChar(ResolvePath(RelativePath)), GetFileExInfoStandard, @Data) and
    ((Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0);
  if Result then
  begin
    Size := (Int64(Data.nFileSizeHigh) shl 32) or Data.nFileSizeLow;
    LastWrite := (Int64(Data.ftLastWriteTime.dwHighDateTime) shl 32) or Data.ftLastWriteTime.dwLowDateTime;
  end;
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
