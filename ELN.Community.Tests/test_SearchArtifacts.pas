unit test_SearchArtifacts;

interface

uses
  System.SysUtils, System.Classes, DUnitX.TestFramework, unit_TextEmbedder, unit_SearchArtifacts,
  unit_SearchArtifactInstall;

type
  [TestFixture]
  TSearchArtifactTests = class
  private
    FRoot: string;
    FManifestPath: string;
    function Sha(const Text: string): string;
    procedure WriteFile(const RelativePath, Text: string);
    function ManifestText(const ModelHash: string = ''): string;
    function Load(const Text: string): TSearchArtifactManifest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadsRepositoryManifestV3;
    [Test]
    procedure LoadsModelRolesAndTerms;
    [Test]
    procedure RejectsManifestVersion2WithClearMessage;
    [Test]
    procedure RejectsInvalidModelSet;
    [Test]
    procedure ReadyWhenAllMatch;
    [Test]
    procedure MissingFileReported;
    [Test]
    procedure WrongSizeReported;
    [Test]
    procedure WrongHashOnlyWhenVerifying;
    [Test]
    procedure RejectsMalformedManifest;
    [Test]
    procedure EnvOverridesRoot;
    [Test]
    procedure OptionalArchiveMissingStillReady;
    [Test]
    procedure RequiredArchiveMissingNotReady;
    [Test]
    procedure RepositoryManifestMarksOnlyPdfiumAndRerankerOptional;
    [Test]
    procedure ReadyWithOptionalPartsMissing;
    [Test]
    procedure OptionalPartReadyByName;
    [Test]
    procedure ReportHasOneCheckPerPart;
    [Test]
    procedure SlashAndBackslashNamesGiveOnePath;
    [Test]
    procedure LinuxManifestMatchesWindowsExceptArchives;
    [Test]
    procedure PdfiumLibraryIsListedInThePlatformManifest;
    [Test]
    procedure DefaultPathNamesThePlatformManifest;
  end;

  TFolderFetcher = class(TInterfacedObject, IArtifactFetcher)
  private
    FSource: string;
  public
    Calls: Integer;
    CorruptName: string;
    LastName: string;
    Names: TArray<string>;
    FailAfterBytes: Int64;
    constructor Create(const Source: string);
    procedure Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck);
  end;

  [TestFixture]
  TSearchArtifactInstallTests = class
  private
    FRoot: string;
    FSource: string;
    FFetcher: TFolderFetcher;
    FFetcherIntf: IArtifactFetcher;
    FManifest: TSearchArtifactManifest;
    function Sha(const Text: string): string;
    function PartFiles: TArray<string>;
    procedure Install(const Cancelled: TCancelCheck = nil; const Progress: TInstallProgress = nil);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InstallsAllAndReportsReady;
    [Test]
    procedure SecondRunFetchesNothing;
    [Test]
    procedure CorruptDownloadLeavesNoFinalFile;
    [Test]
    procedure FailureMidwayThenRetryCompletes;
    [Test]
    procedure CancelLeavesNoPartFiles;
    [Test]
    procedure ExtractsOnlyListedRuntimeFiles;
    [Test]
    procedure ProgressReachesTotal;
    [Test]
    procedure RejectsPathsOutsideRoot;
    [Test]
    procedure InstallSkipsValidFilesAndFetchesOnlyMissingArchive;
    [Test]
    procedure ExtractsOnlyListedTarFiles;
    [Test]
    procedure InstallsOptionalPartsAndVerifiesHashes;
    [Test]
    procedure RequiredPartsInstallBeforeOptionalParts;
    [Test]
    procedure CorruptOptionalDownloadKeepsRequiredPartsReady;
    [Test]
    procedure CancelDuringTarExtraction;
  end;

  [TestFixture]
  TTarGzTests = class
  private
    FRoot: string;
    FArchive: string;
    function Bytes(const Text: string): TBytes;
    function Target(const Name: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TarGzExtractsListedFilesOnly;
    [Test]
    procedure TarGzRejectsTraversal;
    [Test]
    procedure TarGzTruncatedArchiveFails;
    [Test]
    procedure TarGzMissingWantedEntryFails;
  end;

  [TestFixture]
  TArtifactProxyTests = class
  public
    [Test]
    procedure HttpsUrlPrefersHttpsProxy;
    [Test]
    procedure HttpUrlUsesHttpProxyOnly;
    [Test]
    procedure NothingSetKeepsSystemProxy;
    [Test]
    procedure ParsesCredentialsAndOptionalScheme;
    [Test]
    procedure MissingOrBadPortRaises;
    [Test]
    procedure NoProxyMatchesHostSuffixes;
    [Test]
    procedure ErrorsDoNotEchoCredentials;
  end;

  TScriptedTransport = class(TInterfacedObject, IArtifactTransport)
  public
    Content: TBytes;
    FailAfter: TArray<Integer>;
    Statuses: TArray<Integer>;
    IgnoreRange: Boolean;
    RangeStarts: TArray<Int64>;
    constructor Create(const Text: string);
    function Get(const Url: string; RangeStart: Int64; const Target: TStream;
      const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck): TTransferResult;
  end;

  [TestFixture]
  TArtifactFetchResumeTests = class
  private
    FPath: string;
    FTransport: TScriptedTransport;
    FTransportIntf: IArtifactTransport;
    function Fetcher(const Delays: TArray<Integer>): IArtifactFetcher;
    function FileText: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ResumeAppendsAfterFailure;
    [Test]
    procedure RestartsWhenServerIgnoresRange;
    [Test]
    procedure GivesUpAfterFiveRetries;
    [Test]
    procedure CancelDuringBackoff;
    [Test]
    procedure BackoffSurvivesCancelCheckThatConsumesTime;
    [Test]
    procedure ServerErrorIsRetriedAndBodyDropped;
    [Test]
    procedure ClientErrorIsNotRetried;
    [Test]
    procedure RtlNetworkExceptionsAreTransient;
  end;

  TArchiveFolderFetcher = class(TInterfacedObject, IArtifactFetcher)
  private
    FSource: string;
  public
    Names: TArray<string>;
    constructor Create(const Source: string);
    procedure Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
      const Cancelled: TCancelCheck);
  end;

  [TestFixture]
  TLinuxArchiveInstallTests = class
  public
    [Test]
    procedure InstallerExtractsEveryListedFile;
  end;

{$IFDEF MSWINDOWS}
  [TestFixture]
  TWinHttpCancelTests = class
  public
    [Test]
    procedure CancelDuringStalledResponseReturnsPromptly;
  end;
{$ENDIF}

implementation

uses
  System.IOUtils, System.Hash, System.Zip, System.ZLib, System.Diagnostics, System.Net.URLClient,
  System.Net.HttpClient,
{$IFDEF MSWINDOWS}
  Winapi.Winsock2,
{$ENDIF}
  unit_TarGz, unit_SearchTestSupport;

type
  TTarItem = record
    Name: string;
    Data: TBytes;
    TypeFlag: AnsiChar;
  end;

function WindowsManifestPath: string;
begin
  Result := RepoFilePath('ELN.Search/search-artifacts.json');
end;

function LinuxManifestPath: string;
begin
  Result := RepoFilePath('ELN.Search/search-artifacts-linux.json');
end;

{ TSearchArtifactTests }

function TSearchArtifactTests.Sha(const Text: string): string;
begin
  Result := UpperCase(THashSHA2.GetHashString(Text, SHA256));
end;

procedure TSearchArtifactTests.WriteFile(const RelativePath, Text: string);
var
  Path: string;
begin
  Path := TPath.Combine(FRoot, NativePath(RelativePath));
  TDirectory.CreateDirectory(ExtractFileDir(Path));
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
end;

function TSearchArtifactTests.ManifestText(const ModelHash: string): string;
var
  Hash: string;
begin
  Hash := ModelHash;
  if Hash = '' then
    Hash := Sha('alpha');
  Result :=
    '{"ManifestVersion":3,"Models":[' +
    '{"Role":"embedder","Name":"test/embedder","License":"MIT","Revision":"r1",' +
    '"BaseUrl":"https://example.invalid/m","Folder":"m","Files":[' +
    '{"Name":"a.txt","Size":5,"Sha256":"' + Hash + '"},' +
    '{"Name":"b.txt","Size":5,"Sha256":"' + Sha('bravo') + '"}]},' +
    '{"Role":"reranker","Optional":true,"Name":"test/reranker","License":"Apache-2.0",' +
    '"DataTerms":"Terms of the training data.","Revision":"r2",' +
    '"BaseUrl":"https://example.invalid/rr","Folder":"rr","Files":[' +
    '{"Name":"onnx/r.bin","Size":6,"Sha256":"' + Sha('rerank') + '"}]}],' +
    '"Archives":[{"Name":"rt.zip","Kind":"zip","License":"MIT","Folder":"rt",' +
    '"Url":"https://example.invalid/rt.zip",' +
    '"Size":1000,"Sha256":"' + Sha('zip') + '","Files":[' +
    '{"Name":"pkg\\lib\\x.dll","Size":3,"Sha256":"' + Sha('dll') + '"}]}]}';
end;

function TSearchArtifactTests.Load(const Text: string): TSearchArtifactManifest;
begin
  TFile.WriteAllText(FManifestPath, Text, TEncoding.UTF8);
  Result := TSearchArtifactManifest.LoadFromFile(FManifestPath);
end;

procedure TSearchArtifactTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-artifacts-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FManifestPath := TPath.Combine(FRoot, 'manifest.json');
  WriteFile('m\a.txt', 'alpha');
  WriteFile('m\b.txt', 'bravo');
  WriteFile('rt\pkg\lib\x.dll', 'dll');
  WriteFile('rr\onnx\r.bin', 'rerank');
end;

procedure TSearchArtifactTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSearchArtifactTests.LoadsRepositoryManifestV3;
var
  M: TSearchArtifactManifest;
  F: TArtifactFile;
  Embedder, Reranker: TArtifactModel;
  Sum: Int64;
begin
  M := TSearchArtifactManifest.LoadFromFile(WindowsManifestPath);
  Assert.AreEqual(2, Integer(Length(M.Models)));
  Assert.IsTrue(M.FindModel(mrEmbedder, Embedder));
  Assert.AreEqual('intfloat/multilingual-e5-small', Embedder.Name);
  Assert.AreEqual('multilingual-e5-small', Embedder.Folder);
  Assert.IsFalse(Embedder.Optional);
  Assert.AreEqual(6, Integer(Length(Embedder.Files)));
  Assert.AreEqual(NativePath('multilingual-e5-small/model.onnx'), Embedder.Files[0].RelativePath);
  Assert.AreEqual(Int64(470268510), Embedder.Files[0].Size);
  Assert.IsTrue(M.FindModel(mrReranker, Reranker));
  Assert.AreEqual('cross-encoder/mmarco-mMiniLMv2-L12-H384-v1', Reranker.Name);
  Assert.AreEqual('mmarco-mMiniLMv2-L12-H384-v1', Reranker.Folder);
  Assert.AreEqual('1427fd652930e4ba29e8149678df786c240d8825', Reranker.Revision);
  Assert.AreEqual(2, Integer(Length(Reranker.Files)));
  Assert.AreEqual(NativePath('mmarco-mMiniLMv2-L12-H384-v1/onnx/model_quint8_avx2.onnx'), Reranker.Files[0].RelativePath);
  Assert.AreEqual(Int64(118620016), Reranker.Files[0].Size);
  Assert.AreEqual('6C2513767FB63D008A4377BEF7A7A3555433D9436342BB53E35A3A72FFC52D4B', Reranker.Files[0].Sha256);
  Assert.AreEqual(NativePath('mmarco-mMiniLMv2-L12-H384-v1/config.json'), Reranker.Files[1].RelativePath);
  Assert.AreEqual('Apache-2.0', Reranker.License);
  Assert.Contains(Reranker.DataTerms, 'mMARCO');
  Assert.Contains(Reranker.DataTerms, 'MS MARCO');
  Assert.Contains(Reranker.DataTerms, 'non-commercial research');
  Assert.AreEqual(2, Integer(Length(M.Archives)));
  Assert.AreEqual('onnxruntime', M.Archives[0].Folder);
  Assert.IsTrue(M.Archives[0].Kind = akZip);
  Assert.AreEqual(Int64(82929944), M.Archives[0].Size);
  Assert.AreEqual(4, Integer(Length(M.Archives[0].Files)));
  Assert.AreEqual(NativePath('onnxruntime/onnxruntime-win-x64-1.31.1/lib/onnxruntime.dll'), M.Archives[0].Files[0].RelativePath);
  Assert.AreEqual('MIT', M.Archives[0].License);
  Assert.AreEqual('pdfium', M.Archives[1].Folder);
  Assert.IsTrue(M.Archives[1].Kind = akTarGz);
  Assert.AreEqual(Int64(3904987), M.Archives[1].Size);
  Assert.AreEqual('9A964261760CFF52570AABF038AB346D3A5034DD8B30D0D5FE8861235D356B8B', M.Archives[1].Sha256);
  Assert.AreEqual(NativePath('pdfium/bin/pdfium.dll'), M.Archives[1].Files[0].RelativePath);
  Assert.AreEqual(NativePath('pdfium/LICENSE'), M.Archives[1].Files[1].RelativePath);
  Assert.AreEqual(NativePath('pdfium/licenses/pdfium.txt'), M.Archives[1].Files[Length(M.Archives[1].Files) - 3].RelativePath);
  Sum := M.Archives[0].Size + M.Archives[1].Size;
  for F in Embedder.Files do
    Inc(Sum, F.Size);
  for F in Reranker.Files do
    Inc(Sum, F.Size);
  Assert.AreEqual(Sum, M.TotalDownloadBytes);
end;

procedure TSearchArtifactTests.LoadsModelRolesAndTerms;
var
  M: TSearchArtifactManifest;
  Embedder, Reranker: TArtifactModel;
  Parts: TArray<TArtifactPart>;
begin
  M := Load(ManifestText);
  Assert.IsTrue(M.FindModel(mrEmbedder, Embedder));
  Assert.IsTrue(M.FindModel(mrReranker, Reranker));
  Assert.AreEqual('test/embedder', Embedder.Name);
  Assert.AreEqual('MIT', Embedder.License);
  Assert.AreEqual('', Embedder.DataTerms);
  Assert.IsFalse(Embedder.Optional);
  Assert.IsTrue(Reranker.Optional);
  Assert.AreEqual(NativePath('rr/onnx/r.bin'), Reranker.Files[0].RelativePath);
  Assert.AreEqual('https://example.invalid/rr', Reranker.BaseUrl);
  Assert.AreEqual('Terms of the training data.', Reranker.DataTerms);
  Parts := M.Parts;
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual('test/embedder', Parts[0].Name);
  Assert.AreEqual(Int64(10), Parts[0].Size);
  Assert.IsFalse(Parts[0].Optional);
  Assert.AreEqual('test/reranker', Parts[1].Name);
  Assert.IsTrue(Parts[1].Optional);
  Assert.AreEqual('rt.zip', Parts[2].Name);
  Assert.AreEqual(Int64(1000), Parts[2].Size);
  Assert.AreEqual(Int64(1016), M.TotalDownloadBytes);
end;

procedure TSearchArtifactTests.RejectsManifestVersion2WithClearMessage;
var
  Message: string;
begin
  Message := '';
  try
    Load(ManifestText.Replace('"ManifestVersion":3', '"ManifestVersion":2'));
  except
    on E: ESearchArtifactError do
      Message := E.Message;
  end;
  Assert.Contains(Message, 'version 2');
  Assert.Contains(Message, 'version 3');
end;

procedure TSearchArtifactTests.RejectsInvalidModelSet;
var
  Text: string;
begin
  Text := ManifestText;
  Assert.WillRaise(procedure begin Load(Text.Replace('"Role":"embedder"', '"Role":"reranker"')); end,
    ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"Role":"reranker"', '"Role":"embedder"')); end,
    ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"Role":"reranker"', '"Role":"judge"')); end,
    ESearchArtifactError);
  Assert.WillRaise(
    procedure begin Load(Text.Replace('"Role":"embedder",', '"Role":"embedder","Optional":true,')); end,
    ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"Revision":"r1",', '')); end, ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"License":"MIT","Revision"', '"Revision"')); end,
    ESearchArtifactError);
end;

procedure TSearchArtifactTests.ReadyWhenAllMatch;
var
  Check: TArtifactCheck;
begin
  Check := CheckSearchArtifacts(Load(ManifestText), FRoot, True);
  Assert.IsTrue(Check.State = asReady, Check.FirstProblem);
  Assert.AreEqual('', Check.FirstProblem);
end;

procedure TSearchArtifactTests.MissingFileReported;
var
  Check: TArtifactCheck;
begin
  TFile.Delete(TPath.Combine(FRoot, NativePath('m/b.txt')));
  Check := CheckSearchArtifacts(Load(ManifestText), FRoot, False);
  Assert.IsTrue(Check.State = asMissing);
  Assert.Contains(Check.FirstProblem, 'b.txt');
end;

procedure TSearchArtifactTests.WrongSizeReported;
var
  Check: TArtifactCheck;
begin
  WriteFile('rt\pkg\lib\x.dll', 'dll!');
  Check := CheckSearchArtifacts(Load(ManifestText), FRoot, False);
  Assert.IsTrue(Check.State = asWrongSize);
  Assert.Contains(Check.FirstProblem, 'x.dll');
end;

procedure TSearchArtifactTests.WrongHashOnlyWhenVerifying;
var
  M: TSearchArtifactManifest;
begin
  WriteFile('m\a.txt', 'ALPHA');
  M := Load(ManifestText);
  Assert.IsTrue(CheckSearchArtifacts(M, FRoot, False).State = asReady);
  Assert.IsTrue(CheckSearchArtifacts(M, FRoot, True).State = asWrongHash);
  Assert.Contains(CheckSearchArtifacts(M, FRoot, True).FirstProblem, 'a.txt');
end;

procedure TSearchArtifactTests.RejectsMalformedManifest;
var
  Text: string;
begin
  Text := ManifestText;
  Assert.WillRaise(procedure begin Load(Text.Replace('"Folder":"m",', '')); end, ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"Size":5', '"Size":-5')); end, ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(ManifestText('XYZ')); end, ESearchArtifactError);
  Assert.WillRaise(procedure begin Load('not json'); end, ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"ManifestVersion":3', '"ManifestVersion":1')); end,
    ESearchArtifactError);
  Assert.WillRaise(procedure begin Load(Text.Replace('"Kind":"zip"', '"Kind":"rar"')); end,
    ESearchArtifactError);
end;

procedure TSearchArtifactTests.OptionalArchiveMissingStillReady;
var
  Text: string;
  M: TSearchArtifactManifest;
begin
  Text := ManifestText.Replace('"Kind":"zip",', '"Kind":"zip","Optional":true,');
  TFile.Delete(TPath.Combine(FRoot, NativePath('rt/pkg/lib/x.dll')));
  M := Load(Text);
  Assert.IsTrue(M.Archives[0].Optional);
  Assert.IsTrue(SearchArtifactsReadyAt(FManifestPath, FRoot));
  Assert.IsTrue(CheckSearchArtifacts(M, FRoot, False, True).State = asReady);
  Assert.IsTrue(CheckSearchArtifacts(M, FRoot, False).State = asMissing);
  Assert.IsTrue(CheckSearchArtifacts(M, FRoot, True).State = asMissing);
end;

procedure TSearchArtifactTests.RequiredArchiveMissingNotReady;
begin
  TFile.Delete(TPath.Combine(FRoot, NativePath('rt/pkg/lib/x.dll')));
  Load(ManifestText);
  Assert.IsFalse(SearchArtifactsReadyAt(FManifestPath, FRoot));
end;

procedure TSearchArtifactTests.RepositoryManifestMarksOnlyPdfiumAndRerankerOptional;
var
  Path: string;
  M: TSearchArtifactManifest;
  Embedder, Reranker: TArtifactModel;
begin
  for Path in [WindowsManifestPath, LinuxManifestPath] do
  begin
    M := TSearchArtifactManifest.LoadFromFile(Path);
    Assert.IsTrue(M.FindModel(mrEmbedder, Embedder), Path);
    Assert.IsTrue(M.FindModel(mrReranker, Reranker), Path);
    Assert.IsFalse(Embedder.Optional, Path);
    Assert.IsTrue(Reranker.Optional, Path);
    Assert.IsFalse(M.Archives[0].Optional, Path);
    Assert.IsTrue(M.Archives[1].Optional, Path);
  end;
end;

procedure TSearchArtifactTests.SlashAndBackslashNamesGiveOnePath;
var
  Slash, Backslash: TSearchArtifactManifest;
  Expected: string;
begin
  Backslash := Load(ManifestText);
  Slash := Load(ManifestText.Replace('pkg\\lib\\x.dll', 'pkg/lib/x.dll').Replace('onnx/r.bin', 'onnx\\r.bin'));
  Expected := 'rt' + PathDelim + 'pkg' + PathDelim + 'lib' + PathDelim + 'x.dll';
  Assert.AreEqual(Expected, Backslash.Archives[0].Files[0].RelativePath);
  Assert.AreEqual(Expected, Slash.Archives[0].Files[0].RelativePath);
  Assert.AreEqual('rr' + PathDelim + 'onnx' + PathDelim + 'r.bin', Backslash.Models[1].Files[0].RelativePath);
  Assert.AreEqual(Backslash.Models[1].Files[0].RelativePath, Slash.Models[1].Files[0].RelativePath);
  Assert.IsTrue(CheckSearchArtifacts(Backslash, FRoot, True).State = asReady,
    CheckSearchArtifacts(Backslash, FRoot, True).FirstProblem);
  Assert.IsTrue(CheckSearchArtifacts(Slash, FRoot, True).State = asReady,
    CheckSearchArtifacts(Slash, FRoot, True).FirstProblem);
end;

procedure TSearchArtifactTests.LinuxManifestMatchesWindowsExceptArchives;
var
  Win, Linux: TSearchArtifactManifest;
  WinParts, LinuxParts: TArray<TArtifactPart>;
  I, J: Integer;
begin
  Win := TSearchArtifactManifest.LoadFromFile(WindowsManifestPath);
  Linux := TSearchArtifactManifest.LoadFromFile(LinuxManifestPath);
  Assert.AreEqual<NativeInt>(Length(Win.Models), Length(Linux.Models));
  for I := 0 to High(Win.Models) do
  begin
    Assert.AreEqual(Win.Models[I].Name, Linux.Models[I].Name);
    Assert.IsTrue(Win.Models[I].Role = Linux.Models[I].Role, Win.Models[I].Name);
    Assert.AreEqual(Win.Models[I].Revision, Linux.Models[I].Revision);
    Assert.AreEqual(Win.Models[I].BaseUrl, Linux.Models[I].BaseUrl);
    Assert.AreEqual(Win.Models[I].Folder, Linux.Models[I].Folder);
    Assert.AreEqual(Win.Models[I].License, Linux.Models[I].License);
    Assert.AreEqual(Win.Models[I].DataTerms, Linux.Models[I].DataTerms);
    Assert.AreEqual<Boolean>(Win.Models[I].Optional, Linux.Models[I].Optional);
    Assert.AreEqual<NativeInt>(Length(Win.Models[I].Files), Length(Linux.Models[I].Files));
    for J := 0 to High(Win.Models[I].Files) do
    begin
      Assert.AreEqual(Win.Models[I].Files[J].RelativePath, Linux.Models[I].Files[J].RelativePath);
      Assert.AreEqual(Win.Models[I].Files[J].Size, Linux.Models[I].Files[J].Size);
      Assert.AreEqual(Win.Models[I].Files[J].Sha256, Linux.Models[I].Files[J].Sha256);
    end;
  end;
  Assert.AreEqual<NativeInt>(Length(Win.Archives), Length(Linux.Archives));
  for I := 0 to High(Win.Archives) do
  begin
    Assert.AreNotEqual(Win.Archives[I].Name, Linux.Archives[I].Name);
    Assert.AreEqual(Win.Archives[I].Folder, Linux.Archives[I].Folder);
    Assert.AreEqual(Win.Archives[I].License, Linux.Archives[I].License);
    Assert.AreEqual<Boolean>(Win.Archives[I].Optional, Linux.Archives[I].Optional);
    Assert.IsTrue(Linux.Archives[I].Kind = akTarGz, Linux.Archives[I].Name);
    Assert.AreEqual<NativeInt>(Length(Win.Archives[I].Files), Length(Linux.Archives[I].Files));
  end;
  Assert.AreEqual('onnxruntime-linux-x64-1.31.1.tgz', Linux.Archives[0].Name);
  Assert.AreEqual(Int64(11413655), Linux.Archives[0].Size);
  Assert.AreEqual('C849E36A1EF3E22D4FF217B9D1CE4A3CF5B9467B975610913AE959AD5B16BDC9', Linux.Archives[0].Sha256);
  Assert.AreEqual(NativePath('onnxruntime/onnxruntime-linux-x64-1.31.1/lib/libonnxruntime.so.1.31.1'),
    Linux.Archives[0].Files[0].RelativePath);
  Assert.AreEqual('pdfium-linux-x64.tgz', Linux.Archives[1].Name);
  Assert.AreEqual(Int64(3828800), Linux.Archives[1].Size);
  Assert.AreEqual('E1C3CE6E270CB5E0C20816B379AD9F2C1309972697C505F508DE92BF5E7D6659', Linux.Archives[1].Sha256);
  Assert.AreEqual(NativePath('pdfium/lib/libpdfium.so'), Linux.Archives[1].Files[0].RelativePath);
  WinParts := Win.Parts;
  LinuxParts := Linux.Parts;
  Assert.AreEqual<NativeInt>(Length(WinParts), Length(LinuxParts));
  for I := 0 to High(WinParts) do
    if I < Length(Win.Models) then
      Assert.AreEqual(WinParts[I].Name, LinuxParts[I].Name)
    else
      Assert.AreNotEqual(WinParts[I].Name, LinuxParts[I].Name);
end;

procedure TSearchArtifactTests.PdfiumLibraryIsListedInThePlatformManifest;
var
  M: TSearchArtifactManifest;
  Root: string;
  A: TArtifactArchive;
  F: TArtifactFile;
  Found: Boolean;
begin
  M := TSearchArtifactManifest.LoadFromFile(PlatformManifestPath);
  Root := TPath.Combine(TPath.GetTempPath, 'artifact-root');
  Found := False;
  for A in M.Archives do
    for F in A.Files do
      if TPath.Combine(Root, F.RelativePath) = M.PdfiumLibraryPath(Root) then
        Found := A.Optional;
  Assert.IsTrue(Found, M.PdfiumLibraryPath(Root) + ' is not an optional file of ' + PlatformManifestPath);
  Assert.AreEqual(M.PdfiumLibraryPath(SearchArtifactRoot), SearchPdfiumLibraryPath);
end;

procedure TSearchArtifactTests.DefaultPathNamesThePlatformManifest;
begin
  Assert.AreEqual({$IFDEF MSWINDOWS}'search-artifacts.json'{$ELSE}'search-artifacts-linux.json'{$ENDIF},
    SearchArtifactManifestName);
  Assert.AreEqual(ExtractFilePath(ParamStr(0)) + SearchArtifactManifestName, TSearchArtifactManifest.DefaultPath);
  Assert.IsTrue(TFile.Exists(PlatformManifestPath));
end;

procedure TSearchArtifactTests.ReadyWithOptionalPartsMissing;
var
  Report: TArtifactReport;
begin
  Load(ManifestText);
  Assert.IsTrue(CheckArtifactReport(TSearchArtifactManifest.LoadFromFile(FManifestPath), FRoot, True).Readiness =
    arReady);
  TFile.Delete(TPath.Combine(FRoot, NativePath('rr/onnx/r.bin')));
  Report := CheckArtifactReport(TSearchArtifactManifest.LoadFromFile(FManifestPath), FRoot, True);
  Assert.IsTrue(Report.Readiness = arReadyOptionalMissing);
  Assert.IsTrue(Report.Required.State = asReady);
  Assert.IsTrue(SearchArtifactsReadyAt(FManifestPath, FRoot));
  TFile.Delete(TPath.Combine(FRoot, NativePath('m/b.txt')));
  Report := CheckArtifactReport(TSearchArtifactManifest.LoadFromFile(FManifestPath), FRoot, True);
  Assert.IsTrue(Report.Readiness = arNotReady);
  Assert.IsTrue(Report.Required.State = asMissing);
  Assert.Contains(Report.Required.FirstProblem, 'b.txt');
  Assert.IsFalse(SearchArtifactsReadyAt(FManifestPath, FRoot));
end;

procedure TSearchArtifactTests.OptionalPartReadyByName;
var
  M: TSearchArtifactManifest;
begin
  M := Load(ManifestText);
  Assert.IsTrue(OptionalPartReady(M, FRoot, 'test/reranker'));
  Assert.IsFalse(OptionalPartReady(M, FRoot, 'test/embedder'));
  Assert.IsFalse(OptionalPartReady(M, FRoot, 'rt.zip'));
  Assert.IsFalse(OptionalPartReady(M, FRoot, 'unknown'));
  WriteFile('rr\onnx\r.bin', 'rerank!');
  Assert.IsFalse(OptionalPartReady(M, FRoot, 'test/reranker'));
  TFile.Delete(TPath.Combine(FRoot, NativePath('rr/onnx/r.bin')));
  Assert.IsFalse(OptionalPartReady(M, FRoot, 'test/reranker'));
end;

procedure TSearchArtifactTests.ReportHasOneCheckPerPart;
var
  M: TSearchArtifactManifest;
  Report: TArtifactReport;
begin
  WriteFile('rr\onnx\r.bin', 'RERANK');
  M := Load(ManifestText);
  Report := CheckArtifactReport(M, FRoot, False);
  Assert.AreEqual(3, Integer(Length(Report.Parts)));
  Assert.AreEqual(3, Integer(Length(Report.Checks)));
  Assert.IsTrue(Report.Readiness = arReady);
  Report := CheckArtifactReport(M, FRoot, True);
  Assert.AreEqual('test/reranker', Report.Parts[1].Name);
  Assert.IsTrue(Report.Checks[0].State = asReady);
  Assert.IsTrue(Report.Checks[1].State = asWrongHash);
  Assert.IsTrue(Report.Checks[2].State = asReady);
  Assert.IsTrue(Report.Readiness = arReadyOptionalMissing);
end;

procedure TSearchArtifactTests.EnvOverridesRoot;
var
  Saved: string;
begin
  Saved := GetEnvironmentVariable('ELN_SEARCH_ARTIFACTS');
  try
    SetEnvironmentValue('ELN_SEARCH_ARTIFACTS', FRoot);
    Assert.AreEqual(FRoot, SearchArtifactRoot);
    SetEnvironmentValue('ELN_SEARCH_ARTIFACTS', '');
    Assert.AreEqual(TE5EmbedderConfig.DefaultArtifactRoot, SearchArtifactRoot);
  finally
    SetEnvironmentValue('ELN_SEARCH_ARTIFACTS', Saved);
  end;
end;

function ArtFile(const RelativePath: string; Size: Int64; const Sha256: string): TArtifactFile;
begin
  Result.RelativePath := NativePath(RelativePath);
  Result.Size := Size;
  Result.Sha256 := Sha256;
end;

function TarItem(const Name: string; const Data: TBytes; TypeFlag: AnsiChar = '0'): TTarItem;
begin
  Result.Name := Name;
  Result.Data := Data;
  Result.TypeFlag := TypeFlag;
end;

function OctalText(Value: Int64; Digits: Integer): string;
begin
  Result := '';
  repeat
    Result := Chr(Ord('0') + Integer(Value and 7)) + Result;
    Value := Value shr 3;
  until Value = 0;
  while Length(Result) < Digits do
    Result := '0' + Result;
end;

procedure PutAscii(var Block: TBytes; Offset: Integer; const Text: string);
var
  Raw: TBytes;
begin
  Raw := TEncoding.UTF8.GetBytes(Text);
  if Length(Raw) > 0 then
    Move(Raw[0], Block[Offset], Length(Raw));
end;

procedure AppendTarEntry(Stream: TStream; const Name: string; const Data: TBytes; TypeFlag: AnsiChar);
var
  Block, Pad: TBytes;
  I: Integer;
  Sum: Int64;
begin
  SetLength(Block, 512);
  PutAscii(Block, 0, Copy(Name, 1, 100));
  PutAscii(Block, 100, '0000644');
  PutAscii(Block, 108, '0000000');
  PutAscii(Block, 116, '0000000');
  PutAscii(Block, 124, OctalText(Length(Data), 11));
  PutAscii(Block, 136, OctalText(0, 11));
  for I := 148 to 155 do
    Block[I] := Ord(' ');
  Block[156] := Ord(TypeFlag);
  PutAscii(Block, 257, 'ustar');
  PutAscii(Block, 263, '00');
  Sum := 0;
  for I := 0 to 511 do
    Inc(Sum, Block[I]);
  PutAscii(Block, 148, OctalText(Sum, 6));
  Block[154] := 0;
  Block[155] := Ord(' ');
  Stream.WriteBuffer(Block[0], 512);
  if Length(Data) > 0 then
  begin
    Stream.WriteBuffer(Data[0], Length(Data));
    SetLength(Pad, (512 - Length(Data) mod 512) mod 512);
    if Length(Pad) > 0 then
      Stream.WriteBuffer(Pad[0], Length(Pad));
  end;
end;

procedure BuildTarGz(const Path: string; const Items: array of TTarItem);
var
  Tar: TMemoryStream;
  Gz: TFileStream;
  Compressor: TZCompressionStream;
  Item: TTarItem;
  LongName, Zeros: TBytes;
begin
  Tar := TMemoryStream.Create;
  try
    for Item in Items do
    begin
      if Length(Item.Name) > 100 then
      begin
        LongName := TEncoding.UTF8.GetBytes(Item.Name);
        SetLength(LongName, Length(LongName) + 1);
        LongName[High(LongName)] := 0;
        AppendTarEntry(Tar, '././@LongLink', LongName, 'L');
      end;
      AppendTarEntry(Tar, Item.Name, Item.Data, Item.TypeFlag);
    end;
    SetLength(Zeros, 1024);
    Tar.WriteBuffer(Zeros[0], 1024);
    Gz := TFileStream.Create(Path, fmCreate);
    try
      Compressor := TZCompressionStream.Create(Gz, zcDefault, 15 + 16);
      try
        Compressor.WriteBuffer(Tar.Memory^, Tar.Size);
      finally
        Compressor.Free;
      end;
    finally
      Gz.Free;
    end;
  finally
    Tar.Free;
  end;
end;

function ModelOf(Role: TArtifactModelRole; const Name, Folder, BaseUrl: string; Optional: Boolean;
  const Files: TArray<TArtifactFile>): TArtifactModel;
begin
  Result := Default(TArtifactModel);
  Result.Role := Role;
  Result.Name := Name;
  Result.Folder := Folder;
  Result.BaseUrl := BaseUrl;
  Result.Optional := Optional;
  Result.Files := Files;
end;

function ArchiveOf(const Name, Folder: string; Kind: TArtifactArchiveKind; const Path: string;
  const Files: TArray<TArtifactFile>): TArtifactArchive;
begin
  Result.Name := Name;
  Result.Folder := Folder;
  Result.Kind := Kind;
  Result.Url := 'https://example.invalid/dl/' + Name;
  Result.Size := TFile.GetSize(Path);
  Result.Sha256 := UpperCase(THashSHA2.GetHashStringFromFile(Path, SHA256));
  Result.Files := Files;
end;

{ TFolderFetcher }

constructor TFolderFetcher.Create(const Source: string);
begin
  inherited Create;
  FSource := Source;
  FailAfterBytes := -1;
end;

procedure TFolderFetcher.Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
  const Cancelled: TCancelCheck);
const
  Chunk = 2;
var
  Bytes: TBytes;
  Target: TFileStream;
  Name: string;
  Written, Count: Integer;
begin
  Inc(Calls);
  LastName := Url.Substring(Url.LastIndexOf('/') + 1);
  Name := LastName;
  Names := Names + [LastName];
  Bytes := TFile.ReadAllBytes(TPath.Combine(FSource, Name));
  if (Name = CorruptName) and (Length(Bytes) > 0) then
    Bytes[0] := Bytes[0] xor 1;
  Target := TFileStream.Create(TargetPath, fmCreate);
  try
    Written := 0;
    while Written < Length(Bytes) do
    begin
      if Assigned(Cancelled) and Cancelled() then
        raise EOperationCancelled.Create('cancelled');
      if (FailAfterBytes >= 0) and (Written >= FailAfterBytes) then
        raise EInOutError.Create('simulated network failure');
      Count := Length(Bytes) - Written;
      if Count > Chunk then
        Count := Chunk;
      Target.WriteBuffer(Bytes[Written], Count);
      Inc(Written, Count);
      if Assigned(Progress) then
        Progress(Written);
    end;
  finally
    Target.Free;
  end;
end;

{ TSearchArtifactInstallTests }

function TSearchArtifactInstallTests.Sha(const Text: string): string;
begin
  Result := UpperCase(THashSHA2.GetHashString(Text, SHA256));
end;

function TSearchArtifactInstallTests.PartFiles: TArray<string>;
begin
  if not TDirectory.Exists(FRoot) then
    Exit(nil);
  Result := TDirectory.GetFiles(FRoot, '*.part', TSearchOption.soAllDirectories);
end;

procedure TSearchArtifactInstallTests.Install(const Cancelled: TCancelCheck; const Progress: TInstallProgress);
begin
  InstallSearchArtifacts(FManifest, FRoot, FFetcherIntf, Progress, Cancelled);
end;

procedure TSearchArtifactInstallTests.Setup;
var
  Zip: TZipFile;
  ZipPath, Dll, Extra, TgzPath: string;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-install-' + TGUID.NewGuid.ToString);
  FSource := FRoot + '-src';
  TDirectory.CreateDirectory(FSource);
  TFile.WriteAllText(TPath.Combine(FSource, 'a.txt'), 'alpha');
  TFile.WriteAllText(TPath.Combine(FSource, 'b.txt'), 'bravo');
  TFile.WriteAllText(TPath.Combine(FSource, 'r.bin'), 'rerank');
  Dll := TPath.Combine(FSource, 'x.dll');
  Extra := TPath.Combine(FSource, 'extra.txt');
  TFile.WriteAllText(Dll, 'dll');
  TFile.WriteAllText(Extra, 'extra');
  ZipPath := TPath.Combine(FSource, 'rt.zip');
  TgzPath := TPath.Combine(FSource, 'pdfium.tgz');
  BuildTarGz(TgzPath, [TarItem('bin/pdfium.dll', TEncoding.UTF8.GetBytes('pdfium-dll-bytes')),
    TarItem('include/skip.h', TEncoding.UTF8.GetBytes('skip')),
    TarItem('LICENSE', TEncoding.UTF8.GetBytes('license'))]);
  Zip := TZipFile.Create;
  try
    Zip.Open(ZipPath, zmWrite);
    Zip.Add(Dll, 'pkg/lib/x.dll');
    Zip.Add(Extra, 'pkg/extra.txt');
    Zip.Close;
  finally
    Zip.Free;
  end;
  FManifest := Default(TSearchArtifactManifest);
  FManifest.Models := [
    ModelOf(mrEmbedder, 'test/embedder', 'm', 'https://example.invalid/m', False,
      [ArtFile('m\a.txt', 5, Sha('alpha')), ArtFile('m\b.txt', 5, Sha('bravo'))]),
    ModelOf(mrReranker, 'test/reranker', 'rr', 'https://example.invalid/rr', True,
      [ArtFile('rr\onnx\r.bin', 6, Sha('rerank'))])];
  FManifest.Archives := [
    ArchiveOf('rt.zip', 'rt', akZip, ZipPath, [ArtFile('rt\pkg\lib\x.dll', 3, Sha('dll'))]),
    ArchiveOf('pdfium.tgz', 'pdfium', akTarGz, TgzPath,
      [ArtFile('pdfium\bin\pdfium.dll', 16, Sha('pdfium-dll-bytes')), ArtFile('pdfium\LICENSE', 7, Sha('license'))])];
  FManifest.Archives[0].Optional := False;
  FManifest.Archives[1].Optional := True;
  FManifest.TotalDownloadBytes := 16 + FManifest.Archives[0].Size + FManifest.Archives[1].Size;
  FFetcher := TFolderFetcher.Create(FSource);
  FFetcherIntf := FFetcher;
end;

procedure TSearchArtifactInstallTests.TearDown;
begin
  FFetcherIntf := nil;
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
  if TDirectory.Exists(FSource) then
    TDirectory.Delete(FSource, True);
end;

procedure TSearchArtifactInstallTests.InstallsAllAndReportsReady;
begin
  Install;
  Assert.IsTrue(CheckSearchArtifacts(FManifest, FRoot, True).State = asReady);
  Assert.AreEqual(5, FFetcher.Calls);
  Assert.AreEqual(0, Integer(Length(PartFiles)));
end;

procedure TSearchArtifactInstallTests.SecondRunFetchesNothing;
begin
  Install;
  FFetcher.Calls := 0;
  Install;
  Assert.AreEqual(0, FFetcher.Calls);
  Assert.IsTrue(CheckSearchArtifacts(FManifest, FRoot, True).State = asReady);
end;

procedure TSearchArtifactInstallTests.CorruptDownloadLeavesNoFinalFile;
var
  Raised: Boolean;
begin
  FFetcher.CorruptName := 'b.txt';
  Raised := False;
  try
    Install;
  except
    on E: ESearchArtifactError do
    begin
      Raised := True;
      Assert.Contains(E.Message, 'b.txt');
    end;
  end;
  Assert.IsTrue(Raised, 'ESearchArtifactError expected');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('m/b.txt'))));
  Assert.AreEqual(0, Integer(Length(PartFiles)));
end;

procedure TSearchArtifactInstallTests.FailureMidwayThenRetryCompletes;
begin
  FFetcher.FailAfterBytes := 3;
  Assert.WillRaise(procedure begin Install; end, EInOutError);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('m/a.txt'))));
  Assert.AreEqual(0, Integer(Length(PartFiles)));
  FFetcher.FailAfterBytes := -1;
  Install;
  Assert.IsTrue(CheckSearchArtifacts(FManifest, FRoot, True).State = asReady);
  Assert.AreEqual(0, Integer(Length(PartFiles)));
end;

procedure TSearchArtifactInstallTests.CancelLeavesNoPartFiles;
begin
  Assert.WillRaise(
    procedure
    begin
      Install(function: Boolean begin Result := FFetcher.Calls >= 2; end);
    end, EOperationCancelled);
  Assert.AreEqual(2, FFetcher.Calls);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FRoot, NativePath('m/a.txt'))));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('m/b.txt'))));
  Assert.AreEqual(0, Integer(Length(PartFiles)));
end;

procedure TSearchArtifactInstallTests.ExtractsOnlyListedRuntimeFiles;
begin
  Install;
  Assert.IsTrue(TFile.Exists(TPath.Combine(FRoot, NativePath('rt/pkg/lib/x.dll'))));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('rt/pkg/extra.txt'))));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('rt/rt.zip'))));
  Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(TPath.Combine(FRoot, 'rt'), '*', TSearchOption.soAllDirectories))));
end;

procedure TSearchArtifactInstallTests.ProgressReachesTotal;
var
  Last, Previous: Int64;
  Monotonic: Boolean;
begin
  Last := -1;
  Monotonic := True;
  Install(nil,
    procedure(DoneBytes, TotalBytes: Int64; const CurrentFile: string)
    begin
      Previous := Last;
      Last := DoneBytes;
      if (Previous > Last) or (TotalBytes <> FManifest.TotalDownloadBytes) then
        Monotonic := False;
    end);
  Assert.AreEqual(FManifest.TotalDownloadBytes, Last);
  Assert.IsTrue(Monotonic, 'progress must not decrease');
end;

procedure TSearchArtifactInstallTests.RejectsPathsOutsideRoot;
var
  Evil: string;
begin
  Evil := TPath.Combine(TPath.GetTempPath, 'eln-evil-' + TGUID.NewGuid.ToString + '.txt');
  FManifest.Models[0].Files[0].RelativePath := '..\' + ExtractFileName(Evil);
  Assert.WillRaise(procedure begin Install; end, ESearchArtifactError);
  FManifest.Models[0].Files[0].RelativePath := Evil;
  Assert.WillRaise(procedure begin Install; end, ESearchArtifactError);
  FManifest.Models[0].Files[0].RelativePath := 'm\..\..\' + ExtractFileName(Evil);
  Assert.WillRaise(procedure begin Install; end, ESearchArtifactError);
  FManifest.Models[0].Files[0].RelativePath := NativePath('m/a.txt');
  FManifest.Models[1].Files[0].RelativePath := 'rr\..\..\r.bin';
  Assert.WillRaise(procedure begin Install; end, ESearchArtifactError);
  FManifest.Models[1].Files[0].RelativePath := NativePath('rr/onnx/r.bin');
  FManifest.Archives[0].Files[0].RelativePath := 'rt\..\..\x.dll';
  Assert.WillRaise(procedure begin Install; end, ESearchArtifactError);
  Assert.AreEqual(0, FFetcher.Calls);
  Assert.IsFalse(TFile.Exists(Evil));
end;

procedure TSearchArtifactInstallTests.InstallSkipsValidFilesAndFetchesOnlyMissingArchive;
begin
  Install;
  TDirectory.Delete(TPath.Combine(FRoot, 'pdfium'), True);
  FFetcher.Calls := 0;
  Install;
  Assert.AreEqual(1, FFetcher.Calls);
  Assert.AreEqual('pdfium.tgz', FFetcher.LastName);
  Assert.IsTrue(CheckSearchArtifacts(FManifest, FRoot, True).State = asReady);
end;

procedure TSearchArtifactInstallTests.ExtractsOnlyListedTarFiles;
begin
  Install;
  Assert.AreEqual('pdfium-dll-bytes', TFile.ReadAllText(TPath.Combine(FRoot, NativePath('pdfium/bin/pdfium.dll'))));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FRoot, NativePath('pdfium/LICENSE'))));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('pdfium/include/skip.h'))));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('pdfium/pdfium.tgz'))));
  Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(TPath.Combine(FRoot, 'pdfium'), '*', TSearchOption.soAllDirectories))));
end;

procedure TSearchArtifactInstallTests.InstallsOptionalPartsAndVerifiesHashes;
begin
  Install;
  Assert.AreEqual('rerank', TFile.ReadAllText(TPath.Combine(FRoot, NativePath('rr/onnx/r.bin'))));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FRoot, NativePath('pdfium/bin/pdfium.dll'))));
  Assert.IsTrue(CheckArtifactReport(FManifest, FRoot, True).Readiness = arReady);
  Assert.IsTrue(OptionalPartReady(FManifest, FRoot, 'test/reranker'));
  Assert.IsTrue(OptionalPartReady(FManifest, FRoot, 'pdfium.tgz'));
end;

procedure TSearchArtifactInstallTests.RequiredPartsInstallBeforeOptionalParts;
var
  I, LastRequired, FirstOptional: Integer;
begin
  Install;
  LastRequired := -1;
  FirstOptional := MaxInt;
  for I := 0 to High(FFetcher.Names) do
    if (FFetcher.Names[I] = 'a.txt') or (FFetcher.Names[I] = 'b.txt') or (FFetcher.Names[I] = 'rt.zip') then
      LastRequired := I
    else if I < FirstOptional then
      FirstOptional := I;
  Assert.AreEqual(5, Integer(Length(FFetcher.Names)));
  Assert.IsTrue(LastRequired < FirstOptional, 'required downloads must finish before optional ones start');
end;

procedure TSearchArtifactInstallTests.CorruptOptionalDownloadKeepsRequiredPartsReady;
var
  Raised: Boolean;
begin
  FFetcher.CorruptName := 'r.bin';
  Raised := False;
  try
    Install;
  except
    on E: ESearchArtifactError do
    begin
      Raised := True;
      Assert.Contains(E.Message, 'r.bin');
    end;
  end;
  Assert.IsTrue(Raised, 'ESearchArtifactError expected');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('rr/onnx/r.bin'))));
  Assert.AreEqual(0, Integer(Length(PartFiles)));
  Assert.IsTrue(CheckArtifactReport(FManifest, FRoot, True).Readiness = arReadyOptionalMissing);
  Assert.IsTrue(CheckSearchArtifacts(FManifest, FRoot, True, True).State = asReady);
end;

procedure TSearchArtifactInstallTests.CancelDuringTarExtraction;
var
  Part: string;
begin
  Part := TPath.Combine(FRoot, NativePath('pdfium/bin/pdfium.dll.part'));
  Assert.WillRaise(
    procedure
    begin
      Install(function: Boolean begin Result := TFile.Exists(Part); end);
    end, EOperationCancelled);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('pdfium/bin/pdfium.dll'))));
  Assert.AreEqual(0, Integer(Length(PartFiles)));
end;

function TTarGzTests.Bytes(const Text: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(Text);
end;

function TTarGzTests.Target(const Name: string): string;
begin
  Result := TPath.Combine(FRoot, NativePath('out/' + Name));
end;

procedure TTarGzTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'eln-targz-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FArchive := TPath.Combine(FRoot, 'a.tgz');
end;

procedure TTarGzTests.TearDown;
begin
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TTarGzTests.TarGzExtractsListedFilesOnly;
var
  LongName: string;
begin
  LongName := 'licenses/' + StringOfChar('n', 110) + '.txt';
  BuildTarGz(FArchive, [TarItem('dir/', nil, '5'), TarItem('a.txt', Bytes('alpha')),
    TarItem('skip.txt', Bytes('skipme')), TarItem(LongName, Bytes('long body'))]);
  ExtractTarGzEntries(FArchive, ['a.txt', LongName],
    function(Name: string): string begin Result := Target(Name); end, nil);
  Assert.AreEqual('alpha', TFile.ReadAllText(Target('a.txt')));
  Assert.AreEqual('long body', TFile.ReadAllText(Target(LongName)));
  Assert.IsFalse(TFile.Exists(Target('skip.txt')));
  Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(TPath.Combine(FRoot, 'out'), '*', TSearchOption.soAllDirectories))));
end;

procedure TTarGzTests.TarGzRejectsTraversal;
var
  Calls: Integer;
begin
  Calls := 0;
  BuildTarGz(FArchive, [TarItem('../x', Bytes('evil'))]);
  Assert.WillRaise(
    procedure
    begin
      ExtractTarGzEntries(FArchive, ['../x'],
        function(Name: string): string begin Inc(Calls); Result := Target(Name); end, nil);
    end, ESearchArtifactError);
  Assert.AreEqual(0, Calls);
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, 'x')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, NativePath('out/../x'))));
end;

procedure TTarGzTests.TarGzTruncatedArchiveFails;
var
  Data: TBytes;
  Raw: TBytes;
  I: Integer;
begin
  SetLength(Data, 300000);
  RandSeed := 12345;
  for I := 0 to High(Data) do
    Data[I] := Random(256);
  BuildTarGz(FArchive, [TarItem('big.bin', Data)]);
  Raw := TFile.ReadAllBytes(FArchive);
  SetLength(Raw, Length(Raw) div 2);
  TFile.WriteAllBytes(FArchive, Raw);
  Assert.WillRaise(
    procedure
    begin
      ExtractTarGzEntries(FArchive, ['big.bin'],
        function(Name: string): string begin Result := Target(Name); end, nil);
    end, ESearchArtifactError);
  Assert.IsFalse(TFile.Exists(Target('big.bin')));
end;

procedure TTarGzTests.TarGzMissingWantedEntryFails;
begin
  BuildTarGz(FArchive, [TarItem('a.txt', Bytes('alpha'))]);
  Assert.WillRaise(
    procedure
    begin
      ExtractTarGzEntries(FArchive, ['a.txt', 'b.txt'],
        function(Name: string): string begin Result := Target(Name); end, nil);
    end, ESearchArtifactError);
end;

procedure TArtifactProxyTests.HttpsUrlPrefersHttpsProxy;
var
  P: TArtifactProxy;
begin
  P := ResolveArtifactProxy('https://huggingface.co/x', 'http://secure.example:8443', 'http://plain.example:8080', '');
  Assert.IsTrue(P.Enabled);
  Assert.AreEqual('secure.example', P.Host);
  Assert.AreEqual(8443, P.Port);
  P := ResolveArtifactProxy('https://huggingface.co/x', '', 'http://plain.example:8080', '');
  Assert.AreEqual('plain.example', P.Host);
end;

procedure TArtifactProxyTests.HttpUrlUsesHttpProxyOnly;
var
  P: TArtifactProxy;
begin
  P := ResolveArtifactProxy('http://example.com/x', 'http://secure.example:8443', 'http://plain.example:8080', '');
  Assert.AreEqual('plain.example', P.Host);
  Assert.AreEqual(8080, P.Port);
  P := ResolveArtifactProxy('http://example.com/x', 'http://secure.example:8443', '', '');
  Assert.IsFalse(P.Enabled);
end;

procedure TArtifactProxyTests.NothingSetKeepsSystemProxy;
begin
  Assert.IsFalse(ResolveArtifactProxy('https://huggingface.co/x', '', '', '').Enabled);
end;

procedure TArtifactProxyTests.ParsesCredentialsAndOptionalScheme;
var
  P: TArtifactProxy;
begin
  P := ResolveArtifactProxy('https://a.example/x', 'http://bob:p%40ss@proxy.example:3128/', '', '');
  Assert.AreEqual('bob', P.User);
  Assert.AreEqual('p@ss', P.Password);
  Assert.AreEqual('proxy.example', P.Host);
  Assert.AreEqual(3128, P.Port);
  P := ResolveArtifactProxy('https://a.example/x', '127.0.0.1:10808', '', '');
  Assert.AreEqual('127.0.0.1', P.Host);
  Assert.AreEqual(10808, P.Port);
  Assert.AreEqual('', P.User);
end;

procedure TArtifactProxyTests.MissingOrBadPortRaises;
begin
  Assert.WillRaise(procedure begin ResolveArtifactProxy('https://a.example/x', 'http://proxy.example', '', ''); end,
    ESearchArtifactError);
  Assert.WillRaise(procedure begin ResolveArtifactProxy('https://a.example/x', 'http://proxy.example:abc', '', ''); end,
    ESearchArtifactError);
  Assert.WillRaise(procedure begin ResolveArtifactProxy('https://a.example/x', 'socks5://proxy.example:1080', '', ''); end,
    ESearchArtifactError);
end;

procedure TArtifactProxyTests.NoProxyMatchesHostSuffixes;
const
  Setting = 'http://proxy.example:8080';
begin
  Assert.IsFalse(ResolveArtifactProxy('https://huggingface.co/x', Setting, '', 'huggingface.co').Enabled);
  Assert.IsFalse(ResolveArtifactProxy('https://cdn.huggingface.co/x', Setting, '', 'localhost, .huggingface.co').Enabled);
  Assert.IsFalse(ResolveArtifactProxy('https://anything.example/x', Setting, '', '*').Enabled);
  Assert.IsTrue(ResolveArtifactProxy('https://nothuggingface.co/x', Setting, '', 'huggingface.co').Enabled);
  Assert.IsTrue(ResolveArtifactProxy('https://huggingface.co/x', Setting, '', 'localhost,127.0.0.1').Enabled);
end;

procedure TArtifactProxyTests.ErrorsDoNotEchoCredentials;
var
  Setting: string;
  Message: string;
begin
  for Setting in ['http://bob:s3cret@proxy.example', 'http://bob:s3cret@proxy.example:abc',
    'socks5://bob:s3cret@proxy.example:1080', 'bob:s3cret@proxy.example', 'http://bob:s3cret@proxy.example:99999/'] do
  begin
    Message := '';
    try
      ResolveArtifactProxy('https://a.example/x', Setting, '', '');
    except
      on E: ESearchArtifactError do
        Message := E.Message;
    end;
    Assert.AreNotEqual('', Message, Setting);
    Assert.IsFalse(Message.Contains('s3cret'), Message);
    Assert.IsFalse(Message.Contains('bob'), Message);
    Assert.IsTrue(Message.Contains('***@proxy.example'), Message);
  end;
end;

{ TScriptedTransport }

constructor TScriptedTransport.Create(const Text: string);
begin
  inherited Create;
  Content := TEncoding.UTF8.GetBytes(Text);
end;

function TScriptedTransport.Get(const Url: string; RangeStart: Int64; const Target: TStream;
  const BeforeBody: TFunc<Int64, Boolean>; const Progress: TProc<Int64>;
  const Cancelled: TCancelCheck): TTransferResult;
var
  Call, Count, Start: Integer;
  Body: TBytes;
begin
  Call := Length(RangeStarts);
  RangeStarts := RangeStarts + [RangeStart];
  Result := Default(TTransferResult);
  if (Call < Length(Statuses)) and (Statuses[Call] <> 0) then
  begin
    Body := TEncoding.UTF8.GetBytes('oops');
    Target.WriteBuffer(Body[0], Length(Body));
    Result.Status := Statuses[Call];
    Exit;
  end;
  Start := 0;
  if not IgnoreRange then
    Start := RangeStart;
  Body := Copy(Content, Start, MaxInt);
  if not BeforeBody(Length(Body)) then
  begin
    Result.Refused := True;
    Exit;
  end;
  Count := Length(Body);
  if (Call < Length(FailAfter)) and (FailAfter[Call] >= 0) then
    Count := FailAfter[Call];
  if Count > 0 then
    Target.WriteBuffer(Body[0], Count);
  Progress(Count);
  if Count < Length(Body) then
    raise EArtifactTransientError.CreateFmt('failure #%d', [Call + 1]);
  if (RangeStart > 0) and not IgnoreRange then
    Result.Status := 206
  else
    Result.Status := 200;
end;

{ TArtifactFetchResumeTests }

procedure TArtifactFetchResumeTests.Setup;
begin
  FPath := TPath.Combine(TPath.GetTempPath, 'eln-fetch-' + TGUID.NewGuid.ToString + '.part');
  FTransport := TScriptedTransport.Create('ABCDEFGHIJ');
  FTransportIntf := FTransport;
end;

procedure TArtifactFetchResumeTests.TearDown;
begin
  FTransportIntf := nil;
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
end;

function TArtifactFetchResumeTests.Fetcher(const Delays: TArray<Integer>): IArtifactFetcher;
begin
  Result := THttpArtifactFetcher.Create(FTransportIntf, Delays);
end;

function TArtifactFetchResumeTests.FileText: string;
begin
  Result := TFile.ReadAllText(FPath, TEncoding.UTF8);
end;

procedure TArtifactFetchResumeTests.ResumeAppendsAfterFailure;
var
  Last: Int64;
begin
  FTransport.FailAfter := [4, -1];
  Last := 0;
  Fetcher([1, 1, 1, 1, 1]).Fetch('https://example.invalid/f', FPath,
    procedure(Bytes: Int64) begin Last := Bytes; end, nil);
  Assert.AreEqual('ABCDEFGHIJ', FileText);
  Assert.AreEqual(2, Integer(Length(FTransport.RangeStarts)));
  Assert.AreEqual(Int64(0), FTransport.RangeStarts[0]);
  Assert.AreEqual(Int64(4), FTransport.RangeStarts[1]);
  Assert.AreEqual(Int64(10), Last);
end;

procedure TArtifactFetchResumeTests.RestartsWhenServerIgnoresRange;
begin
  FTransport.IgnoreRange := True;
  FTransport.FailAfter := [4, -1, -1];
  Fetcher([1, 1, 1, 1, 1]).Fetch('https://example.invalid/f', FPath, nil, nil);
  Assert.AreEqual('ABCDEFGHIJ', FileText);
  Assert.AreEqual(3, Integer(Length(FTransport.RangeStarts)));
  Assert.AreEqual(Int64(4), FTransport.RangeStarts[1]);
  Assert.AreEqual(Int64(0), FTransport.RangeStarts[2]);
end;

procedure TArtifactFetchResumeTests.GivesUpAfterFiveRetries;
var
  Raised: Boolean;
begin
  FTransport.FailAfter := [1, 1, 1, 1, 1, 1, 1];
  Raised := False;
  try
    Fetcher([1, 1, 1, 1, 1]).Fetch('https://example.invalid/f', FPath, nil, nil);
  except
    on E: EArtifactTransientError do
    begin
      Raised := True;
      Assert.AreEqual('failure #6', E.Message);
    end;
  end;
  Assert.IsTrue(Raised, 'EArtifactTransientError expected');
  Assert.AreEqual(6, Integer(Length(FTransport.RangeStarts)));
end;

procedure TArtifactFetchResumeTests.CancelDuringBackoff;
var
  Watch: TStopwatch;
begin
  FTransport.FailAfter := [3];
  Watch := TStopwatch.StartNew;
  Assert.WillRaise(
    procedure
    begin
      Fetcher([5000]).Fetch('https://example.invalid/f', FPath, nil,
        function: Boolean begin Result := Length(FTransport.RangeStarts) >= 1; end);
    end, EOperationCancelled);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 2500, 'cancel must not wait for the whole backoff');
  Assert.AreEqual(1, Integer(Length(FTransport.RangeStarts)));
end;

procedure TArtifactFetchResumeTests.BackoffSurvivesCancelCheckThatConsumesTime;
var
  Watch: TStopwatch;
begin
  FTransport.FailAfter := [3, -1];
  Watch := TStopwatch.StartNew;
  Fetcher([100]).Fetch('https://example.invalid/f', FPath, nil,
    function: Boolean
    begin
      if Length(FTransport.RangeStarts) >= 1 then
        Sleep(150);
      Result := False;
    end);
  Assert.AreEqual('ABCDEFGHIJ', FileText);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 5000, 'backoff must not sleep past a deadline it already missed');
end;

procedure TArtifactFetchResumeTests.ServerErrorIsRetriedAndBodyDropped;
begin
  FTransport.Statuses := [503, 0];
  Fetcher([1, 1, 1, 1, 1]).Fetch('https://example.invalid/f', FPath, nil, nil);
  Assert.AreEqual('ABCDEFGHIJ', FileText);
  Assert.AreEqual(2, Integer(Length(FTransport.RangeStarts)));
end;

procedure TArtifactFetchResumeTests.ClientErrorIsNotRetried;
begin
  FTransport.Statuses := [404];
  Assert.WillRaise(
    procedure
    begin
      Fetcher([1, 1, 1, 1, 1]).Fetch('https://example.invalid/f', FPath, nil, nil);
    end, ESearchArtifactError);
  Assert.AreEqual(1, Integer(Length(FTransport.RangeStarts)));
  Assert.AreEqual(Int64(0), TFile.GetSize(FPath));
end;

procedure TArtifactFetchResumeTests.RtlNetworkExceptionsAreTransient;
var
  Transient: TArray<Exception>;
  NotTransient: TArray<Exception>;
  E: Exception;
begin
  Transient := [ENetHTTPClientException.Create('client'), ENetHTTPRequestException.Create('connect'),
    ENetHTTPResponseException.Create('read stall 12002')];
  NotTransient := [ENetHTTPCertificateException.Create('certificate'), ENetCredentialException.Create('credentials'),
    EInOutError.Create('disk'), ESearchArtifactError.Create('manifest')];
  try
    for E in Transient do
      Assert.IsTrue(IsTransientNetworkException(E), E.ClassName);
    for E in NotTransient do
      Assert.IsFalse(IsTransientNetworkException(E), E.ClassName);
  finally
    for E in Transient do
      E.Free;
    for E in NotTransient do
      E.Free;
  end;
end;

const
  LinuxArchivesVariable = 'ELN_SEARCH_ARCHIVES';

constructor TArchiveFolderFetcher.Create(const Source: string);
begin
  inherited Create;
  FSource := Source;
end;

procedure TArchiveFolderFetcher.Fetch(const Url, TargetPath: string; const Progress: TProc<Int64>;
  const Cancelled: TCancelCheck);
var
  Name: string;
begin
  Name := Url.Substring(Url.LastIndexOf('/') + 1);
  Names := Names + [Name];
  TFile.Copy(TPath.Combine(FSource, Name), TargetPath);
end;

procedure TLinuxArchiveInstallTests.InstallerExtractsEveryListedFile;
var
  Manifest: TSearchArtifactManifest;
  Root: string;
  Fetcher: TArchiveFolderFetcher;
  FetcherRef: IArtifactFetcher;
  A: TArtifactArchive;
  F: TArtifactFile;
  Listed: Integer;
  Check: TArtifactCheck;
begin
  Manifest := TSearchArtifactManifest.LoadFromFile(LinuxManifestPath);
  Manifest.Models := nil;
  Root := TPath.Combine(TPath.GetTempPath, 'eln-linux-archives-' + TGUID.NewGuid.ToString);
  Fetcher := TArchiveFolderFetcher.Create(GetEnvironmentVariable(LinuxArchivesVariable));
  FetcherRef := Fetcher;
  try
    InstallSearchArtifacts(Manifest, Root, FetcherRef, nil, nil);
    Assert.AreEqual('onnxruntime-linux-x64-1.31.1.tgz,pdfium-linux-x64.tgz', string.Join(',', Fetcher.Names));
    Listed := 0;
    for A in Manifest.Archives do
      for F in A.Files do
      begin
        Assert.IsTrue(ArtifactFileMatches(TPath.Combine(Root, F.RelativePath), F.Size, F.Sha256), F.RelativePath);
        Inc(Listed);
      end;
    Assert.AreEqual(Listed, Integer(Length(TDirectory.GetFiles(Root, '*', TSearchOption.soAllDirectories))));
    Check := CheckSearchArtifacts(Manifest, Root, True);
    Assert.IsTrue(Check.State = asReady, Check.FirstProblem);
  finally
    FetcherRef := nil;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

{$IFDEF MSWINDOWS}
{ TWinHttpCancelTests }

procedure TWinHttpCancelTests.CancelDuringStalledResponseReturnsPromptly;
var
  Data: TWSAData;
  Listener: TSocket;
  Address: TSockAddrIn;
  AddressSize: Integer;
  Port: Word;
  Path, SavedHttp, SavedHttps: string;
  Watch: TStopwatch;
begin
  Assert.AreEqual(0, WSAStartup($0202, Data));
  Listener := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  SavedHttp := GetEnvironmentVariable('HTTP_PROXY');
  SavedHttps := GetEnvironmentVariable('HTTPS_PROXY');
  Path := TPath.Combine(TPath.GetTempPath, 'eln-stall-' + TGUID.NewGuid.ToString + '.part');
  try
    Assert.IsTrue(Listener <> INVALID_SOCKET);
    Address := Default(TSockAddrIn);
    Address.sin_family := AF_INET;
    Address.sin_addr.S_addr := htonl(INADDR_LOOPBACK);
    Assert.AreEqual(0, bind(Listener, TSockAddr(Address), SizeOf(Address)));
    AddressSize := SizeOf(Address);
    Assert.AreEqual(0, getsockname(Listener, TSockAddr(Address), AddressSize));
    Port := ntohs(Address.sin_port);
    Assert.AreEqual(0, listen(Listener, 1));
    SetEnvironmentValue('HTTP_PROXY', '');
    SetEnvironmentValue('HTTPS_PROXY', '');
    Watch := TStopwatch.StartNew;
    Assert.WillRaise(
      procedure
      begin
        THttpArtifactFetcher.Create.Fetch(Format('http://127.0.0.1:%d/f', [Port]), Path, nil,
          function: Boolean begin Result := Watch.ElapsedMilliseconds > 300; end);
      end, EOperationCancelled);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 2000,
      Format('cancel took %d ms', [Watch.ElapsedMilliseconds]));
  finally
    if SavedHttp <> '' then
      SetEnvironmentValue('HTTP_PROXY', SavedHttp);
    if SavedHttps <> '' then
      SetEnvironmentValue('HTTPS_PROXY', SavedHttps);
    closesocket(Listener);
    WSACleanup;
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;
{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TSearchArtifactTests);
  TDUnitX.RegisterTestFixture(TSearchArtifactInstallTests);
  TDUnitX.RegisterTestFixture(TArtifactProxyTests);
  TDUnitX.RegisterTestFixture(TArtifactFetchResumeTests);
  if GetEnvironmentVariable(LinuxArchivesVariable) <> '' then
    TDUnitX.RegisterTestFixture(TLinuxArchiveInstallTests);
{$IFDEF MSWINDOWS}
  TDUnitX.RegisterTestFixture(TWinHttpCancelTests);
{$ENDIF}

end.
