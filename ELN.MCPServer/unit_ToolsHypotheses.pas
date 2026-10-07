unit unit_ToolsHypotheses;

{
  MCP tools for the experiment tree (spec section 7). Agents can propose
  hypotheses, attach runs, cite evidence and submit conclusions.

  NONE of these tools can approve, reject, accept or return a hypothesis.
  Those four gates are executed by a unit this server never compiles
  (spec D6); test_HypothesisLinkage and test_ToolRegistryGates enforce it.
  Tool descriptions say so, so an agent tells its human where to go instead
  of looking for a tool.

  Every error leaves as a plain Exception: unit_MCPDiag.ClientErrorMessage
  passes only exact-class Exception messages to the client and replaces every
  descendant with a generic "internal error", which would hide the refusal
  reasons. RunHypTool does the translation, ONCE, for every handler in this
  unit (controller ruling for Plan 2 Task 2):

    function HandleXxx(const Params: TJSONObject;
      const Context: TToolContext): TJSONObject;
    begin
      Result := RunHypTool(
        function: TJSONObject
        begin
          Result := DoXxx(Params, Context);
        end);
    end;

  Contract of RunHypTool: it runs Body and returns whatever Body returns. If
  Body raises EHypothesisError, EHypothesisConflict or EHypothesisAccess (or
  any descendant), the exception is replaced by an equivalent plain Exception
  carrying the same message (EHypothesisError/EHypothesisConflict also append
  a machine-readable "[refusal_code]" / "[version_conflict; ...]" suffix), so
  ClientErrorMessage always shows the refusal to the caller. Any OTHER
  exception (a missing parameter, an infrastructure error) passes through
  unchanged - RunHypTool only ever narrows what MapModelError recognises, it
  never invents new errors. Tasks 3-5 reuse this same helper for
  update_hypothesis, attach_run, detach_run, cite_evidence, remove_evidence,
  submit_conclusion and abandon_hypothesis.
}

interface

uses
  System.JSON,
  System.SysUtils,
  unit_MCPTools;

const
  APPROVAL_HINT = 'Approving a proposal and accepting a conclusion are done ' +
    'by a human in the ELN desktop or web app; no MCP tool can do either.';

  HYPOTHESIS_TOOL_NAMES: array[0..10] of string = ('list_hypotheses',
    'get_hypothesis', 'get_hypothesis_tree', 'propose_hypothesis',
    'update_hypothesis', 'attach_run', 'detach_run', 'cite_evidence',
    'remove_evidence', 'submit_conclusion', 'abandon_hypothesis');

procedure RegisterHypothesisTools(Registry: TToolRegistry);

/// <summary>Runs Body and maps a model refusal (EHypothesisError /
/// EHypothesisConflict / EHypothesisAccess) to a plain Exception so the
/// refusal reason reaches the MCP client instead of being replaced by
/// unit_MCPDiag's generic "internal error". Every exported Handle* below is
/// a one-line wrapper around this. Exposed so Tasks 3-5 reuse it rather than
/// repeating the try/except.</summary>
function RunHypTool(const Body: TFunc<TJSONObject>): TJSONObject;

// Exposed for ELN.Tests\test_ToolsHypotheses.
function HandleListHypotheses(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleGetHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleGetHypothesisTree(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleProposeHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleUpdateHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleAttachRun(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleDetachRun(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleCiteEvidence(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleRemoveEvidence(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleSubmitConclusion(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
function HandleAbandonHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;

implementation

uses
  System.DateUtils,
  unit_User,
  unit_Hypothesis,
  unit_HypothesisRun,
  unit_HypothesisEvidence,
  unit_HypothesisRules,
  unit_HypothesisModel,
  unit_ToolScope,
  unit_ToolsWrite;

const
  GATE_JSON: array[THypothesisGate] of string =
    ('approve_proposal', 'accept_conclusion');

{ ---- error translation ---- }

/// A plain Exception for a model error, or nil for anything else (which the
/// caller re-raises unchanged).
function MapModelError(E: Exception): Exception;
begin
  // Before EHypothesisError (its parent): another record's lost lock is
  // retryable, not a refusal.
  if E is EHypothesisOtherRecordChanged then
    Result := Exception.CreateFmt('%s [conflict; retry]', [E.Message])
  else if E is EHypothesisError then
    Result := Exception.CreateFmt('%s [%s]',
      [E.Message, HypRefusalNames[EHypothesisError(E).Refusal]])
  else if E is EHypothesisConflict then
    Result := Exception.CreateFmt('%s [version_conflict; current_version=%d]',
      [E.Message, EHypothesisConflict(E).CurrentVersion])
  else if E is EHypothesisAccess then
    Result := Exception.Create(E.Message)
  else
    Result := nil;
end;

function RunHypTool(const Body: TFunc<TJSONObject>): TJSONObject;
var
  Mapped: Exception;
begin
  try
    Result := Body();
  except
    on E: Exception do
    begin
      Mapped := MapModelError(E);
      if Mapped <> nil then raise Mapped;
      raise;
    end;
  end;
end;

{ ---- parameters ---- }

procedure RaiseUnknownName(const S: string; const ANames: array of string;
  const AWhat: string);
var
  I: Integer;
  Known: TArray<string>;
begin
  SetLength(Known, 0);
  for I := 0 to High(ANames) do
    if ANames[I] <> '' then
    begin
      SetLength(Known, Length(Known) + 1);
      Known[High(Known)] := ANames[I];
    end;
  raise Exception.CreateFmt('Unknown %s "%s". Use one of: %s.',
    [AWhat, S, string.Join(', ', Known)]);
end;

function NameIndex(const S: string; const ANames: array of string;
  const AWhat: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ANames) do
    if (ANames[I] <> '') and SameText(ANames[I], S) then
      Exit(I);
  RaiseUnknownName(S, ANames, AWhat);
  Result := -1;   // not reached: the compiler cannot see that RaiseUnknownName never returns
end;

type
  THypStatusFilter = set of THypothesisStatus;

/// <summary>The list_hypotheses status filter as a SET, built by walking
/// HypothesisStatusNames. Agent input never becomes a scalar status value, and
/// no gate status is named in this unit: test_HypothesisLinkage forbids MCP
/// code to name hsApproved/hsRejected/hsAccepted, to cast to
/// THypothesisStatus, or to assign a .Status at all (final review I3).
/// </summary>
function ParseStatusFilter(const S: string): THypStatusFilter;
var
  St: THypothesisStatus;
begin
  Result := [];
  for St := Low(THypothesisStatus) to High(THypothesisStatus) do
    if SameText(HypothesisStatusNames[St], S) then
      Include(Result, St);
  if Result = [] then
    RaiseUnknownName(S, HypothesisStatusNames, 'status');
end;

function ParseDerived(const S: string): THypDerivedState;
begin
  Result := THypDerivedState(NameIndex(S, HypDerivedStateNames, 'derived_state'));
end;

function ParseRole(const S: string): THypothesisRunRole;
begin
  Result := THypothesisRunRole(NameIndex(S, HypothesisRunRoleNames, 'role'));
end;

function ParseOutcome(const S: string): THypothesisOutcome;
begin
  Result := THypothesisOutcome(NameIndex(S, HypothesisOutcomeNames, 'outcome'));
end;

/// <summary>The hypothesis, if this session may see its project. A missing
/// id and an out-of-scope id raise the SAME message under a scope (no
/// existence oracle).</summary>
function LoadVisible(const Context: TToolContext; AId: Integer): THypothesis;
begin
  Result := Context.Manager.Find<THypothesis>(AId);
  if Result = nil then
  begin
    if IsScopeActive(Context) then
      RaiseOutOfScope;
    raise Exception.CreateFmt('Hypothesis %d not found.', [AId]);
  end;
  RequireProjectRead(Context, Result.ProjectId);
end;

{ ---- JSON ---- }

function IntOrNull(AValue: Int64): TJSONValue;
begin
  if AValue = 0 then
    Result := TJSONNull.Create
  else
    Result := TJSONNumber.Create(AValue);
end;

function NumOrNull(AHas: Boolean; AValue: Double): TJSONValue;
begin
  if AHas then
    Result := TJSONNumber.Create(AValue)
  else
    Result := TJSONNull.Create;
end;

function KeyValueJSON(const S: THypothesisSummary): TJSONValue;
var
  O: TJSONObject;
begin
  if S.KeyValueTypeId = 0 then
    Exit(TJSONNull.Create);
  O := TJSONObject.Create;
  O.AddPair('value_type_id', TJSONNumber.Create(S.KeyValueTypeId));
  O.AddPair('n', TJSONNumber.Create(S.KeyValue.N));
  O.AddPair('mean', NumOrNull(S.KeyValue.N > 0, S.KeyValue.Mean));
  O.AddPair('min', NumOrNull(S.KeyValue.N > 0, S.KeyValue.Min));
  O.AddPair('max', NumOrNull(S.KeyValue.N > 0, S.KeyValue.Max));
  Result := O;
end;

function SummaryJSON(const S: THypothesisSummary): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(S.Id));
  Result.AddPair('project_id', TJSONNumber.Create(S.ProjectId));
  Result.AddPair('parent_id', IntOrNull(S.ParentId));
  Result.AddPair('title', S.Title);
  Result.AddPair('status', HypothesisStatusNames[S.Status]);
  if S.Derived = hdsNone then
    Result.AddPair('derived_state', TJSONNull.Create)
  else
    Result.AddPair('derived_state', HypDerivedStateNames[S.Derived]);
  Result.AddPair('created_by', TJSONNumber.Create(S.CreatedBy));
  Result.AddPair('run_count', TJSONNumber.Create(S.RunCount));
  Result.AddPair('evidence_count', TJSONNumber.Create(S.EvidenceCount));
  Result.AddPair('version', TJSONNumber.Create(S.Version));
  Result.AddPair('key_value', KeyValueJSON(S));
end;

function PendingGate(AStatus: THypothesisStatus; out AGate: THypothesisGate): Boolean;
begin
  Result := True;
  case AStatus of
    hsProposed: AGate := hgApproveProposals;
    hsInReview: AGate := hgAcceptConclusions;
  else
    AGate := hgApproveProposals;
    Result := False;
  end;
end;

{ ---- schemas ---- }

function Prop(const AType, ADesc: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  Result.AddPair('description', ADesc);
end;

function PropEnum(const ADesc: string; const AValues: array of string): TJSONObject;
var
  A: TJSONArray;
  I: Integer;
begin
  Result := Prop('string', ADesc);
  A := TJSONArray.Create;
  for I := 0 to High(AValues) do
    if AValues[I] <> '' then
      A.Add(AValues[I]);
  Result.AddPair('enum', A);
end;

function Schema(const ANames: array of string; const AProps: array of TJSONObject;
  const ARequired: array of string): TJSONObject;
var
  Props: TJSONObject;
  Req: TJSONArray;
  I: Integer;
begin
  Assert(Length(ANames) = Length(AProps), 'schema: names/props mismatch');
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Props := TJSONObject.Create;
  for I := 0 to High(ANames) do
    Props.AddPair(ANames[I], AProps[I]);
  Result.AddPair('properties', Props);
  Req := TJSONArray.Create;
  for I := 0 to High(ARequired) do
    Req.Add(ARequired[I]);
  Result.AddPair('required', Req);
end;

{ ---- list_hypotheses ---- }

function DoListHypotheses(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Flt: THypothesisFilter;
  S: string;
  I: Integer;
  M: THypothesisModel;
  Rows: TArray<THypothesisSummary>;
  Row: THypothesisSummary;
  Arr: TJSONArray;
begin
  Flt := THypothesisFilter.All;
  if GetOptInt(Params, 'project_id', I) then
  begin
    RequireProjectRead(Context, I);
    Flt.ProjectId := I;
  end;
  if GetOptStr(Params, 'status', S) then
    Flt.Statuses := ParseStatusFilter(S);
  if GetOptStr(Params, 'derived_state', S) then
    Flt.DerivedStates := [ParseDerived(S)];
  if GetOptInt(Params, 'root_id', I) then
    Flt.RootId := I;
  if GetOptInt(Params, 'author_id', I) then
    Flt.AuthorId := I;
  // A scoped key lists its own projects only: the model never reads the
  // rest of the installation just to have the rows dropped below (Task 5b).
  if IsScopeActive(Context) then
    Flt.ProjectIds := Context.ScopedProjects;

  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    Rows := M.List(Context.User, Flt);
  finally
    M.Free;
  end;

  Result := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Result.AddPair('hypotheses', Arr);
  for Row in Rows do
    if IsProjectVisible(Context, Row.ProjectId) then
      Arr.AddElement(SummaryJSON(Row));
  Result.AddPair('count', TJSONNumber.Create(Arr.Count));
end;

function HandleListHypotheses(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoListHypotheses(Params, Context);
    end);
end;

{ ---- get_hypothesis ---- }

function DoGetHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  M: THypothesisModel;
  D: THypothesisDetail;
  R: THypothesisRunView;
  E: THypothesisEvidenceView;
  Hs: THypothesisHistoryView;
  Arr: TJSONArray;
  O: TJSONObject;
  Gate: THypothesisGate;
  Reason: string;
  Visible: Boolean;
  Kid: Integer;
begin
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    D := M.Get(Context.User, H.Id, Context.ScopedProjects);
  finally
    M.Free;
  end;

  Result := SummaryJSON(D.Summary);
  // Everything below builds on Result; if any of it raises (CanPassGate
  // reads the database), free the tree instead of leaking it (final review
  // Minor 5).
  try
    Result.AddPair('statement', D.Statement);
    Result.AddPair('change', D.Change);
    if D.HasOutcome then
      Result.AddPair('outcome', HypothesisOutcomeNames[D.Outcome])
    else
      Result.AddPair('outcome', TJSONNull.Create);
    Result.AddPair('conclusion', D.Conclusion);
    Result.AddPair('content_hash', D.ContentHash);
    Result.AddPair('created_device_id', IntOrNull(D.CreatedDeviceId));
    // Hypothesis CreatedDate/ChangedDate are always UTCNow (unit_TimeHelper,
    // unit_HypothesisModel.Propose/WriteStatus) - the DateToISO8601(_, False)
    // this used to call mislabels a UTC instant with the host's local offset
    // (Task H item 5).
    Result.AddPair('created_date', DateToISO8601(D.CreatedDate, True));

    Arr := TJSONArray.Create;
    Result.AddPair('runs', Arr);
    for R in D.Runs do
    begin
      Visible := IsProjectVisible(Context, R.ItemProjectId);
      O := TJSONObject.Create;
      Arr.AddElement(O);   // owned by Arr immediately: a raising AddPair below must not leak O
      O.AddPair('run_id', TJSONNumber.Create(R.RunId));
      if Visible then
      begin
        O.AddPair('item_id', TJSONNumber.Create(R.ItemId));
        O.AddPair('item_title', R.ItemTitle);
        O.AddPair('item_project_id', TJSONNumber.Create(R.ItemProjectId));
      end
      else
      begin
        // Out-of-scope item: null every item-derived field. A scoped key must
        // learn nothing about project O just because a hypothesis in its own
        // project references an item there (final review 3).
        O.AddPair('item_id', TJSONNull.Create);
        O.AddPair('item_title', TJSONNull.Create);
        O.AddPair('item_project_id', TJSONNull.Create);
      end;
      O.AddPair('role', HypothesisRunRoleNames[R.Role]);
      if Visible then
        O.AddPair('missing', TJSONBool.Create(R.Missing))
      else
        // Out-of-scope item: whether a foreign item is missing would reveal
        // that it was deleted, so redact it like the other item-derived
        // fields (final review 3, controller re-review).
        O.AddPair('missing', TJSONNull.Create);
      O.AddPair('outside_scope', TJSONBool.Create(not Visible));
    end;

    Arr := TJSONArray.Create;
    Result.AddPair('evidence', Arr);
    for E in D.Evidence do
    begin
      // ItemProjectId, not ProjectOfItem: THypothesisEvidenceView already
      // carries it (populated by THypothesisModel.Get), so this is one field
      // read instead of a second Find<TItem> round trip - same as runs[].
      Visible := IsProjectVisible(Context, E.ItemProjectId);
      O := TJSONObject.Create;
      Arr.AddElement(O);   // owned by Arr immediately: a raising AddPair below must not leak O
      O.AddPair('evidence_id', TJSONNumber.Create(E.EvidenceId));
      if Visible then
      begin
        O.AddPair('item_id', TJSONNumber.Create(E.ItemId));
        O.AddPair('item_title', E.ItemTitle);
        O.AddPair('file_id', IntOrNull(E.FileId));
        O.AddPair('value_id', IntOrNull(E.ValueId));
        O.AddPair('note', E.Note);
        O.AddPair('file_hash', E.FileHash);
        O.AddPair('value_snapshot', NumOrNull(E.HasSnapshot, E.ValueSnapshot));
        O.AddPair('changed', TJSONBool.Create(E.Changed));
        O.AddPair('missing', TJSONBool.Create(E.Missing));
      end
      else
      begin
        // Out-of-scope item: null every item-derived field (id, title, file,
        // value, note, hash, snapshot, changed/missing flags) - a citation
        // from another project must not leak that project's ids, free-text
        // notes, file hashes or measured values to a scoped key. evidence_id
        // and outside_scope are the only fields kept, so the agent can still
        // name this evidence (e.g. to remove_evidence, if the model allows).
        O.AddPair('item_id', TJSONNull.Create);
        O.AddPair('item_title', TJSONNull.Create);
        O.AddPair('file_id', TJSONNull.Create);
        O.AddPair('value_id', TJSONNull.Create);
        O.AddPair('note', TJSONNull.Create);
        O.AddPair('file_hash', TJSONNull.Create);
        O.AddPair('value_snapshot', TJSONNull.Create);
        O.AddPair('changed', TJSONNull.Create);
        O.AddPair('missing', TJSONNull.Create);
      end;
      O.AddPair('outside_scope', TJSONBool.Create(not Visible));
    end;

    Arr := TJSONArray.Create;
    Result.AddPair('history', Arr);
    for Hs in D.History do
    begin
      O := TJSONObject.Create;
      Arr.AddElement(O);   // owned by Arr immediately: a raising AddPair below must not leak O
      O.AddPair('old_status', HypothesisStatusNames[Hs.OldStatus]);
      O.AddPair('new_status', HypothesisStatusNames[Hs.NewStatus]);
      O.AddPair('changed_by', TJSONNumber.Create(Hs.ChangedBy));
      O.AddPair('changed_device_id', IntOrNull(Hs.ChangedDeviceId));
      O.AddPair('changed_date', DateToISO8601(Hs.ChangedDate, True));
      O.AddPair('comment', Hs.Comment);
    end;

    Arr := TJSONArray.Create;
    Result.AddPair('child_ids', Arr);
    for Kid in D.ChildIds do
      Arr.Add(Kid);

    // A READ of eligibility: tells the agent whether its human can act in the
    // app. Nothing here, or anywhere in this unit, can pass the gate.
    if PendingGate(H.Status, Gate) then
    begin
      Result.AddPair('pending_gate', GATE_JSON[Gate]);
      Result.AddPair('can_approve', TJSONBool.Create(
        Context.AccessPolicy.CanPassGate(Context.Manager, Context.User, H, Gate, Reason)));
    end
    else
    begin
      Result.AddPair('pending_gate', TJSONNull.Create);
      Result.AddPair('can_approve', TJSONBool.Create(False));
    end;
    Result.AddPair('approval_note', APPROVAL_HINT);
  except
    Result.Free;
    raise;
  end;
end;

function HandleGetHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoGetHypothesis(Params, Context);
    end);
end;

{ ---- get_hypothesis_tree ---- }

function DoGetHypothesisTree(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Pid, Root: Integer;
  M: THypothesisModel;
  Rows: TArray<THypothesisSummary>;
  Row: THypothesisSummary;
  Arr: TJSONArray;
begin
  Pid := GetReqInt(Params, 'project_id');
  RequireProjectRead(Context, Pid);
  Root := 0;
  GetOptInt(Params, 'root_id', Root);
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    Rows := M.Tree(Context.User, Pid, Root, Context.ScopedProjects);
  finally
    M.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('project_id', TJSONNumber.Create(Pid));
  Result.AddPair('root_id', IntOrNull(Root));
  Arr := TJSONArray.Create;
  Result.AddPair('nodes', Arr);
  for Row in Rows do
    Arr.AddElement(SummaryJSON(Row));
end;

function HandleGetHypothesisTree(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoGetHypothesisTree(Params, Context);
    end);
end;

{ ---- propose_hypothesis ---- }

function DoProposeHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  Pid, Parent, KV: Integer;
  Change: string;
  M: THypothesisModel;
  H: THypothesis;
begin
  Pid := GetReqInt(Params, 'project_id');
  CheckProjectWriteAccess(Context, Pid);   // scope + write rule, MCP wording
  Parent := 0;
  GetOptInt(Params, 'parent_id', Parent);
  // Through LoadVisible BEFORE the model sees it: under a scope, a missing
  // parent and one in another project must read the same, or parent_id is an
  // existence oracle for hypotheses outside the scope (final review I1).
  if Parent <> 0 then
    LoadVisible(Context, Parent);
  KV := 0;
  GetOptInt(Params, 'key_value_type_id', KV);
  Change := '';
  GetOptStr(Params, 'change', Change);
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    H := M.Propose(Context.User, Context.DeviceId, Pid, Parent,
      GetReqStr(Params, 'title'), GetReqStr(Params, 'statement'), Change, KV);
    Result := SummaryJSON(M.Get(Context.User, H.Id, Context.ScopedProjects).Summary);
  finally
    M.Free;
  end;
  Result.AddPair('message', 'Proposed. ' + APPROVAL_HINT +
    ' Work on it (runs, evidence) starts once it is approved.');
end;

function HandleProposeHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoProposeHypothesis(Params, Context);
    end);
end;

{ ---- update_hypothesis ---- }

function DoUpdateHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  Id, Ver, KV, I: Integer;
  Title, Statement, Change, S: string;
  M: THypothesisModel;
begin
  Id := GetReqInt(Params, 'hypothesis_id');
  Ver := GetReqInt(Params, 'version');
  H := LoadVisible(Context, Id);
  CheckProjectWriteAccess(Context, H.ProjectId);
  Title := H.Title;
  Statement := H.Statement;
  Change := H.Change;
  if H.KeyValueTypeId.HasValue then KV := H.KeyValueTypeId.Value else KV := 0;
  // GetOptStr's Value is an `out` parameter: Delphi finalizes (clears) it on
  // entry regardless of whether the key is present, so blindly passing Title/
  // Statement/Change straight through would wipe an omitted field instead of
  // leaving it unchanged. Route through a temp and only overwrite on a real hit.
  if GetOptStr(Params, 'title', S) then Title := S;
  if GetOptStr(Params, 'statement', S) then Statement := S;
  if GetOptStr(Params, 'change', S) then Change := S;
  if GetOptInt(Params, 'key_value_type_id', I) then
    KV := I;
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    M.UpdateProposed(Context.User, Id, Ver, Title, Statement, Change, KV);
    Result := SummaryJSON(M.Get(Context.User, Id, Context.ScopedProjects).Summary);
  finally
    M.Free;
  end;
end;

function HandleUpdateHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoUpdateHypothesis(Params, Context);
    end);
end;

{ ---- attach_run / detach_run ---- }

function DoAttachRun(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  ItemId: Integer;
  RoleStr, S: string;
  Role: THypothesisRunRole;
  M: THypothesisModel;
  Run: THypothesisRun;
begin
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  CheckProjectWriteAccess(Context, H.ProjectId);
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);          // a Reference in another project must be in scope too
  // GetOptStr's Value is an `out` parameter: Delphi clears it on entry
  // regardless of whether the key is present (the Task 3 trap), so RoleStr
  // must not be passed directly - route through a temp and only overwrite
  // the 'Run' default on a real hit.
  RoleStr := 'Run';
  if GetOptStr(Params, 'role', S) then
    RoleStr := S;
  Role := ParseRole(RoleStr);
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    Run := M.AttachRun(Context.User, H.Id, ItemId, Role);
    Result := TJSONObject.Create;
    Result.AddPair('run_id', TJSONNumber.Create(Run.Id));
  finally
    M.Free;
  end;
  Result.AddPair('hypothesis_id', TJSONNumber.Create(H.Id));
  Result.AddPair('item_id', TJSONNumber.Create(ItemId));
  Result.AddPair('role', HypothesisRunRoleNames[Role]);
end;

function HandleAttachRun(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoAttachRun(Params, Context);
    end);
end;

function DoDetachRun(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  ItemId: Integer;
  M: THypothesisModel;
begin
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  CheckProjectWriteAccess(Context, H.ProjectId);
  ItemId := GetReqInt(Params, 'item_id');
  // get_hypothesis redacts an out-of-scope Reference's item_id; without this
  // a scoped key could recover it by probing detach_run(h, 1..N) - and the
  // first hit would destroy a link it can never re-attach (final review
  // Minor 1). Same uniform message as a missing item.
  RequireItemRead(Context, ItemId);
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    M.DetachRun(Context.User, H.Id, ItemId);
  finally
    M.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('hypothesis_id', TJSONNumber.Create(H.Id));
  Result.AddPair('item_id', TJSONNumber.Create(ItemId));
  Result.AddPair('detached', TJSONBool.Create(True));
end;

function HandleDetachRun(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoDetachRun(Params, Context);
    end);
end;

{ ---- cite_evidence / remove_evidence ---- }

function DoCiteEvidence(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  ItemId, ValueId: Integer;
  FileId: Int64;
  Note: string;
  M: THypothesisModel;
  E: THypothesisEvidence;
begin
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  CheckProjectWriteAccess(Context, H.ProjectId);
  ItemId := GetReqInt(Params, 'item_id');
  RequireItemRead(Context, ItemId);
  FileId := 0;
  if GetOptInt64(Params, 'file_id', FileId) and (FileId <> 0) then
    RequireFileRead(Context, FileId);
  ValueId := 0;
  GetOptInt(Params, 'value_id', ValueId);
  Note := '';
  GetOptStr(Params, 'note', Note);
  // file_hash / value_snapshot are never read from Params: the model copies
  // them from the file and value rows (spec 7).
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    E := M.CiteEvidence(Context.User, H.Id, ItemId, FileId, ValueId, Note);
    Result := TJSONObject.Create;
    Result.AddPair('evidence_id', TJSONNumber.Create(E.Id));
    Result.AddPair('hypothesis_id', TJSONNumber.Create(H.Id));
    Result.AddPair('item_id', TJSONNumber.Create(ItemId));
    if E.FileId.HasValue then
      Result.AddPair('file_id', TJSONNumber.Create(E.FileId.Value))
    else
      Result.AddPair('file_id', TJSONNull.Create);
    if E.ValueId.HasValue then
      Result.AddPair('value_id', TJSONNumber.Create(E.ValueId.Value))
    else
      Result.AddPair('value_id', TJSONNull.Create);
    Result.AddPair('note', E.Note);
    Result.AddPair('file_hash', E.FileHash);
    Result.AddPair('value_snapshot',
      NumOrNull(E.ValueSnapshot.HasValue, E.ValueSnapshot.ValueOrDefault));
  finally
    M.Free;
  end;
end;

function HandleCiteEvidence(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoCiteEvidence(Params, Context);
    end);
end;

function DoRemoveEvidence(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  EvId: Integer;
  M: THypothesisModel;
begin
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  CheckProjectWriteAccess(Context, H.ProjectId);
  EvId := GetReqInt(Params, 'evidence_id');
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    M.RemoveEvidence(Context.User, H.Id, EvId);
  finally
    M.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('hypothesis_id', TJSONNumber.Create(H.Id));
  Result.AddPair('evidence_id', TJSONNumber.Create(EvId));
  Result.AddPair('removed', TJSONBool.Create(True));
end;

function HandleRemoveEvidence(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoRemoveEvidence(Params, Context);
    end);
end;

{ ---- submit_conclusion ---- }

function DoSubmitConclusion(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  M: THypothesisModel;
begin
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  CheckProjectWriteAccess(Context, H.ProjectId);
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    M.SubmitConclusion(Context.User, Context.DeviceId, H.Id,
      GetReqInt(Params, 'version'), GetReqStr(Params, 'conclusion'),
      ParseOutcome(GetReqStr(Params, 'outcome')));
    Result := SummaryJSON(M.Get(Context.User, H.Id, Context.ScopedProjects).Summary);
  finally
    M.Free;
  end;
  Result.AddPair('message', 'Submitted for review. ' + APPROVAL_HINT);
end;

function HandleSubmitConclusion(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoSubmitConclusion(Params, Context);
    end);
end;

{ ---- abandon_hypothesis ---- }

function DoAbandonHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
var
  H: THypothesis;
  M: THypothesisModel;
begin
  RequireWriteUser(Context);
  H := LoadVisible(Context, GetReqInt(Params, 'hypothesis_id'));
  CheckProjectWriteAccess(Context, H.ProjectId);
  // Author only on MCP, even for an Admin identity. The model also lets an
  // approver abandon; that stays a human action in the desktop/web app.
  if H.CreatedBy <> Context.User.Id then
    raise Exception.Create('Only the author can abandon a hypothesis through ' +
      'MCP. An approver can abandon it in the ELN desktop or web app.');
  M := THypothesisModel.Create(Context.Manager, Context.AccessPolicy);
  try
    M.Abandon(Context.User, Context.DeviceId, H.Id,
      GetReqInt(Params, 'version'), GetReqStr(Params, 'comment'));
    Result := SummaryJSON(M.Get(Context.User, H.Id, Context.ScopedProjects).Summary);
  finally
    M.Free;
  end;
end;

function HandleAbandonHypothesis(const Params: TJSONObject;
  const Context: TToolContext): TJSONObject;
begin
  Result := RunHypTool(
    function: TJSONObject
    begin
      Result := DoAbandonHypothesis(Params, Context);
    end);
end;

{ ---- registration ---- }

procedure RegisterHypothesisTools(Registry: TToolRegistry);
begin
  Registry.Register('list_hypotheses',
    'List experiment-tree hypotheses you can see. Filters: project_id, status ' +
    '(Proposed, Approved, Rejected, InReview, Accepted, Abandoned), derived_state ' +
    '(to_make = approved with no runs; waiting_for_measurement = runs but no ' +
    'evidence; ready_to_conclude = evidence cited), root_id (a subtree), ' +
    'author_id. ' + APPROVAL_HINT,
    Schema(['project_id', 'status', 'derived_state', 'root_id', 'author_id'],
      [Prop('integer', 'Only this project'),
       PropEnum('Stored status', HypothesisStatusNames),
       PropEnum('Derived state of Approved nodes', HypDerivedStateNames),
       Prop('integer', 'Only this hypothesis and its descendants'),
       Prop('integer', 'Only hypotheses created by this user id')], []),
    HandleListHypotheses, tscProjectScoped);

  Registry.Register('get_hypothesis',
    'One hypothesis with its runs, cited evidence (flagged changed/missing when ' +
    'the file or value no longer matches what was cited), status history, child ' +
    'ids, and whether its pending gate could be passed by the human behind this ' +
    'identity (can_approve). ' + APPROVAL_HINT,
    Schema(['hypothesis_id'], [Prop('integer', 'Hypothesis id')], ['hypothesis_id']),
    HandleGetHypothesis, tscProjectScoped);

  Registry.Register('get_hypothesis_tree',
    'Compact tree of a project''s hypotheses (or one subtree), each node with its ' +
    'status, derived state and the headline value summarised over its Run items ' +
    '(n, mean, min, max). ' + APPROVAL_HINT,
    Schema(['project_id', 'root_id'],
      [Prop('integer', 'Project id'),
       Prop('integer', 'Optional: only this node and its descendants')], ['project_id']),
    HandleGetHypothesisTree, tscProjectScoped);

  Registry.Register('propose_hypothesis',
    'Propose a hypothesis: what you expect and why (statement), and what differs ' +
    'from the parent (change; required unless it is a root). It starts as ' +
    'Proposed and must be approved by a human before lab resources are spent. ' +
    APPROVAL_HINT,
    Schema(['project_id', 'parent_id', 'title', 'statement', 'change', 'key_value_type_id'],
      [Prop('integer', 'Project id'),
       Prop('integer', 'Parent hypothesis id (omit for a root)'),
       Prop('string', 'Short title (max 255)'),
       Prop('string', 'Expectation and why (markdown)'),
       Prop('string', 'What differs from the parent (markdown)'),
       Prop('integer', 'Optional value type id of the headline quantity')],
      ['project_id', 'title', 'statement']),
    HandleProposeHypothesis, tscProjectScoped);

  Registry.Register('update_hypothesis',
    'Edit your own hypothesis while it is still Proposed (only the author, only ' +
    'before approval). Every write (attach/cite/edit/status) bumps the hypothesis ' +
    'version; call get_hypothesis first and pass the current version - a stale ' +
    'version is refused with the current one. Omitted fields keep their value; ' +
    'key_value_type_id 0 clears it. ' + APPROVAL_HINT,
    Schema(['hypothesis_id', 'version', 'title', 'statement', 'change', 'key_value_type_id'],
      [Prop('integer', 'Hypothesis id'),
       Prop('integer', 'Version from get_hypothesis'),
       Prop('string', 'New title'),
       Prop('string', 'New statement'),
       Prop('string', 'New change'),
       Prop('integer', 'Headline value type id; 0 clears')],
      ['hypothesis_id', 'version']),
    HandleUpdateHypothesis, tscProjectScoped);

  Registry.Register('attach_run',
    'Attach an item (Proc, Item or Action) to an Approved hypothesis. role Run ' +
    '(default) = made to test it, must be in the hypothesis''s project; Reference = ' +
    'existing context from any project you can read. Each change bumps the ' +
    'hypothesis version; call get_hypothesis for the current version before ' +
    'submit_conclusion. ' + APPROVAL_HINT,
    Schema(['hypothesis_id', 'item_id', 'role'],
      [Prop('integer', 'Hypothesis id'), Prop('integer', 'Item id'),
       PropEnum('Run or Reference', HypothesisRunRoleNames)],
      ['hypothesis_id', 'item_id']),
    HandleAttachRun, tscProjectScoped);

  Registry.Register('detach_run',
    'Detach an item from an Approved hypothesis. Each change bumps the ' +
    'hypothesis version; call get_hypothesis for the current version before ' +
    'submit_conclusion. ' + APPROVAL_HINT,
    Schema(['hypothesis_id', 'item_id'],
      [Prop('integer', 'Hypothesis id'), Prop('integer', 'Item id')],
      ['hypothesis_id', 'item_id']),
    HandleDetachRun, tscProjectScoped);

  Registry.Register('cite_evidence',
    'Cite evidence for an Approved hypothesis: an item as a whole, or one of its ' +
    'files (file_id) or values (value_id). The server records the file''s MD5 ' +
    'and the value at citation time, so later changes show up as "changed". ' +
    'Each change bumps the hypothesis version; call get_hypothesis for the ' +
    'current version before submit_conclusion. ' + APPROVAL_HINT,
    Schema(['hypothesis_id', 'item_id', 'file_id', 'value_id', 'note'],
      [Prop('integer', 'Hypothesis id'), Prop('integer', 'Item id'),
       Prop('integer', 'Optional file id of that item'),
       Prop('integer', 'Optional value id of that item'),
       Prop('string', 'Why this supports or refutes the hypothesis (max 500)')],
      ['hypothesis_id', 'item_id']),
    HandleCiteEvidence, tscProjectScoped);

  Registry.Register('remove_evidence',
    'Remove a citation from an Approved hypothesis. Each change bumps the ' +
    'hypothesis version; call get_hypothesis for the current version before ' +
    'submit_conclusion. ' + APPROVAL_HINT,
    Schema(['hypothesis_id', 'evidence_id'],
      [Prop('integer', 'Hypothesis id'), Prop('integer', 'Evidence id from get_hypothesis')],
      ['hypothesis_id', 'evidence_id']),
    HandleRemoveEvidence, tscProjectScoped);

  Registry.Register('submit_conclusion',
    'Submit the conclusion of an Approved hypothesis for human review: the ' +
    'conclusion (markdown, may reference [[item:N]]) and the outcome. Refused ' +
    'without at least one cited piece of evidence. The node is then locked ' +
    'until a human accepts it or returns it. Each change bumps the hypothesis ' +
    'version; call get_hypothesis for the current version before calling this. ' +
    APPROVAL_HINT,
    Schema(['hypothesis_id', 'version', 'conclusion', 'outcome'],
      [Prop('integer', 'Hypothesis id'), Prop('integer', 'Version from get_hypothesis'),
       Prop('string', 'Conclusion (markdown)'),
       PropEnum('Supported, Refuted or Inconclusive', HypothesisOutcomeNames)],
      ['hypothesis_id', 'version', 'conclusion', 'outcome']),
    HandleSubmitConclusion, tscProjectScoped);

  Registry.Register('abandon_hypothesis',
    'Abandon your own Approved hypothesis (author only through MCP; a comment is ' +
    'required). A revision is a new child hypothesis, not an edit. ' + APPROVAL_HINT,
    Schema(['hypothesis_id', 'version', 'comment'],
      [Prop('integer', 'Hypothesis id'), Prop('integer', 'Version from get_hypothesis'),
       Prop('string', Format('Why it is abandoned (max %d characters)', [MAX_HYP_COMMENT]))],
      ['hypothesis_id', 'version', 'comment']),
    HandleAbandonHypothesis, tscProjectScoped);
end;

end.
