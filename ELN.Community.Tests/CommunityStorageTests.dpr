program CommunityStorageTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  unit_NotebookStorage in '..\ELN.Model\unit_NotebookStorage.pas',
  unit_LocalNotebookStorage in '..\ELN.Community\unit_LocalNotebookStorage.pas';

var
  FixtureDir, NotebookRoot: string;
  Storage: INotebookStorage;
  LocalStorage: TLocalNotebookStorage;
  Passed, Failed: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckBytes(const Expected, Actual: TBytes; const MessageText: string);
var
  I: Integer;
begin
  Check(Length(Expected) = Length(Actual), MessageText + ': byte count');
  for I := 0 to High(Expected) do
    Check(Expected[I] = Actual[I], MessageText + ': byte ' + IntToStr(I));
end;

procedure MustRaise(const Operation: TProc; const MessageText: string);
var
  RaisedException: Boolean;
begin
  RaisedException := False;
  try
    Operation();
  except
    on E: Exception do
      RaisedException := True;
  end;
  Check(RaisedException, MessageText + ': expected an exception');
end;

function BinaryData: TBytes;
begin
  Result := TBytes.Create(0, 255, 128, 13, 10, 0, 1, 127, 254);
end;

procedure RunTest(const TestName: string; const Test: TProc);
var
  Id: TGUID;
begin
  CreateGUID(Id);
  FixtureDir := TPath.Combine(TPath.GetTempPath,
    'ELN-Community-Storage-' + GUIDToString(Id));
  NotebookRoot := TPath.Combine(FixtureDir, 'notebook');
  LocalStorage := nil;
  Storage := nil;
  try
    ForceDirectories(NotebookRoot);
    LocalStorage := TLocalNotebookStorage.Create(NotebookRoot);
    Storage := LocalStorage;
    try
      Test();
      Inc(Passed);
      WriteLn('PASS ', TestName);
    except
      on E: Exception do
      begin
        Inc(Failed);
        WriteLn('FAIL ', TestName, ': ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    Storage := nil;
    LocalStorage := nil;
    if DirectoryExists(FixtureDir) then
      TDirectory.Delete(FixtureDir, True);
  end;
end;

procedure TestBinaryRoundTrip;
var
  Expected: TBytes;
begin
  Expected := BinaryData;
  Check(not Storage.Exists('nested/data.bin'), 'missing file must not exist');
  Storage.WriteBytes('nested/data.bin', Expected);
  Check(Storage.Exists('nested/data.bin'), 'written file must exist');
  CheckBytes(Expected, Storage.ReadBytes('nested/data.bin'), 'binary round trip');
  Check(FileExists(TPath.Combine(NotebookRoot, 'nested\data.bin')),
    'write must create parent directories');
end;

procedure TestEmptyFileAndOverwrite;
var
  Empty: TBytes;
begin
  Empty := nil;
  Storage.WriteBytes('empty.bin', Empty);
  Check(Storage.Exists('empty.bin'), 'zero-byte file must exist');
  CheckBytes(Empty, Storage.ReadBytes('empty.bin'), 'zero-byte round trip');
  Storage.WriteBytes('empty.bin', BinaryData);
  CheckBytes(BinaryData, Storage.ReadBytes('empty.bin'), 'explicit write overwrite');
end;

procedure TestNativeAndSlashPaths;
begin
  Storage.WriteBytes('nested\native.bin', BinaryData);
  CheckBytes(BinaryData, Storage.ReadBytes('nested/native.bin'),
    'native and forward-slash paths identify the same file');
  Check(SameFileName(LocalStorage.ResolvePath('nested/native.bin'),
    TPath.Combine(NotebookRoot, 'nested\native.bin')), 'resolved root path');
end;

procedure TestNoProtocolPrefixMapping;
begin
  Storage.WriteBytes('files/Projects/item.bin', BinaryData);
  Check(FileExists(TPath.Combine(NotebookRoot, 'files\Projects\item.bin')),
    'provider must preserve literal files prefix');
  Check(not FileExists(TPath.Combine(NotebookRoot, 'Projects\item.bin')),
    'protocol prefix mapping belongs in adapter');
end;

procedure TestRejectedPaths;
var
  BadPath: string;
  BadPaths: TArray<string>;
begin
  BadPaths := TArray<string>.Create('', '..', '../outside.bin',
    '..\outside.bin', 'nested/../outside.bin', 'nested\..\outside.bin',
    '/rooted.bin', '\rooted.bin', 'C:\absolute.bin', 'C:drive-relative.bin',
    '\\server\share\file.bin', TPath.Combine(NotebookRoot, 'absolute.bin'));
  for BadPath in BadPaths do
  begin
    MustRaise(
      procedure
      begin
        LocalStorage.ResolvePath(BadPath);
      end, 'reject unsafe path ' + BadPath);
    MustRaise(
      procedure
      begin
        Storage.WriteBytes(BadPath, BinaryData);
      end, 'reject unsafe write ' + BadPath);
  end;
end;

procedure TestSiblingPrefixProtection;
var
  SiblingRoot, Sentinel: string;
begin
  SiblingRoot := TPath.Combine(FixtureDir, 'notebook-other');
  ForceDirectories(SiblingRoot);
  Sentinel := TPath.Combine(SiblingRoot, 'sentinel.bin');
  TFile.WriteAllBytes(Sentinel, BinaryData);
  MustRaise(
    procedure
    begin
      Storage.WriteBytes('../notebook-other/sentinel.bin', TBytes.Create(7));
    end, 'prefix-sibling traversal must be rejected');
  MustRaise(
    procedure
    begin
      LocalStorage.ResolvePath(Sentinel);
    end, 'absolute prefix-sibling path must be rejected');
  CheckBytes(BinaryData, TFile.ReadAllBytes(Sentinel), 'sibling must remain intact');
end;

procedure TestCopyInAndOut;
var
  SourceFile, TargetFile: string;
begin
  SourceFile := TPath.Combine(FixtureDir, 'import.bin');
  TargetFile := TPath.Combine(FixtureDir, 'exports\out.bin');
  TFile.WriteAllBytes(SourceFile, BinaryData);
  Storage.CopyIn(SourceFile, 'attachments/import.bin');
  CheckBytes(BinaryData, Storage.ReadBytes('attachments/import.bin'), 'copy in');
  Storage.CopyOut('attachments/import.bin', TargetFile);
  CheckBytes(BinaryData, TFile.ReadAllBytes(TargetFile), 'copy out');
  CheckBytes(BinaryData, TFile.ReadAllBytes(SourceFile), 'copy retains source');
end;

procedure TestNestedMove;
var
  Relocator: IFileRelocator;
begin
  Storage.WriteBytes('old/file.bin', BinaryData);
  Relocator := Storage;
  Relocator.MoveFile('old/file.bin', 'new/nested/file.bin');
  Check(not Storage.Exists('old/file.bin'), 'move removes old path');
  CheckBytes(BinaryData, Storage.ReadBytes('new/nested/file.bin'), 'nested move bytes');
end;

procedure TestSamePathMove;
begin
  Storage.WriteBytes('same/file.bin', BinaryData);
  Storage.MoveFile('same/file.bin', 'same\file.bin');
  CheckBytes(BinaryData, Storage.ReadBytes('same/file.bin'),
    'same normalized path move keeps file');
end;

procedure TestMoveCollision;
var
  DestinationData: TBytes;
begin
  DestinationData := TBytes.Create(3, 2, 1);
  Storage.WriteBytes('from.bin', BinaryData);
  Storage.WriteBytes('to.bin', DestinationData);
  MustRaise(
    procedure
    begin
      Storage.MoveFile('from.bin', 'to.bin');
    end, 'move must not overwrite existing destination');
  CheckBytes(BinaryData, Storage.ReadBytes('from.bin'), 'collision retains source');
  CheckBytes(DestinationData, Storage.ReadBytes('to.bin'), 'collision retains target');
end;

procedure TestMissingSources;
var
  OutsideMissing, OutsideTarget: string;
begin
  OutsideMissing := TPath.Combine(FixtureDir, 'not-present.bin');
  OutsideTarget := TPath.Combine(FixtureDir, 'out.bin');
  MustRaise(
    procedure
    begin
      Storage.ReadBytes('missing.bin');
    end, 'missing read');
  MustRaise(
    procedure
    begin
      Storage.MoveFile('missing.bin', 'new/missing.bin');
    end, 'missing move source');
  MustRaise(
    procedure
    begin
      Storage.MoveFile('missing.bin', 'missing.bin');
    end, 'same-path move still rejects missing source');
  MustRaise(
    procedure
    begin
      Storage.CopyIn(OutsideMissing, 'new/import.bin');
    end, 'missing copy-in source');
  MustRaise(
    procedure
    begin
      Storage.CopyOut('missing.bin', OutsideTarget);
    end, 'missing copy-out source');
  MustRaise(
    procedure
    begin
      Storage.CopyOut('missing.bin', TPath.Combine(NotebookRoot, 'missing.bin'));
    end, 'same-path export still rejects missing source');
  Check(not FileExists(OutsideTarget), 'missing copy-out must not create target');
end;

procedure TestMoveRejectsTraversal;
var
  OutsideSource, OutsideEscaped, StolenPath: string;
  OutsideBytes: TBytes;
begin
  OutsideSource := TPath.Combine(FixtureDir, 'outside-source.bin');
  OutsideEscaped := TPath.Combine(FixtureDir, 'escaped.bin');
  StolenPath := TPath.Combine(NotebookRoot, 'stolen.bin');
  OutsideBytes := TBytes.Create(9, 8, 7, 0, 255, 13, 10);
  TFile.WriteAllBytes(OutsideSource, OutsideBytes);
  Storage.WriteBytes('safe.bin', BinaryData);
  MustRaise(
    procedure
    begin
      Storage.MoveFile('safe.bin', '../escaped.bin');
    end, 'move destination traversal');
  MustRaise(
    procedure
    begin
      Storage.MoveFile('../outside-source.bin', 'stolen.bin');
    end, 'move source traversal');
  Check(FileExists(OutsideSource), 'rejected source traversal keeps outside source');
  CheckBytes(OutsideBytes, TFile.ReadAllBytes(OutsideSource), 'outside source bytes unchanged');
  Check(not FileExists(StolenPath), 'rejected source traversal creates no destination');
  Check(not FileExists(OutsideEscaped), 'rejected destination traversal creates no escaped file');
  CheckBytes(BinaryData, Storage.ReadBytes('safe.bin'), 'rejected move retains source');
end;

procedure TestStorageInspection;
var
  Inspection: INotebookStorageInspection;
  Status: Integer;
  Size: Int64;
  Names: TArray<string>;
begin
  Check(Supports(Storage, INotebookStorageInspection, Inspection),
    'local storage must support repair inspection');
  Storage.WriteBytes('Projects/[00001]Lab/[0001]Item/[0001]binary.bin', BinaryData);
  Storage.WriteBytes('Projects/[00001]Lab/[0001]Item/[0002]empty.bin', nil);
  Check(Inspection.TryGetFileInfo(
    'Projects/[00001]Lab/[0001]Item/[0001]binary.bin', Status, Size),
    'nonempty attachment is present');
  Check((Status = 200) and (Size = Length(BinaryData)),
    'inspection reports exact byte length');
  Check(Inspection.TryGetFileInfo(
    'Projects/[00001]Lab/[0001]Item/[0002]empty.bin', Status, Size),
    'empty attachment is present, not missing');
  Check(Size = 0, 'empty attachment has zero length');
  Check(not Inspection.TryGetFileInfo('Projects/missing.bin', Status, Size),
    'missing attachment has no metadata');
  Check(Status = 404, 'missing attachment is confirmed absent');
  Check(Inspection.ListCollection('Projects/[00001]Lab/[0001]Item', Names),
    'attachment collection can be listed');
  Check(Length(Names) = 2, 'listing contains both attachment names');
  Check(Inspection.ListCollection('Projects/absent', Names),
    'absent collection is a successful empty listing');
  Check(Length(Names) = 0, 'missing collection contains no names');
  MustRaise(
    procedure
    begin
      Inspection.ListCollection('../outside', Names);
    end, 'inspection refuses traversal');
end;

begin
  try
    Passed := 0;
    Failed := 0;
    RunTest('binary round trip and nested directory creation', TestBinaryRoundTrip);
    RunTest('empty file and explicit overwrite', TestEmptyFileAndOverwrite);
    RunTest('native and forward slash paths', TestNativeAndSlashPaths);
    RunTest('provider preserves files prefix', TestNoProtocolPrefixMapping);
    RunTest('unsafe paths rejected', TestRejectedPaths);
    RunTest('root-prefix sibling protected', TestSiblingPrefixProtection);
    RunTest('binary copy in and out', TestCopyInAndOut);
    RunTest('nested move through IFileRelocator', TestNestedMove);
    RunTest('same-path move preserves bytes', TestSamePathMove);
    RunTest('move collision preserves both files', TestMoveCollision);
    RunTest('missing sources rejected', TestMissingSources);
    RunTest('move traversal rejected', TestMoveRejectsTraversal);
    RunTest('repair inspection distinguishes present empty and missing', TestStorageInspection);
    WriteLn(Format('%d passed; %d failed', [Passed, Failed]));
    if Failed > 0 then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      WriteLn('FAIL fixture: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

