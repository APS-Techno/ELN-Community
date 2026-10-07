unit unit_FileLocator;

{
  Pure candidate matching for the repair_files storage hunt.

  When a file's bytes are not at the path the database implies, they may still
  be on storage under a stale name: the item was renamed before renames
  relocated their files, or moved between projects without the files following.
  Both cases leave the TITLE on disk wrong and the ID intact, because every
  stored name is built id-first:

    project folder  Format('[%.*d]%s', [5, Id, Title])   unit_ProjectModel:138
    item folder     Format('[%.*d]%s', [4, Id, Title])   unit_Item:374
    file name       Format('[%.*d]%s%s', [4, Id, ...])   unit_Item:427

  So the hunt matches on the bracketed id token and ignores the title entirely.
  The closing bracket is load-bearing: it is what stops file 40 from claiming
  file 40123's bytes.

  No I/O here. The caller supplies names it listed from storage; this unit only
  decides which of them belong to a given id, and refuses to choose when more
  than one does.
}

interface

type
  { Outcome of narrowing a list of candidate names down to one.
      loNotFound   - nothing on storage carries this id
      loFound      - exactly one candidate; safe to act on
      loAmbiguous  - several candidates; a repair must NOT guess }
  TLocateOutcome = (loNotFound, loFound, loAmbiguous);

function ProjectFolderToken(AProjectId: Integer): string;
function ItemFolderToken(AItemId: Integer): string;
function FileNameToken(AFileId: Integer): string;

{ Every name in ANames that begins with AToken. }
function FindNamesWithToken(const ANames: TArray<string>;
  const AToken: string): TArray<string>;

{ Narrow candidates to one. AMatch is set only for loFound; it is cleared
  otherwise, so a caller cannot act on a half-answer. }
function ResolveSingleMatch(const AMatches: TArray<string>;
  out AMatch: string): TLocateOutcome;

implementation

uses
  System.SysUtils,
  System.StrUtils;

function MakeToken(AId, ADigits: Integer): string;
begin
  // '%.*d' is a MINIMUM width, so ids wider than the pad keep every digit.
  Result := Format('[%.*d]', [ADigits, AId]);
end;

function ProjectFolderToken(AProjectId: Integer): string;
begin
  Result := MakeToken(AProjectId, 5);
end;

function ItemFolderToken(AItemId: Integer): string;
begin
  Result := MakeToken(AItemId, 4);
end;

function FileNameToken(AFileId: Integer): string;
begin
  Result := MakeToken(AFileId, 4);
end;

function FindNamesWithToken(const ANames: TArray<string>;
  const AToken: string): TArray<string>;
var
  S: string;
  N: Integer;
begin
  // Fail closed: StartsStr('', X) is True for every X, so an empty token would
  // otherwise claim the whole listing and the repair would act on a name
  // chosen at random. A caller with no token has nothing to look for.
  if AToken = '' then
    Exit(nil);

  SetLength(Result, Length(ANames));
  N := 0;
  for S in ANames do
    if StartsStr(AToken, S) then
    begin
      Result[N] := S;
      Inc(N);
    end;
  SetLength(Result, N);
end;

function ResolveSingleMatch(const AMatches: TArray<string>;
  out AMatch: string): TLocateOutcome;
begin
  AMatch := '';
  case Length(AMatches) of
    0: Result := loNotFound;
    1:
      begin
        AMatch := AMatches[0];
        Result := loFound;
      end;
  else
    Result := loAmbiguous;
  end;
end;

end.
