unit unit_HypothesisRules;

{
  Pure transition rules for the experiment tree (spec §6.1). No manager, no
  database, no policy: callers work out WHO the user is (actors) and WHAT is
  true (facts), and this unit answers yes or names the reason for no.

  Gate transitions (IsGateTransition) are decided here like any other, but
  only unit_HypothesisGateModel is allowed to EXECUTE them.
}

interface

uses
  unit_Hypothesis;

type
  THypActor = (haAuthor, haWriter, haProposalApprover, haConclusionApprover);
  THypActors = set of THypActor;

  THypRefusal = (hrOk, hrNotAllowed, hrFinal, hrNeedsComment,
    hrNeedsConclusion, hrNeedsOutcome, hrNeedsEvidence, hrLocked,
    hrNeedsTitle, hrNeedsStatement, hrNeedsChange, hrCommentTooLong);

  THypFacts = record
    HasComment: Boolean;
    HasConclusion: Boolean;
    HasOutcome: Boolean;
    EvidenceCount: Integer;
    class function Make(AHasComment, AHasConclusion, AHasOutcome: Boolean;
      AEvidenceCount: Integer): THypFacts; static;
  end;

  THypField = (hfTitle, hfStatement, hfChange, hfKeyValueType);
  THypFields = set of THypField;

const
  FinalStatuses: set of THypothesisStatus = [hsRejected, hsAccepted, hsAbandoned];
  /// <summary>Items cited by a hypothesis in these states cannot be deleted.</summary>
  LockedStatuses: set of THypothesisStatus = [hsInReview, hsAccepted];

  HypRefusalNames: array[THypRefusal] of string = ('ok', 'not_allowed',
    'final', 'needs_comment', 'needs_conclusion', 'needs_outcome',
    'needs_evidence', 'locked', 'needs_title', 'needs_statement',
    'needs_change', 'comment_too_long');

  /// <summary>A status-change comment (gate or abandon) holds at most this
  /// many characters, counted as HypCommentLength counts them.</summary>
  MAX_HYP_COMMENT = 500;

function IsGateTransition(AFrom, ATo: THypothesisStatus): Boolean;
function GateOfTransition(AFrom, ATo: THypothesisStatus;
  out AGate: THypothesisGate): Boolean;
function CheckTransition(AFrom, ATo: THypothesisStatus; AActors: THypActors;
  const AFacts: THypFacts): THypRefusal;
function CheckProposal(const ATitle, AStatement, AChange: string;
  AIsRoot: Boolean): THypRefusal;
function EditableFields(AStatus: THypothesisStatus;
  AActors: THypActors): THypFields;
function CanChangeRunsOrEvidence(AStatus: THypothesisStatus): Boolean;
/// <summary>Reference items are context for a proposal: the author may add
/// them while Proposed; anyone who may change runs may change them while
/// Approved.</summary>
function CanChangeReferences(AStatus: THypothesisStatus;
  AActors: THypActors): Boolean;
function RefusalText(ARefusal: THypRefusal): string;
/// <summary>Characters in a comment as the Comment column counts them
/// (MySQL VARCHAR counts code points): a surrogate pair is one.</summary>
function HypCommentLength(const AComment: string): Integer;

implementation

uses
  System.SysUtils;

class function THypFacts.Make(AHasComment, AHasConclusion, AHasOutcome: Boolean;
  AEvidenceCount: Integer): THypFacts;
begin
  Result.HasComment := AHasComment;
  Result.HasConclusion := AHasConclusion;
  Result.HasOutcome := AHasOutcome;
  Result.EvidenceCount := AEvidenceCount;
end;

function GateOfTransition(AFrom, ATo: THypothesisStatus;
  out AGate: THypothesisGate): Boolean;
begin
  Result := True;
  if (AFrom = hsProposed) and (ATo in [hsApproved, hsRejected]) then
    AGate := hgApproveProposals
  else if (AFrom = hsInReview) and (ATo in [hsAccepted, hsApproved]) then
    AGate := hgAcceptConclusions
  else
  begin
    AGate := hgApproveProposals;
    Result := False;
  end;
end;

function IsGateTransition(AFrom, ATo: THypothesisStatus): Boolean;
var
  G: THypothesisGate;
begin
  Result := GateOfTransition(AFrom, ATo, G);
end;

function CheckTransition(AFrom, ATo: THypothesisStatus; AActors: THypActors;
  const AFacts: THypFacts): THypRefusal;
begin
  if AFrom in FinalStatuses then
    Exit(hrFinal);

  if (AFrom = hsProposed) and (ATo = hsApproved) then
  begin
    if not (haProposalApprover in AActors) then Exit(hrNotAllowed);
    Exit(hrOk);
  end;

  if (AFrom = hsProposed) and (ATo = hsRejected) then
  begin
    if not (haProposalApprover in AActors) then Exit(hrNotAllowed);
    if not AFacts.HasComment then Exit(hrNeedsComment);
    Exit(hrOk);
  end;

  if (AFrom = hsApproved) and (ATo = hsInReview) then
  begin
    if AActors * [haAuthor, haWriter] = [] then Exit(hrNotAllowed);
    if not AFacts.HasConclusion then Exit(hrNeedsConclusion);
    if not AFacts.HasOutcome then Exit(hrNeedsOutcome);
    if AFacts.EvidenceCount < 1 then Exit(hrNeedsEvidence);
    Exit(hrOk);
  end;

  if (AFrom = hsInReview) and (ATo = hsAccepted) then
  begin
    if not (haConclusionApprover in AActors) then Exit(hrNotAllowed);
    Exit(hrOk);
  end;

  if (AFrom = hsInReview) and (ATo = hsApproved) then
  begin
    if not (haConclusionApprover in AActors) then Exit(hrNotAllowed);
    if not AFacts.HasComment then Exit(hrNeedsComment);
    Exit(hrOk);
  end;

  if (AFrom = hsApproved) and (ATo = hsAbandoned) then
  begin
    if AActors * [haAuthor, haProposalApprover] = [] then Exit(hrNotAllowed);
    if not AFacts.HasComment then Exit(hrNeedsComment);
    Exit(hrOk);
  end;

  Result := hrNotAllowed;
end;

function CheckProposal(const ATitle, AStatement, AChange: string;
  AIsRoot: Boolean): THypRefusal;
begin
  if Trim(ATitle) = '' then Exit(hrNeedsTitle);
  if Trim(AStatement) = '' then Exit(hrNeedsStatement);
  if (not AIsRoot) and (Trim(AChange) = '') then Exit(hrNeedsChange);
  Result := hrOk;
end;

function EditableFields(AStatus: THypothesisStatus;
  AActors: THypActors): THypFields;
begin
  if (AStatus = hsProposed) and (haAuthor in AActors) then
    Result := [hfTitle, hfStatement, hfChange, hfKeyValueType]
  else
    Result := [];
end;

function CanChangeRunsOrEvidence(AStatus: THypothesisStatus): Boolean;
begin
  Result := AStatus = hsApproved;
end;

function CanChangeReferences(AStatus: THypothesisStatus;
  AActors: THypActors): Boolean;
begin
  Result := (AStatus = hsApproved) or
    ((AStatus = hsProposed) and (haAuthor in AActors));
end;

function RefusalText(ARefusal: THypRefusal): string;
begin
  case ARefusal of
    hrOk:              Result := 'Allowed.';
    hrNotAllowed:      Result := 'This change is not allowed for you in the hypothesis''s current state.';
    hrFinal:           Result := 'The hypothesis is final (accepted, rejected or abandoned); propose a child hypothesis instead.';
    hrNeedsComment:    Result := 'A comment is required.';
    hrNeedsConclusion: Result := 'A conclusion is required.';
    hrNeedsOutcome:    Result := 'An outcome (supported, refuted or inconclusive) is required.';
    hrNeedsEvidence:   Result := 'Cite at least one piece of evidence first.';
    hrLocked:          Result := 'The hypothesis is locked in its current state.';
    hrNeedsTitle:      Result := 'A title is required.';
    hrNeedsStatement:  Result := 'A statement (what you expect and why) is required.';
    hrNeedsChange:     Result := 'Describe what differs from the parent hypothesis.';
    hrCommentTooLong:  Result := Format('The comment is longer than %d characters.', [MAX_HYP_COMMENT]);
  else
    Result := 'Refused.';
  end;
end;

function HypCommentLength(const AComment: string): Integer;
var
  I: Integer;
begin
  Result := Length(AComment);
  for I := 1 to Length(AComment) - 1 do
    if (AComment[I] >= #$D800) and (AComment[I] <= #$DBFF) and
       (AComment[I + 1] >= #$DC00) and (AComment[I + 1] <= #$DFFF) then
      Dec(Result);
end;

end.
