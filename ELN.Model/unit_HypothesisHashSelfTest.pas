unit unit_HypothesisHashSelfTest;

{
  A startup self-check for the hypothesis seal hash (unit_HypothesisHash).

  test_HypothesisHash's known-answer test (DUnitX) never runs on Linux64 --
  DUnitX cannot run there -- yet Linux64 is exactly where the WebAPI computes
  the seal for real (ELN.WebAPI is deployed as a Linux Docker container).
  This unit builds the very same fixture in memory, computes the hash with
  the production function, and compares it against the known answer, so the
  running WebAPI can verify its own hash arithmetic once at startup without
  DUnitX. GET /health then reports the cached result.

  The known-answer INPUTS and the expected hash live here as the single
  source of truth; test_HypothesisHash.pas's Setup and Hash_KnownAnswer test
  use these same constants/fixture builder instead of duplicating them.

  Self-contained: RTL + the existing hypothesis domain/hash units only, so
  ELN.Model still compiles clean into the MCP server and the desktop (no
  gate-status names, casts or assignments here -- keeps test_HypothesisLinkage
  green). HypothesisHashSelfTest must never raise: the WebAPI must never
  refuse to start because of it, so any exception is caught and reported as
  a plain False.
}

interface

uses
  unit_Hypothesis,
  unit_HypothesisRun,
  unit_HypothesisEvidence,
  unit_HypothesisHash;

const
  // Same fixture as BuildHypothesisContent's known-answer test.
  HYPOTHESIS_HASH_KAT_CONTENT =
    'HYP|7|1:S|1:C|0|4:Done|' +
    'RN|1|11|1|RN|2|10|0|' +
    'EV|4|10|-|3|0:|3FF8000000000000|0:|' +
    'EV|5|10|99|-|3:abc|-|1:n|';
  // sha256(HYPOTHESIS_HASH_KAT_CONTENT as UTF-8), computed independently in Python.
  HYPOTHESIS_HASH_KAT_HASH = '514ae34be8e0bf843456af721496d429588b333524b5f075e9924c1e2c7294d9';

/// <summary>Builds the fixture objects behind HYPOTHESIS_HASH_KAT_CONTENT /
/// HYPOTHESIS_HASH_KAT_HASH: caller owns and must free AH plus every element
/// of ARuns and AEv (e.g. via a DUnitX TearDown).</summary>
procedure BuildHypothesisHashKatFixture(out AH: THypothesis;
  out ARuns: TArray<THypothesisRun>; out AEv: TArray<THypothesisEvidence>);

/// <summary>Builds the known-answer fixture, computes ComputeHypothesisHash
/// over it, compares the result against HYPOTHESIS_HASH_KAT_HASH, and frees
/// everything it created. Never raises: any exception is caught and reported
/// as False so a startup caller can log a warning instead of crashing.</summary>
function HypothesisHashSelfTest: Boolean;

implementation

uses
  System.SysUtils;

function KatRun(AId, AItemId: Integer; ARole: THypothesisRunRole): THypothesisRun;
begin
  Result := THypothesisRun.Create;
  Result.Id := AId;
  Result.ItemId := AItemId;
  Result.Role := ARole;
end;

procedure BuildHypothesisHashKatFixture(out AH: THypothesis;
  out ARuns: TArray<THypothesisRun>; out AEv: TArray<THypothesisEvidence>);
var
  E4, E5: THypothesisEvidence;
begin
  AH := THypothesis.Create;
  AH.Id := 7;
  AH.Statement := 'S';
  AH.Change := 'C';
  AH.Outcome := hoSupported;
  AH.Conclusion := 'Done';

  // Deliberately out of order: the seal must sort by Id.
  ARuns := [KatRun(2, 10, hrrRun), KatRun(1, 11, hrrReference)];

  E5 := THypothesisEvidence.Create;
  E5.Id := 5; E5.ItemId := 10; E5.FileId := Int64(99);
  E5.FileHash := 'abc'; E5.Note := 'n';
  E4 := THypothesisEvidence.Create;
  E4.Id := 4; E4.ItemId := 10; E4.ValueId := 3; E4.ValueSnapshot := 1.5;
  AEv := [E5, E4];
end;

function HypothesisHashSelfTest: Boolean;
var
  H: THypothesis;
  Runs: TArray<THypothesisRun>;
  Ev: TArray<THypothesisEvidence>;
  R: THypothesisRun;
  E: THypothesisEvidence;
begin
  H := nil;
  Runs := nil;
  Ev := nil;
  try
    try
      BuildHypothesisHashKatFixture(H, Runs, Ev);
      Result := SameText(LowerCase(ComputeHypothesisHash(H, Runs, Ev)),
        HYPOTHESIS_HASH_KAT_HASH);
    except
      Result := False;
    end;
  finally
    for R in Runs do R.Free;
    for E in Ev do E.Free;
    H.Free;
  end;
end;

end.
