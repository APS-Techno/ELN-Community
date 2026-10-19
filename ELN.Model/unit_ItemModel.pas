unit unit_ItemModel;

interface
uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  System.Classes,
  System.Generics.Collections,
  unit_TELNModel,
  unit_ItemTypes,
  unit_Item,
  unit_ActionType,
  unit_Equipment,
  unit_LabEntry,
  unit_Protocol,
  unit_FileRelocator,
  unit_NotebookStorage,
  unit_FileType,
  unit_ValueType,
  unit_ELNDB_Dictionary,
  unit_AuditLog,
  unit_ValueSource;

type

  TItemModel = class(TELNModel)
    private
      FDic: TItemDictionary;
      FManager: TObjectManager;
      FProjectID, FFolderID: integer;
      procedure CollectLiveSubtree(Item: TItem; AList: TList<TItem>);
      function NewValue(ValueType: TValueType; RecType: TRecType;
        AValue: double; UserId: Integer; Item: TItem; Tol: double;
        const Description: string; const Source: TValueSourceInfo): TValue;
      procedure DiscardValue(Item: TItem; Val: TValue);
      procedure UpdateReaderValue(Val: TValue; ValueType: TValueType;
        RecType: TRecType; AValue: double; UserId: Integer; Item: TItem;
        Tol: double; const Description: string; const Source: TValueSourceInfo;
        const AnalysisSnapshot: string);

   protected
      function GetDataSet: TAureliusDataset; override;
      function GetItemsList: TItems;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;
      procedure AssignProject(const ProjectId, FolderID: integer);
      property List: TItems read GetItemsList;
      property Manager: TObjectManager read FManager;

      function AddItem(const IType: TItemType;
                                  Title: string;
                                  Level: TItemLevel = TItemLevel.Proc;
                                 Parent: integer = 0;
                            Description: string = '';
                                  AType: TActionType = nil;
                             AEquipment: TEquipment = nil;
                                 UserId: Integer = 0;
                             Properties: string = ''): TItem;


      procedure AddNote(const Title, Content: string; UserId: Integer; var Item: TItem);
      procedure AddProtocol(const Title: string;
                            ProtocolType: TProtocolType;
                            TemplateId: Integer;
                            UserId: Integer;
                            var Item: TItem;
                            const FormData: string = '');

      function AddFile(const FType: TFileType;
                       Title: string; UserId: Integer; var  Item: TItem): TFile;

      procedure AddValue(ValueType: TValueType; RecType: TRecType;
        AValue: double; UserId: Integer; var Item: TItem;
        Tol: double; const Description: string;
        const Source: TValueSourceInfo); overload;
      procedure AddValue(ValueType: TValueType; RecType: TRecType;
        AValue: double; UserId: Integer; var Item: TItem;
        Tol: double; const Description: string;
        const Source: TValueSourceInfo;
        const AnalysisSnapshot: string); overload;
      procedure PutReaderValue(ValueType: TValueType; RecType: TRecType;
        AValue: double; UserId: Integer; var Item: TItem;
        Tol: double; const Description: string;
        const Source: TValueSourceInfo; const AnalysisSnapshot: string;
        Occurrence: Integer);
      function ReaderValuesOf(Item: TItem; FileId: Int64): TArray<TValue>;
      procedure RemoveValue(Val: TValue; var Item: TItem; UserId: Integer);
      function RemoveFile(AFile: TFile; var Item: TItem; UserId: Integer): Boolean;
      function RemoveEntry(Entry: TLabEntry; var Item: TItem; UserId: Integer): Boolean;

      function GetItem(const ID:integer):TItem;
      function GetItemForEntry(EntryId: Integer): TItem;
      function UpdateItem(Item: TItem; UserId: Integer): Boolean;
      // Scalar edits only. Uses Item.Version as the optimistic baseline.
      // Commits metadata, audit and attachment moves together, or rolls back.
      // Refreshes Item after the attempt, but never flushes unrelated drafts.
      // False means signed/stale refusal; other failures raise.
      function UpdateItemDurable(Item: TItem; UserId: Integer;
        const Relocator: IFileRelocator): Boolean;
      function UpdateEntry(Entry: TLabEntry; UserId: Integer): Boolean;
      function UpdateFile(AFile: TFile; UserId: Integer): Boolean;
      function MoveFile(AFile: TFile; NewParentId, UserId: Integer): Boolean;
      function ReorderItems(Items: TItems): Boolean;
      function MoveProc(Proc: TItem; NewProjectID, NewFolderID, UserID: Integer;
  const Relocator: IFileRelocator = nil): Boolean;

      function IsItemEmpty(Item: TItem): Boolean;
      function DeleteItem(Item: TItem; UserId: Integer): Boolean;
      function SoftDeleteItemTree(Item: TItem; UserId: Integer): Boolean;
      function FindDeleteBlocker(Item: TItem): string;
      function GetRecentItems(UserId: Integer; Count: Integer = 20): TItems; overload;
      function GetRecentItems(UserId: Integer; DateFrom: TDateTime; Count: Integer = 20): TItems; overload;
      procedure EvictCache;
  end;

implementation

uses
  System.Generics.Defaults,
  unit_AuditHelper,
  unit_AnalysisSettingsModel,
  Aurelius.Commands.Exceptions,
  unit_ConflictHandler,
  unit_SignatureModel,
  unit_DataModel,
  unit_Project,
  unit_TimeHelper,
  unit_Hypothesis,
  unit_HypothesisGuard;


function TItemModel.AddFile(const FType: TFileType; Title: string;
  UserId: Integer; var Item: TItem): TFile;
var
  ManagedFileType: TFileType;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit(nil);

  ManagedFileType := FManager.Find<TFileType>(FType.Id);

  Result := TFile.Create;
  Result.FileType := ManagedFileType;
  Result.Title   := Title;
  Result.CreatedDate := UTCNow;
  Result.CreatedBy := UserId;
  Result.Item := Item;

  Item.Files.Add(Result);

  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit(nil);
  RecordAudit(FManager, aetFile, Result.Id, aoCreate, UserId,
    'Added file "' + Title + '" to item "' + Item.Title + '"');
end;

function TItemModel.AddItem(const IType: TItemType;
                                  Title: string;
                                  Level: TItemLevel;
                                 Parent: integer;
                            Description: string;
                                  AType: TActionType;
                             AEquipment: TEquipment;
                                 UserId: Integer;
                             Properties: string): TItem;
begin
  Result := TItem.Create;
  Result.Title := Title;
  Result.Description := Description;
  Result.Type_ := IType;
  Result.Level := Level;
  Result.CreatedDate := UTCNow;
  Result.CreatedBy := UserId;
  Result.ProjectID := FProjectID;
  Result.FolderID := FFolderID;
  Result.Parent := Parent;
  Result.Expanded := True;
  Result.Properties := Properties;

  if Assigned(AType) then
    Result.ActionType := FManager.Find<TActionType>(AType.Id);

  if Assigned(AEquipment) then
    Result.Equipment := FManager.Find<TEquipment>(AEquipment.Id);

  FManager.Save(Result);
  FManager.Flush;
  RecordAudit(FManager, aetItem, Result.Id, aoCreate, UserId,
    'Created item "' + Title + '"');
  FManager.Evict(Result);
end;

procedure TItemModel.AddNote(const Title, Content: string; UserId: Integer; var Item: TItem);
var
  Protocol: TProtocol;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Protocol := TProtocol.Create;
  Protocol.Title := Title;
  Protocol.FormData := Content;
  Protocol.ProtocolType := ptNote;
  Protocol.ValidationStatus := vsDraft;
  Protocol.CreatedDate := UTCNow;
  Protocol.CreatedBy := UserId;

  Item.Entries.Add(Protocol);
  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetNote, Protocol.Id, aoCreate, UserId,
    'Added note "' + Title + '" to item "' + Item.Title + '"');
end;

procedure TItemModel.AddProtocol(const Title: string;
                                 ProtocolType: TProtocolType;
                                 TemplateId: Integer;
                                 UserId: Integer;
                                 var Item: TItem;
                                 const FormData: string = '');
var
  Protocol: TProtocol;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Protocol := TProtocol.Create;
  Protocol.Title := Title;
  Protocol.ProtocolType := ProtocolType;
  Protocol.TemplateId := TemplateId;
  Protocol.FormData := FormData;
  Protocol.ValidationStatus := vsDraft;
  Protocol.CreatedDate := UTCNow;
  Protocol.CreatedBy := UserId;

  if Assigned(Item.ActionType) and Assigned(Item.ActionType.Equipment) then
  begin
    Protocol.EquipModel := Item.ActionType.Equipment.Model;
    Protocol.EquipManufacturer := Item.ActionType.Equipment.Manufacturer;
    Protocol.EquipLocation := Item.ActionType.Equipment.Location;
  end;

  Item.Entries.Add(Protocol);
  FManager.Update(Item);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetProtocol, Protocol.Id, aoCreate, UserId,
    'Added protocol "' + Title + '" to item "' + Item.Title + '"');
end;

procedure TItemModel.AssignProject(const ProjectID, FolderID: integer);
begin
  FProjectID := ProjectID;
  FFolderID := FolderID;
  if FFolderID < 0 then
    FFolderID := 0;
end;

constructor TItemModel.Create;
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TItemDictionary.Create;
end;

destructor TItemModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TItemModel.NewValue(ValueType: TValueType; RecType: TRecType;
  AValue: double; UserId: Integer; Item: TItem; Tol: double;
  const Description: string; const Source: TValueSourceInfo): TValue;
begin
  Result := TValue.Create;
  Result.ValueType := FManager.Find<TValueType>(ValueType.Id);
  Result.RecType := RecType;
  Result.Value := AValue;
  Result.Tol := Tol;
  Result.Description := Description;
  Result.CreatedDate := UTCNow;
  Result.CreatedBy := UserId;
  Result.Item := Item;
  ApplySource(Result, Source);

  Item.Values.Add(Result);
  FManager.Update(Item);
end;

procedure TItemModel.AddValue(ValueType: TValueType; RecType: TRecType;
  AValue: double; UserId: Integer; var Item: TItem;
  Tol: double; const Description: string; const Source: TValueSourceInfo);
var
  Val: TValue;
begin
  ValidateSource(Source);
  if Source.Kind = vskDerived then
    raise EArgumentException.Create('Derived values are stored with their inputs through TDerivedValueModel');
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Val := NewValue(ValueType, RecType, AValue, UserId, Item, Tol, Description,
    Source);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetValue, Val.Id, aoCreate, UserId,
    'Added value to item "' + Item.Title + '"');
end;

procedure TItemModel.AddValue(ValueType: TValueType; RecType: TRecType;
  AValue: double; UserId: Integer; var Item: TItem;
  Tol: double; const Description: string; const Source: TValueSourceInfo;
  const AnalysisSnapshot: string);
var
  Val: TValue;
  Analysis: TAnalysisSettingsModel;
  Trans: IDBTransaction;
begin
  ValidateSource(Source);
  if (Source.Kind <> vskReader) or (Source.ReaderId = '') then
    raise EArgumentException.Create('An analysis snapshot requires a Reader source');
  TAnalysisSettingsModel.CompleteSnapshot(AnalysisSnapshot,
    Source.ReaderId, Source.KeyName, Source.FileId, 0);
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Val := nil;
  Analysis := TAnalysisSettingsModel.Create(FManager);
  try
    Trans := FManager.Connection.BeginTransaction;
    try
      Val := NewValue(ValueType, RecType, AValue, UserId, Item, Tol, Description,
        Source);
      if not TConflictHandler.SafeFlush(FManager) then
      begin
        Trans.Rollback;
        Exit;
      end;
      Analysis.SaveSnapshot(Source.ReaderId, Val.Id,
        TAnalysisSettingsModel.CompleteSnapshot(AnalysisSnapshot,
          Source.ReaderId, Source.KeyName, Source.FileId, Val.Id));
      RecordAudit(FManager, aetValue, Val.Id, aoCreate, UserId,
        'Added value to item "' + Item.Title + '"');
      Trans.Commit;
    except
      try
        Trans.Rollback;
      except
      end;
      DiscardValue(Item, Val);
      raise;
    end;
  finally
    Analysis.Free;
  end;
end;

procedure TItemModel.DiscardValue(Item: TItem; Val: TValue);
begin
  if Val = nil then
    Exit;
  Item.Values.Remove(Val);
  try
    FManager.Evict(Val);
  except
    Val.Free;
    Exit;
  end;
  FManager.AddOwnership(Val);
end;

function TItemModel.ReaderValuesOf(Item: TItem; FileId: Int64): TArray<TValue>;
var
  Val: TValue;
  Found: TList<TValue>;
begin
  Found := TList<TValue>.Create;
  try
    for Val in Item.Values do
      if (Val.EffectiveSourceKind = vskReader) and Val.SourceFileId.HasValue and
        (Val.SourceFileId.Value = FileId) then
        Found.Add(Val);
    Found.Sort(TComparer<TValue>.Construct(
      function(const A, B: TValue): Integer
      begin
        Result := A.Id - B.Id;
      end));
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function SameSource(const A, B: TValueSourceInfo): Boolean;
begin
  Result := (A.Kind = B.Kind) and (A.FileId = B.FileId) and
    (A.ReaderId = B.ReaderId) and (A.ReaderVersion = B.ReaderVersion) and
    (A.KeyName = B.KeyName) and (A.Note = B.Note) and
    (A.ReaderUnits.HasValue = B.ReaderUnits.HasValue) and
    (not A.ReaderUnits.HasValue or (A.ReaderUnits.Value = B.ReaderUnits.Value)) and
    (A.ConversionFactor.HasValue = B.ConversionFactor.HasValue) and
    (not A.ConversionFactor.HasValue or
      (A.ConversionFactor.Value = B.ConversionFactor.Value));
end;

procedure TItemModel.PutReaderValue(ValueType: TValueType; RecType: TRecType;
  AValue: double; UserId: Integer; var Item: TItem; Tol: double;
  const Description: string; const Source: TValueSourceInfo;
  const AnalysisSnapshot: string; Occurrence: Integer);
var
  Candidate, Existing: TValue;
  Seen: Integer;
begin
  if Source.Kind <> vskReader then
    raise EArgumentException.Create('PutReaderValue requires a Reader source');
  Existing := nil;
  Seen := 0;
  for Candidate in ReaderValuesOf(Item, Source.FileId) do
    if Candidate.KeyName = Source.KeyName then
    begin
      if Seen = Occurrence then
      begin
        Existing := Candidate;
        Break;
      end;
      Inc(Seen);
    end;
  if Existing <> nil then
    UpdateReaderValue(Existing, ValueType, RecType, AValue, UserId, Item, Tol,
      Description, Source, AnalysisSnapshot)
  else if AnalysisSnapshot = '' then
    AddValue(ValueType, RecType, AValue, UserId, Item, Tol, Description, Source)
  else
    AddValue(ValueType, RecType, AValue, UserId, Item, Tol, Description, Source,
      AnalysisSnapshot);
end;

procedure TItemModel.UpdateReaderValue(Val: TValue; ValueType: TValueType;
  RecType: TRecType; AValue: double; UserId: Integer; Item: TItem; Tol: double;
  const Description: string; const Source: TValueSourceInfo;
  const AnalysisSnapshot: string);
var
  Snapshot, Stored, OldReaderId: string;
  Applied: TValueSourceInfo;
  Analysis: TAnalysisSettingsModel;
  Trans: IDBTransaction;
begin
  ValidateSource(Source);
  if AnalysisSnapshot = '' then
    Snapshot := ''
  else
    Snapshot := TAnalysisSettingsModel.CompleteSnapshot(AnalysisSnapshot,
      Source.ReaderId, Source.KeyName, Source.FileId, Val.Id);
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  Applied := Source;
  if Trim(Applied.ReaderVersion) = '' then
    Applied.ReaderVersion := 'unknown';
  OldReaderId := Val.ReaderId;
  Analysis := TAnalysisSettingsModel.Create(FManager);
  try
    Analysis.LoadSnapshot(Val, Stored);
    if Assigned(Val.ValueType) and (Val.ValueType.Id = ValueType.Id) and
      (Val.RecType = RecType) and (Val.Value = AValue) and (Val.Tol = Tol) and
      (Val.Description = Description) and SameSource(ReadSource(Val), Applied) and
      (Stored = Snapshot) then
      Exit;

    Trans := FManager.Connection.BeginTransaction;
    try
      Val.ValueType := FManager.Find<TValueType>(ValueType.Id);
      Val.RecType := RecType;
      Val.Value := AValue;
      Val.Tol := Tol;
      Val.Description := Description;
      ApplySource(Val, Source);
      Val.ModifiedDate := UTCNow;
      Val.ModifiedBy := UserId;
      if not TConflictHandler.SafeFlush(FManager) then
      begin
        Trans.Rollback;
        Exit;
      end;
      if OldReaderId <> Source.ReaderId then
        Analysis.DeleteForValue(OldReaderId, Val.Id);
      if Snapshot = '' then
        Analysis.DeleteForValue(Source.ReaderId, Val.Id)
      else
        Analysis.SaveSnapshot(Source.ReaderId, Val.Id, Snapshot);
      RecordAudit(FManager, aetValue, Val.Id, aoUpdate, UserId,
        'Updated value of item "' + Item.Title + '" from its source file');
      Trans.Commit;
    except
      try
        Trans.Rollback;
      except
      end;
      FManager.Refresh(Val);
      raise;
    end;
  finally
    Analysis.Free;
  end;
end;

procedure TItemModel.RemoveValue(Val: TValue; var Item: TItem; UserId: Integer);
var
  ValId: Integer;
  ReaderId: string;
  Analysis: TAnalysisSettingsModel;
begin
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  ValId := Val.Id;
  ReaderId := Val.ReaderId;
  Item.Values.Remove(Val);
  FManager.Remove(Val);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetValue, ValId, aoDelete, UserId,
    'Removed value from item "' + Item.Title + '"');
  Analysis := TAnalysisSettingsModel.Create(FManager);
  try
    Analysis.DeleteForValue(ReaderId, ValId);
  finally
    Analysis.Free;
  end;
end;

function TItemModel.RemoveFile(AFile: TFile; var Item: TItem; UserId: Integer): Boolean;
var
  FileId: Int64;
  FileTitle: string;
  Extracted: TArray<TValue>;
  ValueIds: TArray<Integer>;
  ReaderIds: TArray<string>;
  I: Integer;
  Analysis: TAnalysisSettingsModel;
begin
  Result := False;
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  FileId := AFile.Id;
  FileTitle := AFile.Title;
  Extracted := ReaderValuesOf(Item, FileId);
  SetLength(ValueIds, Length(Extracted));
  SetLength(ReaderIds, Length(Extracted));
  for I := 0 to High(Extracted) do
  begin
    ValueIds[I] := Extracted[I].Id;
    ReaderIds[I] := Extracted[I].ReaderId;
    Item.Values.Remove(Extracted[I]);
    FManager.Remove(Extracted[I]);
  end;
  Item.Files.Remove(AFile);
  FManager.Remove(AFile);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, aetFile, FileId, aoDelete, UserId,
    'Removed file "' + FileTitle + '" from item "' + Item.Title + '"');
  for I := 0 to High(ValueIds) do
    RecordAudit(FManager, aetValue, ValueIds[I], aoDelete, UserId,
      'Removed value extracted from file "' + FileTitle + '" from item "' +
      Item.Title + '"');
  Analysis := TAnalysisSettingsModel.Create(FManager);
  try
    Analysis.DeleteForFile(FileId);
    for I := 0 to High(ValueIds) do
      Analysis.DeleteForValue(ReaderIds[I], ValueIds[I]);
  finally
    Analysis.Free;
  end;
  if Assigned(Model) then
    Model.ViewerStates.DeleteForFile(FileId);
  Result := True;
end;

function TItemModel.RemoveEntry(Entry: TLabEntry; var Item: TItem; UserId: Integer): Boolean;
var
  EntryId: Integer;
  EntryTitle: string;
  EntityType: TAuditEntityType;
begin
  Result := False;
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit;

  EntryId := Entry.Id;
  if Entry is TProtocol then
  begin
    EntryTitle := TProtocol(Entry).Title;
    if TProtocol(Entry).ProtocolType.HasValue and
       (TProtocol(Entry).ProtocolType.Value = ptNote) then
      EntityType := aetNote
    else
      EntityType := aetProtocol;
  end
  else
  begin
    EntryTitle := '';
    EntityType := aetProtocol;
  end;
  Item.Entries.Remove(Entry);
  FManager.Remove(Entry);
  if not TConflictHandler.SafeFlush(FManager) then
    Exit;
  RecordAudit(FManager, EntityType, EntryId, aoDelete, UserId,
    'Removed entry "' + EntryTitle + '" from item "' + Item.Title + '"');
  Result := True;
end;

function TItemModel.GetDataSet: TAureliusDataset;
begin
  if not Assigned(FDataSet) then
    OpenDataSet;

  Result := FDataSet;
end;

function TItemModel.GetItem(const ID: integer): TItem;
begin
  Result := FManager.Find<TItem>(ID);
end;

function TItemModel.GetItemForEntry(EntryId: Integer): TItem;
begin
  Result := FManager.Find<TItem>
    .CreateAlias('Entries', 'e')
    .Where(Linq['e.Id'] = EntryId)
    .UniqueResult;
end;

function TItemModel.GetItemsList: TItems;
var
  Criteria: TCriteria;
begin
  Criteria := FManager.Find<TItem>
    .Where((FDic.ProjectID = FProjectID) and (FDic.IsDeleted = False));
  // New root writes use zero; legacy non-positive locations remain visible.
  if FFolderID = 0 then
    Criteria.Where(FDic.FolderID <= 0)
  else
    Criteria.Where(FDic.FolderID = FFolderID);
  Result := Criteria.OrderBy('SortOrder').OrderBy('Id').List<TItem>;
end;

function TItemModel.UpdateItem(Item: TItem; UserId: Integer): Boolean;
var
  ReadManager: TObjectManager;
  Persisted: TItem;
begin
  // A split title change followed by Flush cannot compensate attachment moves.
  ReadManager := TObjectManager.Create(FManager.Connection);
  try
    Persisted := ReadManager.Find<TItem>(Item.Id);
    if Assigned(Persisted) and (Persisted.Title <> Item.Title) then
    begin
      Item.Title := Persisted.Title;
      raise EInvalidOperation.Create('Use UpdateItemDurable to change an item title.');
    end;
  finally
    TConflictHandler.FreeOperationManager(ReadManager);
  end;
  if IsItemSignedCheck(FManager, Item.Id) then
    Exit(False);

  Item.ModifiedDate := UTCNow;
  Item.ModifiedBy := UserId;
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoUpdate, UserId,
      'Updated item "' + Item.Title + '"');
end;

function TItemModel.UpdateItemDurable(Item: TItem; UserId: Integer;
  const Relocator: IFileRelocator): Boolean;
var
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  Current: TItem;
  Project: TProject;
  Attachment: TFile;
  Moves: TFileMoveJournal;
  OldFolder: string;
  Committed: Boolean;
begin
  Result := False;
  if Item = nil then
    raise EArgumentNilException.Create('Item');
  Operation := TObjectManager.Create(FManager.Connection);
  Moves := TFileMoveJournal.Create(Relocator);
  try
    Transaction := TConflictHandler.BeginOperationTransaction(FManager);
    Committed := False;
    try
      try
        Current := Operation.Find<TItem>(Item.Id);
        if (Current = nil) or (Current.Version <> Item.Version) or
          IsItemSignedCheck(Operation, Item.Id) then
          Exit(False);
        OldFolder := Current.FolderName;
        Current.Title := Item.Title;
        Current.Description := Item.Description;
        Current.Properties := Item.Properties;
        Current.Type_ := Item.Type_;
        Current.Level := Item.Level;
        if Item.ActionType = nil then
          Current.ActionType := nil
        else
          Current.ActionType := Operation.Find<TActionType>(Item.ActionType.Id);
        if Item.Equipment = nil then
          Current.Equipment := nil
        else
          Current.Equipment := Operation.Find<TEquipment>(Item.Equipment.Id);
        Current.ModifiedDate := UTCNow;
        Current.ModifiedBy := UserId;
        if OldFolder <> Current.FolderName then
        begin
          Project := Operation.Find<TProject>(Current.ProjectID);
          if Project = nil then
            raise EInvalidOperation.Create('The item project no longer exists.');
          for Attachment in Current.Files do
            Moves.Add(BuildItemFileRemotePath(Project.FileFolder, OldFolder, Attachment.FullName),
              BuildItemFileRemotePath(Project.FileFolder, Current.FolderName, Attachment.FullName));
        end;
        Moves.Execute;
        Operation.Flush;
        RecordAudit(Operation, aetItem, Current.Id, aoUpdate, UserId,
          'Updated item "' + Current.Title + '"');
        Transaction.Commit;
        Committed := True;
        Result := True;
      finally
        if not Committed then
        begin
          try
            Transaction.Rollback;
          finally
            Moves.Rollback;
          end;
        end;
      end;
    except
      on E: EVersionedConcurrencyControl do
      begin
        if Assigned(TConflictHandler.OnConflict) then
          TConflictHandler.OnConflict(E.Message);
        Result := False;
      end;
    end;
  finally
    try
      // Only the submitted item loses rejected edits. The operation manager
      // owns all failed writes and audit entries, so no later host Flush can
      // replay them.
      FManager.Refresh(Item);
    finally
      Moves.Free;
      TConflictHandler.FreeOperationManager(Operation);
    end;
  end;
end;

function TItemModel.UpdateEntry(Entry: TLabEntry; UserId: Integer): Boolean;
var
  ParentItem: TItem;
  EntityType: TAuditEntityType;
begin
  Result := False;

  ParentItem := GetItemForEntry(Entry.Id);
  if not Assigned(ParentItem) then
    Exit;
  if IsItemSignedCheck(FManager, ParentItem.Id) then
    Exit;

  Entry.ModifiedDate := UTCNow;
  Entry.ModifiedBy := UserId;
  FManager.Update(Entry);
  Result := TConflictHandler.SafeFlush(FManager);
  if not Result then
    Exit;

  if (Entry is TProtocol)
     and TProtocol(Entry).ProtocolType.HasValue
     and (TProtocol(Entry).ProtocolType.Value = ptNote) then
    EntityType := aetNote
  else
    EntityType := aetProtocol;

  RecordAudit(FManager, EntityType, Entry.Id, aoUpdate, UserId,
    'Updated entry "' + Entry.Title + '" on item "' + ParentItem.Title + '"');
end;

function TItemModel.UpdateFile(AFile: TFile; UserId: Integer): Boolean;
begin
  AFile.ModifiedDate := UTCNow;
  AFile.ModifiedBy := UserId;
  FManager.Update(AFile);
  Result := TConflictHandler.SafeFlush(FManager);
end;

function TItemModel.MoveFile(AFile: TFile; NewParentId, UserId: Integer): Boolean;
var
  OldParent, NewParent: TItem;
begin
  OldParent := AFile.Item;
  NewParent := FManager.Find<TItem>(NewParentId);
  if not Assigned(NewParent) then
    Exit(False);

  // Change FK directly — do NOT manipulate proxy collections
  // (CascadeAllRemoveOrphan on TItem.Files would delete the file as orphan)
  AFile.Item := NewParent;
  AFile.ModifiedDate := UTCNow;
  AFile.ModifiedBy := UserId;
  FManager.Update(AFile);
  Result := TConflictHandler.SafeFlush(FManager);

  if Result then
  begin
    RecordAudit(FManager, aetFile, AFile.Id, aoUpdate, UserId,
      'Moved file "' + AFile.Title + '" to "' + NewParent.Title + '"');
    FManager.Evict(AFile);
    FManager.Evict(OldParent);
    FManager.Evict(NewParent);
  end;
end;

function TItemModel.ReorderItems(Items: TItems): Boolean;
var
  I: Integer;
begin
  for I := 0 to Items.Count - 1 do
    Items[I].SortOrder := I * 10;
  Result := TConflictHandler.SafeFlush(FManager);
end;

procedure TItemModel.OpenDataSet;
begin
  FDataSet.SetSourceCriteria(FManager.Find<TItem>);
  FDataSet.Open;
end;

function TItemModel.IsItemEmpty(Item: TItem): Boolean;
var
  Children: TList<TItem>;
begin
  Children := FManager.Find<TItem>
    .Where((FDic.ParentID = Item.Id) and (FDic.IsDeleted = False))
    .List;
  try
    if Children.Count > 0 then
      Exit(False);
  finally
    Children.Free;
  end;

  Result := (Item.Entries.Count = 0) and
            (Item.Files.Count = 0) and
            (Item.Values.Count = 0);
end;

procedure TItemModel.CollectLiveSubtree(Item: TItem; AList: TList<TItem>);
var
  Children: TList<TItem>;
  Child: TItem;
begin
  if AList.Contains(Item) then
    Exit;
  AList.Add(Item);
  Children := FManager.Find<TItem>
    .Where((FDic.ParentID = Item.Id) and (FDic.IsDeleted = False))
    .List;
  try
    for Child in Children do
      CollectLiveSubtree(Child, AList);
  finally
    Children.Free;
  end;
end;

function TItemModel.FindDeleteBlocker(Item: TItem): string;
const
  StatusWord: array[Boolean] of string = ('accepted', 'in review');
var
  Subtree: TList<TItem>;
  I: TItem;
  HypId: Integer;
  HStatus: THypothesisStatus;
  Why: string;
begin
  Result := '';
  Subtree := TList<TItem>.Create;
  try
    CollectLiveSubtree(Item, Subtree);
    for I in Subtree do
    begin
      if IsItemSignedCheck(FManager, I.Id) then
        Why := 'is signed'
      else if IsItemCitedByLockedHypothesis(FManager, I.Id, HypId, HStatus) then
        Why := Format('is cited by hypothesis #%d (%s)',
          [HypId, StatusWord[HStatus = hsInReview]])
      else
        Continue;
      if I = Item then
        Exit(Format('Cannot delete item "%s": it %s.', [Item.Title, Why]))
      else
        Exit(Format('Cannot delete item "%s": "%s" inside it %s.',
          [Item.Title, I.Title, Why]));
    end;
  finally
    Subtree.Free;
  end;
end;

function TItemModel.DeleteItem(Item: TItem; UserId: Integer): Boolean;
begin
  if FindDeleteBlocker(Item) <> '' then
    Exit(False);

  Item.IsDeleted := True;
  Item.DeletedDate := UTCNow;
  Item.DeletedBy := UserId;
  FManager.Update(Item);
  Result := TConflictHandler.SafeFlush(FManager);
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoDelete, UserId,
      'Moved item "' + Item.Title + '" to recycle bin');
end;

function TItemModel.SoftDeleteItemTree(Item: TItem; UserId: Integer): Boolean;
var
  Subtree: TList<TItem>;
  I: TItem;
  Trans: IDBTransaction;
begin
  // Check the whole subtree before marking any node deleted; signed children
  // must refuse the entire operation.
  if FindDeleteBlocker(Item) <> '' then
    Exit(False);
  if Item.IsDeleted then
    Exit(True);

  Subtree := TList<TItem>.Create;
  try
    CollectLiveSubtree(Item, Subtree);
    // One transaction for the whole subtree: without it, a mid-batch version
    // conflict on one descendant (EVersionedConcurrencyControl) can commit the
    // UPDATEs that ran before it and leave the subtree partially soft-deleted,
    // exactly the "nothing is deleted" guarantee this method exists to give.
    Trans := FManager.Connection.BeginTransaction;
    try
      for I in Subtree do
      begin
        I.IsDeleted := True;
        I.DeletedDate := UTCNow;
        I.DeletedBy := UserId;
        FManager.Update(I);
      end;
      Result := TConflictHandler.SafeFlush(FManager);
      if Result then
        Trans.Commit
      else
      begin
        Trans.Rollback;
        for I in Subtree do
          FManager.Refresh(I);
      end;
    except
      Trans.Rollback;
      for I in Subtree do
        FManager.Refresh(I);
      raise;
    end;
  finally
    Subtree.Free;
  end;
  if Result then
    RecordAudit(FManager, aetItem, Item.Id, aoDelete, UserId,
      'Moved item "' + Item.Title + '" and descendants to recycle bin');
end;

function TItemModel.MoveProc(Proc: TItem; NewProjectID, NewFolderID, UserID: Integer;
  const Relocator: IFileRelocator): Boolean;
var
  Operation: TObjectManager;
  Transaction: IDBTransaction;
  AllItems: TItems;
  ToMove: TList<TItem>;
  Item, Current, Cached: TItem;
  OldProject, NewProject: TProject;
  Attachment: TFile;
  Moves: TFileMoveJournal;
  Committed, Stale: Boolean;

  procedure CollectDescendants(ParentID: Integer);
  var
    Child: TItem;
  begin
    for Child in AllItems do
      if (Child.Parent = ParentID) and not ToMove.Contains(Child) then
      begin
        ToMove.Add(Child);
        CollectDescendants(Child.Id);
      end;
  end;

begin
  Result := False;
  if Proc = nil then
    Exit;
  if NewFolderID < 0 then
    NewFolderID := 0;
  Operation := TObjectManager.Create(FManager.Connection);
  AllItems := nil;
  ToMove := TList<TItem>.Create;
  Moves := TFileMoveJournal.Create(Relocator);
  try
    Transaction := TConflictHandler.BeginOperationTransaction(FManager);
    Committed := False;
    try
      try
        Current := Operation.Find<TItem>(Proc.Id);
        if Current = nil then
          Exit(False);
        ToMove.Add(Current);
        AllItems := Operation.Find<TItem>
          .Where(FDic.ProjectID = Current.ProjectID).List;
        CollectDescendants(Current.Id);
        Stale := Current.Version <> Proc.Version;
        for Item in ToMove do
        begin
          Cached := FManager.FindCached<TItem>(Item.Id);
          if Assigned(Cached) then
          begin
            if FManager.HasChanges(Cached) then
              raise EInvalidOperation.Create('Save or cancel item edits before moving the subtree.');
            Stale := Stale or (Cached.Version <> Item.Version);
          end;
          if IsItemSignedCheck(Operation, Item.Id) then
            Exit(False);
        end;
        if Stale then
          Exit(False);
        OldProject := Operation.Find<TProject>(Current.ProjectID);
        NewProject := Operation.Find<TProject>(NewProjectID);
        if (OldProject = nil) or (NewProject = nil) then
          raise EInvalidOperation.Create('The source or destination project no longer exists.');
        if (NewFolderID <> 0) and (NewProject.GetFolder(NewFolderID) = nil) then
          raise EInvalidOperation.Create('The destination folder is not in the destination project.');
        for Item in ToMove do
        begin
          if Item.ProjectID <> NewProjectID then
            for Attachment in Item.Files do
              Moves.Add(BuildItemFileRemotePath(OldProject.FileFolder, Item.FolderName, Attachment.FullName),
                BuildItemFileRemotePath(NewProject.FileFolder, Item.FolderName, Attachment.FullName));
          Item.ProjectID := NewProjectID;
          Item.FolderID := NewFolderID;
        end;
        Moves.Execute;
        Operation.Flush;
        RecordAudit(Operation, aetItem, Current.Id, aoUpdate, UserID,
          Format('Moved Proc "%s" to project %d, folder %d',
            [Current.Title, NewProjectID, NewFolderID]));
        Transaction.Commit;
        Committed := True;
        Result := True;
      finally
        if not Committed then
        begin
          try
            Transaction.Rollback;
          finally
            Moves.Rollback;
          end;
        end;
      end;
    except
      on E: EVersionedConcurrencyControl do
      begin
        if Assigned(TConflictHandler.OnConflict) then
          TConflictHandler.OnConflict(E.Message);
        Result := False;
      end;
    end;
  finally
    try
      // Refresh the whole affected cache only after commit/rollback. Never
      // clear the host manager or include its unrelated pending edits.
      for Item in ToMove do
      begin
        Cached := FManager.FindCached<TItem>(Item.Id);
        if Assigned(Cached) and not FManager.HasChanges(Cached) then
          FManager.Refresh(Cached);
      end;
    finally
      Moves.Free;
      ToMove.Free;
      AllItems.Free;
      TConflictHandler.FreeOperationManager(Operation);
    end;
  end;
end;

function TItemModel.GetRecentItems(UserId: Integer; Count: Integer): TItems;
begin
  Result := FManager.Find<TItem>
    .Where(FDic.IsDeleted = False)
    .Where(FDic.Level = Ord(TItemLevel.Proc))
    .Where(FDic.CreatedBy = UserId)
    .OrderBy(FDic.ModifiedDate, False)
    .Take(Count)
    .List;
end;

function TItemModel.GetRecentItems(UserId: Integer; DateFrom: TDateTime;
  Count: Integer): TItems;
var
  Criteria: TCriteria;
begin
  Criteria := FManager.Find<TItem>
    .Where(FDic.IsDeleted = False)
    .Where(FDic.Level = Ord(TItemLevel.Proc));

  if UserId > 0 then
    Criteria.Where(FDic.CreatedBy = UserId);

  if DateFrom > 0 then
    Criteria.Where(FDic.ModifiedDate >= DateFrom);

  Result := Criteria
    .OrderBy(FDic.ModifiedDate, False)
    .Take(Count)
    .List<TItem>;
end;

procedure TItemModel.EvictCache;
var
  Items: TItems;
  Item: TItem;
  Entry: TLabEntry;
  AFile: TFile;
  Val: TValue;
begin
  Items := GetItemsList;
  try
    for Item in Items do
    begin
      for Entry in Item.Entries do
        FManager.Evict(Entry);
      for AFile in Item.Files do
        FManager.Evict(AFile);
      for Val in Item.Values do
        FManager.Evict(Val);
      FManager.Evict(Item);
    end;
  finally
    Items.Free;
  end;
end;

end.
