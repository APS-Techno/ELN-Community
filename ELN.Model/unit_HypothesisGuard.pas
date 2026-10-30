unit unit_HypothesisGuard;

{ Deleting cited items in review or accepted would change the evidence
  a human is asked to accept, or has already accepted. }

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_Hypothesis;

function IsItemCitedByLockedHypothesis(Manager: TObjectManager; ItemId: Integer;
  out AHypothesisId: Integer; out AStatus: THypothesisStatus): Boolean;

function IsFileCitedByLockedHypothesis(Manager: TObjectManager; FileId: Int64;
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
  // Find queries uncached IDs already; only cached instances need Refresh.
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

function IsFileCitedByLockedHypothesis(Manager: TObjectManager; FileId: Int64;
  out AHypothesisId: Integer; out AStatus: THypothesisStatus): Boolean;
var
  Ev: TList<THypothesisEvidence>;
  E: THypothesisEvidence;
begin
  AHypothesisId := 0;
  AStatus := hsProposed;
  Ev := Manager.Find<THypothesisEvidence>.Where(Linq['FileId'] = FileId).List;
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
