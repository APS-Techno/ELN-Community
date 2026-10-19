unit test_AddFileSourceFolder;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook, unit_Item;

type
  [TestFixture]
  TAddFileSourceFolderTests = class
  private
    FRoot: string;
    FSource: string;
    FWork: string;
    FNotebook: TLocalNotebook;
    FItem: TItem;
    function PrepareWorkingCopy(FileId: Int64): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure AddedFilesNeverMaterializeIntoSourceFolder;
  end;

implementation

uses
  System.IOUtils, System.Classes, System.Types, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls,
  VirtualTrees.Types, RzSplit, unit_ItemTypes, unit_Project, unit_FileType,
  unit_ELNPluginCore, unit_ELNThumbnailList, frame_ItemTree, frame_ContentViewer,
  dm_TreeImages, dlg_File, unit_PreviewQueue, unit_ElnFileEnumerator,
  unit_DataModel, test_SharedDesktopViewer;

const
  Password = 'Synthetic-Desktop-Regression-Only!';

type
  TItemContextPlugin = class(TComponent, IViewerPlugin, IItemContextAware)
  private
    FFrame: TFrame;
    FItemId: Integer;
  public
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

constructor TItemContextPlugin.Create(AOwner: TComponent);
begin
  inherited;
  FFrame := TFrame.Create(nil);
end;

destructor TItemContextPlugin.Destroy;
begin
  FFrame.Free;
  inherited;
end;

function TItemContextPlugin.GetFrame: TFrame;
begin Result := FFrame; end;
function TItemContextPlugin.GetCaption: string;
begin Result := 'Item context viewer'; end;
function TItemContextPlugin.GetParams: TPluginParams;
begin
  Result := Default(TPluginParams);
  Result.PType := ptFile;
  Result.Ext := '.synthetic';
end;

function TItemContextPlugin.LoadFromFile(const FileName: string): Boolean;
begin
  if (FItemId > 0) and Assigned(ElnFileEnumerator) then
    ElnFileEnumerator.EnsureItemFilesInDir(FItemId, ExtractFilePath(FileName));
  Result := True;
end;

function TItemContextPlugin.LoadFromStream(Stream: TMemoryStream): Boolean;
begin Result := False; end;
procedure TItemContextPlugin.DisplayText(const Caption, Text: string);
begin end;
procedure TItemContextPlugin.SetItemContext(ItemId: Integer; FileId: Int64);
begin FItemId := ItemId; end;

procedure TAddFileSourceFolderTests.Setup;
var
  Project: TProject;
  Detached: TItem;
begin
  Assert.IsNull(Model, 'Fixture must not replace a live desktop model');
  FRoot := TPath.Combine(TPath.GetTempPath,
    'ELN-AddFile-' + TGUID.NewGuid.ToString);
  FSource := TPath.Combine(FRoot, 'source');
  FWork := TPath.Combine(FRoot, 'work');
  ForceDirectories(FSource);
  ForceDirectories(FWork);
  FNotebook := TLocalNotebook.CreateNew(TPath.Combine(FRoot, 'notebook.sqlite'),
    TPath.Combine(FRoot, 'files'), 'Synthetic', 'Scientist', Password);
  Model := TDataModel.Create(FNotebook.Connection, FNotebook.Principal.Id,
    FNotebook.AccessPolicy, FNotebook.Storage);
  Project := Model.Projects.AddProject('Synthetic project', '', Model.User);
  Model.Items.AssignProject(Project.Id, 0);
  Detached := Model.Items.AddItem(TItemType.Specimen, 'Synthetic item',
    TItemLevel.Item, 0, '', nil, nil, Model.User.Id);
  FItem := Model.Manager.Find<TItem>(Detached.Id);
  Detached.Free;
end;

procedure TAddFileSourceFolderTests.TearDown;
begin
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TAddFileSourceFolderTests.PrepareWorkingCopy(FileId: Int64): string;
var
  Stored: unit_Item.TFile;
begin
  Stored := Model.Manager.Find<unit_Item.TFile>(FileId);
  Result := TPath.Combine(FWork, Stored.FullName);
  Model.Storage.CopyOut(
    StringReplace(Model.GetFileName(FileId), '\', '/', [rfReplaceAll]), Result);
end;

procedure TAddFileSourceFolderTests.AddedFilesNeverMaterializeIntoSourceFolder;
var
  FileType: TFileType;
  Files: TFileInfoArray;
  Queue: TArray<TPreviewQueueItem>;
  Entry: TPreviewQueueItem;
  Host: TForm;
  Viewer: TframeContentViewer;
  Items: TframeItemTree;
  Thumbnails: TELNThumbnailList;
  Splitter: TRzSplitter;
  Previews: TPreviewQueue;
  Plugin: TItemContextPlugin;
  PreviousEnumerator: IElnFileEnumerator;
  OwnImages: Boolean;
  Original, Found: TArray<string>;
  I: Integer;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.synthetic';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;

  SetLength(Files, 2);
  for I := 0 to 1 do
  begin
    Files[I].Name := 'sample' + IntToStr(I);
    Files[I].FileType := FileType;
    Files[I].SourcePath := TPath.Combine(FSource, Files[I].Name + '.synthetic');
    TFile.WriteAllText(Files[I].SourcePath, 'synthetic body ' + IntToStr(I));
  end;
  Original := TDirectory.GetFiles(FSource);
  TArray.Sort<string>(Original);

  PreviousEnumerator := ElnFileEnumerator;
  InstallElnFileEnumerator;
  OwnImages := not Assigned(dmTreeImages);
  if OwnImages then
    dmTreeImages := TdmTreeImages.Create(nil);
  Host := nil;
  Plugin := nil;
  try
    Host := TForm.CreateNew(nil);
    Viewer := TframeContentViewer.Create(Host);
    Viewer.Parent := Host;
    InitializeEmptyViewer(Viewer);
    Plugin := TItemContextPlugin.Create(nil);
    Viewer.upfPluginManagerPluginRegistered(nil, Plugin);
    Thumbnails := TELNThumbnailList.Create(Host);
    Thumbnails.Parent := Host;
    Splitter := TRzSplitter.Create(Host);
    Splitter.Parent := Host;
    Items := TframeItemTree.Create(Host);
    Items.Parent := Host;
    Previews := TPreviewQueue.Create(Host, Viewer);
    try
      Items.Init(Thumbnails, Viewer, Splitter);
      Items.tmrStartup.Enabled := False;
      Items.OnPrepareFile := PrepareWorkingCopy;

      Assert.IsTrue(Items.UploadFiles(Files, FItem, Queue));
      Assert.AreEqual(2, Length(Queue));
      for Entry in Queue do
        Previews.ProcessItem(Entry);

      Found := TDirectory.GetFiles(FSource);
      TArray.Sort<string>(Found);
      Assert.AreEqual(Length(Original), Length(Found),
        'The source folder must contain only the original files, found: ' +
        string.Join(', ', Found));
      for I := 0 to High(Original) do
        Assert.AreEqual(Original[I], Found[I]);
      Assert.AreEqual(0, Length(TDirectory.GetDirectories(FSource)));
      for Entry in Queue do
        Assert.IsFalse(SameText(ExcludeTrailingPathDelimiter(
          ExtractFilePath(Entry.FilePath)), FSource),
          'The queued path must be the notebook working copy, not the source: ' +
          Entry.FilePath);
    finally
      Previews.Free;
      Items.Free;
    end;
  finally
    if Assigned(Plugin) then
      Plugin.Frame.Parent := nil;
    Host.Free;
    Plugin.Free;
    if OwnImages then
      FreeAndNil(dmTreeImages);
    ElnFileEnumerator := PreviousEnumerator;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAddFileSourceFolderTests);

end.
