unit unit_AuditHelper;

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_AuditLog;

/// ADescription longer than the 500-char column is cut here, never by the
/// callers, and never through a surrogate pair.
procedure RecordAudit(AManager: TObjectManager; AEntityType: TAuditEntityType;
  AEntityId: Int64; AOperation: TAuditOperation; AUserId: Integer;
  const ADescription: string);

implementation

uses
  System.SysUtils,
  unit_TimeHelper;

procedure RecordAudit(AManager: TObjectManager; AEntityType: TAuditEntityType;
  AEntityId: Int64; AOperation: TAuditOperation; AUserId: Integer;
  const ADescription: string);
const
  MAX_DESCRIPTION = 500;   // TAuditLog.Description column length
var
  Entry: TAuditLog;
  Desc: string;
begin
  Desc := ADescription;
  if Length(Desc) > MAX_DESCRIPTION then
    // A high surrogate as the last char would be stored alone (invalid UTF-16).
    if (Desc[MAX_DESCRIPTION] >= #$D800) and (Desc[MAX_DESCRIPTION] <= #$DBFF) then
      SetLength(Desc, MAX_DESCRIPTION - 1)
    else
      SetLength(Desc, MAX_DESCRIPTION);
  Entry := TAuditLog.Create;
  try
    Entry.EntityType := AEntityType;
    Entry.EntityId := AEntityId;
    Entry.Operation := AOperation;
    Entry.UserId := AUserId;
    Entry.Timestamp := UTCNow;
    Entry.Description := Desc;
    AManager.Save(Entry);
    AManager.Flush;
  except
    // Evict a failed audit write so a later shared-manager Flush cannot replay it.
    // Evict can fail before Save attaches the entry; preserve the original error.
    try
      AManager.Evict(Entry);
    except
    end;
    Entry.Free;
    raise;
  end;
end;

end.
