unit unit_HypothesisHash;

{ The seal is shared by Linux64 and Win32: hash IEEE-754 bits rather than
  locale/platform float text, and length-prefix fields so delimiters in user
  text cannot change field boundaries. }

interface

uses
  unit_Hypothesis,
  unit_HypothesisRun,
  unit_HypothesisEvidence;

function BuildHypothesisContent(H: THypothesis;
  const ARuns: TArray<THypothesisRun>;
  const AEvidence: TArray<THypothesisEvidence>): string;
function ComputeHypothesisHash(H: THypothesis;
  const ARuns: TArray<THypothesisRun>;
  const AEvidence: TArray<THypothesisEvidence>): string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Hash,
  System.Generics.Collections,
  System.Generics.Defaults;

function L(const S: string): string;
begin
  Result := IntToStr(Length(S)) + ':' + S;
end;

function DoubleBits(const V: Double): string;
var
  Bits: Int64;
begin
  Move(V, Bits, SizeOf(Bits));
  Result := IntToHex(Bits, 16);
end;

function BuildHypothesisContent(H: THypothesis;
  const ARuns: TArray<THypothesisRun>;
  const AEvidence: TArray<THypothesisEvidence>): string;
var
  Runs: TArray<THypothesisRun>;
  Ev: TArray<THypothesisEvidence>;
  R: THypothesisRun;
  E: THypothesisEvidence;
  SB: TStringBuilder;
  OutcomeStr: string;
begin
  Runs := Copy(ARuns);
  Ev := Copy(AEvidence);
  TArray.Sort<THypothesisRun>(Runs, TComparer<THypothesisRun>.Construct(
    function(const A, B: THypothesisRun): Integer
    begin
      Result := CompareValue(A.Id, B.Id);
    end));
  TArray.Sort<THypothesisEvidence>(Ev, TComparer<THypothesisEvidence>.Construct(
    function(const A, B: THypothesisEvidence): Integer
    begin
      Result := CompareValue(A.Id, B.Id);
    end));

  if H.Outcome.HasValue then
    OutcomeStr := IntToStr(Ord(H.Outcome.Value))
  else
    OutcomeStr := '-';

  SB := TStringBuilder.Create;
  try
    SB.Append('HYP|').Append(IntToStr(H.Id)).Append('|')
      .Append(L(H.Statement)).Append('|')
      .Append(L(H.Change)).Append('|')
      .Append(OutcomeStr).Append('|')
      .Append(L(H.Conclusion)).Append('|');
    for R in Runs do
      SB.Append('RN|').Append(IntToStr(R.Id)).Append('|')
        .Append(IntToStr(R.ItemId)).Append('|')
        .Append(IntToStr(Ord(R.Role))).Append('|');
    for E in Ev do
    begin
      SB.Append('EV|').Append(IntToStr(E.Id)).Append('|')
        .Append(IntToStr(E.ItemId)).Append('|');
      if E.FileId.HasValue then SB.Append(IntToStr(E.FileId.Value)) else SB.Append('-');
      SB.Append('|');
      if E.ValueId.HasValue then SB.Append(IntToStr(E.ValueId.Value)) else SB.Append('-');
      SB.Append('|').Append(L(E.FileHash)).Append('|');
      if E.ValueSnapshot.HasValue then SB.Append(DoubleBits(E.ValueSnapshot.Value)) else SB.Append('-');
      SB.Append('|').Append(L(E.Note)).Append('|');
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function ComputeHypothesisHash(H: THypothesis;
  const ARuns: TArray<THypothesisRun>;
  const AEvidence: TArray<THypothesisEvidence>): string;
begin
  Result := LowerCase(THashSHA2.GetHashString(
    BuildHypothesisContent(H, ARuns, AEvidence)));
end;

end.
