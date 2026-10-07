unit unit_HypothesisGuard;

{ Is this item cited (as a run or as evidence) by a hypothesis that is In
  review or Accepted? Such items cannot be deleted (spec 6.5): the approver
  is being asked to accept exactly that evidence, or already has. A READ;
  safe for every client. }

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_Hypothesis;

function IsItemCitedByLockedHypothesis(Manager: TObjectManager; ItemId: Integer;
  out AHypothesisId: Integer; out AStatus: THypothesisStatus): Boolean;

implementation

uses
  System.Generics.Collections,
  Aurelius.Criteria.Linq,
  unit_HypothesisRun,
  unit_HypothesisEvidence,
  unit_HypothesisRules;

function CheckOne(Manager: TObjectManager; HypId: Integer;
  var AHypothesisId: Integer; var AStatus: THypothesisStatus): Boolean;
var
  H: THypothesis;
  WasCached: Boolean;
begin
  // Same "refresh only if already cached" pattern as THypothesisModel.Load
  // (R3): Find already hit the DB for an id this manager had not seen before,
  // so a second round trip (Refresh) is only needed when the instance came
  // back from the identity map instead.
  WasCached := Manager.IsCached<THypothesis>(HypId);
  H := Manager.Find<THypothesis>(HypId);
  // The manager may be long-lived (MCP session, desktop): judge the status
  // that is committed now, not the one cached when H was first loaded.
  if WasCached and Assigned(H) then
    Manager.Refresh(H);
  Result := Assigned(H) and (H.Status in LockedStatuses);
  if Result then
  begin
    AHypothesisId := H.Id;
    AStatus := H.Status;
  end;
end;

function IsItemCitedByLockedHypothesis(Manager: TObjectManager; ItemId: Integer;
  out AHypothesisId: Integer; out AStatus: THypothesisStatus): Boolean;
var
  Runs: TList<THypothesisRun>;
  Ev: TList<THypothesisEvidence>;
  R: THypothesisRun;
  E: THypothesisEvidence;
begin
  AHypothesisId := 0;
  AStatus := hsProposed;
  Runs := Manager.Find<THypothesisRun>.Where(Linq['ItemId'] = ItemId).List;
  try
    for R in Runs do
      if CheckOne(Manager, R.HypothesisId, AHypothesisId, AStatus) then
        Exit(True);
  finally
    Runs.Free;
  end;
  Ev := Manager.Find<THypothesisEvidence>.Where(Linq['ItemId'] = ItemId).List;
  try
    for E in Ev do
      if CheckOne(Manager, E.HypothesisId, AHypothesisId, AStatus) then
        Exit(True);
  finally
    Ev.Free;
  end;
  Result := False;
end;

end.
