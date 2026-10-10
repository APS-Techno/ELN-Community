unit unit_FileLocator;

{ Stored names begin with a bracketed ID, which remains stable after title
  changes or moves. Match the complete token, including its closing bracket,
  so ID 40 cannot claim ID 40123. Multiple candidates must never be guessed. }

interface

type
  { Multiple candidates are ambiguous; repair must not guess. }
  TLocateOutcome = (loNotFound, loFound, loAmbiguous);

function ProjectFolderToken(AProjectId: Integer): string;
function ItemFolderToken(AItemId: Integer): string;
function FileNameToken(AFileId: Int64): string;

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

function MakeToken(AId: Int64; ADigits: Integer): string;
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

function FileNameToken(AFileId: Int64): string;
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
