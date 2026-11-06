unit unit_SearchStatusText;

interface

uses
  System.SysUtils, unit_SemanticSearchApi;

function ServerStatusText(const Status: TSemanticSearchStatus;
  const ToLocal: TFunc<TDateTime, TDateTime>; const Settings: TFormatSettings): string;

implementation

uses
  System.Math;

function Count(Value: Int64; const Settings: TFormatSettings): string;
begin
  Result := FormatFloat('#,##0', Value, Settings);
end;

function ReasonText(const Code: string): string;
begin
  if Code = 'storage_unavailable' then
    Result := 'the file storage is not reachable'
  else if Code = 'database_unavailable' then
    Result := 'the notebook database is not reachable'
  else
    Result := 'the sync failed';
end;

function ServerStatusText(const Status: TSemanticSearchStatus;
  const ToLocal: TFunc<TDateTime, TDateTime>; const Settings: TFormatSettings): string;
var
  Updated, Total: string;
  Sum: Int64;
begin
  if (Status.State = ssSyncing) and (Status.FilesTotal > 0) then
    Exit('Indexing' + #$2026 + ' reading files ' + Count(Status.FilesDone, Settings) +
      ' of ' + Count(Status.FilesTotal, Settings));
  Updated := '';
  if Status.LastSyncUtc <> 0 then
    Updated := FormatDateTime('hh:nn', ToLocal(Status.LastSyncUtc), Settings);
  Sum := Int64(Status.IndexedPassages) + Status.PendingPassages;
  if Status.LastErrorCode <> '' then
  begin
    if Updated = '' then
      Result := 'Index not updated: ' + ReasonText(Status.LastErrorCode)
    else
      Result := 'Index not updated since ' + Updated + ': ' + ReasonText(Status.LastErrorCode);
  end
  else
  begin
    if Status.IsComplete then
      Result := 'Index complete: ' + Count(Status.IndexedPassages, Settings) + ' passages'
    else if Sum = 0 then
      Result := 'Indexing' + #$2026
    else
    begin
      Total := Count(Sum, Settings);
      Result := 'Indexing' + #$2026 + ' ' +
        IntToStr(Min(99, Int64(Status.IndexedPassages) * 100 div Sum)) + ' % (' +
        Count(Status.IndexedPassages, Settings) + ' of ' + Total + ' passages)';
    end;
    if Updated <> '' then
      Result := Result + ' ' + #$00B7 + ' updated ' + Updated;
  end;
  if Status.FilesSkipped > 0 then
    Result := Result + ' ' + #$00B7 + ' ' + IntToStr(Status.FilesSkipped) + ' files skipped';
end;

end.
