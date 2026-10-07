program CommunityStorageSmoke;

{$APPTYPE CONSOLE}
{$ASSERTIONS ON}

uses
  System.SysUtils,
  System.IOUtils,
  unit_NotebookStorage,
  unit_FileRelocator,
  unit_LocalNotebookStorage;

var
  Storage: INotebookStorage;
  Relocator: unit_NotebookStorage.IFileRelocator;
  Root: string;
  Id: TGUID;
  Payload, Actual: TBytes;
  Rejected: Boolean;
begin
  CreateGUID(Id);
  Root := TPath.Combine(TPath.GetTempPath, 'ELNCommunitySmoke-' + GUIDToString(Id));
  try
    Storage := TLocalNotebookStorage.Create(Root);
    Payload := TBytes.Create(0, 255, 128, 10, 13, 42);
    Storage.WriteBytes('Projects/[00001]Local/[0001]Notebook/[0001]test.bin', Payload);
    Storage.MoveFile('Projects/[00001]Local/[0001]Notebook/[0001]test.bin',
      'Projects/[00001]Local/[0001]Renamed/[0001]test.bin');
    Assert(not Storage.Exists('Projects/[00001]Local/[0001]Notebook/[0001]test.bin'));
    Actual := Storage.ReadBytes('Projects/[00001]Local/[0001]Renamed/[0001]test.bin');
    Assert(Length(Actual) = Length(Payload));
    for var I := 0 to High(Payload) do
      Assert(Actual[I] = Payload[I]);
    Relocator := TNotebookFileRelocator.Create(Storage);
    Relocator.MoveFile(
      BuildItemFileRemotePath('[00001]Local', '[0001]Renamed', '[0001]test.bin'),
      BuildItemFileRemotePath('[00001]Local', '[0001]Moved', '[0001]test.bin'));
    Assert(Storage.Exists('Projects/[00001]Local/[0001]Moved/[0001]test.bin'));
    Assert(not Storage.Exists('Projects/[00001]Local/[0001]Renamed/[0001]test.bin'));
    Rejected := False;
    try
      Storage.WriteBytes('../escape.bin', Payload);
    except
      on E: EArgumentException do
        Rejected := True;
    end;
    Assert(Rejected);
    Relocator := nil;
    Storage := nil;
    Writeln('PASS: binary attachment rename and traversal rejection');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Storage := nil;
      Relocator := nil;
      ExitCode := 1;
    end;
  end;
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
end.
