unit test_SharedDesktopViewer;

interface

uses
  DUnitX.TestFramework, frame_ContentViewer;

type
  [TestFixture]
  TSharedDesktopViewerTests = class
  public
    [Test] procedure FailedExtractionPreservesEveryProtocolField;
    [Test] procedure NotesRenderRichTextWithoutAPlugin;
    [Test] procedure PreviewLoadDoesNotReplaceActiveViewer;
    [Test] procedure ConstructionFailurePreservesOriginalException;
    [Test] procedure UnsupportedFileRetainsExternalOpenIdentity;
    [TestCase('Matched reader', 'False')]
    [TestCase('Generic reader', 'True')]
    procedure FailedReaderDoesNotActivateItsCard(GenericReader: Boolean);
  end;

procedure InitializeEmptyViewer(Viewer: TframeContentViewer);

implementation

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Graphics,
  Aurelius.Types.Nullable, unit_Protocol, unit_ELNPluginCore,
  editor_Protocols, dm_TreeImages, System.IOUtils, Winapi.Windows;

type
  EFixtureReadFailure = class(Exception);

  TFailingContentViewer = class(TframeContentViewer)
  protected
    procedure ReadState(Reader: TReader); override;
  end;

  TUnavailableEditor = class(TInterfacedObject, IProtocolEditor)
  public
    procedure LoadTemplate(const TemplateHtml, FormData: string);
    procedure LoadFreeText(const FormData: string);
    function GetFormData: string;
    procedure SetReadOnly(Value: Boolean);
    function GetReadOnly: Boolean;
    procedure PrepareForReparent;
    procedure SetOnDirty(const Handler: TNotifyEvent);
  end;

  // A deterministic file decoder: the host, not this double, must isolate it.
  TFixturePlugin = class(TComponent, IViewerPlugin, IItemContextAware)
  private
    FFrame: TFrame;
    FItemId: Integer;
    FFileId: Int64;
  public
    Extensions: string;
    RejectLoad: Boolean;
    LoadCount: Integer;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetFrame: TFrame;
    function GetCaption: string;
    function GetParams: TPluginParams;
    function LoadFromFile(const FileName: string): Boolean;
    function LoadFromStream(Stream: TMemoryStream): Boolean;
    procedure DisplayText(const Caption, Text: string);
    procedure SetItemContext(ItemId: Integer; FileId: Int64);
    property Frame: TFrame read GetFrame;
  end;

procedure TFailingContentViewer.ReadState(Reader: TReader);
begin
  // Simulate failure before the DFM has constructed the plugin manager.
  raise EFixtureReadFailure.Create('Synthetic frame streaming failure');
end;

procedure TSharedDesktopViewerTests.ConstructionFailurePreservesOriginalException;
begin
  Assert.WillRaise(
    procedure
    var
      Viewer: TFailingContentViewer;
    begin
      Viewer := TFailingContentViewer.Create(nil);
      Viewer.Free;
    end, EFixtureReadFailure);
end;

procedure InitializeEmptyViewer(Viewer: TframeContentViewer);
var
  Root, PreviousDllDirectory: string;
  Count: DWORD;
begin
  Root := TPath.Combine(TPath.GetTempPath,
    'ELN-Empty-Plugins-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Root);
  try
    Count := GetDllDirectory(0, nil);
    SetLength(PreviousDllDirectory, Count);
    if Count > 0 then
    begin
      Count := GetDllDirectory(Count, PChar(PreviousDllDirectory));
      SetLength(PreviousDllDirectory, Count);
    end;
    try
      Viewer.Init(Root);
    finally
      if PreviousDllDirectory = '' then
        SetDllDirectory(nil)
      else
        SetDllDirectory(PChar(PreviousDllDirectory));
    end;
  finally
    TDirectory.Delete(Root);
  end;
end;

procedure TUnavailableEditor.LoadTemplate(const TemplateHtml, FormData: string);
begin end;
procedure TUnavailableEditor.LoadFreeText(const FormData: string);
begin end;
function TUnavailableEditor.GetFormData: string;
begin
  raise EInvalidOperation.Create('Synthetic extraction failure');
end;
procedure TUnavailableEditor.SetReadOnly(Value: Boolean);
begin end;
function TUnavailableEditor.GetReadOnly: Boolean;
begin Result := False; end;
procedure TUnavailableEditor.PrepareForReparent;
begin end;
procedure TUnavailableEditor.SetOnDirty(const Handler: TNotifyEvent);
begin end;

constructor TFixturePlugin.Create(AOwner: TComponent);
begin
  inherited;
  FFrame := TFrame.Create(nil);
  Extensions := '.synthetic';
end;

destructor TFixturePlugin.Destroy;
begin
  FFrame.Free;
  inherited;
end;

function TFixturePlugin.GetFrame: TFrame;
begin Result := FFrame; end;
function TFixturePlugin.GetCaption: string;
begin Result := 'Synthetic viewer'; end;
function TFixturePlugin.GetParams: TPluginParams;
begin
  Result := Default(TPluginParams);
  Result.PType := ptFile;
  Result.Ext := Extensions;
end;
function TFixturePlugin.LoadFromFile(const FileName: string): Boolean;
begin
  Inc(LoadCount);
  FFrame.Hint := Format('%s:%d:%d', [FileName, FItemId, FFileId]);
  Result := not RejectLoad;
end;
function TFixturePlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin Result := False; end;
procedure TFixturePlugin.DisplayText(const Caption, Text: string);
begin FFrame.Hint := Text; end;
procedure TFixturePlugin.SetItemContext(ItemId: Integer; FileId: Int64);
begin FItemId := ItemId; FFileId := FileId; end;

procedure TSharedDesktopViewerTests.FailedExtractionPreservesEveryProtocolField;
var
  Protocol: TProtocol;
  Editor: IProtocolEditor;
begin
  Protocol := TProtocol.Create;
  Editor := TUnavailableEditor.Create;
  try
    Protocol.Title := 'Original title';
    Protocol.ProtocolType := ptMeasurement;
    Protocol.TemplateId := 7;
    Protocol.FormData := '{"result":42}';
    Assert.WillRaise(
      procedure
      begin
        TedProtocols.ApplyEditorContent(Protocol, Editor, 'Changed title',
          ptExperiment, 9);
      end, EInvalidOperation);
    Assert.AreEqual('Original title', Protocol.Title);
    Assert.AreEqual(Ord(ptMeasurement), Ord(Protocol.ProtocolType.Value));
    Assert.AreEqual(7, Protocol.TemplateId.Value);
    Assert.AreEqual('{"result":42}', Protocol.FormData);
  finally
    Protocol.Free;
  end;
end;

procedure TSharedDesktopViewerTests.NotesRenderRichTextWithoutAPlugin;
var
  Host: TForm;
  Viewer: TframeContentViewer;
begin
  Host := TForm.CreateNew(nil);
  try
    Viewer := TframeContentViewer.Create(Host);
    Viewer.Parent := Host;
    InitializeEmptyViewer(Viewer);
    Viewer.DisplayNote('Synthetic note', '{\rtf1\ansi Plain \b bold\b0 .}');
    Assert.IsTrue(Viewer.Cards.ActiveCard = Viewer.NoteCard);
    Assert.IsTrue(Pos('Plain bold', Viewer.NoteContent.Text) > 0);
    Assert.IsTrue(Viewer.NoteContent.ReadOnly);
    Assert.IsFalse(Viewer.btnOpen.Visible);
    Assert.IsFalse(Viewer.btnUpdatePreview.Visible);
    Viewer.NoteContent.SelStart := 6;
    Viewer.NoteContent.SelLength := 4;
    Assert.IsTrue(fsBold in Viewer.NoteContent.SelAttributes.Style);
  finally
    Host.Free;
  end;
end;

procedure TSharedDesktopViewerTests.PreviewLoadDoesNotReplaceActiveViewer;
var
  Host: TForm;
  Viewer: TframeContentViewer;
  Active: TFixturePlugin;
  Owner: TComponent;
  Preview: IViewerPlugin;
begin
  Host := TForm.CreateNew(nil);
  Active := nil;
  try
    Viewer := TframeContentViewer.Create(Host);
    Viewer.Parent := Host;
    InitializeEmptyViewer(Viewer);
    Active := TFixturePlugin.Create(nil);
    Viewer.upfPluginManagerPluginRegistered(nil, Active);
    Viewer.DisplayFile('A.synthetic');
    Owner := TComponent.Create(nil);
    try
      Preview := Viewer.LoadPreviewPlugin('B.synthetic', 31, 42, Owner);
      Assert.IsTrue(Assigned(Preview));
      Assert.AreEqual('B.synthetic:31:42', Preview.Frame.Hint);
      Assert.AreEqual('A.synthetic:0:0', Active.Frame.Hint);
      Assert.IsTrue(Preview.Frame <> Active.Frame);
      Assert.IsFalse(Preview.Frame.Parent.Visible);
    finally
      Preview := nil;
      Owner.Free;
    end;
  finally
    // VCL parents destroy their child controls even when Owner is nil.
    // Keep the plugin's frame alive until its interfaces have been released.
    if Assigned(Active) then
      Active.Frame.Parent := nil;
    Host.Free;
    Active.Free;
  end;
end;

procedure TSharedDesktopViewerTests.FailedReaderDoesNotActivateItsCard(
  GenericReader: Boolean);
var
  Host: TForm;
  Viewer: TframeContentViewer;
  Reader, Fallback: TFixturePlugin;
  PreviousCard: TComponent;
begin
  Host := TForm.CreateNew(nil);
  Reader := nil;
  Fallback := nil;
  try
    Viewer := TframeContentViewer.Create(Host);
    Viewer.Parent := Host;
    InitializeEmptyViewer(Viewer);
    PreviousCard := Viewer.Cards.ActiveCard;
    Reader := TFixturePlugin.Create(nil);
    if GenericReader then
      Reader.Extensions := '';
    Viewer.upfPluginManagerPluginRegistered(nil, Reader);
    if not GenericReader then
    begin
      Fallback := TFixturePlugin.Create(nil);
      Fallback.Extensions := '';
      Viewer.upfPluginManagerPluginRegistered(nil, Fallback);
    end;
    Viewer.DisplayFile('Previous.synthetic', 7);
    Reader.RejectLoad := True;
    Assert.WillRaise(
      procedure
      begin
        Viewer.DisplayFile('Rejected.synthetic', 42);
      end, EReadError);
    Assert.IsTrue(Viewer.Cards.ActiveCard = PreviousCard,
      'A rejected reader must not become the successful display');
    Assert.IsFalse(Viewer.IsFileDisplayed(42),
      'Rejected content must not own a notebook file identity');
    Assert.IsFalse(Viewer.IsFileDisplayed(7));
    Assert.AreEqual(2, Reader.LoadCount);
    if Assigned(Fallback) then
      Assert.AreEqual(0, Fallback.LoadCount,
        'A reader failure is not an unsupported-extension fallback');
  finally
    if Assigned(Reader) then
      Reader.Frame.Parent := nil;
    if Assigned(Fallback) then
      Fallback.Frame.Parent := nil;
    Host.Free;
    Fallback.Free;
    Reader.Free;
  end;
end;

procedure TSharedDesktopViewerTests.UnsupportedFileRetainsExternalOpenIdentity;
var
  Host: TForm;
  Viewer: TframeContentViewer;
begin
  Host := TForm.CreateNew(nil);
  try
    Viewer := TframeContentViewer.Create(Host);
    Viewer.Parent := Host;
    InitializeEmptyViewer(Viewer);
    Viewer.DisplayFile('Unsupported.extension', 77);
    Assert.IsTrue(Viewer.IsFileDisplayed(77),
      'An unsupported file must still be available to Open externally');
    Assert.IsTrue(Viewer.btnOpen.Visible);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSharedDesktopViewerTests);

end.
