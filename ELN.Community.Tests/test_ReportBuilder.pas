unit test_ReportBuilder;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestReportBuilder = class
  public
    [Test]
    procedure BuildReport_SingleItem_ContainsTitle;
    [Test]
    procedure BuildReport_IncludesMetadata;
    [Test]
    procedure BuildReport_WithProtocol_ContainsSection;
    [Test]
    procedure BuildReport_WithValues_ContainsTable;
    [Test]
    procedure BuildReport_ScientificValuesRetainMagnitudeAndPrecision;
    [Test]
    procedure BuildReport_WithFiles_ContainsTable;
    [Test]
    procedure BuildReport_WithTags_ContainsTagNames;
    [Test]
    procedure BuildReport_WithComments_ContainsText;
    [Test]
    procedure BuildReport_WithSignature_ContainsSignerName;
    [Test]
    procedure BuildReport_PaperSizeLetter_UsesLetterCss;
    [Test]
    procedure BuildReport_HtmlEncodes_SpecialChars;
    [Test]
    procedure BuildReport_MultipleItems_HasPageBreak;
    [Test]
    procedure BuildReport_WithLogoPath_ContainsBase64Image;
    [Test]
    procedure BuildReport_MultipleItems_HasTableOfContents;
    [Test]
    procedure BuildFiles_WithStorageRoot_ContainsThumbnailGrid;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  unit_ReportBuilder,
  unit_Item,
  unit_ItemTypes,
  unit_Protocol,
  unit_LabEntry,
  unit_Tag,
  unit_Comment,
  unit_Signature,
  unit_Template,
  unit_FileType,
  unit_ValueType,
  unit_TimeHelper;

function MakeItem(const ATitle: string;
  AType: TItemType = TItemType.Synthesis): TItem;
begin
  Result := TItem.Create;
  Result.Title := ATitle;
  Result.Type_ := AType;
  Result.Level := TItemLevel.Proc;
  Result.CreatedDate := UTCNow;
end;

function MakeData(Item: TItem): TReportItemData;
begin
  Result.Item := Item;
  Result.Tags := nil;
  Result.Comments := nil;
  Result.Signature := nil;
  Result.IntegrityOk := True;
  Result.HasSignature := False;
  Result.Templates := nil;
  Result.StorageRoot := '';
end;

{ TTestReportBuilder }

procedure TTestReportBuilder.BuildReport_SingleItem_ContainsTitle;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('My Test Experiment');
  try
    Items.Add(MakeData(Item));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('My Test Experiment'),
      'Report should contain item title');
  finally
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_IncludesMetadata;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Metadata Test');
  try
    Item.Description := 'A detailed description';
    Items.Add(MakeData(Item));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('A detailed description'),
      'Should contain item description');
  finally
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithProtocol_ContainsSection;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Protocol: TProtocol;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Protocol Test');
  try
    Protocol := TProtocol.Create;
    Protocol.Title := 'My Experiment Protocol';
    Protocol.ProtocolType := ptExperiment;
    Protocol.ValidationStatus := vsDraft;
    Protocol.CreatedDate := UTCNow;
    Item.Entries.Add(Protocol);

    Items.Add(MakeData(Item));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('My Experiment Protocol'),
      'Should contain protocol title');
  finally
    Protocol.Free;
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithValues_ContainsTable;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Val: TValue;
  VType: TValueType;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Values Test');
  VType := TValueType.Create;
  try
    VType.Symbol := 'T';
    VType.Units := 'K';

    Val := TValue.Create;
    Val.ValueType := VType;
    Val.Value := 300.0;
    Val.RecType := TRecType.TEST_RESULT;
    Val.Description := 'Room temperature';
    Val.CreatedDate := UTCNow;
    Item.Values.Add(Val);

    Items.Add(MakeData(Item));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('300'), 'Should contain the value');
    Assert.IsTrue(Html.Contains('Room temperature'),
      'Should contain value description');
  finally
    Val.Free;
    VType.Free;
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_ScientificValuesRetainMagnitudeAndPrecision;
const
  Values: array[0..3] of Double = (1.25e-8, -1.3e-8, 1.23456789e-3, 1e-200);
  Tolerances: array[0..3] of Double = (1e-10, 1e-12, 1e-8, 1e-202);
  Separator = ' &plusmn; ';
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Val: TValue;
  VType: TValueType;
  Html, NumberText: string;
  Match: TMatch;
  I, SeparatorPos: Integer;
  DisplayValue, DisplayTolerance: Double;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Scientific magnitude');
  VType := TValueType.Create;
  Val := TValue.Create;
  try
    VType.Symbol := 'd';
    VType.Units := 'm';
    Val.ValueType := VType;
    Val.RecType := TRecType.TEST_RESULT;
    Val.CreatedDate := UTCNow;
    Item.Values.Add(Val);
    Items.Add(MakeData(Item));
    for I := Low(Values) to High(Values) do
    begin
      Val.Value := Values[I];
      Val.Tol := Tolerances[I];
      Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);
      Match := TRegEx.Match(Html, '<td>d</td>\s*<td>([^<]*)</td>\s*<td>m</td>');
      Assert.IsTrue(Match.Success, 'Scientific value row must retain its symbol and units');
      NumberText := Match.Groups[1].Value;
      SeparatorPos := Pos(Separator, NumberText);
      Assert.IsTrue(SeparatorPos > 0, 'Nonzero tolerance must be reported');
      Assert.IsTrue(TryStrToFloat(Copy(NumberText, 1, SeparatorPos - 1), DisplayValue),
        'Reported value must be a number');
      Assert.IsTrue(TryStrToFloat(Copy(NumberText, SeparatorPos + Length(Separator),
        MaxInt), DisplayTolerance), 'Reported tolerance must be a number');
      Assert.AreEqual(Values[I], DisplayValue, Abs(Values[I]) * 1e-12,
        'Report must preserve nonzero magnitude and scientific precision');
      Assert.AreEqual(Tolerances[I], DisplayTolerance, Abs(Tolerances[I]) * 1e-12,
        'Report must preserve the tolerance magnitude and precision');
    end;
  finally
    Val.Free;
    VType.Free;
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithFiles_ContainsTable;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  F: TFile;
  FT: TFileType;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Files Test');
  FT := TFileType.Create;
  try
    FT.Ext := '.pdf';

    F := TFile.Create;
    F.Title := 'Analysis Report';
    F.Hash := 'abc123def456';
    F.FileType := FT;
    F.CreatedDate := UTCNow;
    Item.Files.Add(F);

    Items.Add(MakeData(Item));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('Analysis Report'), 'Should contain file title');
    Assert.IsTrue(Html.Contains('.pdf'), 'Should contain file extension');
    Assert.IsTrue(Html.Contains('abc123def456'), 'Should contain file hash');
  finally
    F.Free;
    FT.Free;
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithTags_ContainsTagNames;
var
  Items: TList<TReportItemData>;
  Tags: TTags;
  Tag: TTag;
  Data: TReportItemData;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Tags := TTags.Create;
  Tag := TTag.Create;
  try
    Tag.Name := 'Important';
    Tag.Color := '#FF0000';
    Tags.Add(Tag);

    Data := MakeData(MakeItem('Tags Test'));
    Data.Tags := Tags;
    Items.Add(Data);

    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('Important'), 'Should contain tag name');
    Assert.IsTrue(Html.Contains('#FF0000'), 'Should contain tag color');
  finally
    Tag.Free;
    Data.Item.Free;
    Tags.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithComments_ContainsText;
var
  Items: TList<TReportItemData>;
  Comments: TComments;
  Comment: TComment;
  Data: TReportItemData;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Comments := TComments.Create;
  Comment := TComment.Create;
  try
    Comment.UserName := 'Dr. Smith';
    Comment.Text := 'Excellent results on this sample';
    Comment.CreatedDate := UTCNow;
    Comments.Add(Comment);

    Data := MakeData(MakeItem('Comments Test'));
    Data.Comments := Comments;
    Items.Add(Data);

    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('Dr. Smith'), 'Should contain commenter name');
    Assert.IsTrue(Html.Contains('Excellent results on this sample'),
      'Should contain comment text');
  finally
    Comment.Free;
    Data.Item.Free;
    Comments.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithSignature_ContainsSignerName;
var
  Items: TList<TReportItemData>;
  Sig: TSignature;
  Data: TReportItemData;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Sig := TSignature.Create;
  try
    Sig.UserName := 'Prof. Johnson';
    Sig.SignedDate := UTCNow;
    Sig.Meaning := 'Approval';
    Sig.ContentHash := 'sha256abcdef1234567890';

    Data := MakeData(MakeItem('Signature Test'));
    Data.Signature := Sig;
    Data.HasSignature := True;
    Data.IntegrityOk := True;
    Items.Add(Data);

    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('Prof. Johnson'),
      'Should contain signer name');
    Assert.IsTrue(Html.Contains('Approval'),
      'Should contain signature meaning');
  finally
    Sig.Free;
    Data.Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_PaperSizeLetter_UsesLetterCss;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Opts: TReportOptions;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Paper Test');
  try
    Items.Add(MakeData(Item));
    Opts := TReportOptions.Default;
    Opts.PaperSize := psLetter;
    Html := TReportBuilder.BuildReport(Items, Opts);

    Assert.IsTrue(Html.Contains('letter'),
      'CSS should use letter page size');
  finally
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_HtmlEncodes_SpecialChars;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Test <script>alert("xss")</script>');
  try
    Items.Add(MakeData(Item));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('&lt;script&gt;'),
      'Should HTML-encode angle brackets');
    Assert.IsTrue(Html.Contains('&quot;'),
      'Should HTML-encode double quotes');
    Assert.IsFalse(Html.Contains('<script>'),
      'Should not contain raw script tags');
  finally
    Item.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_MultipleItems_HasPageBreak;
var
  Items: TList<TReportItemData>;
  Item1, Item2: TItem;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item1 := MakeItem('First Item');
  Item2 := MakeItem('Second Item');
  try
    Items.Add(MakeData(Item1));
    Items.Add(MakeData(Item2));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('page-break'),
      'Should contain page break between items');
    Assert.IsTrue(Html.Contains('First Item'), 'Should contain first item');
    Assert.IsTrue(Html.Contains('Second Item'), 'Should contain second item');
  finally
    Item1.Free;
    Item2.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildReport_WithLogoPath_ContainsBase64Image;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  Opts: TReportOptions;
  Html: string;
  LogoPath: string;
  SL: TStringList;
begin
  LogoPath := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'eln_test_logo.png';
  SL := TStringList.Create;
  try
    SL.Text := 'PNG';
    SL.SaveToFile(LogoPath);
  finally
    SL.Free;
  end;

  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Logo Test');
  try
    Items.Add(MakeData(Item));
    Opts := TReportOptions.Default;
    Opts.LogoPath := LogoPath;
    Html := TReportBuilder.BuildReport(Items, Opts);

    Assert.IsTrue(Html.Contains('report-logo'), 'Should contain logo div');
    Assert.IsTrue(Html.Contains('data:image/png;base64,'), 'Should contain base64 image');
  finally
    Item.Free;
    Items.Free;
    DeleteFile(LogoPath);
  end;
end;

procedure TTestReportBuilder.BuildReport_MultipleItems_HasTableOfContents;
var
  Items: TList<TReportItemData>;
  Item1, Item2, Item3: TItem;
  Html: string;
begin
  Items := TList<TReportItemData>.Create;
  Item1 := MakeItem('Alpha Experiment');
  Item2 := MakeItem('Beta Experiment');
  Item3 := MakeItem('Gamma Experiment');
  try
    Items.Add(MakeData(Item1));
    Items.Add(MakeData(Item2));
    Items.Add(MakeData(Item3));
    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('toc-list'), 'Should contain TOC list class');
    Assert.IsTrue(Html.Contains('#item-0'), 'Should contain anchor for first item');
    Assert.IsTrue(Html.Contains('#item-2'), 'Should contain anchor for third item');
    Assert.IsTrue(Html.Contains('Alpha Experiment'), 'Should list first item in TOC');
    Assert.IsTrue(Html.Contains('Gamma Experiment'), 'Should list third item in TOC');
  finally
    Item1.Free;
    Item2.Free;
    Item3.Free;
    Items.Free;
  end;
end;

procedure TTestReportBuilder.BuildFiles_WithStorageRoot_ContainsThumbnailGrid;
var
  Items: TList<TReportItemData>;
  Item: TItem;
  F: TFile;
  FT: TFileType;
  Data: TReportItemData;
  Html, TempDir, PreviewDir, PreviewPath: string;
  SL: TStringList;
begin
  TempDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'eln_test_report\';
  PreviewDir := TempDir + 'Previews\[1000]\';
  ForceDirectories(PreviewDir);

  Items := TList<TReportItemData>.Create;
  Item := MakeItem('Thumb Test');
  Item.Id := 42;
  FT := TFileType.Create;
  try
    FT.Ext := '.dat';
    F := TFile.Create;
    F.Id := 7;
    F.Title := 'Measurement Data';
    F.Hash := 'hash123';
    F.FileType := FT;
    F.CreatedDate := UTCNow;
    Item.Files.Add(F);

    PreviewPath := Format('%s%.*d_%.*d.png', [PreviewDir, 5, 42, 5, 7]);
    SL := TStringList.Create;
    try
      SL.Text := 'FAKEPNG';
      SL.SaveToFile(PreviewPath);
    finally
      SL.Free;
    end;

    Data := MakeData(Item);
    Data.StorageRoot := TempDir;
    Items.Add(Data);

    Html := TReportBuilder.BuildReport(Items, TReportOptions.Default);

    Assert.IsTrue(Html.Contains('thumbnail-grid'), 'Should contain thumbnail grid');
    Assert.IsTrue(Html.Contains('data:image/png;base64,'), 'Should contain base64 thumbnail');
    Assert.IsTrue(Html.Contains('Measurement Data'), 'Should contain file title as caption');
  finally
    F.Free;
    FT.Free;
    Item.Free;
    Items.Free;
    if FileExists(PreviewPath) then DeleteFile(PreviewPath);
    RemoveDir(PreviewDir);
    RemoveDir(TempDir + 'Previews\[1000]');
    RemoveDir(TempDir + 'Previews');
    RemoveDir(TempDir);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestReportBuilder);

end.
