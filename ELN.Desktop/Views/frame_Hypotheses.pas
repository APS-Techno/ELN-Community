unit frame_Hypotheses;

{
  Desktop Hypotheses view (spec 10): the project's hypotheses as a tree on the
  left, the selected one on the right, and the decision panel (the two human
  gates) at the bottom for the people the approval policy names.

  All decisions and all user-visible wording are in THypothesesVM (tested);
  this frame only renders it and forwards clicks. The wording follows the
  web's decision page (ELN.WebApp/src/screens/experimentParts.ts): a plain
  status line, "We expected" / "What changes", one sentence per decision
  button, and a plain history (pre-flight C9).

  Unreadable runs and evidence (another project the user cannot read) show
  "Not readable", no warning and no navigation (C7): rows are addressed by
  index through the VM (RunNavigateItemId, EvidenceNavigateItemId,
  DetachRunAt) - never Detail.Runs[i].ItemId, which the VM zeroes for them.

  Embedded inline in frame_ContentViewer.dfm (HypothesesCard). The VM is
  created lazily on first OpenProject, because the frame exists before
  login, and freed by ResetSession before logout frees Model.

  Source is ASCII only: non-ASCII characters are #$ escapes.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls,
  VirtualTrees.BaseAncestorVCL, VirtualTrees.BaseTree, VirtualTrees.AncestorVCL,
  VirtualTrees, VirtualTrees.Types,
  RzPanel, RzLabel, RzCommon,
  Aurelius.Types.Nullable,
  unit_Hypothesis, unit_HypothesisModel, unit_HypothesesVM, unit_TreeLook;

type
  /// <summary>Same signature as the dashboard's navigation event
  /// (frame_Dashboard), declared here to avoid depending on it.</summary>
  THypNavigateItemEvent = procedure(Sender: TObject; ProjectId, FolderId,
    ItemId: Integer) of object;
  /// <summary>The item selected in the item tree now; 0 = none.</summary>
  THypSelectedItemFunc = function: Integer of object;

  PHypNodeData = ^THypNodeData;
  THypNodeData = record
    NodeIndex: Integer;   // index into VM.Nodes
  end;

  TframeHypotheses = class(TFrame)
    pnlToolbar: TRzPanel;
    lblProject: TLabel;
    pnlToolbarButtons: TPanel;
    btnNewRoot: TButton;
    btnNewChild: TButton;
    btnEdit: TButton;
    btnAbandon: TButton;
    btnRefresh: TButton;
    splMain: TSplitter;
    vstHypotheses: TVirtualStringTree;
    lblEmpty: TLabel;
    pnlDetail: TRzPanel;
    lblTitle: TLabel;
    lblStatus: TLabel;
    lblWarning: TLabel;
    lblNotice: TLabel;
    pcDetail: TPageControl;
    tsOverview: TTabSheet;
    lblKeyValue: TLabel;
    lblStatementCap: TLabel;
    memStatement: TMemo;
    pnlChange: TPanel;
    lblChangeCap: TLabel;
    memChange: TMemo;
    tsRuns: TTabSheet;
    lvRuns: TListView;
    pnlRunButtons: TRzPanel;
    lblRunsHint: TLabel;
    btnAttachSelected: TButton;
    btnDetach: TButton;
    tsEvidence: TTabSheet;
    lvEvidence: TListView;
    pnlEvidenceButtons: TRzPanel;
    lblEvidenceHint: TLabel;
    btnCite: TButton;
    btnRemoveEvidence: TButton;
    tsConclusion: TTabSheet;
    lblConclusionCap: TLabel;
    memConclusion: TMemo;
    pnlConclusionButtons: TRzPanel;
    lblOutcome: TLabel;
    cbOutcome: TComboBox;
    btnSubmit: TButton;
    tsHistory: TTabSheet;
    lvHistory: TListView;
    pnlGate: TRzPanel;
    lblGate: TLabel;
    lblGateHelp1: TLabel;
    lblGateHelp2: TLabel;
    lblGateHint: TLabel;
    memGateComment: TMemo;
    pnlGateButtons: TRzPanel;
    btnGatePrimary: TButton;
    btnGateSecondary: TButton;
    procedure btnNewRootClick(Sender: TObject);
    procedure btnNewChildClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnAbandonClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure vstHypothesesGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure vstHypothesesGetCellText(Sender: TCustomVirtualStringTree;
      var E: TVSTGetCellTextEventArgs);
    procedure vstHypothesesFocusChanged(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex);
    procedure vstHypothesesBeforeCellPaint(Sender: TBaseVirtualTree;
      TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
    procedure vstHypothesesAfterCellPaint(Sender: TBaseVirtualTree;
      TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      CellRect: TRect);
    procedure vstHypothesesPaintText(Sender: TBaseVirtualTree;
      const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
      TextType: TVSTTextType);
    procedure lvRunsCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvRunsDblClick(Sender: TObject);
    procedure btnAttachSelectedClick(Sender: TObject);
    procedure btnDetachClick(Sender: TObject);
    procedure lvEvidenceCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvEvidenceDblClick(Sender: TObject);
    procedure btnCiteClick(Sender: TObject);
    procedure btnRemoveEvidenceClick(Sender: TObject);
    procedure memConclusionChange(Sender: TObject);
    procedure cbOutcomeChange(Sender: TObject);
    procedure btnSubmitClick(Sender: TObject);
    procedure memGateCommentChange(Sender: TObject);
    procedure btnGateClick(Sender: TObject);
  private
    FVM: THypothesesVM;
    FLook: TTreeLook;             // shared tree look (unit_TreeLook): rows by status
    FFilling: Boolean;            // programmatic control updates: ignore change events
    FSelecting: Boolean;          // a tree click is selecting: the node list is unchanged
    FShownId: Integer;            // the hypothesis the detail currently shows
    FDraftCopied: Boolean;        // FVM.DiscardedDraftText went to the clipboard
    FOnNavigateItem: THypNavigateItemEvent;
    FOnGetSelectedItemId: THypSelectedItemFunc;
    FOnRunsChanged: TNotifyEvent;
    FOnDecisionsChanged: TNotifyEvent;
    function RowColor(Node: PVirtualNode): TColor;
    procedure EnsureVM;
    procedure FillTree;
    procedure ShowDetail;
    function DraftDiscardedNotice: string;
    procedure ShowRows;
    procedure ShowGate;
    procedure ShowOutcome(const O: TVMOutcome);
    procedure RunsChanged;
    procedure DecisionsChanged;
    procedure ProposeOutcome(const O: TVMOutcome);
    procedure NavigateTo(AItemId: Integer);
    procedure VMChanged(Sender: TObject);
    function OrderedGateTargets: TArray<THypothesisStatus>;
    class procedure ShowAtTop(ACtrl: TControl; AVisible: Boolean;
      AAfter: TControl); static;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenProject(AProjectId: Integer; AHypothesisId: Integer = 0);
    procedure ResetSession;
    property OnNavigateItem: THypNavigateItemEvent read FOnNavigateItem write FOnNavigateItem;
    /// <summary>"Attach selected item..." attaches what this returns: the
    /// host wires it to the item tree's current selection.</summary>
    property OnGetSelectedItemId: THypSelectedItemFunc read FOnGetSelectedItemId
      write FOnGetSelectedItemId;
    /// <summary>Raised after a Run was attached or removed, so the host can
    /// refresh the item tree's HYP badges (pre-flight C20). References never
    /// carry the badge, so attaching or removing one does not raise it.</summary>
    property OnRunsChanged: TNotifyEvent read FOnRunsChanged write FOnRunsChanged;
    /// <summary>Raised after a step that can change who a hypothesis waits
    /// on - a gate (Approve/Reject/Accept/Return), Submit, a proposal, or
    /// Abandon - so the host can refresh the dashboard's "Waiting for You"
    /// list (Task 10). Never reloads the item tree.</summary>
    property OnDecisionsChanged: TNotifyEvent read FOnDecisionsChanged
      write FOnDecisionsChanged;
  end;

implementation

{$R *.dfm}

uses
  Vcl.Clipbrd,
  unit_DataModel,
  unit_TreeAppearance,
  unit_Project,
  unit_Item,
  unit_HypothesisRules,
  dlg_HypothesisEdit,
  dlg_HypothesisPick,
  dlg_EvidencePick;

const
  SEP = '  ' + #$00B7 + '  ';     // "  .  " with a middle dot, as the web's status line
  EMDASH = #$2014;
  AMBER = $000080D0;              // BGR, as the dashboard's "changed" colour
  // TListItem.Data of a run / evidence row: how to colour it (from the VM's
  // row flags, never from the badge text).
  ROW_OK = 0;
  ROW_NOT_READABLE = 1;
  ROW_MISSING = 2;
  ROW_CHANGED = 3;

function RowColour(AItem: TListItem; var AColour: TColor): Boolean;
begin
  Result := True;
  case NativeInt(AItem.Data) of
    ROW_NOT_READABLE: AColour := clGrayText;
    ROW_MISSING:      AColour := clRed;
    ROW_CHANGED:      AColour := AMBER;
  else
    Result := False;
  end;
end;

{ TframeHypotheses }

constructor TframeHypotheses.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);   // TFrame has no OnCreate in Delphi 13: set up here
  pcDetail.ActivePage := tsOverview;
  cbOutcome.ItemIndex := -1;    // no outcome chosen until the user picks one
  memGateComment.MaxLength := MAX_HYP_COMMENT;   // UTF-16 units: never more than the model allows
  pnlDetail.Visible := False;
  lblEmpty.Visible := True;
  // Every hypothesis can hold children; Focus selects the row, and the
  // focus-change event already shows it.
  FLook := TTreeLook.Create(vstHypotheses, RowColor,
    function(Node: PVirtualNode): Boolean
    begin
      Result := True;
    end,
    nil);
end;

destructor TframeHypotheses.Destroy;
begin
  FLook.Free;   // before the tree goes: it restores the tree's WindowProc
  FreeAndNil(FVM);
  inherited;
end;

procedure TframeHypotheses.EnsureVM;
begin
  if FVM = nil then
  begin
    FVM := THypothesesVM.Create(Model.Manager, Model.User, Model.Access);
    FVM.OnChanged := VMChanged;
  end;
end;

procedure TframeHypotheses.ResetSession;
begin
  FreeAndNil(FVM);
  FShownId := 0;
  FLook.ClearHover;
  vstHypotheses.Clear;
  pnlDetail.Visible := False;
  lblEmpty.Visible := True;
  lblProject.Caption := 'Hypotheses';
end;

procedure TframeHypotheses.OpenProject(AProjectId, AHypothesisId: Integer);
var
  P: TProject;
begin
  EnsureVM;
  P := Model.Manager.Find<TProject>(AProjectId);
  if Assigned(P) then
    lblProject.Caption := 'Hypotheses in ' + P.Title
  else
    lblProject.Caption := 'Hypotheses';
  lblProject.Hint := lblProject.Caption;
  FVM.OpenProject(AProjectId, AHypothesisId);
end;

procedure TframeHypotheses.VMChanged(Sender: TObject);
begin
  // A tree click only selects: the node list is the same, and rebuilding the
  // tree inside its own focus-change event would free the node it is handling.
  if FSelecting then
    vstHypotheses.Invalidate
  else
    FillTree;
  ShowDetail;
end;

procedure TframeHypotheses.FillTree;

  procedure AddChildren(AParent: PVirtualNode; const AIndexes: TArray<Integer>);
  var
    I: Integer;
    Node: PVirtualNode;
    Data: PHypNodeData;
  begin
    for I in AIndexes do
    begin
      Node := vstHypotheses.AddChild(AParent);
      Data := vstHypotheses.GetNodeData(Node);
      Data.NodeIndex := I;
      AddChildren(Node, FVM.ChildIndexes(I));
      if FVM.Nodes[I].Id = FVM.SelectedId then
      begin
        vstHypotheses.FocusedNode := Node;
        vstHypotheses.Selected[Node] := True;
      end;
    end;
  end;

begin
  FFilling := True;
  vstHypotheses.BeginUpdate;
  try
    FLook.ClearHover;
    vstHypotheses.Clear;
    AddChildren(nil, FVM.RootIndexes);
    vstHypotheses.FullExpand;
  finally
    vstHypotheses.EndUpdate;
    FFilling := False;
  end;
  if Assigned(vstHypotheses.FocusedNode) then
    vstHypotheses.ScrollIntoView(vstHypotheses.FocusedNode, False);
end;

class procedure TframeHypotheses.ShowAtTop(ACtrl: TControl; AVisible: Boolean;
  AAfter: TControl);
begin
  // An alTop control that is hidden and shown again keeps its old Top and
  // can land below its neighbours; put it back right after AAfter (or first).
  if AVisible and not ACtrl.Visible then
  begin
    if AAfter = nil then
      ACtrl.Top := 0
    else
      ACtrl.Top := AAfter.Top + AAfter.Height + 1;
  end;
  ACtrl.Visible := AVisible;
end;

procedure TframeHypotheses.ShowDetail;
var
  D: THypothesisDetail;
  S, Outcome, Warning, KeyValue, Notice, DraftNotice: string;
  DraftKept: Boolean;
begin
  if FVM = nil then
    Exit;
  DraftNotice := DraftDiscardedNotice;
  // The clipboard failed: the text stays on screen until the user edits it
  // or moves on (the VM keeps it that long).
  DraftKept := (FVM.DiscardedDraftText <> '') and not FDraftCopied;
  btnNewRoot.Enabled := FVM.CanPropose;
  btnNewChild.Enabled := FVM.CanPropose and FVM.HasDetail and
    not (FVM.Detail.Summary.Status in [hsRejected, hsAbandoned]);
  btnEdit.Enabled := FVM.CanEditSelected;
  btnAbandon.Enabled := FVM.CanAbandon;

  pnlDetail.Visible := FVM.HasDetail;
  lblEmpty.Visible := not FVM.HasDetail;
  if not FVM.HasDetail then
  begin
    if FVM.SelectionLost then
      S := 'The hypothesis you were viewing is no longer available to you.'
    else if Length(FVM.Nodes) > 0 then
      S := 'Select a hypothesis on the left.'
    else if FVM.CanPropose then
      S := 'This project has no hypotheses yet.' + sLineBreak +
        'Click "New hypothesis..." to propose one.'
    else
      S := 'This project has no hypotheses yet.';
    // A draft whose node vanished (access removed, deleted): say so here,
    // and show the text itself if it could not go to the clipboard.
    if DraftKept then
      S := DRAFT_DISCARDED_TEXT + ' ' + DRAFT_NOT_COPIED_TEXT + sLineBreak +
        sLineBreak + FVM.DiscardedDraftText + sLineBreak + sLineBreak + S
    else if DraftNotice <> '' then
      S := DraftNotice + sLineBreak + sLineBreak + S;
    lblEmpty.Caption := S;
    FShownId := 0;
    Exit;
  end;

  D := FVM.Detail;
  if D.Summary.Id <> FShownId then
    pcDetail.ActivePage := tsOverview;

  FFilling := True;
  try
    lblTitle.Caption := Format('%s  (#%d)', [D.Summary.Title, D.Summary.Id]);

    // Status line: the plain status word, the outcome of a submitted or
    // accepted conclusion, the seal, and - when this user has nothing to
    // decide - what the hypothesis is waiting for.
    S := THypothesesVM.StatusCaption(D.Summary);
    Outcome := THypothesesVM.OutcomeCaption(D);
    if Outcome <> '' then
      S := S + SEP + Outcome;
    if FVM.SealState = hssIntact then
      S := S + SEP + THypothesesVM.SealText(hssIntact);
    if Length(FVM.GateTargets) = 0 then
      S := S + SEP + THypothesesVM.WaitingText(D.Summary.Status);
    lblStatus.Caption := S;

    Warning := '';
    if FVM.SealState = hssTampered then
      Warning := THypothesesVM.SealText(hssTampered);
    if FVM.PolicyInvalid and (D.Summary.Status in [hsProposed, hsInReview]) then
    begin
      if Warning <> '' then
        Warning := Warning + sLineBreak;
      Warning := Warning + POLICY_INVALID_TEXT;
    end;
    lblWarning.Caption := Warning;
    ShowAtTop(lblWarning, Warning <> '', lblStatus);
    Notice := FVM.ReturnedNoticeText;
    if DraftNotice <> '' then
    begin
      if Notice <> '' then
        Notice := sLineBreak + Notice;
      Notice := DraftNotice + Notice;
    end;
    lblNotice.Caption := Notice;
    if lblWarning.Visible then
      ShowAtTop(lblNotice, lblNotice.Caption <> '', lblWarning)
    else
      ShowAtTop(lblNotice, lblNotice.Caption <> '', lblStatus);

    // Proposal
    KeyValue := FVM.KeyValueText(D.Summary);
    lblKeyValue.Caption := 'Key value: ' + KeyValue;
    ShowAtTop(lblKeyValue, KeyValue <> '', nil);
    memStatement.Text := D.Statement;
    memChange.Text := D.Change;
    pnlChange.Visible := Trim(D.Change) <> '';

    ShowRows;

    // Conclusion: a draft the user is typing survives a reload while the VM
    // says it can still be sent as-is (a refresh, the user's own attach);
    // otherwise the stored conclusion is shown.
    // A dropped draft that could not go to the clipboard stays on screen.
    if not FVM.HasConclusionDraft then
      if DraftKept then
        memConclusion.Text := FVM.DiscardedDraftText
      else
      begin
        memConclusion.Text := D.Conclusion;
        if D.HasOutcome then
          cbOutcome.ItemIndex := Ord(D.Outcome)
        else
          cbOutcome.ItemIndex := -1;    // no outcome stored: force a real choice
      end;
    memConclusion.ReadOnly := not FVM.CanSubmit;
    cbOutcome.Enabled := FVM.CanSubmit;
    btnSubmit.Enabled := FVM.CanSubmit;

    ShowGate;
  finally
    FFilling := False;
  end;
  FShownId := D.Summary.Id;
end;

function TframeHypotheses.DraftDiscardedNotice: string;
begin
  // Save a dropped draft's text once: a repaint or a later reload must not
  // copy it again over whatever the user has copied since.
  if (FVM.DiscardedDraftText <> '') and not FVM.DiscardedDraftSaved then
  begin
    try
      Clipboard.AsText := FVM.DiscardedDraftText;
      FDraftCopied := True;
    except
      FDraftCopied := False;             // clipboard locked: ShowDetail keeps it on screen
    end;
    FVM.DiscardedDraftSaved := True;
  end;
  Result := '';
  if (FVM.DiscardedDraftText <> '') and not FDraftCopied then
    Result := DRAFT_DISCARDED_TEXT + ' ' + DRAFT_KEPT_TEXT  // until the user edits it or moves on
  else if FVM.DraftDiscarded then
  begin
    Result := DRAFT_DISCARDED_TEXT;
    if FVM.DiscardedDraftText <> '' then
      Result := Result + ' ' + DRAFT_COPIED_TEXT;
  end;
end;

procedure TframeHypotheses.ShowRows;
var
  D: THypothesisDetail;
  Rows: TArray<THypHistoryRow>;
  H: THypHistoryRow;
  LI: TListItem;
  I: Integer;
begin
  D := FVM.Detail;

  // Rows are filled in Detail.Runs / Detail.Evidence order and the lists are
  // unsorted, so Selected.Index is the VM's row index. LI.Data holds the
  // row's ROW_* colour code.
  lvRuns.Items.BeginUpdate;
  try
    lvRuns.Items.Clear;
    for I := 0 to High(D.Runs) do
    begin
      LI := lvRuns.Items.Add;
      LI.Caption := FVM.RunCaption(I);
      if FVM.RunReadable(I) then
      begin
        LI.SubItems.Add(HypothesisRunRoleNames[D.Runs[I].Role]);
        LI.SubItems.Add(THypothesesVM.RunBadge(D.Runs[I]));
        if D.Runs[I].Missing then
          LI.Data := Pointer(ROW_MISSING)
        else
          LI.Data := Pointer(ROW_OK);
      end
      else
      begin
        LI.SubItems.Add('');
        LI.SubItems.Add('');
        LI.Data := Pointer(ROW_NOT_READABLE);
      end;
    end;
  finally
    lvRuns.Items.EndUpdate;
  end;
  tsRuns.Caption := Format('Runs (%d)', [Length(D.Runs)]);
  btnAttachSelected.Enabled := FVM.CanChangeRuns or FVM.CanAttachReferences;
  btnDetach.Enabled := FVM.CanChangeRuns or FVM.CanAttachReferences;

  lvEvidence.Items.BeginUpdate;
  try
    lvEvidence.Items.Clear;
    for I := 0 to High(D.Evidence) do
    begin
      LI := lvEvidence.Items.Add;
      LI.Caption := FVM.EvidenceItemCaption(I);
      LI.SubItems.Add(FVM.EvidenceWhat(I));
      if FVM.EvidenceReadable(I) then
      begin
        LI.SubItems.Add(D.Evidence[I].Note);
        LI.SubItems.Add(THypothesesVM.EvidenceBadge(D.Evidence[I]));
        if D.Evidence[I].Missing then
          LI.Data := Pointer(ROW_MISSING)
        else if D.Evidence[I].Changed then
          LI.Data := Pointer(ROW_CHANGED)
        else
          LI.Data := Pointer(ROW_OK);
      end
      else
      begin
        LI.SubItems.Add('');
        LI.SubItems.Add('');
        LI.Data := Pointer(ROW_NOT_READABLE);
      end;
    end;
  finally
    lvEvidence.Items.EndUpdate;
  end;
  tsEvidence.Caption := Format('Evidence (%d)', [Length(D.Evidence)]);
  btnCite.Enabled := FVM.CanChangeRuns;
  btnRemoveEvidence.Enabled := FVM.CanChangeRuns;

  Rows := FVM.HistoryRows;
  lvHistory.Items.BeginUpdate;
  try
    lvHistory.Items.Clear;
    for H in Rows do
    begin
      LI := lvHistory.Items.Add;
      LI.Caption := H.WhenText;
      LI.SubItems.Add(H.Who);
      LI.SubItems.Add(H.What);
      LI.SubItems.Add(H.Comment);
    end;
  finally
    lvHistory.Items.EndUpdate;
  end;
end;

function TframeHypotheses.OrderedGateTargets: TArray<THypothesisStatus>;
var
  Src: TArray<THypothesisStatus>;
  From: THypothesisStatus;
  I, N: Integer;

  function IsForward(T: THypothesisStatus): Boolean;
  begin
    Result := (T = hsAccepted) or ((T = hsApproved) and (From = hsProposed));
  end;

begin
  // The step that moves the work forward first (Approve, Accept), then the
  // one that stops or sends it back (Reject, Return), as the web's buttons.
  From := FVM.Detail.Summary.Status;
  Src := FVM.GateTargets;
  SetLength(Result, Length(Src));
  N := 0;
  for I := 0 to High(Src) do
    if IsForward(Src[I]) then
    begin
      Result[N] := Src[I];
      Inc(N);
    end;
  for I := 0 to High(Src) do
    if not IsForward(Src[I]) then
    begin
      Result[N] := Src[I];
      Inc(N);
    end;
end;

procedure TframeHypotheses.ShowGate;
var
  Targets: TArray<THypothesisStatus>;
  From, T: THypothesisStatus;
  NeedsComment: Boolean;

  function HelpLine(ATo: THypothesisStatus): string;
  begin
    Result := THypothesesVM.GateCaption(From, ATo) + ' ' + EMDASH + ' ' +
      THypothesesVM.GateHelp(From, ATo);
  end;

begin
  // Only the people the approval policy names for this gate get the panel;
  // everyone else reads what the hypothesis waits for in the status line.
  Targets := OrderedGateTargets;
  From := FVM.Detail.Summary.Status;
  pnlGate.Visible := Length(Targets) > 0;
  if not pnlGate.Visible then
    Exit;

  lblGate.Caption := DECISION_LABEL;
  lblGateHelp1.Caption := HelpLine(Targets[0]);
  btnGatePrimary.Caption := THypothesesVM.GateCaption(From, Targets[0]);
  btnGatePrimary.Tag := Ord(Targets[0]);
  btnGateSecondary.Visible := Length(Targets) > 1;
  if Length(Targets) > 1 then
  begin
    lblGateHelp2.Caption := HelpLine(Targets[1]);
    btnGateSecondary.Caption := THypothesesVM.GateCaption(From, Targets[1]);
    btnGateSecondary.Tag := Ord(Targets[1]);
  end;
  ShowAtTop(lblGateHelp2, Length(Targets) > 1, lblGateHelp1);

  NeedsComment := False;
  for T in Targets do
    if FVM.GateNeedsComment(T) then
      NeedsComment := True;
  lblGateHint.Caption := THypothesesVM.GateCommentHint(From, NeedsComment);
  if memGateComment.Text <> FVM.GateComment then
    memGateComment.Text := FVM.GateComment;
end;

procedure TframeHypotheses.ShowOutcome(const O: TVMOutcome);
begin
  if not O.Ok then
    MessageDlg(O.Message, mtWarning, [mbOK], 0);
end;

procedure TframeHypotheses.RunsChanged;
begin
  if Assigned(FOnRunsChanged) then
    FOnRunsChanged(Self);
end;

procedure TframeHypotheses.DecisionsChanged;
begin
  if Assigned(FOnDecisionsChanged) then
    FOnDecisionsChanged(Self);
end;

procedure TframeHypotheses.ProposeOutcome(const O: TVMOutcome);
begin
  ShowOutcome(O);
  if O.Ok then
    DecisionsChanged;   // a new proposal waits on an approver
end;

procedure TframeHypotheses.NavigateTo(AItemId: Integer);
var
  Item: TItem;
begin
  // 0 = the row is not readable or its item is gone: no navigation (C7).
  if (AItemId <= 0) or not Assigned(FOnNavigateItem) then
    Exit;
  // The item's own project and folder, as the eln:// link handler passes
  // them, so an item in a subfolder is found (pre-flight C18).
  Item := Model.Manager.Find<TItem>(AItemId);
  if (Item = nil) or Item.IsDeleted then
  begin
    MessageDlg('This item is no longer available.', mtInformation, [mbOK], 0);
    Exit;
  end;
  FOnNavigateItem(Self, Item.ProjectID, Item.FolderID, Item.Id);
end;

{ Tree }

{ Tree look }

// Row colours by status (unit_TreeAppearance).
function TframeHypotheses.RowColor(Node: PVirtualNode): TColor;
var
  Data: PHypNodeData;
begin
  Result := HypStatusColor(hsAbandoned);
  Data := vstHypotheses.GetNodeData(Node);
  if (FVM <> nil) and Assigned(Data) and (Data.NodeIndex <= High(FVM.Nodes)) then
    Result := HypStatusColor(FVM.Nodes[Data.NodeIndex].Status);
end;

procedure TframeHypotheses.vstHypothesesBeforeCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellPaintMode: TVTCellPaintMode; CellRect: TRect; var ContentRect: TRect);
begin
  FLook.BeforeCellPaint(TargetCanvas, Node, CellPaintMode, CellRect, ContentRect);
end;

procedure TframeHypotheses.vstHypothesesAfterCellPaint(Sender: TBaseVirtualTree;
  TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  CellRect: TRect);
begin
  FLook.AfterCellPaint(TargetCanvas, Node, Column, CellRect);
end;

procedure TframeHypotheses.vstHypothesesPaintText(Sender: TBaseVirtualTree;
  const TargetCanvas: TCanvas; Node: PVirtualNode; Column: TColumnIndex;
  TextType: TVSTTextType);
begin
  FLook.PaintText(TargetCanvas, Node, Column);
end;

procedure TframeHypotheses.vstHypothesesGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize := SizeOf(THypNodeData);
end;

procedure TframeHypotheses.vstHypothesesGetCellText(Sender: TCustomVirtualStringTree;
  var E: TVSTGetCellTextEventArgs);
var
  Data: PHypNodeData;
  S: THypothesisSummary;
begin
  E.CellText := '';
  Data := Sender.GetNodeData(E.Node);
  if (FVM = nil) or not Assigned(Data) or (Data.NodeIndex > High(FVM.Nodes)) then
    Exit;
  S := FVM.Nodes[Data.NodeIndex];
  case E.Column of
    0: E.CellText := S.Title;
    1: E.CellText := THypothesesVM.StatusCaption(S);
    2: E.CellText := FVM.KeyValueText(S);
  end;
end;

procedure TframeHypotheses.vstHypothesesFocusChanged(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex);
var
  Data: PHypNodeData;
begin
  if FFilling or (FVM = nil) or not Assigned(Node) then
    Exit;
  Data := Sender.GetNodeData(Node);
  if not Assigned(Data) or (Data.NodeIndex > High(FVM.Nodes)) then
    Exit;
  FSelecting := True;
  try
    FVM.Select(FVM.Nodes[Data.NodeIndex].Id);
  finally
    FSelecting := False;
  end;
end;

{ Toolbar }

procedure TframeHypotheses.btnNewRootClick(Sender: TObject);
var
  T, S, C: string;
  K: Integer;
begin
  if FVM = nil then
    Exit;
  T := ''; S := ''; C := ''; K := 0;
  if TdlgHypothesisEdit.Execute('New hypothesis', False, T, S, C, K) then
    ProposeOutcome(FVM.ProposeRoot(T, S, K));
end;

procedure TframeHypotheses.btnNewChildClick(Sender: TObject);
var
  T, S, C: string;
  K: Integer;
begin
  if (FVM = nil) or not FVM.HasDetail then
    Exit;
  T := ''; S := ''; C := ''; K := FVM.Detail.Summary.KeyValueTypeId;
  if TdlgHypothesisEdit.Execute(Format('New follow-up to "%s"',
    [FVM.Detail.Summary.Title]), True, T, S, C, K) then
    ProposeOutcome(FVM.ProposeChild(FVM.SelectedId, T, S, C, K));
end;

procedure TframeHypotheses.btnEditClick(Sender: TObject);
var
  T, S, C: string;
  K: Integer;
begin
  if (FVM = nil) or not FVM.HasDetail then
    Exit;
  T := FVM.Detail.Summary.Title;
  S := FVM.Detail.Statement;
  C := FVM.Detail.Change;
  K := FVM.Detail.Summary.KeyValueTypeId;
  if TdlgHypothesisEdit.Execute('Edit proposal', FVM.Detail.Summary.ParentId <> 0,
    T, S, C, K) then
    ShowOutcome(FVM.SaveEdit(T, S, C, K));
end;

procedure TframeHypotheses.btnAbandonClick(Sender: TObject);
var
  Reason: array of string;
  O: TVMOutcome;
begin
  if (FVM = nil) or not FVM.HasDetail then
    Exit;
  SetLength(Reason, 1);
  // An over-long reason keeps the dialog open with the text, rather than
  // coming back as a refusal after the typed text is gone.
  if not InputQuery('Abandon "' + FVM.Detail.Summary.Title + '"',
    ['Why is work on it stopping?'], Reason,
    function(const AValues: array of string): Boolean
    begin
      Result := HypCommentLength(AValues[0]) <= MAX_HYP_COMMENT;
      if not Result then
        ShowMessage(RefusalText(hrCommentTooLong));
    end) then
    Exit;
  O := FVM.Abandon(Reason[0]);
  ShowOutcome(O);
  if O.Ok then
    DecisionsChanged;   // it no longer waits on anyone
end;

procedure TframeHypotheses.btnRefreshClick(Sender: TObject);
begin
  if Assigned(FVM) then
    FVM.Reload;
end;

{ Runs }

procedure TframeHypotheses.lvRunsCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  C: TColor;
begin
  if RowColour(Item, C) then
    Sender.Canvas.Font.Color := C;
  DefaultDraw := True;
end;

procedure TframeHypotheses.lvRunsDblClick(Sender: TObject);
begin
  if (FVM = nil) or (lvRuns.Selected = nil) then
    Exit;
  NavigateTo(FVM.RunNavigateItemId(lvRuns.Selected.Index));
end;

procedure TframeHypotheses.btnAttachSelectedClick(Sender: TObject);
var
  ItemId, HypId: Integer;
  Item: TItem;
  Role: THypothesisRunRole;
  O: TVMOutcome;
begin
  if (FVM = nil) or not FVM.HasDetail then
    Exit;
  // The item selected in the item tree right now (a left click there closes
  // this view, so it is usually a keyboard or right-click selection) - what
  // the dialog below names. Drag-and-drop from the item tree is deliberately
  // not used (Plan 4 Task 3).
  ItemId := 0;
  if Assigned(FOnGetSelectedItemId) then
    ItemId := FOnGetSelectedItemId();
  Item := nil;
  if ItemId > 0 then
    Item := Model.Manager.Find<TItem>(ItemId);
  if (Item = nil) or Item.IsDeleted then
  begin
    MessageDlg('Select an item in the item tree first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  // The pick dialog offers only this hypothesis and asks Run or Reference;
  // while it waits for approval only Reference is possible (C21).
  if not TdlgHypothesisPick.Execute([FVM.Detail.Summary], HypId, Role,
    Format('Attach "%s" (selected in the item tree) to:', [Item.Title])) then
    Exit;
  O := FVM.AttachItem(HypId, ItemId, Role);
  ShowOutcome(O);
  if O.Ok then
  begin
    pcDetail.ActivePage := tsRuns;
    if Role = hrrRun then
      RunsChanged;      // only a Run carries the HYP badge
  end;
end;

procedure TframeHypotheses.btnDetachClick(Sender: TObject);
var
  O: TVMOutcome;
  Idx: Integer;
  Question: string;
  WasRun: Boolean;
begin
  if (FVM = nil) or (lvRuns.Selected = nil) then
    Exit;
  Idx := lvRuns.Selected.Index;
  // Never quote "Not readable" as if it were the item's name (C7).
  if FVM.RunReadable(Idx) then
    Question := Format('Remove "%s" from this hypothesis?', [FVM.RunCaption(Idx)])
  else
    Question := 'Remove this run from the hypothesis?';
  if MessageDlg(Question, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  // Read the role now: the detach reloads Detail. Role survives redaction.
  WasRun := (Idx <= High(FVM.Detail.Runs)) and
    (FVM.Detail.Runs[Idx].Role = hrrRun);
  O := FVM.DetachRunAt(Idx);
  ShowOutcome(O);
  if O.Ok and WasRun then
    RunsChanged;        // only a Run carries the HYP badge
end;

{ Evidence }

procedure TframeHypotheses.lvEvidenceCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  C: TColor;
begin
  if RowColour(Item, C) then
    Sender.Canvas.Font.Color := C;
  DefaultDraw := True;
end;

procedure TframeHypotheses.lvEvidenceDblClick(Sender: TObject);
begin
  if (FVM = nil) or (lvEvidence.Selected = nil) then
    Exit;
  NavigateTo(FVM.EvidenceNavigateItemId(lvEvidence.Selected.Index));
end;

procedure TframeHypotheses.btnCiteClick(Sender: TObject);
var
  Choice: TEvidenceChoice;
  Note: string;
begin
  if (FVM = nil) or not FVM.HasDetail then
    Exit;
  if TdlgEvidencePick.Execute(FVM, Choice, Note) then
    ShowOutcome(FVM.Cite(Choice, Note));
end;

procedure TframeHypotheses.btnRemoveEvidenceClick(Sender: TObject);
var
  Idx: Integer;
begin
  if (FVM = nil) or (lvEvidence.Selected = nil) then
    Exit;
  Idx := lvEvidence.Selected.Index;
  if (Idx < 0) or (Idx > High(FVM.Detail.Evidence)) then
    Exit;
  if MessageDlg('Remove this evidence from the hypothesis?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then
    Exit;
  // EvidenceId survives redaction (C7), so an unreadable row can be removed.
  ShowOutcome(FVM.RemoveEvidence(FVM.Detail.Evidence[Idx].EvidenceId));
end;

{ Conclusion }

procedure TframeHypotheses.memConclusionChange(Sender: TObject);
begin
  if not FFilling and Assigned(FVM) then
    FVM.BeginConclusionDraft(memConclusion.Text);
end;

procedure TframeHypotheses.cbOutcomeChange(Sender: TObject);
begin
  if not FFilling and Assigned(FVM) then
    FVM.BeginConclusionDraft(memConclusion.Text);
end;

procedure TframeHypotheses.btnSubmitClick(Sender: TObject);
var
  O: TVMOutcome;
  Outcome: Nullable<THypothesisOutcome>;
begin
  if (FVM = nil) or not FVM.HasDetail then
    Exit;
  // ItemIndex -1 means the user never picked one: leave Outcome empty so the
  // VM refuses with the needs-outcome message instead of guessing.
  if cbOutcome.ItemIndex >= 0 then
    Outcome := THypothesisOutcome(cbOutcome.ItemIndex);
  // A successful Submit ends the draft in the VM before its reload repaints
  // the detail, so the stored conclusion shows from now on.
  O := FVM.Submit(memConclusion.Text, Outcome);
  ShowOutcome(O);
  if O.Ok then
    DecisionsChanged;   // now waits on an acceptor
end;

{ Decision }

procedure TframeHypotheses.memGateCommentChange(Sender: TObject);
begin
  // The VM keeps the typed comment across reloads (an attach, a refresh or a
  // refused gate step repaints the panel from FVM.GateComment).
  if not FFilling and Assigned(FVM) then
    FVM.GateComment := memGateComment.Text;
end;

procedure TframeHypotheses.btnGateClick(Sender: TObject);
var
  O: TVMOutcome;
begin
  if FVM = nil then
    Exit;
  // On a conflict the view reloaded and the comment was kept.
  O := FVM.Gate(THypothesisStatus((Sender as TButton).Tag), memGateComment.Text);
  ShowOutcome(O);
  if O.Ok then
    DecisionsChanged;   // the dashboard's "Waiting for You" list may have changed
end;

end.
