unit test_FilePaths;

interface

uses
  DUnitX.TestFramework, unit_FilePaths;

type
  [TestFixture]
  TFilePathsTests = class
  public
    [Test]
    procedure WindowsInvalidCharactersBecomeDashes;
    [Test]
    procedure TildeIsKept;
    [Test]
    procedure ControlCharacterBecomesDash;
    [Test]
    procedure AttachmentPathCleansFoldersOnly;
  end;

implementation

procedure TFilePathsTests.WindowsInvalidCharactersBecomeDashes;
begin
  Assert.AreEqual('a-b-c-d-e-f-g-h-i-j',
    CleanFileName('a:b?c*d<e>f|g"h\i/j'));
end;

procedure TFilePathsTests.TildeIsKept;
begin
  Assert.AreEqual('x~y', CleanFileName('x~y'));
end;

procedure TFilePathsTests.ControlCharacterBecomesDash;
begin
  Assert.AreEqual('a-b', CleanFileName('a' + #9 + 'b'));
end;

procedure TFilePathsTests.AttachmentPathCleansFoldersOnly;
begin
  Assert.AreEqual('Projects/P-1/I-2/[0001]f.txt',
    AttachmentRelativePath('P:1', 'I?2', '[0001]f.txt'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFilePathsTests);

end.
