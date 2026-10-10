unit test_SharedDesktopMutations;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook,
  unit_Item, unit_ItemTreeVM, System.Messaging, unit_Common;

type
  [TestFixture]
  TSharedDesktopMutationTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FVM: TItemTreeVM;
    FItem: TItem;
    FDialogError: string;
    FLastLocation: TLocation;
    procedure ExerciseActionDialog(Sender: TObject);
    procedure CaptureLocation(const Sender: TObject; const M: TMessage);
    procedure ExerciseDuplicatePicker(Sender: TObject);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SignedNoteAddCannotLeakIntoLaterFlush;
    [Test] procedure SignedProtocolAddCannotLeakIntoLaterFlush;
    [Test] procedure SignedNoteEditCannotLeakIntoLaterFlush;
    [Test] procedure EditedDraftValueRemainsNewAndTransfersOwner;
    [Test] procedure InUseExtensionChangeIsRefusedBeforeMutation;
    [Test] procedure TypedActionFieldsSurviveSelectionChanges;
    [Test] procedure WideFileSelectionKeepsFileCommandsVisible;
    [Test] procedure ProjectRootSelectionIncludesLegacyRootItems;
    [Test] procedure DuplicatePickerProjectRootUsesZero;
    [Test] procedure LegacyRootFolderAndPositiveChildRemainVisible;
  end;

implementation

uses
  System.IOUtils, System.Classes, Aurelius.Engine.ObjectManager,
  unit_Project, unit_ItemTypes, unit_Types,
  unit_ProjectAccessPolicy, unit_Protocol, unit_ValueType, unit_ActionDialogVM, unit_FileType,
  editor_FileTypes, dlg_Action, dlg_ItemPicker, unit_DlgConstants, Vcl.Forms, Vcl.ExtCtrls,
  Vcl.Controls, Aurelius.Drivers.Interfaces, VirtualTrees.Types, RzSplit,
  frame_ProjectsPanel, frame_ItemTree, frame_ContentViewer, unit_ELNThumbnailList,
  test_SharedDesktopViewer, dm_TreeImages, unit_DataModel;

const
  Password = 'Synthetic-Desktop-Regression-Only!';

procedure TSharedDesktopMutationTests.Setup;
var
  Id: TGUID;
  Project: TProject;
  Detached: TItem;
begin
  Assert.IsNull(Model, 'Fixture must not replace a live desktop model');
  CreateGUID(Id);
  FRoot := TPath.Combine(TPath.GetTempPath, 'ELN-Desktop-' + GUIDToString(Id));
  ForceDirectories(FRoot);
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
  FVM := TItemTreeVM.Create(Model.Items, Model.Authors, Model.History,
    Model.Signatures, Model.Comments, Model.Tags, Model.ItemLinks, Model.Access);
  FVM.SetLocation(Project.Id, 0, paReadWrite);
end;

procedure TSharedDesktopMutationTests.TearDown;
begin
  FVM.Free;
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TSharedDesktopMutationTests.WideFileSelectionKeepsFileCommandsVisible;
const
  FileId: Int64 = 2147483648;
var
  FileType: TFileType;
  AFile: unit_Item.TFile;
  Statement: IDBStatement;
  Host: TForm;
  Viewer: TframeContentViewer;
  Items: TframeItemTree;
  Thumbnails: TELNThumbnailList;
  Splitter: TRzSplitter;
  Node: PVirtualNode;
  Data: PNodeData;
  OwnImages: Boolean;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.txt';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  AFile := Model.Items.AddFile(FileType, 'wide identity', Model.User.Id, FItem);
  Statement := Model.Connection.CreateStatement;
  Statement.SetSQLCommand('UPDATE Files SET Id = ' + IntToStr(FileId) +
    ' WHERE Id = ' + IntToStr(AFile.Id));
  Statement.Execute;
  Statement := nil;
  AFile := Model.Manager.Find<unit_Item.TFile>(FileId);
  Assert.IsNotNull(AFile);
  OwnImages := not Assigned(dmTreeImages);
  if OwnImages then
    dmTreeImages := TdmTreeImages.Create(nil);
  Host := nil;
  try
    Host := TForm.CreateNew(nil);
    Viewer := TframeContentViewer.Create(Host);
    Viewer.Parent := Host;
    InitializeEmptyViewer(Viewer);
    Thumbnails := TELNThumbnailList.Create(Host);
    Thumbnails.Parent := Host;
    Splitter := TRzSplitter.Create(Host);
    Splitter.Parent := Host;
    Items := TframeItemTree.Create(Host);
    Items.Parent := Host;
    try
      Items.Init(Thumbnails, Viewer, Splitter);
      Items.tmrStartup.Enabled := False;
      Node := Items.Tree.AddChild(nil);
      Data := Items.Tree.GetNodeData(Node);
      Data.NodeType := ntFile;
      Data.AFile := AFile;
      Assert.IsTrue(Items.SelectFile(FileId));
      Assert.AreEqual(FileId, Model.LastChild);
      Assert.IsTrue(Viewer.btnUpdateFile.Visible,
        'A valid file above MaxInt must retain its file commands');
    finally
      Items.Free;
    end;
  finally
    Host.Free;
    if OwnImages then
      FreeAndNil(dmTreeImages);
  end;
end;

procedure TSharedDesktopMutationTests.SignedNoteAddCannotLeakIntoLaterFlush;
var
  Draft: TProtocol;
  Fresh: TObjectManager;
begin
  Assert.IsTrue(Model.Signatures.SignItem(FItem, Model.User, Password,
    'Synthetic signature', 'Regression fixture'));
  Draft := TProtocol.Create;
  try
    Draft.Title := 'Refused note';
    Draft.ProtocolType := ptNote;
    Draft.FormData := 'Do not persist';
    Assert.IsFalse(FVM.AddNote(Draft, FItem));
    Assert.AreEqual(0, FItem.Entries.Count);
    Model.Manager.Flush;
    Fresh := TObjectManager.Create(Model.Connection);
    try
      Assert.AreEqual(0, Fresh.Find<TItem>(FItem.Id).Entries.Count);
    finally
      Fresh.Free;
    end;
  finally
    Draft.Free;
  end;
end;

procedure TSharedDesktopMutationTests.SignedNoteEditCannotLeakIntoLaterFlush;
var
  Note: TProtocol;
  Fresh: TObjectManager;
begin
  Note := TProtocol.Create;
  Note.Title := 'Original note';
  Note.ProtocolType := ptNote;
  Note.FormData := 'Original body';
  Note.CreatedDate := Now;
  Note.CreatedBy := Model.User.Id;
  Assert.IsTrue(FVM.AddNote(Note, FItem));
  Assert.IsTrue(Model.Signatures.SignItem(FItem, Model.User, Password,
    'Synthetic signature', 'Regression fixture'));
  Assert.IsFalse(FVM.UpdateNote(Note, 'Refused title', 'Refused body'));
  Assert.AreEqual('Original note', Note.Title);
  Assert.AreEqual('Original body', Note.FormData);
  Model.Manager.Flush;
  Fresh := TObjectManager.Create(Model.Connection);
  try
    Assert.AreEqual('Original note', Fresh.Find<TProtocol>(Note.Id).Title);
    Assert.AreEqual('Original body', Fresh.Find<TProtocol>(Note.Id).FormData);
  finally
    Fresh.Free;
  end;
end;

procedure TSharedDesktopMutationTests.SignedProtocolAddCannotLeakIntoLaterFlush;
var
  Draft: TProtocol;
  Fresh: TObjectManager;
begin
  Assert.IsTrue(Model.Signatures.SignItem(FItem, Model.User, Password,
    'Synthetic signature', 'Regression fixture'));
  Draft := TProtocol.Create;
  try
    Draft.Title := 'Refused protocol';
    Draft.ProtocolType := ptExperiment;
    Draft.FormData := '{"result":42}';
    Assert.IsFalse(FVM.AddProtocol(Draft, FItem));
    Assert.AreEqual(0, FItem.Entries.Count);
    Model.Manager.Flush;
    Fresh := TObjectManager.Create(Model.Connection);
    try
      Assert.AreEqual(0, Fresh.Find<TItem>(FItem.Id).Entries.Count);
    finally
      Fresh.Free;
    end;
  finally
    Draft.Free;
  end;
end;

procedure TSharedDesktopMutationTests.EditedDraftValueRemainsNewAndTransfersOwner;
var
  VM: TActionDialogVM;
  VT: TValueType;
  Target: TItem;
begin
  VT := TValueType.Create;
  Target := TItem.Create;
  VM := TActionDialogVM.Create(Model.ActionTypes, Model.Equipments,
    Model.Items, Model.User.Id);
  try
    VT.Symbol := 'T';
    VT.Units := 'K';
    VM.LoadForNew([TItemLevel.Action]);
    VM.Title := 'Custom action';
    VM.Description := 'Keep description';
    VM.Properties := '{"operator":"Synthetic"}';
    VM.AddValue(VT, EXP_CONDITION, 300, 0, 'draft');
    VM.Item.Values[0].Value := 310;
    VM.ValueEdited;
    Assert.IsFalse(VM.IsEditMode);
    Assert.IsTrue(VM.CanSave);
    VM.ApplyTo(Target);
    Assert.AreEqual('Custom action', Target.Title);
    Assert.AreEqual('Keep description', Target.Description);
    Assert.AreEqual('{"operator":"Synthetic"}', Target.Properties);
    Assert.AreEqual(1, Target.Values.Count);
    Assert.AreEqual<Double>(310.0, Target.Values[0].Value);
    Assert.IsTrue(Target.Values[0].Item = Target);
  finally
    VM.Free;
    Target.Free;
    VT.Free;
  end;
end;

procedure TSharedDesktopMutationTests.InUseExtensionChangeIsRefusedBeforeMutation;
var
  FT: TFileType;
  Attachment: unit_Item.TFile;
begin
  FT := TFileType.Create;
  FT.Ext := '.synthetic';
  FT.Description := 'Synthetic file type';
  Model.Manager.Save(FT);
  Model.Manager.Flush;
  Attachment := Model.Items.AddFile(FT, 'fixture', Model.User.Id, FItem);
  Assert.WillRaise(
    procedure
    begin
      TedFileTypes.ValidateExtensionChange(Model.Manager, FT.Id, '.changed');
    end, EInvalidOperation);
  Model.Manager.Flush;
  Assert.AreEqual('.synthetic', Attachment.FileType.Ext);
  TedFileTypes.ValidateExtensionChange(Model.Manager, FT.Id, '.synthetic');
end;

procedure TSharedDesktopMutationTests.ExerciseActionDialog(Sender: TObject);
var
  Dialog: TdlgAction;
begin
  TTimer(Sender).Enabled := False;
  Dialog := Screen.ActiveForm as TdlgAction;
  try
    Dialog.edTitle.Text := 'Custom action';
    Dialog.edComment.Text := 'Keep these notes';
    Dialog.vleProps.InsertRow('operator', 'Synthetic', True);
    Dialog.PropertiesChanged(Dialog.vleProps, 1, 1, 'Synthetic');
    Assert.IsTrue(Dialog.btnSave.Enabled, 'Typing a title must enable Save');
    Dialog.lbItemType.ItemIndex := 1;
    Dialog.lbItemTypeClick(Dialog.lbItemType);
    Assert.AreEqual('Custom action', Dialog.edTitle.Text);
    Assert.AreEqual('Keep these notes', Dialog.edComment.Text);
    Assert.AreEqual('Synthetic', Dialog.vleProps.Values['operator']);
    Dialog.ModalResult := mrOk;
  except
    on E: Exception do
    begin
      FDialogError := E.Message;
      Dialog.ModalResult := mrCancel;
    end;
  end;
end;

procedure TSharedDesktopMutationTests.TypedActionFieldsSurviveSelectionChanges;
var
  Timer: TTimer;
  Draft: TItem;
  Saved: Boolean;
begin
  Draft := TItem.Create;
  Timer := TTimer.Create(nil);
  try
    FDialogError := '';
    Timer.Interval := 1;
    Timer.OnTimer := ExerciseActionDialog;
    Timer.Enabled := True;
    Saved := ShowActionDialog(dmNew, Draft, [TItemLevel.Action]);
    Assert.AreEqual('', FDialogError);
    Assert.IsTrue(Saved);
    Assert.AreEqual('Custom action', Draft.Title);
    Assert.AreEqual('Keep these notes', Draft.Description);
    Assert.AreEqual('{"operator":"Synthetic"}', Draft.Properties);
  finally
    Timer.Free;
    Draft.Free;
  end;
end;

procedure TSharedDesktopMutationTests.CaptureLocation(const Sender: TObject;
  const M: TMessage);
begin
  FLastLocation := TMessage<TLocation>(M).Value;
end;

procedure TSharedDesktopMutationTests.ProjectRootSelectionIncludesLegacyRootItems;
var
  Host: TForm;
  Projects: TframeProjectTree;
  OwnImages: Boolean;
  Legacy: TItem;
  Rows: TItems;
  Node: PVirtualNode;
  Data: frame_ProjectsPanel.PNodeData;
begin
  Legacy := TItem.Create;
  Legacy.Title := 'Legacy root item';
  Legacy.ProjectID := FItem.ProjectID;
  Legacy.FolderID := -1;
  Legacy.Type_ := TItemType.Specimen;
  Legacy.Level := TItemLevel.Item;
  Legacy.CreatedBy := Model.User.Id;
  Legacy.CreatedDate := Now;
  Model.Manager.Save(Legacy);
  Model.Manager.Flush;

  OwnImages := not Assigned(dmTreeImages);
  if OwnImages then
    dmTreeImages := TdmTreeImages.Create(nil);
  Host := nil;
  TMessageManager.DefaultManager.SubscribeToMessage(
    TMessage<TLocation>, CaptureLocation);
  try
    Host := TForm.CreateNew(nil);
    Projects := TframeProjectTree.Create(Host);
    Projects.Parent := Host;
    Projects.Init;
    FLastLocation := Default(TLocation);
    Projects.SelectProject(FItem.ProjectID);
    Assert.AreEqual(FItem.ProjectID, FLastLocation.ProjectID);
    Assert.AreEqual(0, FLastLocation.FolderID,
      'Clicking a project must publish the canonical root destination');
    FVM.SetLocation(FLastLocation.ProjectID, FLastLocation.FolderID,
      FLastLocation.Access);
    FVM.LoadItemData;
    Rows := FVM.Items;
    try
      Assert.AreEqual(2, Rows.Count,
        'Project root must include both canonical and legacy root rows');
    finally
      Rows.Free;
    end;

    Node := Projects.Tree.AddChild(nil);
    Data := Projects.Tree.GetNodeData(Node);
    Data.NodeType := frame_ProjectsPanel.ntFavoriteItem;
    Data.FavProjectId := FItem.ProjectID;
    Data.FavFolderId := -1;
    Data.FavItemId := Legacy.Id;
    Data.FavTitle := 'Legacy favorite';
    Projects.Tree.ClearSelection;
    Projects.Tree.Selected[Node] := True;
    Projects.Tree.FocusedNode := Node;
    Projects.TreeClick(Projects.Tree);
    Assert.AreEqual(0, FLastLocation.FolderID,
      'Opening a legacy root favorite must not republish a negative folder');
    Assert.AreEqual(0, Model.LastFolder);

    Data.FavFolderId := 123;
    Projects.TreeClick(Projects.Tree);
    Assert.AreEqual(123, FLastLocation.FolderID,
      'A positive folder destination must remain unchanged');
    Assert.AreEqual(123, Model.LastFolder);
  finally
    TMessageManager.DefaultManager.Unsubscribe(
      TMessage<TLocation>, CaptureLocation);
    Host.Free;
    if OwnImages then
      FreeAndNil(dmTreeImages);
  end;
end;

procedure TSharedDesktopMutationTests.LegacyRootFolderAndPositiveChildRemainVisible;
var
  Project: TProject;
  Legacy, Child: TFolder;
  Host: TForm;
  Projects: TframeProjectTree;
  OwnImages: Boolean;
  Node, LegacyNode, ChildNode: PVirtualNode;
  Data, ParentData: frame_ProjectsPanel.PNodeData;
  Fresh: TObjectManager;
begin
  Project := Model.Manager.Find<TProject>(FItem.ProjectID);
  Project.Expanded := True;
  Legacy := TFolder.Create;
  Legacy.Title := 'Legacy root folder';
  Legacy.ParentFolderID := -1;
  Legacy.CreatedDate := Now;
  Legacy.CreatedBy := Model.User.Id;
  Legacy.Expanded := True;
  Project.Folders.Add(Legacy);
  Model.Manager.Flush;
  Child := TFolder.Create;
  Child.Title := 'Nested folder';
  Child.ParentFolderID := Legacy.Id;
  Child.CreatedDate := Now;
  Child.CreatedBy := Model.User.Id;
  Project.Folders.Add(Child);
  Model.Manager.Flush;

  OwnImages := not Assigned(dmTreeImages);
  if OwnImages then
    dmTreeImages := TdmTreeImages.Create(nil);
  Host := nil;
  try
    Host := TForm.CreateNew(nil);
    Projects := TframeProjectTree.Create(Host);
    Projects.Parent := Host;
    Projects.Init;
    LegacyNode := nil;
    ChildNode := nil;
    Node := Projects.Tree.GetFirstVisible;
    while Assigned(Node) do
    begin
      Data := Projects.Tree.GetNodeData(Node);
      if Assigned(Data) and (Data.NodeType = frame_ProjectsPanel.ntFolder) then
      begin
        if Data.Folder.Id = Legacy.Id then LegacyNode := Node;
        if Data.Folder.Id = Child.Id then ChildNode := Node;
      end;
      Node := Projects.Tree.GetNextVisible(Node);
    end;
    Assert.IsTrue(Assigned(LegacyNode), 'A legacy root folder must be visible');
    Assert.IsTrue(Assigned(ChildNode), 'Its positive-parent child must be visible');
    ParentData := Projects.Tree.GetNodeData(LegacyNode.Parent);
    Assert.IsTrue(ParentData.NodeType = frame_ProjectsPanel.ntProject);
    Assert.AreEqual(Project.Id, ParentData.Project.Id);
    Assert.IsTrue(ChildNode.Parent = LegacyNode,
      'A positive parent ID must keep the child below its actual parent');

    Model.Manager.Flush;
    Fresh := TObjectManager.Create(Model.Connection);
    try
      Assert.AreEqual(-1, Fresh.Find<TFolder>(Legacy.Id).ParentFolderID,
        'Displaying legacy folders must not rewrite stored root values');
      Assert.AreEqual(Legacy.Id, Fresh.Find<TFolder>(Child.Id).ParentFolderID);
    finally
      Fresh.Free;
    end;
  finally
    Host.Free;
    if OwnImages then
      FreeAndNil(dmTreeImages);
  end;
end;

procedure TSharedDesktopMutationTests.ExerciseDuplicatePicker(Sender: TObject);
var
  Dialog: TdlgItemPicker;
  Node: PVirtualNode;
  Data: PPickerNodeData;
begin
  TTimer(Sender).Enabled := False;
  Dialog := Screen.ActiveForm as TdlgItemPicker;
  try
    Node := Dialog.Tree.GetFirst;
    while Assigned(Node) do
    begin
      Data := Dialog.Tree.GetNodeData(Node);
      if (Data.Kind = nkProject) and (Data.ProjectId = FItem.ProjectID) then
      begin
        Dialog.Tree.Selected[Node] := True;
        Dialog.Tree.FocusedNode := Node;
        Dialog.TreeChange(Dialog.Tree, Node);
        Assert.IsTrue(Dialog.btnOK.Enabled);
        Dialog.btnOKClick(Dialog.btnOK);
        Exit;
      end;
      Node := Dialog.Tree.GetNext(Node);
    end;
    raise Exception.Create('Synthetic project destination was not listed');
  except
    on E: Exception do
    begin
      FDialogError := E.Message;
      Dialog.ModalResult := mrCancel;
    end;
  end;
end;

procedure TSharedDesktopMutationTests.DuplicatePickerProjectRootUsesZero;
var
  Timer: TTimer;
  Destination: TDuplicateResult;
  Accepted: Boolean;
begin
  Timer := TTimer.Create(nil);
  try
    FDialogError := '';
    Timer.Interval := 1;
    Timer.OnTimer := ExerciseDuplicatePicker;
    Timer.Enabled := True;
    Accepted := TdlgItemPicker.ExecuteDuplicate(FItem.Id, Destination);
    Assert.AreEqual('', FDialogError);
    Assert.IsTrue(Accepted);
    Assert.AreEqual(FItem.ProjectID, Destination.ProjectId);
    Assert.AreEqual(0, Destination.FolderId);
    Assert.AreEqual(0, Destination.ParentItemId);
  finally
    Timer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSharedDesktopMutationTests);

end.
