unit unit_AuditHelper;

interface

uses
  Aurelius.Engine.ObjectManager,
  unit_AuditLog;

/// ADescription longer than the 500-char column is cut here, never by the
/// callers, and never through a surrogate pair.
procedure RecordAudit(AManager: TObjectManager; AEntityType: TAuditEntityType;
  AEntityId: Integer; AOperation: TAuditOperation; AUserId: Integer;
  const ADescription: string);

implementation

uses
  System.SysUtils,
  unit_TimeHelper;

procedure RecordAudit(AManager: TObjectManager; AEntityType: TAuditEntityType;
  AEntityId: Integer; AOperation: TAuditOperation; AUserId: Integer;
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
    // A failed Save/Flush must not leave a half-saved entry in the manager's
    // identity map: the next caller's Flush would otherwise re-raise against
    // it (2026-08-10 shared-manager-poisoning incident). Evict can itself
    // raise "object not attached" when Save never got far enough to attach
    // it -- swallow that one and re-raise the original error regardless.
    try
      AManager.Evict(Entry);
    except
    end;
    Entry.Free;
    raise;
  end;
end;

end.
