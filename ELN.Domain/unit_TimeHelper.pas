{ Persistent timestamps and comparisons use UTC; convert to local time only
  for display. Server-side timestamp defaults require a UTC database session.
  Existing local-time rows require an explicit migration, not reinterpretation. }
unit unit_TimeHelper;

interface

uses
  System.SysUtils, System.DateUtils;

function UTCNow: TDateTime;

function FromUTC(const AUtc: TDateTime): TDateTime;

// Use for user-entered local times; use UTCNow for new timestamps.
function ToUTC(const ALocal: TDateTime): TDateTime;

implementation

function UTCNow: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function FromUTC(const AUtc: TDateTime): TDateTime;
begin
  if AUtc = 0 then
    Result := 0
  else
    Result := TTimeZone.Local.ToLocalTime(AUtc);
end;

function ToUTC(const ALocal: TDateTime): TDateTime;
begin
  if ALocal = 0 then
    Result := 0
  else
    Result := TTimeZone.Local.ToUniversalTime(ALocal);
end;

end.
