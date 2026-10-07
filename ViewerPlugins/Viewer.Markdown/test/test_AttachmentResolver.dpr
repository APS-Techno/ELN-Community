program test_AttachmentResolver;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  unit_MarkdownAttachmentResolver in '..\unit_MarkdownAttachmentResolver.pas';

var
  Failures: Integer = 0;

procedure AssertEq(const ATestName, AExpected, AActual: string);
begin
  if AExpected = AActual then
    Writeln('PASS ', ATestName)
  else
  begin
    Inc(Failures);
    Writeln('FAIL ', ATestName);
    Writeln('  expected: ', AExpected);
    Writeln('  actual:   ', AActual);
  end;
end;

function MakeTempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
    'AttachTest_' + FormatDateTime('yyyymmddhhnnsszzz', Now));
  TDirectory.CreateDirectory(Result);
end;

procedure Touch(const ADir, AName: string);
begin
  TFile.WriteAllText(TPath.Combine(ADir, AName), '');
end;

procedure RunTests;
var
  Dir: string;
begin
  Dir := MakeTempDir;
  try
    Touch(Dir, '[1046]dcpulseg3f.png');
    Touch(Dir, '[1052]D3GF_UserManual.pdf');
    Touch(Dir, '[2000]photo with spaces.png');
    Touch(Dir, 'no_prefix.png');  // plain file, should NOT be in the map

    AssertEq(
      'RewritesPlainImage',
      '![](%5B1046%5Ddcpulseg3f.png)',
      RewriteAttachmentRefs('![](dcpulseg3f.png)', Dir));

    AssertEq(
      'PreservesAltText',
      '![Power source](%5B1046%5Ddcpulseg3f.png)',
      RewriteAttachmentRefs('![Power source](dcpulseg3f.png)', Dir));

    AssertEq(
      'PreservesTitle',
      '![alt](%5B1046%5Ddcpulseg3f.png "Hover title")',
      RewriteAttachmentRefs('![alt](dcpulseg3f.png "Hover title")', Dir));

    AssertEq(
      'RewritesLinkNotJustImage',
      '[Manual](%5B1052%5DD3GF_UserManual.pdf)',
      RewriteAttachmentRefs('[Manual](D3GF_UserManual.pdf)', Dir));

    AssertEq(
      'CaseInsensitiveLookupPreservesUserCasing',
      '![](%5B1046%5DDCPULSEG3F.PNG)',
      RewriteAttachmentRefs('![](DCPULSEG3F.PNG)', Dir));

    AssertEq(
      'UnquotedSpaceUrlsAreLeftAlone',
      '![](photo with spaces.png)',
      RewriteAttachmentRefs('![](photo with spaces.png)', Dir));

    AssertEq(
      'UrlEncodedSpacesResolveAndPreserveEncoding',
      '![](%5B2000%5Dphoto%20with%20spaces.png)',
      RewriteAttachmentRefs('![](photo%20with%20spaces.png)', Dir));

    AssertEq(
      'PassesThroughHttp',
      '[ex](https://example.com/foo.png)',
      RewriteAttachmentRefs('[ex](https://example.com/foo.png)', Dir));

    AssertEq(
      'PassesThroughElnScheme',
      '[x](eln://item/1)',
      RewriteAttachmentRefs('[x](eln://item/1)', Dir));

    AssertEq(
      'PassesThroughAbsoluteSlash',
      '[x](/dcpulseg3f.png)',
      RewriteAttachmentRefs('[x](/dcpulseg3f.png)', Dir));

    AssertEq(
      'PassesThroughDriveLetter',
      '[x](C:/foo.png)',
      RewriteAttachmentRefs('[x](C:/foo.png)', Dir));

    AssertEq(
      'PassesThroughFragment',
      '[section](#heading)',
      RewriteAttachmentRefs('[section](#heading)', Dir));

    AssertEq(
      'LeavesUnknownFileAlone',
      '![](missing.png)',
      RewriteAttachmentRefs('![](missing.png)', Dir));

    AssertEq(
      'LeavesFileWithoutIdPrefixAlone',
      '![](no_prefix.png)',
      RewriteAttachmentRefs('![](no_prefix.png)', Dir));

    AssertEq(
      'RewritesMultipleImagesInOneDoc',
      '![a](%5B1046%5Ddcpulseg3f.png) and ![b](%5B1052%5DD3GF_UserManual.pdf)',
      RewriteAttachmentRefs(
        '![a](dcpulseg3f.png) and ![b](D3GF_UserManual.pdf)', Dir));

    AssertEq(
      'DoesNotTouchDoubleBracketElnTokens',
      'see [[item:534]] and ![](%5B1046%5Ddcpulseg3f.png)',
      RewriteAttachmentRefs(
        'see [[item:534]] and ![](dcpulseg3f.png)', Dir));

    AssertEq(
      'EmptyDirIsNoOp',
      '![](dcpulseg3f.png)',
      RewriteAttachmentRefs('![](dcpulseg3f.png)', MakeTempDir));

    AssertEq(
      'NonexistentDirIsNoOp',
      '![](dcpulseg3f.png)',
      RewriteAttachmentRefs('![](dcpulseg3f.png)',
        TPath.Combine(Dir, 'nope_does_not_exist')));

    // --- AFiles override path: host-supplied "[ID]name.ext" list takes ---
    // --- precedence over (or substitutes for) on-disk enumeration.    ---

    AssertEq(
      'AFilesListResolvesWithoutDir',
      '![](%5B1046%5Ddcpulseg3f.png)',
      RewriteAttachmentRefs('![](dcpulseg3f.png)', '',
        TArray<string>.Create('[1046]dcpulseg3f.png')));

    AssertEq(
      'AFilesListSupersedesDir',
      // Dir contains [1046]; AFiles redefines it as [9999] — AFiles wins.
      '![](%5B9999%5Ddcpulseg3f.png)',
      RewriteAttachmentRefs('![](dcpulseg3f.png)', Dir,
        TArray<string>.Create('[9999]dcpulseg3f.png')));

    AssertEq(
      'AFilesListAcceptsBareNames',
      // No directory component on the entries — the resolver treats them as
      // bare filenames produced by the host enumerator.
      '![alt](%5B1052%5DD3GF_UserManual.pdf)',
      RewriteAttachmentRefs('![alt](D3GF_UserManual.pdf)', '',
        TArray<string>.Create('[1052]D3GF_UserManual.pdf', '[1046]dcpulseg3f.png')));

    AssertEq(
      'EmptyAFilesFallsBackToDir',
      // Empty AFiles -> resolver falls back to ADir enumeration (existing
      // behaviour), which has [1046]dcpulseg3f.png.
      '![](%5B1046%5Ddcpulseg3f.png)',
      RewriteAttachmentRefs('![](dcpulseg3f.png)', Dir, nil));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

begin
  try
    RunTests;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end;

  Writeln('');
  if Failures > 0 then
  begin
    Writeln('FAILED: ', Failures);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.
