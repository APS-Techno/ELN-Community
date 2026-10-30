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
    procedure ExerciseQuickEquipment(Sender: TObject);
    procedure ExerciseQuickActionType(Sender: TObject);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SignedNoteAddCannotLeakIntoLaterFlush;
    [Test] procedure SignedProtocolAddCannotLeakIntoLaterFlush;
    [Test] procedure SignedNoteEditCannotLeakIntoLaterFlush;
    [Test] procedure EditedDraftValueRemainsNewAndTransfersOwner;
    [Test] procedure InUseExtensionChangeIsRefusedBeforeMutation;
    [Test] procedure TypedActionFieldsSurviveSelectionChanges;
    [Test] procedure QuickEquipmentOkWaitsForAllFields;
    [Test] procedure QuickActionTypeOkWaitsForTitle;
    [Test] procedure WideFileSelectionKeepsFileCommandsVisible;
    [Test] procedure SelectFileKeepsMultiSelectionThatContainsIt;
    [Test] procedure ProjectRootSelectionIncludesLegacyRootItems;
    [Test] procedure DuplicatePickerProjectRootUsesZero;
    [Test] procedure LegacyRootFolderAndPositiveChildRemainVisible;
    [Test] procedure StartupRestoresLastSelectedProjectAndFolder;
  end;

implementation

uses
  System.IOUtils, System.Classes, Aurelius.Engine.ObjectManager,
  unit_Project, unit_ItemTypes, unit_Types,
  unit_ProjectAccessPolicy, unit_Protocol, unit_ValueType, unit_ValueTypeModel, unit_ActionDialogVM, unit_FileType,
  editor_FileTypes, dlg_Action, dlg_ItemPicker, unit_DlgConstants, Vcl.Forms, Vcl.ExtCtrls,
  Vcl.Controls, Vcl.StdCtrls, Aurelius.Drivers.Interfaces, VirtualTrees.Types, RzSplit, unit_ActionType,
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

procedure TSharedDesktopMutationTests.SelectFileKeepsMultiSelectionThatContainsIt;
var
  FileType: TFileType;
  Files: array[0..2] of unit_Item.TFile;
  Nodes: array[0..2] of PVirtualNode;
  Host: TForm;
  Viewer: TframeContentViewer;
  Items: TframeItemTree;
  Thumbnails: TELNThumbnailList;
  Splitter: TRzSplitter;
  Data: PNodeData;
  OwnImages: Boolean;
  I: Integer;
begin
  FileType := TFileType.Create;
  FileType.Ext := '.txt';
  FileType.CreatedDate := Now;
  Model.Manager.Save(FileType);
  Model.Manager.Flush;
  for I := 0 to 2 do
    Files[I] := Model.Items.AddFile(FileType, 'file ' + IntToStr(I),
      Model.User.Id, FItem);
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
      for I := 0 to 2 do
      begin
        Nodes[I] := Items.Tree.AddChild(nil);
        Data := Items.Tree.GetNodeData(Nodes[I]);
        Data.NodeType := ntFile;
        Data.AFile := Files[I];
      end;
      Items.Tree.Selected[Nodes[0]] := True;
      Items.Tree.Selected[Nodes[1]] := True;
      Items.Tree.FocusedNode := Nodes[0];

      Assert.IsTrue(Items.SelectFile(Files[1].Id));
      Assert.AreEqual(Cardinal(2), Items.Tree.SelectedCount,
        'Selecting a file inside the selection must keep the selection');
      Assert.IsTrue(Items.Tree.FocusedNode = Nodes[1]);

      Assert.IsTrue(Items.SelectFile(Files[2].Id));
      Assert.AreEqual(Cardinal(1), Items.Tree.SelectedCount,
        'Selecting a file outside the selection must select only that file');
      Assert.IsTrue(Items.Tree.Selected[Nodes[2]]);
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
    Assert.AreEqual<NativeInt>(0, FItem.Entries.Count);
    Model.Manager.Flush;
    Fresh := TObjectManager.Create(Model.Connection);
    try
      Assert.AreEqual<NativeInt>(0, Fresh.Find<TItem>(FItem.Id).Entries.Count);
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
    Assert.AreEqual<NativeInt>(0, FItem.Entries.Count);
    Model.Manager.Flush;
    Fresh := TObjectManager.Create(Model.Connection);
    try
      Assert.AreEqual<NativeInt>(0, Fresh.Find<TItem>(FItem.Id).Entries.Count);
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
  Before: TValueFields;
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
    Before := TValueFields.Read(VM.Item.Values[0]);
    VM.Item.Values[0].Value := 310;
    VM.ValueEdited(VM.Item.Values[0], Before);
    Assert.AreEqual<NativeInt>(1, Length(VM.ValueRows));
    Assert.AreEqual('T', VM.ValueRows[0].Quantity);
    Assert.AreEqual('Condition', VM.ValueRows[0].Kind);
    Assert.AreEqual('draft', VM.ValueRows[0].Note);
    Assert.AreEqual(FormatSIValue(310, 'K'), VM.ValueRows[0].Value);
    Assert.IsFalse(VM.IsEditMode);
    Assert.IsTrue(VM.CanSave);
    VM.ApplyTo(Target);
    Assert.AreEqual('Custom action', Target.Title);
    Assert.AreEqual('Keep description', Target.Description);
    Assert.AreEqual('{"operator":"Synthetic"}', Target.Properties);
    Assert.AreEqual<NativeInt>(1, Target.Values.Count);
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
    Assert.AreEqual('Add new action', Dialog.Caption);
    Assert.AreEqual('Properties (1)', Dialog.tsProperties.Caption);
    Dialog.cbItemType.ItemIndex := 1;
    Dialog.cbItemTypeChange(Dialog.cbItemType);
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

procedure TSharedDesktopMutationTests.ExerciseQuickEquipment(Sender: TObject);
var
  Form: TForm;
  Edits: TArray<TEdit>;
  Ok: TButton;
  I: Integer;
begin
  TTimer(Sender).Enabled := False;
  Form := Screen.ActiveForm;
  try
    Ok := nil;
    for I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TEdit then
        Edits := Edits + [TEdit(Form.Components[I])]
      else if (Form.Components[I] is TButton) and
        (TButton(Form.Components[I]).Caption = 'OK') then
        Ok := TButton(Form.Components[I]);
    Assert.AreEqual<NativeInt>(3, Length(Edits));
    Assert.IsNotNull(Ok);
    Edits[0].Text := 'Synthetic model';
    Edits[2].Text := 'Synthetic lab';
    Assert.IsFalse(Ok.Enabled, 'OK must wait for the manufacturer');
    Edits[1].Text := '   ';
    Assert.IsFalse(Ok.Enabled, 'Blank text is not a manufacturer');
    Edits[1].Text := 'Synthetic maker';
    Assert.IsTrue(Ok.Enabled, 'All fields filled must enable OK');
    Ok.Click;
  except
    on E: Exception do
    begin
      FDialogError := E.Message;
      Form.ModalResult := mrCancel;
    end;
  end;
end;

procedure TSharedDesktopMutationTests.QuickEquipmentOkWaitsForAllFields;
var
  Timer: TTimer;
  AModel, AManufacturer, ALocation: string;
begin
  Timer := TTimer.Create(nil);
  try
    FDialogError := '';
    Timer.Interval := 1;
    Timer.OnTimer := ExerciseQuickEquipment;
    Timer.Enabled := True;
    Assert.IsTrue(ShowQuickEquipment(AModel, AManufacturer, ALocation),
      FDialogError);
    Assert.AreEqual('', FDialogError);
    Assert.AreEqual('Synthetic model', AModel);
    Assert.AreEqual('Synthetic maker', AManufacturer);
    Assert.AreEqual('Synthetic lab', ALocation);
  finally
    Timer.Free;
  end;
end;

procedure TSharedDesktopMutationTests.ExerciseQuickActionType(Sender: TObject);
var
  Form: TForm;
  Title: TEdit;
  Ok: TButton;
  I: Integer;
begin
  TTimer(Sender).Enabled := False;
  Form := Screen.ActiveForm;
  try
    Title := nil;
    Ok := nil;
    for I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TEdit then
        Title := TEdit(Form.Components[I])
      else if (Form.Components[I] is TButton) and
        (TButton(Form.Components[I]).Caption = 'OK') then
        Ok := TButton(Form.Components[I]);
    Assert.IsNotNull(Title);
    Assert.IsNotNull(Ok);
    Assert.IsFalse(Ok.Enabled, 'OK must wait for a title');
    Title.Text := '   ';
    Assert.IsFalse(Ok.Enabled, 'Blank text is not a title');
    Title.Text := 'Synthetic type';
    Assert.IsTrue(Ok.Enabled, 'A title must enable OK');
    Ok.Click;
  except
    on E: Exception do
    begin
      FDialogError := E.Message;
      Form.ModalResult := mrCancel;
    end;
  end;
end;

procedure TSharedDesktopMutationTests.QuickActionTypeOkWaitsForTitle;
var
  Timer: TTimer;
  ATitle: string;
  AKind: TActionKind;
begin
  Timer := TTimer.Create(nil);
  try
    FDialogError := '';
    Timer.Interval := 1;
    Timer.OnTimer := ExerciseQuickActionType;
    Timer.Enabled := True;
    Assert.IsTrue(ShowQuickActionType(TItemType.Measurement, ATitle, AKind),
      FDialogError);
    Assert.AreEqual('', FDialogError);
    Assert.AreEqual('Synthetic type', ATitle);
    Assert.IsTrue(AKind = TActionKind.Measurement);
  finally
    Timer.Free;
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
      Assert.AreEqual<NativeInt>(2, Rows.Count,
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

procedure TSharedDesktopMutationTests.StartupRestoresLastSelectedProjectAndFolder;
var
  Project: TProject;
  Folder: TFolder;
  OwnImages: Boolean;
  Kind: frame_ProjectsPanel.TNodeType;
  Id: Integer;

  procedure SelectedAfterInit(out AKind: frame_ProjectsPanel.TNodeType; out AId: Integer);
  var
    Host: TForm;
    Projects: TframeProjectTree;
    Node: PVirtualNode;
    Data: frame_ProjectsPanel.PNodeData;
  begin
    Host := TForm.CreateNew(nil);
    try
      Projects := TframeProjectTree.Create(Host);
      Projects.Parent := Host;
      Projects.Init;
      Projects.RestoreLastSelection;
      Node := Projects.Tree.GetFirstSelected;
      Assert.IsTrue(Assigned(Node), 'Startup must select the remembered node');
      Data := Projects.Tree.GetNodeData(Node);
      AKind := Data.NodeType;
      case AKind of
        frame_ProjectsPanel.ntProject: AId := Data.Project.Id;
        frame_ProjectsPanel.ntFolder: AId := Data.Folder.Id;
      else
        AId := 0;
      end;
    finally
      Host.Free;
    end;
  end;

begin
  Project := Model.Manager.Find<TProject>(FItem.ProjectID);
  Folder := TFolder.Create;
  Folder.Title := 'Remembered folder';
  Folder.ParentFolderID := 0;
  Folder.CreatedDate := Now;
  Folder.CreatedBy := Model.User.Id;
  Project.Folders.Add(Folder);
  Model.Manager.Flush;
  OwnImages := not Assigned(dmTreeImages);
  if OwnImages then
    dmTreeImages := TdmTreeImages.Create(nil);
  try
    Model.History.UserRecord.LastProject := Project.Id;
    Model.History.UserRecord.LastFolder := 0;
    SelectedAfterInit(Kind, Id);
    Assert.IsTrue(Kind = frame_ProjectsPanel.ntProject, 'A remembered project is selected');
    Assert.AreEqual(Project.Id, Id);

    Model.History.UserRecord.LastProject := Project.Id;
    Model.History.UserRecord.LastFolder := Folder.Id;
    SelectedAfterInit(Kind, Id);
    Assert.IsTrue(Kind = frame_ProjectsPanel.ntFolder, 'A remembered folder is selected');
    Assert.AreEqual(Folder.Id, Id);
  finally
    if OwnImages then
      FreeAndNil(dmTreeImages);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSharedDesktopMutationTests);

end.
