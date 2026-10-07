{*
  unit_TimeHelper.pas — UTC timestamp helpers.

  All persistent TDateTime fields (Created/Modified/Deleted/Signed/Timestamp/…)
  are stored as UTC. Callers use UTCNow on writes and FromUTC on reads for
  display. The boundary rule is:

    WRITE:   Field := UTCNow;
    READ:    DisplayStr := FormatDateTime(..., FromUTC(Field));
    FILTER:  WhereField >= UTCNow - 30;           // comparisons in UTC space

  Why UTC: multi-user / multi-timezone MySQL deployments need monotonic,
  timezone-independent ordering for audit log entries, signatures, and
  modified-date sorts. A local-time write from New York and London at 10:00
  would collide; UTC avoids that.

  MySQL session: ConnectionModule sets `SET time_zone = '+00:00'` on connect
  so any server-side CURRENT_TIMESTAMP defaults also produce UTC.

  Existing rows: a one-shot migration is required on any database that was
  written to before this change. See Docs/MIGRATIONS.md or run:

    UPDATE <table> SET <col> = DATETIME(<col>, '<+HH:MM>');   -- SQLite
    UPDATE <table> SET <col> = CONVERT_TZ(<col>, '<tz>', 'UTC'); -- MySQL
*}
unit unit_TimeHelper;

interface

uses
  System.SysUtils, System.DateUtils;

/// Current wall-clock time in UTC. Replacement for Delphi's Now.
function UTCNow: TDateTime;

/// Convert a stored UTC timestamp to local time for display.
function FromUTC(const AUtc: TDateTime): TDateTime;

/// Convert a local TDateTime to UTC (rarely needed — use UTCNow for fresh
/// timestamps; this is only for converting user-entered local values).
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
