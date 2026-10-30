unit test_PassageContextBuild;

interface

uses
  System.SysUtils, System.Generics.Collections, DUnitX.TestFramework, unit_SearchPassages, unit_PassageContext;

type
  [TestFixture]
  TPassageContextBuildTests = class
  private
    function Parts(const Project: string; const Folders: TArray<string>;
      const Title, Kind, Parent, Action: string): TPassageContextParts;
  public
    [Test]
    procedure DescriptionPassageFormat;
    [Test]
    procedure ActionTypeSitsBetweenKindAndParent;
    [Test]
    procedure TitlePassageLeavesOutItemTitle;
    [Test]
    procedure EachPartIsCutTo80Characters;
    [Test]
    procedure WholeContextIsCutTo240Characters;
    [Test]
    procedure CutKeepsSurrogatePairsWhole;
    [Test]
    procedure EmptyPartsAreLeftOut;
    [Test]
    procedure LineBreaksInPartsBecomeSpaces;
    [Test]
    procedure ModeNoneGivesNoContext;
    [Test]
    procedure ModeItemKeepsProjectAndItemTitle;
    [Test]
    procedure ModeFullEqualsBuild;
    [Test]
    procedure EmptyContextKeepsStage5HashAndEmbedText;
    [Test]
    procedure ContextHashIsSha256OfContextLfText;
    [Test]
    procedure AppendedPassagesCarryContextAndHash;
    [Test]
    procedure PartsRoundTripThroughJson;
    [Test]
    procedure MalformedPartsJsonIsRefused;
  end;

implementation

uses
  System.Hash;

function TPassageContextBuildTests.Parts(const Project: string; const Folders: TArray<string>;
  const Title, Kind, Parent, Action: string): TPassageContextParts;
begin
  Result := Default(TPassageContextParts);
  Result.ProjectTitle := Project;
  Result.FolderPath := Folders;
  Result.ItemTitle := Title;
  Result.ItemKind := Kind;
  Result.ParentTitle := Parent;
  Result.ActionType := Action;
end;

procedure TPassageContextBuildTests.DescriptionPassageFormat;
begin
  Assert.AreEqual(
    'Thermal stability > Annealing > W/B4C stacks | Item: Anneal 600 C | Specimen | Parent: XRR run',
    BuildPassageContext(Parts('Thermal stability', ['Annealing', 'W/B4C stacks'], 'Anneal 600 C',
      'Specimen', 'XRR run', ''), pfItemDescription));
end;

procedure TPassageContextBuildTests.ActionTypeSitsBetweenKindAndParent;
begin
  Assert.AreEqual('P | Item: Scan | Measurement | X-ray reflectometry | Parent: Run',
    BuildPassageContext(Parts('P', nil, 'Scan', 'Measurement', 'Run', 'X-ray reflectometry'),
      pfItemDescription));
end;

procedure TPassageContextBuildTests.TitlePassageLeavesOutItemTitle;
begin
  Assert.AreEqual('P > F | Measurement | Parent: Run',
    BuildPassageContext(Parts('P', ['F'], 'Scan', 'Measurement', 'Run', ''), pfItemTitle));
end;

procedure TPassageContextBuildTests.EachPartIsCutTo80Characters;
begin
  Assert.AreEqual(StringOfChar('a', 80),
    BuildPassageContext(Parts(StringOfChar('a', 100), nil, '', '', '', ''), pfItemDescription));
  Assert.AreEqual(StringOfChar('b', 80),
    BuildPassageContext(Parts('', [StringOfChar('b', 90)], '', '', '', ''), pfItemDescription));
  Assert.AreEqual('Item: ' + StringOfChar('c', 80),
    BuildPassageContext(Parts('', nil, StringOfChar('c', 81), '', '', ''), pfItemDescription));
  Assert.AreEqual(StringOfChar('d', 80),
    BuildPassageContext(Parts('', nil, '', StringOfChar('d', 200), '', ''), pfItemDescription));
  Assert.AreEqual(StringOfChar('e', 80),
    BuildPassageContext(Parts('', nil, '', '', '', StringOfChar('e', 120)), pfItemDescription));
  Assert.AreEqual('Parent: ' + StringOfChar('f', 80),
    BuildPassageContext(Parts('', nil, '', '', StringOfChar('f', 81), ''), pfItemDescription));
end;

procedure TPassageContextBuildTests.WholeContextIsCutTo240Characters;
var
  Context: string;
begin
  Context := BuildPassageContext(Parts(StringOfChar('a', 80), [StringOfChar('b', 80),
    StringOfChar('c', 80)], StringOfChar('d', 80), 'Specimen', 'Parent', ''), pfItemDescription);
  Assert.AreEqual(240, Length(Context));
  Assert.AreEqual(StringOfChar('a', 80) + ' > ' + StringOfChar('b', 80) + ' > ' +
    StringOfChar('c', 74), Context);
end;

procedure TPassageContextBuildTests.CutKeepsSurrogatePairsWhole;
var
  Value: string;
begin
  Value := StringOfChar('a', 79) + #$D83D#$DE00 + 'b';
  Assert.AreEqual(StringOfChar('a', 79),
    BuildPassageContext(Parts(Value, nil, '', '', '', ''), pfItemDescription));
end;

procedure TPassageContextBuildTests.EmptyPartsAreLeftOut;
begin
  Assert.AreEqual('P | Item: Scan', BuildPassageContext(Parts('P', ['', '  '], 'Scan', '', '', ''),
    pfItemDescription));
  Assert.AreEqual('F | Specimen', BuildPassageContext(Parts('', ['F'], '', 'Specimen', '', ''),
    pfItemDescription));
  Assert.AreEqual('', BuildPassageContext(Parts('', nil, '', '', '', ''), pfItemDescription));
  Assert.AreEqual('', BuildPassageContext(Parts('', nil, 'Only the title', '', '', ''), pfItemTitle));
end;

procedure TPassageContextBuildTests.LineBreaksInPartsBecomeSpaces;
begin
  Assert.AreEqual('A B | Item: C D',
    BuildPassageContext(Parts('A'#13#10'B', nil, #9'C'#10'D ', '', '', ''), pfItemDescription));
end;

procedure TPassageContextBuildTests.ModeNoneGivesNoContext;
begin
  Assert.AreEqual('', PassageContextFor(pcmNone, Parts('P', ['F'], 'Scan', 'Specimen', 'Run', 'A'),
    pfItemDescription));
end;

procedure TPassageContextBuildTests.ModeItemKeepsProjectAndItemTitle;
var
  Source: TPassageContextParts;
begin
  Source := Parts('P', ['F'], 'Scan', 'Specimen', 'Run', 'A');
  Assert.AreEqual('P | Item: Scan', PassageContextFor(pcmItem, Source, pfItemDescription));
  Assert.AreEqual('P', PassageContextFor(pcmItem, Source, pfItemTitle));
end;

procedure TPassageContextBuildTests.ModeFullEqualsBuild;
var
  Source: TPassageContextParts;
begin
  Source := Parts('P', ['F'], 'Scan', 'Specimen', 'Run', 'A');
  Assert.AreEqual(BuildPassageContext(Source, pfFileText), PassageContextFor(pcmFull, Source, pfFileText));
end;

procedure TPassageContextBuildTests.EmptyContextKeepsStage5HashAndEmbedText;
var
  Passage: TSearchPassage;
begin
  Assert.AreEqual(PassageHash('alpha'), PassageContentHash('', 'alpha'));
  Passage := Default(TSearchPassage);
  Passage.Text := 'alpha';
  Assert.AreEqual('alpha', PassageEmbedText(Passage));
  Passage.Context := 'P';
  Assert.AreEqual('P'#10'alpha', PassageEmbedText(Passage));
end;

procedure TPassageContextBuildTests.ContextHashIsSha256OfContextLfText;
var
  Expected: string;
begin
  Expected := UpperCase(THashSHA2.GetHashString('P > F'#10'alpha', THashSHA2.TSHA2Version.SHA256));
  Assert.AreEqual(Expected, PassageContentHash('P > F', 'alpha'));
  Assert.AreNotEqual(PassageContentHash('P > F', 'alpha'), PassageContentHash('P > G', 'alpha'));
  Assert.AreNotEqual(PassageHash('alpha'), PassageContentHash('P > F', 'alpha'));
end;

procedure TPassageContextBuildTests.AppendedPassagesCarryContextAndHash;
var
  Target: TList<TSearchPassage>;
  Passage: TSearchPassage;
begin
  Target := TList<TSearchPassage>.Create;
  try
    AppendTextPassages(Target, 'item:1:description', 1, 1, 0, pfItemDescription,
      StringOfChar('x', 2600), 'P | Item: T');
    Assert.IsTrue(Target.Count > 1);
    for Passage in Target do
    begin
      Assert.AreEqual('P | Item: T', Passage.Context);
      Assert.AreEqual(PassageContentHash('P | Item: T', Passage.Text), Passage.ContentHash);
    end;
    Target.Clear;
    AppendTextPassages(Target, 'item:1:description', 1, 1, 0, pfItemDescription, 'alpha', '');
    Assert.AreEqual('', Target[0].Context);
    Assert.AreEqual(PassageHash('alpha'), Target[0].ContentHash);
  finally
    Target.Free;
  end;
end;

procedure TPassageContextBuildTests.PartsRoundTripThroughJson;
var
  Source, Back: TPassageContextParts;
begin
  Source := Parts('Проект "A"', ['Top', 'Sub > deep'], 'Title'#10'line', 'Specimen', 'Parent', 'Action');
  Assert.IsTrue(TryParsePassageContextParts(PassageContextPartsToJson(Source), Back));
  Assert.AreEqual(Source.ProjectTitle, Back.ProjectTitle);
  Assert.AreEqual<NativeInt>(2, Length(Back.FolderPath));
  Assert.AreEqual('Top', Back.FolderPath[0]);
  Assert.AreEqual('Sub > deep', Back.FolderPath[1]);
  Assert.AreEqual(Source.ItemTitle, Back.ItemTitle);
  Assert.AreEqual(Source.ItemKind, Back.ItemKind);
  Assert.AreEqual(Source.ParentTitle, Back.ParentTitle);
  Assert.AreEqual(Source.ActionType, Back.ActionType);
  Assert.AreEqual(BuildPassageContext(Source, pfFileText), BuildPassageContext(Back, pfFileText));
end;

procedure TPassageContextBuildTests.MalformedPartsJsonIsRefused;
var
  Back: TPassageContextParts;
  Text: string;
begin
  for Text in ['', '{', '[]', '"text"', 'null'] do
    Assert.IsFalse(TryParsePassageContextParts(Text, Back), '[' + Text + ']');
end;

initialization
  TDUnitX.RegisterTestFixture(TPassageContextBuildTests);

end.
