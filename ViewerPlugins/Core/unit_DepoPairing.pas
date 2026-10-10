unit unit_DepoPairing;

{ Finalized runs name their TSV in outcome.dataFile. Aborted runs can lack
  outcome, so only those use the filename-timestamp fallback. Attachment ID
  prefixes are not part of the instrument filename. }

interface

uses
  System.SysUtils, System.Classes;

const
  PairToleranceSec = 5;

function IsDepoJsonName(const FileName: string): Boolean;
function IsDepoSnapshotJson(const JsonText: string): Boolean;
function StripAttachmentIdPrefix(const FileName: string): string;
function TryParseTsvTimestamp(const FileName: string; out DT: TDateTime): Boolean;
function TryParseDepoJsonTimestamp(const FileName: string; out DT: TDateTime): Boolean;
function TryGetDataFileRef(const JsonText: string; out TsvName: string): Boolean;
function FindPairedTsv(const JsonText, JsonFileName: string;
  const CandidateNames: TArray<string>): string;
function IsJsonForTsv(const JsonText, JsonFileName, TsvFileName: string): Boolean;
procedure ExpandDepoPairs(Files: TStrings);

implementation

uses
  System.StrUtils, System.DateUtils, System.Math, System.IOUtils, System.JSON;

function StripAttachmentIdPrefix(const FileName: string): string;
var
  P, I: Integer;
begin
  Result := FileName;
  if (Result = '') or (Result[1] <> '[') then Exit;
  P := Pos(']', Result);
  if P <= 2 then Exit;
  for I := 2 to P - 1 do
    if not CharInSet(Result[I], ['0'..'9']) then Exit;
  Delete(Result, 1, P);
end;

function IsDepoJsonName(const FileName: string): Boolean;
begin
  Result := EndsText('.depo.json',
    StripAttachmentIdPrefix(ExtractFileName(FileName)));
end;

function TryParseStamp(const S: string; out DT: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, Sec: Integer;
begin
  DT := 0;
  Result := (Length(S) = 19) and
    (S[5] = '-') and (S[8] = '-') and (S[11] = '_') and
    (S[14] = '-') and (S[17] = '-') and
    TryStrToInt(Copy(S, 1, 4), Y)   and TryStrToInt(Copy(S, 6, 2), Mo) and
    TryStrToInt(Copy(S, 9, 2), D)   and TryStrToInt(Copy(S, 12, 2), H) and
    TryStrToInt(Copy(S, 15, 2), Mi) and TryStrToInt(Copy(S, 18, 2), Sec) and
    TryEncodeDateTime(Y, Mo, D, H, Mi, Sec, 0, DT);
end;

function TryParseTsvTimestamp(const FileName: string; out DT: TDateTime): Boolean;
var
  Bare: string;
begin
  DT := 0;
  Bare := StripAttachmentIdPrefix(ExtractFileName(FileName));
  Result := EndsText('.tsv', Bare) and (Length(Bare) >= 19) and
    TryParseStamp(Copy(Bare, 1, 19), DT);
end;

// Deposition_<specimen>_<YYYY-MM-DD_HH-MM-SS>.depo.json - the specimen may
// itself contain underscores, so the timestamp is the LAST 19 characters of
// the base name.
function TryParseDepoJsonTimestamp(const FileName: string; out DT: TDateTime): Boolean;
var
  Bare: string;
begin
  DT := 0;
  Bare := StripAttachmentIdPrefix(ExtractFileName(FileName));
  if not (StartsText('Deposition_', Bare) and EndsText('.depo.json', Bare)) then
    Exit(False);
  SetLength(Bare, Length(Bare) - Length('.depo.json'));
  Result := (Length(Bare) >= 11 + 19) and
    TryParseStamp(Copy(Bare, Length(Bare) - 18, 19), DT);
end;

function ParseSnapshotRoot(const JsonText: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  V := TJSONObject.ParseJSONValue(JsonText);
  if not (V is TJSONObject) then
  begin
    V.Free;
    Exit;
  end;
  if TJSONObject(V).GetValue<string>('kind', '') <> 'deposition-snapshot' then
  begin
    V.Free;
    Exit;
  end;
  Result := TJSONObject(V);
end;

function IsDepoSnapshotJson(const JsonText: string): Boolean;
var
  Root: TJSONObject;
begin
  Root := ParseSnapshotRoot(JsonText);
  Result := Assigned(Root);
  Root.Free;
end;

function TryGetDataFileRef(const JsonText: string; out TsvName: string): Boolean;
var
  Root, Outc: TJSONObject;
begin
  TsvName := '';
  Root := ParseSnapshotRoot(JsonText);
  if not Assigned(Root) then Exit(False);
  try
    Outc := Root.GetValue<TJSONObject>('outcome', nil);
    if Assigned(Outc) then
      TsvName := Outc.GetValue<string>('dataFile', '');
  finally
    Root.Free;
  end;
  Result := TsvName <> '';
end;

function FindPairedTsv(const JsonText, JsonFileName: string;
  const CandidateNames: TArray<string>): string;
var
  Ref, Cand, Best: string;
  JDt, CDt: TDateTime;
  Diff, BestDiff: Double;
begin
  Result := '';

  if TryGetDataFileRef(JsonText, Ref) then
  begin
    for Cand in CandidateNames do
      if SameText(StripAttachmentIdPrefix(ExtractFileName(Cand)), Ref) then
        Exit(Cand);
    // A recorded partner is authoritative, even when it is not available.
    Exit;
  end;

  if not TryParseDepoJsonTimestamp(JsonFileName, JDt) then Exit;
  Best := '';
  BestDiff := PairToleranceSec + 1;
  for Cand in CandidateNames do
    if TryParseTsvTimestamp(Cand, CDt) then
    begin
      Diff := Abs(SecondSpan(JDt, CDt));
      if (Diff <= PairToleranceSec) and (Diff < BestDiff) then
      begin
        Best := Cand;
        BestDiff := Diff;
      end;
    end;
  Result := Best;
end;

function IsJsonForTsv(const JsonText, JsonFileName, TsvFileName: string): Boolean;
var
  Ref: string;
  JDt, TDt: TDateTime;
begin
  if TryGetDataFileRef(JsonText, Ref) then
    Exit(SameText(StripAttachmentIdPrefix(ExtractFileName(TsvFileName)), Ref));
  Result := TryParseDepoJsonTimestamp(JsonFileName, JDt) and
    TryParseTsvTimestamp(TsvFileName, TDt) and
    (Abs(SecondSpan(JDt, TDt)) <= PairToleranceSec);
end;

procedure ExpandDepoPairs(Files: TStrings);
var
  I, J: Integer;
  JsonText, Partner: string;
  Candidates: TArray<string>;
  Dup: Boolean;
begin
  for I := Files.Count - 1 downto 0 do
  begin
    if not IsDepoJsonName(Files[I]) then Continue;
    if not FileExists(Files[I]) then Continue;
    try
      JsonText := TFile.ReadAllText(Files[I], TEncoding.UTF8);
      Candidates := TDirectory.GetFiles(ExtractFilePath(Files[I]), '*.tsv');
    except
      Continue;
    end;
    Partner := FindPairedTsv(JsonText, ExtractFileName(Files[I]), Candidates);
    if Partner = '' then Continue;
    Dup := False;
    for J := 0 to Files.Count - 1 do
      if SameText(Files[J], Partner) then
      begin
        Dup := True;
        Break;
      end;
    if not Dup then
      Files.Add(Partner);
  end;
end;

end.
