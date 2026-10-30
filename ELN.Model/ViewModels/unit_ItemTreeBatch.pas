unit unit_ItemTreeBatch;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  unit_DataModel, unit_ItemTreeVM, unit_Item, unit_LabEntry, unit_FileType,
  unit_FilePaths;

type
  TBatchTargetKind = (btItem, btFile, btNote);
  TBatchKinds = set of TBatchTargetKind;
  TBatchOperation = (boDelete, boExtract, boMove, boTags, boExport, boDrag);

  TBatchTarget = record
    Kind: TBatchTargetKind;
    Item: TItem;
    AFile: unit_Item.TFile;
    Entry: TLabEntry;
    Id: Int64;
    Name: string;
    function Title: string;
    function Key: string;
    class function ForItem(AItem: TItem): TBatchTarget; static;
    class function ForFile(AFile: unit_Item.TFile; AOwner: TItem): TBatchTarget; static;
    class function ForNote(AEntry: TLabEntry; AOwner: TItem): TBatchTarget; static;
  end;

  TBatchSkip = record
    Target: TBatchTarget;
    Reason: string;
  end;

  TBatchPlan = record
    Targets: TArray<TBatchTarget>;
    Skipped: TArray<TBatchSkip>;
  end;

  TBatchResult = record
    Done: TArray<TBatchTarget>;
    Failed: TArray<TBatchSkip>;
  end;

  TItemTreeBatch = class
  private
    FModel: TDataModel;
    FVM: TItemTreeVM;
    function BuildPlan(const Targets: TArray<TBatchTarget>;
      const Prior: TArray<TBatchSkip>;
      const ReasonOf: TFunc<TBatchTarget, string>): TBatchPlan;
    function RunEach(const Plan: TBatchPlan;
      const Step: TFunc<TBatchTarget, string>): TBatchResult;
  public
    constructor Create(AModel: TDataModel; AVM: TItemTreeVM);
    class function KindsOf(const Targets: TArray<TBatchTarget>): TBatchKinds; static;
    class function Allows(Op: TBatchOperation;
      const Targets: TArray<TBatchTarget>): Boolean; static;
    class function FormatSkips(const Skips: TArray<TBatchSkip>;
      MaxLines: Integer = 20): string; static;
    class function UniqueTargetPath(const Folder, FileName: string): string; static;
    function TopLevel(const Targets: TArray<TBatchTarget>): TArray<TBatchTarget>;
    function PlanDelete(const Targets: TArray<TBatchTarget>): TBatchPlan;
    function ExecuteDelete(const Plan: TBatchPlan): TBatchResult;
    function DescendantCount(const Plan: TBatchPlan): Integer;
    function PlanMoveItems(const Targets: TArray<TBatchTarget>): TBatchPlan;
    function PlanMoveItemsTo(const Plan: TBatchPlan; NewParentId: Integer): TBatchPlan;
    function ExecuteMoveItems(const Plan: TBatchPlan; NewParentId: Integer): TBatchResult;
    function PlanMoveFiles(const Targets: TArray<TBatchTarget>;
      NewItemId: Integer): TBatchPlan;
    function ExecuteMoveFiles(const Plan: TBatchPlan; NewItemId: Integer): TBatchResult;
    function PlanTags(const Targets: TArray<TBatchTarget>): TBatchPlan;
    function CountTagged(const ItemIds: TArray<Integer>; TagId: Integer): Integer;
    procedure AssignTagToAll(const ItemIds: TArray<Integer>; TagId: Integer);
    procedure UnassignTagFromAll(const ItemIds: TArray<Integer>; TagId: Integer);
    function ExecuteExportFiles(const Targets: TArray<TBatchTarget>;
      const Folder: string): TBatchResult;
    class function PreviewStoragePath(ItemId: Integer; FileId: Int64): string; static;
  end;

function SubtreeItemIds(Manager: TObjectManager; Root: TItem): TArray<Integer>;

implementation

uses
  System.IOUtils, Aurelius.Criteria.Linq, unit_SignatureModel, unit_ItemModel,
  unit_ItemTypes;

function SubtreeItemIds(Manager: TObjectManager; Root: TItem): TArray<Integer>;
var
  All: TList<TItem>;
  Ids: TList<Integer>;
  Index: Integer;
  Candidate: TItem;
begin
  Ids := TList<Integer>.Create;
  try
    Ids.Add(Root.Id);
    All := Manager.Find<TItem>
      .Where((Linq['ProjectID'] = Root.ProjectID) and (Linq['IsDeleted'] = False))
      .List;
    try
      Index := 0;
      while Index < Ids.Count do
      begin
        for Candidate in All do
          if (Candidate.Parent = Ids[Index]) and not Ids.Contains(Candidate.Id) then
            Ids.Add(Candidate.Id);
        Inc(Index);
      end;
    finally
      All.Free;
    end;
    Result := Ids.ToArray;
  finally
    Ids.Free;
  end;
end;

function TBatchTarget.Title: string;
begin
  Result := Name;
end;

function TBatchTarget.Key: string;
begin
  case Kind of
    btItem: Result := 'I:' + IntToStr(Id);
    btFile: Result := 'F:' + IntToStr(Id);
  else
    Result := 'N:' + IntToStr(Id);
  end;
end;

class function TBatchTarget.ForItem(AItem: TItem): TBatchTarget;
begin
  Result := Default(TBatchTarget);
  Result.Kind := btItem;
  Result.Item := AItem;
  Result.Id := AItem.Id;
  Result.Name := AItem.Title;
end;

class function TBatchTarget.ForFile(AFile: unit_Item.TFile; AOwner: TItem): TBatchTarget;
begin
  Result := Default(TBatchTarget);
  Result.Kind := btFile;
  Result.Item := AOwner;
  Result.AFile := AFile;
  Result.Id := AFile.Id;
  Result.Name := AFile.Title + AFile.FileType.Ext;
end;

class function TBatchTarget.ForNote(AEntry: TLabEntry; AOwner: TItem): TBatchTarget;
begin
  Result := Default(TBatchTarget);
  Result.Kind := btNote;
  Result.Item := AOwner;
  Result.Entry := AEntry;
  Result.Id := AEntry.Id;
  Result.Name := AEntry.Title;
end;

constructor TItemTreeBatch.Create(AModel: TDataModel; AVM: TItemTreeVM);
begin
  inherited Create;
  FModel := AModel;
  FVM := AVM;
end;

class function TItemTreeBatch.KindsOf(const Targets: TArray<TBatchTarget>): TBatchKinds;
var
  Target: TBatchTarget;
begin
  Result := [];
  for Target in Targets do
    Include(Result, Target.Kind);
end;

class function TItemTreeBatch.Allows(Op: TBatchOperation;
  const Targets: TArray<TBatchTarget>): Boolean;
var
  Kinds: TBatchKinds;
  Target: TBatchTarget;
begin
  Result := False;
  if Length(Targets) = 0 then
    Exit;
  Kinds := KindsOf(Targets);
  case Op of
    boDelete:
      Result := True;
    boExtract, boExport:
      Result := Kinds = [btFile];
    boMove:
      Result := (Kinds = [btItem]) or (Kinds = [btFile]);
    boTags:
      Result := Kinds = [btItem];
    boDrag:
    begin
      Result := Kinds = [btItem];
      if Result then
        for Target in Targets do
          if Target.Item.Parent <> 0 then
            Exit(False);
    end;
  end;
end;

class function TItemTreeBatch.FormatSkips(const Skips: TArray<TBatchSkip>;
  MaxLines: Integer): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    for I := 0 to High(Skips) do
    begin
      if I >= MaxLines then
      begin
        Lines.Add('...and ' + IntToStr(Length(Skips) - MaxLines) + ' more');
        Break;
      end;
      Lines.Add('"' + Skips[I].Target.Title + '": ' + Skips[I].Reason);
    end;
    Result := Lines.Text.TrimRight([#13, #10]);
  finally
    Lines.Free;
  end;
end;

class function TItemTreeBatch.UniqueTargetPath(const Folder, FileName: string): string;
var
  BaseName, Ext: string;
  Counter: Integer;
begin
  Result := TPath.Combine(Folder, FileName);
  if not TFile.Exists(Result) then
    Exit;
  BaseName := TPath.GetFileNameWithoutExtension(FileName);
  Ext := TPath.GetExtension(FileName);
  Counter := 2;
  repeat
    Result := TPath.Combine(Folder, Format('%s (%d)%s', [BaseName, Counter, Ext]));
    Inc(Counter);
  until not TFile.Exists(Result);
end;

function TItemTreeBatch.TopLevel(const Targets: TArray<TBatchTarget>): TArray<TBatchTarget>;
var
  ItemIds: TList<Integer>;
  Kept: TList<TBatchTarget>;
  Target: TBatchTarget;
  Cursor: TItem;
  Covered: Boolean;
  Steps: Integer;
begin
  ItemIds := TList<Integer>.Create;
  Kept := TList<TBatchTarget>.Create;
  try
    for Target in Targets do
      if Target.Kind = btItem then
        ItemIds.Add(Target.Item.Id);
    for Target in Targets do
    begin
      Covered := False;
      Cursor := nil;
      if Target.Kind <> btItem then
        Cursor := Target.Item
      else if Target.Item.Parent <> 0 then
        Cursor := FModel.Manager.Find<TItem>(Target.Item.Parent);
      Steps := 0;
      while Assigned(Cursor) and (Steps < 10000) do
      begin
        if ItemIds.Contains(Cursor.Id) then
        begin
          Covered := True;
          Break;
        end;
        if Cursor.Parent = 0 then
          Break;
        Cursor := FModel.Manager.Find<TItem>(Cursor.Parent);
        Inc(Steps);
      end;
      if not Covered then
        Kept.Add(Target);
    end;
    Result := Kept.ToArray;
  finally
    Kept.Free;
    ItemIds.Free;
  end;
end;

function TItemTreeBatch.BuildPlan(const Targets: TArray<TBatchTarget>;
  const Prior: TArray<TBatchSkip>;
  const ReasonOf: TFunc<TBatchTarget, string>): TBatchPlan;
var
  Accepted: TList<TBatchTarget>;
  Skipped: TList<TBatchSkip>;
  Target: TBatchTarget;
  Skip: TBatchSkip;
  Reason: string;
begin
  Accepted := TList<TBatchTarget>.Create;
  Skipped := TList<TBatchSkip>.Create;
  try
    Skipped.AddRange(Prior);
    for Target in Targets do
    begin
      Reason := ReasonOf(Target);
      if Reason = '' then
        Accepted.Add(Target)
      else
      begin
        Skip.Target := Target;
        Skip.Reason := Reason;
        Skipped.Add(Skip);
      end;
    end;
    Result.Targets := Accepted.ToArray;
    Result.Skipped := Skipped.ToArray;
  finally
    Skipped.Free;
    Accepted.Free;
  end;
end;

function TItemTreeBatch.RunEach(const Plan: TBatchPlan;
  const Step: TFunc<TBatchTarget, string>): TBatchResult;
var
  Done: TList<TBatchTarget>;
  Failed: TList<TBatchSkip>;
  Target: TBatchTarget;
  FailText: string;
  Failure: TBatchSkip;
begin
  Done := TList<TBatchTarget>.Create;
  Failed := TList<TBatchSkip>.Create;
  try
    for Target in Plan.Targets do
    begin
      try
        FailText := Step(Target);
      except
        on EAbort do
          raise;
        on E: Exception do
          FailText := E.Message;
      end;
      if FailText = '' then
        Done.Add(Target)
      else
      begin
        Failure.Target := Target;
        Failure.Reason := FailText;
        Failed.Add(Failure);
      end;
    end;
    Result.Done := Done.ToArray;
    Result.Failed := Failed.ToArray;
  finally
    Failed.Free;
    Done.Free;
  end;
end;

function TItemTreeBatch.PlanDelete(const Targets: TArray<TBatchTarget>): TBatchPlan;
begin
  Result := BuildPlan(Targets, nil,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      if not FModel.Access.CanWrite(FModel.Manager, FModel.User, Target.Item.ProjectID) then
        Result := 'You cannot change this project.'
      else if Target.Kind = btItem then
        Result := FModel.Items.FindDeleteBlocker(Target.Item)
      else if IsItemSignedCheck(FModel.Manager, Target.Item.Id) then
        Result := 'Its item is signed.';
    end);
end;

function TItemTreeBatch.ExecuteDelete(const Plan: TBatchPlan): TBatchResult;
begin
  Result := RunEach(Plan,
    function(Target: TBatchTarget): string
    var
      Owner: TItem;
      FileId: Int64;
      StoragePath: string;
      Blocker: string;
    begin
      Result := '';
      Owner := Target.Item;
      case Target.Kind of
        btItem:
          if not FModel.Items.SoftDeleteItemTree(Target.Item, FModel.User.Id) then
          begin
            Blocker := FModel.Items.FindDeleteBlocker(Target.Item);
            if Blocker <> '' then
              Result := Blocker
            else
              Result := 'The item was changed by another session. Refresh and try again.';
          end;
        btFile:
        begin
          FileId := Target.AFile.Id;
          StoragePath := StringReplace(FModel.GetFileName(FileId), '\', '/',
            [rfReplaceAll]);
          if FModel.Items.RemoveFile(Target.AFile, Owner, FModel.User.Id) then
          begin
            try
              FModel.Storage.DeleteFile(StoragePath);
            except
              on EAbort do
                raise;
              on E: Exception do
                Result := 'The file record was deleted, but its bytes remain at ' +
                  StoragePath + ': ' + E.Message;
            end;
            try
              FModel.Storage.DeleteFile(PreviewStoragePath(Owner.Id, FileId));
            except
              on EAbort do
                raise;
              on Exception do
                ;
            end;
          end
          else
            Result := 'The file was not deleted. It may be signed or changed by another session.';
        end;
      else
        if not FVM.DeleteEntry(Target.Entry, Owner) then
          Result := 'The note was not deleted. It may be signed or changed by another session.';
      end;
    end);
end;

function TItemTreeBatch.DescendantCount(const Plan: TBatchPlan): Integer;
var
  Target: TBatchTarget;
begin
  Result := 0;
  for Target in Plan.Targets do
    if Target.Kind = btItem then
      Inc(Result, Length(SubtreeItemIds(FModel.Manager, Target.Item)) - 1);
end;

class function TItemTreeBatch.PreviewStoragePath(ItemId: Integer; FileId: Int64): string;
begin
  Result := PreviewRelativePath(ItemId, FileId);
end;

function TItemTreeBatch.PlanMoveItems(const Targets: TArray<TBatchTarget>): TBatchPlan;
begin
  Result := BuildPlan(Targets, nil,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      if not FModel.Access.CanWrite(FModel.Manager, FModel.User, Target.Item.ProjectID) then
        Result := 'You cannot change this project.'
      else if Target.Item.Level = TItemLevel.Folder then
        Result := 'Folders cannot be moved here.'
      else if IsItemSignedCheck(FModel.Manager, Target.Item.Id) then
        Result := 'The item is signed.';
    end);
end;

function TItemTreeBatch.PlanMoveItemsTo(const Plan: TBatchPlan;
  NewParentId: Integer): TBatchPlan;
begin
  Result := BuildPlan(Plan.Targets, Plan.Skipped,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      if TArray.IndexOf<Integer>(SubtreeItemIds(FModel.Manager, Target.Item),
        NewParentId) >= 0 then
        Result := 'The target is inside this item.'
      else if Target.Item.Parent = NewParentId then
        Result := 'The item is already there.';
    end);
end;

function TItemTreeBatch.ExecuteMoveItems(const Plan: TBatchPlan;
  NewParentId: Integer): TBatchResult;
begin
  Result := RunEach(Plan,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      if not FVM.ReparentItem(Target.Item, NewParentId) then
        Result := 'The item could not be moved. It may be signed or changed by another session.';
    end);
end;

function TItemTreeBatch.PlanMoveFiles(const Targets: TArray<TBatchTarget>;
  NewItemId: Integer): TBatchPlan;
begin
  Result := BuildPlan(Targets, nil,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      if not FModel.Access.CanWrite(FModel.Manager, FModel.User, Target.Item.ProjectID) then
        Result := 'You cannot change this project.'
      else if IsItemSignedCheck(FModel.Manager, Target.Item.Id) then
        Result := 'Its item is signed.'
      else if Target.Item.Id = NewItemId then
        Result := 'The file is already there.';
    end);
end;

function TItemTreeBatch.ExecuteMoveFiles(const Plan: TBatchPlan;
  NewItemId: Integer): TBatchResult;
begin
  Result := RunEach(Plan,
    function(Target: TBatchTarget): string
    var
      OldItemId: Integer;
      Current: unit_Item.TFile;
      OldPath, NewPath: string;
      RolledBack: Boolean;
    begin
      Result := '';
      OldItemId := Target.Item.Id;
      OldPath := StringReplace(FModel.GetFileName(Target.AFile.Id), '\', '/',
        [rfReplaceAll]);
      Current := FModel.Manager.Find<unit_Item.TFile>(Target.AFile.Id);
      if not (Assigned(Current) and
        FModel.Items.MoveFile(Current, NewItemId, FModel.User.Id)) then
        Exit('The file could not be moved. It may be changed by another session.');
      NewPath := StringReplace(FModel.GetFileName(Target.AFile.Id), '\', '/',
        [rfReplaceAll]);
      try
        if OldPath <> NewPath then
          FModel.Storage.MoveFile(OldPath, NewPath);
      except
        on EAbort do
          raise;
        on E: Exception do
        begin
          try
            Current := FModel.Manager.Find<unit_Item.TFile>(Target.AFile.Id);
            RolledBack := Assigned(Current) and
              FModel.Items.MoveFile(Current, OldItemId, FModel.User.Id);
          except
            RolledBack := False;
          end;
          if RolledBack then
            Result := E.Message
          else
            Result := E.Message + Format(' Rollback failed: file %d row points to item %d; bytes remain at %s.',
              [Target.AFile.Id, NewItemId, OldPath]);
        end;
      end;
    end);
end;

function TItemTreeBatch.PlanTags(const Targets: TArray<TBatchTarget>): TBatchPlan;
begin
  Result := BuildPlan(Targets, nil,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      if not FModel.Access.CanWrite(FModel.Manager, FModel.User, Target.Item.ProjectID) then
        Result := 'You cannot change this project.';
    end);
end;

function TItemTreeBatch.CountTagged(const ItemIds: TArray<Integer>;
  TagId: Integer): Integer;
var
  ItemId: Integer;
begin
  Result := 0;
  for ItemId in ItemIds do
    if FModel.Tags.IsTagAssigned(ItemId, TagId) then
      Inc(Result);
end;

procedure TItemTreeBatch.AssignTagToAll(const ItemIds: TArray<Integer>;
  TagId: Integer);
var
  ItemId: Integer;
begin
  for ItemId in ItemIds do
    FModel.Tags.AssignTag(ItemId, TagId);
end;

procedure TItemTreeBatch.UnassignTagFromAll(const ItemIds: TArray<Integer>;
  TagId: Integer);
var
  ItemId: Integer;
begin
  for ItemId in ItemIds do
    FModel.Tags.UnassignTag(ItemId, TagId);
end;

function TItemTreeBatch.ExecuteExportFiles(const Targets: TArray<TBatchTarget>;
  const Folder: string): TBatchResult;
var
  Plan: TBatchPlan;
begin
  Plan := Default(TBatchPlan);
  Plan.Targets := Targets;
  Result := RunEach(Plan,
    function(Target: TBatchTarget): string
    begin
      Result := '';
      FModel.Storage.CopyOut(
        StringReplace(FModel.GetFileName(Target.AFile.Id), '\', '/', [rfReplaceAll]),
        UniqueTargetPath(Folder, Target.AFile.Title + Target.AFile.FileType.Ext));
    end);
end;

end.
