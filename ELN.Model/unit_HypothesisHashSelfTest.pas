unit unit_HypothesisHashSelfTest;

{ Linux64 cannot run DUnitX, but computes the production seal. Share this
  known-answer fixture with the test suite to check platform arithmetic.
  Failure must return False rather than prevent the host from starting. }

interface

uses
  unit_Hypothesis,
  unit_HypothesisRun,
  unit_HypothesisEvidence,
  unit_HypothesisHash;

const
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
