unit test_ItemTreeBatch;

interface

uses
  System.SysUtils, DUnitX.TestFramework, unit_LocalNotebook,
  unit_Item, unit_ItemTypes, unit_ItemTreeVM, unit_ItemTreeBatch;

type
  [TestFixture]
  TItemTreeBatchTests = class
  private
    FRoot: string;
    FNotebook: TLocalNotebook;
    FVM: TItemTreeVM;
    FBatch: TItemTreeBatch;
    FProjectId: Integer;
    function NewItem(const Title: string; Parent: Integer;
      Level: TItemLevel = TItemLevel.Item): TItem;
    function NewFile(Owner: TItem; const Title: string): unit_Item.TFile;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TopLevelDropsDescendantsAndOwnedNodes;
    [Test] procedure AllowsFollowsSelectionRules;
    [Test] procedure FormatSkipsCapsLines;
    [Test] procedure UniqueTargetPathAddsCounter;
    [Test] procedure PlanDeleteSkipsBlockedTargets;
    [Test] procedure PlanDeleteSeesFreshSignature;
    [Test] procedure ExecuteDeleteProcessesAllKinds;
    [Test] procedure DeleteItemWithSelectedOwnFile;
    [Test] procedure DeletedTargetsKeepKeyAndTitle;
    [Test] procedure ExecuteDeleteContinuesAfterFailure;
    [Test] procedure DescendantCountCountsSubtrees;
    [Test] procedure PlanMoveItemsSkipsFolderSignedAndCycle;
    [Test] procedure ExecuteMoveItemsReparents;
    [Test] procedure ExecuteMoveFilesMovesBytes;
    [Test] procedure PlanMoveFilesSkipsSameItem;
    [Test] procedure TagCountsAndAssignAll;
    [Test] procedure ExportSameTitleTwice;
    [Test] procedure ExecuteMoveFilesRollsBackOnStorageFailure;
  end;

implementation

uses
  System.IOUtils, Aurelius.Criteria.Linq, Aurelius.Engine.ObjectManager,
  unit_DataModel, unit_Project, unit_LabEntry, unit_FileType,
  unit_ProjectAccessPolicy, unit_Tag;

const
  Password = 'Synthetic-Desktop-Regression-Only!';

procedure TItemTreeBatchTests.Setup;
var
  Id: TGUID;
  Project: TProject;
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
  FProjectId := Project.Id;
  Model.Items.AssignProject(Project.Id, 0);
  FVM := TItemTreeVM.Create(Model.Items, Model.Authors, Model.History,
    Model.Signatures, Model.Comments, Model.Tags, Model.ItemLinks, Model.Access);
  FVM.SetLocation(Project.Id, 0, paReadWrite);
  FBatch := TItemTreeBatch.Create(Model, FVM);
end;

procedure TItemTreeBatchTests.TearDown;
begin
  FBatch.Free;
  FVM.Free;
  FreeAndNil(Model);
  FNotebook.Free;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TItemTreeBatchTests.NewItem(const Title: string; Parent: Integer;
  Level: TItemLevel): TItem;
var
  Detached: TItem;
begin
  Detached := Model.Items.AddItem(TItemType.Specimen, Title, Level, Parent, '',
    nil, nil, Model.User.Id);
  Result := Model.Manager.Find<TItem>(Detached.Id);
  Detached.Free;
end;

function TItemTreeBatchTests.NewFile(Owner: TItem;
  const Title: string): unit_Item.TFile;
var
  FileType: TFileType;
begin
  FileType := Model.Manager.Find<TFileType>
    .Where(Linq['Ext'] = '.txt').UniqueResult;
  if FileType = nil then
  begin
    FileType := TFileType.Create;
    FileType.Ext := '.txt';
    FileType.CreatedDate := Now;
    Model.Manager.Save(FileType);
    Model.Manager.Flush;
  end;
  Result := Model.Items.AddFile(FileType, Title, Model.User.Id, Owner);
end;

procedure TItemTreeBatchTests.TopLevelDropsDescendantsAndOwnedNodes;
var
  RootItem, Child, Grandchild, Other: TItem;
  F: unit_Item.TFile;
  N: TLabEntry;
  Picked: TArray<TBatchTarget>;
begin
  RootItem := NewItem('Root', 0);
  Child := NewItem('Child', RootItem.Id);
  Grandchild := NewItem('Grandchild', Child.Id);
  Other := NewItem('Other', 0);
  F := NewFile(RootItem, 'file');
  Model.Items.AddNote('note', 'body', Model.User.Id, Child);
  Assert.AreEqual<NativeInt>(1, Child.Entries.Count);
  N := Child.Entries[0];

  Picked := FBatch.TopLevel([
    TBatchTarget.ForItem(Child), TBatchTarget.ForFile(F, RootItem),
    TBatchTarget.ForItem(RootItem), TBatchTarget.ForItem(Grandchild),
    TBatchTarget.ForNote(N, Child), TBatchTarget.ForItem(Other)]);

  Assert.AreEqual<NativeInt>(2, Length(Picked));
  Assert.AreEqual('I:' + IntToStr(RootItem.Id), Picked[0].Key);
  Assert.AreEqual('I:' + IntToStr(Other.Id), Picked[1].Key);
end;

procedure TItemTreeBatchTests.AllowsFollowsSelectionRules;
var
  RootItem, Child, FolderItem, Other: TItem;
  F1, F2: unit_Item.TFile;
  N: TLabEntry;
  AnItem, AFile, ANote, AFolder, ARoot, AChild: TBatchTarget;
  Empty: TArray<TBatchTarget>;
begin
  RootItem := NewItem('Root', 0);
  Other := NewItem('Other', 0);
  Child := NewItem('Child', RootItem.Id);
  FolderItem := NewItem('Folder', RootItem.Id, TItemLevel.Folder);
  F1 := NewFile(RootItem, 'one');
  F2 := NewFile(RootItem, 'two');
  Model.Items.AddNote('note', 'body', Model.User.Id, Child);
  N := Child.Entries[0];

  AnItem := TBatchTarget.ForItem(Child);
  AFolder := TBatchTarget.ForItem(FolderItem);
  AFile := TBatchTarget.ForFile(F1, RootItem);
  ANote := TBatchTarget.ForNote(N, Child);
  ARoot := TBatchTarget.ForItem(RootItem);
  AChild := TBatchTarget.ForItem(Child);

  Assert.IsTrue(TItemTreeBatch.Allows(boDelete, [AnItem, AFile, ANote]));
  Assert.IsTrue(TItemTreeBatch.Allows(boExtract, [AFile, TBatchTarget.ForFile(F2, RootItem)]));
  Assert.IsFalse(TItemTreeBatch.Allows(boExtract, [AFile, AnItem]));
  Assert.IsTrue(TItemTreeBatch.Allows(boMove, [AnItem, AFolder]));
  Assert.IsTrue(TItemTreeBatch.Allows(boMove, [AFile, TBatchTarget.ForFile(F2, RootItem)]));
  Assert.IsFalse(TItemTreeBatch.Allows(boMove, [AnItem, AFile]));
  Assert.IsTrue(TItemTreeBatch.Allows(boTags, [AnItem, AFolder]));
  Assert.IsFalse(TItemTreeBatch.Allows(boTags, [AnItem, ANote]));
  Assert.IsTrue(TItemTreeBatch.Allows(boExport, [AFile, TBatchTarget.ForFile(F2, RootItem)]));
  Assert.IsFalse(TItemTreeBatch.Allows(boExport, [AFile, ANote]));
  Assert.IsTrue(TItemTreeBatch.Allows(boDrag, [ARoot, TBatchTarget.ForItem(Other)]));
  Assert.IsFalse(TItemTreeBatch.Allows(boDrag, [ARoot, AChild]));

  Empty := nil;
  Assert.IsFalse(TItemTreeBatch.Allows(boDelete, Empty));
  Assert.IsFalse(TItemTreeBatch.Allows(boExtract, Empty));
  Assert.IsFalse(TItemTreeBatch.Allows(boMove, Empty));
  Assert.IsFalse(TItemTreeBatch.Allows(boTags, Empty));
  Assert.IsFalse(TItemTreeBatch.Allows(boExport, Empty));
  Assert.IsFalse(TItemTreeBatch.Allows(boDrag, Empty));
end;

procedure TItemTreeBatchTests.FormatSkipsCapsLines;
var
  Item: TItem;
  Skips: TArray<TBatchSkip>;
  Lines: TArray<string>;
  I: Integer;
begin
  Item := NewItem('Subject', 0);
  SetLength(Skips, 25);
  for I := 0 to 24 do
  begin
    Skips[I].Target := TBatchTarget.ForItem(Item);
    Skips[I].Reason := 'R' + IntToStr(I + 1);
  end;
  Lines := TItemTreeBatch.FormatSkips(Skips, 20).Split([sLineBreak]);
  Assert.AreEqual<NativeInt>(21, Length(Lines));
  Assert.AreEqual('"Subject": R1', Lines[0]);
  Assert.AreEqual('...and 5 more', Lines[20]);
end;

procedure TItemTreeBatchTests.UniqueTargetPathAddsCounter;
var
  Folder: string;
begin
  Folder := TPath.Combine(FRoot, 'export');
  ForceDirectories(Folder);
  Assert.AreEqual(TPath.Combine(Folder, 'a.txt'),
    TItemTreeBatch.UniqueTargetPath(Folder, 'a.txt'));
  TFile.WriteAllText(TPath.Combine(Folder, 'a.txt'), 'x');
  Assert.AreEqual(TPath.Combine(Folder, 'a (2).txt'),
    TItemTreeBatch.UniqueTargetPath(Folder, 'a.txt'));
  TFile.WriteAllText(TPath.Combine(Folder, 'a (2).txt'), 'x');
  Assert.AreEqual(TPath.Combine(Folder, 'a (3).txt'),
    TItemTreeBatch.UniqueTargetPath(Folder, 'a.txt'));
end;

procedure TItemTreeBatchTests.PlanDeleteSkipsBlockedTargets;
var
  A, B: TItem;
  FA: unit_Item.TFile;
  NB: TLabEntry;
  Plan: TBatchPlan;
begin
  A := NewItem('A', 0);
  B := NewItem('B', 0);
  FA := NewFile(A, 'fa');
  Model.Items.AddNote('nb', 'body', Model.User.Id, B);
  NB := B.Entries[0];
  Assert.IsTrue(Model.Signatures.SignItem(A, Model.User, Password, 'Synthetic', ''));

  Plan := FBatch.PlanDelete([TBatchTarget.ForItem(A), TBatchTarget.ForItem(B),
    TBatchTarget.ForFile(FA, A), TBatchTarget.ForNote(NB, B)]);

  Assert.AreEqual<NativeInt>(2, Length(Plan.Targets));
  Assert.AreEqual('I:' + IntToStr(B.Id), Plan.Targets[0].Key);
  Assert.AreEqual('N:' + IntToStr(NB.Id), Plan.Targets[1].Key);
  Assert.AreEqual<NativeInt>(2, Length(Plan.Skipped));
  Assert.IsTrue(Plan.Skipped[0].Reason.StartsWith('Cannot delete item "A"'));
  Assert.AreEqual('Its item is signed.', Plan.Skipped[1].Reason);
end;

procedure TItemTreeBatchTests.PlanDeleteSeesFreshSignature;
var
  B: TItem;
  FB: unit_Item.TFile;
  Plan: TBatchPlan;
begin
  B := NewItem('B', 0);
  FB := NewFile(B, 'fb');
  FVM.LoadItemData;
  Assert.IsTrue(Model.Signatures.SignItem(B, Model.User, Password, 'Synthetic', ''));

  Plan := FBatch.PlanDelete([TBatchTarget.ForFile(FB, B)]);

  Assert.AreEqual<NativeInt>(0, Length(Plan.Targets));
  Assert.AreEqual<NativeInt>(1, Length(Plan.Skipped));
  Assert.AreEqual('Its item is signed.', Plan.Skipped[0].Reason);
end;

procedure TItemTreeBatchTests.ExecuteDeleteProcessesAllKinds;
var
  X, Y, Y1, Z: TItem;
  FZ: unit_Item.TFile;
  NZ: TLabEntry;
  FzId: Int64;
  NzId, XId, YId, Y1Id: Integer;
  FzPath: string;
  Result: TBatchResult;
  Fresh: TObjectManager;
begin
  X := NewItem('X', 0);
  Y := NewItem('Y', 0);
  Y1 := NewItem('Y1', Y.Id);
  Z := NewItem('Z', 0);
  FZ := NewFile(Z, 'fz');
  Model.Items.AddNote('nz', 'body', Model.User.Id, Z);
  NZ := Z.Entries[0];
  FzId := FZ.Id;
  NzId := NZ.Id;
  XId := X.Id;
  YId := Y.Id;
  Y1Id := Y1.Id;
  FzPath := StringReplace(Model.GetFileName(FzId), '\', '/', [rfReplaceAll]);
  Model.Storage.WriteBytes(FzPath, TBytes.Create(1, 2, 3));
  Assert.IsTrue(Model.Storage.Exists(FzPath));

  Result := FBatch.ExecuteDelete(FBatch.PlanDelete([TBatchTarget.ForItem(X),
    TBatchTarget.ForItem(Y), TBatchTarget.ForFile(FZ, Z),
    TBatchTarget.ForNote(NZ, Z)]));

  Assert.AreEqual<NativeInt>(4, Length(Result.Done));
  Assert.AreEqual<NativeInt>(0, Length(Result.Failed));
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.IsTrue(Fresh.Find<TItem>(XId).IsDeleted);
    Assert.IsTrue(Fresh.Find<TItem>(YId).IsDeleted);
    Assert.IsTrue(Fresh.Find<TItem>(Y1Id).IsDeleted);
    Assert.IsNull(Fresh.Find<unit_Item.TFile>(FzId));
    Assert.IsNull(Fresh.Find<TLabEntry>(NzId));
  finally
    Fresh.Free;
  end;
  Assert.IsFalse(Model.Storage.Exists(FzPath));
end;

procedure TItemTreeBatchTests.DeleteItemWithSelectedOwnFile;
var
  X: TItem;
  FX: unit_Item.TFile;
  Result: TBatchResult;
begin
  X := NewItem('X', 0);
  FX := NewFile(X, 'fx');

  Result := FBatch.ExecuteDelete(FBatch.PlanDelete(FBatch.TopLevel(
    [TBatchTarget.ForItem(X), TBatchTarget.ForFile(FX, X)])));

  Assert.AreEqual<NativeInt>(1, Length(Result.Done));
  Assert.AreEqual<NativeInt>(0, Length(Result.Failed));
end;

procedure TItemTreeBatchTests.DeletedTargetsKeepKeyAndTitle;
var
  Z: TItem;
  FZ: unit_Item.TFile;
  NZ: TLabEntry;
  TargetFile, TargetNote: TBatchTarget;
  FileKey, FileTitle, NoteKey, NoteTitle: string;
  Result: TBatchResult;
begin
  Z := NewItem('Z', 0);
  FZ := NewFile(Z, 'fz');
  Model.Items.AddNote('nz', 'body', Model.User.Id, Z);
  NZ := Z.Entries[0];
  TargetFile := TBatchTarget.ForFile(FZ, Z);
  TargetNote := TBatchTarget.ForNote(NZ, Z);
  FileKey := TargetFile.Key;
  FileTitle := TargetFile.Title;
  NoteKey := TargetNote.Key;
  NoteTitle := TargetNote.Title;

  Result := FBatch.ExecuteDelete(FBatch.PlanDelete([TargetFile, TargetNote]));

  Assert.AreEqual<NativeInt>(2, Length(Result.Done));
  Assert.AreEqual(FileKey, Result.Done[0].Key);
  Assert.AreEqual(FileTitle, Result.Done[0].Title);
  Assert.AreEqual(NoteKey, Result.Done[1].Key);
  Assert.AreEqual(NoteTitle, Result.Done[1].Title);
end;

procedure TItemTreeBatchTests.ExecuteDeleteContinuesAfterFailure;
var
  P, Q: TItem;
  Plan: TBatchPlan;
  Result: TBatchResult;
begin
  P := NewItem('P', 0);
  Q := NewItem('Q', 0);
  Plan := FBatch.PlanDelete([TBatchTarget.ForItem(P), TBatchTarget.ForItem(Q)]);
  Assert.AreEqual<NativeInt>(2, Length(Plan.Targets));
  Assert.IsTrue(Model.Signatures.SignItem(P, Model.User, Password, 'Synthetic', ''));

  Result := FBatch.ExecuteDelete(Plan);

  Assert.AreEqual<NativeInt>(1, Length(Result.Failed));
  Assert.AreEqual('I:' + IntToStr(P.Id), Result.Failed[0].Target.Key);
  Assert.AreEqual('Cannot delete item "P": it is signed.',
    Result.Failed[0].Reason);
  Assert.AreEqual<NativeInt>(1, Length(Result.Done));
  Assert.AreEqual('I:' + IntToStr(Q.Id), Result.Done[0].Key);
end;

procedure TItemTreeBatchTests.DescendantCountCountsSubtrees;
var
  X, Y, Y1, Y2: TItem;
begin
  X := NewItem('X', 0);
  Y := NewItem('Y', 0);
  Y1 := NewItem('Y1', Y.Id);
  Y2 := NewItem('Y2', Y.Id);
  NewItem('Y11', Y1.Id);
  Assert.IsNotNull(Y2);
  Assert.AreEqual(3, FBatch.DescendantCount(FBatch.PlanDelete(
    [TBatchTarget.ForItem(X), TBatchTarget.ForItem(Y)])));
end;

procedure TItemTreeBatchTests.PlanMoveItemsSkipsFolderSignedAndCycle;
var
  Fo, S, A, A1, B: TItem;
  Plan: TBatchPlan;
begin
  Fo := NewItem('Fo', 0, TItemLevel.Folder);
  S := NewItem('S', 0);
  A := NewItem('A', 0);
  A1 := NewItem('A1', A.Id);
  B := NewItem('B', 0);
  Assert.IsTrue(Model.Signatures.SignItem(S, Model.User, Password, 'Synthetic', ''));

  Plan := FBatch.PlanMoveItemsTo(FBatch.PlanMoveItems([TBatchTarget.ForItem(Fo),
    TBatchTarget.ForItem(S), TBatchTarget.ForItem(A), TBatchTarget.ForItem(B)]),
    A1.Id);

  Assert.AreEqual<NativeInt>(1, Length(Plan.Targets));
  Assert.AreEqual('I:' + IntToStr(B.Id), Plan.Targets[0].Key);
  Assert.AreEqual<NativeInt>(3, Length(Plan.Skipped));
  Assert.AreEqual('Folders cannot be moved here.', Plan.Skipped[0].Reason);
  Assert.AreEqual('The item is signed.', Plan.Skipped[1].Reason);
  Assert.AreEqual('The target is inside this item.', Plan.Skipped[2].Reason);
end;

procedure TItemTreeBatchTests.ExecuteMoveItemsReparents;
var
  P, B, C: TItem;
  BId, CId, PId: Integer;
  Result: TBatchResult;
  Fresh: TObjectManager;
begin
  P := NewItem('P', 0);
  B := NewItem('B', 0);
  C := NewItem('C', 0);
  PId := P.Id;
  BId := B.Id;
  CId := C.Id;

  Result := FBatch.ExecuteMoveItems(FBatch.PlanMoveItemsTo(FBatch.PlanMoveItems(
    [TBatchTarget.ForItem(B), TBatchTarget.ForItem(C)]), PId), PId);

  Assert.AreEqual<NativeInt>(2, Length(Result.Done));
  Assert.AreEqual<NativeInt>(0, Length(Result.Failed));
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(PId, Fresh.Find<TItem>(BId).Parent);
    Assert.AreEqual(PId, Fresh.Find<TItem>(CId).Parent);
  finally
    Fresh.Free;
  end;
end;

procedure TItemTreeBatchTests.ExecuteMoveFilesMovesBytes;
var
  A, B: TItem;
  F1, F2: unit_Item.TFile;
  Old1, Old2, New1, New2: string;
  Result: TBatchResult;
begin
  A := NewItem('A', 0);
  B := NewItem('B', 0);
  F1 := NewFile(A, 'f1');
  F2 := NewFile(A, 'f2');
  Old1 := StringReplace(Model.GetFileName(F1.Id), '\', '/', [rfReplaceAll]);
  Old2 := StringReplace(Model.GetFileName(F2.Id), '\', '/', [rfReplaceAll]);
  Model.Storage.WriteBytes(Old1, TBytes.Create(1, 2, 3));
  Model.Storage.WriteBytes(Old2, TBytes.Create(4, 5, 6));

  Result := FBatch.ExecuteMoveFiles(FBatch.PlanMoveFiles(
    [TBatchTarget.ForFile(F1, A), TBatchTarget.ForFile(F2, A)], B.Id), B.Id);

  Assert.AreEqual<NativeInt>(2, Length(Result.Done));
  Assert.AreEqual<NativeInt>(0, Length(Result.Failed));
  New1 := StringReplace(Model.GetFileName(F1.Id), '\', '/', [rfReplaceAll]);
  New2 := StringReplace(Model.GetFileName(F2.Id), '\', '/', [rfReplaceAll]);
  Assert.AreNotEqual(Old1, New1);
  Assert.IsTrue(Model.Storage.Exists(New1));
  Assert.IsTrue(Model.Storage.Exists(New2));
  Assert.IsFalse(Model.Storage.Exists(Old1));
  Assert.IsFalse(Model.Storage.Exists(Old2));
end;

procedure TItemTreeBatchTests.PlanMoveFilesSkipsSameItem;
var
  B: TItem;
  FB: unit_Item.TFile;
  Plan: TBatchPlan;
begin
  B := NewItem('B', 0);
  FB := NewFile(B, 'fb');
  Plan := FBatch.PlanMoveFiles([TBatchTarget.ForFile(FB, B)], B.Id);
  Assert.AreEqual<NativeInt>(0, Length(Plan.Targets));
  Assert.AreEqual<NativeInt>(1, Length(Plan.Skipped));
  Assert.AreEqual('The file is already there.', Plan.Skipped[0].Reason);
end;

procedure TItemTreeBatchTests.ExecuteMoveFilesRollsBackOnStorageFailure;
var
  A, B: TItem;
  F1, F2: unit_Item.TFile;
  Id1, Id2: Int64;
  AId, BId: Integer;
  Old2, New2: string;
  Result: TBatchResult;
  Fresh: TObjectManager;
begin
  A := NewItem('A', 0);
  B := NewItem('B', 0);
  AId := A.Id;
  BId := B.Id;
  F1 := NewFile(A, 'f1');
  F2 := NewFile(A, 'f2');
  Id1 := F1.Id;
  Id2 := F2.Id;
  Old2 := StringReplace(Model.GetFileName(Id2), '\', '/', [rfReplaceAll]);
  Model.Storage.WriteBytes(Old2, TBytes.Create(4, 5, 6));

  Result := FBatch.ExecuteMoveFiles(FBatch.PlanMoveFiles(
    [TBatchTarget.ForFile(F1, A), TBatchTarget.ForFile(F2, A)], BId), BId);

  Assert.AreEqual<NativeInt>(1, Length(Result.Failed), 'failed count');
  Assert.AreEqual('F:' + IntToStr(Id1), Result.Failed[0].Target.Key);
  Assert.IsFalse(Result.Failed[0].Reason.Contains('Rollback failed'), Result.Failed[0].Reason);
  Assert.IsTrue(Result.Failed[0].Reason <> '');
  Assert.AreEqual<NativeInt>(1, Length(Result.Done), 'done count');
  Assert.AreEqual('F:' + IntToStr(Id2), Result.Done[0].Key);
  Fresh := TObjectManager.Create(FNotebook.Connection);
  try
    Assert.AreEqual(AId, Fresh.Find<unit_Item.TFile>(Id1).Item.Id);
    Assert.AreEqual(BId, Fresh.Find<unit_Item.TFile>(Id2).Item.Id);
  finally
    Fresh.Free;
  end;
  New2 := StringReplace(Model.GetFileName(Id2), '\', '/', [rfReplaceAll]);
  Assert.IsTrue(Model.Storage.Exists(New2));
  Assert.IsFalse(Model.Storage.Exists(Old2));
end;

procedure TItemTreeBatchTests.TagCountsAndAssignAll;
var
  A, B, C: TItem;
  Tag: TTag;
  TagId: Integer;
  Ids: TArray<Integer>;
begin
  Tag := Model.Tags.AddTag('Synthetic', '#0000FF', Model.User.Id);
  TagId := Tag.Id;
  A := NewItem('A', 0);
  B := NewItem('B', 0);
  C := NewItem('C', 0);
  Ids := TArray<Integer>.Create(A.Id, B.Id, C.Id);
  Model.Tags.AssignTag(A.Id, TagId);
  Assert.AreEqual(1, FBatch.CountTagged(Ids, TagId));
  FBatch.AssignTagToAll(Ids, TagId);
  Assert.AreEqual(3, FBatch.CountTagged(Ids, TagId));
  FBatch.UnassignTagFromAll(Ids, TagId);
  Assert.AreEqual(0, FBatch.CountTagged(Ids, TagId));
end;

procedure TItemTreeBatchTests.ExportSameTitleTwice;
var
  A, B: TItem;
  F1, F2: unit_Item.TFile;
  Folder: string;
  Result: TBatchResult;
begin
  A := NewItem('A', 0);
  B := NewItem('B', 0);
  F1 := NewFile(A, 'data');
  F2 := NewFile(B, 'data');
  Model.Storage.WriteBytes(StringReplace(Model.GetFileName(F1.Id), '\', '/',
    [rfReplaceAll]), TBytes.Create(1, 2, 3));
  Model.Storage.WriteBytes(StringReplace(Model.GetFileName(F2.Id), '\', '/',
    [rfReplaceAll]), TBytes.Create(4, 5, 6));
  Folder := TPath.Combine(TPath.GetTempPath, 'ELN-Export-' + TGUID.NewGuid.ToString);
  ForceDirectories(Folder);
  try
    System.IOUtils.TFile.WriteAllBytes(TPath.Combine(Folder, 'data.txt'),
      TBytes.Create(9, 9));

    Result := FBatch.ExecuteExportFiles(
      [TBatchTarget.ForFile(F1, A), TBatchTarget.ForFile(F2, B)], Folder);

    Assert.AreEqual<NativeInt>(2, Length(Result.Done));
    Assert.AreEqual<NativeInt>(0, Length(Result.Failed));
    Assert.AreEqual<TBytes>(TBytes.Create(9, 9),
      System.IOUtils.TFile.ReadAllBytes(TPath.Combine(Folder, 'data.txt')));
    Assert.AreEqual<TBytes>(TBytes.Create(1, 2, 3),
      System.IOUtils.TFile.ReadAllBytes(TPath.Combine(Folder, 'data (2).txt')));
    Assert.AreEqual<TBytes>(TBytes.Create(4, 5, 6),
      System.IOUtils.TFile.ReadAllBytes(TPath.Combine(Folder, 'data (3).txt')));
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TItemTreeBatchTests);

end.
