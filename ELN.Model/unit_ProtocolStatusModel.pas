unit unit_ProtocolStatusModel;

interface

uses
  SysUtils,
  System.Generics.Collections,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  unit_TELNModel,
  unit_Protocol,
  unit_ProtocolStatusChange,
  unit_User,
  unit_ProjectAccessPolicy,
  unit_ELNDB_Dictionary;

type
  EProtocolTransitionError = class(Exception);
  EProtocolTransitionConflict = class(EProtocolTransitionError);

  TProtocolStatusModel = class(TELNModel)
  private
    FDic: TProtocolStatusChangeDictionary;
    FProtocolDic: TProtocolDictionary;
    FItemDic: TItemDictionary;
    FManager: TObjectManager;
    FAccess: IProjectAccessPolicy;
  public
    constructor Create(Manager: TObjectManager; const Access: IProjectAccessPolicy);
    destructor Destroy; override;
    procedure OpenDataSet; override;

    function GetAllowedTransitions(CurrentStatus: TValidationStatus;
      AUser: TUser; AProjectId, AAuthorId: Integer): TArray<TValidationStatus>;
    function CanTransition(CurrentStatus, NewStatus: TValidationStatus;
      AUser: TUser; AProjectId, AAuthorId: Integer): Boolean;
    function TryGetAccessContext(AProtocolId: Integer;
      out AProjectId, AAuthorId: Integer): Boolean;
    function Transition(AUser: TUser; AProtocolId, AExpectedVersion: Integer;
      AFrom, ATo: TValidationStatus; const AComment: string): Integer;
    function IsProtocolReadOnly(Status: TValidationStatus): Boolean;
    // Initial or imported history only. Existing human transitions use Transition.
    procedure RecordStatusChange(ProtocolId: Integer;
      OldStatus, NewStatus: TValidationStatus;
      UserId: Integer; const Comment: string);
    function GetStatusHistory(ProtocolId: Integer): TProtocolStatusChanges;
    function GetProtocolsByStatus(Status: TValidationStatus; UserId: Integer = -1): TList<TProtocol>;
  end;

implementation

uses
  System.Variants,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  unit_Item,
  unit_LabEntry,
  unit_TimeHelper,
  Aurelius.Drivers.Interfaces,
  Aurelius.Commands.Exceptions,
  unit_SignatureModel,
  unit_AuditLog,
  unit_AuditHelper;

type
  TProtocolAccessContext = record
    ItemId, ProjectId, AuthorId: Integer;
    ParentDeleted: Boolean;
  end;

function ReadProtocolAccessContext(AManager: TObjectManager;
  AProtocolId: Integer; out AContext: TProtocolAccessContext): Boolean;
var
  Rows: TObjectList<TCriteriaResult>;
begin
  AContext := Default(TProtocolAccessContext);
  Rows := AManager.Find<TItem>
    .CreateAlias('Entries', 'e')
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('Id').As_('ItemId'))
      .Add(TProjections.Prop('ProjectID').As_('ProjectId'))
      .Add(TProjections.Prop('IsDeleted').As_('Deleted'))
      .Add(TProjections.Prop('e.CreatedBy').As_('AuthorId')))
    .Where(Linq['e.Id'] = AProtocolId).ListValues;
  try
    Result := Rows.Count = 1;
    if not Result then
      Exit;
    AContext.ItemId := Integer(Rows[0].Values['ItemId']);
    AContext.ProjectId := Integer(Rows[0].Values['ProjectId']);
    AContext.ParentDeleted := VarIsNull(Rows[0].Values['Deleted']) or
      Boolean(Rows[0].Values['Deleted']);
    if not VarIsNull(Rows[0].Values['AuthorId']) then
      AContext.AuthorId := Integer(Rows[0].Values['AuthorId']);
  finally
    Rows.Free;
  end;
end;

function ProtocolTransitionAllowed(AManager: TObjectManager;
  const AAccess: IProjectAccessPolicy; AUser: TUser;
  AProjectId, AAuthorId: Integer; AFrom, ATo: TValidationStatus): Boolean;
begin
  case AFrom of
    vsDraft:
      Result := (ATo = vsInReview) and
        AAccess.CanWrite(AManager, AUser, AProjectId);
    vsRejected:
      Result := (ATo = vsDraft) and
        AAccess.CanWrite(AManager, AUser, AProjectId);
    vsInReview:
      Result := (ATo in [vsApproved, vsRejected]) and
        AAccess.CanReviewProtocol(AManager, AUser, AProjectId, AAuthorId);
  else
    Result := False;
  end;
end;


constructor TProtocolStatusModel.Create(Manager: TObjectManager;
  const Access: IProjectAccessPolicy);
begin
  inherited Create;
  if Access = nil then
    raise EArgumentNilException.Create('Access');
  FManager := Manager;
  FAccess := Access;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TProtocolStatusChangeDictionary.Create;
  FProtocolDic := TProtocolDictionary.Create;
  FItemDic := TItemDictionary.Create;
end;

destructor TProtocolStatusModel.Destroy;
begin
  FItemDic.Free;
  FProtocolDic.Free;
  FDic.Free;
  inherited;
end;

procedure TProtocolStatusModel.OpenDataSet;
begin
end;

function TProtocolStatusModel.GetAllowedTransitions(
  CurrentStatus: TValidationStatus; AUser: TUser;
  AProjectId, AAuthorId: Integer): TArray<TValidationStatus>;
begin
  Result := [];
  case CurrentStatus of
    vsDraft:
      if ProtocolTransitionAllowed(FManager, FAccess, AUser, AProjectId,
        AAuthorId, CurrentStatus, vsInReview) then
        Result := [vsInReview];
    vsInReview:
      if ProtocolTransitionAllowed(FManager, FAccess, AUser, AProjectId,
        AAuthorId, CurrentStatus, vsApproved) then
        Result := [vsApproved, vsRejected];
    vsRejected:
      if ProtocolTransitionAllowed(FManager, FAccess, AUser, AProjectId,
        AAuthorId, CurrentStatus, vsDraft) then
        Result := [vsDraft];
  end;
end;

function TProtocolStatusModel.CanTransition(
  CurrentStatus, NewStatus: TValidationStatus; AUser: TUser;
  AProjectId, AAuthorId: Integer): Boolean;
begin
  Result := ProtocolTransitionAllowed(FManager, FAccess, AUser,
    AProjectId, AAuthorId, CurrentStatus, NewStatus);
end;

function TProtocolStatusModel.TryGetAccessContext(AProtocolId: Integer;
  out AProjectId, AAuthorId: Integer): Boolean;
var
  Context: TProtocolAccessContext;
begin
  Result := ReadProtocolAccessContext(FManager, AProtocolId, Context) and
    not Context.ParentDeleted;
  if Result then
    Result := not IsItemSignedCheck(FManager, Context.ItemId);
  AProjectId := Context.ProjectId;
  AAuthorId := Context.AuthorId;
end;

function TProtocolStatusModel.Transition(AUser: TUser;
  AProtocolId, AExpectedVersion: Integer; AFrom, ATo: TValidationStatus;
  const AComment: string): Integer;
const
  StatusNames: array[TValidationStatus] of string =
    ('Draft', 'InReview', 'Approved', 'Rejected');
var
  OperationManager: TObjectManager;
  Transaction: IDBTransaction;
  Actor: TUser;
  Protocol: TProtocol;
  Context: TProtocolAccessContext;
  Change: TProtocolStatusChange;
  ChangedAt: TDateTime;
begin
  // This manager cannot flush unrelated drafts in the desktop manager.
  OperationManager := TObjectManager.Create(FManager.Connection);
  try
    Transaction := OperationManager.Connection.BeginTransaction;
    try
      if (AUser = nil) or AUser.IsArchived then
        raise EProtocolTransitionError.Create('An active scientist is required.');
      Actor := OperationManager.Find<TUser>(AUser.Id);
      if (Actor = nil) or Actor.IsArchived then
        raise EProtocolTransitionError.Create('The scientist is no longer active.');
      Protocol := OperationManager.Find<TProtocol>(AProtocolId);
      if Protocol = nil then
        raise EProtocolTransitionError.Create('Protocol not found.');
      if Protocol.Version <> AExpectedVersion then
        raise EProtocolTransitionConflict.Create('The protocol changed; reload before reviewing it.');
      if Protocol.ValidationStatus <> AFrom then
        raise EProtocolTransitionConflict.Create('The protocol state changed; reload before reviewing it.');
      if IsProtocolReadOnly(Protocol.ValidationStatus) then
        raise EProtocolTransitionError.Create('An approved protocol cannot change status.');
      if not ReadProtocolAccessContext(OperationManager, AProtocolId, Context) or
         Context.ParentDeleted then
        raise EProtocolTransitionError.Create('The protocol parent is missing or deleted.');
      if IsItemSignedCheck(OperationManager, Context.ItemId) then
        raise EProtocolTransitionError.Create('A signed item cannot change protocol status.');
      if not ProtocolTransitionAllowed(OperationManager, FAccess, Actor,
        Context.ProjectId, Context.AuthorId, AFrom, ATo) then
        raise EProtocolTransitionError.Create('This protocol status change is not allowed.');

      ChangedAt := UTCNow;
      Protocol.ValidationStatus := ATo;
      Protocol.ModifiedDate := ChangedAt;
      Protocol.ModifiedBy := Actor.Id;
      OperationManager.Flush;

      Change := TProtocolStatusChange.Create;
      try
        Change.ProtocolId := Protocol.Id;
        Change.OldStatus := AFrom;
        Change.NewStatus := ATo;
        Change.ChangedBy := Actor.Id;
        Change.ChangedDate := ChangedAt;
        Change.Comment := AComment;
        OperationManager.Save(Change);
        OperationManager.Flush;
      except
        try
          OperationManager.Evict(Change);
        except
        end;
        Change.Free;
        raise;
      end;
      RecordAudit(OperationManager, aetProtocol, Protocol.Id, aoUpdate, Actor.Id,
        'Protocol status ' + StatusNames[AFrom] + ' -> ' + StatusNames[ATo]);
      Transaction.Commit;
      Result := Protocol.Version;
    except
      on E: Exception do
      begin
        try
          Transaction.Rollback;
        except
          // A lost connection must not replace the original failure.
        end;
        if E is EVersionedConcurrencyControl then
          raise EProtocolTransitionConflict.Create('The protocol changed; reload before reviewing it.');
        raise;
      end;
    end;
  finally
    // Dispose every operation-owned snapshot and rolled-back row. The host's
    // cached protocol was never mutated and remains safe on any failure.
    Transaction := nil;
    OperationManager.Free;
  end;
end;

function TProtocolStatusModel.IsProtocolReadOnly(Status: TValidationStatus): Boolean;
begin
  Result := Status = vsApproved;
end;

procedure TProtocolStatusModel.RecordStatusChange(ProtocolId: Integer;
  OldStatus, NewStatus: TValidationStatus;
  UserId: Integer; const Comment: string);
var
  Change: TProtocolStatusChange;
begin
  Change := TProtocolStatusChange.Create;
  Change.ProtocolId := ProtocolId;
  Change.OldStatus := OldStatus;
  Change.NewStatus := NewStatus;
  Change.ChangedBy := UserId;
  Change.ChangedDate := UTCNow;
  Change.Comment := Comment;
  FManager.Save(Change);
  FManager.Flush;
end;

function TProtocolStatusModel.GetStatusHistory(
  ProtocolId: Integer): TProtocolStatusChanges;
begin
  Result := FManager.Find<TProtocolStatusChange>
    .Where(FDic.ProtocolId = ProtocolId)
    .OrderBy(FDic.ChangedDate)
    .List;
end;

function TProtocolStatusModel.GetProtocolsByStatus(
  Status: TValidationStatus; UserId: Integer): TList<TProtocol>;
var
  Criteria: TCriteria;
  Binned: TDictionary<Integer, Boolean>;
  DeletedItems: TList<TItem>;
  Item: TItem;
  Entry: TLabEntry;
  All: TList<TProtocol>;
  P: TProtocol;
begin
  // TLabEntry cannot reference TItem without a circular dependency, and an
  // item-side entries alias cannot reach TProtocol columns. Exclude recycled
  // protocols through the deleted items' collections instead.
  Binned := TDictionary<Integer, Boolean>.Create;
  try
    DeletedItems := FManager.Find<TItem>
      .Where(FItemDic.IsDeleted = True)
      .List;
    try
      for Item in DeletedItems do
        for Entry in Item.Entries do
          Binned.AddOrSetValue(Entry.Id, True);
    finally
      DeletedItems.Free;
    end;

    Criteria := FManager.Find<TProtocol>
      .Where(FProtocolDic.ValidationStatus = Ord(Status))
      .Where(FProtocolDic.ProtocolType <> Ord(ptNote));

    if UserId > 0 then
      Criteria.Where(FProtocolDic.CreatedBy = UserId);

    All := Criteria
      .OrderBy(FProtocolDic.CreatedDate)
      .List<TProtocol>;
    try
      Result := TList<TProtocol>.Create;
      try
        for P in All do
          if not Binned.ContainsKey(P.Id) then
            Result.Add(P);
      except
        Result.Free;
        raise;
      end;
    finally
      All.Free;
    end;
  finally
    Binned.Free;
  end;
end;

end.
