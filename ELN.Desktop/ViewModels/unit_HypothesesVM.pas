unit unit_HypothesesVM;

{
  State and commands behind the desktop Hypotheses view (spec 10).

  Lives in ELN.Desktop\ViewModels - NOT ELN.Desktop\Units (both MCP servers
  put that folder on their unit search path) nor ELN.Model: it executes the
  human gates through unit_HypothesisGateModel, which only desktop, WebAPI
  and test code may name (test_HypothesisLinkage; pre-flight C1, C2).
  Non-visual, so it is unit-tested (test_HypothesesVM).

  All decisions stay in the models: the gate model is used for Transition
  only; allowed gate targets and the seal come from THypothesisModel
  (AllowedGateTargetsFor, SealStateOf - pre-flight C8), and edit/attach
  rights from unit_HypothesisRules over THypothesisModel.ActorsFor.

  Commands never raise for a refusal: they return a TVMOutcome the view
  shows. A stale version (someone else changed the hypothesis) reloads the
  view and keeps the gate comment the user typed.

  Per-selection facts (actors, gate targets, seal, policy validity) are
  computed once when the detail loads, not on every Can* call: the view asks
  for several of them per repaint, over a remote database.

  Unreadable foreign items (pre-flight C7): a run or evidence row whose item
  lives in a project the user cannot read is redacted in Detail (no item
  id, title, note, file/value ids or badges) and reported by RunReadable /
  EvidenceReadable; it is never offered by the evidence picker. The same
  trade-off the web made: no existence oracle.

  User-visible wording (pre-flight C9) is the web's, verbatim
  (ELN.WebApp/src/lib/hypView.ts, hypotheses.ts gateLabel, and
  screens/experimentParts.ts). Non-ASCII characters are #$ escapes, so this
  unit needs no BOM.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Aurelius.Engine.ObjectManager,
  Aurelius.Types.Nullable,
  unit_User,
  unit_Hypothesis,
  unit_HypothesisRules,
  unit_HypothesisModel,
  unit_HypothesisGateModel,
  unit_ProjectAccessPolicy;

type
  TOpenHypothesisEvent = procedure(Sender: TObject; AProjectId,
    AHypothesisId: Integer) of object;

  TVMOutcome = record
    Ok: Boolean;
    Reloaded: Boolean;      // the view was refreshed because the data changed underneath
    Message: string;        // empty when Ok
  end;

  TEvidenceChoiceKind = (eckWholeItem, eckFile, eckValue);

  TEvidenceChoice = record
    Kind: TEvidenceChoiceKind;
    ItemId: Integer;
    FileId: Int64;
    ValueId: Integer;
    Caption: string;
  end;

  /// <summary>One row of the evidence picker's item list: a readable, live
  /// run or reference item (Depth 0) or one of its live descendants.</summary>
  TEvidenceSource = record
    ItemId: Integer;
    Depth: Integer;
    Caption: string;
  end;

  /// <summary>One line of the History list, ready to show.</summary>
  THypHistoryRow = record
    When: TDateTime;        // local time
    WhenText: string;       // 'yyyy-mm-dd hh:nn', local
    Who: string;            // display name, plus '(device #N)' when N > 0
    What: string;           // HistorySentence
    Comment: string;
  end;

const
  DECISION_LABEL = 'Your decision';
  NOT_READABLE_TEXT = 'Not readable';
  // The web's sentence, word for word (unit_HypothesisHttp POLICY_INVALID_MESSAGE).
  POLICY_INVALID_TEXT = 'The approval policy is invalid; an administrator must ' +
    'fix it in Administration > Approval Policy.';
  STALE_VERSION_TEXT = 'Someone else changed this hypothesis. The view was ' +
    'reloaded; check the changes and try again.';
  DRAFT_DISCARDED_TEXT = 'Your unsent conclusion was discarded because this ' +
    'hypothesis changed.';
  DRAFT_COPIED_TEXT = 'Your text was copied to the clipboard.';
  DRAFT_KEPT_TEXT = 'It could not be copied to the clipboard, so it is still ' +
    'shown below - copy it before you leave this hypothesis.';
  DRAFT_NOT_COPIED_TEXT = 'It could not be copied to the clipboard; here it is:';

type
  THypothesesVM = class
  private
    FManager: TObjectManager;
    FAccess: IProjectAccessPolicy;
    FUser: TUser;
    FModel: THypothesisModel;
    FGates: THypothesisGateModel;
    FProjectId: Integer;
    FCanWriteProject: Boolean;
    FNodes: TArray<THypothesisSummary>;
    FIsRoot: TArray<Boolean>;
    FSelectedId: Integer;
    FDetail: THypothesisDetail;
    FHasDetail: Boolean;
    FActors: THypActors;
    FGateTargets: TArray<THypothesisStatus>;
    FSealState: THypSealState;
    FPolicyInvalid: Boolean;
    FRunReadable: TArray<Boolean>;
    FRunItemIds: TArray<Integer>;                 // before redaction; never exposed
    FEvidenceReadable: TArray<Boolean>;
    FReadable: TDictionary<Integer, Boolean>;     // project id -> CanRead
    FUserNames: TDictionary<Integer, string>;
    FGateComment: string;
    FHasDraft: Boolean;           // the user is typing a conclusion for FDraftId
    FDraftId: Integer;
    FDraftVersion: Integer;       // the Version the draft can still be submitted against
    FDraftText: string;           // the draft as last typed
    FDraftDiscarded: Boolean;     // the last load dropped the draft: the node changed
    FDiscardedDraftText: string;  // what that dropped draft said, for the view to save
    FDiscardedDraftSaved: Boolean;
    FSelectionLost: Boolean;      // the last Reload lost the selected node
    FOnChanged: TNotifyEvent;
    function Run(const AAction: TFunc<Integer>): TVMOutcome;
    procedure BuildShape;
    procedure LoadDetail;
    procedure Redact;
    procedure CheckDraft(AWasOnDraft: Boolean);
    procedure ClearDiscardedDraft;
    procedure Changed;
    function CanReadProject(AProjectId: Integer): Boolean;
    function LiveItem(AItemId: Integer; out ATitle: string;
      out AProjectId: Integer): Boolean;
    function UserName(AUserId: Integer): string;
    function WhoText(AUserId, ADeviceId: Integer): string;
    function FileText(AFileId: Int64): string;
    function ValueEvidenceText(const E: THypothesisEvidenceView): string;
    class function CommentRequired(AFrom, ATo: THypothesisStatus): Boolean; static;
    class function FormatShortDate(ALocal, ANowLocal: TDateTime): string; static;
  public
    constructor Create(AManager: TObjectManager; AUser: TUser;
      const AAccess: IProjectAccessPolicy);
    destructor Destroy; override;
    procedure OpenProject(AProjectId: Integer; ASelectId: Integer = 0);
    procedure Reload;
    procedure Select(AId: Integer);
    function RootIndexes: TArray<Integer>;
    function ChildIndexes(ANodeIndex: Integer): TArray<Integer>;
    function IndexOfId(AId: Integer): Integer;

    // UI state (for the selected node; all False / empty without one)
    function CanPropose: Boolean;
    function CanEditSelected: Boolean;
    /// <summary>Run rows and evidence: any writer, while Approved.</summary>
    function CanChangeRuns: Boolean;
    /// <summary>Reference rows: the author while Proposed, any writer while
    /// Approved (Plan 1 CanChangeReferences; pre-flight C21).</summary>
    function CanAttachReferences: Boolean;
    function CanSubmit: Boolean;
    /// <summary>The user started a conclusion draft (typed a conclusion or
    /// picked an outcome) for the selected node. The view keeps showing it
    /// only while HasConclusionDraft: a draft lives while it can still be
    /// submitted as-is - same node, CanSubmit, and no change but the user's
    /// own since it began. Any other change drops it (DraftDiscarded), so
    /// a read-only conclusion always shows what is stored. Call it on every
    /// edit: AText is the conclusion as typed so far.</summary>
    procedure BeginConclusionDraft(const AText: string);
    function CanAbandon: Boolean;
    function GateTargets: TArray<THypothesisStatus>;
    function GateCaption(ATo: THypothesisStatus): string; overload;
    function GateNeedsComment(ATo: THypothesisStatus): Boolean;
    function SealState: THypSealState;
    /// <summary>The stored approval policy cannot be parsed: no gate is
    /// offered to anyone until an administrator fixes it (spec 6.2, C16).</summary>
    function PolicyInvalid: Boolean;

    // Rows of the selected node (index into Detail.Runs / Detail.Evidence)
    function RunReadable(AIndex: Integer): Boolean;
    function RunCaption(AIndex: Integer): string;
    /// <summary>The item to open for run row AIndex; 0 when it is not
    /// readable or gone (no navigation).</summary>
    function RunNavigateItemId(AIndex: Integer): Integer;
    function EvidenceReadable(AIndex: Integer): Boolean;
    function EvidenceItemCaption(AIndex: Integer): string;
    function EvidenceNavigateItemId(AIndex: Integer): Integer;
    /// <summary>File name, "name: value unit", or "Item" (whole item).</summary>
    function EvidenceWhat(AIndex: Integer): string;
    function HistoryRows: TArray<THypHistoryRow>;
    function ReturnedNoticeText: string;
    function KeyValueText(const S: THypothesisSummary): string;

    // Evidence picker (pre-flight C6): live queries, never TItem.Files/Values
    function EvidenceSources: TArray<TEvidenceSource>;
    function EvidenceChoicesFor(AItemId: Integer): TArray<TEvidenceChoice>;
    function ApprovedInProject(AProjectId: Integer): TArray<THypothesisSummary>;
    /// <summary>Approved hypotheses in the project (attach as Run or
    /// Reference), plus AUser's own Proposed hypotheses there (Reference
    /// only: Plan 1 CanChangeReferences, pre-flight C21). Feeds the item
    /// tree's "Attach to hypothesis..." picker; dlg_HypothesisPick forces
    /// Reference for any row that is not Approved.</summary>
    function AttachableInProject(AProjectId: Integer): TArray<THypothesisSummary>;

    // Wording (pre-flight C9), shared with the web
    class function StatusCaption(const S: THypothesisSummary): string; static;
    class function OutcomeCaption(const D: THypothesisDetail): string; static;
    class function WaitingText(AStatus: THypothesisStatus): string; static;
    class function GateCaption(AFrom, ATo: THypothesisStatus): string; overload; static;
    class function GateHelp(AFrom, ATo: THypothesisStatus): string; static;
    class function GateCommentHint(AFrom: THypothesisStatus;
      ANeedsComment: Boolean): string; static;
    class function HistorySentence(AOld, ANew: THypothesisStatus): string; static;
    class function SealText(AState: THypSealState): string; static;
    class function EvidenceBadge(const E: THypothesisEvidenceView): string; static;
    /// <summary>"missing" when the run's item is gone, else ''.</summary>
    class function RunBadge(const R: THypothesisRunView): string; static;
    class function LastReturn(const D: THypothesisDetail;
      out H: THypothesisHistoryView): Boolean; static;
    class function ReturnedNotice(const H: THypothesisHistoryView;
      const AByName: string; ANowLocal: TDateTime): string; static;
    class function FormatNumber(AValue: Double): string; static;
    /// <summary>The dashboard's "Waiting for You" row age (hypView.ts
    /// formatAge): "just now" / "N min ago" / "N h ago" / "yesterday" /
    /// "N days ago" / a short date. Both arguments are UTC; seconds-based
    /// buckets, not calendar-day ones, exactly as the web computes them.</summary>
    class function AgeText(AWhenUtc, ANowUtc: TDateTime): string; static;

    // Commands (all return an outcome; none raises for a refusal)
    function ProposeRoot(const ATitle, AStatement: string;
      AKeyValueTypeId: Integer): TVMOutcome;
    function ProposeChild(AParentId: Integer; const ATitle, AStatement,
      AChange: string; AKeyValueTypeId: Integer): TVMOutcome;
    /// <summary>A new root with the item attached as a Reference (spec 10;
    /// pre-flight C10). Never approves it.</summary>
    function ProposeFromItem(AItemId: Integer; const ATitle, AStatement: string;
      AKeyValueTypeId: Integer): TVMOutcome;
    function SaveEdit(const ATitle, AStatement, AChange: string;
      AKeyValueTypeId: Integer): TVMOutcome;
    function AttachItem(AHypothesisId, AItemId: Integer;
      ARole: THypothesisRunRole): TVMOutcome;
    function DetachItem(AItemId: Integer): TVMOutcome;
    /// <summary>Detach run row AIndex - also one whose item the user cannot
    /// read, whose id Detail no longer carries.</summary>
    function DetachRunAt(AIndex: Integer): TVMOutcome;
    function Cite(const AChoice: TEvidenceChoice; const ANote: string): TVMOutcome;
    function RemoveEvidence(AEvidenceId: Integer): TVMOutcome;
    function Submit(const AConclusion: string;
      AOutcome: Nullable<THypothesisOutcome>): TVMOutcome;
    function Abandon(const AComment: string): TVMOutcome;
    function Gate(ATo: THypothesisStatus; const AComment: string): TVMOutcome;

    property Nodes: TArray<THypothesisSummary> read FNodes;
    property Detail: THypothesisDetail read FDetail;
    property HasDetail: Boolean read FHasDetail;
    property SelectedId: Integer read FSelectedId;
    property ProjectId: Integer read FProjectId;
    property GateComment: string read FGateComment write FGateComment;  // survives a failed gate
    property HasConclusionDraft: Boolean read FHasDraft;
    /// <summary>The last reload dropped the user's draft because the node
    /// changed underneath, or vanished (access removed, deleted) while the
    /// user was on it (DRAFT_DISCARDED_TEXT); False after any other load.</summary>
    property DraftDiscarded: Boolean read FDraftDiscarded;
    /// <summary>The text of a draft dropped because its node changed or
    /// vanished (lost access, deleted) under the user - when it was not blank
    /// and differs from the stored conclusion; '' otherwise. The view saves
    /// it instead of losing what the user typed. It outlives later reloads
    /// (a view that could not copy it keeps showing it) and ends when the
    /// user edits the conclusion or selects another node.</summary>
    property DiscardedDraftText: string read FDiscardedDraftText;
    /// <summary>The view sets it once it has saved DiscardedDraftText, so a
    /// repaint within the same load does not save it again.</summary>
    property DiscardedDraftSaved: Boolean read FDiscardedDraftSaved
      write FDiscardedDraftSaved;
    /// <summary>The last Reload lost the node that was selected: it is gone
    /// or no longer readable (e.g. the user's access was removed).</summary>
    property SelectionLost: Boolean read FSelectionLost;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.StrUtils,
  System.DateUtils,
  System.Variants,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq,
  Aurelius.Criteria.Projections,
  unit_Item,
  unit_ItemTypes,
  unit_ValueType,
  unit_FileType,
  unit_TimeHelper;

const
  MIDDOT = #$00B7;
  EMDASH = #$2014;
  CHECKMARK = #$2713;
  MONTHS: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  IN_CHUNK = 500;

function Fail(const AMessage: string; AReloaded: Boolean = False): TVMOutcome;
begin
  Result.Ok := False;
  Result.Reloaded := AReloaded;
  Result.Message := AMessage;
end;

function Success: TVMOutcome;
begin
  Result.Ok := True;
  Result.Reloaded := False;
  Result.Message := '';
end;

// The web's display file name (WebAPI THypJsonContext.FileNameOf): the stored
// Title usually lacks the extension, and FileType.Ext may or may not carry
// the leading dot.
function FileDisplayName(AFile: unit_Item.TFile): string;
var
  FT: TFileType;
  Ext: string;
begin
  Result := AFile.Title;
  FT := AFile.FileType;
  if FT = nil then
    Exit;
  Ext := FT.Ext;
  if Ext = '' then
    Exit;
  if Ext[1] <> '.' then
    Ext := '.' + Ext;
  if not EndsText(Ext, Result) then
    Result := Result + Ext;
end;

// "name: value unit" - hypView.ts formatValueEvidence.
function ValueText(const AName, AUnits: string; AHasValue: Boolean;
  AValue: Double): string;
begin
  if not AHasValue then
    Exit(AName + ': ' + EMDASH);
  Result := AName + ': ' + THypothesesVM.FormatNumber(AValue);
  if AUnits <> '' then
    Result := Result + ' ' + AUnits;
end;

function ValueTypeName(VT: TValueType): string;
begin
  // As the WebAPI names a value type: Title, then Symbol, then the word.
  Result := '';
  if VT <> nil then
  begin
    Result := VT.Title;
    if Result = '' then
      Result := VT.Symbol;
  end;
  if Result = '' then
    Result := 'Value';
end;

{ THypothesesVM }

constructor THypothesesVM.Create(AManager: TObjectManager; AUser: TUser;
  const AAccess: IProjectAccessPolicy);
begin
  inherited Create;
  if AAccess = nil then
    raise EArgumentNilException.Create('Access');
  FManager := AManager;
  FUser := AUser;
  FAccess := AAccess;
  FModel := THypothesisModel.Create(AManager, AAccess);
  FGates := THypothesisGateModel.Create(AManager, AAccess);
  FReadable := TDictionary<Integer, Boolean>.Create;
  FUserNames := TDictionary<Integer, string>.Create;
end;

destructor THypothesesVM.Destroy;
begin
  FUserNames.Free;
  FReadable.Free;
  FGates.Free;
  FModel.Free;
  inherited;
end;

procedure THypothesesVM.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function THypothesesVM.CanReadProject(AProjectId: Integer): Boolean;
begin
  if AProjectId = 0 then
    Exit(False);
  if not FReadable.TryGetValue(AProjectId, Result) then
  begin
    Result := FAccess.CanRead(FManager, FUser, AProjectId);
    FReadable.Add(AProjectId, Result);
  end;
end;

function THypothesesVM.LiveItem(AItemId: Integer; out ATitle: string;
  out AProjectId: Integer): Boolean;
var
  Rows: TObjectList<TCriteriaResult>;
begin
  // A projection, not Find<TItem>: the desktop's manager lives for the whole
  // session, so a cached TItem can still say "not deleted" long after it was.
  ATitle := '';
  AProjectId := 0;
  Rows := FManager.Find<TItem>
    .Select(TProjections.ProjectionList
      .Add(TProjections.Prop('ProjectID').As_('Pid'))
      .Add(TProjections.Prop('Title').As_('T')))
    .Where((Linq['Id'] = AItemId) and (Linq['IsDeleted'] = False))
    .ListValues;
  try
    Result := Rows.Count > 0;
    if Result then
    begin
      AProjectId := Rows[0].Values['Pid'];
      ATitle := VarToStr(Rows[0].Values['T']);
    end;
  finally
    Rows.Free;
  end;
end;

function THypothesesVM.UserName(AUserId: Integer): string;
var
  U: TUser;
begin
  if FUserNames.TryGetValue(AUserId, Result) then
    Exit;
  U := FManager.Find<TUser>(AUserId);
  if U = nil then
    Result := '#' + IntToStr(AUserId)
  else
  begin
    Result := Trim(U.FirstName + ' ' + U.LastName);
    if Result = '' then
      Result := U.Username;
  end;
  FUserNames.Add(AUserId, Result);
end;

function THypothesesVM.WhoText(AUserId, ADeviceId: Integer): string;
begin
  Result := UserName(AUserId);
  if ADeviceId > 0 then
    Result := Result + Format(' (device #%d)', [ADeviceId]);
end;

procedure THypothesesVM.OpenProject(AProjectId, ASelectId: Integer);
begin
  FProjectId := AProjectId;
  if ASelectId <> FSelectedId then
    ClearDiscardedDraft;               // navigating elsewhere ends a kept text
  FSelectedId := ASelectId;
  FGateComment := '';
  Reload;
end;

procedure THypothesesVM.Reload;
var
  PrevSelectedId: Integer;
  WasOnDraft: Boolean;
begin
  PrevSelectedId := FSelectedId;
  WasOnDraft := FHasDraft and (FSelectedId = FDraftId);
  // Permissions may have changed since the last load.
  FReadable.Clear;
  FUserNames.Clear;
  if FProjectId = 0 then
  begin
    FCanWriteProject := False;
    FNodes := nil;
  end
  else
  begin
    FCanWriteProject := FAccess.CanWrite(FManager, FUser, FProjectId);
    FNodes := FModel.Tree(FUser, FProjectId, 0);
  end;
  BuildShape;
  LoadDetail;
  FSelectionLost := (PrevSelectedId <> 0) and (FSelectedId = 0);
  CheckDraft(WasOnDraft);
  Changed;
end;

procedure THypothesesVM.Select(AId: Integer);
begin
  if AId = FSelectedId then
    Exit;
  FSelectedId := AId;
  FGateComment := '';
  FSelectionLost := False;
  ClearDiscardedDraft;                 // the user moved on
  LoadDetail;
  CheckDraft(False);
  Changed;
end;

procedure THypothesesVM.LoadDetail;
var
  H: THypothesis;
  Eligibility: TGateEligibility;
begin
  FHasDetail := False;
  FDetail := Default(THypothesisDetail);
  FActors := [];
  FGateTargets := nil;
  FSealState := hssNone;
  FRunReadable := nil;
  FRunItemIds := nil;
  FEvidenceReadable := nil;
  Eligibility := FAccess.CreateGateEligibility(FManager, FUser);
  try
    FPolicyInvalid := Eligibility.PolicyInvalid;
  finally
    Eligibility.Free;
  end;
  if (FSelectedId = 0) or (IndexOfId(FSelectedId) < 0) then
  begin
    FSelectedId := 0;
    Exit;
  end;
  try
    FDetail := FModel.Get(FUser, FSelectedId);
  except
    on EHypothesisAccess do
    begin
      // Gone or unreadable between the tree read and this one.
      FDetail := Default(THypothesisDetail);
      FSelectedId := 0;
      Exit;
    end;
  end;
  // Get has just refreshed the cached row, so Find sees it as committed now.
  H := FManager.Find<THypothesis>(FSelectedId);
  FActors := FModel.ActorsFor(FUser, H);
  FGateTargets := THypothesisModel.AllowedGateTargetsFor(FManager, FUser, H, FAccess);
  FSealState := THypothesisModel.SealStateOf(FManager, H);
  Redact;
  FHasDetail := True;
end;

procedure THypothesesVM.CheckDraft(AWasOnDraft: Boolean);
var
  SameNode, Vanished: Boolean;
begin
  FDraftDiscarded := False;
  if not FHasDraft then
    Exit;
  SameNode := FHasDetail and (FDetail.Summary.Id = FDraftId);
  if SameNode and (FDetail.Summary.Version = FDraftVersion) and CanSubmit then
    Exit;
  // The user was still on the draft's node, and it is gone or unreadable now
  // (access removed, deleted). The text is the user's own words: save it.
  Vanished := AWasOnDraft and not SameNode;
  // Another node shows its own conclusion; a changed one shows what is stored.
  FHasDraft := False;
  FDraftDiscarded := SameNode or Vanished;
  if FDraftDiscarded and (Trim(FDraftText) <> '') and
    (Vanished or (FDraftText <> FDetail.Conclusion)) then
  begin
    FDiscardedDraftText := FDraftText;
    FDiscardedDraftSaved := False;
  end;
end;

procedure THypothesesVM.ClearDiscardedDraft;
begin
  FDiscardedDraftText := '';
  FDiscardedDraftSaved := False;
end;

procedure THypothesesVM.BeginConclusionDraft(const AText: string);
begin
  ClearDiscardedDraft;                 // the user took the kept text up again
  if not FHasDraft then
  begin
    if not CanSubmit then
      Exit;                            // cannot be sent: no draft
    FHasDraft := True;
    FDraftId := FSelectedId;
    FDraftVersion := FDetail.Summary.Version;
  end;
  FDraftText := AText;
end;

procedure THypothesesVM.Redact;
var
  I: Integer;
  Ok: Boolean;
begin
  SetLength(FRunReadable, Length(FDetail.Runs));
  SetLength(FRunItemIds, Length(FDetail.Runs));
  for I := 0 to High(FDetail.Runs) do
  begin
    FRunItemIds[I] := FDetail.Runs[I].ItemId;
    // ItemProjectId 0 = the item row is gone: nothing to show either (web).
    Ok := CanReadProject(FDetail.Runs[I].ItemProjectId);
    FRunReadable[I] := Ok;
    if not Ok then
    begin
      // As the web: no item id either. DetachRunAt uses FRunItemIds.
      FDetail.Runs[I].ItemId := 0;
      FDetail.Runs[I].ItemTitle := '';
      FDetail.Runs[I].ItemProjectId := 0;
      FDetail.Runs[I].Missing := False;
    end;
  end;
  SetLength(FEvidenceReadable, Length(FDetail.Evidence));
  for I := 0 to High(FDetail.Evidence) do
  begin
    Ok := CanReadProject(FDetail.Evidence[I].ItemProjectId);
    FEvidenceReadable[I] := Ok;
    if not Ok then
    begin
      // Only EvidenceId survives (RemoveEvidence needs it): no ids, note,
      // hash, value or missing/changed state of another project's item.
      FDetail.Evidence[I].ItemId := 0;
      FDetail.Evidence[I].ItemProjectId := 0;
      FDetail.Evidence[I].ValueId := 0;
      FDetail.Evidence[I].FileId := 0;
      FDetail.Evidence[I].ItemTitle := '';
      FDetail.Evidence[I].Note := '';
      FDetail.Evidence[I].FileHash := '';
      FDetail.Evidence[I].HasSnapshot := False;
      FDetail.Evidence[I].ValueSnapshot := 0;
      FDetail.Evidence[I].Changed := False;
      FDetail.Evidence[I].Missing := False;
    end;
  end;
end;

function THypothesesVM.IndexOfId(AId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if FNodes[I].Id = AId then
      Exit(I);
  Result := -1;
end;

procedure THypothesesVM.BuildShape;
var
  I: Integer;
  Reached: TArray<Boolean>;
  Queue: TList<Integer>;

  procedure Reach(AFrom: Integer);
  var
    J, Head: Integer;
  begin
    Reached[AFrom] := True;
    Queue.Clear;
    Queue.Add(AFrom);
    Head := 0;
    while Head < Queue.Count do
    begin
      for J := 0 to High(FNodes) do
        if not Reached[J] and (FNodes[J].ParentId = FNodes[Queue[Head]].Id) then
        begin
          Reached[J] := True;
          Queue.Add(J);
        end;
      Inc(Head);
    end;
  end;

begin
  // Roots: no parent, or a parent not in the list (an orphan). Then every
  // node no root reaches - a parent cycle, which only a hand-edited row can
  // make - becomes a root too, so it is shown once instead of never (the web
  // rescues them the same way). ChildIndexes never returns a root, so the
  // tree the view builds is always finite.
  SetLength(FIsRoot, Length(FNodes));
  SetLength(Reached, Length(FNodes));
  for I := 0 to High(FNodes) do
  begin
    FIsRoot[I] := (FNodes[I].ParentId = 0) or (IndexOfId(FNodes[I].ParentId) < 0);
    Reached[I] := False;
  end;
  Queue := TList<Integer>.Create;
  try
    for I := 0 to High(FNodes) do
      if FIsRoot[I] and not Reached[I] then
        Reach(I);
    // Whatever the real roots did not reach sits on (or hangs off) a cycle.
    for I := 0 to High(FNodes) do
      if not Reached[I] then
      begin
        FIsRoot[I] := True;
        Reach(I);
      end;
  finally
    Queue.Free;
  end;
end;

function THypothesesVM.RootIndexes: TArray<Integer>;
var
  I: Integer;
  L: TList<Integer>;
begin
  L := TList<Integer>.Create;
  try
    for I := 0 to High(FIsRoot) do
      if FIsRoot[I] then
        L.Add(I);                                // incl. orphans and rescued cycles
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function THypothesesVM.ChildIndexes(ANodeIndex: Integer): TArray<Integer>;
var
  I, ParentId: Integer;
  L: TList<Integer>;
begin
  ParentId := FNodes[ANodeIndex].Id;
  L := TList<Integer>.Create;
  try
    for I := 0 to High(FNodes) do
      if (FNodes[I].ParentId = ParentId) and not FIsRoot[I] then
        L.Add(I);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function THypothesesVM.Run(const AAction: TFunc<Integer>): TVMOutcome;
var
  NewId, OwnId, OwnVersion: Integer;
begin
  // A refusal of the data itself (validation, wrong state) leaves the view
  // as it is. A stale version, or an access refusal (the node is gone, the
  // user may no longer write or approve - often because something changed
  // underneath), reloads it so the buttons match what is true now. Reload
  // never touches FGateComment.
  Result := Success;
  OwnId := FDetail.Summary.Id;          // FDetail is the one the action was made on
  OwnVersion := FDetail.Summary.Version;
  try
    NewId := AAction();
    if NewId <> 0 then
      FSelectedId := NewId;
    // Our own write (an attach, a citation) bumped the Version by one and
    // left the conclusion alone: the draft is still ours to submit. If
    // anyone else wrote too, the Version moved further and CheckDraft drops it.
    if FHasDraft and (FDraftId = OwnId) and (FDraftVersion = OwnVersion) and
      (FSelectedId = OwnId) then
      FDraftVersion := OwnVersion + 1;
  except
    on E: EHypothesisConflict do
      Result := Fail(STALE_VERSION_TEXT, True);
    on E: EHypothesisOtherRecordChanged do     // before EHypothesisError: reload
      Result := Fail(E.Message, True);
    on E: EHypothesisError do
      Exit(Fail(E.Message));
    on E: EHypothesisAccess do                 // incl. NotFound, NotApprover
      Result := Fail(E.Message, True);
  end;
  Reload;
end;

{ UI state }

function THypothesesVM.CanPropose: Boolean;
begin
  Result := FCanWriteProject;
end;

function THypothesesVM.CanEditSelected: Boolean;
begin
  Result := FHasDetail and (haWriter in FActors) and
    (EditableFields(FDetail.Summary.Status, FActors) <> []);
end;

function THypothesesVM.CanChangeRuns: Boolean;
begin
  Result := FHasDetail and (haWriter in FActors) and
    CanChangeRunsOrEvidence(FDetail.Summary.Status);
end;

function THypothesesVM.CanAttachReferences: Boolean;
begin
  Result := FHasDetail and (haWriter in FActors) and
    CanChangeReferences(FDetail.Summary.Status, FActors);
end;

function THypothesesVM.CanSubmit: Boolean;
begin
  // Approved -> InReview needs the author or a writer, and the model's
  // RequireWrite makes that "a writer".
  Result := FHasDetail and (FDetail.Summary.Status = hsApproved) and
    (haWriter in FActors);
end;

function THypothesesVM.CanAbandon: Boolean;
begin
  Result := FHasDetail and (FDetail.Summary.Status = hsApproved) and
    (haWriter in FActors) and
    (FActors * [haAuthor, haProposalApprover] <> []);
end;

function THypothesesVM.GateTargets: TArray<THypothesisStatus>;
begin
  Result := FGateTargets;          // empty without a node or on an invalid policy
end;

function THypothesesVM.GateCaption(ATo: THypothesisStatus): string;
begin
  if not FHasDetail then
    Exit('');
  Result := GateCaption(FDetail.Summary.Status, ATo);
end;

function THypothesesVM.GateNeedsComment(ATo: THypothesisStatus): Boolean;
begin
  Result := FHasDetail and CommentRequired(FDetail.Summary.Status, ATo);
end;

function THypothesesVM.SealState: THypSealState;
begin
  Result := FSealState;
end;

function THypothesesVM.PolicyInvalid: Boolean;
begin
  Result := FPolicyInvalid;
end;

{ Rows }

function THypothesesVM.RunReadable(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FRunReadable)) and FRunReadable[AIndex];
end;

function THypothesesVM.RunCaption(AIndex: Integer): string;
begin
  if not RunReadable(AIndex) then
    Exit(NOT_READABLE_TEXT);
  Result := FDetail.Runs[AIndex].ItemTitle;
  if Result = '' then
    Result := 'item #' + IntToStr(FDetail.Runs[AIndex].ItemId);
end;

function THypothesesVM.RunNavigateItemId(AIndex: Integer): Integer;
begin
  if not RunReadable(AIndex) or FDetail.Runs[AIndex].Missing then
    Exit(0);
  Result := FDetail.Runs[AIndex].ItemId;
end;

function THypothesesVM.EvidenceNavigateItemId(AIndex: Integer): Integer;
begin
  if not EvidenceReadable(AIndex) or FDetail.Evidence[AIndex].Missing then
    Exit(0);
  Result := FDetail.Evidence[AIndex].ItemId;
end;

function THypothesesVM.EvidenceReadable(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FEvidenceReadable)) and
    FEvidenceReadable[AIndex];
end;

function THypothesesVM.EvidenceItemCaption(AIndex: Integer): string;
begin
  if not EvidenceReadable(AIndex) then
    Exit(NOT_READABLE_TEXT);
  Result := FDetail.Evidence[AIndex].ItemTitle;
  if Result = '' then
    Result := 'item #' + IntToStr(FDetail.Evidence[AIndex].ItemId);
end;

function THypothesesVM.FileText(AFileId: Int64): string;
var
  Fl: unit_Item.TFile;
begin
  Fl := FManager.Find<unit_Item.TFile>(AFileId);
  if Fl = nil then
    Result := 'File'                    // the row is gone; the badge says "missing"
  else
    Result := FileDisplayName(Fl);
end;

function THypothesesVM.ValueEvidenceText(const E: THypothesisEvidenceView): string;
var
  V: TValue;
  VT: TValueType;
begin
  VT := nil;
  V := FManager.Find<TValue>(E.ValueId);
  if V <> nil then
    VT := V.ValueType;
  if VT = nil then
    Result := ValueText('Value', '', E.HasSnapshot, E.ValueSnapshot)
  else
    Result := ValueText(ValueTypeName(VT), VT.Units, E.HasSnapshot, E.ValueSnapshot);
end;

function THypothesesVM.EvidenceWhat(AIndex: Integer): string;
var
  E: THypothesisEvidenceView;
begin
  if not EvidenceReadable(AIndex) then
    Exit(NOT_READABLE_TEXT);
  E := FDetail.Evidence[AIndex];
  if E.FileId <> 0 then
    Result := FileText(E.FileId)
  else if E.ValueId <> 0 then
    Result := ValueEvidenceText(E)
  else
    Result := 'Item';
end;

function THypothesesVM.HistoryRows: TArray<THypHistoryRow>;

  function Row(AUtc: TDateTime; AUserId, ADeviceId: Integer;
    const AWhat, AComment: string): THypHistoryRow;
  begin
    Result.When := FromUTC(AUtc);
    Result.WhenText := FormatDateTime('yyyy-mm-dd hh:nn', Result.When,
      TFormatSettings.Invariant);
    Result.Who := WhoText(AUserId, ADeviceId);
    Result.What := AWhat;
    Result.Comment := AComment;
  end;

var
  L: TList<THypHistoryRow>;
  H: THypothesisHistoryView;
  HasProposedRow: Boolean;
begin
  if not FHasDetail then
    Exit(nil);
  L := TList<THypHistoryRow>.Create;
  try
    // The history always opens with who proposed the node, even when no
    // status-change row says so (web 7b64ab4); never twice.
    HasProposedRow := False;
    for H in FDetail.History do
      if H.NewStatus = hsProposed then
        HasProposedRow := True;
    if not HasProposedRow then
      L.Add(Row(FDetail.CreatedDate, FDetail.Summary.CreatedBy,
        FDetail.CreatedDeviceId, HistorySentence(hsProposed, hsProposed), ''));
    for H in FDetail.History do
      L.Add(Row(H.ChangedDate, H.ChangedBy, H.ChangedDeviceId,
        HistorySentence(H.OldStatus, H.NewStatus), H.Comment));
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function THypothesesVM.ReturnedNoticeText: string;
var
  H: THypothesisHistoryView;
begin
  if FHasDetail and LastReturn(FDetail, H) then
    Result := ReturnedNotice(H, UserName(H.ChangedBy), Now)
  else
    Result := '';
end;

function THypothesesVM.KeyValueText(const S: THypothesisSummary): string;
var
  VT: TValueType;
  Name, Units: string;
begin
  // hypView.ts formatKeyValue.
  if S.KeyValueTypeId = 0 then
    Exit('');
  VT := FManager.Find<TValueType>(S.KeyValueTypeId);
  Name := '';
  Units := '';
  if VT <> nil then
  begin
    Name := VT.Title;
    if Name = '' then
      Name := VT.Symbol;
    Units := VT.Units;
  end;
  if Name = '' then
    Name := 'Key value';
  if S.KeyValue.N = 0 then
    Exit(Name + ': no values yet');
  Result := Name + ': ' + FormatNumber(S.KeyValue.Mean);
  if Units <> '' then
    Result := Result + ' ' + Units;
  if S.KeyValue.N > 1 then
    Result := Result + Format(' (mean of %d)', [S.KeyValue.N]);
end;

{ Evidence picker }

function THypothesesVM.EvidenceSources: TArray<TEvidenceSource>;
var
  L: TList<TEvidenceSource>;
  Seen: TDictionary<Integer, Boolean>;
  Kids: TObjectDictionary<Integer, TList<TEvidenceSource>>;

  function Src(AItemId, ADepth: Integer; const ACaption: string): TEvidenceSource;
  begin
    Result.ItemId := AItemId;
    Result.Depth := ADepth;
    Result.Caption := ACaption;
  end;

  // Every live, readable descendant of ARoot, level by level (one query per
  // level and IN_CHUNK ids), into Kids (parent id -> children in tree order).
  // A Folder-level item cannot be cited (the model refuses it, review U60):
  // it is walked through but not listed, its children shown in its place.
  procedure LoadSubtree(ARoot: Integer);
  var
    Frontier, Next: TList<Integer>;
    ListedParent: TDictionary<Integer, Integer>;   // folder id -> the parent its children list under
    Chunk: TArray<Variant>;
    I, N, K, Id, Pid, Up, ProjectId: Integer;
    Rows: TObjectList<TCriteriaResult>;
    Row: TCriteriaResult;
    Lst: TList<TEvidenceSource>;
  begin
    Frontier := TList<Integer>.Create;
    Next := TList<Integer>.Create;
    ListedParent := TDictionary<Integer, Integer>.Create;
    try
      Frontier.Add(ARoot);
      while Frontier.Count > 0 do
      begin
        Next.Clear;
        I := 0;
        while I < Frontier.Count do
        begin
          N := Frontier.Count - I;
          if N > IN_CHUNK then
            N := IN_CHUNK;
          SetLength(Chunk, N);
          for K := 0 to N - 1 do
            Chunk[K] := Frontier[I + K];
          Inc(I, N);
          Rows := FManager.Find<TItem>
            .Select(TProjections.ProjectionList
              .Add(TProjections.Prop('Id').As_('Id'))
              .Add(TProjections.Prop('ParentID').As_('Pid'))
              .Add(TProjections.Prop('ProjectID').As_('Prj'))
              .Add(TProjections.Prop('Title').As_('T'))
              .Add(TProjections.Prop('Level').As_('Lvl')))
            .Where(Linq['ParentID']._In(Chunk) and (Linq['IsDeleted'] = False))
            .OrderBy('SortOrder')
            .OrderBy('Id')
            .ListValues;
          try
            for Row in Rows do
            begin
              Id := Row.Values['Id'];
              Pid := Row.Values['Pid'];
              ProjectId := Row.Values['Prj'];
              if Seen.ContainsKey(Id) or (Id = Pid) or not CanReadProject(ProjectId) then
                Continue;
              Seen.Add(Id, True);
              Next.Add(Id);
              if ListedParent.TryGetValue(Pid, Up) then
                Pid := Up;
              if Integer(Row.Values['Lvl']) = Ord(TItemLevel.Folder) then
              begin
                ListedParent.Add(Id, Pid);
                Continue;
              end;
              if not Kids.TryGetValue(Pid, Lst) then
              begin
                Lst := TList<TEvidenceSource>.Create;
                Kids.Add(Pid, Lst);
              end;
              Lst.Add(Src(Id, 0, VarToStr(Row.Values['T'])));
            end;
          finally
            Rows.Free;
          end;
        end;
        Frontier.Clear;
        Frontier.AddRange(Next);
      end;
    finally
      ListedParent.Free;
      Next.Free;
      Frontier.Free;
    end;
  end;

  procedure Emit(AParent, ADepth: Integer);
  var
    Lst: TList<TEvidenceSource>;
    S: TEvidenceSource;
  begin
    if not Kids.TryGetValue(AParent, Lst) then
      Exit;
    for S in Lst do
    begin
      L.Add(Src(S.ItemId, ADepth, S.Caption));
      Emit(S.ItemId, ADepth + 1);
    end;
  end;

var
  I, ProjectId: Integer;
  Title: string;
  R: THypothesisRunView;
begin
  if not FHasDetail then
    Exit(nil);
  L := TList<TEvidenceSource>.Create;
  Seen := TDictionary<Integer, Boolean>.Create;
  Kids := TObjectDictionary<Integer, TList<TEvidenceSource>>.Create([doOwnsValues]);
  try
    for I := 0 to High(FDetail.Runs) do
    begin
      R := FDetail.Runs[I];
      if not RunReadable(I) or Seen.ContainsKey(R.ItemId) then
        Continue;
      // Live, now: the detail's Missing flag comes from the session cache.
      if not LiveItem(R.ItemId, Title, ProjectId) or not CanReadProject(ProjectId) then
        Continue;
      Seen.Add(R.ItemId, True);
      L.Add(Src(R.ItemId, 0, Title));
      Kids.Clear;
      LoadSubtree(R.ItemId);
      Emit(R.ItemId, 1);
    end;
    Result := L.ToArray;
  finally
    Kids.Free;
    Seen.Free;
    L.Free;
  end;
end;

function THypothesesVM.EvidenceChoicesFor(AItemId: Integer): TArray<TEvidenceChoice>;
var
  L: TList<TEvidenceChoice>;
  C: TEvidenceChoice;
  Title: string;
  ProjectId: Integer;
  Files: TList<unit_Item.TFile>;
  Fl: unit_Item.TFile;
  Values: TList<TValue>;
  V: TValue;
  VT: TValueType;
begin
  if not LiveItem(AItemId, Title, ProjectId) or not CanReadProject(ProjectId) then
    Exit(nil);
  L := TList<TEvidenceChoice>.Create;
  try
    C := Default(TEvidenceChoice);
    C.Kind := eckWholeItem;
    C.ItemId := AItemId;
    C.Caption := 'Item';
    L.Add(C);

    // Queried by item id and Refreshing - never TItem.Files/Values, which
    // this long-lived manager loads once and never updates (pre-flight C6).
    Files := FManager.Find<unit_Item.TFile>
      .CreateAlias('Item', 'i')
      .Where(Linq['i.Id'] = AItemId)
      .OrderBy('Id')
      .Refreshing
      .List;
    try
      for Fl in Files do
      begin
        C := Default(TEvidenceChoice);
        C.Kind := eckFile;
        C.ItemId := AItemId;
        C.FileId := Fl.Id;
        C.Caption := FileDisplayName(Fl);
        L.Add(C);
      end;
    finally
      Files.Free;
    end;

    Values := FManager.Find<TValue>
      .CreateAlias('Item', 'i')
      .Where(Linq['i.Id'] = AItemId)
      .OrderBy('Id')
      .Refreshing
      .List;
    try
      for V in Values do
      begin
        C := Default(TEvidenceChoice);
        C.Kind := eckValue;
        C.ItemId := AItemId;
        C.ValueId := V.Id;
        VT := V.ValueType;
        if VT = nil then
          C.Caption := ValueText('Value', '', True, V.Value)
        else
          C.Caption := ValueText(ValueTypeName(VT), VT.Units, True, V.Value);
        L.Add(C);
      end;
    finally
      Values.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function THypothesesVM.ApprovedInProject(AProjectId: Integer): TArray<THypothesisSummary>;
var
  Flt: THypothesisFilter;
begin
  Flt := THypothesisFilter.All;
  Flt.ProjectId := AProjectId;
  Flt.Statuses := [hsApproved];
  Result := FModel.List(FUser, Flt);
end;

function THypothesesVM.AttachableInProject(AProjectId: Integer): TArray<THypothesisSummary>;
var
  Flt: THypothesisFilter;
  OwnProposed: TArray<THypothesisSummary>;
begin
  Result := ApprovedInProject(AProjectId);
  Flt := THypothesisFilter.All;
  Flt.ProjectId := AProjectId;
  Flt.Statuses := [hsProposed];
  Flt.AuthorId := FUser.Id;
  OwnProposed := FModel.List(FUser, Flt);
  Result := Result + OwnProposed;
end;

{ Wording }

class function THypothesesVM.StatusCaption(const S: THypothesisSummary): string;
begin
  // hypView.ts statusChip.
  case S.Status of
    hsProposed: Result := 'Needs approval';
    hsInReview: Result := 'Needs acceptance';
    hsAccepted: Result := 'Accepted';
    hsRejected: Result := 'Rejected';
    hsAbandoned: Result := 'Abandoned';
    hsApproved:
      case S.Derived of
        hdsWaitingForMeasurement: Result := 'In the lab ' + MIDDOT + ' no evidence yet';
        hdsReadyToConclude: Result := 'In the lab ' + MIDDOT + ' evidence in';
      else
        Result := 'Not started';
      end;
  else
    Result := HypothesisStatusNames[S.Status];
  end;
end;

class function THypothesesVM.OutcomeCaption(const D: THypothesisDetail): string;
begin
  // The outcome belongs to a submitted or accepted conclusion; an Approved
  // node carrying one is a returned draft (13C ruling).
  if D.HasOutcome and (D.Summary.Status in [hsInReview, hsAccepted]) then
    Result := HypothesisOutcomeNames[D.Outcome]
  else
    Result := '';
end;

class function THypothesesVM.WaitingText(AStatus: THypothesisStatus): string;
begin
  // experimentParts.ts WAITING_TEXT.
  case AStatus of
    hsProposed: Result := 'Waiting for an approver.';
    hsInReview: Result := 'Waiting for the conclusion to be accepted.';
    hsApproved: Result := 'Waiting for runs, evidence and a conclusion.';
  else
    Result := 'Closed.';
  end;
end;

class function THypothesesVM.GateCaption(AFrom, ATo: THypothesisStatus): string;
begin
  // hypotheses.ts gateLabel.
  case ATo of
    hsRejected: Result := 'Reject';
    hsAccepted: Result := 'Accept';
    hsApproved:
      if AFrom = hsInReview then
        Result := 'Return for more work'
      else
        Result := 'Approve';
  else
    Result := HypothesisStatusNames[ATo];
  end;
end;

class function THypothesesVM.GateHelp(AFrom, ATo: THypothesisStatus): string;
begin
  // hypView.ts gateHelp.
  case ATo of
    hsRejected: Result := 'Closes it. A reason is required.';
    hsAccepted: Result := 'Seals the result: it can no longer change, and cited items can''t be deleted.';
    hsApproved:
      if AFrom = hsInReview then
        Result := 'Sends it back for more work. A comment is required.'
      else
        Result := 'Work can start.';
  else
    Result := '';
  end;
end;

class function THypothesesVM.GateCommentHint(AFrom: THypothesisStatus;
  ANeedsComment: Boolean): string;
begin
  // experimentParts.ts commentPlaceholder.
  if not ANeedsComment then
    Result := 'Comment (optional)'
  else if AFrom = hsProposed then
    Result := 'Reason (required to reject)'
  else
    Result := 'Comment (required to return)';
end;

class function THypothesesVM.CommentRequired(AFrom, ATo: THypothesisStatus): Boolean;
begin
  // hypotheses.ts commentRequired.
  Result := (ATo = hsRejected) or ((AFrom = hsInReview) and (ATo = hsApproved));
end;

class function THypothesesVM.HistorySentence(AOld, ANew: THypothesisStatus): string;
begin
  // hypView.ts historySentence - same order of tests.
  if ANew = hsProposed then Exit('proposed it');
  if (AOld = hsProposed) and (ANew = hsApproved) then Exit('approved the proposal');
  if (AOld = hsInReview) and (ANew = hsApproved) then Exit('returned it for more work');
  if ANew = hsRejected then Exit('rejected the proposal');
  if ANew = hsInReview then Exit('submitted the conclusion');
  if ANew = hsAccepted then Exit('accepted the conclusion');
  if ANew = hsAbandoned then Exit('abandoned it');
  Result := Format('moved it from %s to %s',
    [HypothesisStatusNames[AOld], HypothesisStatusNames[ANew]]);
end;

class function THypothesesVM.SealText(AState: THypSealState): string;
begin
  case AState of
    hssIntact: Result := 'Sealed ' + CHECKMARK;
    hssTampered: Result := 'Seal broken: this accepted record changed after it ' +
      'was sealed. Treat its content as unverified.';
  else
    Result := '';
  end;
end;

class function THypothesesVM.EvidenceBadge(const E: THypothesisEvidenceView): string;
begin
  if E.Missing then
    Result := 'missing'
  else if E.Changed then
    Result := 'changed'
  else
    Result := '';
end;

class function THypothesesVM.RunBadge(const R: THypothesisRunView): string;
begin
  // The web's run row: only a "missing" chip.
  if R.Missing then
    Result := 'missing'
  else
    Result := '';
end;

class function THypothesesVM.LastReturn(const D: THypothesisDetail;
  out H: THypothesisHistoryView): Boolean;
begin
  // hypView.ts lastReturn. History is ordered oldest first (ChangedDate, Id).
  H := Default(THypothesisHistoryView);
  if (D.Summary.Status <> hsApproved) or (Length(D.History) = 0) then
    Exit(False);
  H := D.History[High(D.History)];
  Result := (H.OldStatus = hsInReview) and (H.NewStatus = hsApproved);
  if not Result then
    H := Default(THypothesisHistoryView);
end;

class function THypothesesVM.FormatShortDate(ALocal, ANowLocal: TDateTime): string;
begin
  // hypView.ts formatShortDate: "15 Mar", or "15 Mar 2025" in another year.
  Result := Format('%d %s', [DayOf(ALocal), MONTHS[MonthOf(ALocal)]]);
  if YearOf(ALocal) <> YearOf(ANowLocal) then
    Result := Result + ' ' + IntToStr(YearOf(ALocal));
end;

class function THypothesesVM.ReturnedNotice(const H: THypothesisHistoryView;
  const AByName: string; ANowLocal: TDateTime): string;
begin
  Result := Format('Returned for more work on %s by %s',
    [FormatShortDate(FromUTC(H.ChangedDate), ANowLocal), AByName]);
  if H.Comment <> '' then
    Result := Result + ': "' + H.Comment + '"';
end;

class function THypothesesVM.AgeText(AWhenUtc, ANowUtc: TDateTime): string;
var
  Sec: Double;
  Days: Integer;
begin
  // hypView.ts formatAge, ported: seconds-based buckets (not calendar days),
  // clamped at 0 for future timestamps (clock skew).
  Sec := (ANowUtc - AWhenUtc) * SecsPerDay;
  if Sec < 0 then
    Sec := 0;
  if Sec < 60 then
    Exit('just now');
  if Sec < 3600 then
    Exit(IntToStr(Trunc(Sec / 60)) + ' min ago');
  if Sec < 86400 then
    Exit(IntToStr(Trunc(Sec / 3600)) + ' h ago');
  Days := Trunc(Sec / 86400);
  if Days = 1 then
    Exit('yesterday');
  if Days < 7 then
    Exit(IntToStr(Days) + ' days ago');
  Result := FormatShortDate(FromUTC(AWhenUtc), FromUTC(ANowUtc));
end;

class function THypothesesVM.FormatNumber(AValue: Double): string;
begin
  // hypView.ts num: whole numbers from 100 up, else 4 significant digits
  // with trailing zeros dropped.
  if Abs(AValue) >= 100 then
    Result := FormatFloat('0', AValue, TFormatSettings.Invariant)
  else
    Result := FloatToStrF(AValue, ffGeneral, 4, 0, TFormatSettings.Invariant);
end;

{ Commands }

function THypothesesVM.ProposeRoot(const ATitle, AStatement: string;
  AKeyValueTypeId: Integer): TVMOutcome;
begin
  Result := Run(
    function: Integer
    begin
      // Device 0: the desktop has no device key (spec D9).
      Result := FModel.Propose(FUser, 0, FProjectId, 0, ATitle, AStatement, '',
        AKeyValueTypeId).Id;
    end);
end;

function THypothesesVM.ProposeChild(AParentId: Integer; const ATitle,
  AStatement, AChange: string; AKeyValueTypeId: Integer): TVMOutcome;
begin
  Result := Run(
    function: Integer
    begin
      Result := FModel.Propose(FUser, 0, FProjectId, AParentId, ATitle,
        AStatement, AChange, AKeyValueTypeId).Id;
    end);
end;

function THypothesesVM.ProposeFromItem(AItemId: Integer; const ATitle,
  AStatement: string; AKeyValueTypeId: Integer): TVMOutcome;
var
  Title: string;
  ItemProjectId: Integer;
begin
  if not LiveItem(AItemId, Title, ItemProjectId) or not CanReadProject(ItemProjectId) then
    Exit(Fail(Format('Item %d not found.', [AItemId])));
  Result := Run(
    function: Integer
    begin
      Result := FModel.Propose(FUser, 0, ItemProjectId, 0, ATitle, AStatement,
        '', AKeyValueTypeId).Id;
      // Switch to the item's project only once the proposal exists: a
      // refusal leaves the view where it was.
      if ItemProjectId <> FProjectId then
      begin
        FProjectId := ItemProjectId;
        FGateComment := '';
      end;
    end);
  if not Result.Ok then
    Exit;
  // The author may attach References while Proposed (Plan 1
  // CanChangeReferences), so the starting item becomes a real Reference row.
  Result := AttachItem(FSelectedId, AItemId, hrrReference);
  if not Result.Ok then
    Result.Message := 'The hypothesis was proposed, but the item could not be ' +
      'attached as a Reference: ' + Result.Message;
end;

function THypothesesVM.SaveEdit(const ATitle, AStatement, AChange: string;
  AKeyValueTypeId: Integer): TVMOutcome;
var
  Id, V: Integer;
begin
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  // Copies: FSelectedId / FDetail change during Reload.
  Id := FSelectedId;
  V := FDetail.Summary.Version;
  Result := Run(
    function: Integer
    begin
      FModel.UpdateProposed(FUser, Id, V, ATitle, AStatement, AChange, AKeyValueTypeId);
      Result := 0;
    end);
end;

function THypothesesVM.AttachItem(AHypothesisId, AItemId: Integer;
  ARole: THypothesisRunRole): TVMOutcome;
begin
  Result := Run(
    function: Integer
    begin
      FModel.AttachRun(FUser, AHypothesisId, AItemId, ARole);
      Result := AHypothesisId;
    end);
end;

function THypothesesVM.DetachItem(AItemId: Integer): TVMOutcome;
var
  Id: Integer;
begin
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  Id := FSelectedId;
  Result := Run(
    function: Integer
    begin
      FModel.DetachRun(FUser, Id, AItemId);
      Result := 0;
    end);
end;

function THypothesesVM.DetachRunAt(AIndex: Integer): TVMOutcome;
begin
  if not FHasDetail or (AIndex < 0) or (AIndex > High(FRunItemIds)) then
    Exit(Fail('Select a run first.'));
  Result := DetachItem(FRunItemIds[AIndex]);
end;

function THypothesesVM.Cite(const AChoice: TEvidenceChoice;
  const ANote: string): TVMOutcome;
var
  Id: Integer;
  C: TEvidenceChoice;
begin
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  Id := FSelectedId;
  C := AChoice;
  Result := Run(
    function: Integer
    begin
      FModel.CiteEvidence(FUser, Id, C.ItemId, C.FileId, C.ValueId, ANote);
      Result := 0;
    end);
end;

function THypothesesVM.RemoveEvidence(AEvidenceId: Integer): TVMOutcome;
var
  Id: Integer;
begin
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  Id := FSelectedId;
  Result := Run(
    function: Integer
    begin
      FModel.RemoveEvidence(FUser, Id, AEvidenceId);
      Result := 0;
    end);
end;

function THypothesesVM.Submit(const AConclusion: string;
  AOutcome: Nullable<THypothesisOutcome>): TVMOutcome;
var
  Id, V: Integer;
  Outcome: THypothesisOutcome;
begin
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  if not AOutcome.HasValue then
    Exit(Fail(RefusalText(hrNeedsOutcome)));
  Outcome := AOutcome.Value;
  Id := FSelectedId;
  V := FDetail.Summary.Version;
  Result := Run(
    function: Integer
    begin
      FModel.SubmitConclusion(FUser, 0, Id, V, AConclusion, Outcome);
      FHasDraft := False;               // sent: the stored conclusion from now on
      ClearDiscardedDraft;
      Result := 0;
    end);
end;

function THypothesesVM.Abandon(const AComment: string): TVMOutcome;
var
  Id, V: Integer;
begin
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  Id := FSelectedId;
  V := FDetail.Summary.Version;
  Result := Run(
    function: Integer
    begin
      FModel.Abandon(FUser, 0, Id, V, AComment);
      FHasDraft := False;               // our own step ended it; nothing to report
      ClearDiscardedDraft;
      Result := 0;
    end);
end;

function THypothesesVM.Gate(ATo: THypothesisStatus;
  const AComment: string): TVMOutcome;
var
  Id, V: Integer;
begin
  FGateComment := AComment;             // kept if anything below fails
  if not FHasDetail then
    Exit(Fail('Select a hypothesis first.'));
  if GateNeedsComment(ATo) and (Trim(AComment) = '') then
    Exit(Fail('A comment is required for this step.'));
  Id := FSelectedId;
  V := FDetail.Summary.Version;
  Result := Run(
    function: Integer
    begin
      // A human clicked this gate; device 0: the desktop has no device key.
      FGates.Transition(FUser, 0, Id, V, ATo, AComment);
      Result := 0;
    end);
  if Result.Ok then
    FGateComment := '';
end;

end.
